// MARK: - AutocompleteModels.swift
// CViewCore - 채팅 입력 자동완성 모델

import Foundation

// MARK: - Emoticon Suggestion

/// 이모티콘 자동완성 제안 항목
public struct EmoticonSuggestion: Identifiable, Sendable, Hashable {
    public let id: String
    public let emoticonId: String
    public let displayName: String
    public let imageURL: URL?
    /// 채팅에 삽입할 패턴 (예: `{:emoticonId:}`)
    public let chatPattern: String

    public init(emoticonId: String, displayName: String, imageURL: URL?, chatPattern: String) {
        self.id = emoticonId
        self.emoticonId = emoticonId
        self.displayName = displayName
        self.imageURL = imageURL
        self.chatPattern = chatPattern
    }

    public init(from item: EmoticonItem) {
        self.id = item.emoticonId
        self.emoticonId = item.emoticonId
        self.displayName = item.emoticonName ?? item.emoticonId
        self.imageURL = item.imageURL
        self.chatPattern = item.chatPattern
    }
}

// MARK: - Mention Suggestion

/// @멘션 자동완성 제안 항목
public struct MentionSuggestion: Identifiable, Sendable, Hashable {
    public let id: String
    public let userId: String
    public let nickname: String
    public let profileImageUrl: String?

    public init(userId: String, nickname: String, profileImageUrl: String? = nil) {
        self.id = userId
        self.userId = userId
        self.nickname = nickname
        self.profileImageUrl = profileImageUrl
    }
}

// MARK: - Autocomplete Trigger

/// 자동완성 트리거 종류
public enum AutocompleteTrigger: Sendable, Equatable {
    case none
    case emoticon(query: String, range: Range<String.Index>)
    case mention(query: String, range: Range<String.Index>)
}
