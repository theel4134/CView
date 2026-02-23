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
            lowLatencyConfig: LowLatencyController.Configuration = .default,
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
    private let logger = AppLogger.player
    
    // Sub-controllers
    private let hlsParser = HLSManifestParser()
    private var abrController: ABRController?
    private var lowLatencyController: LowLatencyController?
    private let streamProxy = LocalStreamProxy()
    
    // State
    private var _phase: StreamPhase = .idle
    private var _masterPlaylist: MasterPlaylist?
    private var _currentQuality: StreamQualityInfo?
    private var _streamURL: URL?
    private var _startTime: Date?
    private var _isProxyActive = false
    
    // PDT-based latency provider (Method A)
    private var pdtProvider: PDTLatencyProvider?
    
    // Player reference (injected)
    private var playerEngine: (any PlayerEngineProtocol)?
    
    // Reconnection handler
    private var reconnectionHandler = PlaybackReconnectionHandler(config: .balanced)
    
    // Event stream
    private var eventContinuation: AsyncStream<StreamEvent>.Continuation?
    private var _eventStream: AsyncStream<StreamEvent>?
    
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
        // PlayerViewModel에서 coordinator를 교체 시 stopStream() 없이 해제될 수 있음.
        // 프록시 포트 누수 방지를 위해 deinit에서도 정리.
        streamProxy.stop()
        eventContinuation?.finish()
    }
    
    // MARK: - Setup
    
    /// Inject player engine
    public func setPlayerEngine(_ engine: any PlayerEngineProtocol) {
        self.playerEngine = engine
        configureEngineCallbacks(engine)
    }
    
    /// 엔진 콜백 연결 — AVPlayerEngine의 재연결 요청 수신
    private func configureEngineCallbacks(_ engine: any PlayerEngineProtocol) {
        if let avEngine = engine as? AVPlayerEngine {
            avEngine.onReconnectRequested = { [weak self] in
                Task { await self?.triggerReconnect(reason: "engine requested") }
            }
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
            // CDN Content-Type 버그 대응: 프록시 활성화
            // ex-nlive-streaming.navercdn.com이 fMP4를 video/MP2T로 응답
            // → VLC adaptive demux 파싱 실패
            var playbackURL = url
            if LocalStreamProxy.needsProxy(for: url) {
                if let host = url.host {
                    do {
                        try streamProxy.start(for: host)
                        playbackURL = streamProxy.proxyURL(from: url)
                        _isProxyActive = true
                        logger.info("CDN proxy active: \(host, privacy: .public) → localhost:\(self.streamProxy.port, privacy: .public)")
                    } catch {
                        logger.warning("CDN proxy failed, direct connection: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            
            try await playerEngine?.play(url: playbackURL)
            
            updatePhase(.playing)
            
            // 백그라운드에서 매니페스트 파싱 (품질 정보 UI용)
            loadManifestInfo(from: url)
            
            // 저지연 싱크: 백그라운드에서 비동기 실행 (play() 직후 바로 반환, 화면 출력 차단 안 함)
            // PDT 안정화 루프(최대 6초)가 startStream을 블로킹하던 문제 해결
            if config.enableLowLatency {
                Task { [weak self] in await self?.startLowLatencySync() }
            }
            
            logger.info("Stream started: \(url.absoluteString, privacy: .public)")
            
        } catch {
            updatePhase(.error(error.localizedDescription))
            throw error
        }
    }
    
    /// 백그라운드에서 매니페스트를 파싱하여 품질 정보 수집 (재생에는 영향 없음)
    private func loadManifestInfo(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                let content = String(data: data, encoding: .utf8) ?? ""
                
                if content.contains("#EXT-X-STREAM-INF") {
                    let master = try await self.hlsParser.parseMasterPlaylist(content: content, baseURL: url)
                    await self.updateMasterPlaylist(master)
                }
            } catch {
                await self.logger.debug("Manifest info fetch skipped: \(error.localizedDescription)")
            }
        }
    }
    
    /// 매니페스트 정보 업데이트 (actor-isolated)
    private func updateMasterPlaylist(_ master: MasterPlaylist) async {
        _masterPlaylist = master
        await abrController?.setLevels(master.variants)
        
        // 최고 품질을 현재 품질로 표시 (VLC가 자동 선택)
        if let best = master.variants.first {
            _currentQuality = qualityFromVariant(best)
            emitEvent(.qualitySelected(_currentQuality!))
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
    
    /// Switch quality manually
    public func switchQuality(to variant: MasterPlaylist.Variant) async throws {
        guard let engine = playerEngine else { return }
        
        // Stop current playback
        engine.stop()
        
        // Play new quality
        try await engine.play(url: variant.uri)
        
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
    
    private func startLowLatencySync() async {
        guard let controller = lowLatencyController else { return }
        
        await controller.setOnRateChange { [weak self] rate in
            Task { [weak self] in
                await self?.playerEngine?.setRate(Float(rate))
            }
        }
        
        await controller.setOnSeekRequired { [weak self] targetLatency in
            Task { [weak self] in
                guard let engine = await self?.playerEngine else { return }
                let seekTarget = engine.duration - targetLatency
                if seekTarget > 0 {
                    engine.seek(to: seekTarget)
                }
            }
        }
        
        // Method A: 미디어 플레이리스트 URL 확보 (마스터 플레이리스트 파싱)
        // loadManifestInfo가 백그라운드 Task이므로 직접 fetch해서 타이밍 문제 해결
        let mediaPlaylistURL = await resolveMediaPlaylistURL()
        
        if let mediaPlaylistURL {
            let provider = PDTLatencyProvider(playlistURL: mediaPlaylistURL)
            await provider.start()
            pdtProvider = provider
            
            // PDT 초기 안정화 대기 (최대 6초, 값이 준비되면 즉시 진행)
            for _ in 0..<6 {
                if await provider.isReady { break }
                try? await Task.sleep(for: .seconds(1))
            }
            
            logger.info("PDT sync active: \(mediaPlaylistURL.lastPathComponent, privacy: .public)")
            
            await controller.startSync { [weak provider, weak self] in
                // PDT 기반 실제 레이턴시 (Method A 우선)
                if let pdtLatency = await provider?.currentLatency() {
                    return pdtLatency
                }
                // Fallback: VLC 버퍼 내부 duration-currentTime (PDT 없을 때)
                return await self?.vlcBufferLatency()
            }
        } else {
            // 마스터 플레이리스트 fetch 실패 - VLC 버퍼 fallback
            logger.info("Media playlist URL unavailable, using VLC buffer latency")
            await controller.startSync { [weak self] in
                await self?.vlcBufferLatency()
            }
        }
    }
    
    /// 마스터 플레이리스트에서 첫 번째 미디어 플레이리스트 URL을 가져옴
    /// 이미 파싱된 경우 즉시 반환, 없으면 _streamURL에서 직접 fetch
    private func resolveMediaPlaylistURL() async -> URL? {
        // 이미 파싱된 경우 즉시 반환
        if let url = _masterPlaylist?.variants.first?.uri {
            return url
        }
        // 직접 fetch
        guard let streamURL = _streamURL else { return nil }
        do {
            var request = URLRequest(url: streamURL)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            if content.contains("#EXT-X-STREAM-INF") {
                let master = try hlsParser.parseMasterPlaylist(content: content, baseURL: streamURL)
                // 파싱 결과로 내부 상태도 업데이트 (loadManifestInfo 중복 방지 효과)
                if _masterPlaylist == nil {
                    await updateMasterPlaylist(master)
                }
                return master.variants.first?.uri
            } else if content.contains("#EXTINF") {
                // 이미 미디어 플레이리스트인 경우
                return streamURL
            }
        } catch {
            logger.warning("Master playlist fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
    
    /// VLC 내부 버퍼 기반 레이턴시 (PDT 없을 때 fallback)
    private func vlcBufferLatency() async -> TimeInterval? {
        guard let engine = playerEngine else { return nil }
        guard engine.isPlaying else { return nil }
        let duration = engine.duration
        let current = engine.currentTime
        guard duration > 0, current > 0 else { return nil }
        let latency = duration - current
        guard latency > 0, latency < 60 else { return nil }
        return latency
    }
    
    // MARK: - Reconnection

    /// 재연결 트리거 — 현재 URL로 재시도
    /// - Parameter reason: 로그용 재연결 원인
    func triggerReconnect(reason: String = "") {
        guard let url = _streamURL else {
            logger.warning("StreamCoordinator: 재연결 실패 — 저장된 URL 없음")
            return
        }
        // 이미 재연결 중이면 무시
        guard _phase != .reconnecting else { return }
        updatePhase(.reconnecting)
        logger.info("StreamCoordinator: 재연결 시작 (\(reason))")

        Task { [weak self] in
            await self?.reconnectionHandler.startReconnecting(
                onAttempt: { [weak self] attempt, delay in
                    guard let self else { return }
                    await self.logger.info("StreamCoordinator: 재시도 \(attempt) — \(String(format: "%.1f", delay))초 대기")
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    await self.performReconnectAttempt(url: url)
                },
                onExhausted: { [weak self] in
                    await self?.handleReconnectExhausted()
                }
            )
        }
    }

    /// 단일 재연결 시도 — play()를 재호출하여 스트림 재시작
    private func performReconnectAttempt(url: URL) async {
        guard let engine = playerEngine else { return }
        engine.stop()
        do {
            try await engine.play(url: url)
            await reconnectionHandler.handleSuccess()
            updatePhase(.playing)
            logger.info("StreamCoordinator: 재연결 성공")
        } catch {
            logger.warning("StreamCoordinator: 재연결 시도 실패 — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 재연결 시도 모두 소진
    private func handleReconnectExhausted() {
        updatePhase(.error("재연결 최대 횟수 초과"))
        emitEvent(.error("재연결 최대 횟수 초과"))
        logger.error("StreamCoordinator: 재연결 소진")
    }
    
    private func updatePhase(_ newPhase: StreamPhase) {
        _phase = newPhase
        emitEvent(.phaseChanged(newPhase))
    }
    
    private func qualityFromVariant(_ variant: MasterPlaylist.Variant) -> StreamQualityInfo {
        StreamQualityInfo(
            name: variant.qualityLabel,
            resolution: variant.resolution,
            bandwidth: variant.bandwidth
        )
    }
    
    private func emitEvent(_ event: StreamEvent) {
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
    case stopped
}

// MARK: - Stream Coordinator Error

public enum StreamCoordinatorError: Error, Sendable {
    case qualityNotFound
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
