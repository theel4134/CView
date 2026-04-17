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
    var showFollowingList: Bool {
        get { ps.showFollowingList }
        nonmutating set { ps.showFollowingList = newValue }
    }
    var showMultiLive: Bool {
        get { ps.showMultiLive }
        nonmutating set { ps.showMultiLive = newValue }
    }
    var showMLSettings: Bool {
        get { ps.showMLSettings }
        nonmutating set { ps.showMLSettings = newValue }
    }
    // PiP 모드 — 영속 (AppState)
    var isMultiLivePiPMode: Bool {
        get { ps.isMultiLivePiPMode }
        nonmutating set { ps.isMultiLivePiPMode = newValue }
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

    // 트랜지언트 상태 — 뷰 로컬 (재생성 시 초기화 허용)
    @State var searchText: String = ""
    @State private var _searchDebounceTask: Task<Void, Never>?
    @State private var _resizeDebounceTask: Task<Void, Never>?
    @State var mlAddError: String?
    @FocusState var isSearchFocused: Bool
    @State var skeletonAppeared = false

    var multiLiveManager: MultiLiveManager { appState.multiLiveManager }

    @State var chatAddError: String?
    @State var showDisconnectAllConfirm = false
    @State var showMergedChat = false
    /// 채팅 세션 복원 진행 중 플래그 — 멀티라이브 onChange 중복 추가 방지
    @State private var isRestoringChatSessions = false
    @GestureState var chatSwipeDragOffset: CGFloat = 0
    @State var livePageDragOffset: CGFloat = 0
    @State var offlinePageDragOffset: CGFloat = 0
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

    @State private var _recomputeTask: Task<Void, Never>?

    /// 필터/정렬 조건이 바뀔 때만 재산출 — 무거운 연산은 백그라운드에서 수행
    private func recomputeFiltered() {
        _recomputeTask?.cancel()
        // 캡처할 값을 미리 스냅샷
        let allChannels = viewModel.followingChannels
        let order = sortOrder
        let liveOnly = filterLiveOnly
        let category = selectedCategory
        let query = searchText.lowercased()

        _recomputeTask = Task {
            // 백그라운드에서 무거운 정렬/필터 수행
            let result: (live: [LiveChannelItem], offline: [LiveChannelItem], cats: [(String, Int)]) = await Task.detached(priority: .userInitiated) {
                // 카테고리 계수 (필터 적용 전 전체 라이브 기준)
                var counts: [String: Int] = [:]
                for ch in allChannels where ch.isLive {
                    if let cat = ch.categoryName {
                        counts[cat, default: 0] += 1
                    }
                }
                let sortedCats = counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

                // 정렬 → 필터 적용
                var channels = order.sort(allChannels)
                if liveOnly { channels = channels.filter { $0.isLive } }
                if let cat = category { channels = channels.filter { $0.categoryName == cat } }
                if !query.isEmpty {
                    channels = channels.filter { ch in
                        ch.channelName.lowercased().contains(query)
                        || ch.liveTitle.lowercased().contains(query)
                        || (ch.categoryName ?? "").lowercased().contains(query)
                    }
                }
                let live = channels.filter { $0.isLive }
                let offline = channels.filter { !$0.isLive }
                return (live, offline, sortedCats)
            }.value

            guard !Task.isCancelled else { return }
            // MainActor에서 결과만 할당
            cachedLive = result.live
            cachedAllOffline = result.offline
            cachedLiveCategoryCounts = result.cats
        }
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

            // 배경 — 단색 기반 미니멀 그라디언트 (drawingGroup으로 단일 GPU 텍스처 렌더)
            LinearGradient(
                stops: [
                    .init(color: DesignTokens.Colors.chzzkGreen.opacity(colorScheme == .light ? 0.02 : 0.03), location: 0),
                    .init(color: .clear, location: 0.5),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .drawingGroup()
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
        // 멀티라이브 세션 추가 시 → 멀티채팅에도 자동 추가 (복원 중에는 스킵)
        .onChange(of: multiLiveManager.sessions.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            guard !isRestoringChatSessions else { return }
            // [Fix] 배열 스냅샷 캡처 — onChange 콜백과 배열 접근 사이의 레이스 방지
            let currentSessions = Array(multiLiveManager.sessions)
            let existingChatIds = Set(chatSessionManager.sessions.map { $0.id })
            let newSessions = currentSessions.filter { !existingChatIds.contains($0.channelId) }
            for session in newSessions {
                let channelId = session.channelId
                Task { await addChatChannel(channelId: channelId) }
            }
            if !newSessions.isEmpty {
                showMultiChat = true
            }
        }
        .task {
            // 멀티채팅 세션 복원 (SettingsStore 연결 + 저장된 세션 재연결)
            if chatSessionManager.sessions.isEmpty {
                chatSessionManager.configure(settingsStore: appState.settingsStore)
                isRestoringChatSessions = true
                await restoreSavedChatSessions()
                isRestoringChatSessions = false
            }

            // [최적화] 캐시 데이터가 있으면 즉시 렌더링 → 백그라운드 갱신
            if !viewModel.followingChannels.isEmpty {
                recomputeFiltered()
                let isFresh = viewModel.followingCachedAt.map { Date().timeIntervalSince($0) < 300 } ?? false
                if isFresh { return }
                // 캐시가 오래된 경우 백그라운드에서 갱신 (스켈레톤 표시 없이)
                guard !viewModel.isLoadingFollowing else { return }
                await viewModel.loadFollowingChannels()
            } else {
                guard !viewModel.isLoadingFollowing else { return }
                await viewModel.loadFollowingChannels()
            }
        }
        .onAppear {
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }


    // MARK: - Main Content (widget-style card layout)

    private var mainContent: some View {
        let effectiveShowMultiLive = showMultiLive && !isMultiLivePiPMode
        let hasSidePanel = effectiveShowMultiLive || showMultiChat

        return GeometryReader { geo in
            let totalWidth = geo.size.width
            let listWidth = totalWidth * FollowingViewState.followingListRatio

            HStack(spacing: 0) {
                // 팔로잉 리스트 — 왼쪽에서 push 슬라이드
                if showFollowingList {
                    followingListContent
                        .frame(width: listWidth)
                        .frame(maxHeight: .infinity)
                        .compositingGroup()
                        .background {
                            HStack(spacing: 0) {
                                LinearGradient(
                                    colors: [.black.opacity(0.06), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 8)
                                Spacer(minLength: 0)
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 10)
                            }
                            .allowsHitTesting(false)
                        }
                        .transition(.move(edge: .leading))

                    // 구분선
                    Rectangle()
                        .fill(DesignTokens.Glass.dividerColor.opacity(0.3))
                        .frame(width: 1)
                }

                // 우측 컨텐츠 — 사이드 패널 또는 빈 상태
                if hasSidePanel {
                    sidePanelContent(windowWidth: totalWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    followingListEmptyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .transaction { t in
            t.animation = DesignTokens.Animation.snappy
        }
    }

    /// 사이드 패널이 모두 닫혀있을 때 표시되는 빈 상태 뷰
    private var followingListEmptyPanel: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // 미니 토글 버튼 (좌상단)
            HStack {
                followingListToggleButton
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.lg)

            Spacer()

            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "rectangle.split.2x2")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                Text("멀티라이브 또는 멀티채팅을 열어보세요")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("팔로잉 목록에서 채널을 선택할 수 있습니다")
                    .font(DesignTokens.Typography.custom(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
            }

            Spacer()
        }
    }

    /// 팔로잉 리스트 열기/닫기 토글 버튼 (재사용)
    var followingListToggleButton: some View {
        Button {
            withAnimation(DesignTokens.Animation.snappy) {
                showFollowingList.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showFollowingList ? "sidebar.left" : "sidebar.left")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                Text("팔로잉")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(showFollowingList
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.textTertiary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .help(showFollowingList ? "팔로잉 목록 닫기" : "팔로잉 목록 열기")
    }

    // MARK: - 듀얼 패널 리사이즈 디바이더

    @State private var dualSplitDragStartRatio: CGFloat = 0
    @State private var isDualSplitDragging: Bool = false

    /// 멀티라이브 ↔ 멀티채팅 리사이즈 디바이더
    private func dualPanelResizeDivider(containerWidth: CGFloat) -> some View {
        let thickness: CGFloat = 3
        return ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness + 12)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 1)
                .fill(
                    isDualSplitDragging
                        ? DesignTokens.Colors.accentBlue.opacity(0.8)
                        : DesignTokens.Glass.dividerColor
                )
                .frame(width: thickness)
                .shadow(
                    color: isDualSplitDragging ? DesignTokens.Colors.accentBlue.opacity(0.3) : .clear,
                    radius: 4
                )
        }
        .frame(width: thickness)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDualSplitDragging {
                        isDualSplitDragging = true
                        dualSplitDragStartRatio = ps.dualSplitRatio
                    }
                    guard containerWidth > 0 else { return }
                    let newRatio = dualSplitDragStartRatio + value.translation.width / containerWidth
                    ps.dualSplitRatio = min(0.85, max(0.35, newRatio))
                }
                .onEnded { _ in
                    isDualSplitDragging = false
                }
        )
        .transaction { $0.animation = nil }
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .animation(DesignTokens.Animation.fast, value: isDualSplitDragging)
    }

    /// 멀티라이브 + 멀티채팅 동시 또는 단독 표시
    /// 멀티채팅 너비는 사용자 설정(`SettingsStore.multiChat.panelWidthRatio`, 기본 25%)을 따름.
    @ViewBuilder
    private func sidePanelContent(windowWidth: CGFloat) -> some View {
        let effectiveShowMultiLive = showMultiLive && !isMultiLivePiPMode
        let ratio = min(max(appState.settingsStore.multiChat.panelWidthRatio, 0.15), 0.50)
        let chatFixedWidth = max(windowWidth * ratio, 0)
        if effectiveShowMultiLive && showMultiChat {
            GeometryReader { geo in
                let panelW = geo.size.width
                let chatW = min(chatFixedWidth, max(panelW - 100, 0))
                let liveW = max(panelW - chatW, 0)

                HStack(spacing: 0) {
                    multiLiveInlinePanel
                        .frame(width: liveW)
                        .frame(maxHeight: .infinity)

                    multiChatInlinePanel
                        .frame(width: chatW)
                        .frame(maxHeight: .infinity)
                }
            }
        } else if effectiveShowMultiLive {
            multiLiveInlinePanel
        } else if showMultiChat {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                multiChatInlinePanel
                    .frame(width: chatFixedWidth)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Multi-Live PiP Auto-Transition

    /// 멀티라이브 활성 세션을 PiP로 자동 전환
    private func startMultiLivePiP() {
        let pip = PiPController.shared

        // 이미 PiP 활성 → 모드 플래그만 동기화
        guard !pip.isActive else {
            isMultiLivePiPMode = true
            return
        }

        guard let session = multiLiveManager.selectedSession ?? multiLiveManager.sessions.first,
              let vlcEngine = session.playerViewModel.playerEngine as? VLCPlayerEngine
        else { return }

        pip.startPiP(vlcEngine: vlcEngine, title: session.channelName)

        // PiP "메인 창 복귀" 버튼 → PiP 종료 + 인라인 복원
        pip.onReturnToMain = { [ps] in
            pip.stopPiP()
            ps.isMultiLivePiPMode = false
        }

        // PiP 종료(닫기 버튼·외부 호출 등) → 인라인 복원
        pip.onPiPStopped = { [ps] in
            ps.isMultiLivePiPMode = false
        }

        isMultiLivePiPMode = true
    }

    // MARK: - Following List Content

    private var followingListContent: some View {
        let outerPad = DesignTokens.Spacing.xl
        let innerSpacing = DesignTokens.Spacing.xl

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
                            if abs(newWidth - followingContentWidth) > 8 {
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
                    // 필터/카테고리 영역 구분선
                    sectionDivider
                    categoryFilterChips
                }

                // 검색 결과 없음
                if cachedLive.isEmpty && cachedAllOffline.isEmpty {
                    widgetCard {
                        emptySearchResult
                    }
                } else {
                    // ── 라이브 채널 아바타 스트립 (프로필 이미지 기반 빠른 탐색)
                    if !cachedLive.isEmpty {
                        widgetCard {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                sectionHeader(
                                    icon: "dot.radiowaves.left.and.right",
                                    title: "라이브 중",
                                    count: totalLiveCount,
                                    color: DesignTokens.Colors.live
                                )

                                liveAvatarStrip
                            }
                        }

                        // ── 라이브 채널 썸네일 그리드 (페이징)
                        widgetCard {
                            VStack(spacing: DesignTokens.Spacing.sm) {
                                livePagingView

                                if totalLivePages > 1 {
                                    pageNavigator(
                                        currentPage: Binding(
                                            get: { ps.livePageIndex },
                                            set: { ps.livePageIndex = $0 }
                                        ),
                                        totalPages: totalLivePages,
                                        accentColor: DesignTokens.Colors.chzzkGreen
                                    )
                                }
                            }
                        }
                    }

                    // ── 라이브/오프라인 구분선
                    if !filterLiveOnly && totalOfflineCount > 0 && !cachedLive.isEmpty {
                        sectionDivider
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
        }
        .onKeyPress(.leftArrow) {
            guard !isSearchFocused else { return .ignored }
            if livePageIndex > 0 {
                withAnimation(DesignTokens.Animation.smooth) { livePageIndex -= 1 }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            guard !isSearchFocused else { return .ignored }
            if livePageIndex < totalLivePages - 1 {
                withAnimation(DesignTokens.Animation.smooth) { livePageIndex += 1 }
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Section Divider

    /// 섹션 간 구분을 위한 그라디언트 디바이더
    private var sectionDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: DesignTokens.Colors.surfaceElevated.opacity(0.6), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
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
