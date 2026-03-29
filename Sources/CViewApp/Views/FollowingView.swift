// MARK: - FollowingView.swift
// CViewApp - 라이브 채널 목록 탭
// 글래스모피즘 + 모던 인터랙션 + 부드러운 애니메이션

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI
import CViewNetworking
import CViewChat

// MARK: - Sort Order

enum FollowingSortOrder: String, CaseIterable, Identifiable {
    case liveFirst    = "라이브 우선"
    case viewers      = "시청자 많은 순"
    case nameAsc      = "채널명 가나다순"
    case original     = "기본 순서"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .liveFirst: return "dot.radiowaves.left.and.right"
        case .viewers:   return "person.2"
        case .nameAsc:   return "textformat.abc"
        case .original:  return "list.bullet"
        }
    }

    func sort(_ channels: [LiveChannelItem]) -> [LiveChannelItem] {
        switch self {
        case .liveFirst:
            return channels.sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive }
                return lhs.viewerCount > rhs.viewerCount
            }
        case .viewers:
            return channels.sorted { $0.viewerCount > $1.viewerCount }
        case .nameAsc:
            return channels.sorted { $0.channelName < $1.channelName }
        case .original:
            return channels
        }
    }
}

// MARK: - Preference Key for Live Grid Height

struct LiveGridHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Following View

