// MARK: - LiveChannelItem.swift
// 라이브 채널 아이템 뷰모델 (HomeViewModel에서 추출)

import Foundation

/// 라이브 채널 정보를 표시하기 위한 View Model
public struct LiveChannelItem: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let channelName: String
    public let channelImageUrl: String?
    public let liveTitle: String
    public let viewerCount: Int
    public let categoryName: String?
    public let categoryType: String?    // "GAME" | "SPORTS" | "ETC"
    public let thumbnailUrl: String?
    public let channelId: String
    public let isLive: Bool
    public let openDate: Date?

    public init(
        id: String,
        channelName: String,
        channelImageUrl: String?,
        liveTitle: String,
        viewerCount: Int,
        categoryName: String?,
        categoryType: String? = nil,
        thumbnailUrl: String?,
        channelId: String,
        isLive: Bool = true,
        openDate: Date? = nil
    ) {
        self.id = id
        self.channelName = channelName
        self.channelImageUrl = channelImageUrl
        self.liveTitle = liveTitle
        self.viewerCount = viewerCount
        self.categoryName = categoryName
        self.categoryType = categoryType
        self.thumbnailUrl = thumbnailUrl
        self.channelId = channelId
        self.isLive = isLive
        self.openDate = openDate
    }

    /// Formatted viewer count (e.g., "1.5만")
    public var formattedViewerCount: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f만", Double(viewerCount) / 10_000.0)
        } else if viewerCount >= 1_000 {
            return String(format: "%.1f천", Double(viewerCount) / 1_000.0)
        }
        return "\(viewerCount)"
    }
}
