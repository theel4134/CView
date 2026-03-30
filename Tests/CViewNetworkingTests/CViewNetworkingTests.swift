// MARK: - ChzzkEndpointTests.swift
// CViewNetworking — ChzzkEndpoint 엔드포인트 테스트

import Testing
import Foundation
@testable import CViewNetworking
@testable import CViewCore

// MARK: - Path

@Suite("ChzzkEndpoint — Path")
struct ChzzkEndpointPathTests {

    @Test("channelInfo 경로에 채널 ID 포함")
    func channelInfoPath() {
        let ep = ChzzkEndpoint.channelInfo(channelId: "ch-123")
        #expect(ep.path == "/service/v1/channels/ch-123")
    }

    @Test("liveDetail 경로")
    func liveDetailPath() {
        let ep = ChzzkEndpoint.liveDetail(channelId: "abc")
        #expect(ep.path == "/service/v3/channels/abc/live-detail")
    }

    @Test("liveStatus 경로")
    func liveStatusPath() {
        let ep = ChzzkEndpoint.liveStatus(channelId: "xyz")
        #expect(ep.path == "/polling/v1/channels/xyz/live-status")
    }

    @Test("following 경로")
    func followingPath() {
        let ep = ChzzkEndpoint.following(size: 20, page: 0)
        #expect(ep.path == "/service/v1/channels/followings")
    }

    @Test("chatAccessToken 경로")
    func chatAccessTokenPath() {
        let ep = ChzzkEndpoint.chatAccessToken(chatChannelId: "chat-001")
        #expect(ep.path == "/polling/v3/channels/chat-001/access-token")
    }

    @Test("vodDetail 경로")
    func vodDetailPath() {
        let ep = ChzzkEndpoint.vodDetail(videoNo: 42)
        #expect(ep.path == "/service/v3/videos/42")
    }

    @Test("clipDetail 경로")
    func clipDetailPath() {
        let ep = ChzzkEndpoint.clipDetail(clipUID: "clip-abc")
        #expect(ep.path == "/service/v1/clips/clip-abc/detail")
    }

    @Test("userStatus 경로")
    func userStatusPath() {
        let ep = ChzzkEndpoint.userStatus
        #expect(ep.path == "/service/v1/users/me")
    }

    @Test("emoticonDeploy 경로")
    func emoticonDeployPath() {
        let ep = ChzzkEndpoint.emoticonDeploy(channelId: "em-ch")
        #expect(ep.path == "/service/v1/channels/em-ch/emoticon-deploy")
    }
}

// MARK: - HTTP Method

@Suite("ChzzkEndpoint — Method")
struct ChzzkEndpointMethodTests {

    @Test("기본 GET 엔드포인트")
    func defaultGet() {
        #expect(ChzzkEndpoint.channelInfo(channelId: "x").method == .get)
        #expect(ChzzkEndpoint.liveDetail(channelId: "x").method == .get)
        #expect(ChzzkEndpoint.userStatus.method == .get)
        #expect(ChzzkEndpoint.topLives(size: 10).method == .get)
    }

    @Test("follow는 POST")
    func followPost() {
        #expect(ChzzkEndpoint.follow(channelId: "x").method == .post)
    }

    @Test("unfollow는 DELETE")
    func unfollowDelete() {
        #expect(ChzzkEndpoint.unfollow(channelId: "x").method == .delete)
    }

    @Test("clipInkey는 POST")
    func clipInkeyPost() {
        let ep = ChzzkEndpoint.clipInkey(clipUID: "uid")
        #expect(ep.method == .post)
        #expect(ep.body != nil)
    }
}

// MARK: - Query Items

@Suite("ChzzkEndpoint — QueryItems")
struct ChzzkEndpointQueryTests {

