// MARK: - FollowingViewState.swift
// CViewApp — 라이브 메뉴(FollowingView) 상태 보존 모델
// 다른 메뉴로 이동 후 복귀 시 상태가 초기화되지 않도록 AppState에서 관리

import SwiftUI

enum FollowingHubMode: String, CaseIterable, Sendable, Codable {
    case explore = "탐색"
    case watch = "시청"
    case multi = "멀티"

    var icon: String {
        switch self {
        case .explore: return "safari"
        case .watch: return "play.rectangle"
        case .multi: return "square.grid.2x2"
        }
    }
}

// [Removed 2026-04-28] LiveHubLayoutPreset / LiveHubControlRoomPreset / LiveHubFloatingAutoHideDelay
// — Native Inspector / Floating Palette / Control Room 프리셋 디자인 폐기.
// 라이브 메뉴는 단일 디자인 (Top Mode Bar + Stage + Right Chat Dock + Bottom Following Sheet)으로 통합됨.
// 참고: docs/live-menu-final-overview-following-redesign-2026-04-27.md

enum LiveWorkspaceWidthClass: String, CaseIterable {
    case wide
    case regular
    case compact

    static func from(width: CGFloat) -> LiveWorkspaceWidthClass {
        if width >= 1280 { return .wide }
        if width >= 1000 { return .regular }
        return .compact
    }
}

/// 스테이지 우상단 Tool Popover 활성 종류 (비영속 — 멀티/싱글 공용)
enum StageToolPopover: String, CaseIterable {
    case none
    case quality
    case tools
    case network
    case metrics
    case layout      // [2026-04-28] 디자인 사료 §2 — 그리드 레이아웃 변경
    case reconnect   // [2026-04-28] 디자인 사료 §2 — 세션 재연결
}

// MARK: - 2026-04-27 최종 리디자인 모델
//
// docs/live-menu-final-overview-following-redesign-2026-04-27.md
// "탐색 첫 화면은 팔로잉 종합 정보, 팔로잉 목록은 하단에서 올라오는 예쁜 live deck, 우측은 채팅 전용."

/// 하단 팔로잉 시트 상태 (collapsed → peek → expanded)
enum FollowingSheetState: String, CaseIterable {
    case collapsed
    case peek
    case expanded

    var next: FollowingSheetState {
        switch self {
        case .collapsed: return .peek
        case .peek: return .expanded
        case .expanded: return .collapsed
        }
    }
}

/// 우측 채팅 도크 포커스 (멀티/싱글 비율)
enum ChatDockFocus: String, CaseIterable {
    case balanced   // 50/50
    case single     // 35/65 — 싱글 채팅 강조
    case multi      // 70/30 — 멀티 채팅 강조
}

/// 팔로잉 표시 모드 (시트 expanded 상태에서)
enum FollowingDisplayMode: String, CaseIterable {
    case spotlight   // 추천 + rail
    case rail        // 가로 mini cards만
    case dense       // 한 줄짜리 dense rows

    var icon: String {
        switch self {
        case .spotlight: return "sparkles.rectangle.stack"
        case .rail: return "rectangle.split.3x1"
        case .dense: return "list.bullet"
        }
    }

    var title: String {
        switch self {
        case .spotlight: return "스포트라이트"
        case .rail: return "Rail"
        case .dense: return "Dense"
        }
    }
}

/// 팔로잉 시트 필터 (전체/라이브/즐겨찾기/최근/카테고리)
enum FollowingSheetFilter: String, CaseIterable {
    case all
    case live
    case favorites
    case recent

    var title: String {
        switch self {
        case .all: return "전체"
        case .live: return "라이브"
        case .favorites: return "즐겨찾기"
        case .recent: return "최근"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .live: return "antenna.radiowaves.left.and.right"
        case .favorites: return "star.fill"
        case .recent: return "clock"
        }
    }
}

/// 라이브 메뉴의 영속 상태 — AppState에 보관되어 뷰 재생성에도 유지됨
@Observable
@MainActor
final class FollowingViewState {

    private enum DefaultsKey {
        static let autoSyncChatOnMultiLiveAdd = "following.liveHub.autoSyncChatOnMultiLiveAdd"
        // 2026-04-27 redesign
        static let hubMode = "following.liveHub.hubMode"
        static let sheetState = "following.liveHub.sheetState"
        static let chatDockFocus = "following.liveHub.chatDockFocus"
        static let followingDisplayMode = "following.liveHub.followingDisplayMode"
        static let sheetFilter = "following.liveHub.sheetFilter"
        // [2026-04-28] 라이브 메뉴 단일 디자인 마이그레이션
        // 값이 일치하지 않으면 영속 모드/시트 상태를 explore/peek 로 리셋한다.
        static let redesignMigration = "following.liveHub.redesignMigration"
        static let redesignMigrationCurrent = "2026-04-28-unified"
    }

    private let defaults: UserDefaults

    // MARK: - 정렬/필터

    var sortOrder: FollowingSortOrder = .liveFirst
    var filterLiveOnly: Bool = false
    var selectedCategory: String? = nil
    /// 라이브 메뉴 상단 모드 — 첫 진입은 `.explore` (탐색 = 팔로잉 종합 정보)
    var hubMode: FollowingHubMode = .explore {
        didSet { defaults.set(hubMode.rawValue, forKey: DefaultsKey.hubMode) }
    }

    // MARK: - 2026-04-27 최종 리디자인 상태

