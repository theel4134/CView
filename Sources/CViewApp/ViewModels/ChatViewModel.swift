// MARK: - ChatViewModel.swift
// CViewApp - Chat ViewModel
// 원본: ChzzkChatService 직접 참조 → 개선: ChatEngine 추상화 + @Observable

import Foundation
import SwiftUI
import CViewCore
import CViewChat

// MARK: - Chat ViewModel

@Observable
@MainActor
public final class ChatViewModel {
    
    // MARK: - State
    
    public var messages: [ChatMessageItem] = []
    public var connectionState: ChatConnectionState = .disconnected
    public var inputText = ""
    public var isAutoScrollEnabled = true
    public var showDonationsOnly = false
    public var fontSize: CGFloat = 13
    public var opacity: Double = 1.0

    // Display options
    public var showTimestamp: Bool = true
    public var showBadge: Bool = true
    public var lineSpacing: CGFloat = 2.0
    public var highlightMentions: Bool = true
    public var emoticonEnabled: Bool = true
    public var showDonation: Bool = true

    // Filter / capacity
    public var maxVisibleMessages: Int = 500
    public var blockedWords: [String] = []
    
    // Stats
    public var messageCount: Int = 0
    public var messagesPerSecond: Double = 0
    
    // Emoticon/highlight
    public var highlightedUsers: Set<String> = []
    public var pinnedMessage: ChatMessageItem?
    public var isFilterEnabled: Bool = true
    
    /// 채널 이모티콘 맵 (emoticonId → imageURL)
    public var channelEmoticons: [String: String] = [:] {
        didSet {
            guard !channelEmoticons.isEmpty, !messages.isEmpty else { return }
            // 채널 이모티콘 로드 완료 후 기존 메시지에 소급 적용
            messages = messages.map { enrichWithChannelEmoticons($0) }
        }
    }
    
    /// 채널 이모티콘 팩 목록
    public var emoticonPacks: [EmoticonPack] = []
    
    /// 채팅 메시지에서 수집된 이모티콘 (ID → URL)
    private var collectedEmoticons: [String: URL] = [:]
    
    /// 이모티콘 피커에 표시할 팩 목록
    /// - API로 로드된 팩이 있으면 그것을 사용
    /// - 없으면 channelEmoticons + 채팅 수집분을 합쳐 가상 팩 생성
    public var emoticonPickerPacks: [EmoticonPack] {
        if !emoticonPacks.isEmpty { return emoticonPacks }
        // channelEmoticons + collectedEmoticons 합산
        var merged: [String: URL] = collectedEmoticons
        for (id, urlStr) in channelEmoticons where merged[id] == nil {
            if let url = URL(string: urlStr) { merged[id] = url }
        }
        guard !merged.isEmpty else { return [] }
        let items = merged
            .map { EmoticonItem(emoticonId: $0.key, imageURL: $0.value) }
            .sorted { $0.emoticonId < $1.emoticonId }
        return [EmoticonPack(
            emoticonPackId: "_stream",
            emoticonPackName: "스트림 이모티콘",
            emoticons: items
        )]
    }
    
    // Error
    public var errorMessage: String?

    /// 채팅 전송 가능 여부: 연결됨 + 로그인 상태(uid 보유)
    public var canSendChat: Bool {
        connectionState.isConnected && currentUserUid != nil
    }

    // MARK: - Dependencies
    
    private var chatEngine: ChatEngine?
    private var moderationService: ChatModerationService?
    private let logger = AppLogger.chat
    
    /// 차단 목록 변경 시 외부 저장용 콜백
    public var onBlockedUsersChanged: (([String]) -> Void)?
    
    /// 초기 차단 목록 (connect 전에 설정)
    public var initialBlockedUsers: [String] = []
    
    /// 현재 로그인 사용자 정보 (보낸 메시지 로컬 표시용)
    public var currentUserUid: String?
    public var currentUserNickname: String?
    
    // Tasks
    private var eventListenTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var recentMessageTimestamps: [Date] = []
    
    // MARK: - Initialization
    
    public init() {}

