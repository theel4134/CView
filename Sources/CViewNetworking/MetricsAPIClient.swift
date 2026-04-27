// MARK: - MetricsAPIClient.swift
// 메트릭 서버(cv.dododo.app) API 클라이언트 — Actor 기반

import Foundation
import CViewCore

/// 메트릭 서버 API 클라이언트
/// - ChzzkResponse 래퍼 없이 직접 JSON 디코딩
/// - POST/PUT/DELETE는 JWT 인증 필요
/// - 서버 다운 시 non-blocking (옵셔널 리턴)
public actor MetricsAPIClient {
    
    private let session: URLSession
    private var baseURL: URL
    private var directBaseURL: URL   // 메트릭 서버 직접 (포트 8443)
    private let cache: ResponseCache
    private var maxRetries: Int = 2
    
    // MARK: - JWT 인증
    private var jwtToken: String?
    private var jwtExpiresAt: Date?
    private let deviceId: String
    private let appSecret: String
    
    public init(
        baseURL: URL = URL(string: MetricsSettings.defaultServerURL)!,
        directBaseURL: URL = URL(string: MetricsSettings.defaultDirectServerURL)!,
        cache: ResponseCache = ResponseCache(),
        appSecret: String = Bundle.main.object(forInfoDictionaryKey: "METRICS_APP_SECRET") as? String ?? "dev-app-secret-change-in-production"
    ) {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        config.timeoutIntervalForRequest = MetricsNetDefaults.requestTimeout
        config.timeoutIntervalForResource = MetricsNetDefaults.resourceTimeout
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        
        self.session = URLSession(configuration: config)
        self.baseURL = baseURL
        self.directBaseURL = directBaseURL
        self.cache = cache
        self.appSecret = appSecret
        
        // 고유 device ID 생성 (앱 생명주기 동안 유지)
        if let stored = UserDefaults.standard.string(forKey: "cview_device_id") {
            self.deviceId = stored
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "cview_device_id")
            self.deviceId = newId
        }
    }
    
    /// 서버 URL 동적 변경
    public func updateBaseURL(_ url: URL) {
        self.baseURL = url
        // directBaseURL은 포트 8443으로 재구성
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.port = 8443
        self.directBaseURL = components.url ?? url
    }
    
    // MARK: - JWT Token Management
    
    /// JWT 토큰 발급 (POST /api/auth/token)
    public func fetchJWT() async {
        struct TokenRequest: Encodable {
            let device_id: String
            let app_secret: String
        }
        struct TokenResponse: Decodable {
            let token: String
            let expires_in: Int
        }
        
        let url = baseURL.appending(path: "/api/auth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            TokenRequest(device_id: deviceId, app_secret: appSecret)
        )
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                Log.network.error("JWT 발급 실패 — HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.jwtToken = tokenResponse.token
            self.jwtExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
            Log.network.info("JWT 발급 완료 — 만료: \(tokenResponse.expires_in)초")
        } catch {
            Log.network.error("JWT 발급 오류: \(error.localizedDescription)")
        }
    }
    
    /// 유효한 JWT 토큰 반환 (만료 임박 시 재발급)
    private func validToken() async -> String? {
        // 만료 5분 전에 재발급
        if let token = jwtToken, let exp = jwtExpiresAt, exp.timeIntervalSinceNow > 300 {
            return token
        }
        await fetchJWT()
        return jwtToken
    }
    
    /// 요청에 JWT 인증 헤더 적용
    private func applyAuth(to request: inout URLRequest, endpoint: MetricsEndpoint) async {
        guard endpoint.requiresAuth else { return }
        if let token = await validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// 연결 테스트 (헬스체크 엔드포인트)
    /// - Returns: (success: Bool, latencyMs: Double, message: String)
    public func testConnection() async -> (success: Bool, latencyMs: Double, message: String) {
        let start = Date()
        do {
            let health = try await fetchHealth()
            let ms = Date().timeIntervalSince(start) * 1000
            let uptime = health.uptime.map { String(format: "%.0f시간", $0 / 3600) } ?? ""
            return (true, ms, "\(health.status) \(uptime)")
        } catch {
            let ms = Date().timeIntervalSince(start) * 1000
            return (false, ms, error.localizedDescription)
        }
    }

    // MARK: - Generic Request
    
    /// 메트릭 서버에 요청 (직접 JSON 디코딩, ChzzkResponse 래퍼 없음)
    public func request<T: Decodable & Sendable>(
        _ endpoint: MetricsEndpoint,
        as type: T.Type
    ) async throws -> T {
        // [Opt-N-3] 캐시 키 결정적 직렬화 — queryItems.description은 순서 비결정적이어서 cache miss 유발
        let queryString = endpoint.queryItems?
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&") ?? ""
        let cacheKey = "metrics:" + endpoint.path + "?" + queryString
        if case .returnCacheElseLoad(let ttl) = endpoint.cachePolicy {
            if let cached: T = await cache.get(key: cacheKey, ttl: ttl) {
                return cached
            }
        }
        
        // URL 구성 — nginx /api/stats/ 라우팅 충돌 엔드포인트는 직접 포트 사용
        let effectiveBaseURL = endpoint.usesDirectMetricsServer ? directBaseURL : baseURL
        var urlComponents = URLComponents(url: effectiveBaseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems
        
        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }
        
        // 요청 구성
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        await applyAuth(to: &request, endpoint: endpoint)
        
        // 재시도 루프
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                // 401: 토큰 재발급 후 1회 재시도
                if httpResponse.statusCode == 401 && endpoint.requiresAuth && attempt == 0 {
                    self.jwtToken = nil
                    await applyAuth(to: &request, endpoint: endpoint)
                    continue
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode >= 500 && attempt < maxRetries - 1 {
                        try await Task.sleep(for: .seconds(Double(attempt + 1)))
                        continue
                    }
                    throw APIError.httpError(statusCode: httpResponse.statusCode)
                }
                
                let decoded = try JSONDecoder().decode(T.self, from: data)
                
                // 캐시 저장
                if case .returnCacheElseLoad = endpoint.cachePolicy {
                    await cache.set(key: cacheKey, value: decoded)
                }
                
                return decoded
                
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1)))
                    continue
                }
            } catch {
                throw error
            }
        }
        
        throw lastError ?? APIError.networkError("Request failed after retries")
    }
    
    /// POST 요청 (별도 body + 응답 디코딩)
    /// endpoint의 body 대신 외부 전달 body를 사용한다.
    public func post<Req: Encodable & Sendable, Res: Decodable & Sendable>(
        _ endpoint: MetricsEndpoint,
        body: Req,
        as type: Res.Type
    ) async throws -> Res {
        let effectiveBaseURL = endpoint.usesDirectMetricsServer ? directBaseURL : baseURL
        var urlComponents = URLComponents(url: effectiveBaseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems

        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        await applyAuth(to: &request, endpoint: endpoint)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // 401: 토큰 재발급 후 1회 재시도
        if httpResponse.statusCode == 401 && endpoint.requiresAuth {
            self.jwtToken = nil
            await applyAuth(to: &request, endpoint: endpoint)
            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHttp = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(retryHttp.statusCode) else {
                throw APIError.httpError(statusCode: retryHttp.statusCode)
            }
            return try JSONDecoder().decode(Res.self, from: retryData)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }
    
    /// POST 요청 (응답 무시)
    public func postIgnoringResponse(_ endpoint: MetricsEndpoint) async throws {
        let effectiveBaseURL = endpoint.usesDirectMetricsServer ? directBaseURL : baseURL
        var urlComponents = URLComponents(url: effectiveBaseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems
        
        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = endpoint.body
        await applyAuth(to: &request, endpoint: endpoint)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // 401: 토큰 재발급 후 1회 재시도
        if httpResponse.statusCode == 401 && endpoint.requiresAuth {
            self.jwtToken = nil
            await applyAuth(to: &request, endpoint: endpoint)
            let (_, retryResponse) = try await session.data(for: request)
            guard let retryHttp = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(retryHttp.statusCode) else {
                throw APIError.httpError(statusCode: retryHttp.statusCode)
            }
            return
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Convenience Methods (GET)
    
    /// 서버 전체 통계 (legacy /api/stats)
    public func fetchStats() async throws -> MetricsServerStats {
        try await request(.stats, as: MetricsServerStats.self)
    }
    
    /// 서버 통계 개요 (v4.5+ /api/stats/overview)
    public func fetchOverview() async throws -> MetricsOverviewResponse {
        try await request(.statsOverview, as: MetricsOverviewResponse.self)
    }
    
    /// 서버 시스템 정보 (v4.5+ /api/stats/system)
    public func fetchSystem() async throws -> MetricsSystemResponse {
        try await request(.statsSystem, as: MetricsSystemResponse.self)
    }
    
    /// 카테고리별 통계 (v4.5+ /api/stats/categories)
    public func fetchCategories() async throws -> MetricsCategoriesResponse {
        try await request(.statsCategories, as: MetricsCategoriesResponse.self)
    }
    
    /// 채널 랭킹 (v4.5+ /api/stats/channels/ranking)
    public func fetchChannelRanking(sort: String = "viewers", limit: Int = 10) async throws -> MetricsChannelRankingResponse {
        try await request(.statsChannelRanking(sort: sort, limit: limit), as: MetricsChannelRankingResponse.self)
    }
    
    /// 서버 헬스체크
    public func fetchHealth() async throws -> MetricsHealthResponse {
        try await request(.health, as: MetricsHealthResponse.self)
    }
    
    /// 채널별 통계
    public func fetchChannelStats(channelId: String) async throws -> ChannelMetricsDetail {
        try await request(.channelStats(channelId: channelId), as: ChannelMetricsDetail.self)
    }
    
    /// 채널 실시간 레이턴시
    public func fetchRealLatency(channelId: String) async throws -> RealLatencyResponse {
        try await request(.channelRealLatency(channelId: channelId), as: RealLatencyResponse.self)
    }
    
    /// 채널 동기화 추천
    public func fetchSyncRecommendation(channelId: String, appLatency: Double? = nil) async throws -> SyncRecommendationResponse {
        try await request(.channelSyncRecommendation(channelId: channelId, appLatency: appLatency), as: SyncRecommendationResponse.self)
    }
    
    /// 채널 PDT 동기화 정보
    public func fetchPDTSync(channelId: String) async throws -> PDTSyncResponse {
        try await request(.channelPDTSync(channelId: channelId), as: PDTSyncResponse.self)
    }
    
    /// 활성 앱 채널 목록
    public func fetchActiveAppChannels() async throws -> ActiveAppChannelsResponse {
        try await request(.activeAppChannels, as: ActiveAppChannelsResponse.self)
    }
    
    // MARK: - Convenience Methods (POST)
    
    /// 앱 레이턴시 전송
    public func sendAppLatency(_ payload: AppLatencyPayload) async throws -> AppLatencyPostResponse {
        try await request(.postAppLatency(payload), as: AppLatencyPostResponse.self)
    }
    
    /// PDT 동기화 데이터 전송
    public func sendPDTSync(_ payload: PDTSyncPayload) async throws -> PDTSyncResponse {
        try await request(.postPDTSync(payload), as: PDTSyncResponse.self)
    }
    
    /// 채널 활성화 (서버에 채널 등록)
    public func activateChannel(_ payload: ChannelActivatePayload) async throws -> ChannelActivateResponse {
        try await request(.addChannel(payload), as: ChannelActivateResponse.self)
    }
    
    /// 채널 비활성화 (서버에서 채널 제거)
    public func deactivateChannel(channelId: String) async throws {
        try await postIgnoringResponse(.removeChannel(channelId: channelId))
    }
    
    /// 채널 핑 (활성 유지 — 간단 메트릭 전송으로 대체)
    public func pingChannel(channelId: String) async throws {
        try await postIgnoringResponse(.pingChannel(channelId: channelId))
    }
    
    /// 범용 메트릭 전송 (/api/metrics — 서버 v3 호환)
    public func sendMetrics(_ payload: AppLatencyPayload) async throws {
        try await postIgnoringResponse(.postMetrics(payload))
    }
    
    // MARK: - CView App Integration
    
    /// CView 앱 연결 등록 — 서버에 클라이언트 등록 및 초기 동기화 데이터 수신
    public func cviewConnect(_ payload: CViewConnectPayload) async throws -> CViewConnectResponse {
        try await request(.cviewConnect(payload), as: CViewConnectResponse.self)
    }
    
    /// CView 앱 연결 해제
    public func cviewDisconnect(_ payload: CViewDisconnectPayload) async throws {
        try await postIgnoringResponse(.cviewDisconnect(payload))
    }
    
    /// CView 하트비트 — 메트릭 전송 + 양방향 동기화 데이터 수신
    public func cviewHeartbeat(_ payload: CViewHeartbeatPayload) async throws -> CViewHeartbeatResponse {
        try await request(.cviewHeartbeat(payload), as: CViewHeartbeatResponse.self)
    }
    
    /// CView 채널 통합 통계 조회
    public func cviewChannelStats(channelId: String) async throws -> CViewChannelStatsResponse {
        try await request(.cviewChannelStats(channelId: channelId), as: CViewChannelStatsResponse.self)
    }
    
    /// CView 동기화 상태 조회
    public func cviewSyncStatus(channelId: String) async throws -> CViewSyncStatusResponse {
        try await request(.cviewSyncStatus(channelId: channelId), as: CViewSyncStatusResponse.self)
    }

    /// PDT 기반 웹/앱 정밀 동기화 비교 (P0 / 2026-04-25)
    ///
    /// `cviewSyncStatus` 보다 정밀한 비교 — 웹/앱 모두 `EXT-X-PROGRAM-DATE-TIME`
    /// 기반 latency 를 치지직 서버 시간으로 정규화해 driftMs 를 반환한다.
    /// 정밀 제어 모드의 단일 진실 공급원으로 사용한다.
    public func pdtComparison(channelId: String) async throws -> PDTComparisonResponse {
        try await request(.pdtComparison(channelId: channelId), as: PDTComparisonResponse.self)
    }
    
    /// CView 채팅 메시지 서버 중계
    public func cviewRelayChatMessage(_ payload: CViewChatRelayPayload) async throws -> CViewChatRelayResponse {
        try await request(.cviewChatRelay(payload), as: CViewChatRelayResponse.self)
    }
    
    // MARK: - Hybrid Sync
    
    /// 하이브리드 동기화 하트비트 전송
    public func hybridHeartbeat(_ payload: HybridHeartbeatPayload) async throws -> HybridHeartbeatResponse {
        try await request(.hybridHeartbeat(payload), as: HybridHeartbeatResponse.self)
    }
    
    // MARK: - Auth Cookie Sync
    
    /// NID 쿠키를 대시보드 서버에 동기화
    public func syncAuthCookies(_ payload: AuthCookieSyncPayload) async throws -> AuthCookieSyncResponse {
        try await request(.syncAuthCookies(payload), as: AuthCookieSyncResponse.self)
    }
}
