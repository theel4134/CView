// MARK: - FollowingView.swift
// CViewApp - 라이브 채널 목록 탭
// 글래스모피즘 + 모던 인터랙션 + 부드러운 애니메이션

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI
import CViewNetworking
import CViewChat

// MARK: - Sort Order, Preference Key
//
// 분리 위치:
// - FollowingSortOrder enum   → FollowingSortOrder.swift
// - LiveGridHeightKey         → LiveGridHeightKey.swift

// MARK: - Following View

struct FollowingView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) var appState
    @Environment(AppRouter.self) var router
    @Environment(\.openWindow) var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    var hubMode: FollowingHubMode {
        get { ps.hubMode }
        nonmutating set { ps.hubMode = newValue }
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
    var autoSyncChatOnMultiLiveAdd: Bool {
        get { ps.autoSyncChatOnMultiLiveAdd }
        nonmutating set { ps.autoSyncChatOnMultiLiveAdd = newValue }
    }
    var smartQueueChannelIds: [String] {
        get { ps.smartQueueChannelIds }
        nonmutating set { ps.smartQueueChannelIds = newValue }
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
    @State var smartQueueBatchResult: String?
    @FocusState var isSearchFocused: Bool
    @State var skeletonAppeared = false

    // 슬라이딩 필러 하이라이트용 네임스페이스 (matchedGeometryEffect)
    @Namespace var filterPillNS
    @Namespace var categoryPillNS
    @Namespace var pageIndicatorNS

    var multiLiveManager: MultiLiveManager { appState.multiLiveManager }

    @State var chatAddError: String?
    @State var showDisconnectAllConfirm = false
    @State var showMergedChat = false
    /// 채팅 세션 복원 진행 중 플래그 — 멀티라이브 onChange 중복 추가 방지
    @State private var isRestoringChatSessions = false
    @GestureState var chatSwipeDragOffset: CGFloat = 0
    @State var livePageDragOffset: CGFloat = 0
    @State var offlinePageDragOffset: CGFloat = 0
    /// 헤더 새로고침 버튼 스피너 각도 (loadingSpin 무한반복 버그 회피)
    @State var refreshRotation: Double = 0
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
            // [Fix 32] PowerAware: 배터리에서는 .utility로 자동 강등(E-core 유도)
            let result: (live: [LiveChannelItem], offline: [LiveChannelItem], cats: [(String, Int)]) = await Task.detached(priority: PowerAwareTaskPriority.userVisible) {
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

    private func runInitialFollowingLoad() async {
        // 멀티채팅 세션 복원 (SettingsStore 연결 + 저장된 세션 재연결)
        if chatSessionManager.sessions.isEmpty {
            chatSessionManager.configure(settingsStore: appState.settingsStore)
            isRestoringChatSessions = true
            await restoreSavedChatSessions()
            isRestoringChatSessions = false
        }

        // [2026-04-28] 시트 필터(즐겨찾기/최근) 데이터 로드
        await reloadFavoritesAndRecent()

        // [최적화] 캐시 데이터가 있으면 즉시 렌더링 → 백그라운드 갱신
        if !viewModel.followingChannels.isEmpty {
            recomputeFiltered()
            let isFresh = viewModel.followingCachedAt
                .map { Date().timeIntervalSince($0) < 300 } ?? false
            if isFresh { return }
            // 캐시가 오래된 경우 백그라운드에서 갱신 (스켈레톤 표시 없이)
            guard !viewModel.isLoadingFollowing else { return }
            await viewModel.loadFollowingChannels()
        } else {
            guard !viewModel.isLoadingFollowing else { return }
            await viewModel.loadFollowingChannels()
        }
    }

    /// [2026-04-28] DataStore에서 즐겨찾기/최근 채널 ID를 로드해 ps에 캐싱.
    /// FollowingBottomSheetView의 favorites/recent 필터에서 즉시 사용.
    private func reloadFavoritesAndRecent() async {
        guard let ds = appState.dataStore else { return }
        let favs = (try? await ds.fetchFavoriteItems()) ?? []
        let recents = (try? await ds.fetchRecentItems(limit: 30)) ?? []
        ps.favoriteChannelIds = Set(favs.map(\.channelId))
        ps.recentChannelIds = recents.map(\.channelId)
    }

    var body: some View {
        let root = AnyView(
            ZStack {
                DesignTokens.Colors.background
                    .ignoresSafeArea()

                // 배경 레이어: 단색 + 앰비언트 글로우 + 상단 스캔라인로 깊이감을 강화.
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: DesignTokens.Colors.chzzkGreen.opacity(colorScheme == .light ? 0.03 : 0.05), location: 0),
                            .init(color: DesignTokens.Colors.accentBlue.opacity(colorScheme == .light ? 0.015 : 0.03), location: 0.32),
                            .init(color: .clear, location: 0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [
                            DesignTokens.Colors.chzzkGreen.opacity(colorScheme == .light ? 0.08 : 0.14),
                            .clear,
                        ],
                        center: .topLeading,
                        startRadius: 24,
                        endRadius: 560
                    )

                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .light ? 0.10 : 0.05),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxHeight: 120)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

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
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
        )

        let animatedRoot = AnyView(
            root
                .animation(DesignTokens.Animation.smooth, value: appState.isLoggedIn)
                .animation(DesignTokens.Animation.smooth, value: viewModel.needsCookieLogin)
                .animation(DesignTokens.Animation.smooth, value: viewModel.followingChannels.isEmpty)
                .animation(DesignTokens.Animation.smooth, value: viewModel.isLoadingFollowing)
        )

        let observedRoot = AnyView(
            animatedRoot
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
                    guard autoSyncChatOnMultiLiveAdd else { return }
                    guard !isRestoringChatSessions else { return }
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
                .onChange(of: showMultiChat) { _, isOn in
                    if isOn { ps.chatDockFocus = .multi }
                }
        )

        return observedRoot
            .task { await runInitialFollowingLoad() }
            .onAppear {
                viewModel.startAutoRefresh()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
            // [2026-04-30] 카테고리 → 시청 탭 진입 시 pending 채널을 자동 재생
            .task(id: router.pendingWatchChannelId) {
                guard let channelId = router.pendingWatchChannelId else { return }
                router.pendingWatchChannelId = nil
                await multiLiveManager.addSession(channelId: channelId, presentationOverride: .embedded)
                applyHubModePreset(.watch)
            }
    }


    // MARK: - Main Content (2026-04-27 Final Redesign)
    //
    // [Fix 2026-04-28] GeometryReader가 VStack 내부에서 부모에게 제안받은 전체 높이를
    // 가져가 liveHubTopBar 위에 덮어씌우는 macOS SwiftUI 레이아웃 버그.
    // 해결: redesignedWorkspace에 .padding(.top, 48)으로 공간을 확보하고
    // liveHubTopBar를 .overlay(alignment: .top)으로 항상 최상단에 렌더링.

    private var mainContent: some View {
        redesignedWorkspace
            .animation(DesignTokens.Animation.smooth, value: hubMode)
            .animation(DesignTokens.Animation.smooth, value: ps.followingSheetState)
            .animation(DesignTokens.Animation.smooth, value: ps.chatDockFocus)
            .transaction { t in
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    t.animation = nil
                }
            }
            .padding(.top, 48)
            .overlay(alignment: .top) {
                liveHubTopBar
            }
    }

    @ViewBuilder
    private var redesignedWorkspace: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let chatDockWidth = chatDockWidth(for: totalWidth)
            let stageWidth = max(totalWidth - chatDockWidth - 1, 0)

            // 시청/멀티 모드(싱글·그리드 공통)에서 팔로잉 시트 on/off 토글로 제어.
            // 우상단 stageToolBar 의 토글 버튼이 단일 진실 공급원이며,
            // 싱글 시청·멀티 그리드 모두에서 사용자가 토글로 시트를 표시/숨길 수 있다.
            let shouldHideFollowingSheet = (hubMode == .watch || hubMode == .multi)
                && !multiLiveManager.sessions.isEmpty
                && ps.isFollowingSheetHidden

            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    redesignedStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !shouldHideFollowingSheet {
                        followingBottomSheet(totalWidth: stageWidth, totalHeight: geo.size.height)
                    }
                }
                .frame(width: stageWidth)

                Rectangle()
                    .fill(DesignTokens.Glass.dividerColor.opacity(0.6))
                    .frame(width: 1)

                rightChatDock
                    .frame(width: chatDockWidth)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// 우측 채팅 도크 폭 — 화면 폭에 따라 280-420pt 클램프
    private func chatDockWidth(for totalWidth: CGFloat) -> CGFloat {
        let base: CGFloat
        switch ps.chatDockFocus {
        case .balanced: base = totalWidth * 0.30
        case .single:   base = totalWidth * 0.34
        case .multi:    base = totalWidth * 0.36
        }
        return min(max(base, 280), 460)
    }

    @ViewBuilder
    private var redesignedStage: some View {
        switch hubMode {
        case .explore:
            overviewStage
        case .watch:
            if multiLiveManager.sessions.isEmpty {
                emptyWatchStage
            } else {
                multiLiveInlinePanel
            }
        case .multi:
            if multiLiveManager.sessions.isEmpty {
                emptyMultiStage
            } else {
                multiLiveInlinePanel
            }
        }
    }

    private var emptyWatchStage: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "play.tv")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Text("아직 시청 중인 채널이 없습니다")
                .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("아래 팔로잉 시트에서 채널을 선택하세요")
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    ps.followingSheetState = .expanded
                }
            } label: {
                Label("팔로잉 시트 열기", systemImage: "rectangle.portrait.and.arrow.up")
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.16)))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    private var emptyMultiStage: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Text("멀티라이브 세션이 비어 있습니다")
                .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("팔로잉 시트의 Smart Queue에 채널을 담거나, 카드의 + 멀티 버튼으로 추가하세요")
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    func performSmartQueueBatchAdd() async {
        guard !smartQueueChannelIds.isEmpty else { return }

        var added = 0
        var duplicated = 0
        var notLive = 0
        var skippedMax = 0
        let queuedIds = smartQueueChannelIds

        for channelId in queuedIds {
            if multiLiveManager.sessions.contains(where: { $0.channelId == channelId }) {
                duplicated += 1
                continue
            }
            guard multiLiveManager.canAddSession else {
                skippedMax += 1
                continue
            }
            guard cachedLive.contains(where: { $0.channelId == channelId }) else {
                notLive += 1
                continue
            }

            await multiLiveManager.addSession(
                channelId: channelId,
                preferredEngine: appState.settingsStore.player.preferredEngine,
                presentationOverride: .embedded
            )
            added += 1
        }

        smartQueueChannelIds.removeAll()
        if added > 0 {
            // [2026-04-28] queue batch add 후 자동으로 멀티 모드로 전환
            applyHubModePreset(.multi)
            if autoSyncChatOnMultiLiveAdd {
                showMultiChat = true
            }
        }

        var tokens: [String] = []
        tokens.append("추가 \(added)")
        if duplicated > 0 { tokens.append("중복 \(duplicated)") }
        if notLive > 0 { tokens.append("오프라인 \(notLive)") }
        if skippedMax > 0 { tokens.append("한도초과 \(skippedMax)") }
        smartQueueBatchResult = tokens.joined(separator: " · ")
    }

    /// [2026-04-28 P2] 추천 알고리즘으로 Smart Queue 자동 채우기.
    /// 현재 라이브 중 후보를 점수화 (팔로잉/즐겨찾기/최근시청/카테고리/시청자 수) 후 상위 N개를 큐에 담는다.
    /// 이미 멀티라이브 세션에 추가된 채널은 제외, 남은 슬롯 수만큼만 채운다.
    func autoFillSmartQueue() {
        let alreadyAdded = Set(multiLiveManager.sessions.map(\.channelId))
        let remainingSlots = max(0, multiLiveManager.effectiveMaxSessions - multiLiveManager.sessions.count)
        guard remainingSlots > 0 else {
            smartQueueBatchResult = "세션 한도 초과 — 큐를 채울 수 없습니다"
            return
        }

        // 최근 시청 카테고리 추론 — recentChannelIds → cachedLive에서 카테고리 매핑
        let recentCategoriesArr = ps.recentChannelIds.compactMap { id -> String? in
            cachedLive.first(where: { $0.channelId == id })?.categoryName
        }
        let inputs = HomeRecommendationEngine.Inputs(
            candidates: cachedLive,
            followingChannelIds: Set(cachedLive.map(\.channelId)),
            favoriteChannelIds: ps.favoriteChannelIds,
            recentChannelIds: Set(ps.recentChannelIds),
            recentCategories: Set(recentCategoriesArr),
            alreadyWatchingChannelIds: alreadyAdded
        )
        let scored = HomeRecommendationEngine.score(inputs, limit: remainingSlots)
        let picked = scored.map(\.channel.channelId)

        // 기존 큐 + 추천 결과 (중복 제거, 순서 유지)
        var merged = smartQueueChannelIds
        for id in picked where !merged.contains(id) {
            merged.append(id)
            if merged.count >= remainingSlots { break }
        }
        smartQueueChannelIds = merged

        if picked.isEmpty {
            smartQueueBatchResult = "추천할 라이브 채널이 없습니다"
        } else {
            smartQueueBatchResult = "추천 \(picked.count)개를 큐에 담았습니다"
        }
    }

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
                                // 접이식 헤더
                                Button {
                                    withAnimation(DesignTokens.Animation.smooth) {
                                        ps.isOfflineSectionExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 0) {
                                        sectionHeader(
                                            icon: "moon.zzz.fill",
                                            title: "오프라인",
                                            count: totalOfflineCount,
                                            color: DesignTokens.Colors.textTertiary
                                        )
                                        Image(systemName: ps.isOfflineSectionExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                            .padding(.trailing, DesignTokens.Spacing.xs)
                                            .animation(DesignTokens.Animation.snappy, value: ps.isOfflineSectionExpanded)
                                    }
                                }
                                .buttonStyle(.plain)

                                if ps.isOfflineSectionExpanded {
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
                }

                Spacer(minLength: innerSpacing)
            }
            .padding(outerPad)
        }
        .onKeyPress(.leftArrow) {
            guard !isSearchFocused else { return .ignored }
            if livePageIndex > 0 {
                withAnimation(DesignTokens.Animation.gridPageTransition) { livePageIndex -= 1 }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            guard !isSearchFocused else { return .ignored }
            if livePageIndex < totalLivePages - 1 {
                withAnimation(DesignTokens.Animation.gridPageTransition) { livePageIndex += 1 }
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
            // [HiDPI/perf 2026-04-24] 1pt 높이 디바이더에 drawingGroup 은 비용 대비
            // 효과 0 (오프스크린 비트맵 생성 비용 > Metal 직접 렌더). 제거.
            .transition(.opacity)
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
        // [Fix 32] PowerAware: 프리페치는 항상 .background (배터리 보호)
        Task.detached(priority: PowerAwareTaskPriority.prefetch) {
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
        // [Fix 32] PowerAware: 프리페치는 항상 .background (배터리 보호)
        Task.detached(priority: PowerAwareTaskPriority.prefetch) {
            await ImageCacheService.shared.prefetchAndDecode(urls)
        }
    }
}
