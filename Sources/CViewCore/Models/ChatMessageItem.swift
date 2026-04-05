// MARK: - ChatMessageItem.swift
// 채팅 메시지 아이템 뷰모델 (ChatViewModel에서 추출)

import Foundation

/// 채팅 메시지를 View에 표시하기 위한 ViewModel
/// `Equatable` conformance enables SwiftUI to skip re-rendering unchanged rows in ForEach.
public struct ChatMessageItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let userId: String
    public let nickname: String
    public let content: String
    public let timestamp: Date
    public let type: MessageType
    public let badgeImageURL: URL?
    public let emojis: [String: String]
    public let donationAmount: Int?
    public let donationType: String?
    public let subscriptionMonths: Int?
    public let profileImageUrl: String?
    public let isNotice: Bool
    public let isSystem: Bool
    public let userRole: UserRole
    public let badges: [ChatBadge]
    public let titleName: String?
    public let titleColor: String?

    public init(from message: ChatMessage, isNotice: Bool = false) {
        self.id = message.id
        self.userId = message.userId ?? "unknown"
        self.nickname = message.nickname
        self.content = message.content
        self.timestamp = message.timestamp
        self.type = message.type
        self.badgeImageURL = message.profile?.badge?.imageURL
        self.emojis = message.extras?.emojis ?? [:]
        self.donationAmount = message.extras?.donation?.amount
        self.donationType = message.extras?.donation?.type
        self.subscriptionMonths = message.extras?.subscription?.months
        self.profileImageUrl = message.profile?.profileImageURL?.absoluteString
        self.isNotice = isNotice
        self.isSystem = false
        self.userRole = message.profile?.userRole ?? .viewer
        self.badges = (message.profile?.badges ?? []) + (message.profile?.activityBadges ?? [])
        self.titleName = message.profile?.title?.name
        self.titleColor = message.profile?.title?.color
    }

    public static func system(_ message: String) -> ChatMessageItem {
        ChatMessageItem(
            id: UUID().uuidString,
            userId: "system",
            nickname: "시스템",
            content: message,
            timestamp: Date(),
            type: .systemMessage,
            badgeImageURL: nil,
            emojis: [:],
            donationAmount: nil,
            donationType: nil,
            subscriptionMonths: nil,
            profileImageUrl: nil,
            isNotice: false,
            isSystem: true,
            userRole: .viewer,
            badges: [],
            titleName: nil,
            titleColor: nil
        )
    }

    public init(
        id: String, userId: String, nickname: String, content: String,
        timestamp: Date, type: MessageType, badgeImageURL: URL?,
        emojis: [String: String], donationAmount: Int?, donationType: String?,
        subscriptionMonths: Int?,
        profileImageUrl: String?,
        isNotice: Bool, isSystem: Bool,
        userRole: UserRole = .viewer,
        badges: [ChatBadge] = [],
        titleName: String? = nil,
        titleColor: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.nickname = nickname
        self.content = content
        self.timestamp = timestamp
        self.type = type
        self.badgeImageURL = badgeImageURL
        self.emojis = emojis
        self.donationAmount = donationAmount
        self.donationType = donationType
        self.subscriptionMonths = subscriptionMonths
        self.profileImageUrl = profileImageUrl
        self.isNotice = isNotice
        self.isSystem = isSystem
        self.userRole = userRole
        self.badges = badges
        self.titleName = titleName
        self.titleColor = titleColor
    }

    /// 시간 포맷터: 새 인스턴스 생성 대신 정적 재사용
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Formatted timestamp (HH:mm:ss)
    public var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }
}
