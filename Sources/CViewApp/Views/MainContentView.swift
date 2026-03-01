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
    @State private var isCompactSidebar = false

    var body: some View {
        @Bindable var router = router

        ZStack {
            mainContent(router: router)

            if showSplash {
                SplashView {
                    withAnimation(DesignTokens.Animation.normal) {
                        showSplash = false
                    }
                }
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(appState.settingsStore.appearance.theme.colorScheme)
        .commandPaletteOverlay(isPresented: Binding(
            get: { appState.showCommandPalette },
            set: { appState.showCommandPalette = $0 }
        ))
        .background(DesignTokens.Colors.background)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, newWidth in
                        let shouldBeCompact = newWidth < 800
                        if shouldBeCompact != isCompactSidebar {
                            withAnimation(DesignTokens.Animation.contentTransition) {
                                isCompactSidebar = shouldBeCompact
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func mainContent(router: AppRouter) -> some View {
        @Bindable var router = router

        NavigationSplitView {
            SidebarView(isCompact: isCompactSidebar)
                .navigationSplitViewColumnWidth(
                    min: isCompactSidebar ? 56 : 210,
                    ideal: isCompactSidebar ? 62 : 230,
                    max: isCompactSidebar ? 68 : 270
                )
        } detail: {
            NavigationStack(path: $router.path) {
                detailView
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
            
        case .multiChat:
            MultiChatView()
            
        case .multiLive:
            MultiLiveView()
            
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
        case .multiChat:
            MultiChatView()
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

// MARK: - Premium Sidebar View

struct SidebarView: View {

    let isCompact: Bool

    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var hoveredItem: AppRouter.SidebarItem?
    @Namespace private var sidebarNS

    // 섹션 그룹 정의
    private let primaryItems: [AppRouter.SidebarItem] = [.home, .following, .category]
    private let discoverItems: [AppRouter.SidebarItem] = [.search, .clips, .recentFavorites]
    private let toolItems: [AppRouter.SidebarItem] = [.multiChat, .multiLive]

    var body: some View {
        @Bindable var router = router

        VStack(spacing: 0) {
            sidebarHeader

            Divider()
                .overlay(DesignTokens.Colors.border.opacity(0.4))
                .padding(.horizontal, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.md)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    itemSection(items: primaryItems, label: nil)
                    sectionDivider
                    itemSection(items: discoverItems, label: "탐색")
                    sectionDivider
                    itemSection(items: toolItems, label: "도구")
                }
                .padding(.horizontal, isCompact ? 4 : DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }

            Spacer(minLength: 0)

            // 하단 고정: 설정
            VStack(spacing: 0) {
                Divider()
                    .overlay(DesignTokens.Colors.border.opacity(0.35))
                    .padding(.horizontal, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.md)

                SidebarNavItem(
                    item: .settings,
                    isSelected: router.selectedSidebarItem == .settings,
                    isHovered: hoveredItem == .settings,
                    isCompact: isCompact,
                    namespace: sidebarNS,
                    onSelect: {
                        withAnimation(DesignTokens.Animation.indicator) {
                            router.selectSidebar(.settings)
                        }
                    },
                    onHover: { h in hoveredItem = h ? .settings : nil }
                )
                .padding(.horizontal, isCompact ? 4 : DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }

            Divider()
                .overlay(DesignTokens.Colors.border.opacity(0.4))
                .padding(.horizontal, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.md)

            sidebarFooter
        }
        .frame(minWidth: isCompact ? 56 : 210)
        .background {
            // Translucent Glass 사이드바 배경
            ZStack {
                DesignTokens.Colors.background
                DesignTokens.Colors.surfaceBase.opacity(0.5)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func itemSection(items: [AppRouter.SidebarItem], label: String?) -> some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: 2) {
            if let label, !isCompact {
                Text(label.uppercased())
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .tracking(1.1)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xxs)
            }
            ForEach(items) { item in
                SidebarNavItem(
                    item: item,
                    isSelected: router.selectedSidebarItem == item,
                    isHovered: hoveredItem == item,
                    isCompact: isCompact,
                    namespace: sidebarNS,
                    onSelect: {
                        withAnimation(DesignTokens.Animation.indicator) {
                            router.selectSidebar(item)
                        }
                    },
                    onHover: { h in hoveredItem = h ? item : nil },
                    onlineBadgeCount: item == .following
                        ? appState.backgroundUpdateService.onlineChannels.count : 0
                )
            }
        }
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(DesignTokens.Colors.border.opacity(0.25))
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        Group {
            if isCompact {
                // Compact: icon only, centered
                AppIconView(size: 28, showLiveDot: false, animated: true)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.12), radius: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    AppIconView(size: 32, showLiveDot: false, animated: true)
                        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.12), radius: 5)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("CView")
                            .font(DesignTokens.Typography.bodySemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        let liveCount = appState.backgroundUpdateService.onlineChannels.count
                        if liveCount > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 5, height: 5)
                                Text("\(liveCount) LIVE")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                        } else {
                            Text("2.0")
                                .font(DesignTokens.Typography.footnoteMedium)
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        Group {
            if isCompact {
                // Compact footer: icon-only
                if appState.isLoggedIn {
                    VStack(spacing: 6) {
                        ZStack {
                            if let profileURL = appState.userProfileURL {
                                CachedAsyncImage(url: profileURL) { profilePlaceholder }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(DesignTokens.Colors.surfaceElevated)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.45), lineWidth: 1.5)
                        }
                        .help(appState.userNickname ?? "사용자")

                        Button { Task { await appState.handleLogout() } } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .padding(DesignTokens.Spacing.xs)
                                .background(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("로그아웃")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                } else {
                    Button { router.presentSheet(.login) } label: {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(DesignTokens.Typography.custom(size: 15))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("로그인")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
            } else if appState.isLoggedIn {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ZStack {
                        if let profileURL = appState.userProfileURL {
                            CachedAsyncImage(url: profileURL) { profilePlaceholder }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            profilePlaceholder
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.45), lineWidth: 1.5)
                    }
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.15), radius: 4)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.userNickname ?? "사용자")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)

                        let liveCount = appState.backgroundUpdateService.onlineChannels.count
                        if liveCount > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(DesignTokens.Colors.live).frame(width: 4, height: 4)
                                Text("팔로잉 \(liveCount)채널 라이브")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                        } else {
                            HStack(spacing: 3) {
                                Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 4, height: 4)
                                Text("온라인")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                            }
                        }
                    }

                    Spacer()

                    Button { Task { await appState.handleLogout() } } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(DesignTokens.Spacing.xs)
                            .background(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("로그아웃")
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                Button { router.presentSheet(.login) } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(DesignTokens.Typography.custom(size: 15))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                        Text("로그인")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.18), lineWidth: 0.5)
                            }
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(DesignTokens.Colors.surfaceElevated)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "person.fill")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }
}

// MARK: - Sidebar Navigation Item

struct SidebarNavItem: View {
    let item: AppRouter.SidebarItem
    let isSelected: Bool
    let isHovered: Bool
    var isCompact: Bool = false
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    var onlineBadgeCount: Int = 0

    @State private var iconScale: CGFloat = 1.0

    var body: some View {
        Button(action: {
            withAnimation(DesignTokens.Animation.micro) { iconScale = 1.28 }
            withAnimation(DesignTokens.Animation.indicator.delay(0.1)) { iconScale = 1.0 }
            onSelect()
        }) {
            if isCompact {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .animation(DesignTokens.Animation.indicator, value: isSelected)
        .animation(DesignTokens.Animation.micro, value: isHovered)
        .help(isCompact ? item.rawValue : "")
    }

    // MARK: - Compact Layout (icon only)

    private var compactLayout: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.14), lineWidth: 0.5)
                    }
            } else if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6))
            }

            Image(systemName: item.icon)
                .font(DesignTokens.Typography.custom(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                    ? DesignTokens.Colors.chzzkGreen
                    : (isHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                )
                .scaleEffect(iconScale)
        }
        .frame(width: 40, height: 36)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if item == .following && onlineBadgeCount > 0 {
                compactBadge(onlineBadgeCount)
            }
        }
        .animation(DesignTokens.Animation.indicator, value: isSelected)
        .animation(DesignTokens.Animation.micro, value: isHovered)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func compactBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(DesignTokens.Typography.micro)
            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.live)
            .clipShape(Capsule())
            .offset(x: 2, y: -2)
    }

    // MARK: - Expanded Layout (icon + text)

    private var expandedLayout: some View {
        HStack(spacing: 10) {

            // ── 애니메이션 인디케이터 바 ──────────────────────────
            ZStack {
                if isSelected {
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: 3, height: 22)
                    .clipShape(Capsule())
                    .matchedGeometryEffect(id: "sidebarIndicator", in: namespace)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.7), radius: 5)
                } else {
                    Color.clear.frame(width: 3, height: 22)
                }
            }
            .frame(width: 3)

            // ── 아이콘 (선택시 배경 원 + 애니메이션) ───────────────
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                        .frame(width: 30, height: 30)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6))
                        .frame(width: 30, height: 30)
                }
                Image(systemName: item.icon)
                    .font(DesignTokens.Typography.custom(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected
                        ? DesignTokens.Colors.chzzkGreen
                        : (isHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    )
                    .scaleEffect(iconScale)
            }
            .frame(width: 30, height: 30)
            .animation(DesignTokens.Animation.indicator, value: isSelected)
            .animation(DesignTokens.Animation.micro, value: isHovered)

            // ── 텍스트 ────────────────────────────────────────────
            Text(item.rawValue)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(
                    isSelected
                    ? DesignTokens.Colors.textPrimary
                    : (isHovered ? DesignTokens.Colors.textPrimary.opacity(0.85) : DesignTokens.Colors.textSecondary)
                )

            Spacer()

            // ── 라이브 배지 (팔로잉) ───────────────────────────────
            if item == .following && onlineBadgeCount > 0 {
                liveBadge(onlineBadgeCount)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .padding(.trailing, DesignTokens.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(
                    isSelected
                    ? AnyShapeStyle(DesignTokens.Gradients.sidebarActive)
                    : (isHovered ? AnyShapeStyle(DesignTokens.Colors.surfaceOverlay.opacity(0.3)) : AnyShapeStyle(Color.clear))
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.14), lineWidth: 0.5)
                    }
                }
        }
        .contentShape(Rectangle())
    }

    // 펄스 링 + 라이브 뱃지 — TimelineView 기반 Metal 3 순수 수학 애니메이션
    @ViewBuilder
    private func liveBadge(_ count: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let raw = t.truncatingRemainder(dividingBy: 1.6) / 1.6   // 0→1 (1.6s 주기)
            // easeInOut 근사: smoothstep
            let phase = raw * raw * (3.0 - 2.0 * raw)
            let ringOpacity = (1.0 - phase) * 0.32   // 0.32→0 페이드아웃
            let ringScale   = 1.0 + phase * 0.55      // 1.0→1.55 확대
            ZStack {
                Capsule()
                    .fill(DesignTokens.Colors.live.opacity(ringOpacity))
                    .frame(width: 26, height: 18)
                    .scaleEffect(ringScale)
                Text("\(count)")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.live)
                    .clipShape(Capsule())
            }
            // 펄스 합성을 Metal 단일 패스로 오프로드
            .drawingGroup(opaque: false)
        }
    }
}
