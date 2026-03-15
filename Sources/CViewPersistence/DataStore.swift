// MARK: - CViewPersistence/DataStore.swift
// SwiftData 기반 통합 데이터 저장소

import Foundation
import SwiftData
import CViewCore

/// 통합 데이터 저장소 (actor 기반)
@ModelActor
public actor DataStore {

    // MARK: - Schema Configuration

    public static let schema = Schema([
        PersistedChannel.self,
        PersistedStatistic.self,
        PersistedSetting.self,
        WatchHistory.self,
    ])

    public static func createContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            "CView_v2",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 테스트용 인메모리 컨테이너
    public static func createInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Channel Operations

    /// 채널 저장/업데이트
    public func saveChannel(_ info: ChannelInfo, isFavorite: Bool = false) throws {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == info.channelId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.channelName = info.channelName
            existing.imageURL = info.channelImageURL?.absoluteString
        } else {
            let channel = PersistedChannel(
                channelId: info.channelId,
                channelName: info.channelName,
                imageURL: info.channelImageURL?.absoluteString,
                isFavorite: isFavorite
            )
            modelContext.insert(channel)
        }
        try modelContext.save()
    }

    /// 즐겨찾기 채널 목록 조회
    public func fetchFavorites() throws -> [PersistedChannel] {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.channelName)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// 즐겨찾기 토글
    public func toggleFavorite(channelId: String) throws -> Bool {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )

        guard let channel = try modelContext.fetch(descriptor).first else {
            return false
        }

        channel.isFavorite.toggle()
        try modelContext.save()
        return channel.isFavorite
    }

    /// 최근 시청 채널 목록
    public func fetchRecentlyWatched(limit: Int = 20) throws -> [PersistedChannel] {
        var descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.lastWatched != nil },
            sortBy: [SortDescriptor(\.lastWatched, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    /// 시청 기록 업데이트
    public func updateLastWatched(channelId: String) throws {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )

        if let channel = try modelContext.fetch(descriptor).first {
            channel.lastWatched = .now
            try modelContext.save()
        }
    }

    /// 즐겨찾기 여부 확인 (Sendable-safe Bool 반환)
    public func isFavorite(channelId: String) throws -> Bool {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        guard let channel = try modelContext.fetch(descriptor).first else {
            return false
        }
        return channel.isFavorite
    }

    /// 즐겨찾기 항목을 Sendable 튜플로 반환
    public func fetchFavoriteItems() throws -> [ChannelListData] {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.channelName)]
        )
        return try modelContext.fetch(descriptor).map {
            ChannelListData(
                channelId: $0.channelId,
                channelName: $0.channelName,
                imageURL: $0.imageURL,
                isFavorite: $0.isFavorite,
                lastWatched: $0.lastWatched
            )
        }
    }

    /// 최근 시청 항목을 Sendable 구조체로 반환
    public func fetchRecentItems(limit: Int = 20) throws -> [ChannelListData] {
        var descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.lastWatched != nil },
            sortBy: [SortDescriptor(\.lastWatched, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map {
            ChannelListData(
                channelId: $0.channelId,
                channelName: $0.channelName,
                imageURL: $0.imageURL,
                isFavorite: $0.isFavorite,
                lastWatched: $0.lastWatched
            )
        }
    }

    // MARK: - Memo Operations

    /// 채널 메모 저장
    public func saveMemo(channelId: String, memo: String) throws {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        if let channel = try modelContext.fetch(descriptor).first {
            channel.memo = memo.isEmpty ? nil : memo
            try modelContext.save()
        }
    }

    /// 채널 메모 조회
    public func fetchMemo(channelId: String) throws -> String {
        let descriptor = FetchDescriptor<PersistedChannel>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        return try modelContext.fetch(descriptor).first?.memo ?? ""
    }

    // MARK: - Settings Operations

    /// 설정 저장
    public func saveSetting<T: Codable & Sendable>(key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)

        let descriptor = FetchDescriptor<PersistedSetting>(
            predicate: #Predicate { $0.key == key }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.valueData = data
            existing.updatedAt = .now
        } else {
            let setting = PersistedSetting(key: key, valueData: data)
            modelContext.insert(setting)
        }
        try modelContext.save()
    }

    /// 설정 읽기
    public func loadSetting<T: Codable & Sendable>(key: String, as type: T.Type) throws -> T? {
        let descriptor = FetchDescriptor<PersistedSetting>(
            predicate: #Predicate { $0.key == key }
        )

        guard let setting = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return try JSONDecoder().decode(type, from: setting.valueData)
    }

    // MARK: - Statistics Operations

    /// 통계 기록 저장
    public func saveStatistic(channelId: String, viewerCount: Int, latency: Double?) throws {
        let stat = PersistedStatistic(
            channelId: channelId,
            viewerCount: viewerCount,
            averageLatency: latency
        )
        modelContext.insert(stat)
        try modelContext.save()
    }

    // MARK: - Watch History Operations

    /// 시청 기록 시작 (시청 시작 시 호출)
    public func startWatchRecord(
        channelId: String,
        channelName: String,
        thumbnailURL: String? = nil,
        categoryName: String? = nil
    ) throws -> String {
        let record = WatchHistory(
            channelId: channelId,
            channelName: channelName,
            thumbnailURL: thumbnailURL,
            categoryName: categoryName
        )
        modelContext.insert(record)
        try modelContext.save()
        return "\(channelId)-\(record.startedAt.timeIntervalSince1970)"
    }

    /// 시청 기록 종료 (시청 종료 시 호출)
    public func endWatchRecord(channelId: String, startedAt: Date) throws {
        // startedAt ±1초 범위로 정확한 레코드 매칭
        let matchStart = startedAt.addingTimeInterval(-1)
        let matchEnd = startedAt.addingTimeInterval(1)
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate {
                $0.channelId == channelId && $0.endedAt == nil
                && $0.startedAt >= matchStart && $0.startedAt <= matchEnd
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let record = try modelContext.fetch(descriptor).first {
            record.endedAt = .now
            record.duration = Date.now.timeIntervalSince(record.startedAt)
            try modelContext.save()
        }
    }

    /// 최근 시청 기록 조회
    public func fetchWatchHistory(limit: Int = 50) throws -> [WatchHistoryData] {
        var descriptor = FetchDescriptor<WatchHistory>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map {
            WatchHistoryData(
                channelId: $0.channelId,
                channelName: $0.channelName,
                thumbnailURL: $0.thumbnailURL,
                categoryName: $0.categoryName,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                duration: $0.duration
            )
        }
    }

    /// 총 시청 시간 (초)
    public func totalWatchTime() throws -> TimeInterval {
        let descriptor = FetchDescriptor<WatchHistory>()
        let records = try modelContext.fetch(descriptor)
        return records.reduce(0) { $0 + $1.duration }
    }

    /// 채널별 시청 시간 통계
    public func watchTimeByChannel(limit: Int = 10) throws -> [(channelName: String, duration: TimeInterval)] {
        let descriptor = FetchDescriptor<WatchHistory>()
        let records = try modelContext.fetch(descriptor)

        var channelMap: [String: (name: String, duration: TimeInterval)] = [:]
        for record in records {
            let existing = channelMap[record.channelId] ?? (record.channelName, 0)
            channelMap[record.channelId] = (existing.name, existing.duration + record.duration)
        }

        return channelMap.values
            .sorted { $0.duration > $1.duration }
            .prefix(limit)
            .map { (channelName: $0.name, duration: $0.duration) }
    }

    /// 오래된 시청 기록 정리 (30일 이전)
    public func cleanupOldWatchHistory(olderThan days: Int = 30) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate { $0.startedAt < cutoff }
        )
        let old = try modelContext.fetch(descriptor)
        for record in old {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

// MARK: - Sendable DTO for cross-actor boundary

/// DataStore에서 View로 전달되는 Sendable 채널 데이터
public struct ChannelListData: Sendable, Identifiable {
    public let channelId: String
    public let channelName: String
    public let imageURL: String?
    public let isFavorite: Bool
    public let lastWatched: Date?
    
    public var id: String { channelId }
    
    public init(channelId: String, channelName: String, imageURL: String?, isFavorite: Bool, lastWatched: Date?) {
        self.channelId = channelId
        self.channelName = channelName
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.lastWatched = lastWatched
    }
}
