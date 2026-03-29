// MARK: - ChatViewModel.swift
// CViewApp - Chat ViewModel
// 원본: ChzzkChatService 직접 참조 → 개선: ChatEngine 추상화 + @Observable

import Foundation
import SwiftUI
import CViewCore
import CViewChat
import CViewNetworking
import AppKit

// MARK: - Chat ViewModel

@Observable
@MainActor
public final class ChatViewModel {
    
    // MARK: - State
    
    /// Virtualized message buffer — ring buffer that caps visible messages at `maxVisibleMessages`.
    /// Using a ring buffer instead of plain Array gives O(1) append/eviction and avoids
    /// Array.removeFirst reallocation when trimming old messages.
    public var messages = ChatMessageBuffer(capacity: 200)
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

    // 채팅 표시 모드
    public var displayMode: ChatDisplayMode = .side
    public var overlayWidth: CGFloat = 340
    public var overlayHeight: CGFloat = 400
    public var overlayBackgroundOpacity: Double = 0.5
    public var overlayShowInput: Bool = false

    // Filter / capacity
    public var maxVisibleMessages: Int = 200 {
        didSet {
            if maxVisibleMessages != messages.capacity {
                messages.resize(to: maxVisibleMessages)
            }
        }
    }
    public var blockedWords: [String] = []
    
    // Stats
    public var messageCount: Int = 0
    public var messagesPerSecond: Double = 0

    // MARK: - Chat History & Replay Mode

    /// Full chat history (up to 5000 messages), separate from the visible ring buffer.
    public var chatHistory: [ChatMessageItem] = []

    /// When true, the user has scrolled up — auto-scroll is paused and new messages
    /// accumulate without jumping the viewport.
    public var isReplayMode: Bool = false

    /// Number of new messages received while in replay mode.
    public var unreadCount: Int = 0

    /// Maximum number of messages retained in the full history buffer.
    private static let maxHistorySize = 2500
    
    // Emoticon/highlight
    public var highlightedUsers: Set<String> = []
    public var pinnedMessage: ChatMessageItem?
    public var isFilterEnabled: Bool = true

    // MARK: - Autocomplete State

    /// 이모티콘 자동완성 제안 목록 (`:keyword` 입력 시)
    public var emoticonSuggestions: [EmoticonSuggestion] = []
    /// 멘션 자동완성 제안 목록 (`@name` 입력 시)
    public var mentionSuggestions: [MentionSuggestion] = []
    /// 선택된 자동완성 항목 인덱스
    public var autocompleteSelectedIndex: Int = 0
    /// 현재 자동완성 트리거
    public var autocompleteTrigger: AutocompleteTrigger = .none
    /// 최근 채팅 참여자 (멘션 제안용, 최신순)
    public var recentChatters: [MentionSuggestion] = []
    /// 최대 보관할 최근 참여자 수
    static let maxRecentChattersCount = 100

    /// 자동완성 제안이 활성 상태인지
    public var isAutocompleteActive: Bool {
        !emoticonSuggestions.isEmpty || !mentionSuggestions.isEmpty
    }
    
    /// 채널 이모티콘 맵 (emoticonId → imageURL)
    public var channelEmoticons: [String: String] = [:] {
        didSet {
            guard !channelEmoticons.isEmpty else { return }
            // 채널 이모티콘 로드 완료 후 기존 메시지에 소급 적용 (in-place, no array copy)
            if !messages.isEmpty {
                messages.mapInPlace { enrichWithChannelEmoticons($0) }
            }
            // 채널 이모티콘 이미지 프리페치
            let urls = channelEmoticons.values.compactMap { URL(string: $0) }
            if !urls.isEmpty {
                Task.detached(priority: .background) {
                    await ImageCacheService.shared.prefetch(urls)
                }
            }
        }
    }
    
    /// 채널 이모티콘 팩 목록
    public var emoticonPacks: [EmoticonPack] = [] {
        didSet {
            guard !emoticonPacks.isEmpty else { return }
            prefetchEmoticonImages()
        }
    }
    
    /// 채팅 메시지에서 수집된 이모티콘 (ID → URL)
    var collectedEmoticons: [String: URL] = [:]
    
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
    
    // MARK: - Stream Alert Queue (플레이어 오버레이 알림)

