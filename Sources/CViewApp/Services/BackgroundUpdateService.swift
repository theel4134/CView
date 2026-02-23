// MARK: - BackgroundUpdateService.swift
// CViewApp - 백그라운드 팔로잉 상태 업데이트 서비스

import Foundation
import AppKit       // NSWorkspace sleep/wake 알림
import CViewCore
import CViewNetworking

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
        onNewOnline: @escaping @MainActor ([OnlineChannel]) -> Void
    ) {
        stop()

        // 슬립/웨이크 알림 구독 — 슬립 중에는 폴링 중단
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSleeping = true
        }
        wakeObserver = ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSleeping = false
        }

        updateTask = Task { [weak self] in
            // 초기화 직후 부하 방지 — 5초 지연 후 첫 체크
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.performUpdate(apiClient: apiClient, onNewOnline: onNewOnline)

            // 주기적 반복
            let timerInterval = max(interval, 30) // 최소 30초
            for await _ in AsyncTimerSequence(interval: .seconds(timerInterval), tolerance: .seconds(timerInterval * 0.15)) {
                guard !Task.isCancelled else { break }
                // 슬립 중이면 건너뜀
                if await self?.isSleeping == true { continue }
                await self?.performUpdate(apiClient: apiClient, onNewOnline: onNewOnline)
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
    }

    /// 수동 새로고침
    func refresh(apiClient: ChzzkAPIClient) async {
        await performUpdate(apiClient: apiClient, onNewOnline: { _ in })
    }

    // MARK: - Update Logic

    private func performUpdate(
        apiClient: ChzzkAPIClient,
        onNewOnline: @MainActor ([OnlineChannel]) -> Void
    ) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            let following = try await apiClient.fetchFollowingChannels()

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

            // Equality 체크 — 동일 목록 할당으로 인한 @Observable 재평가 방지
            let currentOnlineIds = Set(currentOnline.map(\.channelId))
            let previousIds = Set(onlineChannels.map(\.channelId))

            // 새로 온라인 된 채널 감지
            let newlyOnline = currentOnline.filter { !previousOnlineIds.contains($0.channelId) }

            if currentOnlineIds != previousIds {
                onlineChannels = currentOnline
            }
            if !newlyOnline.isEmpty {
                newlyOnlineChannels = newlyOnline
            }
            previousOnlineIds = currentOnlineIds
            lastUpdated = .now

            if !newlyOnline.isEmpty {
                onNewOnline(newlyOnline)
            }

            logger.info("Background update: \(currentOnline.count) online, \(newlyOnline.count) newly online")
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
