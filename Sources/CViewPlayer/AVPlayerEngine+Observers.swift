// MARK: - AVPlayerEngine+Observers.swift
// CViewPlayer - KVO/Notification 옵저버 설정 및 메트릭 수집

import Foundation
import AVFoundation
import CViewCore

// MARK: - KVO & Notification Observers

extension AVPlayerEngine {

    internal func setupObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            let phase: PlayerState.Phase
            switch player.timeControlStatus {
            case .playing:
                // 재생 중 타임스탬프 갱신 (스톨 워치독용)
                self.lastProgressTime = Date()
                phase = .playing
            case .paused:
                let cur = self._avState.withLock { $0.state }
                if cur == .loading || cur == .idle { return }
                phase = .paused
            case .waitingToPlayAtSpecifiedRate:
                phase = .buffering(progress: 0)
            @unknown default:
                return
            }
            self._avState.withLock { $0.state = phase }
            self.notifyStateChange(phase)
        }

        // 2초 간격: AVPlayer 기본엔진 전환으로 CPU 절감 (4세션 기준 4→2회/초)
        let interval = CMTime(seconds: 2.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard !self.isBackgroundMode else { return }
            let cur = CMTimeGetSeconds(time)
            let dur = self.duration
            if cur.isFinite {
                self.lastProgressTime = Date()
                self.onTimeChange?(cur, dur)
            }
        }
    }

    internal func observeItemStatus(_ item: AVPlayerItem) {
        removeItemObservers()

        // ── 아이템 상태 KVO ───────────────────────────────────────────
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                let prev = self._avState.withLock { $0.state }
                guard prev != .playing else { break }
                self._avState.withLock { $0.state = .playing }
                self.notifyStateChange(.playing)
                self.logger.info("AVPlayerEngine: readyToPlay")
                // 라이브 스트림: readyToPlay 즉시 라이브 엣지 근처로 seek하여 초기 지연 최소화.
                // AVPlayer가 기본적으로 재생을 시작하는 위치는 seekableRange 시작점이므로
                // configuredTimeOffsetFromLive가 적용되기 전에 수동으로 라이브 엣지 오프셋 적용.
                if self.isLiveStream,
                   let seekRange = item.seekableTimeRanges.last?.timeRangeValue {
                    let liveEdge = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
                    if liveEdge.isFinite && liveEdge > 0 {
                        let cfg = self.catchupConfig
                        let target = max(0, liveEdge - cfg.targetLatency)
                        self.logger.info("AVPlayerEngine: readyToPlay — seeking to live edge −\(String(format: "%.1f", cfg.targetLatency))s (\(String(format: "%.1f", target))s)")
                        self.player.seek(
                            to: CMTime(seconds: target, preferredTimescale: 600),
                            toleranceBefore: CMTime(seconds: 1.0, preferredTimescale: 600),
                            toleranceAfter: .zero
                        )
                    }
                }
                // readyToPlay 직후 stall watchdog 시작:
                // play() 직후가 아니라 어이템이 실제로 준비된 시점부터 감시 시작하여
                // 8초 고정 대기 없이 즉시 흐름으로 감시 시작
                if self.isLiveStream {
                    self.startStallWatchdog()
                }

            case .failed:
                // ErrorLog에서 세부 원인 추출 코드 포함
                if let errLog = item.errorLog()?.events.last {
                    self.logger.error(
                        "AVPlayerEngine: item failed uri=\(errLog.uri ?? "-") statusCode=\(errLog.errorStatusCode)"
                    )
                }
                let err = item.error.map { self.classifyError($0) } ?? .engineInitFailed
                self._avState.withLock { $0.state = .error(err) }
                self.notifyStateChange(.error(err))
                self.logger.error("AVPlayerEngine: item failed — \(item.error?.localizedDescription ?? "?")")

            case .unknown:
                break
            @unknown default:
                break
            }
        }

        // ── 버퍼 fullness KVO — 재생 가능성 변화 확인 ────────────────
        bufferKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.isPlaybackLikelyToKeepUp {
                // 버퍼 회복 → 일시정지 상태에서 자동 재개
                let phase = self._avState.withLock { $0.state }
                if case .buffering = phase {
                    self._avState.withLock { $0.state = .playing }
                    self.notifyStateChange(.playing)
                    Task { @MainActor [weak self] in
                        self?.player.play()
                    }
                }
            }
        }
        bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackBufferFull else { return }
            // 버퍼 완전 충전 → 스톨 타임스탬프 갱신 (워치독 리셋)
            self.lastProgressTime = Date()
        }

        // ── Notification: 스톨 / 종료 / AccessLog ──────────────────────
        stallObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logger.warning("AVPlayerEngine: playback stalled")
            self._avState.withLock { $0.state = .buffering(progress: 0) }
            self.notifyStateChange(.buffering(progress: 0))
            // 스톨 복구: 2초 후 자동 play() 재시도
            // AVPlayer는 버퍼가 충분히 쌓이면 자동 재개하지 않는 경우가 있음
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false
                if keepUp && self.player.timeControlStatus != .playing {
                    self.logger.info("AVPlayerEngine: stall recovery — buffer ready, resuming play")
                    self.player.play()
                    self.lastProgressTime = Date()
                }
            }
        }

        bufferObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self._avState.withLock { $0.state = .ended }
            self.notifyStateChange(.ended)
        }

        // AccessLog: 드롭 프레임, 비트레이트, 스트리밍 정보 모니터링
        // + 주기적 AccessLog 정리 — 장시간 재생 시 이벤트 무한 축적 방지
        accessLogObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  let log = self.player.currentItem?.accessLog(),
                  let entry = log.events.last else { return }

            if entry.indicatedBitrate > 0 {
                self.indicatedBitrate = entry.indicatedBitrate
            }
            let newDropped = entry.numberOfDroppedVideoFrames
            if newDropped > self.droppedFrames {
                let diff = newDropped - self.droppedFrames
                self.droppedFrames = newDropped
                if diff > 5 {
                    self.logger.warning(
                        "AVPlayerEngine: \(diff) frames dropped (total=\(newDropped)) bitrate=\(Int(entry.indicatedBitrate / 1000))kbps"
                    )
                }
            }
            
            // AccessLog 이벤트 수가 과다하면 경고 (AVPlayerItem은 자체 정리 불가)
            // 10분 이상 재생 시 수백 개의 이벤트가 쌓일 수 있음
            let eventCount = log.events.count
            if eventCount > 500 && eventCount % 100 == 0 {
                self.logger.warning(
                    "AVPlayerEngine: AccessLog events accumulating: \(eventCount) entries (memory concern for long playback)"
                )
            }
        }
    }

    internal func removeItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferKeepUpObservation?.invalidate()
        bufferKeepUpObservation = nil
        bufferFullObservation?.invalidate()
        bufferFullObservation = nil
        for obs in [stallObservation, bufferObservation, accessLogObservation, liveOffsetObservation].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
        stallObservation = nil
        bufferObservation = nil
        accessLogObservation = nil
        liveOffsetObservation = nil
    }

    internal func removeObservers() {
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        removeItemObservers()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Metrics Collection (AVPlayer → MetricsForwarder)

    /// 10초 주기로 현재 AVPlayer 재생 메트릭을 수집하여 onAVMetrics 콜백으로 전달
    internal func startMetricsCollection() {
        metricsCollectionTask?.cancel()
        previousDroppedFrames = 0

        metricsCollectionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10초
                guard !Task.isCancelled, let self else { return }
                let snapshot = self.collectMetricsSnapshot()
                self.onAVMetrics?(snapshot)
            }
        }
    }

    /// 현재 시점의 메트릭 스냅샷 수집
    internal func collectMetricsSnapshot() -> AVPlayerLiveMetrics {
        let currentDropped = self.droppedFrames
        let delta = max(0, currentDropped - self.previousDroppedFrames)
        self.previousDroppedFrames = currentDropped

        // 해상도: 현재 재생 중인 비디오 트랙의 naturalSize
        let resolution: String? = {
            guard let item = self.player.currentItem else { return nil }
            for track in item.tracks {
                if track.assetTrack?.mediaType == .video {
                    let size = track.assetTrack?.naturalSize ?? .zero
                    if size.width > 0 && size.height > 0 {
                        return "\(Int(size.width))x\(Int(size.height))"
                    }
                }
            }
            return nil
        }()

        // 버퍼 건강도: isPlaybackLikelyToKeepUp 기반
        let bufferHealth: Double = {
            guard let item = self.player.currentItem else { return 0.0 }
            if item.isPlaybackLikelyToKeepUp { return 1.0 }
            if item.isPlaybackBufferFull { return 0.8 }
            if item.isPlaybackBufferEmpty { return 0.0 }
            return 0.5
        }()

        return AVPlayerLiveMetrics(
            indicatedBitrate: self.indicatedBitrate,
            droppedFrames: currentDropped,
            droppedFramesDelta: delta,
            measuredLatency: self.measuredLatency,
            resolution: resolution,
            playbackRate: self.player.rate,
            bufferHealth: bufferHealth
        )
    }
}
