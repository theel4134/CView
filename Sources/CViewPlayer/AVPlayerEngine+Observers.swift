// MARK: - AVPlayerEngine+Observers.swift
// CViewPlayer - KVO / Notification / 주기 메트릭
//
// 설계 원칙
//   - 모든 옵저버는 ObserverBag에 등록 → removeItemScoped() / removeAll()로 일괄 해제
//   - 콜백 내부에서 상태 전이는 `transition(to:)`로 중복 발행 억제
//   - AccessLog 이벤트 수가 폭증할 수 있으므로 500개 단위 경고 로깅

import Foundation
import AVFoundation
import CViewCore

// MARK: - Player-Level Observers (once at init)

extension AVPlayerEngine {

    /// init에서 한 번만 호출되는 player 단위 옵저버. ObserverBag.removeAll()에서 해제.
    internal func setupPlayerObservers() {
        // timeControlStatus KVO — 재생/일시정지/버퍼링 반영
        let tco = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.stateLock.withLock { $0.lastProgressTime = Date() }
                self.transition(to: .playing)
            case .paused:
                let current = self.currentPhase
                if current == .loading || current == .idle { return }
                self.transition(to: .paused)
            case .waitingToPlayAtSpecifiedRate:
                self.transition(to: .buffering(progress: 0))
            @unknown default:
                return
            }
        }
        observers.addKVO(tco)

        // 주기 시간 콜백 — 2초마다 UI 업데이트 (백그라운드 세션 건너뜀)
        let interval = CMTime(seconds: 2.0, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self else { return }
            if self.isBackgroundMode { return }
            let cur = CMTimeGetSeconds(time)
            guard cur.isFinite else { return }
            self.stateLock.withLock { $0.lastProgressTime = Date() }
            let dur = self.duration
            if let cb = self.onTimeChange {
                Task { @MainActor in cb(cur, dur) }
            }
        }
        observers.addTimeObserver(token, on: player)
    }
}

// MARK: - Item-Scoped Observers (per play())

extension AVPlayerEngine {

    /// play() 시점에 AVPlayerItem 단위 옵저버를 등록.
    /// 기존 item-scoped 옵저버는 호출자에서 `observers.removeItemScoped()`로 먼저 해제됨.
    internal func attachItemObservers(_ item: AVPlayerItem) {

        // status KVO — readyToPlay / failed 처리
        let statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.handleItemReadyToPlay(item)
            case .failed:
                self.handleItemFailed(item)
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        observers.addKVO(statusObs)

        // isPlaybackLikelyToKeepUp — 버퍼 회복 시 자동 재개
        let keepUpObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackLikelyToKeepUp else { return }
            let phase = self.currentPhase
            if case .buffering = phase {
                self.transition(to: .playing)
                Task { @MainActor [weak self] in self?.player.play() }
            }
        }
        observers.addKVO(keepUpObs)

