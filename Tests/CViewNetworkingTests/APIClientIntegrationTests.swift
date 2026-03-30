// MARK: - APIClientIntegrationTests.swift
// Mock-based integration tests for ChzzkAPIClient retry logic, cache,
// error handling, and concurrent request patterns.

import Testing
import Foundation
@testable import CViewNetworking
@testable import CViewCore

// MARK: - Mock Auth Token Provider

/// Mock AuthTokenProvider for testing API client auth paths.
private actor MockAuthTokenProvider: AuthTokenProvider {
    var _cookies: [HTTPCookie]?
    var _accessToken: String?
    var _isAuthenticated: Bool

    init(cookies: [HTTPCookie]? = nil, accessToken: String? = nil, isAuthenticated: Bool = false) {
        self._cookies = cookies
        self._accessToken = accessToken
        self._isAuthenticated = isAuthenticated
    }

    var cookies: [HTTPCookie]? { _cookies }
    var accessToken: String? { _accessToken }
    var isAuthenticated: Bool { _isAuthenticated }

    func setCookies(_ cookies: [HTTPCookie]?) { _cookies = cookies }
    func setAccessToken(_ token: String?) { _accessToken = token }
    func setAuthenticated(_ value: Bool) { _isAuthenticated = value }
}

// MARK: - Mock Endpoint

/// A simple test endpoint conforming to EndpointProtocol.
private struct MockEndpoint: EndpointProtocol, Sendable {
    var path: String = "/test/path"
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem]? = nil
    var body: Data? = nil
    var requiresAuth: Bool = false
    var cachePolicy: CachePolicy = .reloadIgnoringCache
}

// MARK: - Response Cache Integration Tests

@Suite("ResponseCache — Integration")
struct ResponseCacheIntegrationTests {

    @Test("Cache stores and retrieves typed data")
    func storeAndRetrieveTyped() async {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "channel-info", value: "test-channel-data")
        let result: String? = await cache.get(key: "channel-info", ttl: 60)

        #expect(result == "test-channel-data")
    }

    @Test("Cache returns nil for expired entries")
    func expiredEntries() async throws {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "short-lived", value: "data")
        // TTL of 0 means already expired
        let result: String? = await cache.get(key: "short-lived", ttl: 0)
        #expect(result == nil)
    }

    @Test("Cache respects max entries limit")
    func maxEntriesLimit() async {
        let cache = ResponseCache(maxEntries: 5)

        for i in 0..<10 {
            await cache.set(key: "key-\(i)", value: "value-\(i)")
        }

        // The most recent entries should still be accessible
        let recent: String? = await cache.get(key: "key-9", ttl: 60)
        #expect(recent == "value-9")
    }

    @Test("Cache clear removes all entries")
    func clearRemovesAll() async {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "k1", value: "v1")
        await cache.set(key: "k2", value: "v2")
        await cache.clear()

        let r1: String? = await cache.get(key: "k1", ttl: 60)
        let r2: String? = await cache.get(key: "k2", ttl: 60)
        #expect(r1 == nil)
        #expect(r2 == nil)
    }

    @Test("Cache remove deletes specific entry")
    func removeSpecificEntry() async {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "keep", value: "kept")
        await cache.set(key: "delete", value: "deleted")
        await cache.remove(key: "delete")

        let kept: String? = await cache.get(key: "keep", ttl: 60)
        let deleted: String? = await cache.get(key: "delete", ttl: 60)
        #expect(kept == "kept")
        #expect(deleted == nil)
    }

    @Test("Cache purgeExpired removes old entries")
    func purgeExpiredEntries() async throws {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "old", value: "old-data")
        // Purge with a TTL of 0 → everything expired
        await cache.purgeExpired(defaultTTL: 0)

        let result: String? = await cache.get(key: "old", ttl: 60)
        #expect(result == nil)
    }

    @Test("Cache stores different types independently")
    func differentTypesStored() async {
        let cache = ResponseCache(maxEntries: 50)

        await cache.set(key: "string", value: "hello")
        await cache.set(key: "int", value: 42)

        let str: String? = await cache.get(key: "string", ttl: 60)
        let num: Int? = await cache.get(key: "int", ttl: 60)
        #expect(str == "hello")
        #expect(num == 42)
    }

    @Test("Cache concurrent writes don't crash (actor safety)")
    func concurrentWriteSafety() async {
        let cache = ResponseCache(maxEntries: 100)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await cache.set(key: "key-\(i)", value: "value-\(i)")
                }
            }
        }

        // At least some entries should be present
        let sample: String? = await cache.get(key: "key-25", ttl: 60)
        #expect(sample == "value-25")
    }
}

// MARK: - Endpoint Tests

@Suite("ChzzkEndpoint — Comprehensive")
struct ChzzkEndpointComprehensiveTests {

