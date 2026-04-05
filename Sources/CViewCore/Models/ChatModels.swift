// MARK: - CViewCore/Models/ChatModels.swift
// 채팅 도메인 모델

import Foundation

/// 채팅 메시지
public struct ChatMessage: Sendable, Identifiable, Hashable {
    public let id: String
    public let userId: String?
    public let nickname: String
    public let content: String
    public let timestamp: Date
    public let type: MessageType
    public let profile: ChatProfile?
    public let extras: ChatExtras?

    public init(
        id: String = UUID().uuidString,
        userId: String? = nil,
        nickname: String,
        content: String,
        timestamp: Date = .now,
        type: MessageType = .normal,
        profile: ChatProfile? = nil,
        extras: ChatExtras? = nil
    ) {
        self.id = id
        self.userId = userId
        self.nickname = nickname
        self.content = content
        self.timestamp = timestamp
        self.type = type
        self.profile = profile
        self.extras = extras
    }
}

/// 메시지 유형
public enum MessageType: String, Sendable, Codable, Hashable {
    case normal
    case donation
    case subscription
    case systemMessage
    case notice
}

/// 사용자 역할 (치지직 채팅)
public enum UserRole: String, Sendable, Codable, Hashable {
    case streamer = "streamer"
    case manager = "streaming_chat_manager"
    case channelManager = "streaming_channel_manager"
    case viewer = ""

    public init(from code: String?) {
        switch code {
        case "streamer": self = .streamer
        case let c? where c.contains("manager"): self = .manager
        default: self = .viewer
        }
    }

    /// SF Symbol 아이콘
    public var iconName: String? {
        switch self {
        case .streamer: return "mic.circle.fill"
        case .manager, .channelManager: return "wrench.and.screwdriver.fill"
        case .viewer: return nil
        }
    }

    /// 역할 표시 텍스트
    public var displayLabel: String? {
        switch self {
        case .streamer: return "스트리머"
        case .manager, .channelManager: return "매니저"
        case .viewer: return nil
        }
    }

    /// 특수 역할인지 여부
    public var isSpecial: Bool {
        self != .viewer
    }
}

/// 채팅 프로필
public struct ChatProfile: Sendable, Codable, Hashable {
    public let nickname: String
    public let profileImageURL: URL?
    public let userRoleCode: String?
    public let userRole: UserRole
    public let badge: ChatBadge?
    public let badges: [ChatBadge]
    public let title: ChatTitle?
    public let activityBadges: [ChatBadge]

    public init(
        nickname: String,
        profileImageURL: URL? = nil,
        userRoleCode: String? = nil,
        badge: ChatBadge? = nil,
        badges: [ChatBadge] = [],
        title: ChatTitle? = nil,
        activityBadges: [ChatBadge] = []
    ) {
        self.nickname = nickname
        self.profileImageURL = profileImageURL
        self.userRoleCode = userRoleCode
        self.userRole = UserRole(from: userRoleCode)
        self.badge = badge
        self.badges = badges
        self.title = title
        self.activityBadges = activityBadges
    }
}

/// 채팅 뱃지
public struct ChatBadge: Sendable, Codable, Hashable {
    public let imageURL: URL?
    public let badgeId: String?
    public let altText: String?

    public init(imageURL: URL? = nil, badgeId: String? = nil, altText: String? = nil) {
        self.imageURL = imageURL
        self.badgeId = badgeId
        self.altText = altText
    }
}

/// 채팅 칭호
public struct ChatTitle: Sendable, Codable, Hashable {
    public let name: String
    public let color: String?

    public init(name: String, color: String? = nil) {
        self.name = name
        self.color = color
    }
}

/// 후원 정보
public struct DonationInfo: Sendable, Codable, Hashable {
    public let amount: Int
    public let currency: String
    public let type: String

    public init(amount: Int, currency: String = "KRW", type: String = "CHAT") {
        self.amount = amount
        self.currency = currency
        self.type = type
    }
}

/// 구독 정보
public struct SubscriptionInfo: Sendable, Codable, Hashable {
    public let months: Int
    public let tierName: String?

    public init(months: Int, tierName: String? = nil) {
        self.months = months
        self.tierName = tierName
    }
}

/// 채팅 부가 정보
public struct ChatExtras: Sendable, Codable, Hashable {
    public let emojis: [String: String]?
    public let osType: String?
    public let streamingChannelId: String?
    public let donation: DonationInfo?
    public let subscription: SubscriptionInfo?

    public init(
        emojis: [String: String]? = nil,
        osType: String? = nil,
        streamingChannelId: String? = nil,
        donation: DonationInfo? = nil,
        subscription: SubscriptionInfo? = nil
    ) {
        self.emojis = emojis
        self.osType = osType
        self.streamingChannelId = streamingChannelId
        self.donation = donation
        self.subscription = subscription
    }
}

/// 치지직 채팅 프로토콜 명령 코드
public enum ChatCommandCode: Int, Sendable {
    case ping = 0
    case pong = 10000
    case connect = 100
    case connected = 10100
    case requestRecentChat = 5101
    case recentChat = 15101
    case sendChat = 3101
    case chatMessage = 93101
    case donation = 93102
    case kick = 94005
    case blind = 94008
    case notice = 94010
    case penalty = 94015
}

/// 채팅 접속 토큰
public struct ChatAccessToken: Sendable, Codable {
    public let accessToken: String
    public let extraToken: String?
    public let realNameAuth: Bool?
    public let temporaryRestrict: TemporaryRestrict?

    public init(
        accessToken: String,
        extraToken: String? = nil,
        realNameAuth: Bool? = nil,
        temporaryRestrict: TemporaryRestrict? = nil
    ) {
        self.accessToken = accessToken
        self.extraToken = extraToken
        self.realNameAuth = realNameAuth
        self.temporaryRestrict = temporaryRestrict
    }
}

/// 임시 제한 정보
public struct TemporaryRestrict: Sendable, Codable {
    public let temporaryRestrict: Bool?
    public let times: Int?
    public let duration: Int?

    public init(temporaryRestrict: Bool? = false, times: Int? = 0, duration: Int? = 0) {
        self.temporaryRestrict = temporaryRestrict
        self.times = times
        self.duration = duration
    }
}

/// 채팅 연결 상태
public enum ChatConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(serverIndex: Int)
    case reconnecting(attempt: Int)
    case failed(reason: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .disconnected: "연결 안됨"
        case .connecting: "연결 중..."
        case .connected(let idx): "연결됨 (서버 \(idx))"
        case .reconnecting(let attempt): "재연결 중 (\(attempt)회)"
        case .failed(let reason): "연결 실패: \(reason)"
        }
    }
}
