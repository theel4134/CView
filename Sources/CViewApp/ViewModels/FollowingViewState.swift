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

    // MARK: - 팔로잉 리스트

    /// 팔로잉 리스트 표시 여부 (기본 숨김, 왼쪽 슬라이드)
    var showFollowingList: Bool = false

    // MARK: - 멀티라이브 UI

    var showMultiLive: Bool = true
    var showMLSettings: Bool = false
    var showMultiChat: Bool = true

    /// PiP 모드 활성 여부 (비영속 — 멀티라이브 → PiP 자동 전환 시 true)
    var isMultiLivePiPMode: Bool = false

    // MARK: - 멀티채팅
    let chatSessionManager = MultiChatSessionManager()
    var showChatAddChannel: Bool = false
    var showChatSettings: Bool = false

    // MARK: - 듀얼 패널 비율 [Removed 2026-04: dualSplitRatio dead — 사용처 없음]

    /// 팔로잉 리스트 : 사이드 패널 고정 비율 (패널 열림 시)
    static let followingListRatio: CGFloat = 0.25

    // MARK: - 오프라인 섹션

    /// 오프라인 채널 섹션 펼침 여부 (기본 접힘)
    var isOfflineSectionExpanded: Bool = false

    init() {}
}