    /// SettingsStore.chat 에서 뷰모델 상태를 일괄 동기화
    public func applySettings(_ settings: CViewCore.ChatSettings) {
        fontSize = settings.fontSize
        opacity = settings.chatOpacity
        lineSpacing = settings.lineSpacing
        showTimestamp = settings.showTimestamp
        showBadge = settings.showBadge
        highlightMentions = settings.highlightMentions
        maxVisibleMessages = settings.maxVisibleMessages
        emoticonEnabled = settings.emoticonEnabled
        showDonation = settings.showDonation
        showDonationsOnly = settings.showDonationsOnly
        isAutoScrollEnabled = settings.autoScroll
        isFilterEnabled = settings.chatFilterEnabled
        blockedWords = settings.blockedWords
        initialBlockedUsers = settings.blockedUsers
    }

    /// 현재 뷰모델 상태를 ChatSettings 스냅샷으로 내보내기 (팝업에서 저장 시 사용)
    public func exportSettings(base: CViewCore.ChatSettings) -> CViewCore.ChatSettings {
        var s = base
        s.fontSize = fontSize
        s.chatOpacity = opacity
        s.lineSpacing = lineSpacing
        s.showTimestamp = showTimestamp
        s.showBadge = showBadge
        s.highlightMentions = highlightMentions
        s.maxVisibleMessages = maxVisibleMessages
        s.emoticonEnabled = emoticonEnabled
        s.showDonation = showDonation
        s.showDonationsOnly = showDonationsOnly
        s.autoScroll = isAutoScrollEnabled
        s.chatFilterEnabled = isFilterEnabled
        s.blockedWords = blockedWords
        // blockedUsers는 모더레이션 서비스 통해 관리 (별도 콜백)
        return s
    }
    
    // MARK: - Connection
    
    /// Connect to chat for a specific channel
    public func connect(
        chatChannelId: String,
        accessToken: String,
        extraToken: String? = nil,
        uid: String? = nil,
        channelId: String? = nil
    ) async {
        // Clean up existing
        await disconnect()
        
        // 메시지 초기화 (채널 전환 시 이전 채널 메시지 제거)
        messages.removeAll()
        
        let config = ChatEngine.Configuration(
            chatChannelId: chatChannelId,
            accessToken: accessToken,
            extraToken: extraToken,
            uid: uid,
            channelId: channelId
        )
        
        let engine = ChatEngine(configuration: config)
        chatEngine = engine
        moderationService = ChatModerationService(blockedUsers: initialBlockedUsers)
        
        // Start listening to events
        startEventListening(engine)
        startStatsTracking()
        
        // Connect
        await engine.connect()
    }
    
    /// Disconnect from chat
    public func disconnect() async {
        eventListenTask?.cancel()
        eventListenTask = nil
        statsTask?.cancel()
        statsTask = nil
        
        await chatEngine?.disconnect()
        chatEngine = nil
        moderationService = nil
        
        connectionState = .disconnected
    }
    
    // MARK: - Message Sending
    
    /// Send a chat message
    public func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Check for commands
        if let modService = moderationService {
            if let result = await modService.processCommand(text) {
                handleCommandResult(result)
                inputText = ""
                return
            }
        }
        
