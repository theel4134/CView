// MARK: - StreamCoordinator.swift
// CViewPlayer - Unified stream playback coordinator
// 원본: 분산된 sync/player/HLS 관리 → 통합 오케스트레이터 actor

import Foundation
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
        
        public init(
            channelId: String,
            enableLowLatency: Bool = true,
            enableABR: Bool = true,
            preferredQuality: StreamQuality? = nil,
            lowLatencyConfig: LowLatencyController.Configuration = .webSync,
            abrConfig: ABRController.Configuration = .default
        ) {
            self.channelId = channelId
            self.enableLowLatency = enableLowLatency
            self.enableABR = enableABR
            self.preferredQuality = preferredQuality
            self.lowLatencyConfig = lowLatencyConfig
            self.abrConfig = abrConfig
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
    var lowLatencyController: LowLatencyController?
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
    // 20초: FIX14 Phase 1(5초) + Phase 2 초반 커버, Phase 2 후반부터 watchdog 활성화
    let _watchdogGracePeriod: TimeInterval = 20
    
    // 재연결 이중 트리거 방지: 마지막 재연결 시각 (VLC stall + Watchdog 동시 발화 차단)
    var _lastReconnectTime: Date = .distantPast
    let _reconnectCooldown: TimeInterval = 8  // 8초 내 이중 재연결 차단 (10→8s: 빠른 복구)
    
    // PDT-based latency provider (Method A)
    var pdtProvider: PDTLatencyProvider?
    
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
    public var availableQualities: [StreamQualityInfo] {
        guard let master = _masterPlaylist else { return [] }
        return master.variants.map { qualityFromVariant($0) }
    }
    
    /// bandwidth로 variant를 찾아 품질 전환
    public func switchQualityByBandwidth(_ bandwidth: Int) async throws {
        guard let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) else {
            throw StreamCoordinatorError.qualityNotFound
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
