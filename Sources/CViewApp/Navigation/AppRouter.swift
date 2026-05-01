// MARK: - AppRouter.swift
// CViewApp - Navigation and routing
// 원본: NavigationManager → 개선: SwiftUI NavigationStack-native 라우팅

import SwiftUI
import CViewCore

// MARK: - App Route

/// Type-safe navigation destinations
public enum AppRoute: Hashable, Identifiable {
    case home
    case live(channelId: String)
    case search(query: String?)
    case following
    case settings
    case channelDetail(channelId: String)
    case chatOnly(channelId: String)
    case vod(videoNo: Int)
    case clip(clipUID: String)
    case popularClips
    case multiLive
    
    public var id: String {
        switch self {
        case .home: "home"
        case .live(let id): "live-\(id)"
        case .search(let q): "search-\(q ?? "")"
        case .following: "following"
        case .settings: "settings"
        case .channelDetail(let id): "channel-\(id)"
        case .chatOnly(let id): "chat-\(id)"
        case .vod(let no): "vod-\(no)"
        case .clip(let uid): "clip-\(uid)"
        case .popularClips: "popularClips"
        case .multiLive: "multiLive"
        }
    }
}

// MARK: - App Router

/// Manages navigation state for the application.
@Observable
public final class AppRouter {
    
    // MARK: - Properties
    
    /// Current navigation path
    public var path: NavigationPath = NavigationPath()
    
    /// Selected sidebar item
    public var selectedSidebarItem: SidebarItem = .home
    
    /// Settings mode — sidebar slides to show settings tabs
    public var isInSettingsMode: Bool = false

    /// Selected settings group (when in settings mode)
    /// [Redesign 2026-04-29] 7개 탭(SettingsTab) → 6개 작업 중심 그룹(SettingsGroup)
    public var selectedSettingsGroup: SettingsGroup = .overview

    /// Previous sidebar item before entering settings (for back navigation)
    private var previousSidebarItem: SidebarItem = .home
    
    /// Sheet presentation
    public var presentedSheet: SheetRoute?
    
    /// Alert state
    public var alertState: AlertState?

    /// [Redesign 2026-04-29] 검색 메뉴로 query를 들고 진입하기 위한 pending query.
    /// `navigate(to: .search(query:))` 호출 시 설정되며, `SearchView`가 소비 후 nil로 비운다.
    public var pendingSearchQuery: String?

    /// [2026-04-30] 라이브(팔로잉) 메뉴 시청 탭으로 채널을 들고 진입하기 위한 pending channelId.
    /// `navigateToWatch(channelId:)` 호출 시 설정되며, `FollowingView`가 소비 후 nil로 비운다.
    public var pendingWatchChannelId: String?
    
    // MARK: - Sidebar Items
    
