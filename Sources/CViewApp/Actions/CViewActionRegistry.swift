// MARK: - CViewActionRegistry.swift
// CViewAction → 실제 사이드 이펙트(Router/AppState 변경)를 수행하는 단일 dispatcher.
//
// 이 타입을 모든 진입점이 공유하면 라우팅 로직 중복이 사라지고,
// 새 진입점을 추가할 때 여기서만 변경한다.
//
// [Plan 2026-04-30 ACT-1]

import Foundation
import SwiftUI
import os.log

@MainActor
final class CViewActionRegistry {

    // MARK: - Dependencies

    private weak var router: AppRouter?
    private weak var appState: AppState?
    private let logger = Logger(subsystem: "com.cview", category: "ActionRegistry")

    // MARK: - Init

    init(router: AppRouter, appState: AppState) {
        self.router = router
        self.appState = appState
    }

    // MARK: - Dispatch

    /// 액션 하나를 실제 라우팅/상태 변경으로 변환한다.
    /// validation에 실패한 액션은 무시된다.
    @discardableResult
    func dispatch(_ raw: CViewAction) -> Bool {
        guard let action = raw.validated else {
            logger.warning("Action 무시 (validation 실패): \(raw.id, privacy: .public)")
            return false
        }
        guard let router, let appState else {
            logger.error("Registry: router/appState 해제됨")
            return false
        }
        logger.info("Action dispatch: \(action.id, privacy: .public)")

        switch action {
        case .openLive(let channelId, let mode):
            applyOpenLive(channelId: channelId, mode: mode, router: router, appState: appState)
        case .openChannel(let channelId):
            router.navigate(to: .channelDetail(channelId: channelId))
        case .addToMultiLive(let channelId):
            applyAddToMultiLive(channelId: channelId, router: router, appState: appState)
        case .addToMultiChat(let channelId):
            applyAddToMultiChat(channelId: channelId, appState: appState)
        case .switchLiveMode(let mode):
            applySwitchLiveMode(mode, router: router, appState: appState)
        case .openSearch(let query):
            router.navigate(to: .search(query: query))
        case .openClip(let clipUID):
            router.navigate(to: .clip(clipUID: clipUID))
        case .openMetrics(let tab):
            router.selectSidebar(.metrics)
            if let tab { appState.pendingMetricsTab = tab }
        case .openHome:
            router.navigate(to: .home)
        }
        return true
    }

    // MARK: - Specialized handlers

    private func applyOpenLive(
        channelId: String,
        mode: LiveOpenMode,
        router: AppRouter,
        appState: AppState
    ) {
        switch mode {
        case .watch:
            router.navigateToWatch(channelId: channelId)
        case .multi:
            // 라이브 메뉴로 진입 후, 비동기로 세션 추가 + 멀티 모드 전환
            router.selectSidebar(.following)
            Task { @MainActor in
                await appState.multiLiveManager.addSession(channelId: channelId)
                appState.followingViewState.applyHubModePreset(.multi, multiLiveManager: appState.multiLiveManager)
            }
        case .chatOnly:
            router.navigate(to: .chatOnly(channelId: channelId))
        }
    }

    private func applyAddToMultiLive(channelId: String, router: AppRouter, appState: AppState) {
        Task { @MainActor in
            await appState.multiLiveManager.addSession(channelId: channelId)
        }
    }

    private func applyAddToMultiChat(channelId: String, appState: AppState) {
        Task { @MainActor in
            // 채팅 세션 추가는 liveDetail + chatAccessToken 조회가 선행되어야 함
            // (FollowingView+MultiChat.addChatChannel 와 동일한 패턴)
            guard let apiClient = appState.apiClient else { return }
            do {
                let liveDetail = try await apiClient.liveDetail(channelId: channelId)
                guard let chatChannelId = liveDetail.chatChannelId else { return }
                let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
                let channelName = liveDetail.channel?.channelName ?? channelId
                let chatUid: String?
                if appState.isLoggedIn,
                   let userInfo = try? await apiClient.userStatus() {
                    chatUid = userInfo.userIdHash ?? appState.userChannelId
                } else {
                    chatUid = appState.userChannelId
                }
                _ = await appState.followingViewState.chatSessionManager.addSession(
                    channelId: channelId,
                    channelName: channelName,
                    chatChannelId: chatChannelId,
                    accessToken: tokenInfo.accessToken,
                    extraToken: tokenInfo.extraToken,
                    uid: chatUid,
                    nickname: appState.userNickname
                )
            } catch {
                logger.error("addToMultiChat 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applySwitchLiveMode(
        _ mode: FollowingHubMode,
        router: AppRouter,
        appState: AppState
    ) {
        router.selectSidebar(.following)
        appState.followingViewState.applyHubModePreset(mode, multiLiveManager: appState.multiLiveManager)
    }
}