    /// 플레이어 화면 위에 표시할 알림 큐 (후원, 구독 등)
    public var streamAlerts: [StreamAlertItem] = []
    /// 알림 오버레이 활성화 여부
    public var isStreamAlertEnabled: Bool = true
    /// 동시에 표시할 최대 알림 수
    private static let maxVisibleAlerts = 3
    /// 알림 자동 해제 시간 (초)
    private static let alertDismissDelay: TimeInterval = 5.0

    // Error
    public var errorMessage: String?

    /// 채팅 전송 가능 여부: 연결됨 + 로그인 상태(uid 보유)
    public var canSendChat: Bool {
        connectionState.isConnected && currentUserUid != nil
    }

    // MARK: - Dependencies
    
    var chatEngine: ChatEngine?
    var moderationService: ChatModerationService?
    let logger = AppLogger.chat
    
    /// TTS 서비스 (후원/구독 메시지 음성 읽기)
    let ttsService = ChatTTSService()
    
    /// 차단 목록 변경 시 외부 저장용 콜백
    public var onBlockedUsersChanged: (([String]) -> Void)?
    
    /// 초기 차단 목록 (connect 전에 설정)
    public var initialBlockedUsers: [String] = []
    
    /// 현재 로그인 사용자 정보 (보낸 메시지 로컬 표시용)
    public var currentUserUid: String?
    public var currentUserNickname: String?
    
    // Tasks
    var eventListenTask: Task<Void, Never>?
    var statsTask: Task<Void, Never>?
    @ObservationIgnored var recentMessageTimestamps: [Date] = []
    
    /// 멀티라이브 비활성 세션 CPU 절약: 백그라운드 모드에서 flush 간격 증가 + 통계 중단
    @ObservationIgnored public var isBackgroundMode: Bool = false
    /// 백그라운드 모드에서의 배치 flush 간격 (1초 — 기본 100ms의 10배)
    @ObservationIgnored let backgroundFlushIntervalNs: UInt64 = 1_000_000_000
    
    // MARK: - Batching (reduces SwiftUI update frequency from 1000/s → ~10/s)
    
    /// Pending messages accumulated before the next batch flush.
    @ObservationIgnored var pendingMessages: [ChatMessageItem] = []
    /// Active batch‐flush timer task.
    @ObservationIgnored var batchFlushTask: Task<Void, Never>?
    /// Batch flush interval in nanoseconds.
    /// [Freeze Fix] 100ms → 250ms: 멀티라이브 4세션 시 40 mutations/s → 16 mutations/s
    /// MainActor @Observable 업데이트 빈도를 줄여 UI 이벤트 루프 포화 방지
    @ObservationIgnored let batchFlushIntervalNs: UInt64 = 250_000_000
    
    // MARK: - Incremental Stats Cache (O(n) computed → O(batch) 증분 업데이트)
    
    /// 고유 참여 사용자 수 (증분 캐시)
    public internal(set) var uniqueUserCount: Int = 0
    @ObservationIgnored var _uniqueUsers = Set<String>()
    
    /// 도네이션 총 횟수 (증분 캐시)
    public internal(set) var donationCount: Int = 0
    
    /// 도네이션 총 금액 (증분 캐시)
    public internal(set) var totalDonationAmount: Int = 0
    
    /// 구독 메시지 수 (증분 캐시)
    public internal(set) var subscriptionCount: Int = 0
    
    // MARK: - Initialization
    
    public init() {
        pendingMessages.reserveCapacity(64)
    }

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
        ttsService.isEnabled = settings.ttsEnabled
        ttsService.volume = settings.ttsVolume
        ttsService.rate = settings.ttsRate
        displayMode = settings.displayMode
        overlayWidth = settings.overlayWidth
        overlayHeight = settings.overlayHeight
        overlayBackgroundOpacity = settings.overlayBackgroundOpacity
        overlayShowInput = settings.overlayShowInput
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
        s.displayMode = displayMode
        s.overlayWidth = overlayWidth
        s.overlayHeight = overlayHeight
        s.overlayBackgroundOpacity = overlayBackgroundOpacity
        s.overlayShowInput = overlayShowInput
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
        pendingMessages.removeAll(keepingCapacity: true)
        chatHistory.removeAll()
        exitReplayMode()
        
