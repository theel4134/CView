// MARK: - BackgroundUpdateService.swift
// CViewApp - 백그라운드 팔로잉 상태 업데이트 서비스

import Foundation
import AppKit       // NSWorkspace sleep/wake 알림
import CViewCore
import CViewNetworking

/// 백그라운드 업데이트에서 감지된 이벤트들
struct BackgroundUpdateEvent: Sendable {
    /// 새로 온라인 된 채널들
    let newlyOnline: [OnlineChannel]
    /// 카테고리가 변경된 채널들 (channelId, channelName, oldCategory, newCategory)
    let categoryChanged: [ChannelChangeInfo]
    /// 제목이 변경된 채널들 (channelId, channelName, oldTitle, newTitle)
    let titleChanged: [ChannelChangeInfo]
    
    var hasAnyEvent: Bool {
        !newlyOnline.isEmpty || !categoryChanged.isEmpty || !titleChanged.isEmpty
    }
}

/// 채널 변경 정보 DTO
struct ChannelChangeInfo: Sendable {
    let channelId: String
    let channelName: String
    let oldValue: String
    let newValue: String
}

/// 팔로잉 채널 상태를 주기적으로 업데이트하는 서비스
@Observable
@MainActor
final class BackgroundUpdateService {

    // MARK: - State

    /// 팔로잉 중 현재 온라인인 채널들
    private(set) var onlineChannels: [OnlineChannel] = []
    /// 이전 체크에서 온라인이 아니었는데 새로 온라인 된 채널들
    private(set) var newlyOnlineChannels: [OnlineChannel] = []
    /// 마지막 업데이트 시각
    private(set) var lastUpdated: Date?
    /// 업데이트 진행 중
    private(set) var isUpdating = false

    private var updateTask: Task<Void, Never>?
    private var previousOnlineIds: Set<String> = []
    /// 이전 체크 시 채널별 카테고리 맵 (변경 감지용)
    private var previousCategoryMap: [String: String] = [:]
    /// 이전 체크 시 채널별 제목 맵 (변경 감지용)
    private var previousTitleMap: [String: String] = [:]
    private let logger = AppLogger.app
    /// 시스템 슬립 중이면 폴링 일시 중지
    private var isSleeping = false
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?

    // MARK: - Lifecycle