    public enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "홈"
        case following = "라이브"
        case category = "카테고리"
        case search = "검색"
        case clips = "클립"
        case recentFavorites = "최근/즐겨찾기"
        case metrics = "메트릭"
        case settings = "설정"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .home: "house.fill"
            case .following: "heart.fill"
            case .category: "square.grid.2x2.fill"
            case .search: "magnifyingglass"
            case .clips: "film.stack"
            case .recentFavorites: "clock.arrow.circlepath"
            case .metrics: "chart.bar.xaxis"
            case .settings: "gearshape.fill"
            }
        }
    }
    
    // MARK: - Settings Group (Redesign 2026-04-29)

    /// 작업 중심으로 재구성된 6개 설정 그룹
    /// 매핑: overview ⊃ general/appearance, viewing ⊃ player/latency,
    ///       chat ⊃ chat/multiChat, multi ⊃ multiLive,
    ///       integration ⊃ network/metrics, advanced ⊃ performance/cache/keyboard
    public enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
        case overview     = "개요"
        case viewing      = "시청"
        case chat         = "채팅"
        case multi        = "멀티"
        case integration  = "연동"
        case advanced     = "고급"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .overview:     "square.grid.2x2"
            case .viewing:      "play.rectangle.fill"
            case .chat:         "bubble.left.and.bubble.right.fill"
            case .multi:        "rectangle.split.2x2.fill"
            case .integration:  "network"
            case .advanced:     "wrench.and.screwdriver.fill"
            }
        }

        public var color: Color {
            switch self {
            case .overview:     .gray
            case .viewing:      .green
            case .chat:         .purple
            case .multi:        .blue
            case .integration:  .cyan
            case .advanced:     .orange
            }
        }

        public var subtitle: String {
            switch self {
            case .overview:     "검색·자주 쓰는 설정·현재 상태"
            case .viewing:      "재생·화질·레이턴시·스크린샷"
            case .chat:         "패널·표시·TTS·필터"
            case .multi:        "세션·프로세스·대역폭"
            case .integration:  "네트워크·메트릭·App Secret"
            case .advanced:     "성능·디버그·캐시·초기화"
            }
        }
    }

    // MARK: - Sheet Routes
    
    public enum SheetRoute: Identifiable {
        case login
        case channelInfo(channelId: String)
        case qualitySelector
        case chatSettings
        
        public var id: String {
            switch self {
            case .login: "login"
            case .channelInfo(let id): "channelInfo-\(id)"
            case .qualitySelector: "qualitySelector"
            case .chatSettings: "chatSettings"
            }
        }
    }
    
    // MARK: - Alert State
    
    public struct AlertState: Identifiable {
        public let id = UUID()
        public let title: String
        public let message: String
        public let primaryAction: AlertAction?
        public let secondaryAction: AlertAction?
        
        public struct AlertAction {
            public let title: String
            public let role: ButtonRole?
            public let action: () -> Void
            
            public init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
                self.title = title
                self.role = role
                self.action = action
            }
        }
        
        public init(title: String, message: String, primaryAction: AlertAction? = nil, secondaryAction: AlertAction? = nil) {
            self.title = title
            self.message = message
            self.primaryAction = primaryAction
            self.secondaryAction = secondaryAction
        }
    }
    
    // MARK: - Initialization
    
    public init() {
        // [Fix A-2] 마지막 사이드바 탭 복원
        if let raw = UserDefaults.standard.string(forKey: "AppRouter.lastSidebarItem"),
           let item = SidebarItem(rawValue: raw) {
            selectedSidebarItem = item
        }
    }
    
    // MARK: - Navigation Actions
    
    public func navigate(to route: AppRoute) {
        switch route {
        case .following:    selectSidebar(.following)
        case .home:         selectSidebar(.home)
        case .search(let query):
            if let q = query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
                pendingSearchQuery = q
            }
            selectSidebar(.search)
        case .popularClips: selectSidebar(.clips)
        case .multiLive:    selectSidebar(.following)  // 팔로잉에 통합됨
        case .settings:     selectSidebar(.settings)
        default:            path.append(route)
        }
    }
    
    public func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// [2026-04-30] 카테고리 등에서 채널 썸네일을 누를 때 라이브(팔로잉) 메뉴 시청 탭에서
    /// 즉시 재생되도록 라우팅한다. `pendingWatchChannelId` 를 설정하면 `FollowingView` 가
    /// `multiLiveManager.addSession` + `applyHubModePreset(.watch)` 를 수행하고 nil 로 비운다.
    public func navigateToWatch(channelId: String) {
        let trimmed = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingWatchChannelId = trimmed
        selectSidebar(.following)
    }
    
    public func navigateToRoot() {
        path = NavigationPath()
    }
    
    public func selectSidebar(_ item: SidebarItem) {
        if item == .settings {
            enterSettings()
        } else {
            isInSettingsMode = false
            selectedSidebarItem = item
            UserDefaults.standard.set(item.rawValue, forKey: "AppRouter.lastSidebarItem")
            if !path.isEmpty {
                path = NavigationPath()
            }
        }
    }
    
    /// Enter settings mode with slide animation
    public func enterSettings() {
        if selectedSidebarItem != .settings {
            previousSidebarItem = selectedSidebarItem
        }
        selectedSidebarItem = .settings
        UserDefaults.standard.set(SidebarItem.settings.rawValue, forKey: "AppRouter.lastSidebarItem")
        isInSettingsMode = true
        if !path.isEmpty {
            path = NavigationPath()
        }
    }
    
    /// Exit settings mode, return to previous sidebar item
    public func exitSettings() {
        isInSettingsMode = false
        selectedSidebarItem = previousSidebarItem
        UserDefaults.standard.set(previousSidebarItem.rawValue, forKey: "AppRouter.lastSidebarItem")
        if !path.isEmpty {
            path = NavigationPath()
        }
    }
    
    /// Select a settings group (within settings mode)
    public func selectSettingsGroup(_ group: SettingsGroup) {
        selectedSettingsGroup = group
        if !isInSettingsMode {
            enterSettings()
        }
    }
    
    // MARK: - Sheet Actions
    
    public func presentSheet(_ sheet: SheetRoute) {
        presentedSheet = sheet
    }
    
    public func dismissSheet() {
        presentedSheet = nil
    }
    
    // MARK: - Alert Actions
    
    public func showAlert(title: String, message: String) {
        alertState = AlertState(title: title, message: message)
    }
    
    public func showConfirmAlert(
        title: String,
        message: String,
        confirmTitle: String = "확인",
        onConfirm: @escaping () -> Void
    ) {
        alertState = AlertState(
            title: title,
            message: message,
            primaryAction: .init(title: confirmTitle, action: onConfirm),
            secondaryAction: .init(title: "취소", role: .cancel)
        )
    }
    
    public func dismissAlert() {
        alertState = nil
    }
}
