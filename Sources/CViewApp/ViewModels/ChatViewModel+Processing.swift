// MARK: - ChatViewModel+Processing.swift
// CViewApp — 이벤트 처리, 필터링, 이모티콘, 배칭, 통계

import Foundation
import SwiftUI
import CViewCore
import CViewChat
import CViewNetworking

extension ChatViewModel {

    // MARK: - Event Listening

    func startEventListening(_ engine: ChatEngine) {
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
    func handleEvent(_ event: ChatEngineEvent) async {
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

    // MARK: - Message Filtering

    func appendFilteredMessages(_ msgs: [ChatMessage]) async {
        collectEmoticons(from: msgs)

        let channelEmotes = channelEmoticons
        let donationsOnly = showDonationsOnly
        let showDon = showDonation

        let filteredMsgs: [ChatMessage]
        if let modService = moderationService {
            filteredMsgs = await modService.filterMessages(msgs)
        } else {
            filteredMsgs = msgs
        }

        let items = await Task.detached(priority: .userInitiated) {
            let rawItems = filteredMsgs.map { msg in
                Self.enrichWithChannelEmoticonsPure(ChatMessageItem(from: msg), channelEmoticons: channelEmotes)
            }
            return Self.filterByDonationPrefsPure(rawItems, donationsOnly: donationsOnly, showDonation: showDon)
        }.value

        for item in items where item.type == .subscription {
            if let alert = StreamAlertItem(from: item) {
                enqueueStreamAlert(alert)
            }
        }

        enqueueBatchedMessages(items)
    }

    /// 이모티콘 수집 — 새로 발견된 이모티콘은 바로 프리페치
    func collectEmoticons(from msgs: [ChatMessage]) {
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
    func prefetchEmoticonImages() {
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
    func filterByDonationPrefs(_ items: [ChatMessageItem]) -> [ChatMessageItem] {
        Self.filterByDonationPrefsPure(items, donationsOnly: showDonationsOnly, showDonation: showDonation)
    }

    nonisolated static func filterByDonationPrefsPure(
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
    func enrichWithChannelEmoticons(_ item: ChatMessageItem) -> ChatMessageItem {
        Self.enrichWithChannelEmoticonsPure(item, channelEmoticons: channelEmoticons)
    }

    nonisolated static func enrichWithChannelEmoticonsPure(
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

    func refilterMessages() async {
        guard let engine = chatEngine else { return }
        let allMessages = await engine.messages

        guard let modService = moderationService else { return }
        let filtered = await modService.filterMessages(allMessages)

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

    /// Enqueue items for the next batch flush.
    func enqueueBatchedMessages(_ items: [ChatMessageItem]) {
        guard !items.isEmpty else { return }
        pendingMessages.append(contentsOf: items)
        recentMessageTimestamps.append(contentsOf: items.map { _ in Date() })
        messageCount += items.count
        scheduleBatchFlush()
    }

    /// Schedule a single batch-flush task.
    func scheduleBatchFlush() {
        guard batchFlushTask == nil else { return }
        let interval = isBackgroundMode ? backgroundFlushIntervalNs : batchFlushIntervalNs
        batchFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingMessages()
        }
    }

    /// Move all pending messages into the visible ring buffer in one shot.
    func flushPendingMessages() {
        batchFlushTask = nil
        guard !pendingMessages.isEmpty else { return }
        for msg in pendingMessages {
            if msg.type == .donation || msg.type == .subscription {
                ttsService.enqueue(msg)
            }
        }
        trackRecentChatters(from: pendingMessages)
        appendToHistory(pendingMessages)
        if isReplayMode {
            unreadCount += pendingMessages.count
        }
        updateIncrementalStats(with: pendingMessages)
        messages.append(contentsOf: pendingMessages)
        pendingMessages.removeAll(keepingCapacity: true)
    }

    /// 배치 단위로 통계를 증분 업데이트
    func updateIncrementalStats(with batch: [ChatMessageItem]) {
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
    func resetIncrementalStats() {
        _uniqueUsers.removeAll(keepingCapacity: true)
        uniqueUserCount = 0
        donationCount = 0
        totalDonationAmount = 0
        subscriptionCount = 0
    }

    func handleCommandResult(_ result: ChatCommandResult) {
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

    func startStatsTracking() {
        statsTask = Task { [weak self] in
            guard let self else { return }

            let timer = AsyncTimerSequence(interval: 3.0)
            for await _ in timer {
                guard !Task.isCancelled else { break }

                guard !self.isBackgroundMode else { continue }

                let now = Date()
                await MainActor.run {
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
}
