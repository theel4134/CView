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

        // 라이브: 라이브 엣지로 보정 후 반드시 재생을 재개한다.
        // 기존 구현은 seek 후 play()를 다시 호출하지 않아 멀티라이브에서
        // 첫 프레임만 보이고 화면이 멈춘 듯한 정지 현상이 발생할 수 있었다.
        if stateLock.withLock({ $0.isLiveStream }) {
            let desiredRate = max(0.01, stateLock.withLock { $0.rate })
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
                    ) { [weak self] _ in
                        guard let self else { return }
                        self.player.playImmediately(atRate: desiredRate)
                        self.stateLock.withLock { $0.lastProgressTime = Date() }
                    }
                } else {
                    player.playImmediately(atRate: desiredRate)
                }
            } else {
                player.playImmediately(atRate: desiredRate)
            }
            startStallWatchdog()
            startHQRecoveryWatchdog()
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

        if let statusCode = player.currentItem?.errorLog()?.events.last?.errorStatusCode,
           [401, 403, 404, 410, 500, 502, 503, 504].contains(Int(statusCode)) {
            logger.warning("AVPlayerEngine: stall with HTTP \(statusCode) → reconnect")
            handleError(.connectionLost)
            return
        }

        let jitterNs = UInt64.random(in: 0...400_000_000)
        let recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000 + jitterNs)
            guard let self, !Task.isCancelled else { return }

            let before = CMTimeGetSeconds(self.player.currentTime())
            let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false

            if keepUp && self.player.timeControlStatus != .playing {
                self.logger.info("AVPlayerEngine: stall self-recovery — resume play")
                await MainActor.run { self.player.play() }
                self.stateLock.withLock { $0.lastProgressTime = Date() }
                return
            }

            await MainActor.run {
                if self.stateLock.withLock({ $0.isLiveStream }) {
                    self.seekToLiveEdgeForRecovery(reason: "stall")
                } else {
                    self.player.play()
                }
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }

            let after = CMTimeGetSeconds(self.player.currentTime())
            let progressed = before.isFinite && after.isFinite && (after - before) > 0.25
            if progressed {
                self.stateLock.withLock { $0.lastProgressTime = Date() }
            } else {
                self.logger.warning("AVPlayerEngine: stall recovery made no progress → reconnect")
                self.handleError(.connectionLost)
            }
        }
        tasks.set(AVPlayerTaskBag.kStallRecovery, recoveryTask)
    }

    // MARK: - AccessLog 처리

    private func handleAccessLogEntry() {
        guard let log = player.currentItem?.accessLog(),
              let entry = log.events.last else { return }

        // [Multi-live 튜닝] 배경(비선택/음소거) 세션은 지표 갱신/로그 워크를 모두 생략.
        // AccessLog 콜백은 세그먼트마다(~2s) 발생하므로 N=8 멀티라이브에서 주요 CPU 핫스팟.
        // HQ 복귀 워치독도 배경에서 건너뛰므로 indicatedBitrate 를 갱신할 필요가 없다.
        if isBackgroundMode { return }

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
    ///
    /// [Multi-live 튜닝]
    ///   - 배경(비선택) 세션은 interval 을 20s 로 늘리고, 스냅샷 구성/콜백을 완전히 건너뛴다.
    ///     (배경 세션의 서버 메트릭은 신뢰도가 낮고 UI 에도 노출되지 않음)
    ///   - 재생 중이 아닐 때도 스냅샷을 구성하지 않는다 — 버퍼링/오류/정지 단계 불필요한 MainActor 트립 제거.
    internal func startMetricsCollection() {
        stateLock.withLock { $0.previousDroppedFrames = 0 }

        let task = Task { [weak self] in
            while !Task.isCancelled {
                // 현재 세션 상태에 따라 polling 간격 이원화
                let bg: Bool = self?.isBackgroundMode ?? false
                let intervalNs: UInt64 = bg ? 20_000_000_000 : 10_000_000_000
                try? await Task.sleep(nanoseconds: intervalNs)
                guard let self, !Task.isCancelled else { return }

                // 배경 세션 또는 비재생 단계는 스냅샷 자체를 생성하지 않음
                if self.isBackgroundMode { continue }
                let phase = self.currentPhase
                switch phase {
                case .playing, .buffering:
                    break
                default:
                    continue
                }

                let snapshot = await self.makeMetricsSnapshot()
                if let cb = self.onAVMetrics {
                    Task { @MainActor in cb(snapshot) }
                }
            }
        }
        tasks.set(AVPlayerTaskBag.kMetricsCollector, task)
    }

    /// 현재 시점의 AVPlayer 메트릭 스냅샷을 즉시 한 번 발행.
    /// 콜백 바인딩 직후 첫 주기(10초)를 기다리지 않고 서버로 초기 데이터를 보낼 때 사용한다.
    public func emitCurrentMetricsSnapshot() {
        guard stateLock.withLock({ $0.isLiveStream }) else { return }
        guard let callback = onAVMetrics else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            callback(self.makeMetricsSnapshot())
        }
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
