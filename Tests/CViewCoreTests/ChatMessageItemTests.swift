// MARK: - ChatMessageItemTests.swift
// CViewCore — ChatMessageItem 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - Factory / System Message

@Suite("ChatMessageItem — Construction")
struct ChatMessageItemConstructionTests {

    @Test("System message has correct defaults")
    func systemMessage() {
        let item = ChatMessageItem.system("연결됨")

        #expect(item.nickname == "시스템")
        #expect(item.content == "연결됨")
        #expect(item.isSystem == true)
        #expect(item.isNotice == false)
        #expect(item.userId == "system")
        #expect(item.type == .systemMessage)
        #expect(item.emojis.isEmpty)
        #expect(item.donationAmount == nil)
    }

    @Test("init(from: ChatMessage) maps fields correctly")
    func initFromChatMessage() {
        let msg = ChatMessage(
            id: "test-id",
            userId: "user-42",
            nickname: "김치지",
            content: "안녕하세요!",
            type: .normal
        )
        let item = ChatMessageItem(from: msg)

        #expect(item.id == "test-id")
        #expect(item.userId == "user-42")
        #expect(item.nickname == "김치지")
        #expect(item.content == "안녕하세요!")
        #expect(item.type == .normal)
        #expect(item.isNotice == false)
        #expect(item.isSystem == false)
    }

    @Test("init(from: ChatMessage) with nil userId defaults to 'unknown'")
    func nilUserIdDefault() {
        let msg = ChatMessage(nickname: "guest", content: "hi")
        let item = ChatMessageItem(from: msg)
        #expect(item.userId == "unknown")
    }

    @Test("isNotice flag is forwarded")
    func noticeFlagForwarded() {
        let msg = ChatMessage(nickname: "공지", content: "서버 점검", type: .notice)
        let item = ChatMessageItem(from: msg, isNotice: true)
        #expect(item.isNotice == true)
    }
}

// MARK: - Formatted Time

@Suite("ChatMessageItem — Formatted Time")
struct ChatMessageItemTimeTests {

    @Test("formattedTime returns HH:mm:ss format")
    func formattedTimeFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(hour: 14, minute: 5, second: 9))!

        let item = ChatMessageItem(
            id: "t1", userId: "u1", nickname: "test", content: "msg",
            timestamp: date, type: .normal, badgeImageURL: nil,
            emojis: [:], donationAmount: nil, donationType: nil,
            subscriptionMonths: nil, profileImageUrl: nil,
            isNotice: false, isSystem: false
        )

        #expect(item.formattedTime == "14:05:09")
    }
}

// MARK: - Equatable / Identifiable

@Suite("ChatMessageItem — Equatable & Identifiable")
struct ChatMessageItemEqualityTests {

    @Test("Same ID and content are equal")
    func equality() {
        let date = Date()
        let a = ChatMessageItem(
            id: "same", userId: "u", nickname: "n", content: "c",
            timestamp: date, type: .normal, badgeImageURL: nil,
            emojis: [:], donationAmount: nil, donationType: nil,
            subscriptionMonths: nil, profileImageUrl: nil,
            isNotice: false, isSystem: false
        )
        let b = ChatMessageItem(
            id: "same", userId: "u", nickname: "n", content: "c",
            timestamp: date, type: .normal, badgeImageURL: nil,
            emojis: [:], donationAmount: nil, donationType: nil,
            subscriptionMonths: nil, profileImageUrl: nil,
            isNotice: false, isSystem: false
        )
        #expect(a == b)
    }

    @Test("Different IDs are not equal")
    func inequality() {
        let a = ChatMessageItem.system("msg")
        let b = ChatMessageItem.system("msg")
        // Different UUIDs → not equal
        #expect(a != b)
    }
}

// MARK: - AppError Tests (추가)

@Suite("AppError — Error Descriptions")
struct AppErrorExtendedTests {

    @Test("Player error has description")
    func playerError() {
        let error = AppError.player(.engineInitFailed)
        let desc = error.localizedDescription
        #expect(desc.contains("엔진") || desc.contains("초기화"))
    }

    @Test("Chat error has description")
    func chatError() {
        let error = AppError.chat(.connectionFailed("WebSocket timeout"))
        #expect(!error.localizedDescription.isEmpty)
    }

    @Test("Persistence error has description")
    func persistenceError() {
        let error = AppError.persistence(.saveFailed("디스크 공간 부족"))
        #expect(error.localizedDescription.contains("저장"))
    }

    @Test("Recovery suggestion is non-nil")
    func recoverySuggestion() {
        let errors: [AppError] = [
            .network(.timeout),
            .auth(.notLoggedIn),
            .api(.unauthorized),
            .player(.engineInitFailed),
            .chat(.notConnected),
            .persistence(.containerNotLoaded),
            .unknown("test"),
        ]
        for error in errors {
            #expect(error.recoverySuggestion != nil)
        }
    }
}