    /// 주기적 업데이트 시작
    func start(
        apiClient: ChzzkAPIClient,
        interval: TimeInterval,
        onEvent: @escaping @MainActor (BackgroundUpdateEvent) -> Void
    ) {
        stop()

        // 슬립/웨이크 알림 구독 — 슬립 중에는 폴링 중단
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isSleeping = true }
        }
        wakeObserver = ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isSleeping = false }
        }

        updateTask = Task { [weak self] in
            // 초기화 직후 부하 방지 — 5초 지연 후 첫 체크
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.performUpdate(apiClient: apiClient, onEvent: onEvent)

            // 주기적 반복
            let timerInterval = max(interval, 30) // 최소 30초
            for await _ in AsyncTimerSequence(interval: .seconds(timerInterval), tolerance: .seconds(timerInterval * 0.15)) {
                guard !Task.isCancelled else { break }
                // 슬립 중이면 건너뜀
                if self?.isSleeping == true { continue }
                await self?.performUpdate(apiClient: apiClient, onEvent: onEvent)
            }
        }

        logger.info("BackgroundUpdateService started (interval: \(interval)s)")
    }

    /// 업데이트 중지
    func stop() {
        updateTask?.cancel()
        updateTask = nil
        if let obs = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = wakeObserver  { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        sleepObserver = nil
        wakeObserver  = nil
        // 이전 상태 초기화 — restart 시 첫 폴링에서 정확한 diff 보장
        previousOnlineIds = []
        previousCategoryMap = [:]
        previousTitleMap = [:]
    }

    /// 수동 새로고침
    func refresh(apiClient: ChzzkAPIClient) async {
        await performUpdate(apiClient: apiClient, onEvent: { _ in })
    }

    // MARK: - Update Logic

    private func performUpdate(
        apiClient: ChzzkAPIClient,
        onEvent: @MainActor (BackgroundUpdateEvent) -> Void
    ) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            let following = try await apiClient.fetchFollowingChannels()
            
            // 이전 상태를 캡처하여 백그라운드에서 diff 계산
            let prevOnlineIds = previousOnlineIds
            let prevCategoryMap = previousCategoryMap
            let prevTitleMap = previousTitleMap

            // 데이터 가공/비교를 백그라운드 스레드에서 수행 — 메인 스레드 차단 방지
            let result = await Task.detached(priority: .utility) {
                let currentOnline = following
                    .filter { $0.isLive }
                    .map { item in
                        OnlineChannel(
                            channelId: item.channelId,
                            channelName: item.channelName,
                            liveTitle: item.liveTitle,
                            viewerCount: item.viewerCount,
                            thumbnailURL: item.thumbnailUrl,
                            categoryName: item.categoryName
                        )
                    }

                let currentOnlineIds = Set(currentOnline.map(\.channelId))

                // 새로 온라인 된 채널 감지
                let newlyOnline = currentOnline.filter { !prevOnlineIds.contains($0.channelId) }

                // 카테고리/제목 변경 감지
                var categoryChanged: [ChannelChangeInfo] = []
                var titleChanged: [ChannelChangeInfo] = []

                for channel in currentOnline {
                    guard prevOnlineIds.contains(channel.channelId) else { continue }

                    if let oldCategory = prevCategoryMap[channel.channelId],
                       let newCategory = channel.categoryName,
                       oldCategory != newCategory {
                        categoryChanged.append(ChannelChangeInfo(
                            channelId: channel.channelId,
                            channelName: channel.channelName,
                            oldValue: oldCategory,
                            newValue: newCategory
                        ))
                    }

                    if let oldTitle = prevTitleMap[channel.channelId],
                       oldTitle != channel.liveTitle,
                       !channel.liveTitle.isEmpty {
                        titleChanged.append(ChannelChangeInfo(
                            channelId: channel.channelId,
                            channelName: channel.channelName,
                            oldValue: oldTitle,
                            newValue: channel.liveTitle
                        ))
                    }
                }

                let newCategoryMap = Dictionary(
                    uniqueKeysWithValues: currentOnline.compactMap { ch in
                        ch.categoryName.map { (ch.channelId, $0) }
                    }
                )
                let newTitleMap = Dictionary(
                    uniqueKeysWithValues: currentOnline.map { ($0.channelId, $0.liveTitle) }
                )

                return (currentOnline, currentOnlineIds, newlyOnline, categoryChanged, titleChanged, newCategoryMap, newTitleMap)
            }.value

            // UI 상태 업데이트는 @MainActor에서만 수행
            let previousIds = Set(onlineChannels.map(\.channelId))
            if result.1 != previousIds {
                onlineChannels = result.0
            }
            if !result.2.isEmpty {
                newlyOnlineChannels = result.2
            }
            previousOnlineIds = result.1
            lastUpdated = .now
            previousCategoryMap = result.5
            previousTitleMap = result.6

            let event = BackgroundUpdateEvent(
                newlyOnline: result.2,
                categoryChanged: result.3,
                titleChanged: result.4
            )

            if event.hasAnyEvent {
                onEvent(event)
            }

            logger.info("Background update: \(result.0.count) online, \(result.2.count) newly online, \(result.3.count) cat changed, \(result.4.count) title changed")
        } catch {
            logger.error("Background update failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Online Channel DTO

struct OnlineChannel: Identifiable, Sendable, Equatable {
    let channelId: String
    let channelName: String
    let liveTitle: String
    let viewerCount: Int
    let thumbnailURL: String?
    let categoryName: String?

    var id: String { channelId }

    var formattedViewerCount: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f만", Double(viewerCount) / 10_000.0)
        }
        return viewerCount.formatted()
    }
}
