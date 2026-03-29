// MARK: - MainContentView.swift
// CViewApp - Main content view with Dark Glass sidebar
// Design: Translucent sidebar + 4-layer surface stack + chzzk green accent

import SwiftUI
import CViewCore
import CViewPlayer
import CViewAuth
import CViewNetworking
import CViewUI

// MARK: - Main Content View

struct MainContentView: View {
    
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var showSplash = true

    var body: some View {
        @Bindable var router = router

        ZStack {
            mainContent(router: router)

            if showSplash {
                SplashView {
                    withAnimation(DesignTokens.Animation.smooth) {
                        showSplash = false
                    }
                }
                .zIndex(10)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .preferredColorScheme(appState.settingsStore.appearance.theme.colorScheme)
        .commandPaletteOverlay(isPresented: Binding(
            get: { appState.showCommandPalette },
            set: { appState.showCommandPalette = $0 }
        ))
    }

    @ViewBuilder
    private func mainContent(router: AppRouter) -> some View {
        @Bindable var router = router

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            NavigationStack(path: $router.path) {
                detailView
                    .id(router.selectedSidebarItem)
                    .transition(.opacity.combined(with: .scale(scale: 0.995, anchor: .top)))
                    .animation(DesignTokens.Animation.contentTransition, value: router.selectedSidebarItem)
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(for: route)
                    }
            }
            .clipped()
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $router.presentedSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        switch router.selectedSidebarItem {
        case .home:
            if let vm = appState.homeViewModel {
                HomeView(viewModel: vm)
            } else {
                ProgressView()
            }
            
        case .following:
            if let vm = appState.homeViewModel {
                FollowingView(viewModel: vm)
            } else {
                ProgressView()
            }
            
        case .category:
            if let vm = appState.homeViewModel {
                CategoryBrowseView(viewModel: vm)
            } else {
                ProgressView()
            }
            
        case .search:
            SearchView()
            
        case .clips:
            PopularClipsView()
            
        case .recentFavorites:
            RecentFavoritesView()
            
        case .metrics:
            if let vm = appState.homeViewModel {
                MetricsDashboardView(viewModel: vm)
            } else {
                ProgressView()
            }
            
        case .settings:
            SettingsView()
        }
    }
    
    // MARK: - Route Destinations
    
    @ViewBuilder
    private func routeDestination(for route: AppRoute) -> some View {
        switch route {
        case .home:
            if let vm = appState.homeViewModel {
                HomeView(viewModel: vm)
            } else {
                ProgressView()
            }
        case .live(let channelId):
            LiveStreamView(channelId: channelId)
        case .search:
            SearchView()
        case .following:
            if let vm = appState.homeViewModel {
                FollowingView(viewModel: vm)
            } else {
                ProgressView()
            }
        case .channelDetail(let channelId):
            ChannelInfoView(channelId: channelId)
        case .chatOnly(let channelId):
            ChatOnlyView(channelId: channelId)
        case .vod(let videoNo):
            if let apiClient = appState.apiClient {
                VODPlayerView(videoNo: videoNo, apiClient: apiClient)
            } else {
                Text("API Client not initialized")
            }
        case .clip(let clipUID):
            ClipLookupView(clipUID: clipUID)
        case .popularClips:
            PopularClipsView()
        case .multiLive:
            // 팔로잉에 통합됨 — 라우트 호환성 유지
            if let vm = appState.homeViewModel {
                FollowingView(viewModel: vm)
            } else {
                ProgressView()
            }
        case .settings:
            SettingsView()
        }
    }
    
    // MARK: - Sheet Content
    
    @ViewBuilder
    private func sheetContent(for sheet: AppRouter.SheetRoute) -> some View {
        switch sheet {
        case .login:
            LoginView()
        case .channelInfo(let channelId):
            ChannelInfoView(channelId: channelId)
        case .qualitySelector:
            QualitySelectorView()
        case .chatSettings:
            ChatSettingsView()
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {

    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLogoutHovered = false
    @State private var isLoginHovered = false

    private let primaryItems: [AppRouter.SidebarItem] = [.home, .following, .category]
    private let discoverItems: [AppRouter.SidebarItem] = [.search, .clips, .recentFavorites]

    var body: some View {
        @Bindable var router = router

        VStack(spacing: 0) {
            // 앱 헤더
            sidebarHeader

            Divider()

            // 네비게이션 목록
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarSection(title: nil, items: primaryItems)
                    sidebarSection(title: "탐색", items: discoverItems)
                    sidebarSection(title: "기타", items: [.settings])
                }
                .padding(.vertical, 8)
            }

            Divider()

            // 계정 풋터
            accountFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - App Header

    private var sidebarHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm + 2) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text("CView")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text("치지직 뷰어")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 14)
    }

    // MARK: - Section

    @ViewBuilder
    private func sidebarSection(title: String?, items: [AppRouter.SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .padding(.horizontal, DesignTokens.Spacing.lg + 2)
                    .padding(.top, DesignTokens.Spacing.lg + 2)
                    .padding(.bottom, DesignTokens.Spacing.xs)
            }

            ForEach(items) { item in
                sidebarRow(item)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func sidebarRow(_ item: AppRouter.SidebarItem) -> some View {
        let isSelected = router.selectedSidebarItem == item
        let liveCount = item == .following ? appState.backgroundUpdateService.onlineChannels.count : 0

        Button {
            router.selectSidebar(item)
        } label: {
            HStack(spacing: 11) {
                // 아이콘 배경
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(isSelected ? (colorScheme == .light ? iconColor(for: item).opacity(0.15) : Color.accentColor) : iconBackground(for: item))
                        .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? (colorScheme == .light ? iconColor(for: item) : .white) : iconColor(for: item))
                }
                .shadow(color: isSelected ? Color.accentColor.opacity(colorScheme == .light ? 0.15 : 0.28) : .clear, radius: 5, y: 2)

                // 레이블
                Text(item.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color(nsColor: .secondaryLabelColor))
                    .tracking(0.1)

                Spacer()

                // 라이브 뱃지
                if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.live, in: Capsule())
                        .shadow(color: DesignTokens.Colors.live.opacity(0.4), radius: 4, y: 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }

    // MARK: - Icon Styling

    private func iconBackground(for item: AppRouter.SidebarItem) -> Color {
        let opacity = colorScheme == .light ? 0.18 : 0.15
        switch item {
        case .home:             return Color.orange.opacity(opacity)
        case .following:        return Color.pink.opacity(opacity)
        case .category:         return Color.purple.opacity(opacity)
        case .search:           return Color.blue.opacity(opacity)
        case .clips:            return Color.indigo.opacity(opacity)
        case .recentFavorites:  return Color.teal.opacity(opacity)
        case .metrics:          return Color.mint.opacity(opacity)
        case .settings:         return Color.gray.opacity(opacity)
        }
    }

    private func iconColor(for item: AppRouter.SidebarItem) -> Color {
        switch item {
        case .home:             return .orange
        case .following:        return .pink
        case .category:         return .purple
        case .search:           return .blue
        case .clips:            return .indigo
        case .recentFavorites:  return .teal
        case .metrics:          return .mint
        case .settings:         return .gray
        }
    }

    // MARK: - Account Footer

    private var accountFooter: some View {
        Group {
            if appState.isLoggedIn {
                loggedInFooter
            } else {
                loggedOutFooter
            }
        }
        .background(.bar)
    }

    private var loggedInFooter: some View {
        HStack(spacing: 10) {
            avatarImage(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.userNickname ?? "사용자")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let liveCount = appState.backgroundUpdateService.onlineChannels.count
                HStack(spacing: 4) {
                    if liveCount > 0 {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 6, height: 6)
                        Text("\(liveCount)채널 라이브")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.live)
                    } else {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("온라인")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button {
                Task { await appState.handleLogout() }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(isLogoutHovered ? .secondary : .tertiary)
                    .frame(width: 28, height: 28)
                    .background(isLogoutHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary), in: RoundedRectangle(cornerRadius: 6))
                    .scaleEffect(isLogoutHovered ? 1.06 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: isLogoutHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isLogoutHovered = hovering }
            .help("로그아웃")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var loggedOutFooter: some View {
        Button {
            router.presentSheet(.login)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(Color.accentColor.opacity(isLoginHovered ? 0.18 : 0.12))
                        .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
                Text("로그인")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isLoginHovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm + 2)
            .background {
                if isLoginHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(.fill.quaternary)
                }
            }
            .animation(DesignTokens.Animation.fast, value: isLoginHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isLoginHovered = hovering }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func avatarImage(size: CGFloat) -> some View {
        Group {
            if let url = appState.userProfileURL {
                CachedAsyncImage(url: url) { avatarPlaceholder(size: size) }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                avatarPlaceholder(size: size)
            }
        }
    }

    private func avatarPlaceholder(size: CGFloat) -> some View {
        Circle()
            .fill(DesignTokens.Colors.textTertiary.opacity(0.3))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            }
    }
}