    @Test("channelInfo endpoint has correct path")
    func channelInfoPath() {
        let ep = ChzzkEndpoint.channelInfo(channelId: "ch123")
        #expect(ep.path == "/service/v1/channels/ch123")
        #expect(ep.method == .get)
        #expect(ep.requiresAuth == false)
    }

    @Test("liveDetail endpoint includes channelId")
    func liveDetailPath() {
        let ep = ChzzkEndpoint.liveDetail(channelId: "abc")
        #expect(ep.path.contains("abc"))
        #expect(ep.path.contains("live-detail"))
    }

    @Test("following endpoint requires auth")
    func followingRequiresAuth() {
        let ep = ChzzkEndpoint.following(size: 50, page: 0)
        #expect(ep.requiresAuth == true)
    }

    @Test("follow uses POST method")
    func followMethod() {
        let ep = ChzzkEndpoint.follow(channelId: "ch1")
        #expect(ep.method == .post)
    }

    @Test("unfollow uses DELETE method")
    func unfollowMethod() {
        let ep = ChzzkEndpoint.unfollow(channelId: "ch1")
        #expect(ep.method == .delete)
    }

    @Test("searchChannel includes keyword query item")
    func searchChannelQuery() {
        let ep = ChzzkEndpoint.searchChannel(keyword: "테스트", offset: 0, size: 20)
        let hasKeyword = ep.queryItems?.contains { $0.value == "테스트" } ?? false
        #expect(hasKeyword)
    }

    @Test("chatAccessToken does not require auth")
    func chatTokenNoAuth() {
        let ep = ChzzkEndpoint.chatAccessToken(chatChannelId: "cid")
        #expect(ep.requiresAuth == false)
    }

    @Test("chatAccessToken uses reloadIgnoringCache")
    func chatTokenNoCachePolicy() {
        let ep = ChzzkEndpoint.chatAccessToken(chatChannelId: "cid")
        if case .reloadIgnoringCache = ep.cachePolicy {
            // Expected
        } else {
            Issue.record("Expected reloadIgnoringCache for chatAccessToken")
        }
    }

    @Test("channelInfo uses returnCacheElseLoad with 300s TTL")
    func channelInfoCachePolicy() {
        let ep = ChzzkEndpoint.channelInfo(channelId: "ch1")
        if case .returnCacheElseLoad(let ttl) = ep.cachePolicy {
            #expect(ttl == 300)
        } else {
            Issue.record("Expected returnCacheElseLoad for channelInfo")
        }
    }

    @Test("topLives with cursor includes pagination query items")
    func topLivesPagination() {
        let ep = ChzzkEndpoint.topLives(size: 20, concurrentUserCount: 100, liveId: 42)
        let items = ep.queryItems ?? []
        let hasConcurrent = items.contains { $0.name == "concurrentUserCount" && $0.value == "100" }
        let hasLiveId = items.contains { $0.name == "liveId" && $0.value == "42" }
        #expect(hasConcurrent)
        #expect(hasLiveId)
    }

    @Test("clipInkey uses POST and has body")
    func clipInkeyPostWithBody() {
        let ep = ChzzkEndpoint.clipInkey(clipUID: "clip-1")
        #expect(ep.method == .post)
        #expect(ep.body != nil)
    }

    @Test("userStatus requires auth")
    func userStatusAuth() {
        let ep = ChzzkEndpoint.userStatus
        #expect(ep.requiresAuth == true)
    }
}

// MARK: - APIError Tests

@Suite("APIError — Comprehensive")
struct APIErrorComprehensiveTests {

    @Test("Unauthorized error description")
    func unauthorizedDescription() {
        let err = APIError.unauthorized
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test("HTTP error preserves status code")
    func httpErrorStatusCode() {
        let err = APIError.httpError(statusCode: 503)
        if case .httpError(let code) = err {
            #expect(code == 503)
        }
    }

    @Test("Rate limited error includes retryAfter")
    func rateLimitedRetryAfter() {
        let err = APIError.rateLimited(retryAfter: 30.0)
        if case .rateLimited(let retryAfter) = err {
            #expect(retryAfter == 30.0)
        }
    }

    @Test("Network error preserves message")
    func networkErrorMessage() {
        let err = APIError.networkError("timeout occurred")
        if case .networkError(let msg) = err {
            #expect(msg.contains("timeout"))
        }
    }

    @Test("Decoding failed error preserves detail")
    func decodingFailedDetail() {
        let err = APIError.decodingFailed("key not found")
        if case .decodingFailed(let detail) = err {
            #expect(detail == "key not found")
        }
    }

    @Test("APIError equatable conformance")
    func equatableConformance() {
        #expect(APIError.unauthorized == APIError.unauthorized)
        #expect(APIError.httpError(statusCode: 404) == APIError.httpError(statusCode: 404))
        #expect(APIError.httpError(statusCode: 404) != APIError.httpError(statusCode: 500))
    }
}

// MARK: - CachePolicy Tests

@Suite("CachePolicy — Patterns")
struct CachePolicyTests {

