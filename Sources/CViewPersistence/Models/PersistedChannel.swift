// MARK: - CViewPersistence/Models/PersistedChannel.swift
// SwiftData 영속 모델

import Foundation
import SwiftData
import CViewCore

/// 채널 영속 모델 (SwiftData)
@Model
public final class PersistedChannel {
    @Attribute(.unique) public var channelId: String
    public var channelName: String
    public var imageURL: String?
    public var isFavorite: Bool
    public var lastWatched: Date?
    public var addedAt: Date
    public var memo: String?

    @Relationship(deleteRule: .cascade, inverse: \PersistedStatistic.channel)
    public var statistics: [PersistedStatistic]?

    public init(
        channelId: String,
        channelName: String,
        imageURL: String? = nil,
        isFavorite: Bool = false,
        lastWatched: Date? = nil
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.lastWatched = lastWatched
        self.addedAt = .now
    }

    /// 도메인 모델로 변환
    public func toDomain() -> ChannelInfo {
        ChannelInfo(
            channelId: channelId,
            channelName: channelName,
            channelImageURL: imageURL.flatMap(URL.init(string:))
        )
    }
}

/// 시청 통계 영속 모델
@Model
public final class PersistedStatistic {
    public var channelId: String
    public var timestamp: Date
    public var viewerCount: Int
    public var watchDuration: TimeInterval
    public var averageLatency: Double?

    public var channel: PersistedChannel?

    public init(
        channelId: String,
        timestamp: Date = .now,
        viewerCount: Int = 0,
        watchDuration: TimeInterval = 0,
        averageLatency: Double? = nil
    ) {
        self.channelId = channelId
        self.timestamp = timestamp
        self.viewerCount = viewerCount
        self.watchDuration = watchDuration
        self.averageLatency = averageLatency
    }
}

/// 설정 영속 모델
@Model
public final class PersistedSetting {
    @Attribute(.unique) public var key: String
    public var valueData: Data
    public var updatedAt: Date

    public init(key: String, valueData: Data) {
        self.key = key
        self.valueData = valueData
        self.updatedAt = .now
    }
}
