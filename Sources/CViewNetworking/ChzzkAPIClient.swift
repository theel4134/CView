// MARK: - CViewNetworking/ChzzkAPIClient.swift
// Actor 기반 API 클라이언트 — Swift 6 Concurrency 완전 호환

import Foundation
import CViewCore

public extension Notification.Name {
    /// 서버가 401로 응답하여 로그인 세션이 만료됐을 때 발송
    static let chzzkSessionExpired = Notification.Name("com.cview.sessionExpired")
}

/// 치지직 API 클라이언트 (actor 기반)
public actor ChzzkAPIClient: APIClientProtocol {
    let session: URLSession
    private let baseURL: URL
    let authProvider: (any AuthTokenProvider)?
    private let cache: ResponseCache
    private var maxRetries: Int = 3
    /// 캐시 퍼지 주기 Task — deinit 시 취소
    private let cachePurgeTask: Task<Void, Never>
    /// SSL 핀닝 델리게이트 — URLSession이 약한 참조하므로 강한 참조 유지 필요
    private let pinningDelegate: CertificatePinningDelegate
    /// Game API 기본 URL (chat access token 등)
    static let gameAPIBaseURL = URL(string: "https://comm-api.game.naver.com/nng_main")!

    public init(
        authProvider: (any AuthTokenProvider)? = nil,
        cache: ResponseCache = ResponseCache(),
        baseURL: URL = URL(string: "https://api.chzzk.naver.com")!,
        pinningConfiguration: CertificatePinningConfiguration = CertificatePinningConfiguration()
    ) {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": CommonHeaders.chromeUserAgent,
            "Accept": "application/json",
            "Accept-Language": "ko-KR,ko;q=0.9",
            "Accept-Encoding": "gzip, deflate, br",
            "Referer": "https://chzzk.naver.com",
            "Origin": "https://chzzk.naver.com",
        ]
        config.timeoutIntervalForRequest = APIDefaults.requestTimeout
        config.timeoutIntervalForResource = APIDefaults.resourceTimeout
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 6

        let delegate = CertificatePinningDelegate(configuration: pinningConfiguration)
        self.pinningDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.baseURL = baseURL
        self.authProvider = authProvider
        self.cache = cache

        // 5분 간격으로 만료된 응답 캐시 정리 (메모리 누수 방지)
        cachePurgeTask = Task { [cache] in
            for await _ in AsyncTimerSequence(interval: APIDefaults.cachePurgeInterval, tolerance: 30) {
                await cache.purgeExpired(defaultTTL: APIDefaults.defaultCacheTTL)
            }
        }
    }

    deinit {
        cachePurgeTask.cancel()
        session.invalidateAndCancel()
    }

    // MARK: - APIClientProtocol

    /// 네트워크 설정 업데이트
    public func updateRetryCount(_ count: Int) {
        maxRetries = max(1, min(count, 10))
    }

    public func request<T: Decodable & Sendable>(
        _ endpoint: any EndpointProtocol,
        as type: T.Type
    ) async throws -> T {
        // 캐시 확인 — queryItems를 결정적 형식으로 직렬화 (.description은 비결정적)
        let queryString = endpoint.queryItems?
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&") ?? ""
        let cacheKey = endpoint.path + "?" + queryString
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
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Referer")
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")

        // 인증: 쿠키가 있으면 항상 첨부 (soft auth)
        // requiresAuth=true인 경우 쿠키/토큰 없으면 에러, false이면 쿠키가 있을 때만 첨부
        var usedSoftAuth = false
        if let cookies = await authProvider?.cookies, !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            if !endpoint.requiresAuth {
                usedSoftAuth = true
            }
            Log.network.debug("Auth: cookies (\(cookies.count)) for \(endpoint.path, privacy: .public)")
        } else if endpoint.requiresAuth {
            if let token = await authProvider?.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                Log.network.debug("Auth: Bearer token for \(endpoint.path, privacy: .public)")
            } else {
                Log.network.error("Auth: no credentials for \(endpoint.path, privacy: .public)")
                throw APIError.unauthorized
            }
        }

        // 자동 재시도 로직
        var lastError: APIError?
        for attempt in 0..<maxRetries {
            do {
                Log.network.debug("Request: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public) (attempt \(attempt + 1))")

                let data: Data
                let response: URLResponse

                do {
                    (data, response) = try await session.data(for: request)
                } catch let urlError as URLError {
                    switch urlError.code {
                    case .timedOut, .networkConnectionLost:
                        lastError = .networkError(urlError.localizedDescription)
                        if attempt < maxRetries - 1 {
                            let baseDelay = min(Double(attempt + 1) * 0.5, 3.0)
                            let jitter = Double.random(in: 0...0.3) * baseDelay
                            try await Task.sleep(for: .seconds(baseDelay + jitter))
                            continue
                        }
                        throw APIError.networkError("Request timed out")
                    case .notConnectedToInternet:
                        throw APIError.networkError("No internet connection")
                    default:
                        throw APIError.networkError(urlError.localizedDescription)
                    }
                } catch {
                    throw APIError.networkError(error.localizedDescription)
                }

                // 응답 검증
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200...299:
                    break
                case 401:
                    // soft auth(requiresAuth=false)에서 만료 쿠키로 인한 401 →
                    // 쿠키 제거 후 1회 재시도 (인증 불필요 엔드포인트이므로 비인증으로도 동작)
                    if usedSoftAuth {
                        Log.network.info("Soft auth 401 on \(endpoint.path, privacy: .public) — 쿠키 제거 후 재시도")
                        request.setValue(nil, forHTTPHeaderField: "Cookie")
                        usedSoftAuth = false  // 다음 401에서는 세션 만료 처리
                        NotificationCenter.default.post(name: .chzzkSessionExpired, object: nil)
                        continue
                    }
                    // requiresAuth=true 또는 이미 재시도한 경우 → 세션 만료
                    NotificationCenter.default.post(name: .chzzkSessionExpired, object: nil)
                    throw APIError.unauthorized
                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init) ?? 5
                    if attempt < maxRetries - 1 {
                        Log.network.info("Rate limited, retrying after \(retryAfter)s")
                        try await Task.sleep(for: .seconds(min(retryAfter, APIDefaults.maxRateLimitRetrySecs)))
                        continue
                    }
                    throw APIError.rateLimited(retryAfter: retryAfter)
                case 500...599:
                    lastError = .httpError(statusCode: httpResponse.statusCode)
                    if attempt < maxRetries - 1 {
                        let baseDelay = min(Double(attempt + 1) * 0.5, 3.0)
                        let jitter = Double.random(in: 0...0.3) * baseDelay
                        try await Task.sleep(for: .seconds(baseDelay + jitter))
                        continue
                    }
                    throw APIError.httpError(statusCode: httpResponse.statusCode)
                default:
                    let body = String(data: data, encoding: .utf8) ?? "N/A"
                    if httpResponse.statusCode == 404 {
                        Log.network.info("HTTP 404 \(endpoint.path, privacy: .public)")
                    } else {
                        Log.network.error("HTTP \(httpResponse.statusCode, privacy: .public) \(endpoint.path, privacy: .public): \(LogMask.body(body), privacy: .private)")
                    }
                    throw APIError.httpError(statusCode: httpResponse.statusCode)
                }

                // JSON 구조 사전 검증
                let validation = ResponseValidator.validateJSONStructure(data)
                if !validation.warnings.isEmpty {
                    for warning in validation.warnings {
                        Log.network.warning("Response validation: \(warning, privacy: .public) — \(endpoint.path, privacy: .public)")
                    }
                }

                // JSON 디코딩 (ResponseValidator 경유)
                let apiResponse = try ResponseValidator.validateAndDecode(
                    ChzzkResponse<T>.self,
                    from: data,
                    decoder: JSONDecoder.chzzk
                )
                guard let content = apiResponse.content else {
                    throw APIError.emptyContent
                }

                // 캐시 저장
                if case .returnCacheElseLoad = endpoint.cachePolicy {
                    await cache.set(key: cacheKey, value: content)
                }

                return content

            } catch let error as APIError {
                lastError = error
                // 재시도 불가능한 에러는 즉시 throw
                switch error {
                case .unauthorized, .invalidResponse, .emptyContent, .decodingFailed, .malformedResponse:
                    throw error
                case .httpError(let code) where (400...499).contains(code):
                    throw error  // 4xx 클라이언트 에러는 재시도 불필요
                default:
                    if attempt >= maxRetries - 1 { throw error }
                }
            } catch {
                throw APIError.networkError(error.localizedDescription)
            }
        }

        throw lastError ?? APIError.networkError("Unknown error after retries")
    }

    // MARK: - Convenience Methods

    /// 응답 본문 디코딩 없이 API 호출 (POST/DELETE 등)
    public func requestRaw(_ endpoint: any EndpointProtocol) async throws {
        var urlComponents = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = endpoint.queryItems

        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid URL: \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        if endpoint.requiresAuth {
            if let cookies = await authProvider?.cookies, !cookies.isEmpty {
                let headers = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            } else if let token = await authProvider?.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                throw APIError.unauthorized
            }
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// 채널 정보 조회
    public func channelInfo(channelId: String) async throws -> CViewCore.ChannelInfo {
        try await request(ChzzkEndpoint.channelInfo(channelId: channelId), as: CViewCore.ChannelInfo.self)
    }

    /// 라이브 상세 조회
    public func liveDetail(channelId: String) async throws -> CViewCore.LiveInfo {
        try await request(ChzzkEndpoint.liveDetail(channelId: channelId), as: CViewCore.LiveInfo.self)
    }

    /// 팔로잉 목록 조회
    public func following(size: Int = 50, page: Int = 0) async throws -> FollowingContent {
        try await request(ChzzkEndpoint.following(size: size, page: page), as: FollowingContent.self)
    }

    /// 채널 팔로우
    public func followChannel(channelId: String) async throws {
        _ = try await requestRaw(ChzzkEndpoint.follow(channelId: channelId))
    }

    /// 채널 언팔로우
    public func unfollowChannel(channelId: String) async throws {
        _ = try await requestRaw(ChzzkEndpoint.unfollow(channelId: channelId))
    }

}
