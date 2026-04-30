// MARK: - StreamAlertItem.swift
// 플레이어 오버레이에 표시할 알림 아이템 모델

import Foundation

/// 플레이어 화면 위에 떠오르는 알림(후원, 구독, 시스템 등)
public struct StreamAlertItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let alertType: StreamAlertType
    public let nickname: String
    public let content: String
    public let timestamp: Date

    // 후원 전용
    public let donationAmount: Int?
    public let donationType: String?   // "CHAT" / "VIDEO" / "MISSION"

    // 구독 전용
    public let subscriptionMonths: Int?

    public init(
        id: String = UUID().uuidString,
        alertType: StreamAlertType,
        nickname: String,
        content: String = "",
        timestamp: Date = .now,
        donationAmount: Int? = nil,
        donationType: String? = nil,
        subscriptionMonths: Int? = nil
    ) {
        self.id = id
        self.alertType = alertType
        self.nickname = nickname
        self.content = content
        self.timestamp = timestamp
        self.donationAmount = donationAmount
        self.donationType = donationType
        self.subscriptionMonths = subscriptionMonths
    }
}

/// 스트림 알림 유형
public enum StreamAlertType: String, Sendable, Codable, Hashable {
    case donation       // 일반 채팅 후원
    case videoDonation  // 영상 후원
    case missionDonation // 미션 후원
    case subscription   // 구독
    case notice         // 공지
    case systemMessage  // 시스템 메시지
}

// MARK: - ChatMessageItem → StreamAlertItem 변환

extension StreamAlertItem {
    /// ChatMessageItem으로부터 알림 아이템 생성 (알림 대상이 아니면 nil)
    public init?(from item: ChatMessageItem) {
        switch item.type {
        case .donation:
            let dtype = item.donationType ?? "CHAT"
            switch dtype {
            case "VIDEO":   self.init(alertType: .videoDonation, nickname: item.nickname, content: item.content, donationAmount: item.donationAmount, donationType: dtype)
            case "MISSION": self.init(alertType: .missionDonation, nickname: item.nickname, content: item.content, donationAmount: item.donationAmount, donationType: dtype)
            default:        self.init(alertType: .donation, nickname: item.nickname, content: item.content, donationAmount: item.donationAmount, donationType: dtype)
            }
        case .subscription:
            self.init(alertType: .subscription, nickname: item.nickname, content: item.content, subscriptionMonths: item.subscriptionMonths)
        case .notice:
            return nil  // 공지는 별도 isNotice 플래그로 처리
        case .systemMessage:
            return nil  // 시스템 메시지는 채팅에서만 표시
        case .normal:
            return nil
        }
    }

    /// ChatMessageItem이 공지인 경우 알림 생성
    public static func notice(from item: ChatMessageItem) -> StreamAlertItem? {
        guard item.isNotice else { return nil }
        return StreamAlertItem(alertType: .notice, nickname: item.nickname, content: item.content)
    }
}
