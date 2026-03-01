// MARK: - ResponseCacheTests.swift
// Comprehensive unit tests for ResponseCache

import Testing
import Foundation
@testable import CViewNetworking
@testable import CViewCore

// MARK: - Basic Set / Get

@Suite("ResponseCache — Set & Get")
struct ResponseCacheSetGetTests {

    @Test("Set and get a String value")
    func setGetString() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "greeting", value: "hello")
        let result: String? = await cache.get(key: "greeting", ttl: 60)
        #expect(result == "hello")
    }

    @Test("Set and get an Int value")
    func setGetInt() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "count", value: 42)
        let result: Int? = await cache.get(key: "count", ttl: 60)
        #expect(result == 42)
    }

    @Test("Set and get an Array value")
    func setGetArray() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "list", value: [1, 2, 3])
        let result: [Int]? = await cache.get(key: "list", ttl: 60)
        #expect(result == [1, 2, 3])
    }

    @Test("Set and get a custom Sendable struct")
    func setGetCustomStruct() async {
        struct MyData: Sendable, Equatable {
            let name: String
            let value: Int
        }
        let cache = ResponseCache(maxEntries: 10)
        let data = MyData(name: "test", value: 99)
        await cache.set(key: "custom", value: data)
        let result: MyData? = await cache.get(key: "custom", ttl: 60)
        #expect(result == data)
    }

    @Test("Overwrite existing key with new value")
    func overwriteKey() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "key", value: "old")
        await cache.set(key: "key", value: "new")
        let result: String? = await cache.get(key: "key", ttl: 60)
        #expect(result == "new")
    }

    @Test("Multiple keys stored independently")
    func multipleKeys() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "a", value: "alpha")
        await cache.set(key: "b", value: "beta")
        await cache.set(key: "c", value: "gamma")

        let a: String? = await cache.get(key: "a", ttl: 60)
        let b: String? = await cache.get(key: "b", ttl: 60)
        let c: String? = await cache.get(key: "c", ttl: 60)

        #expect(a == "alpha")
        #expect(b == "beta")
        #expect(c == "gamma")
    }
}

// MARK: - Missing Key & Type Mismatch

@Suite("ResponseCache — Missing Key")
struct ResponseCacheMissingTests {

    @Test("Get with missing key returns nil")
    func missingKeyReturnsNil() async {
        let cache = ResponseCache(maxEntries: 10)
        let result: String? = await cache.get(key: "nonexistent", ttl: 60)
        #expect(result == nil)
    }

    @Test("Get with wrong type returns nil")
    func wrongTypeReturnsNil() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "num", value: 42)
        // Try to retrieve as String
        let result: String? = await cache.get(key: "num", ttl: 60)
        #expect(result == nil)
    }

    @Test("Get after remove returns nil")
    func removeKey() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "key", value: "value")
        await cache.remove(key: "key")
        let result: String? = await cache.get(key: "key", ttl: 60)
        #expect(result == nil)
    }

    @Test("Remove nonexistent key does not crash")
    func removeNonexistent() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.remove(key: "doesNotExist")
        // Should not throw or crash
    }
}

// MARK: - TTL Expiration

@Suite("ResponseCache — TTL Expiration")
struct ResponseCacheTTLTests {

    @Test("Get returns nil when TTL has expired")
    func ttlExpired() async throws {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "ephemeral", value: "data")

        // Use a very short TTL; the entry was just set, so it should be nearly 0 age
        // We can't easily wait in unit tests, so use TTL=0 to simulate expiry
        let result: String? = await cache.get(key: "ephemeral", ttl: 0)
        #expect(result == nil)
    }

    @Test("Get returns value when within TTL")
    func withinTTL() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "fresh", value: "data")
        // Large TTL — entry was just set
        let result: String? = await cache.get(key: "fresh", ttl: 3600)
        #expect(result == "data")
    }

    @Test("purgeExpired removes old entries")
    func purgeExpired() async {
        let cache = ResponseCache(maxEntries: 100)
        await cache.set(key: "item", value: "value")

        // Purge with TTL=0 means everything is expired
        await cache.purgeExpired(defaultTTL: 0)

        let result: String? = await cache.get(key: "item", ttl: 3600)
        #expect(result == nil)
    }

    @Test("purgeExpired keeps fresh entries")
    func purgeKeepsFresh() async {
        let cache = ResponseCache(maxEntries: 100)
        await cache.set(key: "fresh", value: "keep-me")

        // Purge with large TTL — entry was just set
        await cache.purgeExpired(defaultTTL: 3600)

        let result: String? = await cache.get(key: "fresh", ttl: 3600)
        #expect(result == "keep-me")
    }
}

