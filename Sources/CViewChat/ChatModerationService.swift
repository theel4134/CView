// MARK: - ChatModerationService.swift
// CViewChat - Chat moderation and command handling
// 원본: ChzzkChatService 내 모더레이션 로직 분리

import Foundation
import CViewCore

// MARK: - Chat Command

/// Supported chat commands (slash commands)
public enum ChatCommand: String, Sendable, CaseIterable {
    case mute = "/mute"
    case unmute = "/unmute"
    case ban = "/ban"
    case unban = "/unban"
    case slow = "/slow"
    case clear = "/clear"
    case notice = "/notice"
    case host = "/host"
    case filter = "/filter"
    case export_ = "/export"
    case block = "/block"
    case unblock = "/unblock"
    case help = "/help"
    
    /// Parse command from user input
    public static func parse(_ input: String) -> (command: ChatCommand, args: [String])? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        
        let components = trimmed.split(separator: " ", maxSplits: 1)
        guard let first = components.first,
              let cmd = ChatCommand(rawValue: String(first)) else {
            return nil
        }
        
        let args = components.count > 1
            ? String(components[1]).split(separator: " ").map(String.init)
            : []
        
        return (cmd, args)
    }
    
    public var requiresManager: Bool {
        switch self {
        case .mute, .unmute, .ban, .unban, .slow, .clear, .notice, .host:
            return true
        case .filter, .export_, .block, .unblock, .help:
            return false
        }
    }
    
    public var description: String {
        switch self {
        case .mute: "사용자 채팅 금지"
        case .unmute: "사용자 채팅 금지 해제"
        case .ban: "사용자 차단"
        case .unban: "사용자 차단 해제"
        case .slow: "슬로우 모드 설정"
        case .clear: "채팅 내역 삭제"
        case .notice: "공지 등록"
        case .host: "호스트 설정"
        case .filter: "키워드 필터 추가"
        case .export_: "채팅 로그 내보내기"
        case .block: "사용자 차단 (로컬)"
        case .unblock: "사용자 차단 해제 (로컬)"
        case .help: "명령어 도움말"
        }
    }
}

// MARK: - Chat Filter

/// Content filter for chat messages
public struct ChatFilter: Sendable {
    
    public enum FilterType: Sendable {
        case keyword([String])
        case regex(String)
        case user([String])
        case donationOnly
    }
    
    public let type: FilterType
    public let isEnabled: Bool
    /// 컴파일된 regex 캐시 — 매 메시지마다 재컴파일 방지
    private let compiledRegex: NSRegularExpression?
    
    public init(type: FilterType, isEnabled: Bool = true) {
        self.type = type
        self.isEnabled = isEnabled
        // regex 타입일 때 init에서 1회만 컴파일
        if case .regex(let pattern) = type {
            do {
                self.compiledRegex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            } catch {
                Log.chat.warning("Chat filter regex compile failed: '\(pattern)' — \(error.localizedDescription)")
                self.compiledRegex = nil
            }
        } else {
            self.compiledRegex = nil
        }
    }
    
    /// Check if a message should be filtered (hidden)
    public func shouldFilter(_ message: ChatMessage) -> Bool {
        guard isEnabled else { return false }
        
        switch type {
        case .keyword(let keywords):
            return keywords.contains { keyword in
                message.content.localizedCaseInsensitiveContains(keyword)
            }
            
        case .regex:
            guard let regex = compiledRegex else {
                return false
            }
            let range = NSRange(message.content.startIndex..., in: message.content)
            return regex.firstMatch(in: message.content, range: range) != nil
            
        case .user(let userIds):
            return userIds.contains(message.userId ?? "")
            
        case .donationOnly:
            return message.type != .donation
        }
    }
}

// MARK: - Chat Moderation Service

