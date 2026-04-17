// MARK: - AVPlayerEngine.swift
// CViewPlayer - AVPlayer 기반 재생 엔진 (v2 재설계)
//
// 설계 개요
//   - 모든 가변 상태를 `Mutex<State>`에 단일 집계
//   - 옵저버/Task는 각각 ObserverBag / TaskBag에서 일괄 관리 → 누수 차단
//   - 스톨 감지는 StallWatchdog(+LiveStream) 단일 경로로 통합
//   - 네트워크 모니터는 전역 싱글톤 공유 (멀티라이브 N개 세션에서 N개 → 1개)
//   - 에러 분류는 AVPlayerErrorClassifier 순수 함수로 분리
//
// 파일 분할
//   - AVPlayerEngine.swift              ← 본 파일: 프로토콜 구현, 재생 파이프라인
//   - AVPlayerEngine+Lifecycle.swift    ← ObserverBag / TaskBag
//   - AVPlayerEngine+Errors.swift       ← 에러 분류기 + URL 판정
//   - AVPlayerEngine+LiveStream.swift   ← 라이브 캐치업 + 스톨 워치독
//   - AVPlayerEngine+Observers.swift    ← KVO / Notification / 메트릭 수집
//   - AVPlayerLayerView.swift           ← Metal Zero-Copy 렌더링 NSView
//   - AVPlayerNetworkMonitor.swift      ← 공유 NWPathMonitor 싱글톤

import Foundation
import AVFoundation
import AppKit
import QuartzCore
import Synchronization
import CViewCore

// MARK: - AVPlayerEngine

/// AVPlayer 기반 라이브/VOD 재생 엔진. `PlayerEngineProtocol` 구현체.
///
/// 외부 공개 API(호환성 보장):
///   - `play(url:)` `pause()` `resume()` `stop()` `seek(to:)` `setRate(_:)` `setVolume(_:)`
///   - `startRecording(to:)` `stopRecording()` `resetForReuse()`
///   - 속성: `player`, `videoView`, `isPlaying`, `rate`, `currentTime`, `duration`,
///           `isRecording`, `isInErrorState`, `isBackgroundMode`, `catchupConfig`, `currentPhase`
///   - 콜백: `onStateChange`, `onTimeChange`, `onLatencyChange`, `onReconnectRequested`, `onAVMetrics`
///   - `setVideoLayerVisible(_:)`
public final class AVPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {

    // MARK: - Internal State (단일 Mutex로 모든 가변 상태 집계)

    internal struct State: Sendable {
        // 재생 상태
        var phase: PlayerState.Phase = .idle
        var rate: Float = 1.0
        var volume: Float = 1.0
        var currentURL: URL? = nil
        var isLiveStream: Bool = false
        var lastProgressTime: Date = .init()

        // 라이브 캐치업 — 기본값은 .balanced (7s 버퍼). VLC 수준의 안정성 확보.
        // .lowLatency(3s 버퍼)는 chzzk 2s 세그먼트 환경에서 지터 한 번에 스톨 유발.
        var catchupConfig: AVLiveCatchupConfig = .balanced
        var networkType: AVPlayerNetworkMonitor.InterfaceType = .other

        // 녹화
        var isRecording: Bool = false
        var recordingURL: URL? = nil

        // 백그라운드(비활성 멀티라이브 세션)
        var isBackgroundMode: Bool = false

        // [Quality Lock] 자동 화질 저하 방지 — 항상 lockedResolution / lockedPeakBitRate 유지.
        // 기본 true: 백그라운드 다운시프트도 무시하고 1080p60 / 8Mbps 고정.
        var isQualityLocked: Bool = true
        var lockedPeakBitRate: Double = 8_000_000            // 8000kbps
        var lockedMaximumResolution: CGSize = CGSize(width: 1920, height: 1080)

        // 선명한 화면(픽셀 샤프 스케일링) 상태 — 새 NSView/PiP 생성 시 재적용용
        var sharpPixelScalingEnabled: Bool = false

        // 메트릭 스냅샷 (AccessLog + Catchup 공유)
        var indicatedBitrate: Double = 0
        var droppedFrames: Int = 0
        var previousDroppedFrames: Int = 0
        var measuredLatency: Double = 0

        // 캐치업 속도 스무딩 히스토리 (최대 4개)
        var rateHistory: [Float] = []

        // 재연결 폭주 방지: 최근 5분 내 재연결 타임스탬프
        var recentReconnectTimestamps: [Date] = []
    }

