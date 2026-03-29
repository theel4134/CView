// MARK: - ChzzkAPIClient+Content.swift
// 검색, VOD/클립, 이모티콘 API

import Foundation
import CViewCore

extension ChzzkAPIClient {

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
    
    // MARK: - Emoticon Methods
    
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
}