/// Handles chat moderation, filtering, and command processing.
public actor ChatModerationService {
    
    // MARK: - Properties
    
    private var filters: [ChatFilter] = []
    private var blockedUsers: Set<String> = []
    private var mutedUsers: [String: Date] = [:] // userId -> mute expiry
    private let logger = AppLogger.chat
    
    public init() {}
    
    /// 저장된 차단 목록으로 초기화
    public init(blockedUsers: [String]) {
        self.blockedUsers = Set(blockedUsers)
    }
    
    // MARK: - Filter Management
    
    public func addFilter(_ filter: ChatFilter) {
        filters.append(filter)
    }
    
    public func removeAllFilters() {
        filters.removeAll()
    }
    
    public func currentFilters() -> [ChatFilter] {
        filters
    }
    
    // MARK: - User Management
    
    public func blockUser(_ userId: String) {
        blockedUsers.insert(userId)
        logger.info("Blocked user: \(userId)")
    }
    
    public func unblockUser(_ userId: String) {
        blockedUsers.remove(userId)
        logger.info("Unblocked user: \(userId)")
    }
    
    public func muteUser(_ userId: String, duration: TimeInterval) {
        mutedUsers[userId] = Date().addingTimeInterval(duration)
        logger.info("Muted user: \(userId) for \(duration)s")
    }
    
    public func unmuteUser(_ userId: String) {
        mutedUsers.removeValue(forKey: userId)
    }
    
    public func isBlocked(_ userId: String) -> Bool {
        blockedUsers.contains(userId)
    }

    public func getBlockedUsers() -> Set<String> {
        blockedUsers
    }
    
    public func isMuted(_ userId: String) -> Bool {
        guard let expiry = mutedUsers[userId] else { return false }
        return Date() <= expiry
    }
    
    /// 만료된 뮤트 항목 정리
    public func cleanExpiredMutes() {
        let now = Date()
        mutedUsers = mutedUsers.filter { $0.value > now }
    }
    
    // MARK: - Message Processing
    
    /// Process messages through all filters and blocks
    /// · 후원(`.donation`)·구독(`.subscription`)·공지(`.notice`)·시스템(`.systemMessage`)은
    ///   처릤 웹 동작과 동일하게 사용자 키워드/정규식 필터를 우회한다. 대형 도네이션이
    ///   컨텐츠 키워드에 걸려 채팅창에서 누락되는 현상을 방지.
    /// · 차단 사용자·뮤트는 그대로 적용 (위반 행위는 후원이라도 차단 유지).
    public func filterMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            // Check blocked users
            guard !isBlocked(message.userId ?? "") else { return false }
            
            // Check muted users
            guard !isMuted(message.userId ?? "") else { return false }

            // 후원·구독·공지·시스템 메시지는 콘텐츠 필터 예외 — 항상 전달
            switch message.type {
            case .donation, .subscription, .notice, .systemMessage:
                return true
            default:
                break
            }

            // Check content filters
            for filter in filters {
                if filter.shouldFilter(message) { return false }
            }
            
            return true
        }
    }
    
    /// Process a single message
    public func shouldShow(_ message: ChatMessage) -> Bool {
        guard !isBlocked(message.userId ?? "") else { return false }
        guard !isMuted(message.userId ?? "") else { return false }
        
        for filter in filters {
            if filter.shouldFilter(message) { return false }
        }
        
        return true
    }
    
    // MARK: - Command Processing
    
    /// Process a chat command, returns the command to send or nil if handled locally
    public func processCommand(_ input: String) -> ChatCommandResult? {
        guard let (command, args) = ChatCommand.parse(input) else {
            return nil
        }
        
        switch command {
        case .mute:
            guard let userId = args.first else {
                return .error("사용법: /mute <사용자ID> [시간(초)]")
            }
            let duration = args.count > 1 ? TimeInterval(args[1]) ?? ChatDefaults.defaultMuteDurationSecs : ChatDefaults.defaultMuteDurationSecs
            muteUser(userId, duration: duration)
            return .localAction("'\(userId)' 님이 \(Int(duration))초간 채팅 금지 되었습니다.")
            
        case .unmute:
            guard let userId = args.first else {
                return .error("사용법: /unmute <사용자ID>")
            }
            unmuteUser(userId)
            return .localAction("'\(userId)' 님의 채팅 금지가 해제되었습니다.")
            
        case .ban:
            guard let userId = args.first else {
                return .error("사용법: /ban <사용자ID>")
            }
            blockUser(userId)
            return .localAction("'\(userId)' 님이 차단되었습니다.")
            
        case .unban:
            guard let userId = args.first else {
                return .error("사용법: /unban <사용자ID>")
            }
            unblockUser(userId)
            return .localAction("'\(userId)' 님의 차단이 해제되었습니다.")
            
        case .clear:
            return .clearChat
            
        case .notice:
            let message = args.joined(separator: " ")
            guard !message.isEmpty else {
                return .error("사용법: /notice <메시지>")
            }
            return .serverCommand(command: command, args: args)
            
        case .slow:
            return .serverCommand(command: command, args: args)
            
        case .host:
            return .serverCommand(command: command, args: args)
            
        case .filter:
            guard !args.isEmpty else {
                return .error("사용법: /filter <키워드> [키워드2 ...]")
            }
            let filter = ChatFilter(type: .keyword(args))
            addFilter(filter)
            return .localAction("키워드 필터 추가: \(args.joined(separator: ", "))")
            
        case .export_:
            return .exportChat
            
        case .block:
            guard let userId = args.first else {
                return .error("사용법: /block <사용자ID>")
            }
            blockUser(userId)
            return .localAction("'\(userId)' 님이 로컬 차단되었습니다.")
            
        case .unblock:
            guard let userId = args.first else {
                return .error("사용법: /unblock <사용자ID>")
            }
            unblockUser(userId)
            return .localAction("'\(userId)' 님의 로컬 차단이 해제되었습니다.")
            
        case .help:
            let helpText = ChatCommand.allCases.map { cmd in
                "\(cmd.rawValue) — \(cmd.description)"
            }.joined(separator: "\n")
            return .localAction("사용 가능한 명령어:\n\(helpText)")
        }
    }
}

// MARK: - Command Result

public enum ChatCommandResult: Sendable {
    case localAction(String)
    case serverCommand(command: ChatCommand, args: [String])
    case clearChat
    case exportChat
    case error(String)
}
