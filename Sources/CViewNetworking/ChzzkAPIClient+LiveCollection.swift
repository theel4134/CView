// MARK: - ChzzkAPIClient+LiveCollection.swift
// 라이브 수집, 채팅 토큰, 사용자 상태, 팔로잉 채널 조회

import Foundation
import CViewCore

extension ChzzkAPIClient {

    // MARK: - Chat Access Token

    /// 채팅 접속 토큰 조회 (인증 선택적 — 비로그인 시 READ 토큰)
    /// 채팅 접속 토큰은 game API (comm-api.game.naver.com) 사용
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

    // MARK: - Live Collection

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

    /// 전체 라이브 수집 (진행률 콜백 + 중복 제거 + 에러 탄력성)
    /// - Parameters:
    ///   - batchSize: 페이지당 항목 수 (최대 50)
    ///   - onProgress: 페이지마다 호출되는 진행률 콜백
    /// - Returns: 중복 제거된 전체 LiveInfo 배열
    public func allLiveChannelsProgressive(
        batchSize: Int = 50,
        onProgress: @Sendable @MainActor (AllLivesProgress) -> Void = { _ in }
    ) async throws -> [CViewCore.LiveInfo] {
        var all: [CViewCore.LiveInfo] = []
        var seenIds = Set<Int>()
        var cursor: LivePageCursor? = nil
        let maxPages = APIDefaults.allLivesMaxPages
        var page = 0
        var estimatedTotal: Int? = nil

        repeat {
            let response: PagedContent<CViewCore.LiveInfo>
            do {
                response = try await topLives(
                    size: batchSize,
                    concurrentUserCount: cursor?.concurrentUserCount,
                    liveId: cursor?.liveId
                )
            } catch {
                // 중간 페이지 실패: 1회 재시도
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    response = try await topLives(
                        size: batchSize,
                        concurrentUserCount: cursor?.concurrentUserCount,
                        liveId: cursor?.liveId
                    )
                } catch {
                    // 재시도도 실패 → 수집된 부분 결과 반환
                    break
                }
            }

            // 첫 페이지에서 totalCount 추출
            if page == 0, let total = response.totalCount {
                estimatedTotal = total
            }

            // liveId 기반 중복 제거
            for info in response.data {
                if seenIds.insert(info.liveId).inserted {
                    all.append(info)
                }
            }

            cursor = response.page?.next
            page += 1

            // 진행률 콜백
            let progress = AllLivesProgress(
                currentCount: all.count,
                estimatedTotal: estimatedTotal,
                currentPage: page,
                deduplicatedCount: (page * batchSize) - all.count
            )
            await onProgress(progress)

            // API 부하 방지용 딜레이
            if cursor != nil {
                try await Task.sleep(for: .milliseconds(50))
            }
        } while cursor != nil && page < maxPages

        return all
    }

    // MARK: - User / Live Status

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
