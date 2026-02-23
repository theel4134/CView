// MARK: - CViewNetworkingTests.swift
// CViewNetworking module tests

import Testing
import Foundation
@testable import CViewNetworking
@testable import CViewCore

@Suite("ChzzkEndpoint")
struct ChzzkEndpointTests {
    
    @Test("Live detail endpoint builds correct path")
    func liveDetailPath() {
        let endpoint = ChzzkEndpoint.liveDetail(channelId: "abc123")
        #expect(endpoint.path.contains("abc123"))
    }
    
    @Test("Search channel endpoint includes query parameter")
    func searchQuery() {
        let endpoint = ChzzkEndpoint.searchChannel(keyword: "test", offset: 0, size: 20)
        #expect(endpoint.queryItems?.contains { $0.value == "test" } == true)
    }
}

@Suite("ResponseCache")
struct ResponseCacheTests {
    
    @Test("Cache stores and retrieves data")
    func storeRetrieve() async {
        let cache = ResponseCache(maxEntries: 10)
        let data = "hello"
        
        await cache.set(key: "key1", value: data)
        let retrieved: String? = await cache.get(key: "key1", ttl: 60)
        
        #expect(retrieved == data)
    }
    
    @Test("Cache returns nil for missing key")
    func missingKey() async {
        let cache = ResponseCache(maxEntries: 10)
        let retrieved: String? = await cache.get(key: "nonexistent", ttl: 60)
        #expect(retrieved == nil)
    }
}