struct FollowingView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) var appState
    @Environment(AppRouter.self) var router
    @Environment(\.colorScheme) private var colorScheme

    /// 영속 상태 — AppState에서 관리되어 메뉴 전환 시에도 유지
    var ps: FollowingViewState { appState.followingViewState }

    // 정렬/필터 — 영속
    var sortOrder: FollowingSortOrder {
        get { ps.sortOrder }
        nonmutating set { ps.sortOrder = newValue }
    }
    var filterLiveOnly: Bool {
        get { ps.filterLiveOnly }
        nonmutating set { ps.filterLiveOnly = newValue }
    }
    var selectedCategory: String? {
        get { ps.selectedCategory }
        nonmutating set { ps.selectedCategory = newValue }
    }
    // 페이징 — 영속
    var livePageIndex: Int {
        get { ps.livePageIndex }
        nonmutating set { ps.livePageIndex = newValue }
    }
    var offlinePageIndex: Int {
        get { ps.offlinePageIndex }
        nonmutating set { ps.offlinePageIndex = newValue }
    }
    // 멀티라이브 — 영속
    var showMultiLive: Bool {
        get { ps.showMultiLive }
        nonmutating set { ps.showMultiLive = newValue }
    }
    var showMLAddChannel: Bool {
        get { ps.showMLAddChannel }
        nonmutating set { ps.showMLAddChannel = newValue }
    }
    var showMLSettings: Bool {
        get { ps.showMLSettings }
        nonmutating set { ps.showMLSettings = newValue }
    }
    var mlPanelWidth: CGFloat {
        get { ps.mlPanelWidth }
        nonmutating set { ps.mlPanelWidth = newValue }
    }
    var hideFollowingList: Bool {
        get { ps.hideFollowingList }
        nonmutating set { ps.hideFollowingList = newValue }
    }
    // 멀티채팅 — 영속
    var showMultiChat: Bool {
        get { ps.showMultiChat }
        nonmutating set { ps.showMultiChat = newValue }
    }
    var chatSessionManager: MultiChatSessionManager { ps.chatSessionManager }
    var showChatAddChannel: Bool {
        get { ps.showChatAddChannel }
        nonmutating set { ps.showChatAddChannel = newValue }
    }
    var showChatSettings: Bool {
        get { ps.showChatSettings }
        nonmutating set { ps.showChatSettings = newValue }
    }
    var dualPanelSplitRatio: CGFloat {
        get { ps.dualPanelSplitRatio }
        nonmutating set { ps.dualPanelSplitRatio = newValue }
    }

    // 트랜지언트 상태 — 뷰 로컬 (재생성 시 초기화 허용)
    @State var searchText: String = ""
    @State private var _searchDebounceTask: Task<Void, Never>?
    @State private var _resizeDebounceTask: Task<Void, Never>?
    @State var mlAddError: String?
    @State private var isDraggingDivider: Bool = false
    @GestureState private var dividerDragOffset: CGFloat = 0
    @FocusState var isSearchFocused: Bool
    @State var skeletonAppeared = false

    var multiLiveManager: MultiLiveManager { appState.multiLiveManager }

    @State var chatSearchQuery: String = ""
    @State var chatSearchResults: [ChannelInfo] = []
    @State var isSearchingChatChannels: Bool = false
    @State var newChatChannelId: String = ""
    @State var chatAddError: String?
    @GestureState private var dualSplitDragOffset: CGFloat = 0
    // 반응형 그리드: 컨테이너 너비에 따라 열 수·페이지 크기 자동 조정
    @State var followingContentWidth: CGFloat = 800

    /// 반응형 레이아웃 토큰 — followingContentWidth 변경 시 자동 재계산
    var layout: ResponsiveFollowingLayout {
        ResponsiveFollowingLayout(width: followingContentWidth)
    }

    var liveColumns: Int { layout.liveColumns }
    var liveItemsPerPage: Int { layout.liveItemsPerPage }
    var offlineItemsPerPage: Int { layout.offlineRowsPerPage }

    // 캐싱된 필터 결과 — 입력 변경 시에만 재산출 (body 중복 호출 방지)
    @State var cachedLive: [LiveChannelItem] = []
    @State var cachedAllOffline: [LiveChannelItem] = []
    @State var cachedLiveCategoryCounts: [(name: String, count: Int)] = []
    @State var computedLiveGridHeight: CGFloat = 500

    var totalLiveCount: Int { cachedLive.count }
    var totalOfflineCount: Int { cachedAllOffline.count }
    var liveCategoryCounts: [(name: String, count: Int)] { cachedLiveCategoryCounts }
    var liveCategories: [String] { cachedLiveCategoryCounts.map { $0.name } }

    var totalLivePages: Int { max(1, Int(ceil(Double(totalLiveCount) / Double(liveItemsPerPage)))) }
    var totalOfflinePages: Int { max(1, Int(ceil(Double(totalOfflineCount) / Double(offlineItemsPerPage)))) }

    func liveChannelsForPage(_ page: Int) -> [LiveChannelItem] {
        let start = page * liveItemsPerPage
        let end = min(start + liveItemsPerPage, totalLiveCount)
        guard start < end else { return [] }
        return Array(cachedLive[start..<end])
    }

    func offlineChannelsForPage(_ page: Int) -> [LiveChannelItem] {
        let start = page * offlineItemsPerPage
        let end = min(start + offlineItemsPerPage, totalOfflineCount)
        guard start < end else { return [] }
        return Array(cachedAllOffline[start..<end])
    }

    func formatShortCount(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000) }
        return "\(n)"
    }

    /// 필터/정렬 조건이 바뀔 때만 재산출 — body 중복 연산 방지
    private func recomputeFiltered() {
        var channels = sortOrder.sort(viewModel.followingChannels)
        if filterLiveOnly { channels = channels.filter { $0.isLive } }
        if let cat = selectedCategory { channels = channels.filter { $0.categoryName == cat } }
        if !searchText.isEmpty {
            channels = channels.filter { $0.channelName.localizedCaseInsensitiveContains(searchText) }
        }
        cachedLive = channels.filter { $0.isLive }
        cachedAllOffline = channels.filter { !$0.isLive }

        var counts: [String: Int] = [:]
        viewModel.followingChannels
            .filter { $0.isLive }
            .compactMap { $0.categoryName }
            .forEach { counts[$0, default: 0] += 1 }
        cachedLiveCategoryCounts = counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    /// 페이지 리셋 + 필터 재계산 (정렬/필터 조건 변경 시 사용)
    private func resetPaginationAndRecompute() {
        livePageIndex = 0
        offlinePageIndex = 0
        recomputeFiltered()
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // 배경 — 단색 기반 미니멀 그라디언트
            LinearGradient(
                stops: [
                    .init(color: DesignTokens.Colors.chzzkGreen.opacity(colorScheme == .light ? 0.02 : 0.03), location: 0),
                    .init(color: .clear, location: 0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if !appState.isLoggedIn {
                followingGateView(
                    icon: "person.crop.circle.badge.questionmark",
                    iconColor: DesignTokens.Colors.textTertiary,
                    title: "로그인이 필요합니다",
                    subtitle: "로그인하면 라이브 채널을 확인할 수 있습니다",
                    buttonLabel: "로그인",
                    action: { router.presentSheet(.login) }
                )
                .transition(.opacity)
            } else if viewModel.needsCookieLogin {
                followingGateView(
                    icon: "key.fill",
                    iconColor: DesignTokens.Colors.accentOrange,
                    title: "네이버 로그인이 필요합니다",
                    subtitle: "라이브 목록을 보려면 '네이버 로그인'으로 다시 로그인하세요",
                    buttonLabel: "네이버 로그인",
                    action: { router.presentSheet(.login) }
                )
                .transition(.opacity)
            } else if viewModel.followingChannels.isEmpty {
                if viewModel.isLoadingFollowing {
                    skeletonLoadingView
                        .transition(.opacity)
                } else {
                    followingGateView(
                        icon: "heart",
                        iconColor: DesignTokens.Colors.accentPink,
                        title: "라이브 채널이 없습니다",
                        subtitle: "치지직에서 채널을 팔로우하면 여기서 확인할 수 있어요",
                        buttonLabel: nil,
                        action: nil
                    )
                    .transition(.opacity)
                }
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(DesignTokens.Animation.smooth, value: viewModel.isLoadingFollowing)
        .animation(DesignTokens.Animation.smooth, value: viewModel.followingChannels.isEmpty)
        .navigationTitle("")
        .toolbar(.hidden)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenuButton
            }
        }
        // 필터/정렬 관련 값 변경 시 1회만 recomputeFiltered() 호출되도록 통합
        .onChange(of: sortOrder) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: filterLiveOnly) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: selectedCategory) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: searchText) { _, _ in
            _searchDebounceTask?.cancel()
            _searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                recomputeFiltered()
            }
        }
        .onChange(of: viewModel.followingChannels) { _, _ in recomputeFiltered() }
        // 페이지 전환 시 인접 페이지 썸네일 프리페치 + 프리디코딩
        .onChange(of: livePageIndex) { _, newPage in
            prefetchAdjacentLivePages(around: newPage)
        }
        .onChange(of: offlinePageIndex) { _, newPage in
            prefetchAdjacentOfflinePages(around: newPage)
        }
        // 멀티라이브 세션 추가 시 → 멀티채팅에도 자동 추가
        .onChange(of: multiLiveManager.sessions.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let existingChatIds = Set(chatSessionManager.sessions.map { $0.id })
            let newSessions = multiLiveManager.sessions.filter { !existingChatIds.contains($0.channelId) }
            for session in newSessions {
                let channelId = session.channelId
                Task { await addChatChannel(channelId: channelId) }
            }
            if !newSessions.isEmpty {
                showMultiChat = true
            }
        }
        .task {
            // 데이터 있고 캐시가 5분 이내면 재로드 스킵
            let isFresh = viewModel.followingCachedAt.map { Date().timeIntervalSince($0) < 300 } ?? false
            guard viewModel.followingChannels.isEmpty || !isFresh else {
                recomputeFiltered()
                return
            }
            guard !viewModel.isLoadingFollowing else { return }
            await viewModel.loadFollowingChannels()
        }
    }


    // MARK: - Main Content (widget-style card layout)

    private let mlPanelMaxRatio: CGFloat = 0.85
    private let mlPanelMinWidth: CGFloat = 280

    private var mainContent: some View {
        let hasSidePanel = showMultiLive || showMultiChat

        return GeometryReader { geo in
            let totalWidth = geo.size.width
            let effectiveWidth = mlPanelWidth - dividerDragOffset
            let clampedPanelWidth = min(max(effectiveWidth, mlPanelMinWidth), totalWidth * mlPanelMaxRatio)
            let listWidth = totalWidth - clampedPanelWidth - 1 // 1 = divider

            HStack(spacing: 0) {
                // 왼쪽: 라이브 채널 목록 — 고정 너비 (나머지를 패널에 양보)
                if !hideFollowingList || !hasSidePanel {
                    followingListContent
                        .frame(width: hasSidePanel ? max(listWidth, 0) : nil)
                        .frame(maxWidth: hasSidePanel ? nil : .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // 오른쪽: 사이드 패널 (멀티라이브 또는 멀티채팅)
                if hasSidePanel {
                    if !hideFollowingList {
                        mlDividerHandle
                    }

                    sidePanelContent(totalWidth: clampedPanelWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(isDraggingDivider ? nil : DesignTokens.Animation.normal, value: showMultiLive)
        .animation(isDraggingDivider ? nil : DesignTokens.Animation.normal, value: showMultiChat)
        .animation(isDraggingDivider ? nil : DesignTokens.Animation.normal, value: hideFollowingList)
    }

    /// 멀티라이브 + 멀티채팅 동시 또는 단독 표시
    @ViewBuilder
    private func sidePanelContent(totalWidth: CGFloat) -> some View {
        if showMultiLive && showMultiChat {
            // 커스텀 분할 뷰 (HSplitView 대신 순수 SwiftUI로 레이아웃 순환 방지)
            GeometryReader { geo in
                let panelW = geo.size.width
                let effectiveRatio = dualPanelSplitRatio + (dualSplitDragOffset / panelW)
                let clampedRatio = min(max(effectiveRatio, 0.25), 0.75)
                let liveW = panelW * clampedRatio
                let chatW = panelW * (1 - clampedRatio)

                HStack(spacing: 0) {
                    multiLiveInlinePanel
                        .frame(width: max(liveW - 1, 0))
                        .frame(maxHeight: .infinity)

                    // 분할 핸들
                    Rectangle()
                        .fill(DesignTokens.Glass.dividerColor.opacity(0.3))
                        .frame(width: 1)
                        .overlay(alignment: .center) {
                            Capsule()
                                .fill(DesignTokens.Colors.textTertiary.opacity(0.3))
                                .frame(width: 3, height: 28)
                        }
                        .contentShape(Rectangle().inset(by: -4))
                        .onHover { h in
                            if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .updating($dualSplitDragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onEnded { value in
                                    let delta = value.translation.width / panelW
                                    dualPanelSplitRatio = min(max(dualPanelSplitRatio + delta, 0.25), 0.75)
                                }
                        )

                    multiChatInlinePanel
                        .frame(width: max(chatW - 1, 0))
                        .frame(maxHeight: .infinity)
                }
            }
        } else if showMultiLive {
            multiLiveInlinePanel
        } else if showMultiChat {
            multiChatInlinePanel
        }
    }

    private var mlDividerHandle: some View {
        Rectangle()
            .fill(isDraggingDivider ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Glass.dividerColor.opacity(0.3))
            .frame(width: 1)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(isDraggingDivider ? DesignTokens.Colors.chzzkGreen.opacity(0.6) : DesignTokens.Colors.textTertiary.opacity(0.3))
                    .frame(width: 3, height: 28)
            }
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dividerDragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onChanged { _ in
                        isDraggingDivider = true
                    }
                    .onEnded { value in
                        mlPanelWidth -= value.translation.width
                        isDraggingDivider = false
                    }
            )
    }

    // MARK: - Following List Content

    private var followingListContent: some View {
        let outerPad = layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.xl
        let innerSpacing = layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.md : DesignTokens.Spacing.xl

        return ScrollView(showsIndicators: false) {
            VStack(spacing: innerSpacing) {
                // 반응형 너비 측정 — 레이아웃 패스 밖에서 상태 업데이트하여 순환 방지
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let w = geo.size.width - outerPad * 2
                            if abs(w - followingContentWidth) > 1 {
                                DispatchQueue.main.async { followingContentWidth = w }
                            }
                        }
                        .onChange(of: geo.size.width) { _, w in
                            let newWidth = w - outerPad * 2
                            if abs(newWidth - followingContentWidth) > 20 {
                                debounceResize(to: newWidth)
                            }
                        }
                }
                .frame(height: 0)

                // 헤더 섹션
                headerSection

                // 검색 및 필터 카드
                searchAndFilterCard

                // 카테고리 필터 칩 (라이브가 있을 때만)
                if !liveCategories.isEmpty {
                    categoryFilterChips
                }

                // 검색 결과 없음
                if cachedLive.isEmpty && cachedAllOffline.isEmpty {
                    widgetCard {
                        emptySearchResult
                    }
                } else {
                    // ── 라이브 채널 카드 그리드 (위젯 카드)
                    if !cachedLive.isEmpty {
                        widgetCard {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                                sectionHeader(
                                    icon: "dot.radiowaves.left.and.right",
                                    title: "라이브 중",
                                    count: totalLiveCount,
                                    color: DesignTokens.Colors.live
                                )

                                livePagingView

                                if totalLivePages > 1 {
                                    pageNavigator(
                                        currentPage: Binding(
                                            get: { ps.livePageIndex },
                                            set: { ps.livePageIndex = $0 }
                                        ),
                                        totalPages: totalLivePages,
                                        accentColor: DesignTokens.Colors.live
                                    )
                                }
                            }
                        }
                    }

                    // ── 오프라인 채널 리스트 (위젯 카드)
                    if !filterLiveOnly && totalOfflineCount > 0 {
                        widgetCard {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                                sectionHeader(
                                    icon: "moon.zzz.fill",
                                    title: "오프라인",
                                    count: totalOfflineCount,
                                    color: DesignTokens.Colors.textTertiary
                                )

                                offlinePagingView

                                if totalOfflinePages > 1 {
                                    pageNavigator(
                                        currentPage: Binding(
                                            get: { ps.offlinePageIndex },
                                            set: { ps.offlinePageIndex = $0 }
                                        ),
                                        totalPages: totalOfflinePages,
                                        accentColor: DesignTokens.Colors.accentPurple
                                    )
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: innerSpacing)
            }
            .padding(outerPad)
            .id(layout.sizeClass)
        }
    }

    // MARK: - Resize Debounce (리사이즈 디바운스)

    /// 너비 변경 시 100ms 디바운스 — 드래그 중 과도한 레이아웃 재계산 방지
    private func debounceResize(to newWidth: CGFloat) {
        _resizeDebounceTask?.cancel()
        _resizeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            followingContentWidth = newWidth
            livePageIndex = min(livePageIndex, max(0, totalLivePages - 1))
            offlinePageIndex = min(offlinePageIndex, max(0, totalOfflinePages - 1))
        }
    }

    // MARK: - Page Prefetch (인접 페이지 썸네일 프리디코딩)

    /// 라이브 페이지 전환 시 인접 페이지 썸네일을 미리 디코딩하여 깜빡임 방지
    private func prefetchAdjacentLivePages(around page: Int) {
        let adjacentPages = [page - 1, page + 1].filter { $0 >= 0 && $0 < totalLivePages }
        let urls: [URL] = adjacentPages.flatMap { p in
            liveChannelsForPage(p).compactMap { ch in
                if let thumb = ch.thumbnailUrl, !thumb.isEmpty { return URL(string: thumb) }
                if let img = ch.channelImageUrl, !img.isEmpty { return URL(string: img) }
                return nil
            }
        }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await ImageCacheService.shared.prefetchAndDecode(urls)
        }
    }

    /// 오프라인 페이지 전환 시 인접 페이지 프로필 이미지 프리페치
    private func prefetchAdjacentOfflinePages(around page: Int) {
        let adjacentPages = [page - 1, page + 1].filter { $0 >= 0 && $0 < totalOfflinePages }
        let urls: [URL] = adjacentPages.flatMap { p in
            offlineChannelsForPage(p).compactMap { ch in
                if let img = ch.channelImageUrl, !img.isEmpty { return URL(string: img) }
                return nil
            }
        }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await ImageCacheService.shared.prefetchAndDecode(urls)
        }
    }
}
