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
    private let session: URLSession
    private let baseURL: URL
    private let authProvider: (any AuthTokenProvider)?
    private let cache: ResponseCache
    private var maxRetries: Int = 3
    /// SSL 핀닝 델리게이트 — URLSession이 약한 참조하므로 강한 참조 유지 필요
    private let pinningDelegate: CertificatePinningDelegate

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
        Task { [cache] in
            for await _ in AsyncTimerSequence(interval: APIDefaults.cachePurgeInterval, tolerance: 30) {
                await cache.purgeExpired(defaultTTL: APIDefaults.defaultCacheTTL)
            }
        }
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
        if let cookies = await authProvider?.cookies, !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
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
                    // 쿠키를 첨부한 요청이 서버에서 401을 반환 = 세션 만료
                    // (자격증명 자체가 없는 경우는 요청 전에 이미 throw됨)
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

    /// 채팅 접속 토큰 조회 (인증 선택적 — 비로그인 시 READ 토큰)
    /// 채팅 접속 토큰은 game API (comm-api.game.naver.com) 사용
    private static let gameAPIBaseURL = URL(string: "https://comm-api.game.naver.com/nng_main")!
    
    public func chatAccessToken(chatChannelId: String) async throws -> CViewCore.ChatAccessToken {
        // 채팅 API는 comm-api.game.naver.com/nng_main 사용 (api.chzzk.naver.com 아님)
        var urlComponents = URLComponents(url: Self.gameAPIBaseURL.appending(path: "/v1/chats/access-token"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "channelId", value: chatChannelId),
            URLQueryItem(name: "chatType", value: "STREAMING")
        ]
        guard let url = urlComponents.url else {
            throw APIError.networkError("Invalid chat token URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(CommonHeaders.chromeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
        
        // 쿠키가 있으면 SEND 권한, 없으면 READ 토큰
        if let cookies = await authProvider?.cookies, !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        Log.network.debug("Chat token request: \(LogMask.urlString(url.absoluteString), privacy: .private)")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            Log.network.error("Chat token HTTP \(httpResponse.statusCode, privacy: .public)")
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // 디버그: raw 응답 확인
        if let rawStr = String(data: data, encoding: .utf8) {
            Log.network.debug("Chat token response: \(LogMask.body(rawStr), privacy: .private)")
        }
        
        do {
            let apiResponse = try JSONDecoder.chzzk.decode(ChzzkResponse<CViewCore.ChatAccessToken>.self, from: data)
            guard let content = apiResponse.content else {
                throw APIError.emptyContent
            }
            return content
        } catch {
            Log.network.error("Chat token decode error: \(error, privacy: .public)")
            throw error
        }
    }

    /// 인기 라이브 조회
    public func topLives(size: Int = 50, concurrentUserCount: Int? = nil, liveId: Int? = nil) async throws -> PagedContent<CViewCore.LiveInfo> {
        try await request(ChzzkEndpoint.topLives(size: size, concurrentUserCount: concurrentUserCount, liveId: liveId), as: PagedContent<CViewCore.LiveInfo>.self)
    }

    /// 전체 라이브 채널 수집 (1페이지 ~ 끝 커서 순회, 통계 집계용)
    /// - Parameter batchSize: 페이지당 항목 수 (최대 50)
    public func allLiveChannels(batchSize: Int = 50) async throws -> [CViewCore.LiveInfo] {
        var all: [CViewCore.LiveInfo] = []
        var cursor: LivePageCursor? = nil
        let maxPages = APIDefaults.allLivesMaxPages  // 안전 상한 (200 * 50 = 10,000 채널)
        var page = 0

        repeat {
            let response = try await topLives(
                size: batchSize,
                concurrentUserCount: cursor?.concurrentUserCount,
                liveId: cursor?.liveId
            )
            all.append(contentsOf: response.data)
            cursor = response.page?.next
            page += 1
        } while cursor != nil && page < maxPages

        return all
    }

    // MARK: - Search Methods

    /// 채널 검색
    public func searchChannels(keyword: String, offset: Int = 0, size: Int = 20) async throws -> SearchResult<CViewCore.ChannelInfo> {
        let raw = try await request(ChzzkEndpoint.searchChannel(keyword: keyword, offset: offset, size: size), as: SearchResult<CViewCore.ChannelSearchItem>.self)
        return SearchResult(size: raw.size, page: raw.page, totalCount: raw.totalCount, data: raw.data.map(\.channel))
    }

    /// 라이브 검색
    public func searchLives(keyword: String, offset: Int = 0, size: Int = 20) async throws -> SearchResult<CViewCore.LiveInfo> {
        let raw = try await request(ChzzkEndpoint.searchLive(keyword: keyword, offset: offset, size: size), as: SearchResult<CViewCore.LiveSearchItem>.self)
        return SearchResult(size: raw.size, page: raw.page, totalCount: raw.totalCount, data: raw.data.map(\.live))
    }

    /// 비디오 검색
    public func searchVideos(keyword: String, offset: Int = 0, size: Int = 20) async throws -> SearchResult<CViewCore.VODInfo> {
        let raw = try await request(ChzzkEndpoint.searchVideo(keyword: keyword, offset: offset, size: size), as: SearchResult<CViewCore.VideoSearchItem>.self)
        return SearchResult(size: raw.size, page: raw.page, totalCount: raw.totalCount, data: raw.data.map(\.video))
    }
    
    // MARK: - VOD Methods
    
    /// VOD 목록 조회
    public func vodList(channelId: String, page: Int = 0, size: Int = 20) async throws -> PagedContent<CViewCore.VODInfo> {
        try await request(ChzzkEndpoint.vodList(channelId: channelId, page: page, size: size), as: PagedContent<CViewCore.VODInfo>.self)
    }
    
    /// VOD 상세 정보 조회
    public func vodDetail(videoNo: Int) async throws -> CViewCore.VODDetail {
        try await request(ChzzkEndpoint.vodDetail(videoNo: videoNo), as: CViewCore.VODDetail.self)
    }
    
    /// 클립 목록 조회
    public func clipList(channelId: String, page: Int = 0, size: Int = 20) async throws -> PagedContent<CViewCore.ClipInfo> {
        try await request(ChzzkEndpoint.clipList(channelId: channelId, page: page, size: size), as: PagedContent<CViewCore.ClipInfo>.self)
    }
    
    /// 치지직 전체 인기/추천 클립 조회 (홈 추천 클립)
    /// - Parameters:
    ///   - filterType: WITHIN_1_DAY / WITHIN_7_DAYS / WITHIN_30_DAYS / ALL_TIME
    ///   - orderType: POPULAR / RECOMMEND
    public func homePopularClips(filterType: String = "WITHIN_7_DAYS", orderType: String = "POPULAR") async throws -> [CViewCore.ClipInfo] {
        let paged = try await request(ChzzkEndpoint.homePopularClips(filterType: filterType, orderType: orderType), as: PagedContent<CViewCore.ClipInfo>.self)
        return paged.data
    }
    
    /// 클립 상세 조회
    public func clipDetail(clipUID: String) async throws -> CViewCore.ClipDetail {
        try await request(ChzzkEndpoint.clipDetail(clipUID: clipUID), as: CViewCore.ClipDetail.self)
    }

    /// 클립 HLS 스트림 URL 획득 (inkey → Naver VOD 순으로)
    /// 1. POST /service/v1/clips/{uid}/inkey → inKey 획득
    /// 2. GET apis.naver.com/rmcnmv/rmcnmv/vod/play/v2.0/{videoId}?key={inKey}&serviceId=nng_chzzk_clip
    /// 3. HLS masterPlaylistUrl 추출
    public func clipStreamURL(clipUID: String, videoId: String) async throws -> URL {
        // Step 1: inkey 획득
        // ChzzkAPIClient.request()를 우회하여 직접 URLRequest 구성
        // — auth 체크에서 throw 없이 쿠키 있으면 첨부, 없어도 시도
        guard let inkeyURL = URL(string: "https://api.chzzk.naver.com/service/v1/clips/\(clipUID)/inkey") else {
            throw APIError.networkError("Invalid inkey URL")
        }

        var inkeyRequest = URLRequest(url: inkeyURL)
        inkeyRequest.httpMethod = "POST"
        inkeyRequest.httpBody = "{}".data(using: .utf8)
        inkeyRequest.timeoutInterval = APIDefaults.clipInkeyTimeout
        inkeyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        inkeyRequest.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Referer")
        inkeyRequest.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")
        inkeyRequest.setValue(
            CommonHeaders.chromeUserAgent,
            forHTTPHeaderField: "User-Agent"
        )

        // 쿠키 직접 첨부 (HTTPCookieStorage.shared — WebKit 동기화 후 NID 쿠키 포함)
        let sharedCookies = HTTPCookieStorage.shared.cookies(for: inkeyURL) ?? []
        let nidCookies = sharedCookies.filter { ["NID_AUT", "NID_SES"].contains($0.name) }
        if !nidCookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: nidCookies)
            for (k, v) in headers { inkeyRequest.setValue(v, forHTTPHeaderField: k) }
            Log.network.info("Clip inkey: attaching \(nidCookies.count) NID cookies")
        } else {
            // 폴백: authProvider 쿠키
            if let authCookies = await authProvider?.cookies, !authCookies.isEmpty {
                let headers = HTTPCookie.requestHeaderFields(with: authCookies)
                for (k, v) in headers { inkeyRequest.setValue(v, forHTTPHeaderField: k) }
                Log.network.info("Clip inkey: attaching \(authCookies.count) auth cookies (provider)")
            } else {
                Log.network.warning("Clip inkey: no cookies found — trying without auth")
            }
        }

        let (inkeyData, inkeyResponse) = try await session.data(for: inkeyRequest)
        guard let inkeyHttp = inkeyResponse as? HTTPURLResponse, inkeyHttp.statusCode == 200 else {
            let code = (inkeyResponse as? HTTPURLResponse)?.statusCode ?? -1
            if let rawStr = String(data: inkeyData, encoding: .utf8) {
                Log.network.error("Clip inkey HTTP \(code): \(LogMask.body(rawStr), privacy: .private)")
            }
            throw APIError.httpError(statusCode: code)
        }

        let inkeyResult = try JSONDecoder.chzzk.decode(ChzzkResponse<CViewCore.ClipInkeyContent>.self, from: inkeyData)
        guard let inKey = inkeyResult.content?.inKey, !inKey.isEmpty else {
            Log.network.error("Clip inkey: content nil or empty (code=\(inkeyResult.code))")
            throw APIError.emptyContent
        }
        Log.network.info("Clip inkey OK (key prefix: \(LogMask.token(inKey), privacy: .private))")

        // Step 2: Naver rmcnmv VOD play API 호출 (외부 API)
        let vodURLString = "https://apis.naver.com/rmcnmv/rmcnmv/vod/play/v2.0/\(videoId)?key=\(inKey)&serviceId=nng_chzzk_clip&cc=kr"
        guard let vodURL = URL(string: vodURLString) else {
            throw APIError.networkError("Invalid VOD URL")
        }

        var vodRequest = URLRequest(url: vodURL)
        vodRequest.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Referer")
        vodRequest.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")

        let (vodData, vodResponse) = try await session.data(for: vodRequest)
        guard let vodHttp = vodResponse as? HTTPURLResponse, vodHttp.statusCode == 200 else {
            throw APIError.httpError(statusCode: (vodResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // Step 3: JSON 파싱 — NaverVodPlayResponse
        let vodPlay = try JSONDecoder().decode(CViewCore.NaverVodPlayResponse.self, from: vodData)
        if let errCode = vodPlay.errorCode {
            Log.network.error("Naver VOD error: \(errCode, privacy: .public)")
            throw APIError.networkError("VOD error: \(errCode)")
        }
        guard let hlsURLString = vodPlay.bestHLSURL, let hlsURL = URL(string: hlsURLString) else {
            if let raw = String(data: vodData, encoding: .utf8) {
                Log.network.error("VOD no HLS URL. Raw: \(LogMask.body(raw), privacy: .private)")
            }
            throw APIError.emptyContent
        }
        Log.network.info("Clip HLS URL: \(LogMask.urlString(hlsURLString), privacy: .private)")
        return hlsURL
    }
    
    /// 채널 이모티콘 배포 정보 조회
    public func emoticonDeploy(channelId: String) async throws -> CViewCore.EmoticonDeploy {
        try await request(ChzzkEndpoint.emoticonDeploy(channelId: channelId), as: CViewCore.EmoticonDeploy.self)
    }
    
    /// 이모티콘 팩 상세 조회
    public func emoticonPack(packId: String) async throws -> CViewCore.EmoticonPack {
        try await request(ChzzkEndpoint.emoticonPack(packId: packId), as: CViewCore.EmoticonPack.self)
    }
    
    /// 사용자가 사용할 수 있는 전체 이모티콘 조회 (/service/v2/emoticons) - 인증 필요
    public func userEmoticons() async throws -> CViewCore.EmoticonDeploy {
        try await request(ChzzkEndpoint.userEmoticons, as: CViewCore.EmoticonDeploy.self)
    }
    
    /// 이모티콘 팩 목록으로부터 emoMap + 팩 배열을 빌드 (비어있는 팩은 상세 API로 병렬 소급)
    public func resolveEmoticonPacks(_ packs: [CViewCore.EmoticonPack]) async -> (emoMap: [String: String], packs: [CViewCore.EmoticonPack]) {
        guard !packs.isEmpty else { return ([:], []) }
        // 빈 팩 상세 조회를 withTaskGroup으로 병렬 처리
        let resolved: [CViewCore.EmoticonPack] = await withTaskGroup(of: CViewCore.EmoticonPack?.self) { group in
            for pack in packs {
                group.addTask {
                    if !(pack.emoticons ?? []).isEmpty { return pack }
                    return try? await self.emoticonPack(packId: pack.emoticonPackId)
                }
            }
            var result: [CViewCore.EmoticonPack] = []
            for await pack in group {
                if let p = pack, !(p.emoticons ?? []).isEmpty { result.append(p) }
            }
            return result
        }
        var emoMap: [String: String] = [:]
        for p in resolved {
            for em in p.emoticons ?? [] {
                if let url = em.imageURL?.absoluteString { emoMap[em.emoticonId] = url }
            }
        }
        return (emoMap, resolved)
    }
    
    /// 치지직 기본 이모티콘 팩 (로그인 없이도 사용 가능한 공개 팩)
    /// - channelId: 어떤 채널이든 OK - basic 팩은 모든 채널에 포함됨
    /// 로그인 상태라면 구독 팩도 자동으로 포함됨 (soft auth)
    public func basicEmoticonPacks(channelId: String) async -> [CViewCore.EmoticonPack] {
        if let deploy = try? await emoticonDeploy(channelId: channelId) {
            let all = deploy.allPacks
            Log.network.info("basicEmoticonPacks(\(channelId)): \(all.count)개 팩 (기본 \(deploy.emoticonPacks?.count ?? 0), 구독 \(deploy.subscriptionEmoticonPacks?.count ?? 0))")
            if !all.isEmpty { return all }
        }
        // 채널 없이도 로그인 유저면 전체 이모티콘 사용 가능
        if let deploy = try? await request(ChzzkEndpoint.userEmoticons,
                                           as: CViewCore.EmoticonDeploy.self) {
            return deploy.allPacks
        }
        return []
    }

    /// 치지직 글로벌 기본 이모티콘 (/service/v1/emoticons) — 채널 ID 불필요, 인증 불필요
    /// 앱 시작 시 1회 호출하여 기본 이모티콘을 사전 캐싱하는 용도
    public func globalBasicEmoticons() async -> [CViewCore.EmoticonPack] {
        do {
            let deploy = try await request(ChzzkEndpoint.basicEmoticonPacks, as: CViewCore.EmoticonDeploy.self)
            let all = deploy.allPacks
            Log.network.info("globalBasicEmoticons: \(all.count)개 팩 로드")
            return all
        } catch {
            Log.network.info("globalBasicEmoticons: API 미지원 (\(error.localizedDescription))")
            return []
        }
    }
    
    /// 사용자 상태 조회 (game server API)
    public func userStatus() async throws -> UserStatusInfo {
        let url = URL(string: "https://comm-api.game.naver.com/nng_main/v1/user/getUserStatus")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Referer")
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")

        // 쿠키 인증
        if let cookies = await authProvider?.cookies, !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(statusCode: status)
        }
        let apiResponse = try JSONDecoder.chzzk.decode(ChzzkResponse<UserStatusInfo>.self, from: data)
        guard let content = apiResponse.content else { throw APIError.emptyContent }
        return content
    }

    /// 라이브 상태 폴링 조회
    public func liveStatus(channelId: String) async throws -> CViewCore.LiveInfo {
        try await request(ChzzkEndpoint.liveStatus(channelId: channelId), as: CViewCore.LiveInfo.self)
    }

    // MARK: - 팔로우 채널 전체 조회 (페이지네이션 + 라이브 상세 병렬 요청)

    /// 모든 팔로잉 채널을 수집하고, 라이브 중인 채널의 상세 정보를 병렬로 조회합니다.
    public func fetchFollowingChannels() async throws -> [LiveChannelItem] {
        var allItems: [(LiveChannelItem, Bool)] = []
        var seenIds: Set<String> = []
        var currentPage = 0
        let batchSize = 50
        let maxPages = 50

        // 페이지네이션: 모든 팔로잉 채널 수집
        while currentPage < maxPages {
            let response = try await following(size: batchSize, page: currentPage)
            let items = response.followingList ?? []
            let pageItems: [(LiveChannelItem, Bool)] = items.compactMap { item in
                guard let channel = item.channel,
                      let channelId = channel.channelId,
                      !seenIds.contains(channelId) else { return nil }
                seenIds.insert(channelId)
                let isLive = item.streamer?.openLive ?? false
                let baseItem = LiveChannelItem(
                    id: channelId,
                    channelName: channel.channelName ?? "Unknown",
                    channelImageUrl: channel.channelImageUrl,
                    liveTitle: "",
                    viewerCount: 0,
                    categoryName: nil,
                    thumbnailUrl: nil,
                    channelId: channelId,
                    isLive: isLive
                )
                return (baseItem, isLive)
            }
            allItems.append(contentsOf: pageItems)

            if let total = response.totalCount, seenIds.count >= total { break }
            if items.count < batchSize { break }
            currentPage += 1
        }

        // 라이브 중인 채널의 상세 정보를 최대 8개씩 병렬 요청 (API rate limit 보호)
        let liveItems = allItems.filter { $0.1 }
        let offlineItems = allItems.filter { !$0.1 }.map(\.0)
        let concurrencyLimit = 8

        var liveResults: [LiveChannelItem] = []
        var offset = 0
        while offset < liveItems.count {
            let chunk = Array(liveItems[offset..<min(offset + concurrencyLimit, liveItems.count)])
            offset += concurrencyLimit

            let chunkResults = await withTaskGroup(of: LiveChannelItem.self) { group in
                for (baseItem, _) in chunk {
                    group.addTask {
                        do {
                            let liveInfo = try await self.liveDetail(channelId: baseItem.channelId)
                            return LiveChannelItem(
                                id: baseItem.id,
                                channelName: baseItem.channelName,
                                channelImageUrl: baseItem.channelImageUrl,
                                liveTitle: liveInfo.liveTitle,
                                viewerCount: liveInfo.concurrentUserCount,
                                categoryName: liveInfo.liveCategoryValue,
                                thumbnailUrl: liveInfo.resolvedLiveImageURL?.absoluteString,
                                channelId: baseItem.channelId,
                                isLive: true,
                                openDate: liveInfo.openDate
                            )
                        } catch {
                            Log.api.warning("라이브 상세 조회 실패: \(baseItem.channelId) — \(error)")
                            return baseItem
                        }
                    }
                }
                var collected: [LiveChannelItem] = []
                for await item in group { collected.append(item) }
                return collected
            }
            liveResults.append(contentsOf: chunkResults)
        }

        return liveResults + offlineItems
    }
}
