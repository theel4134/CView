// MARK: - CViewPersistenceTests/DTOTests.swift
// Sendable DTO 모델 테스트 — WatchHistoryData, ChannelListData

import Testing
import Foundation
@testable import CViewPersistence

// MARK: - WatchHistoryData

@Suite("WatchHistoryData — DTO 속성")
struct WatchHistoryDataTests {

    @Test("id 형식 — channelId-timestamp")
    func idFormat() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: nil,
            categoryName: nil,
            startedAt: date,
            endedAt: nil,
            duration: 0
        )
        #expect(data.id == "ch1-1700000000.0")
    }

    @Test("formattedDuration — 분만 표시")
    func formattedDurationMinutesOnly() {
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: nil,
            categoryName: nil,
            startedAt: .now,
            endedAt: nil,
            duration: 1500  // 25분
        )
        #expect(data.formattedDuration == "25분")
    }

    @Test("formattedDuration — 시간+분 표시")
    func formattedDurationHoursAndMinutes() {
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: nil,
            categoryName: nil,
            startedAt: .now,
            endedAt: nil,
            duration: 5400  // 1시간 30분
        )
        #expect(data.formattedDuration == "1시간 30분")
    }

    @Test("formattedDuration — 0초")
    func formattedDurationZero() {
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: nil,
            categoryName: nil,
            startedAt: .now,
            endedAt: nil,
            duration: 0
        )
        #expect(data.formattedDuration == "0분")
    }

    @Test("formattedDate — MM/dd HH:mm 포맷")
    func formattedDate() {
        // 2023-11-15 14:30:00 UTC
        let date = Date(timeIntervalSince1970: 1700058600)
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: nil,
            categoryName: nil,
            startedAt: date,
            endedAt: nil,
            duration: 0
        )
        // 로케일에 따라 다를 수 있으므로 형식만 검증
        let formatted = data.formattedDate
        #expect(formatted.contains("/"))
        #expect(formatted.contains(":"))
    }

    @Test("모든 필드 초기화 확인")
    func allFields() {
        let start = Date.now
        let end = start.addingTimeInterval(3600)
        let data = WatchHistoryData(
            channelId: "ch1",
            channelName: "채널",
            thumbnailURL: "https://thumb.png",
            categoryName: "게임",
            startedAt: start,
            endedAt: end,
            duration: 3600
        )
        #expect(data.channelId == "ch1")
        #expect(data.channelName == "채널")
        #expect(data.thumbnailURL == "https://thumb.png")
        #expect(data.categoryName == "게임")
        #expect(data.startedAt == start)
        #expect(data.endedAt == end)
        #expect(data.duration == 3600)
    }
}

// MARK: - ChannelListData

@Suite("ChannelListData — DTO 속성")
struct ChannelListDataTests {

    @Test("id는 channelId")
    func idEqualsChannelId() {
        let data = ChannelListData(
            channelId: "abc123",
            channelName: "채널",
            imageURL: nil,
            isFavorite: false,
            lastWatched: nil
        )
        #expect(data.id == "abc123")
    }

    @Test("모든 필드 초기화")
    func allFields() {
        let date = Date.now
        let data = ChannelListData(
            channelId: "ch1",
            channelName: "테스트채널",
            imageURL: "https://img.png",
            isFavorite: true,
            lastWatched: date
        )
        #expect(data.channelId == "ch1")
        #expect(data.channelName == "테스트채널")
        #expect(data.imageURL == "https://img.png")
        #expect(data.isFavorite == true)
        #expect(data.lastWatched == date)
    }

    @Test("imageURL nil 허용")
    func imageURLNil() {
        let data = ChannelListData(
            channelId: "ch1",
            channelName: "채널",
            imageURL: nil,
            isFavorite: false,
            lastWatched: nil
        )
        #expect(data.imageURL == nil)
        #expect(data.lastWatched == nil)
    }
}