    /// 하단 팔로잉 시트 상태 (collapsed → peek → expanded)
    var followingSheetState: FollowingSheetState = .peek {
        didSet { defaults.set(followingSheetState.rawValue, forKey: DefaultsKey.sheetState) }
    }
    /// 우측 채팅 도크 포커스 비율
    var chatDockFocus: ChatDockFocus = .balanced {
        didSet { defaults.set(chatDockFocus.rawValue, forKey: DefaultsKey.chatDockFocus) }
    }
    /// 시트 expanded 상태에서 팔로잉 표시 방식
    var followingDisplayMode: FollowingDisplayMode = .spotlight {
        didSet { defaults.set(followingDisplayMode.rawValue, forKey: DefaultsKey.followingDisplayMode) }
    }
    /// 시트 필터 (전체/라이브/즐겨찾기/최근)
    var sheetFilter: FollowingSheetFilter = .all {
        didSet { defaults.set(sheetFilter.rawValue, forKey: DefaultsKey.sheetFilter) }
    }

    // MARK: - 페이징

    var livePageIndex: Int = 0
    var offlinePageIndex: Int = 0

    // MARK: - 멀티라이브 UI

    var showMultiLive: Bool = true
    var showMultiChat: Bool = false

    /// 스테이지 Tool Popover (비영속 — 화질/도구/네트워크/메트릭)
    var stageToolPopover: StageToolPopover = .none

    /// 멀티라이브 세션 추가 시 멀티채팅 자동 동기화 정책
    var autoSyncChatOnMultiLiveAdd: Bool = true {
        didSet { defaults.set(autoSyncChatOnMultiLiveAdd, forKey: DefaultsKey.autoSyncChatOnMultiLiveAdd) }
    }

    /// Smart Queue (세션 후보) — 영속 상태가 아닌 작업 단위 상태
    var smartQueueChannelIds: [String] = []

    /// [2026-04-28] 시트 필터(즐겨찾기/최근)를 위한 캐시된 채널 ID 셋.
    /// DataStore에서 주기적으로 로드됨 (FollowingView.task).
    var favoriteChannelIds: Set<String> = []
    /// 최근 시청 채널 ID — 최근 순서 보존 배열.
    var recentChannelIds: [String] = []

    /// PiP 모드 활성 여부 (비영속 — 멀티라이브 → PiP 자동 전환 시 true)
    var isMultiLivePiPMode: Bool = false

    /// 시청 모드에서 팔로잉 시트 강제 숨기기 (그리드/멀티라이브 모드용 on/off 토글)
    /// 비영속 — 세션 간에는 리셋됨. 싱글 시청 모드는 이 값과 무관하게 항상 숨김.
    var isFollowingSheetHidden: Bool = false

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // [2026-04-28] 단일 디자인 마이그레이션 — 이전 세션의 hubMode 등을 1회 리셋
        let migration = defaults.string(forKey: DefaultsKey.redesignMigration)
        if migration != DefaultsKey.redesignMigrationCurrent {
            defaults.removeObject(forKey: DefaultsKey.hubMode)
            defaults.removeObject(forKey: DefaultsKey.sheetState)
            defaults.removeObject(forKey: DefaultsKey.chatDockFocus)
            defaults.removeObject(forKey: DefaultsKey.followingDisplayMode)
            defaults.removeObject(forKey: DefaultsKey.sheetFilter)
            defaults.set(DefaultsKey.redesignMigrationCurrent, forKey: DefaultsKey.redesignMigration)
        }

        if defaults.object(forKey: DefaultsKey.autoSyncChatOnMultiLiveAdd) != nil {
            autoSyncChatOnMultiLiveAdd = defaults.bool(forKey: DefaultsKey.autoSyncChatOnMultiLiveAdd)
        }
        // hubMode / sheetState 는 의도적으로 복원하지 않는다.
        // 디자인 규칙: 앱 재시작 시 항상 탐색(explore) + peek 으로 시작.
        // (세션 내 모드 전환은 in-memory ps 를 통해 유지됨)
        if let raw = defaults.string(forKey: DefaultsKey.chatDockFocus),
           let saved = ChatDockFocus(rawValue: raw) {
            chatDockFocus = saved
        }
        if let raw = defaults.string(forKey: DefaultsKey.followingDisplayMode),
           let saved = FollowingDisplayMode(rawValue: raw) {
            followingDisplayMode = saved
        }
        if let raw = defaults.string(forKey: DefaultsKey.sheetFilter),
           let saved = FollowingSheetFilter(rawValue: raw) {
            sheetFilter = saved
        }
    }

    // MARK: - Mode Preset (2026-04-28 통합)

    /// 모든 모드 전환 진입점이 호출해야 하는 단일 함수.
    /// hubMode/chatDockFocus/sheetState/필터/정렬/그리드 레이아웃을 일괄 동기화한다.
    func applyHubModePreset(_ mode: FollowingHubMode, multiLiveManager: MultiLiveManager) {
        hubMode = mode
        switch mode {
        case .explore:
            chatDockFocus = .balanced
            followingSheetState = .peek
            filterLiveOnly = false
            sortOrder = .liveFirst
            multiLiveManager.isGridLayout = false
            showMultiLive = false
        case .watch:
            chatDockFocus = .single
            followingSheetState = .collapsed
            filterLiveOnly = true
            sortOrder = .liveFirst
            multiLiveManager.isGridLayout = false
            showMultiLive = true
        case .multi:
            chatDockFocus = .multi
            followingSheetState = .peek
            filterLiveOnly = true
            sortOrder = .viewers
            multiLiveManager.isGridLayout = true
            showMultiLive = true
        }
    }
}
