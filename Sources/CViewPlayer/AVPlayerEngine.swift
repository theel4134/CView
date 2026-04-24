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

        // [Multi-live] 활성/비활성 세션 여부 — 버퍼 정책 이원화
        // true: 선택 세션(멀티라이브 포그라운드) — 빠른 복구 우선, 차이 버퍼 1개으로 축소
        // false: 비선택 세션(멀티라이브 백그라운드) — 안정성 우선, 차이 버퍼 많은 쪽 제거
        // 기본값 true: 싱글 스트림이거나 멀티라이브 선택 세션에 해당.
        var isSelectedMultiLiveSession: Bool = true

        // 선택된 멀티라이브 세션 warm-up 중 플래그 — warm-up 동안은 안정성 우선 후
        // 2단계에 1080p60/8Mbps 잠금으로 전환한다. 기본값 false (warm-up 아님).
        var isWarmingUpForHQ: Bool = false

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

    /// 멀티라이브에서 현재 선택된 세션인지 여부.
    /// - `true`: 버퍼 짧게(선택 전방 버퍼 상한 적용), 빠른 복구 중심
    /// - `false`: 버퍼 길게(안정성 우선), `automaticallyPreservesTimeOffsetFromLive`도 느슨하게 유지
    public var isSelectedMultiLiveSession: Bool {
        get { stateLock.withLock { $0.isSelectedMultiLiveSession } }
        set {
            stateLock.withLock { $0.isSelectedMultiLiveSession = newValue }
            applyMultiLiveBufferPreferenceToCurrentItem()
        }
    }

    /// warm-up 단계 플래그 — `MultiLiveManager` 등 상위 조정자가 선택 직후 true로 두었다가
    /// 짧은 warm-up 이후 false로 복구한다. warm-up 중에는 상대적으로 단단한 버퍼를 유지하도록
    /// `balanced` 수준의 버퍼를 써서 첫 프레임 지연을 줄인다.
    public var isWarmingUpForHQ: Bool {
        get { stateLock.withLock { $0.isWarmingUpForHQ } }
        set {
            stateLock.withLock { $0.isWarmingUpForHQ = newValue }
            applyMultiLiveBufferPreferenceToCurrentItem()
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

    // chzzk CDN Content-Type 교정용 인-프로세스 인터셉터 (LocalStreamProxy 대체)
    private let httpInterceptor = AVPlayerHTTPInterceptor()
    private let interceptorQueue = DispatchQueue(label: "com.cview.avengine.interceptor")

    /// 스트림 프록시 / 인터셉트 모드. StreamCoordinator 가 재생 시작 직전 주입.
    /// - .avInterceptor   : ResourceLoaderDelegate 사용 (cviewhttps 스킴)
    /// - .avAssetDownload : AVAssetDownloadURLSession 으로 자산 로드 시도
    /// - 그 외            : 일반 AVURLAsset 직접 재생 (URL 은 StreamCoordinator 가 적절히 변환)
    public var streamProxyMode: StreamProxyMode = .localProxy

    // 재연결 폭주 보호 기준
    internal let maxReconnectsInWindow = 3
    internal let reconnectWindowSeconds: TimeInterval = 300 // 5분

    // MARK: - Init / Deinit

    public override init() {
        self.renderView = AVPlayerLayerView()
        self.player = AVPlayer()
        super.init()
        renderView.attach(player: player)

        // [Codec Tune 2026-04-23] 미디어 선택은 LiveStream 경로에서 명시적으로 수행하므로
        // AVPlayer 의 자동 평가(언어/캡션 매칭) 비용을 제거한다. 화질·반응성 무영향.
        player.appliesMediaSelectionCriteriaAutomatically = false
        // 백그라운드 활성 정책 명시 — 비활성 윈도우에서도 오디오 디코드 유지 (기본 동작 명문화)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

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

    /// 멀티라이브 GPU 렌더 계층 업데이트 — compositor contentsScale / 레이어 가시성 조정.
    /// 디코딩 해상도/화질 단계와는 독립 (quality-lock 모드에서도 안전).
    public func setGPURenderTier(_ tier: SessionTier) {
        let avTier: AVGPURenderTier
        switch tier {
        case .active:  avTier = .active
        case .visible: avTier = .visible
        case .hidden:  avTier = .hidden
        }
        renderView.setGPURenderTier(avTier)
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
        tasks.cancel(AVPlayerTaskBag.kStallRecovery)
        tasks.cancel(AVPlayerTaskBag.kLiveCatchup)
        tasks.cancel(AVPlayerTaskBag.kMetricsCollector)
        tasks.cancel(AVPlayerTaskBag.kHQRecovery)
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
        // 라이브는 첫 프레임 이후 seek-to-live-edge 가 즉시 이어지므로
        // playImmediately(atRate:) 로 초기 재생을 강제해 "첫 화면만 멈춰 보이는" 현상을 줄인다.
        player.replaceCurrentItem(with: item)
        let desiredRate = max(0.01, stateLock.withLock { $0.rate })
        player.rate = desiredRate
        if isLive {
            player.playImmediately(atRate: desiredRate)
        } else {
            player.play()
        }

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

        // [Stream Proxy Mode] 모드별 자산 생성 분기.
        //   - .avInterceptor   : URL 을 cviewhttps 스킴으로 치환하고 ResourceLoaderDelegate 부착
        //   - .avAssetDownload : AVAssetDownloadURLSession 으로 자산 로드 시도 (라이브 보장 X, 실험적)
        //   - 나머지            : 일반 AVURLAsset (URL 은 StreamCoordinator 측에서 이미 변환됨)
        let asset: AVURLAsset
        switch streamProxyMode {
        case .avInterceptor:
            let useIntercept = AVPlayerHTTPInterceptor.needsInterception(for: url)
            let assetURL = useIntercept ? AVPlayerHTTPInterceptor.interceptedURL(from: url) : url
            asset = AVURLAsset(url: assetURL, options: assetOptions)
            if useIntercept {
                asset.resourceLoader.setDelegate(httpInterceptor, queue: interceptorQueue)
            }

        case .avAssetDownload:
            // AVAssetDownloadURLSession 은 백그라운드 세션이 필요하나 라이브 HLS 재생에는 부적합.
            // 옵션 노출만 유지하고 일반 AVURLAsset 으로 폴백 (실험적 — 향후 다운로드 작업 wrapping 가능).
            asset = AVURLAsset(url: url, options: assetOptions)
            logger.warning("AVPlayerEngine: avAssetDownload 모드 — 라이브에서는 AVURLAsset 폴백")

        case .localProxy, .urlProtocolHook, .directVLCAdaptive, .none:
            asset = AVURLAsset(url: url, options: assetOptions)
        }
        let item = AVPlayerItem(asset: asset)

        // [Codec Tune 2026-04-23] 매 프레임 HDR 메타데이터 적용 — SDR 콘텐츠는 무비용,
        // HDR(EDR) 디스플레이에서는 톤 매핑 정확도 향상.
        item.appliesPerFrameHDRDisplayMetadata = true

        // [Codec Tune 2026-04-23] LowLatencyController rate 기반 catchup 시 사용되는
        // 오디오 피치 알고리즘을 명시. spectral(default) → timeDomain 으로 강등하면
        // ±15% 레이트 범위에서는 품질 차이 미미하나 CPU 비용이 절반 이하로 감소.
        // 비선택 멀티라이브는 catchup 자체를 사용하지 않으므로 가장 가벼운 varispeed 사용.
        let isSelectedMultiNow = stateLock.withLock { $0.isSelectedMultiLiveSession }
        if isLive && !isSelectedMultiNow {
            // 멀티라이브 비선택 — 1.0× 고정, 음높이 보정 불필요
            item.audioTimePitchAlgorithm = .varispeed
        } else {
            item.audioTimePitchAlgorithm = .timeDomain
        }

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

            adjustCatchupConfigForNetwork()
            let cfg = catchupConfig
            // [Multi-live 이원화] 선택된 세션은 짧은 전방 버퍼로 빠른 복구를,
            // 비선택 세션은 네트워크 변동 흡수용 긴 버퍼를 유지한다.
            let (isSelectedMulti, warmingUp) = stateLock.withLock { s in
                (s.isSelectedMultiLiveSession, s.isWarmingUpForHQ)
            }
            // [Multi-live 튜닝] 라이브 엣지 자동 추종 / 일시정지 중 네트워크 사용 —
            // 선택된 세션만 활성화. 비선택 세션은 AVPlayer 내부의 라이브 엣지 재추적
            // 및 pause-간 preloading 을 억제해 N×I/O 경쟁과 CPU 낭비를 줄인다.
            item.automaticallyPreservesTimeOffsetFromLive = isSelectedMulti
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = isSelectedMulti
            let selectedBuffer = max(1.0, min(cfg.preferredForwardBuffer, 1.5))
            let nonSelectedBuffer = max(cfg.preferredForwardBuffer, 3.5)
            let warmUpBuffer = max(cfg.preferredForwardBuffer, 2.5)
            let liveBuffer: Double = {
                if !isSelectedMulti { return nonSelectedBuffer }
                return warmingUp ? warmUpBuffer : selectedBuffer
            }()
            item.preferredForwardBufferDuration = liveBuffer
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyMultiLiveBufferPreferenceToCurrentItem()
            }
            // 네트워크 전환 순간의 일시 정지를 스톨로 오인하지 않도록 타임스탬프 갱신
            self.stateLock.withLock { $0.lastProgressTime = Date() }
        }
    }

    /// 멀티라이브 선택/비선택 상태에 맞춰 현재 AVPlayerItem의 `preferredForwardBufferDuration`을 갱신.
    /// `catchupConfig.preferredForwardBuffer`를 기준선으로 잡고,
    /// - 선택 세션          : 최대 1.5s (빠른 복구)
    /// - warm-up 진행 중    : 2.5s 내외 (첫 프레임 안정성)
    /// - 비선택 세션        : 3.5s 이상 (버퍼 안정성)
    ///
    /// [Multi-live 튜닝] 버퍼 외에도 라이브 엣지 추종/paused 네트워크 사용 플래그를 함께 갱신한다.
    /// 선택 세션만 true, 비선택 세션은 false 로 두어 N 개 엔진 간 I/O 경쟁을 완화한다.
    public func applyMultiLiveBufferPreferenceToCurrentItem() {
        let isLive = stateLock.withLock { $0.isLiveStream }
        guard isLive else { return }
        let (isSelectedMulti, warmingUp) = stateLock.withLock { s in
            (s.isSelectedMultiLiveSession, s.isWarmingUpForHQ)
        }
        let cfg = catchupConfig
        let liveBuffer: Double = {
            if !isSelectedMulti { return max(cfg.preferredForwardBuffer, 3.5) }
            if warmingUp         { return max(cfg.preferredForwardBuffer, 2.5) }
            return max(1.0, min(cfg.preferredForwardBuffer, 1.5))
        }()
        Task { @MainActor [weak self] in
            guard let self, let item = self.player.currentItem else { return }
            item.preferredForwardBufferDuration = liveBuffer
            item.automaticallyPreservesTimeOffsetFromLive = isSelectedMulti
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = isSelectedMulti
        }
    }
}