        // 통계 카운터 리셋 (채널 전환 시 이전 채널 수치 누적 방지)
        messageCount = 0
        messagesPerSecond = 0
        recentMessageTimestamps.removeAll()
        resetIncrementalStats()
        
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
        batchFlushTask?.cancel()
        batchFlushTask = nil
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
        pendingMessages.removeAll(keepingCapacity: true)
        ttsService.stop()
        
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
            // Local messages bypass batching for instant feedback
            appendToHistory([localMessage])
            messages.append(localMessage)

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
        pendingMessages.removeAll(keepingCapacity: true)
        batchFlushTask?.cancel()
        batchFlushTask = nil
        messageCount = 0
        chatHistory.removeAll()
        resetIncrementalStats()
        exitReplayMode()
        Task { await chatEngine?.clearMessages() }
    }
    
    /// Toggle auto-scroll
    public func toggleAutoScroll() {
        isAutoScrollEnabled.toggle()
        if !isAutoScrollEnabled {
            enterReplayMode()
        } else {
            exitReplayMode()
        }
    }

    /// Scroll to bottom and exit replay mode
    public func scrollToBottom() {
        exitReplayMode()
    }

    // MARK: - Scroll Position

    /// replay mode 진입 debounce 타스크 — 빠른 연속 스크롤 시 불필요한 replay 진입/해제 반복 방지
    @ObservationIgnored private var replayDebounceTask: Task<Void, Never>?

    /// 대기 중인 replay debounce 타스크 취소 — 프로그래밍적 스크롤 시 View에서 호출
    public func cancelReplayDebounce() {
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
    }

    /// 스크롤 위치 변경 시 호출 — 치지직 방식: 하단 도달 시 즉시 해제, 이탈 시 debounce 후 진입
    /// - Parameter isNearBottom: 스크롤이 하단 근처(80px 이내)인지 여부
    public func onScrollPositionChanged(isNearBottom: Bool) {
        if isNearBottom {
            // 하단에 도달하면 즉시 리플레이 모드 해제 + 보류 중인 진입 취소
            replayDebounceTask?.cancel()
            replayDebounceTask = nil
            if isReplayMode {
                exitReplayMode()
            }
        } else {
            // 하단에서 벗어나면 debounce(300ms) 후 리플레이 모드 진입
            // — 메시지 배치 flush(100ms)로 인한 일시적 geometry 변경을 충분히 걸러냄
            guard !isReplayMode else { return }
            guard messages.count > 3 else { return }
            guard replayDebounceTask == nil else { return }
            replayDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self, !self.isReplayMode else { return }
                self.enterReplayMode()
                self.replayDebounceTask = nil
            }
        }
    }

    // MARK: - Replay Mode

    /// Enter replay mode (user scrolled away from bottom).
    public func enterReplayMode() {
        guard !isReplayMode else { return }
        isReplayMode = true
        unreadCount = 0
        isAutoScrollEnabled = false
    }

    /// Exit replay mode and jump back to the latest messages.
    public func exitReplayMode() {
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
        isReplayMode = false
        unreadCount = 0
        isAutoScrollEnabled = true
    }

    /// Append items to the persistent history buffer, capping at `maxHistorySize`.
    func appendToHistory(_ items: [ChatMessageItem]) {
        chatHistory.append(contentsOf: items)
        if chatHistory.count > Self.maxHistorySize {
            chatHistory.removeFirst(chatHistory.count - Self.maxHistorySize)
        }
    }
    
    // MARK: - Stream Alert Methods

    /// 알림을 큐에 추가하고 자동 해제 타이머 시작
    func enqueueStreamAlert(_ alert: StreamAlertItem) {
        guard isStreamAlertEnabled else { return }

        // 최대 표시 수 초과 시 가장 오래된 항목 제거
        if streamAlerts.count >= Self.maxVisibleAlerts {
            streamAlerts.removeFirst()
        }

        withAnimation(DesignTokens.Animation.contentTransition) {
            streamAlerts.append(alert)
        }

        // 자동 해제 타이머
        let alertId = alert.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.alertDismissDelay))
            guard let self else { return }
            withAnimation(DesignTokens.Animation.contentTransition) {
                self.streamAlerts.removeAll { $0.id == alertId }
            }
        }
    }

    /// 수동으로 알림 해제
    public func dismissStreamAlert(_ id: String) {
        withAnimation(DesignTokens.Animation.contentTransition) {
            streamAlerts.removeAll { $0.id == id }
        }
    }

    // State for export sheet
    public var showExportSheet = false
}
