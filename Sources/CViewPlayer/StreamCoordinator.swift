// MARK: - StreamCoordinator.swift
// CViewPlayer - Unified stream playback coordinator
// 원본: 분산된 sync/player/HLS 관리 → 통합 오케스트레이터 actor

import Foundation
import Synchronization
import CViewCore

// MARK: - Stream Coordinator

/// Orchestrates stream playback: API → manifest → ABR → player → sync.
/// Single entry point for stream lifecycle management.
public actor StreamCoordinator {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let channelId: String
        public let enableLowLatency: Bool
        public let enableABR: Bool
        public let preferredQuality: StreamQuality?
        public let lowLatencyConfig: LowLatencyController.Configuration
        public let abrConfig: ABRController.Configuration
        /// 항상 최고 화질(1080p60) 유지 — ABR 하향/대역폭 캡 무시
        public let forceHighestQuality: Bool
        
        public init(
            channelId: String,
            enableLowLatency: Bool = true,
            enableABR: Bool = true,
            preferredQuality: StreamQuality? = nil,
            lowLatencyConfig: LowLatencyController.Configuration = .webSync,
            abrConfig: ABRController.Configuration = .default,
            forceHighestQuality: Bool = true
        ) {
            self.channelId = channelId
            self.enableLowLatency = enableLowLatency
            self.enableABR = enableABR
            self.preferredQuality = preferredQuality
            self.lowLatencyConfig = lowLatencyConfig
            self.abrConfig = abrConfig
            self.forceHighestQuality = forceHighestQuality
        }
    }
    
    // MARK: - State
    
    public enum StreamPhase: Sendable, Equatable {
        case idle
        case loadingInfo
        case loadingManifest
        case connecting
        case playing
        case paused
        case buffering
        case reconnecting
        case streamEnded
        case error(String)
    }
    
    public struct StreamSnapshot: Sendable {
        public let phase: StreamPhase
        public let quality: StreamQualityInfo?
        public let latency: LatencyInfo?
        public let bufferHealth: BufferHealth?
        public let playbackRate: Double
        public let uptime: TimeInterval
        public let timestamp: Date
    }
    
    // MARK: - Properties
    
    let config: Configuration
    let logger = AppLogger.player
    
    // Sub-controllers
    let hlsParser = HLSManifestParser()
    var abrController: ABRController?
    public internal(set) var lowLatencyController: LowLatencyController?
    // 인스턴스별 프록시 — 멀티라이브 세션이 다른 CDN 호스트를 사용할 수 있으므로
    // 각 StreamCoordinator에 독립 프록시를 할당하여 호스트 간 간섭 방지
    let streamProxy = LocalStreamProxy()

    // P0-2: HLS 전용 URLSession — ephemeral(쿠키 격리) + 캐시 비활성화(라이브 스트림)
    nonisolated let hlsSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // State
    var _phase: StreamPhase = .idle
    var _masterPlaylist: MasterPlaylist?
    var _currentQuality: StreamQualityInfo?
    var _streamURL: URL?
    var _startTime: Date?
    var _isProxyActive = false
    
    // 1080p+ABR 하이브리드 상태
    var _preferredQualityVariant: MasterPlaylist.Variant?  // 원래 선호 화질 (복귀 목표)
    var _isQualityDegraded: Bool = false  // 현재 화질 하향 상태 여부
    var _qualityRecoveryTask: Task<Void, Never>?
    // [Fix 25B] nonisolated(unsafe) → Mutex: LowLatencyController 크로스 액터 읽기 시 데이터 레이스 방지
    struct _BufferState: Sendable {
        var bufferHealth: Double = 1.0       // ABR 화질 복귀 판단용 최근 버퍼 건강도
        var vlcBufferLength: TimeInterval = 0  // [Fix 22B] VLC 실제 버퍼 길이 (duration - currentTime)
    }
    let _bufferState = Mutex(_BufferState())
    /// nonisolated: Mutex가 스레드 안전 보장, Task [weak self] 클로저에서 접근 가능
    nonisolated var _lastBufferHealth: Double {
        get { _bufferState.withLock { $0.bufferHealth } }
        set { _bufferState.withLock { $0.bufferHealth = newValue } }
    }
    nonisolated var _lastVLCBufferLength: TimeInterval {
        get { _bufferState.withLock { $0.vlcBufferLength } }
        set { _bufferState.withLock { $0.vlcBufferLength = newValue } }
    }
    
    // 매니페스트 주기적 갱신 (토큰 리프레시 + variant URL 갱신)
    var _manifestRefreshTask: Task<Void, Never>?
    var _currentVariantURL: URL?  // VLC에 전달한 현재 variant URL
    
    // 재생 감시 (Watchdog) — currentTime 정체 감지 → 자동 재연결
    var _watchdogTask: Task<Void, Never>?
    var _lastWatchdogTime: TimeInterval = -1
    var _lastWatchdogDecodedFrames: Int32 = -1  // 보조 감지: VLC 디코딩 프레임 수
    var _stallCount: Int = 0
    let _stallThreshold: Int = 2  // 연속 2회(6초) 정체 시 재연결
    
    // [Fix 15] 초기 재생 시 FIX14 모니터링과 watchdog 충돌 방지
    // FIX14가 35초간 VLC 상태를 감시하므로 그 기간엔 watchdog 재연결 차단
    var _playbackStartTime: Date = .distantPast
    // [Fix 19] 30초: FIX14 35초 감시 기간 + ABR 초기 캘리브레이션 완료 대기
    // 20→30초: 초기 ABR 품질 조정 중 false-positive 재연결 방지
    let _watchdogGracePeriod: TimeInterval = 30
    
    // 재연결 이중 트리거 방지: 마지막 재연결 시각 (VLC stall + Watchdog 동시 발화 차단)
    var _lastReconnectTime: Date = .distantPast
    // [Fix 19] 8→4초: 지수 백오프(0.5/0.75/1.1s)가 중복 방지하므로 쿨다운은 최소화
    let _reconnectCooldown: TimeInterval = 4
    
    // PDT-based latency provider (Method A)
    var pdtProvider: PDTLatencyProvider?
    
    // [Fix 21] VLC 버퍼 레이턴시 EWMA 스무딩 — 톱니파 노이즈 제거
    var _vlcBufferEWMA: TimeInterval?
    
    // [Fix 22D] 화질 복귀 후 ABR 강등 쿨다운 — 복귀↔강등 진동 방지
    var _qualityRecoveryCooldownUntil: Date = .distantPast
    
    // [Fix 26] 화질 프로빙 타이머 — 장시간 저화질 고정(death spiral) 시 주기적 상위 화질 시도
    var _qualityProbeTask: Task<Void, Never>?

    // [Fix 27] 사용자가 수동으로 선택한 화질 — ABR/프로빙/복귀 로직이 이를 override하지 못하도록 잠금
    // 사용자가 수동 선택 시 ABR switchUp/switchDown, 복귀 Task, 프로빙 Task를 모두 무효화하여
    // 수동 선택 직후 재로드가 반복되어 라이브가 멈춰 보이는 문제를 방지
    var _userSelectedVariant: MasterPlaylist.Variant?
    
    // 매니페스트 갱신 연속 실패 카운터 — CDN 장애 감지
    var _manifestRefreshFailCount: Int = 0
    
    // Player reference (injected)
    var playerEngine: (any PlayerEngineProtocol)?
    
    // Reconnection handler
    var reconnectionHandler = PlaybackReconnectionHandler(config: .aggressive)
    
    /// 방송 종료 여부 확인 콜백 — 재연결 시도 전 호출하여 방송이 실제로 종료됐는지 API로 확인
    /// true 반환 시 재연결 중단 → streamEnded 처리
    public var onCheckStreamEnded: (@Sendable () async -> Bool)?
    
    /// 방송 종료 확인 콜백 설정
    public func setCheckStreamEndedCallback(_ callback: @escaping @Sendable () async -> Bool) {
        onCheckStreamEnded = callback
    }
    
    // Event stream
    var eventContinuation: AsyncStream<StreamEvent>.Continuation?
    var _eventStream: AsyncStream<StreamEvent>?
    
    // MARK: - Public Accessors
    
    public var phase: StreamPhase { _phase }
    public var currentQuality: StreamQualityInfo? { _currentQuality }
    public var isPlaying: Bool { _phase == .playing }
    public var uptime: TimeInterval {
        guard let start = _startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    /// 사용 가능한 품질 목록 (MasterPlaylist에서 추출)
    /// - Note: 오디오 전용 variant(해상도 미지정)는 UI의 화질 선택지에서 제외한다.
    ///   멀티라이브/싱글라이브에서 사용자가 실수로 오디오 전용 스트림을 선택하면
    ///   비디오 트랙이 사라져 "재생이 안 되는 것처럼" 보이는 문제를 예방한다.
    public var availableQualities: [StreamQualityInfo] {
        guard let master = _masterPlaylist else { return [] }
        return master.variants
            .filter { isVideoVariant($0) }
            .map { qualityFromVariant($0) }
    }

    /// variant가 비디오를 포함하는지 여부 — RESOLUTION이 유효하거나 CODECS에 비디오 코덱이
    /// 포함되어 있으면 true. 치지직 오디오 전용 variant(RESOLUTION 누락 + mp4a only)를 걸러낸다.
    private func isVideoVariant(_ variant: MasterPlaylist.Variant) -> Bool {
        let res = variant.resolution
        if res.contains("x") || res.contains("X") { return true }
        if let codecs = variant.codecs?.lowercased() {
            // 비디오 코덱 시그니처(avc/hevc/h264/h265/vp9/av01)가 있으면 비디오
            if codecs.contains("avc") || codecs.contains("hev") || codecs.contains("hvc") ||
               codecs.contains("h26") || codecs.contains("vp9") || codecs.contains("av01") {
                return true
            }
        }
        return false
    }

    /// 대역폭 코디네이터에서 할당된 최대 비트레이트를 ABR에 전달
    public func setMaxAllowedBitrate(_ maxBps: Double) async {
        // [Quality Lock] 최고 화질 모드에서는 ABR 캡을 적용하지 않음
        if config.forceHighestQuality { return }
        await abrController?.setMaxAllowedBitrate(maxBps)
    }
    
    /// bandwidth로 variant를 찾아 품질 전환 (사용자 수동 선택)
    public func switchQualityByBandwidth(_ bandwidth: Int) async throws {
        guard let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) else {
            throw StreamCoordinatorError.qualityNotFound
        }

        // [Fix 27] 수동 선택: ABR/복귀/프로빙 Task 모두 취소하고 잠금
        // 이 처리가 없으면 switchQuality 직후 ABR이 다시 override하여 재로드 발생 → "멈춤" 체감
        _userSelectedVariant = variant
        _isQualityDegraded = false
        _qualityRecoveryTask?.cancel()
        _qualityRecoveryTask = nil
        _qualityProbeTask?.cancel()
        _qualityProbeTask = nil
        // 수동 선택 직후 ABR이 즉시 반대로 튀지 않도록 긴 쿨다운 부여
        _qualityRecoveryCooldownUntil = Date().addingTimeInterval(30.0)

        // 동일 화질 재선택은 엔진 reload 없이 무시 (라이브 끊김 방지)
        if let current = _currentQuality, current.bandwidth == variant.bandwidth {
            logger.info("수동 화질 선택: 동일 화질(\(variant.qualityLabel)) — reload 생략")
            return
        }

        try await switchQuality(to: variant)
    }

    // MARK: - Initialization
    
    public init(configuration: Configuration) {
        self.config = configuration
        
        if configuration.enableABR {
            self.abrController = ABRController(configuration: configuration.abrConfig)
        }
        
        if configuration.enableLowLatency {
            self.lowLatencyController = LowLatencyController(configuration: configuration.lowLatencyConfig)
        }
    }
    
    deinit {
        // Task 조기 취소 — [weak self] guard 도달 대기 없이 즉시 중단
        _qualityRecoveryTask?.cancel()
        _manifestRefreshTask?.cancel()
        _watchdogTask?.cancel()
        // 인스턴스별 프록시 정리 — 자신의 NWListener만 종료
        streamProxy.stop()
        hlsSession.invalidateAndCancel()
        eventContinuation?.finish()
    }

    // MARK: - Proxy Stats

    /// 이 코디네이터의 per-instance 프록시 네트워크 통계 반환
    public nonisolated func proxyNetworkStats() -> ProxyNetworkStats {
        streamProxy.networkStats()
    }

    // MARK: - Latency Access (Direct Query)

    /// PDT 기반 세그먼트 레이턴시 (초, nil = PDT 미지원/비활성)
    public func pdtLatencySeconds() async -> TimeInterval? {
        await pdtProvider?.currentLatency()
    }

    /// VLC 버퍼 기반 재생 위치 지연 (초, nil = 비가용)
    public func bufferLatencySeconds() async -> TimeInterval? {
        await vlcBufferLatency()
    }

    /// 현재 종합 레이턴시 (초) — PDT + vlcBuffer 합산, 없으면 vlcBuffer 단독
    /// MetricsForwarder 콜백에서 직접 호출하여 정확한 실시간 레이턴시를 취득
    public func currentLatencySeconds() async -> TimeInterval? {
        if let pdt = await pdtProvider?.currentLatency() {
            let buffer = await vlcBufferLatency() ?? 0
            return pdt + buffer
        }
        return await vlcBufferLatency()
    }
    
    // MARK: - Low Latency Config Update
    
    /// 런타임 레이턴시 설정 변경 — LowLatencyController를 새 config로 재생성
    public func updateLowLatencyConfig(_ newConfig: LowLatencyController.Configuration) {
        self.lowLatencyController = LowLatencyController(configuration: newConfig)
        logger.info("LowLatencyController reconfigured: target=\(newConfig.targetLatency)s")
    }
    
    // MARK: - Setup
    
    /// Inject player engine
    public func setPlayerEngine(_ engine: any PlayerEngineProtocol) {
        self.playerEngine = engine
        configureEngineCallbacks(engine)
    }
    
    /// [Opt: Single VLC] 프리페치된 마스터 매니페스트 주입
    /// 호버 시 HLSPrefetchService가 미리 받아온 매니페스트를 전달하면
    /// startStream()에서 resolveHighestQualityVariant() 네트워크 요청을 건너뛴다 (~200-400ms 절약)
    public func setPrefetchedManifest(_ manifest: MasterPlaylist) {
        _masterPlaylist = manifest
    }
    
    /// 엔진 콜백 연결 — AVPlayerEngine의 재연결 요청 수신, VLC ABR 하이브리드 연결
    private func configureEngineCallbacks(_ engine: any PlayerEngineProtocol) {
        if let avEngine = engine as? AVPlayerEngine {
            avEngine.onReconnectRequested = { [weak self] in
                Task { await self?.triggerReconnect(reason: "engine requested") }
            }
        }
        
        // VLC 엔진: 1080p+ABR 하이브리드 적응형 화질 콜백 연결
        if let vlcEngine = engine as? VLCPlayerEngine {
            vlcEngine.onQualityAdaptationRequest = { [weak self] action in
                Task { [weak self] in
                    await self?.handleQualityAdaptation(action)
                }
            }
            // VLC onStateChange는 PlayerViewModel._handleVLCPhase에서 설정.
            // PlayerViewModel이 handleVLCEngineState()를 호출하여 watchdog/lowLatency를 제어.
        }
    }

    /// PlayerViewModel에서 VLC 상태 변경을 전달받아 watchdog + lowLatency 제어
    /// PlayerViewModel._handleVLCPhase에서 호출되어 콜백 덮어쓰기 문제 해결
    public func handleVLCEngineState(_ phase: PlayerState.Phase) async {
        switch phase {
        case .playing:
            await lowLatencyController?.resumeFromBuffering()
            let alreadyWatching = _watchdogTask?.isCancelled == false
            if !alreadyWatching {
                // [Fix 15] 최초 재생 시각 기록 — watchdog grace period 기준점
                _playbackStartTime = Date()
                startPlaybackWatchdog()
            }
        case .buffering:
            await lowLatencyController?.pauseForBuffering()
        default:
            break
        }
    }
    
    /// Get event stream
    public func events() -> AsyncStream<StreamEvent> {
        if let existing = _eventStream { return existing }
        
        let stream = AsyncStream<StreamEvent> { continuation in
            self.eventContinuation = continuation
        }
        _eventStream = stream
        return stream
    }
    

    // MARK: - Internal Helpers

    func updatePhase(_ newPhase: StreamPhase) {
        _phase = newPhase
        emitEvent(.phaseChanged(newPhase))
    }
    

    func qualityFromVariant(_ variant: MasterPlaylist.Variant) -> StreamQualityInfo {
        StreamQualityInfo(
            name: variant.qualityLabel,
            resolution: variant.resolution,
            bandwidth: variant.bandwidth
        )
    }
    

    func emitEvent(_ event: StreamEvent) {
        eventContinuation?.yield(event)
    }
}