    internal let stateLock = Mutex(State())

    // MARK: - Public Properties (PlayerEngineProtocol + AVPlayer 특화)

    public let player: AVPlayer

    /// 라이브 캐치업 설정. 외부에서 프리셋 변경 가능 (.ultraLow / .lowLatency / .balanced / .webSync / .stable).
    public var catchupConfig: AVLiveCatchupConfig {
        get { stateLock.withLock { $0.catchupConfig } }
        set { stateLock.withLock { $0.catchupConfig = newValue } }
    }

    /// 멀티라이브 비활성(음소거) 세션 CPU 절감 모드.
    /// - 캐치업 루프/스톨 워치독/주기 time 콜백 전파 중단
    /// - play() 시점에 480p·2Mbps·10s 버퍼로 다운시프트 (단, `isQualityLocked=true`일 때는 다운시프트 생략)
    public var isBackgroundMode: Bool {
        get { stateLock.withLock { $0.isBackgroundMode } }
        set { stateLock.withLock { $0.isBackgroundMode = newValue } }
    }

    /// 화질 자동 저하(ABR 다운시프트) 방지 플래그.
    /// `true`(기본값)이면 `lockedPeakBitRate` / `lockedMaximumResolution` 를 항상 고정 적용하며,
    /// 배경 모드/네트워크 저하 상황에서도 화질을 낮추지 않는다.
    /// 라이브 스트리밍 시 항상 1080p60 / 8Mbps 유지가 목표.
    public var isQualityLocked: Bool {
        get { stateLock.withLock { $0.isQualityLocked } }
        set {
            stateLock.withLock { $0.isQualityLocked = newValue }
            applyQualityPreferencesToCurrentItem()
        }
    }

    /// 잠금 상태에서 적용할 최대 비트레이트(bps). 기본 8_000_000 = 8Mbps.
    public var lockedPeakBitRate: Double {
        get { stateLock.withLock { $0.lockedPeakBitRate } }
        set {
            stateLock.withLock { $0.lockedPeakBitRate = max(0, newValue) }
            applyQualityPreferencesToCurrentItem()
        }
    }

    /// 잠금 상태에서 적용할 최대 해상도. 기본 1920×1080.
    public var lockedMaximumResolution: CGSize {
        get { stateLock.withLock { $0.lockedMaximumResolution } }
        set {
            stateLock.withLock { $0.lockedMaximumResolution = newValue }
            applyQualityPreferencesToCurrentItem()
        }
    }

    // MARK: - Callbacks

    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?
    public var onTimeChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?
    public var onLatencyChange: (@Sendable (Double) -> Void)?
    public var onReconnectRequested: (@Sendable () -> Void)?
    public var onAVMetrics: (@Sendable (AVPlayerLiveMetrics) -> Void)?

    // MARK: - PlayerEngineProtocol 요구사항

    public var isPlaying: Bool {
        stateLock.withLock { $0.phase == .playing }
    }

    public var isInErrorState: Bool {
        stateLock.withLock {
            if case .error = $0.phase { return true }
            return false
        }
    }

    public var currentTime: TimeInterval {
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? t : 0
    }

