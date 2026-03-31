// MARK: - FollowingViewState.swift
// CViewApp — 라이브 메뉴(FollowingView) 상태 보존 모델
// 다른 메뉴로 이동 후 복귀 시 상태가 초기화되지 않도록 AppState에서 관리

import SwiftUI

/// 라이브 메뉴의 영속 상태 — AppState에 보관되어 뷰 재생성에도 유지됨
@Observable
@MainActor
final class FollowingViewState {

    // MARK: - 정렬/필터

    var sortOrder: FollowingSortOrder = .liveFirst
    var filterLiveOnly: Bool = false
    var selectedCategory: String? = nil

    // MARK: - 페이징

    var livePageIndex: Int = 0
    var offlinePageIndex: Int = 0

    // MARK: - 멀티라이브 UI

    var showMultiLive: Bool = false
    var showMLAddChannel: Bool = false
    var showMLSettings: Bool = false
    var mlPanelWidth: CGFloat = 560
    var hideFollowingList: Bool = false
    var followingListWidth: CGFloat = 480

    // MARK: - 멀티채팅

    var showMultiChat: Bool = false
    let chatSessionManager = MultiChatSessionManager()
    var showChatAddChannel: Bool = false
    var showChatSettings: Bool = false

    // MARK: - 듀얼 패널 분할

    var dualPanelSplitRatio: CGFloat = 0.6
}