// MARK: - Stream Events

public enum StreamEvent: Sendable {
    case phaseChanged(StreamCoordinator.StreamPhase)
    case qualitySelected(StreamQualityInfo)
    case qualityChanged(StreamQualityInfo)
    case abrDecision(ABRController.ABRDecision)
    case latencyUpdate(LatencyInfo)
    case bufferUpdate(BufferHealth)
    case error(String)
    case streamEnded
    case stopped
}

// MARK: - Stream Coordinator Error

public enum StreamCoordinatorError: Error, Sendable {
    case qualityNotFound
}

public enum StreamError: Error, LocalizedError, Sendable {
    case proxyStartFailed

    public var errorDescription: String? {
        switch self {
        case .proxyStartFailed: "CDN 프록시 시작 실패 — 네트워크를 확인해주세요"
        }
    }
}

// MARK: - Supporting Types

public struct StreamQualityInfo: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let resolution: String
    public let bandwidth: Int
    
    public init(name: String, resolution: String, bandwidth: Int) {
        self.name = name
        self.resolution = resolution
        self.bandwidth = bandwidth
    }
}

public struct LatencyInfo: Sendable {
    public let current: TimeInterval
    public let target: TimeInterval
    public let ewma: TimeInterval
    
    public init(current: TimeInterval, target: TimeInterval, ewma: TimeInterval) {
        self.current = current
        self.target = target
        self.ewma = ewma
    }
}

public struct BufferHealth: Sendable {
    public let currentLevel: Double
    public let targetLevel: Double
    public let isHealthy: Bool
    
    public init(currentLevel: Double, targetLevel: Double, isHealthy: Bool) {
        self.currentLevel = currentLevel
        self.targetLevel = targetLevel
        self.isHealthy = isHealthy
    }
}