// MARK: - Cache Eviction

@Suite("ResponseCache — Eviction")
struct ResponseCacheEvictionTests {

    @Test("Eviction triggered when maxEntries exceeded")
    func evictionOnOverflow() async {
        let cache = ResponseCache(maxEntries: 4)

        // Fill to capacity
        await cache.set(key: "a", value: 1)
        await cache.set(key: "b", value: 2)
        await cache.set(key: "c", value: 3)
        await cache.set(key: "d", value: 4)

        // This should trigger eviction (removes oldest 25% = 1 entry)
        await cache.set(key: "e", value: 5)

        // The newest entry should be present
        let e: Int? = await cache.get(key: "e", ttl: 60)
        #expect(e == 5)
    }

    @Test("After eviction, some old entries are removed")
    func evictionRemovesOldest() async {
        let cache = ResponseCache(maxEntries: 4)

        await cache.set(key: "oldest", value: 1)
        await cache.set(key: "b", value: 2)
        await cache.set(key: "c", value: 3)
        await cache.set(key: "d", value: 4)

        // Trigger eviction — "oldest" should be removed (25% of 4 = 1)
        await cache.set(key: "e", value: 5)

        let oldest: Int? = await cache.get(key: "oldest", ttl: 60)
        #expect(oldest == nil, "Oldest entry should have been evicted")
    }

    @Test("Cache with maxEntries=1 evicts on every new set")
    func singleEntryCache() async {
        let cache = ResponseCache(maxEntries: 1)

        await cache.set(key: "first", value: "A")
        let first: String? = await cache.get(key: "first", ttl: 60)
        #expect(first == "A")

        await cache.set(key: "second", value: "B")
        let afterFirst: String? = await cache.get(key: "first", ttl: 60)
        let second: String? = await cache.get(key: "second", ttl: 60)
        #expect(afterFirst == nil)
        #expect(second == "B")
    }
}

// MARK: - Clear

@Suite("ResponseCache — Clear")
struct ResponseCacheClearTests {

    @Test("Clear removes all entries")
    func clearAll() async {
        let cache = ResponseCache(maxEntries: 100)
        await cache.set(key: "a", value: 1)
        await cache.set(key: "b", value: 2)
        await cache.set(key: "c", value: 3)

        await cache.clear()

        let a: Int? = await cache.get(key: "a", ttl: 60)
        let b: Int? = await cache.get(key: "b", ttl: 60)
        let c: Int? = await cache.get(key: "c", ttl: 60)
        #expect(a == nil)
        #expect(b == nil)
        #expect(c == nil)
    }

    @Test("Clear on empty cache does not crash")
    func clearEmpty() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.clear()
        // Should not throw
    }

    @Test("Set after clear works normally")
    func setAfterClear() async {
        let cache = ResponseCache(maxEntries: 10)
        await cache.set(key: "old", value: "data")
        await cache.clear()
        await cache.set(key: "new", value: "fresh")
        let result: String? = await cache.get(key: "new", ttl: 60)
        #expect(result == "fresh")
    }
}

// MARK: - Default Configuration

@Suite("ResponseCache — Defaults")
struct ResponseCacheDefaultsTests {

    @Test("Default maxEntries matches constant")
    func defaultMaxEntries() {
        #expect(ResponseCacheDefaults.maxEntries == 200)
    }

    @Test("Default TTL matches constant")
    func defaultTTL() {
        #expect(ResponseCacheDefaults.defaultTTL == 300)
    }

    @Test("Default init creates cache with default maxEntries")
    func defaultInit() async {
        let cache = ResponseCache()
        // Should work without crash — can hold at least 200 entries
        for i in 0..<50 {
            await cache.set(key: "key-\(i)", value: i)
        }
        let result: Int? = await cache.get(key: "key-25", ttl: 60)
        #expect(result == 25)
    }
}