        // isPlaybackBufferFull — 워치독 진행 타임스탬프 갱신
        let fullObs = item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackBufferFull else { return }
            self.stateLock.withLock { $0.lastProgressTime = Date() }
        }
        observers.addKVO(fullObs)

        // Notification: 스톨
        let stallToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackStalled()
        }
        observers.addNotification(stallToken)

        // Notification: VOD 종료
        let endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            self?.transition(to: .ended)
        }
        observers.addNotification(endToken)

        // Notification: AccessLog (비트레이트 / 드롭 프레임)
        let accessToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item, queue: .main
        ) { [weak self] _ in
            self?.handleAccessLogEntry()
        }
        observers.addNotification(accessToken)
    }

    // MARK: - readyToPlay / failed 처리

    private func handleItemReadyToPlay(_ item: AVPlayerItem) {
        let wasPlaying = stateLock.withLock { $0.phase == .playing }
        guard !wasPlaying else { return }
        transition(to: .playing)
        logger.info("AVPlayerEngine: readyToPlay")

        // 라이브: 라이브 엣지 근처로 즉시 seek + 스톨 워치독 기동
        if stateLock.withLock({ $0.isLiveStream }) {
            if let range = item.seekableTimeRanges.last?.timeRangeValue {
                let liveEdge = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                if liveEdge.isFinite && liveEdge > 0 {
                    let cfg = catchupConfig
                    let target = max(0, liveEdge - cfg.targetLatency)
                    logger.info("AVPlayerEngine: seek to live edge −\(String(format: "%.1f", cfg.targetLatency))s (\(String(format: "%.1f", target))s)")
                    player.seek(
                        to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: CMTime(seconds: 1.0, preferredTimescale: 600),
                        toleranceAfter: .zero
                    )
                }
            }
            startStallWatchdog()
        }
    }

    private func handleItemFailed(_ item: AVPlayerItem) {
        if let entry = item.errorLog()?.events.last {
            logger.error("AVPlayerEngine: item failed uri=\(entry.uri ?? "-") status=\(entry.errorStatusCode)")
        }
        let err: PlayerError = item.error.map { AVPlayerErrorClassifier.classify($0) } ?? .engineInitFailed
        handleError(err)
        logger.error("AVPlayerEngine: item failed — \(item.error?.localizedDescription ?? "?")")
    }

    // MARK: - Stall 복구 시도

    /// `.AVPlayerItemPlaybackStalled` 알림 처리.
    /// 단기 스톨은 이 경로에서 2초+지터 후 자동 재개 시도하고,
    /// 장기 스톨은 StallWatchdog이 재연결 요청을 발행한다. (이중 감지 방지: 이 경로에서는 재연결 X)
    private func handlePlaybackStalled() {
        logger.warning("AVPlayerEngine: AVPlayerItemPlaybackStalled")
        transition(to: .buffering(progress: 0))

        // 0~400ms 지터 — 멀티라이브 동시 스톨 시 재요청 스파이크 완화
        let jitterNs = UInt64.random(in: 0...400_000_000)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000 + jitterNs)
            guard let self else { return }
            let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false
            if keepUp && self.player.timeControlStatus != .playing {
                self.logger.info("AVPlayerEngine: stall self-recovery — resume play")
                await MainActor.run { self.player.play() }
                self.stateLock.withLock { $0.lastProgressTime = Date() }
            }
        }
    }

    // MARK: - AccessLog 처리

    private func handleAccessLogEntry() {
        guard let log = player.currentItem?.accessLog(),
              let entry = log.events.last else { return }

        stateLock.withLock { state in
            if entry.indicatedBitrate > 0 {
                state.indicatedBitrate = entry.indicatedBitrate
            }
            let newDropped = entry.numberOfDroppedVideoFrames
            if newDropped > state.droppedFrames {
                let diff = newDropped - state.droppedFrames
                state.droppedFrames = newDropped
                if diff > 5 {
                    self.logger.warning(
                        "AVPlayerEngine: \(diff) frames dropped (total=\(newDropped)) bitrate=\(Int(entry.indicatedBitrate / 1000))kbps"
                    )
                }
            }
        }

        // 이벤트 누적 경고 (AVPlayerItem은 자체 정리 불가)
        let eventCount = log.events.count
        if eventCount > 500 && eventCount % 100 == 0 {
            logger.warning("AVPlayerEngine: AccessLog events=\(eventCount) (memory concern)")
        }
    }
}

// MARK: - Periodic Metrics Collection

extension AVPlayerEngine {

    /// 10초 주기로 `AVPlayerLiveMetrics` 스냅샷을 구성해 `onAVMetrics` 발행.
    internal func startMetricsCollection() {
        stateLock.withLock { $0.previousDroppedFrames = 0 }

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let snapshot = await self.makeMetricsSnapshot()
                if let cb = self.onAVMetrics {
                    Task { @MainActor in cb(snapshot) }
                }
            }
        }
        tasks.set(AVPlayerTaskBag.kMetricsCollector, task)
    }

    /// 현재 시점 메트릭 스냅샷. AVPlayerItem 트랙 접근이 있으므로 MainActor에서 실행.
    @MainActor
    private func makeMetricsSnapshot() -> AVPlayerLiveMetrics {
        let item = player.currentItem

        // 해상도 (비디오 트랙 naturalSize)
        let resolution: String? = {
            guard let item else { return nil }
            for track in item.tracks {
                if track.assetTrack?.mediaType == .video,
                   let size = track.assetTrack?.naturalSize,
                   size.width > 0, size.height > 0 {
                    return "\(Int(size.width))x\(Int(size.height))"
                }
            }
            return nil
        }()

        // 버퍼 건강도
        let bufferHealth: Double = {
            guard let item else { return 0.0 }
            if item.isPlaybackLikelyToKeepUp { return 1.0 }
            if item.isPlaybackBufferFull { return 0.8 }
            if item.isPlaybackBufferEmpty { return 0.0 }
            return 0.5
        }()

        // 상태에서 스냅샷 추출 + 이전 드롭 프레임 수 갱신
        let snap = stateLock.withLock { state -> (bitrate: Double, dropped: Int, delta: Int, latency: Double) in
            let currentDropped = state.droppedFrames
            let delta = max(0, currentDropped - state.previousDroppedFrames)
            state.previousDroppedFrames = currentDropped
            return (state.indicatedBitrate, currentDropped, delta, state.measuredLatency)
        }

        return AVPlayerLiveMetrics(
            indicatedBitrate: snap.bitrate,
            droppedFrames: snap.dropped,
            droppedFramesDelta: snap.delta,
            measuredLatency: snap.latency,
            resolution: resolution,
            playbackRate: player.rate,
            bufferHealth: bufferHealth
        )
    }
}