        do {
            try await chatEngine?.sendMessage(text)
            
            // 서버가 본인 메시지를 에코백하지 않으므로 로컬에서 직접 추가
            let localMessage = ChatMessageItem(
                id: "\(currentUserUid ?? UUID().uuidString)_\(Int(Date().timeIntervalSince1970 * 1_000_000))",
                userId: currentUserUid ?? "me",
                nickname: currentUserNickname ?? "나",
                content: text,
                timestamp: Date(),
                type: .normal,
                badgeImageURL: nil,
                emojis: [:],
                donationAmount: nil,
                donationType: nil,
                subscriptionMonths: nil,
                profileImageUrl: nil,
                isNotice: false,
                isSystem: false
            )
            messages.append(localMessage)
            trimMessageBuffer()
            
            inputText = ""
        } catch {
            errorMessage = "메시지 전송 실패: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Moderation
    
    /// Block a user
    public func blockUser(_ userId: String) async {
        await moderationService?.blockUser(userId)
        // Remove their messages from display
        messages.removeAll { $0.userId == userId }
        // 영속화 콜백
        let blocked = await moderationService?.getBlockedUsers() ?? []
        onBlockedUsersChanged?(Array(blocked))
    }
    
    /// Unblock a user
    public func unblockUser(_ userId: String) async {
        await moderationService?.unblockUser(userId)
        // 영속화 콜백
        let blocked = await moderationService?.getBlockedUsers() ?? []
        onBlockedUsersChanged?(Array(blocked))
    }

    /// Get all blocked user IDs
    public func getBlockedUsers() async -> Set<String> {
        await moderationService?.getBlockedUsers() ?? []
    }
    
    /// Add keyword filter
    public func addKeywordFilter(_ keywords: [String]) async {
        let filter = ChatFilter(type: .keyword(keywords))
        await moderationService?.addFilter(filter)
        await refilterMessages()
    }
    
    /// Toggle user highlight
    public func toggleHighlight(userId: String) {
        if highlightedUsers.contains(userId) {
            highlightedUsers.remove(userId)
        } else {
            highlightedUsers.insert(userId)
        }
    }

    /// Set filter enabled state
    public func setFilterEnabled(_ enabled: Bool) {
        isFilterEnabled = enabled
        Task { await refilterMessages() }
    }
    
    /// Check if user is highlighted
    public func isHighlighted(userId: String) -> Bool {
        highlightedUsers.contains(userId)
    }
    
    /// Pin a message
    public func pinMessage(_ message: ChatMessageItem) {
        pinnedMessage = message
    }
    
    /// Unpin message
    public func unpinMessage() {
        pinnedMessage = nil
    }
    
    // MARK: - Display Control
    
    /// Clear all displayed messages
    public func clearMessages() {
        messages.removeAll()
        messageCount = 0
        Task { await chatEngine?.clearMessages() }
    }
    
    /// Toggle auto-scroll
    public func toggleAutoScroll() {
        isAutoScrollEnabled.toggle()
    }
    
    /// Scroll to bottom
    public func scrollToBottom() {
        isAutoScrollEnabled = true
    }
    
    // MARK: - Private Methods
    
    private func startEventListening(_ engine: ChatEngine) {
        eventListenTask?.cancel()
        eventListenTask = Task { [weak self] in
            guard let self else { return }
            
            let stream = await engine.events()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleEvent(_ event: ChatEngineEvent) async {
        logger.debug("ChatVM handleEvent: \(String(describing: event).prefix(80), privacy: .public)")
        switch event {
        case .connected:
            connectionState = .connected(serverIndex: 0)
            errorMessage = nil
            
        case .disconnected(let reason):
            connectionState = .disconnected
            errorMessage = reason
            
        case .reconnecting:
            connectionState = .reconnecting(attempt: 0)
            
        case .stateChanged(let state):
            connectionState = state
            
        case .newMessages(let msgs):
            logger.debug("ChatVM newMessages: \(msgs.count) msgs, current total: \(self.messages.count)")
            await appendFilteredMessages(msgs)
            
        case .recentMessages(let msgs):
            await appendFilteredMessages(msgs)
            
        case .donations(let msgs):
            await appendFilteredMessages(msgs)
            
        case .notice(let msg):
            let item = ChatMessageItem(from: msg, isNotice: true)
            messages.append(item)
            
        case .messageBlinded(let messageId):
            messages.removeAll { $0.id == messageId }
            
        case .kicked:
            connectionState = .disconnected
            errorMessage = "채팅에서 추방되었습니다."
            
        case .userPenalized(let userId, _):
            logger.info("User penalized: \(userId)")
            
        case .systemMessage(let msg):
            let systemItem = ChatMessageItem.system(msg)
            messages.append(systemItem)
            
        case .messagesCleared:
            messages.removeAll()
        }
        
        trimMessageBuffer()
    }
    
    private func appendFilteredMessages(_ msgs: [ChatMessage]) async {
        // 메시지의 이모티콘을 수집 (피커용 가상 팩 구성에 사용)
        for msg in msgs {
            if let emojis = msg.extras?.emojis {
                for (id, urlStr) in emojis {
                    if collectedEmoticons[id] == nil, let url = URL(string: urlStr) {
                        collectedEmoticons[id] = url
                    }
                }
            }
        }
        
        guard let modService = moderationService else {
            let rawItems = msgs.map { self.enrichWithChannelEmoticons(ChatMessageItem(from: $0)) }
            let items = filterByDonationPrefs(rawItems)
            messages.append(contentsOf: items)
            messageCount += items.count
            recentMessageTimestamps.append(contentsOf: items.map { _ in Date() })
            return
        }
        
        let filtered = await modService.filterMessages(msgs)
        let items = filterByDonationPrefs(
            filtered.map { self.enrichWithChannelEmoticons(ChatMessageItem(from: $0)) }
        )
        
        messages.append(contentsOf: items)
        messageCount += items.count
        recentMessageTimestamps.append(contentsOf: items.map { _ in Date() })
    }

    /// `showDonationsOnly` / `showDonation` 프리퍼런스 적용 필터
    private func filterByDonationPrefs(_ items: [ChatMessageItem]) -> [ChatMessageItem] {
        if showDonationsOnly {
            return items.filter { $0.type == MessageType.donation }
        } else if !showDonation {
            return items.filter { $0.type != MessageType.donation }
        }
        return items
    }
    
    /// 채널 이모티콘 맵을 메시지의 emojis에 병합
    private func enrichWithChannelEmoticons(_ item: ChatMessageItem) -> ChatMessageItem {
        guard !channelEmoticons.isEmpty else { return item }
        var merged = item.emojis
        for (key, value) in channelEmoticons where merged[key] == nil {
            merged[key] = value
        }
        guard merged.count != item.emojis.count else { return item }
        return ChatMessageItem(
            id: item.id, userId: item.userId, nickname: item.nickname,
            content: item.content, timestamp: item.timestamp, type: item.type,
            badgeImageURL: item.badgeImageURL, emojis: merged,
            donationAmount: item.donationAmount, donationType: item.donationType,
            subscriptionMonths: item.subscriptionMonths, profileImageUrl: item.profileImageUrl,
            isNotice: item.isNotice, isSystem: item.isSystem
        )
    }
    
    private func refilterMessages() async {
        guard let engine = chatEngine else { return }
        let allMessages = await engine.messages
        
        guard let modService = moderationService else { return }
        let filtered = await modService.filterMessages(allMessages)
        messages = filterByDonationPrefs(
            filtered.map { enrichWithChannelEmoticons(ChatMessageItem(from: $0)) }
        )
    }
    
    private func trimMessageBuffer() {
        if messages.count > maxVisibleMessages {
            messages.removeFirst(messages.count - maxVisibleMessages)
        }
    }
    
    // State for export sheet
    public var showExportSheet = false
    
    // MARK: - Aggregate Stats (computed)
    
    /// 고유 참여 사용자 수
    public var uniqueUserCount: Int {
        Set(messages.map(\.userId)).count
    }
    
    /// 도네이션 총 횟수
    public var donationCount: Int {
        messages.filter { $0.type == MessageType.donation }.count
    }
    
    /// 도네이션 총 금액
    public var totalDonationAmount: Int {
        messages.compactMap(\.donationAmount).reduce(0, +)
    }
    
    /// 구독 메시지 수
    public var subscriptionCount: Int {
        messages.filter { $0.type == MessageType.subscription }.count
    }
    
    private func handleCommandResult(_ result: ChatCommandResult) {
        switch result {
        case .localAction(let msg):
            let systemItem = ChatMessageItem.system(msg)
            messages.append(systemItem)
            
        case .serverCommand(let command, _):
            logger.info("Server command: \(command.rawValue)")
            
        case .clearChat:
            clearMessages()
            
        case .exportChat:
            showExportSheet = true
            
        case .error(let msg):
            let errorItem = ChatMessageItem.system("⚠️ \(msg)")
            messages.append(errorItem)
        }
    }
    
    private func startStatsTracking() {
        statsTask = Task { [weak self] in
            guard let self else { return }
            
            let timer = AsyncTimerSequence(interval: 1.0)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                
                let now = Date()
                await MainActor.run {
                    self.recentMessageTimestamps = self.recentMessageTimestamps.filter {
                        now.timeIntervalSince($0) < 5.0
                    }
                    self.messagesPerSecond = Double(self.recentMessageTimestamps.count) / 5.0
                }
            }
        }
    }
}

// MARK: - Chat Message Item (View Model)

public struct ChatMessageItem: Identifiable, Sendable {
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
    
    fileprivate init(
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
