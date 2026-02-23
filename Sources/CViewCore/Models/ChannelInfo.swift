// MARK: - CViewCore/Models/ChannelInfo.swift
// 채널 정보 도메인 모델

import Foundation

/// 치지직 채널 기본 정보
public struct ChannelInfo: Sendable, Codable, Identifiable, Hashable {
    public let channelId: String
    public let channelName: String
    public let channelImageURL: URL?
    public let verifiedMark: Bool
    public let followerCount: Int
    public let channelDescription: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelId = try container.decode(String.self, forKey: .channelId)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelImageURL = try? container.decode(URL.self, forKey: .channelImageURL)
        verifiedMark = (try? container.decode(Bool.self, forKey: .verifiedMark)) ?? false
        followerCount = (try? container.decode(Int.self, forKey: .followerCount)) ?? 0
        channelDescription = try? container.decode(String.self, forKey: .channelDescription)
    }

    public var id: String { channelId }

    public init(
        channelId: String,
        channelName: String,
        channelImageURL: URL? = nil,
        verifiedMark: Bool = false,
        followerCount: Int = 0,
        channelDescription: String? = nil
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.channelImageURL = channelImageURL
        self.verifiedMark = verifiedMark
        self.followerCount = followerCount
        self.channelDescription = channelDescription
    }

    enum CodingKeys: String, CodingKey {
        case channelId
        case channelName
        case channelImageURL = "channelImageUrl"
        case verifiedMark
        case followerCount
        case channelDescription
    }
}

/// 팔로잉 채널 (라이브 상태 포함)
public struct FollowingChannel: Sendable, Codable, Identifiable, Hashable {
    public let channel: ChannelInfo
    public let streamer: StreamerInfo?
    public let liveInfo: LiveInfo?

    public var id: String { channel.channelId }
    public var isLive: Bool { liveInfo != nil }

    public init(channel: ChannelInfo, streamer: StreamerInfo? = nil, liveInfo: LiveInfo? = nil) {
        self.channel = channel
        self.streamer = streamer
        self.liveInfo = liveInfo
    }
}

/// 스트리머 요약 정보
public struct StreamerInfo: Sendable, Codable, Hashable {
    public let openLive: Bool

    public init(openLive: Bool = false) {
        self.openLive = openLive
    }
}
