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
        .commandPaletteOverlay(isPresented: Binding(
            get: { appState.showCommandPalette },
            set: { appState.showCommandPalette = $0 }
        ))
        .sheet(isPresented: Binding(
            get: { appState.showKeyboardShortcutsHelp },
            set: { appState.showKeyboardShortcutsHelp = $0 }
        )) {
            KeyboardShortcutsHelpView()
        }
        .sheet(isPresented: Binding(
            get: { appState.showAboutPanel },
            set: { appState.showAboutPanel = $0 }
        )) {
            AboutPanelView()
        }
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
                    .navigationDestination(for: AppRoute.self) { route in
                        routeDestination(for: route)
                    }
                    // [2026-04-22] detail 상단 safe area 무시 — NavigationStack이 기본
                    // 상단 영역을 예약해 MLTabBar 위에 빈 공백이 보였음. ignoresSafeArea
                    // 로 최상단까지 확장 → 탭바가 윈도우 top edge 에 붙음.
                    // SidebarView 는 macOS 트래픽 라이트가 그 위에 그려지도록 safe area 유지.
                    .ignoresSafeArea(.container, edges: .top)
            }
            .clipped()
            .ignoresSafeArea(.container, edges: .top)
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
            SettingsContentView()
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
    @State private var isSettingsBackHovered = false
    @State private var hoveredItem: AppRouter.SidebarItem?
    @State private var hoveredSettingsTab: AppRouter.SettingsTab?
    @Namespace private var sidebarNS
    @Namespace private var settingsNS

    private let primaryItems: [AppRouter.SidebarItem] = [.home, .following, .category]
    private let discoverItems: [AppRouter.SidebarItem] = [.search, .clips, .recentFavorites]

    var body: some View {
        @Bindable var router = router

        VStack(spacing: 0) {
            // 앱 헤더 (변하지 않음)
            sidebarHeader

            Divider()

            // 슬라이드 전환: 메인 메뉴 ↔ 설정 메뉴
            ZStack {
                if router.isInSettingsMode {
                    settingsSidebarContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                } else {
                    mainSidebarContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .move(edge: .leading)
                        ))
                }
            }
            .clipped()
            .animation(DesignTokens.Animation.smooth, value: router.isInSettingsMode)

            Divider()

            // 계정 풋터
            accountFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Main Sidebar Content

    private var mainSidebarContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sidebarSection(title: nil, items: primaryItems)
                sidebarSection(title: "탐색", items: discoverItems)
                sidebarSection(title: "도구", items: [.metrics])
                sidebarSection(title: nil, items: [.settings])
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Settings Sidebar Content

    private var settingsSidebarContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 뒤로가기 버튼
                settingsBackButton
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                // 설정 섹션 헤더
                Text("설정")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.lg + 2)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .padding(.bottom, DesignTokens.Spacing.xs)

                // 설정 탭 목록
                ForEach(AppRouter.SettingsTab.allCases) { tab in
                    settingsTabRow(tab)
                }

                // 버전 정보
                settingsFooter
                    .padding(.top, DesignTokens.Spacing.lg)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Settings Back Button

    @ViewBuilder
    private var settingsBackButton: some View {
        Button {
            withAnimation(DesignTokens.Animation.smooth) {
                router.exitSettings()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSettingsBackHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .offset(x: isSettingsBackHovered ? -2 : 0)
                Text("메뉴")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(isSettingsBackHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, 6)
            .background {
                if isSettingsBackHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(DesignTokens.Colors.textPrimary.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.micro) {
                isSettingsBackHovered = hovering
            }
        }
        .padding(.horizontal, 8)
        .customCursor(.pointingHand)
    }

    // MARK: - Settings Tab Row

    @ViewBuilder
    private func settingsTabRow(_ tab: AppRouter.SettingsTab) -> some View {
        let isSelected = router.selectedSettingsTab == tab
        let isHovered = hoveredSettingsTab == tab

        Button {
            withAnimation(DesignTokens.Animation.snappy) {
                router.selectSettingsTab(tab)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : tab.color)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "settings_sel", in: settingsNS)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(DesignTokens.Colors.textPrimary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.micro) {
                hoveredSettingsTab = hovering ? tab : nil
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .animation(DesignTokens.Animation.indicator, value: router.selectedSettingsTab)
    }

    // MARK: - Settings Footer (Version)

    private var settingsFooter: some View {
        VStack(spacing: 4) {
            Divider()
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.sm)

            Text("CView v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - App Header

    private var sidebarHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm + 2) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text("CView")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("치지직 뷰어")
                    .font(DesignTokens.Typography.custom(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
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
                    .font(DesignTokens.Typography.microSemibold)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
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
        let isHovered = hoveredItem == item
        let liveCount = item == .following ? appState.backgroundUpdateService.onlineChannels.count : 0

        Button {
            router.selectSidebar(item)
        } label: {
            HStack(spacing: 11) {
                // 아이콘 배경
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(isSelected ? (colorScheme == .light ? iconColor(for: item).opacity(0.15) : DesignTokens.Colors.chzzkGreen) : iconBackground(for: item))
                        .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? (colorScheme == .light ? iconColor(for: item) : .white) : iconColor(for: item))
                        .scaleEffect(isHovered && !isSelected ? 1.15 : 1.0)
                        .rotationEffect(.degrees(isHovered && !isSelected ? -3 : 0))
                }
                .shadow(color: isSelected ? DesignTokens.Colors.chzzkGreen.opacity(colorScheme == .light ? 0.15 : 0.28) : .clear, radius: 5, y: 2)
                .scaleEffect(isSelected ? 1.05 : 1.0)

                // 레이블
                Text(item.rawValue)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : (isHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary))
                    .tracking(0.1)

                Spacer()

                // 라이브 뱃지
                if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(DesignTokens.Typography.microSemibold.monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.live, in: Capsule())
                        .shadow(color: DesignTokens.Colors.live.opacity(0.5), radius: 5, y: 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.10))
                        .matchedGeometryEffect(id: "sidebar_sel", in: sidebarNS)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(DesignTokens.Colors.textPrimary.opacity(0.04))
                }
            }
            .offset(x: isHovered && !isSelected ? 2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.micro) {
                hoveredItem = hovering ? item : nil
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .animation(DesignTokens.Animation.indicator, value: router.selectedSidebarItem)
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
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let liveCount = appState.backgroundUpdateService.onlineChannels.count
                HStack(spacing: 4) {
                    if liveCount > 0 {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 6, height: 6)
                            .shadow(color: DesignTokens.Colors.live.opacity(0.6), radius: 4)
                        Text("\(liveCount)채널 라이브")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.live)
                            .contentTransition(.numericText())
                    } else {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.green.opacity(0.5), radius: 3)
                        Text("온라인")
                            .font(DesignTokens.Typography.micro)
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
                    .background(isLogoutHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
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
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(isLoginHovered ? 0.18 : 0.12))
                        .frame(width: DesignTokens.Spacing.xxl, height: DesignTokens.Spacing.xxl)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                Text("로그인")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.microSemibold)
                    .foregroundStyle(isLoginHovered ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary)
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


