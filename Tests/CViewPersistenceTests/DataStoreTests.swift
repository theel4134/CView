// MARK: - CViewPersistenceTests/DataStoreTests.swift
// DataStore actor CRUD 테스트 — 인메모리 SwiftData 컨테이너 사용
// Swift Testing + SwiftData @ModelActor @section attribute 호환 문제로 XCTest 사용

import XCTest
@testable import CViewPersistence
@testable import CViewCore

/// DataStore 타입 별칭 — SwiftData.DataStore 프로토콜과 이름 충돌 방지
private typealias AppDataStore = CViewPersistence.DataStore

/// 인메모리 DataStore 생성 헬퍼
private func makeInMemoryStore() throws -> AppDataStore {
    let container = try AppDataStore.createInMemoryContainer()
    return AppDataStore(modelContainer: container)
}

// MARK: - Channel Operations

final class DataStoreChannelTests: XCTestCase {

    func testSaveAndFetchFavoriteChannel() async throws {
        let store = try makeInMemoryStore()
        let info = ChannelInfo(channelId: "ch1", channelName: "테스트채널", channelImageURL: URL(string: "https://img.example.com/1.png"))

        try await store.saveChannel(info, isFavorite: true)
        let favorites = try await store.fetchFavoriteItems()

        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.channelId, "ch1")
        XCTAssertEqual(favorites.first?.channelName, "테스트채널")
        XCTAssertEqual(favorites.first?.imageURL, "https://img.example.com/1.png")
    }

    func testSaveNonFavoriteChannel() async throws {
        let store = try makeInMemoryStore()
        let info = ChannelInfo(channelId: "ch2", channelName: "일반채널")

        try await store.saveChannel(info, isFavorite: false)
        let favorites = try await store.fetchFavoriteItems()

        XCTAssertTrue(favorites.isEmpty)
    }

    func testSaveChannelUpdatesExisting() async throws {
        let store = try makeInMemoryStore()
        let info1 = ChannelInfo(channelId: "ch1", channelName: "원래이름")
        let info2 = ChannelInfo(channelId: "ch1", channelName: "변경이름", channelImageURL: URL(string: "https://new.png"))

        try await store.saveChannel(info1, isFavorite: true)
        try await store.saveChannel(info2, isFavorite: true)

        let favorites = try await store.fetchFavoriteItems()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.channelName, "변경이름")
        XCTAssertEqual(favorites.first?.imageURL, "https://new.png")
    }

    func testToggleFavorite() async throws {
        let store = try makeInMemoryStore()
        let info = ChannelInfo(channelId: "ch1", channelName: "채널")
        try await store.saveChannel(info, isFavorite: false)

        let result1 = try await store.toggleFavorite(channelId: "ch1")
        XCTAssertTrue(result1)

        let result2 = try await store.toggleFavorite(channelId: "ch1")
        XCTAssertFalse(result2)
    }

    func testToggleFavoriteNonExistent() async throws {
        let store = try makeInMemoryStore()
        let result = try await store.toggleFavorite(channelId: "nonexistent")
        XCTAssertFalse(result)
    }

    func testIsFavoriteCheck() async throws {
        let store = try makeInMemoryStore()
        let info = ChannelInfo(channelId: "ch1", channelName: "채널")
        try await store.saveChannel(info, isFavorite: true)

        let isFav = try await store.isFavorite(channelId: "ch1")
        XCTAssertTrue(isFav)
        let isNotFav = try await store.isFavorite(channelId: "unknown")
        XCTAssertFalse(isNotFav)
    }

    func testFetchFavoriteItems() async throws {
        let store = try makeInMemoryStore()
        try await store.saveChannel(ChannelInfo(channelId: "c1", channelName: "A채널"), isFavorite: true)
        try await store.saveChannel(ChannelInfo(channelId: "c2", channelName: "B채널"), isFavorite: true)
        try await store.saveChannel(ChannelInfo(channelId: "c3", channelName: "C채널"), isFavorite: false)

        let items = try await store.fetchFavoriteItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].channelName, "A채널")
        XCTAssertEqual(items[1].channelName, "B채널")
    }
}