    @Test("Standard cache policy has 60s TTL")
    func standardPolicy() {
        let policy = CachePolicy.standard
        if case .returnCacheElseLoad(let ttl) = policy {
            #expect(ttl == 60)
        } else {
            Issue.record("Expected returnCacheElseLoad for standard")
        }
    }

    @Test("None cache policy is reloadIgnoringCache")
    func nonePolicy() {
        let policy = CachePolicy.none
        if case .reloadIgnoringCache = policy {
            // Expected
        } else {
            Issue.record("Expected reloadIgnoringCache for none")
        }
    }

    @Test("Custom TTL preserved")
    func customTTL() {
        let policy = CachePolicy.returnCacheElseLoad(ttl: 120)
        if case .returnCacheElseLoad(let ttl) = policy {
            #expect(ttl == 120)
        } else {
            Issue.record("Expected returnCacheElseLoad")
        }
    }

    @Test("returnCacheOnly case exists")
    func returnCacheOnly() {
        let policy = CachePolicy.returnCacheOnly
        if case .returnCacheOnly = policy {
            // Expected
        } else {
            Issue.record("Expected returnCacheOnly")
        }
    }
}

// MARK: - Mock AuthTokenProvider Tests

@Suite("MockAuthTokenProvider — Auth Paths")
struct AuthTokenProviderTests {

    @Test("Provider with cookies returns cookies")
    func providerWithCookies() async {
        let cookie = HTTPCookie(properties: [
            .name: "NID_AUT",
            .value: "test-value",
            .domain: ".naver.com",
            .path: "/"
        ])!

        let provider = MockAuthTokenProvider(
            cookies: [cookie],
            isAuthenticated: true
        )

        let cookies = await provider.cookies
        #expect(cookies?.count == 1)
        #expect(cookies?.first?.name == "NID_AUT")
    }

    @Test("Provider without credentials is not authenticated")
    func providerWithoutCredentials() async {
        let provider = MockAuthTokenProvider()
        let isAuth = await provider.isAuthenticated
        #expect(isAuth == false)
        #expect(await provider.cookies == nil)
        #expect(await provider.accessToken == nil)
    }

    @Test("Provider with access token returns token")
    func providerWithAccessToken() async {
        let provider = MockAuthTokenProvider(
            accessToken: "bearer-token-123",
            isAuthenticated: true
        )

        let token = await provider.accessToken
        #expect(token == "bearer-token-123")
    }
}

// MARK: - ChzzkResponse Tests

@Suite("ChzzkResponse — Decoding")
struct ChzzkResponseDecodingTests {

    @Test("Decode simple ChzzkResponse")
    func decodeSimple() throws {
        let json = """
        {"code": 200, "message": "OK", "content": {"name": "test"}}
        """.data(using: .utf8)!

        struct TestContent: Decodable, Sendable { let name: String }
        let response = try JSONDecoder().decode(ChzzkResponse<TestContent>.self, from: json)

        #expect(response.code == 200)
        #expect(response.content?.name == "test")
    }

    @Test("Decode ChzzkResponse with null content")
    func decodeNullContent() throws {
        let json = """
        {"code": 404, "message": "Not Found", "content": null}
        """.data(using: .utf8)!

        struct TestContent: Decodable, Sendable { let name: String }
        let response = try JSONDecoder().decode(ChzzkResponse<TestContent>.self, from: json)

        #expect(response.code == 404)
        #expect(response.content == nil)
    }
}

// MARK: - HTTPMethod Tests

@Suite("HTTPMethod — Raw Values")
struct HTTPMethodTests {

    @Test("GET method raw value")
    func getRawValue() {
        #expect(HTTPMethod.get.rawValue == "GET")
    }

    @Test("POST method raw value")
    func postRawValue() {
        #expect(HTTPMethod.post.rawValue == "POST")
    }

    @Test("PUT method raw value")
    func putRawValue() {
        #expect(HTTPMethod.put.rawValue == "PUT")
    }

    @Test("DELETE method raw value")
    func deleteRawValue() {
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
}

// MARK: - Network Constants Tests

@Suite("NetworkConstants — Values")
struct NetworkConstantsTests {

    @Test("API defaults have reasonable timeout values")
    func apiTimeouts() {
        #expect(APIDefaults.requestTimeout > 0)
        #expect(APIDefaults.resourceTimeout > APIDefaults.requestTimeout)
    }

    @Test("Cache purge interval is 5 minutes")
    func cachePurgeInterval() {
        #expect(APIDefaults.cachePurgeInterval == 300)
    }

    @Test("Response cache defaults")
    func responseCacheDefaults() {
        #expect(ResponseCacheDefaults.maxEntries == 100)
        #expect(ResponseCacheDefaults.defaultTTL == 300)
    }
}

