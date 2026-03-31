// MARK: - CViewPersistence/Models/WatchHistory.swift
// 시청 기록 영속 모델 — SwiftData

import Foundation
import SwiftData

/// 시청 기록 영속 모델
@Model
public final class WatchHistory {
    public var channelId: String
    public var channelName: String
    public var thumbnailURL: String?
    public var categoryName: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval

    public init(
        channelId: String,
        channelName: String,
        thumbnailURL: String? = nil,
        categoryName: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        duration: TimeInterval = 0
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.categoryName = categoryName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
    }
}

/// 시청 기록 Sendable DTO (cross-actor)
public struct WatchHistoryData: Sendable, Identifiable {
    public let channelId: String
    public let channelName: String
    public let thumbnailURL: String?
    public let categoryName: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let duration: TimeInterval

    public var id: String { "\(channelId)-\(startedAt.timeIntervalSince1970)" }

    public var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }
        return "\(minutes)분"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    public var formattedDate: String {
        Self.dateFormatter.string(from: startedAt)
    }

    public init(
        channelId: String,
        channelName: String,
        thumbnailURL: String?,
        categoryName: String?,
        startedAt: Date,
        endedAt: Date?,
        duration: TimeInterval
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.categoryName = categoryName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
    }
}
