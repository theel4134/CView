// MARK: - CViewPersistenceTests/SettingsStoreMetricsNormalizationTests.swift
// SettingsStore metrics 정규화 저장/로드 경계 테스트

import XCTest
@testable import CViewPersistence
@testable import CViewCore

private typealias AppDataStore = CViewPersistence.DataStore

private func makeInMemoryStoreForSettingsStoreMetricsTests() throws -> AppDataStore {
    let container = try AppDataStore.createInMemoryContainer()
    return AppDataStore(modelContainer: container)
}

private struct LegacyMetricsSettingsPayload: Codable, Sendable {
    let metricsEnabled: Bool
    let serverURL: String
    let forwardInterval: TimeInterval
    let pingInterval: TimeInterval
}

final class SettingsStoreMetricsNormalizationTests: XCTestCase {

    func testSaveNormalizesMetricsBeforePersisting() async throws {
        let store = try makeInMemoryStoreForSettingsStoreMetricsTests()
        let settingsStore = await MainActor.run { SettingsStore(dataStore: store) }

        await MainActor.run {
            settingsStore.metrics = MetricsSettings(
                metricsEnabled: true,
                serverURL: "cv.dododo.app",
                forwardInterval: -1,
                pingInterval: 10_000
            )
        }

        await settingsStore.save()
        let persisted = try await store.loadSetting(key: "metrics", as: MetricsSettings.self)

        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.metricsEnabled, true)
        XCTAssertEqual(persisted?.serverURL, "https://cv.dododo.app")
        XCTAssertEqual(persisted?.forwardInterval, MetricsSettings.minForwardInterval)
        XCTAssertEqual(persisted?.pingInterval, MetricsSettings.maxPingInterval)
    }

    func testLoadLegacyPayloadIsNormalizedAndStaysNormalized() async throws {
        let store = try makeInMemoryStoreForSettingsStoreMetricsTests()
        let legacy = LegacyMetricsSettingsPayload(
            metricsEnabled: true,
            serverURL: "   ",
            forwardInterval: 0.1,
            pingInterval: 9999
        )
        try await store.saveSetting(key: "metrics", value: legacy)

        let settingsStore = await MainActor.run { SettingsStore(dataStore: store) }
        await settingsStore.load()

        let loadedMetrics = await MainActor.run { settingsStore.metrics }
        XCTAssertEqual(loadedMetrics.serverURL, MetricsSettings.defaultServerURL)
        XCTAssertEqual(loadedMetrics.forwardInterval, MetricsSettings.minForwardInterval)
        XCTAssertEqual(loadedMetrics.pingInterval, MetricsSettings.maxPingInterval)

        await settingsStore.save()
        let persisted = try await store.loadSetting(key: "metrics", as: MetricsSettings.self)
        XCTAssertEqual(persisted?.serverURL, MetricsSettings.defaultServerURL)
        XCTAssertEqual(persisted?.forwardInterval, MetricsSettings.minForwardInterval)
        XCTAssertEqual(persisted?.pingInterval, MetricsSettings.maxPingInterval)
    }
}