// MARK: - Recently Watched

final class DataStoreRecentlyWatchedTests: XCTestCase {

    func testUpdateLastWatchedAndFetch() async throws {
        let store = try makeInMemoryStore()
        let info = ChannelInfo(channelId: "ch1", channelName: "채널1")
        try await store.saveChannel(info)
        try await store.updateLastWatched(channelId: "ch1")

        let recent = try await store.fetchRecentItems()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.channelId, "ch1")
        XCTAssertNotNil(recent.first?.lastWatched)
    }

    func testNoLastWatchedExcluded() async throws {
        let store = try makeInMemoryStore()
        try await store.saveChannel(ChannelInfo(channelId: "ch1", channelName: "채널1"))

        let recent = try await store.fetchRecentItems()
        XCTAssertTrue(recent.isEmpty)
    }

    func testRecentlyWatchedLimit() async throws {
        let store = try makeInMemoryStore()
        for i in 1...5 {
            try await store.saveChannel(ChannelInfo(channelId: "ch\(i)", channelName: "채널\(i)"))
            try await store.updateLastWatched(channelId: "ch\(i)")
        }

        let recent = try await store.fetchRecentItems(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func testFetchRecentItems() async throws {
        let store = try makeInMemoryStore()
        try await store.saveChannel(ChannelInfo(channelId: "ch1", channelName: "채널1"))
        try await store.updateLastWatched(channelId: "ch1")

        let items = try await store.fetchRecentItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.channelId, "ch1")
        XCTAssertNotNil(items.first?.lastWatched)
    }
}

// MARK: - Memo Operations

final class DataStoreMemoTests: XCTestCase {

    func testSaveMemoAndFetch() async throws {
        let store = try makeInMemoryStore()
        try await store.saveChannel(ChannelInfo(channelId: "ch1", channelName: "채널"))
        try await store.saveMemo(channelId: "ch1", memo: "좋은 채널!")

        let memo = try await store.fetchMemo(channelId: "ch1")
        XCTAssertEqual(memo, "좋은 채널!")
    }

    func testSaveEmptyMemoBecomesNil() async throws {
        let store = try makeInMemoryStore()
        try await store.saveChannel(ChannelInfo(channelId: "ch1", channelName: "채널"))
        try await store.saveMemo(channelId: "ch1", memo: "임시메모")
        try await store.saveMemo(channelId: "ch1", memo: "")

        let memo = try await store.fetchMemo(channelId: "ch1")
        XCTAssertEqual(memo, "")
    }

    func testFetchMemoNonExistent() async throws {
        let store = try makeInMemoryStore()
        let memo = try await store.fetchMemo(channelId: "unknown")
        XCTAssertEqual(memo, "")
    }
}

// MARK: - Settings Operations

final class DataStoreSettingsTests: XCTestCase {

    func testSaveAndLoadStringSettings() async throws {
        let store = try makeInMemoryStore()
        try await store.saveSetting(key: "testKey", value: "testValue")

        let loaded = try await store.loadSetting(key: "testKey", as: String.self)
        XCTAssertEqual(loaded, "testValue")
    }

    func testSaveAndLoadIntSettings() async throws {
        let store = try makeInMemoryStore()
        try await store.saveSetting(key: "count", value: 42)

        let loaded = try await store.loadSetting(key: "count", as: Int.self)
        XCTAssertEqual(loaded, 42)
    }

    func testSaveAndLoadBoolSettings() async throws {
        let store = try makeInMemoryStore()
        try await store.saveSetting(key: "enabled", value: true)

        let loaded = try await store.loadSetting(key: "enabled", as: Bool.self)
        XCTAssertEqual(loaded, true)
    }

