// MARK: - MetricsAPIClient.swift
// 메트릭 서버(cv.dododo.app) API 클라이언트 — Actor 기반

import Foundation
import CViewCore

/// 메트릭 서버 API 클라이언트
/// - ChzzkResponse 래퍼 없이 직접 JSON 디코딩
/// - 인증 불필요 (public API)
/// - 서버 다운 시 non-blocking (옵셔널 리턴)
public actor MetricsAPIClient {
    
    private let session: URLSession
    private var baseURL: URL
    private let cache: ResponseCache
    private var maxRetries: Int = 2
    
    public init(
        baseURL: URL = URL(string: "https://cv.dododo.app")!,
        cache: ResponseCache = ResponseCache()
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
        self.cache = cache
    }
    
    /// 섛버 URL 동적 변경
    public func updateBaseURL(_ url: URL) {
        self.baseURL = url
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
        // 캐시 확인
        let cacheKey = "metrics:" + endpoint.path + (endpoint.queryItems?.description ?? "")
        if case .returnCacheElseLoad(let ttl) = endpoint.cachePolicy {
            if let cached: T = await cache.get(key: cacheKey, ttl: ttl) {
                return cached
            }
        }
        
        // URL 구성
        var urlComponents = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
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
        
        // 재시도 루프
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
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
        var urlComponents = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems

        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }
    
    /// POST 요청 (응답 무시)
    public func postIgnoringResponse(_ endpoint: MetricsEndpoint) async throws {
        var urlComponents = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems
        
        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = endpoint.body
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
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
