// MARK: - ChatViewModel.swift
// CViewApp - Chat ViewModel
// 원본: ChzzkChatService 직접 참조 → 개선: ChatEngine 추상화 + @Observable

import Foundation
import SwiftUI
import AVFoundation
import CViewCore
import CViewChat
import CViewNetworking
import AppKit

// MARK: - Chat TTS Service

/// 후원/구독 메시지를 음성으로 읽어주는 TTS 서비스
/// AVSpeechSynthesizer 기반, 큐 방식 (최대 5개 대기)
@MainActor
final class ChatTTSService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [String] = []
    private let maxQueueSize = 5
    private var isSpeaking = false

    var isEnabled: Bool = false
    var volume: Float = 0.8
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 후원/구독 메시지를 TTS 큐에 추가
    func enqueue(_ message: ChatMessageItem) {
        guard isEnabled else { return }
        guard let text = formatTTSText(message) else { return }
        guard queue.count < maxQueueSize else { return }
        queue.append(text)
        speakNextIfIdle()
    }

    /// TTS 중지 및 큐 초기화
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
        isSpeaking = false
    }

    // MARK: - Private

    private func formatTTSText(_ message: ChatMessageItem) -> String? {
        if message.type == .donation, let amount = message.donationAmount {
            let content = message.content.isEmpty ? "" : ". \(message.content)"
            return "\(message.nickname)님이 \(amount)원 후원\(content)"
        } else if message.type == .subscription {
            if let months = message.subscriptionMonths, months > 0 {
                return "\(message.nickname)님이 \(months)개월 구독"
            }
            return "\(message.nickname)님이 구독"
        }
        return nil
    }

    private func speakNextIfIdle() {
        guard !isSpeaking, !queue.isEmpty else { return }
        let text = queue.removeFirst()
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = volume
        utterance.rate = rate
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.speakNextIfIdle()
        }
    }
}

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
    private static let maxRecentChatters = 100

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
    
    private var chatEngine: ChatEngine?
    private var moderationService: ChatModerationService?
    private let logger = AppLogger.chat
    
    /// TTS 서비스 (후원/구독 메시지 음성 읽기)
    private let ttsService = ChatTTSService()
    
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
    @ObservationIgnored private var recentMessageTimestamps: [Date] = []
    
    /// 멀티라이브 비활성 세션 CPU 절약: 백그라운드 모드에서 flush 간격 증가 + 통계 중단
    @ObservationIgnored public var isBackgroundMode: Bool = false
    /// 백그라운드 모드에서의 배치 flush 간격 (1초 — 기본 100ms의 10배)
    @ObservationIgnored private let backgroundFlushIntervalNs: UInt64 = 1_000_000_000
    
    // MARK: - Batching (reduces SwiftUI update frequency from 1000/s → ~10/s)
    
    /// Pending messages accumulated before the next batch flush.
    @ObservationIgnored private var pendingMessages: [ChatMessageItem] = []
    /// Active batch‐flush timer task.
    @ObservationIgnored private var batchFlushTask: Task<Void, Never>?
    /// Batch flush interval in nanoseconds (default 100 ms).
    @ObservationIgnored private let batchFlushIntervalNs: UInt64 = 100_000_000
    
    // MARK: - Incremental Stats Cache (O(n) computed → O(batch) 증분 업데이트)
    
    /// 고유 참여 사용자 수 (증분 캐시)
    public private(set) var uniqueUserCount: Int = 0
    @ObservationIgnored private var _uniqueUsers = Set<String>()
    
    /// 도네이션 총 횟수 (증분 캐시)
    public private(set) var donationCount: Int = 0
    
    /// 도네이션 총 금액 (증분 캐시)
    public private(set) var totalDonationAmount: Int = 0
    
    /// 구독 메시지 수 (증분 캐시)
    public private(set) var subscriptionCount: Int = 0
    
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
    private func appendToHistory(_ items: [ChatMessageItem]) {
        chatHistory.append(contentsOf: items)
        if chatHistory.count > Self.maxHistorySize {
            chatHistory.removeFirst(chatHistory.count - Self.maxHistorySize)
        }
    }
    
    // MARK: - Stream Alert Methods

    /// 알림을 큐에 추가하고 자동 해제 타이머 시작
    private func enqueueStreamAlert(_ alert: StreamAlertItem) {
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
            await appendFilteredMessages(msgs)
            
        case .recentMessages(let msgs):
            await appendFilteredMessages(msgs)
            
        case .donations(let msgs):
            await appendFilteredMessages(msgs)
            // 후원 알림 발행
            for msg in msgs {
                let item = ChatMessageItem(from: msg)
                if let alert = StreamAlertItem(from: item) {
                    enqueueStreamAlert(alert)
                }
            }
            
        case .notice(let msg):
            let item = ChatMessageItem(from: msg, isNotice: true)
            messages.append(item)
            // 공지 알림 발행
            if let alert = StreamAlertItem.notice(from: item) {
                enqueueStreamAlert(alert)
            }
            
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
    }
    
    private func appendFilteredMessages(_ msgs: [ChatMessage]) async {
        // 메시지의 이모티콘을 수집 (피커용 가상 팩 구성에 사용)
        collectEmoticons(from: msgs)
        
        // 채널 이모티콘 맵과 필터 설정을 캡처 — 백그라운드 Task에서 사용
        let channelEmotes = channelEmoticons
        let donationsOnly = showDonationsOnly
        let showDon = showDonation
        
        // Moderation 필터링 (actor hop은 여기서 — 결과는 [ChatMessage])
        let filteredMsgs: [ChatMessage]
        if let modService = moderationService {
            filteredMsgs = await modService.filterMessages(msgs)
        } else {
            filteredMsgs = msgs
        }
        
        // 무거운 변환/필터링을 백그라운드 스레드에서 수행 — 메인 스레드 부하 제거
        let items = await Task.detached(priority: .userInitiated) {
            let rawItems = filteredMsgs.map { msg in
                Self.enrichWithChannelEmoticonsPure(ChatMessageItem(from: msg), channelEmoticons: channelEmotes)
            }
            return Self.filterByDonationPrefsPure(rawItems, donationsOnly: donationsOnly, showDonation: showDon)
        }.value
        
        // 구독 메시지 알림 발행 (newMessages 경로)
        for item in items where item.type == .subscription {
            if let alert = StreamAlertItem(from: item) {
                enqueueStreamAlert(alert)
            }
        }
        
        enqueueBatchedMessages(items)
    }
    
    /// 이모티콘 수집 — MainActor에서 실행 (collectedEmoticons 딕셔너리 접근)
    /// 새로 발견된 이모티콘은 바로 프리페치하여 다음 표시 시 즉시 로드
    private func collectEmoticons(from msgs: [ChatMessage]) {
        var newURLs: [URL] = []
        for msg in msgs {
            if let emojis = msg.extras?.emojis {
                for (id, urlStr) in emojis {
                    if collectedEmoticons[id] == nil, let url = URL(string: urlStr) {
                        collectedEmoticons[id] = url
                        newURLs.append(url)
                    }
                }
            }
        }
        if !newURLs.isEmpty {
            Task.detached(priority: .background) {
                await ImageCacheService.shared.prefetch(newURLs)
            }
        }
    }

    /// 이모티콘 팩의 모든 이미지를 백그라운드에서 미리 다운로드
    private func prefetchEmoticonImages() {
        let urls = emoticonPacks
            .flatMap { $0.emoticons ?? [] }
            .compactMap { $0.imageURL }
        guard !urls.isEmpty else { return }
        logger.info("이모티콘 프리페치 시작: \(urls.count)개 이미지")
        Task.detached(priority: .background) {
            await ImageCacheService.shared.prefetch(urls)
        }
    }

    /// `showDonationsOnly` / `showDonation` 프리퍼런스 적용 필터
    private func filterByDonationPrefs(_ items: [ChatMessageItem]) -> [ChatMessageItem] {
        Self.filterByDonationPrefsPure(items, donationsOnly: showDonationsOnly, showDonation: showDonation)
    }
    
    /// nonisolated 순수 함수 — Task.detached에서 안전하게 호출 가능
    private nonisolated static func filterByDonationPrefsPure(
        _ items: [ChatMessageItem], donationsOnly: Bool, showDonation: Bool
    ) -> [ChatMessageItem] {
        if donationsOnly {
            return items.filter { $0.type == MessageType.donation }
        } else if !showDonation {
            return items.filter { $0.type != MessageType.donation }
        }
        return items
    }
    
    /// 채널 이모티콘 맵을 메시지의 emojis에 병합
    private func enrichWithChannelEmoticons(_ item: ChatMessageItem) -> ChatMessageItem {
        Self.enrichWithChannelEmoticonsPure(item, channelEmoticons: channelEmoticons)
    }
    
    /// nonisolated 순수 함수 — Task.detached에서 안전하게 호출 가능
    private nonisolated static func enrichWithChannelEmoticonsPure(
        _ item: ChatMessageItem, channelEmoticons: [String: String]
    ) -> ChatMessageItem {
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
        
        // 백그라운드에서 변환 수행
        let channelEmotes = channelEmoticons
        let donationsOnly = showDonationsOnly
        let showDon = showDonation
        let items = await Task.detached(priority: .userInitiated) {
            let raw = filtered.map { Self.enrichWithChannelEmoticonsPure(ChatMessageItem(from: $0), channelEmoticons: channelEmotes) }
            return Self.filterByDonationPrefsPure(raw, donationsOnly: donationsOnly, showDonation: showDon)
        }.value
        messages.replaceAll(with: items)
    }
    
    // MARK: - Batching
    
    /// Enqueue items for the next batch flush (instead of directly mutating `messages`).
    /// Reduces SwiftUI state updates from potentially 1 000+/s to ~10/s.
    private func enqueueBatchedMessages(_ items: [ChatMessageItem]) {
        guard !items.isEmpty else { return }
        pendingMessages.append(contentsOf: items)
        recentMessageTimestamps.append(contentsOf: items.map { _ in Date() })
        messageCount += items.count
        scheduleBatchFlush()
    }
    
    /// Schedule a single batch-flush task. No-op if one is already pending.
    /// 백그라운드 세션은 1초 간격, 포그라운드는 100ms 간격
    private func scheduleBatchFlush() {
        guard batchFlushTask == nil else { return }
        let interval = isBackgroundMode ? backgroundFlushIntervalNs : batchFlushIntervalNs
        batchFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingMessages()
        }
    }
    
    /// Move all pending messages into the visible ring buffer in one shot.
    private func flushPendingMessages() {
        batchFlushTask = nil
        guard !pendingMessages.isEmpty else { return }
        // TTS: 후원/구독 메시지를 음성으로 읽어주기
        for msg in pendingMessages {
            if msg.type == .donation || msg.type == .subscription {
                ttsService.enqueue(msg)
            }
        }
        // Track recent chatters for mention autocomplete
        trackRecentChatters(from: pendingMessages)
        // Persist into full history
        appendToHistory(pendingMessages)
        // Track unread while in replay mode
        if isReplayMode {
            unreadCount += pendingMessages.count
        }
        // 증분 통계 업데이트 — O(batch_size), 이전의 O(messages.count) 대비 대폭 절감
        updateIncrementalStats(with: pendingMessages)
        messages.append(contentsOf: pendingMessages)
        pendingMessages.removeAll(keepingCapacity: true)
    }
    
    /// 배치 단위로 통계를 증분 업데이트
    private func updateIncrementalStats(with batch: [ChatMessageItem]) {
        for msg in batch {
            _uniqueUsers.insert(msg.userId)
            if msg.type == .donation {
                donationCount += 1
                if let amt = msg.donationAmount { totalDonationAmount += amt }
            } else if msg.type == .subscription {
                subscriptionCount += 1
            }
        }
        uniqueUserCount = _uniqueUsers.count
    }
    
    /// 통계 캐시 초기화
    private func resetIncrementalStats() {
        _uniqueUsers.removeAll(keepingCapacity: true)
        uniqueUserCount = 0
        donationCount = 0
        totalDonationAmount = 0
        subscriptionCount = 0
    }
    
    // State for export sheet
    public var showExportSheet = false
    
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
                
                // 백그라운드 세션은 통계 계산 생략 — CPU 절약
                guard !self.isBackgroundMode else { continue }
                
                let now = Date()
                await MainActor.run {
                    // O(1) 접근: 정렬된 배열에서 5초 이전 항목의 인덱스 찾기
                    let cutoff = now.addingTimeInterval(-5.0)
                    if let idx = self.recentMessageTimestamps.firstIndex(where: { $0 >= cutoff }) {
                        self.recentMessageTimestamps.removeSubrange(..<idx)
                    } else {
                        self.recentMessageTimestamps.removeAll()
                    }
                    self.messagesPerSecond = Double(self.recentMessageTimestamps.count) / 5.0
                }
            }
        }
    }

    // MARK: - Autocomplete

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
        if recentChatters.count > Self.maxRecentChatters {
            recentChatters = Array(recentChatters.prefix(Self.maxRecentChatters))
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
    private func detectAutocompleteTrigger(in text: String, cursorOffset: Int) -> AutocompleteTrigger {
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
    private func gatherAllEmoticons() -> [EmoticonSuggestion] {
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
