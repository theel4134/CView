// MARK: - ChatViewModel+Autocomplete.swift
// CViewApp - ChatViewModel 자동완성 (이모티콘 / 멘션)

import Foundation
import CViewCore

// MARK: - Autocomplete

extension ChatViewModel {

    /// 수신된 메시지에서 최근 채팅 참여자 목록 업데이트
    public func trackRecentChatters(from items: [ChatMessageItem]) {
        for item in items {
            guard !item.isSystem, item.userId != "system", item.userId != (currentUserUid ?? "") else { continue }
            // 이미 존재하면 제거 후 앞에 추가 (최신순 유지)
            recentChatters.removeAll { $0.userId == item.userId }
            recentChatters.insert(
                MentionSuggestion(
                    userId: item.userId,
                    nickname: item.nickname,
                    profileImageUrl: item.profileImageUrl
                ),
                at: 0
            )
        }
        // 최대 수 초과 시 truncate
        if recentChatters.count > Self.maxRecentChattersCount {
            recentChatters = Array(recentChatters.prefix(Self.maxRecentChattersCount))
        }
    }

    /// 입력 텍스트에서 자동완성 트리거를 감지하고 제안 목록 업데이트
    public func updateAutocompleteSuggestions(for text: String, cursorOffset: Int? = nil) {
        let effectiveCursor = cursorOffset ?? text.count
        let trigger = detectAutocompleteTrigger(in: text, cursorOffset: effectiveCursor)
        autocompleteTrigger = trigger

        switch trigger {
        case .none:
            emoticonSuggestions = []
            mentionSuggestions = []
            autocompleteSelectedIndex = 0

        case .emoticon(let query, _):
            let q = query.lowercased()
            let allEmoticons = gatherAllEmoticons()
            let filtered = allEmoticons.filter {
                $0.displayName.lowercased().contains(q) || $0.emoticonId.lowercased().contains(q)
            }
            emoticonSuggestions = Array(filtered.prefix(8))
            mentionSuggestions = []
            autocompleteSelectedIndex = 0

        case .mention(let query, _):
            let q = query.lowercased()
            if q.isEmpty {
                mentionSuggestions = Array(recentChatters.prefix(8))
            } else {
                let filtered = recentChatters.filter {
                    $0.nickname.lowercased().contains(q)
                }
                mentionSuggestions = Array(filtered.prefix(8))
            }
            emoticonSuggestions = []
            autocompleteSelectedIndex = 0
        }
    }

    /// 자동완성 항목 선택 시 텍스트에 반영 — 대체된 텍스트 반환
    public func applyAutocompletion(to text: String, selectedIndex: Int) -> String? {
        switch autocompleteTrigger {
        case .emoticon(_, let range):
            guard selectedIndex < emoticonSuggestions.count else { return nil }
            let suggestion = emoticonSuggestions[selectedIndex]
            var result = text
            result.replaceSubrange(range, with: suggestion.chatPattern)
            dismissAutocomplete()
            return result

        case .mention(_, let range):
            guard selectedIndex < mentionSuggestions.count else { return nil }
            let suggestion = mentionSuggestions[selectedIndex]
            var result = text
            result.replaceSubrange(range, with: "@\(suggestion.nickname) ")
            dismissAutocomplete()
            return result

        case .none:
            return nil
        }
    }

    /// 자동완성 팝업 닫기
    public func dismissAutocomplete() {
        emoticonSuggestions = []
        mentionSuggestions = []
        autocompleteSelectedIndex = 0
        autocompleteTrigger = .none
    }

    /// 방향키로 선택 인덱스 이동
    public func moveAutocompleteSelection(delta: Int) {
        let count = isEmoticonAutocomplete ? emoticonSuggestions.count : mentionSuggestions.count
        guard count > 0 else { return }
        autocompleteSelectedIndex = (autocompleteSelectedIndex + delta + count) % count
    }

    /// 현재 이모티콘 자동완성 모드인지
    public var isEmoticonAutocomplete: Bool {
        !emoticonSuggestions.isEmpty
    }

    // MARK: - Private Autocomplete Helpers

    /// 텍스트에서 커서 위치 기준 자동완성 트리거 감지
    func detectAutocompleteTrigger(in text: String, cursorOffset: Int) -> AutocompleteTrigger {
        guard !text.isEmpty, cursorOffset > 0 else { return .none }

        let safeOffset = min(cursorOffset, text.count)
        let cursorIndex = text.index(text.startIndex, offsetBy: safeOffset)
        let beforeCursor = text[text.startIndex..<cursorIndex]

        // `:` 이모티콘 트리거 — `:keyword` 형태 감지
        if let colonRange = beforeCursor.range(of: ":[a-zA-Z0-9_가-힣]{1,20}$", options: .regularExpression) {
            let queryStart = text.index(after: colonRange.lowerBound)
            let query = String(text[queryStart..<colonRange.upperBound])
            let fullRange = colonRange.lowerBound..<colonRange.upperBound
            return .emoticon(query: query, range: fullRange)
        }

        // `@` 멘션 트리거 — `@name` 형태 감지
        if let atRange = beforeCursor.range(of: "@[a-zA-Z0-9_가-힣]{0,20}$", options: .regularExpression) {
            let queryStart = text.index(after: atRange.lowerBound)
            let query = String(text[queryStart..<atRange.upperBound])
            let fullRange = atRange.lowerBound..<atRange.upperBound
            return .mention(query: query, range: fullRange)
        }

        return .none
    }

    /// 모든 이모티콘 소스에서 제안 목록 구축
    func gatherAllEmoticons() -> [EmoticonSuggestion] {
        var suggestions: [EmoticonSuggestion] = []
        var seen = Set<String>()

        // emoticonPacks (API 로드)
        for pack in emoticonPacks {
            for item in pack.emoticons ?? [] where !seen.contains(item.emoticonId) {
                seen.insert(item.emoticonId)
                suggestions.append(EmoticonSuggestion(from: item))
            }
        }

        // channelEmoticons (fallback)
        for (id, urlStr) in channelEmoticons where !seen.contains(id) {
            seen.insert(id)
            suggestions.append(EmoticonSuggestion(
                emoticonId: id,
                displayName: id,
                imageURL: URL(string: urlStr),
                chatPattern: "{:\(id):}"
            ))
        }

        // collectedEmoticons (채팅 수집분)
        for (id, url) in collectedEmoticons where !seen.contains(id) {
            seen.insert(id)
            suggestions.append(EmoticonSuggestion(
                emoticonId: id,
                displayName: id,
                imageURL: url,
                chatPattern: "{:\(id):}"
            ))
        }

        return suggestions
    }
}
