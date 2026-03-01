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
            isSystem: true
        )
    }

    public init(
        id: String, userId: String, nickname: String, content: String,
        timestamp: Date, type: MessageType, badgeImageURL: URL?,
        emojis: [String: String], donationAmount: Int?, donationType: String?,
        subscriptionMonths: Int?,
        profileImageUrl: String?,
        isNotice: Bool, isSystem: Bool
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
    }

    /// 시간 포맷터: 새 인스턴스 생성 대신 정적 재사용 (read-only이므로 nonisolated(unsafe) 안전)
    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Formatted timestamp (HH:mm)
    public var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }
}
