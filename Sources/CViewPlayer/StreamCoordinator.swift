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

    #if DEBUG
    /// 프록시 바이패스 실험 플래그.
    /// `defaults write com.cview.v2 debug.bypassProxy -bool YES` 로 활성화.
    /// VLC가 CDN에 직접 연결하여 재생 가능 여부를 검증하는 데 사용.
    /// 참조: VLC_DIRECT_PLAYBACK_RESEARCH.md §8.2
    private nonisolated var _bypassProxy: Bool {
        UserDefaults.standard.bool(forKey: "debug.bypassProxy")
    }
    /// 프록시 바이패스 시 자동 CDN 진단 실행 여부
    private nonisolated var _diagnosticOnBypass: Bool {
        UserDefaults.standard.bool(forKey: "debug.diagnosticOnBypass")
    }
    #endif
    
    // 1080p+ABR 하이브리드 상태
    private var _preferredQualityVariant: MasterPlaylist.Variant?  // 원래 선호 화질 (복귀 목표)
    private var _isQualityDegraded: Bool = false  // 현재 화질 하향 상태 여부
    private var _qualityRecoveryTask: Task<Void, Never>?
    
    // 매니페스트 주기적 갱신 (토큰 리프레시 + variant URL 갱신)
    private var _manifestRefreshTask: Task<Void, Never>?
    private var _currentVariantURL: URL?  // VLC에 전달한 현재 variant URL
    
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
            
            // VLC 복구 시 신선한 variant URL 제공 콜백
            // VLC의 attemptRecovery()가 만료된 URL로 복구하는 문제 해결
            vlcEngine.onRecoveryURLRefresh = { [weak self] in
                guard let self else { return nil }
                return await self.refreshVariantURLForRecovery()
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
            // CDN Content-Type 버그 대응: 모든 엔진에 프록시 활성화
            // ex-nlive-streaming.navercdn.com이 fMP4(.m4s/.m4v) 세그먼트를
            // Content-Type: video/MP2T (MPEG-TS)로 잘못 응답.
            //
            // VLC adaptive demux 역시 HTTP 응답의 Content-Type을 기반으로
            // demux 모듈을 선택한다. video/MP2T를 받으면 MP4→TS 포맷 전환이
            // 발생하여 "does not look like a TS stream" 경고 + fMP4 박스를 garbage로
            // 스킵 → 영상/음성 출력 없음 (VLC debug log 확인됨).
            //
            // 프록시는 M3U8 내 세그먼트 URL을 모두 localhost로 재작성하므로
            // VLC가 세그먼트를 프록시 경유로 가져올 때 Content-Type: video/mp4를
            // 수신하여 mp4 demux 모드가 유지된다.
            var playbackURL = url
            let isVLCEngine = playerEngine is VLCPlayerEngine

            #if DEBUG
            let shouldBypassProxy = _bypassProxy
            #else
            let shouldBypassProxy = false
            #endif

            if shouldBypassProxy {
                // 🔬 프록시 바이패스 실험 모드
                // VLC가 CDN에 직접 연결하여 EXT-X-MAP 기반 포맷 인식으로
                // Content-Type 문제를 우회할 수 있는지 검증.
                // 활성화: defaults write com.cview.v2 debug.bypassProxy -bool YES
                // 비활성화: defaults delete com.cview.v2 debug.bypassProxy
                // VLC 로그: tail -f /tmp/vlc_internal.log | grep -i "format\|demux\|content\|adaptive"
                logger.warning("⚠️ PROXY BYPASS MODE — CDN 직접 연결 (실험)")
                _isProxyActive = false

                #if DEBUG
                // 바이패스 시 자동 CDN 진단 실행 (선택)
                if _diagnosticOnBypass {
                    Task { [weak self, url] in
                        guard let self else { return }
                        await self.runStreamDiagnostic(url: url)
                    }
                }
                #endif
            } else {
                if LocalStreamProxy.needsProxy(for: url) {
                    if let host = url.host {
                        do {
                            try await streamProxy.start(for: host)
                            playbackURL = streamProxy.proxyURL(from: url)
                            _isProxyActive = true
                            let engineLabel = isVLCEngine ? "VLC" : "AVPlayer"
                            logger.info("CDN proxy active (\(engineLabel, privacy: .public)): \(host, privacy: .public) → localhost:\(self.streamProxy.port, privacy: .public)")
                        } catch {
                            logger.warning("CDN proxy failed, direct connection: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }

            if isVLCEngine {
                // VLC: 마스터 매니페스트 파싱 → 최고 해상도(1080p) variant URL 직접 전달
                // VLC adaptive 모듈의 ABR은 최저 해상도(256x144)부터 올라가므로
                // 직접 1080p variant URL을 전달하여 즉시 최고 화질로 재생.
                // variant URL(미디어 플레이리스트)을 전달하면 VLC가 ABR 없이 해당 해상도로 고정.
                logger.info("VLC engine: resolving highest quality variant...")
                async let cdnWarmup: Void = warmUpCDNConnection(url: url)
                async let variantResolve = resolveHighestQualityVariant(from: url)
                _ = await cdnWarmup
                if let variantURL = await variantResolve {
                    // variant URL을 프록시 경유로 변환 (Content-Type 보정)
                    if _isProxyActive {
                        playbackURL = streamProxy.proxyURL(from: variantURL)
                    } else {
                        playbackURL = variantURL
                    }
                    logger.info("VLC: Using highest variant URL directly (bypassing ABR)")
                }
                // variant 해석 실패 시 playbackURL(master playlist)을 그대로 사용
            }
            
            try await playerEngine?.play(url: playbackURL)
            updatePhase(.playing)
            
            // 백그라운드에서 매니페스트 파싱 (품질 정보 UI용)
            // VLC의 경우 이미 resolveHighestQualityVariant에서 파싱 완료되었을 수 있음
            if _masterPlaylist == nil {
                loadManifestInfo(from: url)
            }
            
            // 매니페스트 주기적 갱신 타이머 시작 (VLC 토큰 리프레시 + variant URL 갱신)
            if isVLCEngine {
                _currentVariantURL = playbackURL
                startManifestRefreshTimer()
            }
            
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
            
            let (data, _) = try await URLSession.shared.data(for: request)
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
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("CDN 워밍 완료: \(url.host ?? "unknown") → HTTP \(httpResponse.statusCode)")
            }
        } catch {
            // 워밍 실패는 비핵심 — 무시하고 정상 재생 진행
            logger.debug("CDN 워밍 실패 (무시): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Manifest Refresh Timer (Token Refresh + Variant URL Update)

    /// 매니페스트 주기적 갱신 타이머 시작 (프로파일별 갱신 주기)
    /// 치지직 CDN URL의 토큰/서명이 만료되면 variant URL이 무효화되므로
    /// 주기적으로 마스터 매니페스트를 재파싱하여 신선한 variant URL을 유지합니다.
    /// lowLatency=15초, normal=20초, highBuffer=30초 주기
    private func startManifestRefreshTimer() {
        _manifestRefreshTask?.cancel()
        
        // 프로파일에서 갱신 주기 취득 (actor-isolated 컨텍스트에서 미리 읽기)
        let refreshInterval: Int
        if let vlcEngine = self.playerEngine as? VLCPlayerEngine {
            refreshInterval = vlcEngine.streamingProfile.manifestRefreshInterval
        } else {
            refreshInterval = 20  // 기본 20초
        }
        
        _manifestRefreshTask = Task { [weak self] in
            // 초기 대기 (최초 재생 직후에는 굳이 갱신 필요 없음)
            try? await Task.sleep(for: .seconds(refreshInterval))
            
            while !Task.isCancelled {
                guard let self else { break }
                await self.refreshMasterManifest()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    /// 마스터 매니페스트를 다시 다운로드하여 variant URL을 갱신합니다.
    /// 토큰 리프레시 + variant 목록 업데이트 + VLC 엔진 URL 동기화.
    private func refreshMasterManifest() async {
        guard let streamURL = _streamURL else { return }
        
        do {
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 5
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            request.cachePolicy = .reloadIgnoringLocalCacheData  // 캐시 무시
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            guard content.contains("#EXT-X-STREAM-INF") else { return }
            
            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: streamURL)
            
            // 매니페스트 업데이트
            _masterPlaylist = master
            await abrController?.setLevels(master.variants)
            
            // 1080p variant URL 갱신
            let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }
            let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                ?? sortedVariants.first
            
            if let variant = target {
                let newURL = variant.uri
                let oldURL = _currentVariantURL
                _currentVariantURL = newURL
                _preferredQualityVariant = variant
                _currentQuality = qualityFromVariant(variant)

                // VLC 엔진의 복구용 URL도 신선한 것으로 동기화
                // 프록시가 활성화된 경우 복구 URL도 프록시 경유로 설정
                if let vlcEngine = playerEngine as? VLCPlayerEngine {
                    let recoveryURL = _isProxyActive ? streamProxy.proxyURL(from: newURL) : newURL
                    vlcEngine.updateCurrentURL(recoveryURL)
                }

                if oldURL != newURL {
                    logger.info("매니페스트 갱신: variant URL 변경됨 (토큰 리프레시)")
                } else {
                    logger.debug("매니페스트 갱신: variant URL 동일 (토큰 유효)")
                }
            }
        } catch {
            logger.debug("매니페스트 갱신 실패 (무시): \(error.localizedDescription)")
        }
    }

    /// VLC 복구 시 신선한 variant URL을 반환합니다.
    /// 복구 직전에 매니페스트를 재파싱하여 만료되지 않은 토큰으로 variant URL을 제공.
    /// 프록시가 활성화된 경우 프록시 경유 URL을 반환합니다.
    private func refreshVariantURLForRecovery() async -> URL? {
        // 먼저 매니페스트 갱신 시도
        await refreshMasterManifest()

        // 갱신된 variant URL 반환 (프록시 활성 시 프록시 URL)
        if let url = _currentVariantURL {
            let finalURL = _isProxyActive ? streamProxy.proxyURL(from: url) : url
            logger.info("복구용 variant URL 갱신 완료: \(finalURL.lastPathComponent, privacy: .public)")
            return finalURL
        }

        return nil
    }

    /// 백그라운드에서 매니페스트를 파싱하여 품질 정보 수집 (재생에는 영향 없음)
    private func loadManifestInfo(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
                
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
        _preferredQualityVariant = nil
        _isQualityDegraded = false
        _qualityRecoveryTask?.cancel()
        _qualityRecoveryTask = nil
        _manifestRefreshTask?.cancel()
        _manifestRefreshTask = nil
        _currentVariantURL = nil
        
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

        // 프록시 활성 시 프록시 경유 URL 사용 (Content-Type 수정 필요)
        let playURL = _isProxyActive ? streamProxy.proxyURL(from: variant.uri) : variant.uri
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
                CommonHeaders.safariUserAgent,
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
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
    public func triggerReconnect(reason: String = "") {
        guard let rawURL = _streamURL else {
            logger.warning("StreamCoordinator: 재연결 실패 — 저장된 URL 없음")
            return
        }
        // 이미 재연결 중이면 무시
        guard _phase != .reconnecting else { return }
        updatePhase(.reconnecting)
        logger.info("StreamCoordinator: 재연결 시작 (\(reason))")

        // 프록시 활성 시 프록시 경유 URL로 재연결
        let url = _isProxyActive ? streamProxy.proxyURL(from: rawURL) : rawURL

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