    @Test("following queryItems에 size, sortType 포함")
    func followingQuery() {
        let ep = ChzzkEndpoint.following(size: 20, page: 0)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "size" && $0.value == "20" })
        #expect(items.contains { $0.name == "sortType" && $0.value == "FOLLOW" })
    }

    @Test("following page > 0 이면 page 파라미터 추가")
    func followingWithPage() {
        let ep = ChzzkEndpoint.following(size: 10, page: 2)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "page" && $0.value == "2" })
    }

    @Test("following page=0 이면 page 파라미터 없음")
    func followingNoPage() {
        let ep = ChzzkEndpoint.following(size: 10, page: 0)
        let items = ep.queryItems ?? []
        #expect(!items.contains { $0.name == "page" })
    }

    @Test("searchChannel queryItems")
    func searchChannelQuery() {
        let ep = ChzzkEndpoint.searchChannel(keyword: "테스트", offset: 10, size: 20)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "keyword" && $0.value == "테스트" })
        #expect(items.contains { $0.name == "offset" && $0.value == "10" })
        #expect(items.contains { $0.name == "size" && $0.value == "20" })
    }

    @Test("topLives queryItems — 기본")
    func topLivesBasic() {
        let ep = ChzzkEndpoint.topLives(size: 50)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "size" && $0.value == "50" })
        #expect(!items.contains { $0.name == "concurrentUserCount" })
    }

    @Test("topLives queryItems — 커서 포함")
    func topLivesWithCursor() {
        let ep = ChzzkEndpoint.topLives(size: 50, concurrentUserCount: 1000, liveId: 42)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "concurrentUserCount" && $0.value == "1000" })
        #expect(items.contains { $0.name == "liveId" && $0.value == "42" })
    }

    @Test("channelInfo queryItems nil")
    func channelInfoNoQuery() {
        #expect(ChzzkEndpoint.channelInfo(channelId: "x").queryItems == nil)
    }

    @Test("clipDetail queryItems에 optionalProperties 포함")
    func clipDetailQuery() {
        let ep = ChzzkEndpoint.clipDetail(clipUID: "uid")
        let items = ep.queryItems ?? []
        let optProps = items.filter { $0.name == "optionalProperties" }
        #expect(optProps.count == 5)
    }

    @Test("vodList queryItems")
    func vodListQuery() {
        let ep = ChzzkEndpoint.vodList(channelId: "ch", page: 1, size: 15)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "page" && $0.value == "1" })
        #expect(items.contains { $0.name == "size" && $0.value == "15" })
        #expect(items.contains { $0.name == "sortType" && $0.value == "LATEST" })
    }
}

// MARK: - Auth & Cache

@Suite("ChzzkEndpoint — Auth & Cache")
struct ChzzkEndpointAuthCacheTests {

    @Test("인증 필요 엔드포인트")
    func requiresAuth() {
        #expect(ChzzkEndpoint.following(size: 20, page: 0).requiresAuth == true)
        #expect(ChzzkEndpoint.userStatus.requiresAuth == true)
        #expect(ChzzkEndpoint.follow(channelId: "x").requiresAuth == true)
        #expect(ChzzkEndpoint.unfollow(channelId: "x").requiresAuth == true)
        #expect(ChzzkEndpoint.clipInkey(clipUID: "x").requiresAuth == true)
        #expect(ChzzkEndpoint.userEmoticons.requiresAuth == true)
    }

    @Test("인증 불필요 엔드포인트")
    func noAuth() {
        #expect(ChzzkEndpoint.channelInfo(channelId: "x").requiresAuth == false)
        #expect(ChzzkEndpoint.liveDetail(channelId: "x").requiresAuth == false)
        #expect(ChzzkEndpoint.topLives(size: 10).requiresAuth == false)
        #expect(ChzzkEndpoint.chatAccessToken(chatChannelId: "x").requiresAuth == false)
        #expect(ChzzkEndpoint.basicEmoticonPacks.requiresAuth == false)
    }

    @Test("liveStatus는 캐시 무시")
    func liveStatusNoCache() {
        let policy = ChzzkEndpoint.liveStatus(channelId: "x").cachePolicy
        if case .reloadIgnoringCache = policy {
            // OK
        } else {
            Issue.record("liveStatus should use reloadIgnoringCache")
        }
    }

