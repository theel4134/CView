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
    case multiChat
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
        case .multiChat: "multiChat"
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
    
    /// Sheet presentation
    public var presentedSheet: SheetRoute?
    
    /// Alert state
    public var alertState: AlertState?
    
    // MARK: - Sidebar Items
    
    public enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "홈"
        case following = "팔로잉"
        case category = "카테고리"
        case search = "검색"
        case clips = "클립"
        case multiChat = "멀티채팅"
        case multiLive = "멀티라이브"
        case recentFavorites = "최근/즐겨찾기"
        case settings = "설정"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .home: "house.fill"
            case .following: "heart.fill"
            case .category: "square.grid.2x2.fill"
            case .search: "magnifyingglass"
            case .clips: "film.stack"
            case .multiChat: "bubble.left.and.bubble.right.fill"
            case .multiLive: "rectangle.split.2x2.fill"
            case .recentFavorites: "clock.arrow.circlepath"
            case .settings: "gearshape.fill"
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
    
    public init() {}
    
    // MARK: - Navigation Actions
    
    public func navigate(to route: AppRoute) {
        switch route {
        case .following:    selectSidebar(.following)
        case .home:         selectSidebar(.home)
        case .search:       selectSidebar(.search)
        case .popularClips: selectSidebar(.clips)
        case .multiChat:    selectSidebar(.multiChat)
        case .multiLive:    selectSidebar(.multiLive)
        case .settings:     selectSidebar(.settings)
        default:            path.append(route)
        }
    }
    
    public func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
    
    public func navigateToRoot() {
        path = NavigationPath()
    }
    
    public func selectSidebar(_ item: SidebarItem) {
        withAnimation(DesignTokens.Animation.contentTransition) {
            selectedSidebarItem = item
        }
        if !path.isEmpty {
            path = NavigationPath()
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