    public var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let d = CMTimeGetSeconds(item.duration)
        return d.isFinite ? d : 0
    }

    public var rate: Float {
        stateLock.withLock { $0.rate }
    }

    public var videoView: NSView { renderView }

    /// 현재 재생 단계 스냅샷 (UI 바인딩용)
    public var currentPhase: PlayerState.Phase {
        stateLock.withLock { $0.phase }
    }

    public var isRecording: Bool {
        stateLock.withLock { $0.isRecording }
    }

    // MARK: - Private Members

    private let renderView: AVPlayerLayerView
    internal let logger = AppLogger.player

    // 옵저버 / Task 라이프사이클 관리자
    internal let observers = AVPlayerObserverBag()
    internal let tasks = AVPlayerTaskBag()

    // 녹화 서비스
    private let recordingService = StreamRecordingService()

    // 공유 네트워크 모니터 구독 토큰
    private var networkSubscriptionId: UUID?

    // 재연결 폭주 보호 기준
    internal let maxReconnectsInWindow = 3
    internal let reconnectWindowSeconds: TimeInterval = 300 // 5분

    // MARK: - Init / Deinit

    public override init() {
        self.renderView = AVPlayerLayerView()
        self.player = AVPlayer()
        super.init()
        renderView.attach(player: player)
        subscribeNetworkMonitor()
        setupPlayerObservers()
    }

    deinit {
        if let id = networkSubscriptionId {
            AVPlayerNetworkMonitor.shared.unsubscribe(id)
        }
        tasks.cancelAll()
        observers.removeAll()
        player.pause()
    }

    // MARK: - Video Layer Visibility

    /// 비디오 출력 레이어 표시/숨김. 디코딩·오디오는 유지하되 GPU 합성 패스만 차단.
    public func setVideoLayerVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderView.playerLayer.isHidden = !visible
        CATransaction.commit()
    }

    /// 현재 선명한 화면(픽셀 샤프 스케일링) 활성 상태.
    public var sharpPixelScalingEnabled: Bool {
        stateLock.withLock { $0.sharpPixelScalingEnabled }
    }

    /// 선명한 화면(픽셀 샤프 스케일링) 설정.
    /// AVPlayerLayer 의 magnificationFilter/minificationFilter 를 .nearest 로 전환하여
    /// 업/다운스케일 시 픽셀 경계를 유지한다. (기본: .linear / .trilinear)
    public func setSharpPixelScaling(_ enabled: Bool) {
        stateLock.withLock { $0.sharpPixelScalingEnabled = enabled }
        renderView.setSharpScaling(enabled)
        logger.info("AVPlayerEngine: sharpPixelScaling = \(enabled)")
    }

    // MARK: - Playback Pipeline

    public func play(url: URL) async throws {
        // 1) 이전 재생 자원 정리
        tasks.cancel(AVPlayerTaskBag.kStallWatchdog)
        tasks.cancel(AVPlayerTaskBag.kLiveCatchup)
        tasks.cancel(AVPlayerTaskBag.kMetricsCollector)
        observers.removeItemScoped()

        // 2) 상태 초기화
        // [Smooth Switch] 이전에 라이브 재생 중이었다면 수동 화질 전환 / 재연결로 판단.
        // 이 경우 .loading 방송을 생략하고 .buffering 으로 부드럽게 전환 → UI 깜빡임/스피너 플리커 제거.
        let isLive = AVPlayerStreamDetector.isLive(url: url)
        let wasLivePlaying: Bool = stateLock.withLock { state in
            let wasActive: Bool = {
                switch state.phase {
                case .playing, .buffering:
                    return state.isLiveStream
                default:
                    return false
                }
            }()
            state.phase = wasActive && isLive ? .buffering(progress: 0) : .loading
            state.currentURL = url
            state.isLiveStream = isLive
            state.rateHistory.removeAll(keepingCapacity: true)
            state.indicatedBitrate = 0
            state.droppedFrames = 0
            state.previousDroppedFrames = 0
            state.measuredLatency = 0
            // 수동 화질 전환도 play() 재호출이므로 재연결 이력에 섞이면 "5분 내 3회" 캡을 앞당김.
            // → 항상 리셋하여 사용자 액션이 자동 복구 예산을 소진하지 않도록 분리.
            state.recentReconnectTimestamps.removeAll(keepingCapacity: true)
            state.lastProgressTime = Date()
            return wasActive
        }
        notifyStateChange(wasLivePlaying && isLive ? .buffering(progress: 0) : .loading)

        // 3) Asset / Item 구성
        let item = makePlayerItem(url: url, isLive: isLive)

        // 4) KVO / Notification 부착
        attachItemObservers(item)

        // 5) 플레이어에 장착 및 재생 시작
        player.replaceCurrentItem(with: item)
        player.rate = stateLock.withLock { $0.rate }
        player.play()

        // 6) 라이브 전용 루프 기동 (스톨 워치독은 readyToPlay 시점에 시작)
        if isLive {
            startLiveCatchupLoop()
            startMetricsCollection()
        }

        logger.info("AVPlayerEngine: play [\(isLive ? "LIVE" : "VOD")] \(url.lastPathComponent)")
    }

    public func pause() {
        player.pause()
        stateLock.withLock { $0.phase = .paused }
        notifyStateChange(.paused)
    }

    public func resume() {
        let r = stateLock.withLock { $0.rate }
        player.rate = r
        player.play()
        stateLock.withLock { $0.phase = .playing }
        notifyStateChange(.playing)
    }

    public func stop() {
        // Task → Observer → Player 순서로 정리 (역순 의존 방지)
        tasks.cancelAll()
        observers.removeItemScoped()

        player.pause()
        player.replaceCurrentItem(with: nil)

        stateLock.withLock {
            $0.phase = .idle
            $0.currentURL = nil
            $0.isLiveStream = false
        }
        notifyStateChange(.idle)
    }

    /// 엔진 풀 반납 시 사용: stop() + 콜백 해제 + 상태 리셋.
    public func resetForReuse() {
        stop()

        // 콜백 참조 전부 해제 — 이전 뷰모델이 GC되도록
        onStateChange = nil
        onTimeChange = nil
        onLatencyChange = nil
        onReconnectRequested = nil
        onAVMetrics = nil

        stateLock.withLock { state in
            state.rate = 1.0
            state.volume = 1.0
            state.isLiveStream = false
            state.isBackgroundMode = false
            state.catchupConfig = .balanced
            state.sharpPixelScalingEnabled = false
            state.lastProgressTime = Date()
            state.rateHistory.removeAll(keepingCapacity: true)
            state.indicatedBitrate = 0
            state.droppedFrames = 0
            state.previousDroppedFrames = 0
            state.measuredLatency = 0
            state.recentReconnectTimestamps.removeAll(keepingCapacity: true)
            state.isRecording = false
            state.recordingURL = nil
        }
        player.volume = 1.0
        setVideoLayerVisible(true)
    }

    public func seek(to position: TimeInterval) {
        let cm = CMTime(seconds: position, preferredTimescale: 600)
        let previous = stateLock.withLock { $0.phase }

        stateLock.withLock { $0.phase = .buffering(progress: 0) }
        notifyStateChange(.buffering(progress: 0))

        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            let restored: PlayerState.Phase = (previous == .paused) ? .paused : .playing
            self.stateLock.withLock { $0.phase = restored }
            self.notifyStateChange(restored)
            if restored == .playing { self.player.play() }
        }
    }

    public func setRate(_ newRate: Float) {
        stateLock.withLock { $0.rate = newRate }
        if player.timeControlStatus == .playing {
            player.rate = newRate
        }
    }

    public func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        player.volume = clamped
        stateLock.withLock { $0.volume = clamped }
    }

    // MARK: - Recording

    public func startRecording(to url: URL) async throws {
        let (already, currentURL) = stateLock.withLock { state -> (Bool, URL?) in
            (state.isRecording, state.currentURL)
        }
        guard !already else {
            throw PlayerError.recordingFailed("이미 녹화 중입니다")
        }
        guard let streamURL = currentURL else {
            throw PlayerError.recordingFailed("재생 중인 스트림이 없습니다")
        }

        try await recordingService.startRecording(playlistURL: streamURL, to: url)

        stateLock.withLock {
            $0.isRecording = true
            $0.recordingURL = url
        }
        logger.info("AVPlayerEngine: recording start → \(url.lastPathComponent, privacy: .public)")
    }

    public func stopRecording() async {
        guard stateLock.withLock({ $0.isRecording }) else { return }
        await recordingService.stopRecording()
        stateLock.withLock {
            $0.isRecording = false
            $0.recordingURL = nil
        }
        logger.info("AVPlayerEngine: recording stop")
    }

    // MARK: - State Transition Helper

    /// 상태를 전이시키고 콜백을 MainActor에서 발행.
    /// 동일 상태로 연속 전이 시 콜백 중복 억제.
    internal func transition(to phase: PlayerState.Phase) {
        let changed: Bool = stateLock.withLock { state in
            guard state.phase != phase else { return false }
            state.phase = phase
            return true
        }
        if changed { notifyStateChange(phase) }
    }

    /// 외부에서 상태 비교 없이 강제로 콜백 발행.
    internal func notifyStateChange(_ phase: PlayerState.Phase) {
        guard let cb = onStateChange else { return }
        Task { @MainActor in cb(phase) }
    }

    // MARK: - Error Pipeline

    /// 에러 상태 전이 + 재연결 가능 유형이면 상위에 재연결 요청 발행.
    internal func handleError(_ error: PlayerError) {
        stateLock.withLock { $0.phase = .error(error) }
        notifyStateChange(.error(error))
        if AVPlayerErrorClassifier.isRecoverable(error) {
            if let cb = onReconnectRequested {
                Task { @MainActor in cb() }
            }
        }
    }

    // MARK: - Player Item Factory

    /// AVURLAsset + AVPlayerItem 구성. 라이브/VOD 분기 최소화.
    private func makePlayerItem(url: URL, isLive: Bool) -> AVPlayerItem {
        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/vnd.apple.mpegurl, application/x-mpegURL, audio/mpegurl, */*"
        ]
        let assetOptions: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            "AVURLAssetAllowsCellularAccessKey": true,
        ]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)

        // 화질 잠금/기본 선호도 스냅샷을 단일 락 진입으로 획득
        let (qualityLocked, lockedBitrate, lockedResolution, bgMode) = stateLock.withLock { s in
            (s.isQualityLocked, s.lockedPeakBitRate, s.lockedMaximumResolution, s.isBackgroundMode)
        }

        // 기본 ABR 선호도 — 1080p 60fps / 8Mbps 고정 (자동 화질 저하 차단)
        // startsOnFirstEligibleVariant = false → AVPlayer 가 preferredPeakBitRate /
        // preferredMaximumResolution 힌트에 맞는 1080p 변종을 선택한 뒤 재생 시작.
        // (true 로 두면 네트워크 추정이 낮을 때 첫 다운로드된 저화질 변종으로 고정되어
        //  852×480 / 1.6Mbps 수준에서 재생이 잠기는 회귀가 발생한다.)
        item.startsOnFirstEligibleVariant = false
        item.preferredMaximumResolution = lockedResolution
        item.preferredPeakBitRate = lockedBitrate
        item.videoComposition = nil  // 디코더 프레임 직통 (선명도 최대)

        // 라이브 저지연 설정
        if isLive {
            player.automaticallyWaitsToMinimizeStalling = false
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            adjustCatchupConfigForNetwork()
            let cfg = catchupConfig
            item.preferredForwardBufferDuration = cfg.preferredForwardBuffer
            item.configuredTimeOffsetFromLive = CMTime(
                seconds: cfg.targetLatency,
                preferredTimescale: 1000
            )

            // 배경(비활성) 세션: 화질 잠금이 해제된 경우에만 대역폭/메모리 축소 적용.
            // 화질 잠금(기본값) 상태에서는 백그라운드에서도 1080p60/8Mbps 유지.
            if bgMode && !qualityLocked {
                item.preferredPeakBitRate = 2_000_000
                item.preferredMaximumResolution = CGSize(width: 854, height: 480)
                item.preferredForwardBufferDuration = 10
            }
        } else {
            player.automaticallyWaitsToMinimizeStalling = true
        }

        return item
    }

    /// 런타임 화질 선호도 변경을 현재 AVPlayerItem 에 즉시 반영.
    /// (lockedPeakBitRate / lockedMaximumResolution / isQualityLocked 토글 시 호출)
    private func applyQualityPreferencesToCurrentItem() {
        let (locked, bitrate, resolution) = stateLock.withLock { s in
            (s.isQualityLocked, s.lockedPeakBitRate, s.lockedMaximumResolution)
        }
        Task { @MainActor [weak self] in
            guard let self, let item = self.player.currentItem else { return }
            if locked {
                item.preferredPeakBitRate = bitrate
                item.preferredMaximumResolution = resolution
            } else {
                // 잠금 해제 시에는 시스템 자동 ABR 허용 (0 = 제한 없음)
                item.preferredPeakBitRate = 0
                item.preferredMaximumResolution = .zero
            }
        }
    }

    // MARK: - Network Monitor Subscription

    private func subscribeNetworkMonitor() {
        networkSubscriptionId = AVPlayerNetworkMonitor.shared.subscribe { [weak self] type in
            guard let self else { return }
            let previous = self.stateLock.withLock { state -> AVPlayerNetworkMonitor.InterfaceType in
                let prev = state.networkType
                state.networkType = type
                return prev
            }
            guard previous != type else { return }
            self.logger.info("AVPlayerEngine: network changed \(String(describing: previous)) → \(String(describing: type))")

            let isLive = self.stateLock.withLock { $0.isLiveStream }
            guard isLive else { return }

            // 라이브: 캐치업 설정 재조정 + 현재 아이템 버퍼 업데이트
            self.adjustCatchupConfigForNetwork()
            let buffer = self.catchupConfig.preferredForwardBuffer
            Task { @MainActor [weak self] in
                guard let self, let item = self.player.currentItem else { return }
                item.preferredForwardBufferDuration = buffer
            }
            // 네트워크 전환 순간의 일시 정지를 스톨로 오인하지 않도록 타임스탬프 갱신
            self.stateLock.withLock { $0.lastProgressTime = Date() }
        }
    }
}
