// MARK: - DashboardModelsTests.swift
// CViewCore 대시보드 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - CategoryTypeStat Tests

@Suite("CategoryTypeStat")
struct CategoryTypeStatTests {

    @Test("displayName(for:) — GAME")
    func displayNameGame() {
        #expect(CategoryTypeStat.displayName(for: "GAME") == "게임")
    }

    @Test("displayName(for:) — SPORTS")
    func displayNameSports() {
        #expect(CategoryTypeStat.displayName(for: "SPORTS") == "스포츠")
    }

    @Test("displayName(for:) — unknown → 기타")
    func displayNameOther() {
        #expect(CategoryTypeStat.displayName(for: "MUSIC") == "기타")
        #expect(CategoryTypeStat.displayName(for: "") == "기타")
    }
}

// MARK: - ViewerHistoryEntry Tests

@Suite("ViewerHistoryEntry")
struct ViewerHistoryEntryTests {

    @Test("init 및 프로퍼티")
    func initAndProperties() {
        let date = Date()
        let entry = ViewerHistoryEntry(timestamp: date, totalViewers: 5000)
        #expect(entry.timestamp == date)
        #expect(entry.totalViewers == 5000)
    }
}

// MARK: - CategoryStat Tests

@Suite("CategoryStat")
struct CategoryStatTests {

    @Test("init 및 프로퍼티")
    func initAndProperties() {
        let stat = CategoryStat(id: "cat1", name: "게임", channelCount: 10, totalViewers: 50000)
        #expect(stat.id == "cat1")
        #expect(stat.name == "게임")
        #expect(stat.channelCount == 10)
        #expect(stat.totalViewers == 50000)
    }
}

// MARK: - ViewerBucket Tests

@Suite("ViewerBucket")
struct ViewerBucketTests {

    @Test("init 및 프로퍼티")
    func initAndProperties() {
        let bucket = ViewerBucket(id: "b1", label: "100-500", count: 25, minViewers: 100, maxViewers: 500)
        #expect(bucket.id == "b1")
        #expect(bucket.label == "100-500")
        #expect(bucket.count == 25)
        #expect(bucket.minViewers == 100)
        #expect(bucket.maxViewers == 500)
    }
}

// MARK: - LatencyHistoryEntry Tests

@Suite("LatencyHistoryEntry")
struct LatencyHistoryEntryTests {

    @Test("init 및 프로퍼티")
    func initAndProperties() {
        let date = Date()
        let entry = LatencyHistoryEntry(timestamp: date, webLatency: 1.5, appLatency: 0.8)
        #expect(entry.timestamp == date)
        #expect(entry.webLatency == 1.5)
        #expect(entry.appLatency == 0.8)
    }
}
