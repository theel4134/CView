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
            // 치지직 웹처럼 채팅방 환영 메시지 표시
            let welcome = ChatMessageItem.system("채팅방에 오신 것을 환영합니다!\n쾌적한 시청 환경을 위해 불필요한 메시지는 필터링 됩니다. 올바른 라이브 채팅 문화 만들기에 동참해 주세요.")
            messages.append(welcome)

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
            guard !msg.isEmpty else { return }
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
        let modService = moderationService

        // moderation 필터링 + 이모티콘 변환 + 후원 필터를 단일 백그라운드 파이프라인에서 처리
        // (MainActor 경유 없이 actor hop → 변환 → 필터를 연속 실행)
        let items = await Task.detached(priority: .userInitiated) {
            let filtered: [ChatMessage]
            if let modService {
                filtered = await modService.filterMessages(msgs)
            } else {
                filtered = msgs
            }
            let rawItems = filtered.map { msg in
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

    /// 이모티콘 팩의 이미지를 백그라운드에서 미리 다운로드
    /// - 팩이 매우 크면 수백~수천 URL 대량 다운로드로 네트워크/메모리 부담이 크므로
    ///   앞쪽 최대 `prefetchLimit`개만 미리 받고 나머지는 실제 사용 시(collectEmoticons) lazy 로드.
    func prefetchEmoticonImages() {
        let prefetchLimit = 120
        let allURLs = emoticonPacks
            .flatMap { $0.emoticons ?? [] }
            .compactMap { $0.imageURL }
        guard !allURLs.isEmpty else { return }
        let urls = Array(allURLs.prefix(prefetchLimit))
        logger.info("이모티콘 프리페치 시작: \(urls.count)/\(allURLs.count)개 (상위 \(prefetchLimit))")
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
        return item.withEmojis(merged)
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
    /// 인입 시점에 중복 제거를 선행하여 드립 flush 부담 최소화.
    func enqueueBatchedMessages(_ items: [ChatMessageItem]) {
        guard !items.isEmpty else { return }

        // 만료된 에코 키 정리
        let now = Date()
        recentSentEchoKeys = recentSentEchoKeys.filter { $0.value > now }

        let unique = items.filter { item in
            // ID 기반 중복 제거 — FIFO 큐로 오래된 ID만 제거 (이전 전체 clear → 재연결/recent 동시 수신 시 중복 통과 버그 수정)
            guard seenMessageIDs.insert(item.id).inserted else { return false }
            seenMessageIDQueue.append(item.id)
            // 본인 메시지 에코백 필터: sendMessage()에서 로컬 추가한 메시지와 동일한 서버 에코 제거
            let echoKey = "\(item.userId)_\(item.content.hashValue)"
            if let expiry = recentSentEchoKeys[echoKey], now < expiry {
                recentSentEchoKeys.removeValue(forKey: echoKey)
                return false
            }
            return true
        }
        // 용량 초과 시 오래된 절반만 제거 (최근 창 보존하여 재수신 메시지 중복 방지)
        if seenMessageIDQueue.count > 800 {
            let removeCount = seenMessageIDQueue.count - 400
            for id in seenMessageIDQueue.prefix(removeCount) {
                seenMessageIDs.remove(id)
            }
            seenMessageIDQueue.removeFirst(removeCount)
        }
        guard !unique.isEmpty else { return }
        pendingMessages.append(contentsOf: unique)
        recentMessageTimestamps.append(contentsOf: unique.map { _ in Date() })
        messageCount += unique.count
        scheduleBatchFlush()
    }

    /// Schedule a single batch-flush task.
    /// 치지직 웹 채팅처럼 1개씩 드립 표시:
    /// - 포그라운드: 50ms 간격으로 메시지 1개씩 flush
    /// - 백그라운드: 3초 간격으로 일괄 flush (CPU 절약)
    func scheduleBatchFlush() {
        guard batchFlushTask == nil else { return }
        guard !pendingMessages.isEmpty else { return }
        let interval = isBackgroundMode ? backgroundFlushIntervalNs : batchFlushIntervalNs
        batchFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingMessages()
        }
    }

    /// 포그라운드: 메시지 1개씩 드립 flush (큐 밀리면 catch-up)
    /// 백그라운드: 일괄 flush
    func flushPendingMessages() {
        batchFlushTask = nil
        guard !pendingMessages.isEmpty else { return }

        // 백그라운드: 전량 flush (애니메이션 없이)
        if isBackgroundMode {
            commitMessages(pendingMessages)
            pendingMessages.removeAll(keepingCapacity: true)
            return
        }

        // 포그라운드 드립: 기본 1개, 큐가 15개 이상 밀리면 절반을 한 번에 flush
        let count = pendingMessages.count
        let flushCount: Int
        if count > 15 {
            flushCount = count / 2
        } else {
            flushCount = 1
        }

        let toFlush = Array(pendingMessages.prefix(flushCount))
        pendingMessages.removeFirst(flushCount)

        commitMessages(toFlush)

        // 남은 메시지가 있으면 다음 드립 예약
        if !pendingMessages.isEmpty {
            scheduleBatchFlush()
        }
    }

    /// 메시지를 visible buffer에 커밋
    private func commitMessages(_ msgs: [ChatMessageItem]) {
        guard !msgs.isEmpty else { return }
        for msg in msgs {
            if msg.type == .donation || msg.type == .subscription {
                ttsService.enqueue(msg)
            }
        }
        trackRecentChatters(from: msgs)
        appendToHistory(msgs)
        if isReplayMode {
            unreadCount += msgs.count
        }
        updateIncrementalStats(with: msgs)
        messages.append(contentsOf: msgs)
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