    func testSettingOverwrite() async throws {
        let store = try makeInMemoryStore()
        try await store.saveSetting(key: "val", value: "old")
        try await store.saveSetting(key: "val", value: "new")

        let loaded = try await store.loadSetting(key: "val", as: String.self)
        XCTAssertEqual(loaded, "new")
    }

    func testLoadNonExistent() async throws {
        let store = try makeInMemoryStore()
        let loaded = try await store.loadSetting(key: "missing", as: String.self)
        XCTAssertNil(loaded)
    }

    func testSaveAndLoadCodableStruct() async throws {
        let store = try makeInMemoryStore()
        let settings = PlayerSettings.default
        try await store.saveSetting(key: "player", value: settings)

        let loaded = try await store.loadSetting(key: "player", as: PlayerSettings.self)
        XCTAssertEqual(loaded, settings)
    }
}

// MARK: - Statistics Operations

final class DataStoreStatisticsTests: XCTestCase {

    func testSaveStatistic() async throws {
        let store = try makeInMemoryStore()
        try await store.saveStatistic(channelId: "ch1", viewerCount: 1500, latency: 2.5)
    }
}

// MARK: - Watch History

final class DataStoreWatchHistoryTests: XCTestCase {

    func testStartWatchRecordAndFetch() async throws {
        let store = try makeInMemoryStore()
        _ = try await store.startWatchRecord(
            channelId: "ch1",
            channelName: "테스트채널",
            thumbnailURL: "https://thumb.png",
            categoryName: "게임"
        )

        let history = try await store.fetchWatchHistory(limit: 10)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.channelId, "ch1")
        XCTAssertEqual(history.first?.channelName, "테스트채널")
        XCTAssertEqual(history.first?.thumbnailURL, "https://thumb.png")
        XCTAssertEqual(history.first?.categoryName, "게임")
        XCTAssertNil(history.first?.endedAt)
    }

    func testEndWatchRecord() async throws {
        let store = try makeInMemoryStore()
        let startDate = Date.now
        _ = try await store.startWatchRecord(channelId: "ch1", channelName: "채널")

        try await Task.sleep(for: .milliseconds(50))
        try await store.endWatchRecord(channelId: "ch1", startedAt: startDate)

        let history = try await store.fetchWatchHistory()
        XCTAssertNotNil(history.first?.endedAt)
        XCTAssertGreaterThan(history.first!.duration, 0)
    }

    func testTotalWatchTime() async throws {
        let store = try makeInMemoryStore()
        _ = try await store.startWatchRecord(channelId: "ch1", channelName: "채널1")
        _ = try await store.startWatchRecord(channelId: "ch2", channelName: "채널2")

        let total = try await store.totalWatchTime()
        XCTAssertGreaterThanOrEqual(total, 0)
    }

    func testWatchHistoryLimit() async throws {
        let store = try makeInMemoryStore()
        for i in 1...5 {
            _ = try await store.startWatchRecord(channelId: "ch\(i)", channelName: "채널\(i)")
        }

        let history = try await store.fetchWatchHistory(limit: 3)
        XCTAssertEqual(history.count, 3)
    }

    func testWatchTimeByChannel() async throws {
        let store = try makeInMemoryStore()
        _ = try await store.startWatchRecord(channelId: "ch1", channelName: "채널1")
        _ = try await store.startWatchRecord(channelId: "ch2", channelName: "채널2")

        let byChannel = try await store.watchTimeByChannel(limit: 10)
        XCTAssertEqual(byChannel.count, 2)
    }

    func testCleanupOldWatchHistory() async throws {
        let store = try makeInMemoryStore()
        _ = try await store.startWatchRecord(channelId: "ch1", channelName: "채널")

        try await store.cleanupOldWatchHistory(olderThan: 0)

        let history = try await store.fetchWatchHistory()
        XCTAssertTrue(history.isEmpty)
    }
}