    @Test("channelInfo는 5분 캐시")
    func channelInfoCache() {
        let policy = ChzzkEndpoint.channelInfo(channelId: "x").cachePolicy
        if case .returnCacheElseLoad(let ttl) = policy {
            #expect(ttl == 300)
        } else {
            Issue.record("channelInfo should use returnCacheElseLoad")
        }
    }
}

// MARK: - MetricsEndpoint

@Suite("MetricsEndpoint — Path & Method")
struct MetricsEndpointTests {

    @Test("stats 경로 및 메서드")
    func statsEndpoint() {
        let ep = MetricsEndpoint.stats
        #expect(ep.path == "/api/stats")
        #expect(ep.method == .get)
    }

    @Test("health 경로")
    func healthEndpoint() {
        let ep = MetricsEndpoint.health
        #expect(ep.path == "/health")
        #expect(ep.method == .get)
    }

    @Test("channelStats 경로")
    func channelStatsPath() {
        let ep = MetricsEndpoint.channelStats(channelId: "ch-1")
        #expect(ep.path == "/api/channel/ch-1/stats")
    }

    @Test("removeChannel은 DELETE")
    func removeChannelDelete() {
        let ep = MetricsEndpoint.removeChannel(channelId: "ch-rm")
        #expect(ep.method == .delete)
        #expect(ep.path == "/api/channels/ch-rm")
    }

    @Test("POST 엔드포인트 메서드 확인")
    func postMethods() {
        #expect(MetricsEndpoint.channelCleanup.method == .post)
        #expect(MetricsEndpoint.pingChannel(channelId: "x").method == .post)
    }

    @Test("모든 MetricsEndpoint는 인증 불필요")
    func noAuthRequired() {
        #expect(MetricsEndpoint.stats.requiresAuth == false)
        #expect(MetricsEndpoint.health.requiresAuth == false)
        #expect(MetricsEndpoint.channelStats(channelId: "x").requiresAuth == false)
    }

    @Test("health는 캐시 무시")
    func healthNoCache() {
        if case .reloadIgnoringCache = MetricsEndpoint.health.cachePolicy {
            // OK
        } else {
            Issue.record("health should use reloadIgnoringCache")
        }
    }

    @Test("stats는 10초 캐시")
    func statsCacheTTL() {
        if case .returnCacheElseLoad(let ttl) = MetricsEndpoint.stats.cachePolicy {
            #expect(ttl == 10)
        } else {
            Issue.record("stats should use returnCacheElseLoad")
        }
    }

    @Test("channelSyncRecommendation queryItems — appLatency 포함")
    func syncRecommendationQuery() {
        let ep = MetricsEndpoint.channelSyncRecommendation(channelId: "ch", appLatency: 150.0)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "appLatency" && $0.value == "150" })
    }

    @Test("channelSyncRecommendation queryItems — appLatency nil")
    func syncRecommendationNoLatency() {
        let ep = MetricsEndpoint.channelSyncRecommendation(channelId: "ch", appLatency: nil)
        #expect(ep.queryItems == nil)
    }

    @Test("statsChannelRanking queryItems")
    func channelRankingQuery() {
        let ep = MetricsEndpoint.statsChannelRanking(sort: "viewers", limit: 10)
        let items = ep.queryItems ?? []
        #expect(items.contains { $0.name == "sort" && $0.value == "viewers" })
        #expect(items.contains { $0.name == "limit" && $0.value == "10" })
    }

    @Test("pingChannel body에 channelId 포함")
    func pingBody() throws {
        let ep = MetricsEndpoint.pingChannel(channelId: "ping-ch")
        let body = ep.body
        #expect(body != nil)
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: String]
        #expect(json?["channelId"] == "ping-ch")
        #expect(json?["source"] == "VLC")
        #expect(json?["platform"] == "app")
    }

    @Test("cviewConnect 경로 및 메서드")
    func cviewConnectEndpoint() {
        let payload = CViewConnectPayload(
            clientId: "test-client",
            appVersion: "1.0",
            channelId: "ch1"
        )
        let ep = MetricsEndpoint.cviewConnect(payload)
        #expect(ep.path == "/api/cview/connect")
        #expect(ep.method == .post)
        #expect(ep.body != nil)
    }
}

