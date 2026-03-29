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
    
    private let config: Configuration
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
    private var _startTime: Date?
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

    // MARK: - 1080p + ABR Hybrid

    /// VLC 엔진의 적응형 화질 전환 요청을 처리합니다.
    /// - downgrade: 대역폭 부족 → 한 단계 낮은 화질로 전환 (e.g., 1080p → 720p)
    /// - upgrade: 버퍼 안정 → 원래 화질로 복귀 (e.g., 720p → 1080p)
    public func handleQualityAdaptation(_ action: QualityAdaptationAction) async {
        guard let master = _masterPlaylist, master.variants.count > 1 else { return }
        
        let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }
        
        switch action {
        case .downgrade(let reason):
            guard !_isQualityDegraded else { return }  // 이미 하향 상태
            
            // 현재 화질 저장 (복귀 목표)
            if _preferredQualityVariant == nil, let current = sortedVariants.first(where: {
                $0.resolution.contains("1080")
            }) ?? sortedVariants.first {
                _preferredQualityVariant = current
            }
            
            // 한 단계 낮은 화질 선택 (720p 우선, 없으면 현재보다 낮은 bandwidth)
            let fallbackVariant = sortedVariants.first(where: { $0.resolution.contains("720") })
                ?? sortedVariants.dropFirst().first  // 1080p 다음 variant
            
            guard let targetVariant = fallbackVariant else { return }
            
            _isQualityDegraded = true
            _qualityRecoveryTask?.cancel()
            
            logger.warning("ABR 하이브리드: 화질 하향 → \(targetVariant.qualityLabel) (\(reason))")
            
            do {
                try await switchQuality(to: targetVariant)
                emitEvent(.qualityChanged(qualityFromVariant(targetVariant)))
                
                // 10초 후 자동 복귀 시도 예약
                _qualityRecoveryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, !Task.isCancelled else { return }
                    await self.handleQualityAdaptation(.upgrade(reason: "10초 타이머 자동 복귀"))
                }
            } catch {
                _isQualityDegraded = false
                logger.warning("ABR 하이브리드: 화질 하향 실패: \(error.localizedDescription)")
            }
            
        case .upgrade(let reason):
            guard _isQualityDegraded else { return }  // 하향 상태 아님
            
            guard let preferredVariant = _preferredQualityVariant else {
                _isQualityDegraded = false
                return
            }
            
            _qualityRecoveryTask?.cancel()
            
            logger.info("ABR 하이브리드: 화질 복귀 → \(preferredVariant.qualityLabel) (\(reason))")
            
            do {
                try await switchQuality(to: preferredVariant)
                _isQualityDegraded = false
                emitEvent(.qualityChanged(qualityFromVariant(preferredVariant)))
            } catch {
                // 복귀 실패 → 10초 후 재시도
                logger.warning("ABR 하이브리드: 화질 복귀 실패, 10초 후 재시도")
                _qualityRecoveryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, !Task.isCancelled else { return }
                    await self.handleQualityAdaptation(.upgrade(reason: "복귀 재시도"))
                }
            }
        }
    }

    /// 현재 화질 하향 상태 여부
    public var isQualityDegraded: Bool { _isQualityDegraded }
    
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
    
    // MARK: - Stream Lifecycle
    
    /// Start playing a stream from URL
    public func startStream(url: URL) async throws {
        _streamURL = url
        _startTime = Date()
        
        updatePhase(.connecting)
        
        do {
            var playbackURL = url
            let isVLCEngine = playerEngine is VLCPlayerEngine

            // [Fix 16] VLC + AVPlayer 모두 프록시 경유
            // CDN이 fMP4 세그먼트를 Content-Type: video/MP2T로 잘못 응답
            // → 프록시에서 video/mp4로 교정하여 VLC MP4→TS 전환 버그 방지
            // Fix 15 회귀(프록시 과부하) 대응: M3U8 응답 1초 캐싱으로 VLC 폴링 부하 해소
            if LocalStreamProxy.needsProxy(for: url) {
                if let host = url.host {
                    var proxyStarted = false
                    do {
                        try await streamProxy.start(for: host)
                        proxyStarted = true
                        _isProxyActive = true
                        streamProxy.onUpstreamAuthFailure = { [weak self] in
                            Task { [weak self] in
                                await self?.triggerReconnect(reason: "CDN 403 토큰 만료 감지")
                            }
                        }
                        let engineLabel = isVLCEngine ? "VLC" : "AVPlayer"
                        logger.info("CDN proxy active (\(engineLabel, privacy: .public)): \(host, privacy: .public) → localhost:\(self.streamProxy.port, privacy: .public)")
                    } catch {
                        logger.warning("CDN proxy failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if !proxyStarted {
                        logger.warning("CDN proxy failed, direct connection fallback")
                    }
                }
            }

            if isVLCEngine {
                // [Fix 16g] VLC에 chunklist(미디어 플레이리스트) URL 직접 전달
                // `:adaptive-use-access` + 마스터 URL 조합 → demux 프로빙 무한루프
                // `:adaptive-use-access` 없이 마스터 URL → chunklist 폴링만, 세그먼트 미다운로드
                // → chunklist URL을 프록시 경유로 전달하여 adaptive가 세그먼트를 직접 파싱
                // 프록시가 chunklist 내 세그먼트 URL을 프록시 절대경로로 변환 → Content-Type 교정
                
                _currentVariantURL = url  // 원본 CDN URL 보존 (재연결용)
                
                // [Opt: Single VLC] 프리페치 매니페스트가 있으면 네트워크 재요청 생략
                // HLSPrefetchService가 호버 시 이미 마스터 매니페스트를 받아왔으므로
                // resolveHighestQualityVariant() GET 요청 (~200-400ms) 절약
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    // 프리페치 캐시에서 variant 직접 해석 — 네트워크 요청 없음
                    let sortedVariants = prefetchedMaster.variants.sorted { $0.bandwidth > $1.bandwidth }
                    let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                        ?? sortedVariants.first
                    
                    // ABR 레벨 설정 (프리페치 경로에서도 필요)
                    await abrController?.setLevels(prefetchedMaster.variants)
                    
                    // CDN 워밍만 비동기 실행 (variant 해석은 이미 완료)
                    await warmUpCDNConnection(url: url)
                    
                    if let variant = target {
                        _currentVariantURL = variant.uri
                        _currentQuality = qualityFromVariant(variant)
                        _preferredQualityVariant = variant
                        emitEvent(.qualitySelected(_currentQuality!))
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: variant.uri)
                        } else {
                            playbackURL = variant.uri
                        }
                        logger.info("VLC: [Opt] 프리페치 매니페스트에서 variant 해석 → \(variant.qualityLabel) (네트워크 절약)")
                    } else {
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: url)
                        }
                    }
                } else {
                    // 프리페치 캐시 없음 — 기존 경로: CDN 워밍 + variant 해석 병렬 실행
                    // warmUp(HEAD)과 resolveVariant(GET)은 독립 작업 — 병렬화로 50~200ms 절약
                    // URLSession이 같은 호스트 커넥션을 재사용하므로 TCP/TLS는 1회만 수립
                    async let warmUpTask: Void = warmUpCDNConnection(url: url)
                    async let variantTask = resolveHighestQualityVariant(from: url)
                    
                    let (_, resolvedVariant) = await (warmUpTask, variantTask)
                    
                    if let variantURL = resolvedVariant {
                        _currentVariantURL = variantURL
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: variantURL)
                        } else {
                            playbackURL = variantURL
                        }
                        logger.info("VLC: [Fix 16g] chunklist URL 직접 전달 → \(variantURL.lastPathComponent, privacy: .public)")
                    } else {
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: url)
                        }
                        logger.warning("VLC: [Fix 16g] variant 해석 실패, 마스터 URL 폴백")
                    }
                }
            } else {
                // AVPlayer: 마스터 URL을 프록시 경유로 전달 (AVPlayer 내장 ABR 활용)
                // [Phase 4] 매니페스트를 미리 파싱하여 1080p 60fps variant 정보 확인 →
                // AVPlayerItem의 preferredPeakBitRate를 정확한 1080p 비트레이트로 힌트 설정
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    // 프리페치 캐시 활용: 네트워크 요청 없이 variant 정보 설정
                    await resolveAVPlayerInitialQuality(from: prefetchedMaster)
                } else {
                    // 프리페치 없음: 빠른 매니페스트 파싱으로 품질 정보 사전 확보
                    await resolveAVPlayerManifest(from: url)
                }
                
                if _isProxyActive {
                    playbackURL = streamProxy.proxyURL(from: url)
                }
            }
            
            if let engine = playerEngine {
                try await engine.play(url: playbackURL)
                updatePhase(.playing)
            } else {
                updatePhase(.error("Player engine unavailable"))
                return
            }
            
            // 백그라운드에서 매니페스트 파싱 (품질 정보 UI용)
            // VLC의 경우 이미 resolveHighestQualityVariant에서 파싱 완료되었을 수 있음
            if _masterPlaylist == nil {
                loadManifestInfo(from: url)
            }
            
            // 매니페스트 주기적 갱신 타이머 시작 (VLC 토큰 리프레시 + variant URL 갱신)
            if isVLCEngine {
                // _currentVariantURL은 이미 startStream 초기 variant 해석에서 설정됨
                startManifestRefreshTimer()
            }
            
            // 재생 감시(Watchdog) 시작 — currentTime 정체 감지
            // AVPlayerEngine: 자체 스마트 워치독(readyToPlay KVO에서 시작)이 있으므로 불필요
            // VLCPlayerEngine: onStateChange .playing 콜백에서 워치독 시작 (configureEngineCallbacks 참조)
            // 양쪽 모두 여기서 직접 시작하지 않음 — 엔진이 실제 준비된 시점에 시작
            
            // 저지연 싱크: 백그라운드에서 비동기 실행 (play() 직후 바로 반환, 화면 출력 차단 안 함)
            // PDT 안정화 루프(최대 6초)가 startStream을 블로킹하던 문제 해결
            if config.enableLowLatency {
                Task { [weak self] in await self?.startLowLatencySync() }
            }
            
            logger.info("Stream started: \(LogMask.url(url), privacy: .private)")
            
        } catch {
            updatePhase(.error(error.localizedDescription))
            throw error
        }
    }
    
    /// 마스터 매니페스트를 파싱하여 1080p (또는 최고 해상도) variant URL을 반환합니다.
    /// VLC 엔진 전용: VLC 자체 ABR을 우회하여 최고 품질 고정 재생.
    /// - Parameter masterURL: HLS 마스터 매니페스트 URL
    /// - Returns: 1080p variant URL (없으면 최고 bandwidth variant, 파싱 실패 시 nil)
    private func resolveHighestQualityVariant(from masterURL: URL) async -> URL? {
        do {
            var request = URLRequest(url: masterURL)
            request.timeoutInterval = 5  // 매니페스트 fetch 타임아웃 5초
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            
            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            guard content.contains("#EXT-X-STREAM-INF") else {
                // 마스터 매니페스트가 아닌 단일 미디어 플레이리스트인 경우
                logger.info("VLC: Single media playlist (no variants) — using directly")
                return nil
            }
            
            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: masterURL)
            
            // 매니페스트 정보 저장 (UI 품질 목록용)
            _masterPlaylist = master
            await abrController?.setLevels(master.variants)
            
            // 1) 1080p variant 우선 선택 (해상도에 "1080" 포함)
            // 2) 1080p 없으면 최고 bandwidth variant 선택
            let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }
            let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                ?? sortedVariants.first  // 최고 bandwidth (이미 정렬됨)
            
            if let variant = target {
                _currentQuality = qualityFromVariant(variant)
                _preferredQualityVariant = variant  // ABR 하이브리드: 복귀 목표 저장
                emitEvent(.qualitySelected(_currentQuality!))
                logger.info("VLC: Resolved variant → \(variant.qualityLabel) (\(variant.bandwidth / 1000)kbps) \(variant.resolution)")
                return variant.uri
            }
            
            return nil
        } catch {
            logger.warning("VLC 1080p variant resolution failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - AVPlayer 1080p 60fps 초기 품질 해석 [Phase 4]
    
    /// 프리페치된 매니페스트에서 AVPlayer 초기 품질 정보를 설정합니다.
    /// AVPlayer는 마스터 URL을 직접 재생하므로 variant URL은 전달하지 않고,
    /// preferredPeakBitRate 힌트와 UI용 품질 정보만 설정합니다.
    private func resolveAVPlayerInitialQuality(from master: MasterPlaylist) async {
        await abrController?.setLevels(master.variants)
        
        guard let variant = select1080p60Variant(from: master.variants) else { return }
        
        _currentQuality = qualityFromVariant(variant)
        _preferredQualityVariant = variant
        emitEvent(.qualitySelected(_currentQuality!))
        logger.info("AVPlayer: [Phase 4] 프리페치 매니페스트 → \(variant.qualityLabel) \(variant.frameRate.map { "\(Int($0))fps" } ?? "") (\(variant.bandwidth / 1000)kbps)")
    }
    
    /// 마스터 URL을 파싱하여 AVPlayer 초기 품질 정보를 설정합니다.
    /// play() 이전에 호출하여 ABR 레벨과 UI 품질 정보를 사전 구성합니다.
    private func resolveAVPlayerManifest(from masterURL: URL) async {
        do {
            var request = URLRequest(url: masterURL)
            request.timeoutInterval = 3  // play() 차단 최소화
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            
            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            guard content.contains("#EXT-X-STREAM-INF") else { return }
            
            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: masterURL)
            _masterPlaylist = master
            
            await resolveAVPlayerInitialQuality(from: master)
            logger.info("AVPlayer: [Phase 4] 매니페스트 파싱 완료 → variants: \(master.variants.count)개")
        } catch {
            logger.debug("AVPlayer: 매니페스트 사전 파싱 실패 (무시): \(error.localizedDescription)")
        }
    }
    
    /// 1080p 60fps variant를 우선 선택하는 공통 선택 로직.
    /// 우선순위: 1080p 60fps > 1080p (아무 fps) > 최고 bandwidth variant
    func select1080p60Variant(from variants: [MasterPlaylist.Variant]) -> MasterPlaylist.Variant? {
        let sorted = variants.sorted { $0.bandwidth > $1.bandwidth }
        
        // 1순위: 1080p && 60fps (프레임레이트가 명시된 경우)
        if let target = sorted.first(where: {
            $0.resolution.contains("1080") && ($0.frameRate ?? 0) >= 59.0
        }) {
            return target
        }
        
        // 2순위: 1080p (아무 프레임레이트)
        if let target = sorted.first(where: { $0.resolution.contains("1080") }) {
            return target
        }
        
        // 3순위: 최고 bandwidth
        return sorted.first
    }
    
    /// CDN 엣지 서버에 HEAD 요청을 보내 TCP/TLS 연결을 사전 수립합니다.
    /// VLC play() 전에 호출하면 초기 버퍼링 시간(TTFP)을 200~500ms 단축할 수 있습니다.
    /// - Parameter url: CDN 스트림 URL (마스터 매니페스트 또는 variant URL)
    private func warmUpCDNConnection(url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3  // 워밍 타임아웃 3초 (너무 오래 걸리면 스킵)
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            let (_, response) = try await hlsSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("CDN 워밍 완료: \(url.host ?? "unknown") → HTTP \(httpResponse.statusCode)")
            }
        } catch {
            // 워밍 실패는 비핵심 — 무시하고 정상 재생 진행
            logger.debug("CDN 워밍 실패 (무시): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop the stream
    public func stopStream() async {
        await reconnectionHandler.cancel()
        playerEngine?.stop()
        await lowLatencyController?.stopSync()
        
        // PDT provider 정리
        await pdtProvider?.stop()
        pdtProvider = nil
        
        // 프록시 정리
        if _isProxyActive {
            streamProxy.stop()
            _isProxyActive = false
        }
        
        _masterPlaylist = nil
        _currentQuality = nil
        _streamURL = nil
        _startTime = nil
        _preferredQualityVariant = nil
        _isQualityDegraded = false
        _qualityRecoveryTask?.cancel()
        _qualityRecoveryTask = nil
        _manifestRefreshTask?.cancel()
        _manifestRefreshTask = nil
        _currentVariantURL = nil
        _watchdogTask?.cancel()
        _watchdogTask = nil
        _stallCount = 0
        _lastWatchdogTime = -1
        _lastWatchdogDecodedFrames = -1
        _lastReconnectTime = .distantPast
        
        updatePhase(.idle)
        emitEvent(.stopped)
        
        logger.info("Stream stopped")
    }
    
    /// Pause playback
    public func pause() {
        playerEngine?.pause()
        updatePhase(.paused)
    }
    
    /// Resume playback
    public func resume() {
        playerEngine?.resume()
        updatePhase(.playing)
    }

    /// 백그라운드 복귀 시 재생 상태 점검 및 복구
    /// - 엔진이 에러 상태면 즉시 재연결
    /// - 엔진이 일시정지 상태면 resume 후 매니페스트 갱신
    /// - 재생 중이면 watchdog을 리셋하여 빠르게 stall 감지 재개
    /// - HLS 매니페스트 갱신 (CDN 토큰 만료 방지)
    public func recoverFromBackground() {
        guard _phase == .playing || _phase == .buffering else { return }
        guard let engine = playerEngine else { return }

        if engine.isInErrorState {
            triggerReconnect(reason: "background recovery: engine in error state")
        } else if !engine.isPlaying {
            // 엔진이 일시정지 상태 — resume 시도 후 watchdog으로 감시
            engine.resume()
            _stallCount = 0
            _lastWatchdogTime = -1
            _lastWatchdogDecodedFrames = -1
            // resume 후 매니페스트도 갱신 (CDN 토큰 만료 대비)
            Task { [weak self] in
                await self?.refreshMasterManifest()
                // resume 후 3초 뒤에도 재생되지 않으면 재연결
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if !engine.isPlaying && !engine.isInErrorState {
                    await self.triggerReconnect(reason: "background recovery: resume failed after 3s")
                }
            }
        } else {
            // watchdog 카운터 리셋 — 포그라운드 복귀 직후부터 stall 감지 재개
            _stallCount = 0
            _lastWatchdogTime = -1
            _lastWatchdogDecodedFrames = -1
            // 매니페스트 갱신 (CDN 토큰이 만료됐을 수 있음)
            Task { [weak self] in
                await self?.refreshMasterManifest()
            }
        }
    }

    /// Switch quality manually
    public func switchQuality(to variant: MasterPlaylist.Variant) async throws {
        guard let engine = playerEngine else { return }

        // 프록시 활성 시 프록시 경유 URL 사용 (Content-Type 수정 필요)
        let playURL = _isProxyActive ? streamProxy.proxyURL(from: variant.uri) : variant.uri

        // 모든 엔진: stop() 없이 바로 play()로 미디어 교체 — 재생 끊김 방지
        // VLCPlayerEngine: player.media = newMedia가 이전 미디어를 안전하게 교체
        // AVPlayerEngine: play() 내부에서 removeItemObservers() + replaceCurrentItem()으로
        //   이전 재생을 정리하므로 별도 stop() 불필요. stop()은 replaceCurrentItem(nil)로
        //   아이템을 완전히 제거하고 상태를 idle로 바꿔 멀티라이브 화질 전환 시 재생이 정지됨.
        try await engine.play(url: playURL)

        _currentQuality = qualityFromVariant(variant)

        emitEvent(.qualityChanged(_currentQuality!))
        logger.info("Quality switched to \(variant.qualityLabel)")
    }
    
    /// Get current snapshot
    public func snapshot() async -> StreamSnapshot {
        return StreamSnapshot(
            phase: _phase,
            quality: _currentQuality,
            latency: nil,
            bufferHealth: nil,
            playbackRate: Double(playerEngine?.rate ?? 1.0),
            uptime: uptime,
            timestamp: Date()
        )
    }
    
    // MARK: - ABR
    
    /// Record bandwidth sample for ABR
    public func recordBandwidthSample(bytesLoaded: Int, duration: TimeInterval) async {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: bytesLoaded,
            duration: duration
        )
        await abrController?.recordSample(sample)
        
        // Check if quality switch is recommended
        if let decision = await abrController?.recommendLevel() {
            switch decision {
            case .switchUp(let bandwidth, let reason):
                emitEvent(.abrDecision(.switchUp(toBandwidth: bandwidth, reason: reason)))
                if let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) {
                    try? await switchQuality(to: variant)
                }
            case .switchDown(let bandwidth, let reason):
                emitEvent(.abrDecision(.switchDown(toBandwidth: bandwidth, reason: reason)))
                if let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) {
                    try? await switchQuality(to: variant)
                }
            case .maintain:
                break
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func selectInitialQuality(from master: MasterPlaylist) -> MasterPlaylist.Variant {
        // If preferred quality specified, try to find it
        if let preferred = config.preferredQuality {
            if let match = master.variants.first(where: { $0.qualityLabel == preferred.displayName }) {
                return match
            }
        }
        
        // Default: middle quality
        let midIndex = master.variants.count / 2
        return master.variants[midIndex]
    }
    
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

    // MARK: - Stream Diagnostic (DEBUG)

    #if DEBUG
    /// CDN 스트림 진단 실행.
    /// M3U8 구조(EXT-X-MAP), 세그먼트 Content-Type, magic bytes를 분석하여
    /// 프록시 바이패스 가능 여부를 판정합니다.
    /// 참조: VLC_DIRECT_PLAYBACK_RESEARCH.md §8
    ///
    /// 사용:
    /// ```
    /// defaults write com.cview.v2 debug.bypassProxy -bool YES
    /// defaults write com.cview.v2 debug.diagnosticOnBypass -bool YES
    /// ```
    public func runStreamDiagnostic(url: URL? = nil) async {
        guard let targetURL = url ?? _streamURL else {
            logger.warning("[Diagnostic] No stream URL available")
            return
        }

        logger.info("[Diagnostic] Starting CDN stream diagnostic...")
        let diagnostic = ChzzkStreamDiagnostic()

        do {
            let result = try await diagnostic.runFullDiagnostic(masterURL: targetURL)

            // 콘솔 + 파일 출력
            let report = result.summary
            logger.info("[Diagnostic] Result:\n\(report, privacy: .public)")

            // /tmp/chzzk_diagnostic.txt에 결과 저장
            let reportPath = "/tmp/chzzk_diagnostic.txt"
            try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            logger.info("[Diagnostic] Report saved to \(reportPath, privacy: .public)")

            // 프록시 바이패스 판정 로그
            let feasibility = result.proxyBypassFeasibility
            if feasibility.feasible {
                logger.info("[Diagnostic] ✅ Proxy bypass appears FEASIBLE (confidence: \(feasibility.confidence.rawValue, privacy: .public))")
            } else {
                logger.warning("[Diagnostic] ❌ Proxy bypass NOT recommended (confidence: \(feasibility.confidence.rawValue, privacy: .public))")
            }
        } catch {
            logger.error("[Diagnostic] Failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
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
