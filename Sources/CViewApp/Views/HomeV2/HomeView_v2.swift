// MARK: - HomeView_v2.swift
// CViewApp - 신규 홈 화면 (정보구조 재배치 + 추천 + 최근/즐겨찾기)
//
// 정보구조 (docs/home-screen-redesign-analysis-2026-04-24.md 기준):
//   1. CommandBar — 인사 + 검색 진입 + 빠른 액션
//   2. (Optional) Cookie Login Banner
//   3. Hero Live Card — 1순위 추천
//   4. Personal Live Rail — 팔로잉 라이브 (기존 personalStatsSection 재사용)
//   5. Continue Watching — 최근 시청
//   6. Favorites — 즐겨찾기
//   7. Discover Recommendations — 점수 기반 추천 그리드
//   8. Top Channels — 인기 채널 (기존 topChannelsSection 재사용)
//   9. Compact Insights — 접이식 통계
//
// 기존 HomeView 는 보존되어 있고, MainContentView 의 @AppStorage("home.useV2") 로 전환된다.

import SwiftUI
import CViewCore
import CViewPersistence
import CViewPlayer
import CViewUI

struct HomeView_v2: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    // MARK: - Local State

    @State private var recentItems: [ChannelListData] = []
    @State private var favoriteItems: [ChannelListData] = []
    @State private var loadStoreTask: Task<Void, Never>?
    /// [Perf 2026-04-24] 홈 마운트 직후 저장소 reload + recompute + prefetch 를
    /// MenuTransitionGate 해제 이후로 지연시키기 위한 부트 태스크.
    @State private var bootTask: Task<Void, Never>?
    @State private var refreshing: Bool = false

    /// 간이 성능 모니터 패널 표시 여부 (CommandBar 의 ⌥M 버튼으로 토글, AppStorage 영속)
    @AppStorage("home.monitor.enabled") private var monitorEnabled: Bool = false

    /// 캐시된 추천 결과 — 입력 시그니처가 바뀌는 때며 재계산 (매 렌더 O(N log N) 회피)
    @State private var cachedRecommendations: [HomeRecommendationEngine.ScoredChannel] = []
    /// channelId → LiveChannelItem 맵 캐시 (이어보기 라이브 표시용)
    @State private var cachedLiveLookup: [String: LiveChannelItem] = [:]
    /// 추천/룩업 캐시 무효화용 시그니처 (정렬 입력의 카운트/해시)
    @State private var cacheSignature: Int = 0

    /// 탐색/인기 섹션 카테고리 필터 (nil = 전체)
    @State private var selectedCategory: String? = nil
    @State private var upNextSegment: UpNextSegment = .following
    @AppStorage("home.v2.upnext.segment") private var upNextSegmentRaw: String = UpNextSegment.following.rawValue
    @State private var showDataHealthDetail: Bool = false
    /// Discover 섹션 "더 보기" 펼침 상태
    @State private var discoverShowAll: Bool = false

    // MARK: - Layout Preferences (P2-1)
    @AppStorage("home.v2.show.hero")        private var prefShowHero: Bool = true
    @AppStorage("home.v2.show.personalLive") private var prefShowPersonalLive: Bool = true
    @AppStorage("home.v2.show.continue")    private var prefShowContinue: Bool = true
    @AppStorage("home.v2.show.discover")    private var prefShowDiscover: Bool = true
    @AppStorage("home.v2.show.top")         private var prefShowTop: Bool = true
    @AppStorage("home.v2.show.insights")    private var prefShowInsights: Bool = true
    @AppStorage("home.v2.show.activeMulti") private var prefShowActiveMulti: Bool = true
    @AppStorage("home.v2.density")          private var densityRaw: String = HomeCardDensity.comfortable.rawValue

    // MARK: - Derived

    /// 인사말 (HomeView 와 동일 규칙)
    private var greeting: String {
        let referenceDate = viewModel.liveChannelsCachedAt ?? Date()
        let hour = Calendar.current.component(.hour, from: referenceDate)
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "좋은 아침이에요"
        case 12..<18: timeGreeting = "좋은 오후에요"
        case 18..<22: timeGreeting = "좋은 저녁이에요"
        default: timeGreeting = "좋은 밤이에요"
        }
        if let nickname = appState.userNickname, !nickname.isEmpty {
            return "\(nickname) 님, \(timeGreeting)"
        }
        return timeGreeting
    }

    /// 캐시 무효화 시그니처 — 채널/팔로잉/멀티라이브/저장소 변화에만 반응
    private var currentSignature: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.allStatChannels.count)
        hasher.combine(viewModel.liveChannels.count)
        hasher.combine(viewModel.followingChannels.count)
        hasher.combine(recentItems.count)
        hasher.combine(favoriteItems.count)
        hasher.combine(appState.multiLiveManager.sessions.count)
        // 첫 채널 ID(정렬 안정성 변화 감지용) — 가벼운 fingerprint
        if let first = viewModel.allStatChannels.first?.channelId {
            hasher.combine(first)
        }
        return hasher.finalize()
    }

    private var density: HomeCardDensity {
        HomeCardDensity(rawValue: densityRaw) ?? .comfortable
    }

    private var heroHeight: CGFloat {
        switch density {
        case .compact: return 236
        case .comfortable: return 292
        case .spacious: return 336
        }
    }

    private var sectionSpacing: CGFloat {
        switch density {
        case .compact: return 12
        case .comfortable: return 16
        case .spacious: return 20
        }
    }

    private var discoverGridMinimum: CGFloat {
        switch density {
        case .compact: return 200
        case .comfortable: return 220
        case .spacious: return 250
        }
    }

    private var topGridMinimum: CGFloat {
        switch density {
        case .compact: return 210
        case .comfortable: return 230
        case .spacious: return 260
        }
    }

    private var queueLimit: Int {
        switch density {
        case .compact: return 6
        case .comfortable: return 7
        case .spacious: return 8
        }
    }

    private struct UpNextItem: Identifiable {
        let id: String
        let channel: LiveChannelItem
        let source: String
    }

    private enum UpNextSegment: String, CaseIterable, Identifiable {
        case following = "팔로잉"
        case favorites = "즐겨찾기"
        case recent = "최근"

        var id: String { rawValue }
    }

    private var upNextItemsBySegment: [UpNextSegment: [UpNextItem]] {
        var map: [UpNextSegment: [UpNextItem]] = [:]

        map[.following] = Array(
            viewModel.recentLiveFollowing
                .prefix(queueLimit)
                .map { .init(id: $0.channelId, channel: $0, source: "팔로잉 LIVE") }
        )

        var favorites: [UpNextItem] = []
        for item in favoriteItems {
            if let live = cachedLiveLookup[item.channelId] {
                favorites.append(.init(id: live.channelId, channel: live, source: "즐겨찾기"))
            }
            if favorites.count >= queueLimit { break }
        }
        map[.favorites] = favorites

        var recents: [UpNextItem] = []
        for item in recentItems {
            if let live = cachedLiveLookup[item.channelId] {
                recents.append(.init(id: live.channelId, channel: live, source: "최근 시청"))
            }
            if recents.count >= queueLimit { break }
        }
        map[.recent] = recents

        return map
    }

    private var currentUpNextItems: [UpNextItem] {
        upNextItemsBySegment[upNextSegment] ?? []
    }

    private enum HomeDataHealth {
        case loading
        case error(String)
        case stale
        case healthy

        var icon: String {
            switch self {
            case .loading: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.triangle.fill"
            case .stale: return "clock.badge.exclamationmark"
            case .healthy: return "checkmark.seal.fill"
            }
        }

        var label: String {
            switch self {
            case .loading: return "갱신 중"
            case .error: return "오류"
            case .stale: return "지연"
            case .healthy: return "정상"
            }
        }

        var tint: Color {
            switch self {
            case .loading: return DesignTokens.Colors.textSecondary
            case .error: return DesignTokens.Colors.warning
            case .stale: return DesignTokens.Colors.warning
            case .healthy: return DesignTokens.Colors.chzzkGreen
            }
        }

        var help: String {
            switch self {
            case .loading:
                return "라이브/통계 데이터를 새로 갱신하고 있어요"
            case let .error(msg):
                return "최근 통계 수집 오류: \(msg)"
            case .stale:
                return "통계 데이터가 오래되었어요. 새로고침을 권장합니다"
            case .healthy:
                return "데이터 상태가 안정적입니다"
            }
        }
    }

    private enum HomeDataIssueKind {
        case auth
        case network
        case rateLimited
        case server
        case unknown

        var label: String {
            switch self {
            case .auth: return "인증"
            case .network: return "네트워크"
            case .rateLimited: return "요청 제한"
            case .server: return "서버"
            case .unknown: return "일반"
            }
        }

        var recommendation: String {
            switch self {
            case .auth:
                return "쿠키 로그인을 다시 진행한 뒤 새로고침하세요"
            case .network:
                return "네트워크 연결 상태를 확인한 뒤 다시 시도하세요"
            case .rateLimited:
                return "짧게 대기한 후 다시 새로고침하는 것이 안전합니다"
            case .server:
                return "일시적인 서버 응답 문제일 수 있어 잠시 후 재시도하는 편이 좋습니다"
            case .unknown:
                return "문제가 반복되면 새로고침 후 다시 확인하세요"
            }
        }
    }

    private var dataHealth: HomeDataHealth {
        if refreshing || viewModel.isLoadingStats {
            return .loading
        }
        if let err = viewModel.statsLoadError, !err.isEmpty {
            return .error(err)
        }
        if let last = viewModel.allStatLastLoadedAt,
           Date().timeIntervalSince(last) > 60 * 10 {
            return .stale
        }
        return .healthy
    }

    private var dataIssueKind: HomeDataIssueKind? {
        guard case let .error(message) = dataHealth else { return nil }
        return classifyDataIssue(message)
    }

    private var shouldShowRefreshAction: Bool {
        switch dataHealth {
        case .loading, .healthy:
            return false
        case .error, .stale:
            return true
        }
    }

    private var upNextEmptyMessage: String {
        switch upNextSegment {
        case .following:
            return "라이브 중인 팔로잉 채널이 없어요"
        case .favorites:
            return "즐겨찾기한 채널 중 라이브가 없어요"
        case .recent:
            return "최근 시청 채널 중 라이브가 없어요"
        }
    }

    private var isUpNextLoading: Bool {
        (refreshing || viewModel.isLoadingStats) && currentUpNextItems.isEmpty
    }

    private var dataHealthUpdatedAtText: String {
        guard let at = viewModel.allStatLastLoadedAt else { return "기록 없음" }
        return Self.absoluteTimeFormatter.string(from: at)
    }

    private var upNextSegmentBinding: Binding<UpNextSegment> {
        Binding(
            get: { upNextSegment },
            set: { newValue in
                upNextSegment = newValue
                upNextSegmentRaw = newValue.rawValue
            }
        )
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let absoluteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    private var statusPanelSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    if !appState.isLoggedIn {
                        router.presentSheet(.login)
                    }
                } label: {
                    HomeV2StatusPill(
                        icon: appState.isLoggedIn ? "person.fill.checkmark" : "person.badge.key",
                        title: "로그인",
                        value: appState.isLoggedIn ? "연결됨" : "필요",
                        tint: appState.isLoggedIn ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.warning
                    )
                }
                .buttonStyle(.plain)
                .help(appState.isLoggedIn ? "로그인 상태" : "로그인 열기")

                Button {
                    if viewModel.needsCookieLogin {
                        router.presentSheet(.login)
                    }
                } label: {
                    HomeV2StatusPill(
                        icon: "key.fill",
                        title: "쿠키",
                        value: viewModel.needsCookieLogin ? "재로그인 필요" : "정상",
                        tint: viewModel.needsCookieLogin ? DesignTokens.Colors.warning : DesignTokens.Colors.chzzkGreen
                    )
                }
                .buttonStyle(.plain)
                .help(viewModel.needsCookieLogin ? "쿠키 로그인 열기" : "쿠키 상태 정상")

                Button {
                    triggerRefresh()
                } label: {
                    HomeV2StatusPill(
                        icon: "arrow.clockwise",
                        title: "추천 캐시",
                        value: cachedRecommendations.isEmpty ? "비어있음" : "준비됨",
                        tint: cachedRecommendations.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen
                    )
                }
                .buttonStyle(.plain)
                .help("라이브/추천 데이터 새로고침")

                Button {
                    showDataHealthDetail.toggle()
                } label: {
                    HomeV2StatusPill(
                        icon: dataHealth.icon,
                        title: "데이터",
                        value: dataHealth.label,
                        tint: dataHealth.tint
                    )
                }
                .buttonStyle(.plain)
                .help(dataHealth.help)
                .popover(isPresented: $showDataHealthDetail, arrowEdge: .bottom) {
                    dataHealthPopoverContent
                }

                if let cachedAt = viewModel.liveChannelsCachedAt {
                    HomeV2StatusPill(
                        icon: "clock",
                        title: "업데이트",
                        value: relativeTime(cachedAt),
                        tint: DesignTokens.Colors.textSecondary
                    )
                }
            }
        }
    }

    private func recomputeCachesIfNeeded() {
        let sig = currentSignature
        guard sig != cacheSignature else { return }
        cacheSignature = sig

        let candidates = viewModel.allStatChannels.isEmpty
            ? viewModel.liveChannels
            : viewModel.allStatChannels

        // liveLookup
        var lookup: [String: LiveChannelItem] = [:]
        lookup.reserveCapacity(candidates.count)
        for ch in candidates { lookup[ch.channelId] = ch }
        cachedLiveLookup = lookup

        // recent categories (최근 시청 채널 ↔ 라이브 매칭에서 카테고리 추출)
        var cats: Set<String> = []
        for r in recentItems.prefix(10) {
            if let live = lookup[r.channelId], let cat = live.categoryName, !cat.isEmpty {
                cats.insert(cat)
            }
        }

        let inputs = HomeRecommendationEngine.Inputs(
            candidates: candidates,
            followingChannelIds: Set(viewModel.followingChannels.map(\.channelId)),
            favoriteChannelIds: Set(favoriteItems.map(\.channelId)),
            recentChannelIds: Set(recentItems.map(\.channelId)),
            recentCategories: cats,
            alreadyWatchingChannelIds: Set(appState.multiLiveManager.sessions.map(\.channelId))
        )
        cachedRecommendations = HomeRecommendationEngine.score(inputs, limit: 12)

        // [ColdStart 2026-04-25] 점수 결과를 디스크에 영속 → 다음 부트의 첫 프레임에
        // Hero/Discover 가 placeholder 없이 즉시 그려진다. fire-and-forget.
        if let ds = appState.dataStore {
            let snapshot = cachedRecommendations
            // Task(@MainActor 상속) → snapshot/ds 모두 MainActor-isolated 로 안전.
            // 실제 인코딩은 store actor 내부에서 수행되므로 메인 스레드 점유 시간은 미미.
            Task {
                await HomeRecommendationCache.save(snapshot, store: ds)
            }
        }

        // 홈 카드 썸네일/아바타 사전 워밍 — 카드가 화면에 등장하기 전에 캐시 채움.
        // ImageCacheService 의 4-동시 게이트로 트래픽 제한, .utility 우선순위로 UI 비방해.
        // (recomputeCachesIfNeeded 는 데이터 변동 시에만 호출되므로 호출 빈도 자연 제한)
        var warming: [LiveChannelItem] = []
        warming.reserveCapacity(viewModel.recentLiveFollowing.count
            + viewModel.topChannels.count
            + cachedRecommendations.count)
        warming.append(contentsOf: cachedRecommendations.map(\.channel))
        warming.append(contentsOf: viewModel.recentLiveFollowing)
        warming.append(contentsOf: viewModel.topChannels)
        HomeThumbnailPrefetcher.prefetchLive(channels: warming)
        HomeThumbnailPrefetcher.prefetchPersisted(items: recentItems + favoriteItems)
    }

    // MARK: - Body

    var body: some View {
        // [hit-test fix 2026-04-24]
        // 이전엔 CommandBar 를 ScrollView 안 첫 행에 두었더니 모든 5개 버튼이
        // 클릭 액션 클로저까지 도달조차 못함 (NSLog 미출력으로 확인).
        // 원인 추정:
        //   (1) macOS 에서 .refreshable 이 ScrollView 상단에 invisible refresh
        //       control 을 배치 → 첫 행 hit-test 를 흡수.
        //   (2) AnimatedGradientText 의 .repeatForever 애니메이션이 매 프레임
        //       transaction 을 발생시켜 클릭 transaction 이 묻힐 가능성.
        // 해결: CommandBar 를 ScrollView 밖 sticky header 로 분리.
        VStack(spacing: 0) {
            // ── Sticky Command Bar (ScrollView 외부 — 항상 클릭 가능) ──
            HStack(spacing: DesignTokens.Spacing.xs) {
                HomeCommandBar(
                    greeting: greeting,
                    isRefreshing: refreshing,
                    monitorEnabled: monitorEnabled,
                    onToggleMonitor: { monitorEnabled.toggle() },
                    onRefresh: { triggerRefresh() }
                )
                HomeLayoutMenu()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.xl + 32)   // 타이틀바(28) 보정 포함
            .padding(.bottom, DesignTokens.Spacing.sm)
            .background {
                ZStack {
                    DesignTokens.Colors.background.opacity(0.96)
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.surfaceElevated.opacity(0.78),
                            DesignTokens.Colors.background.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                    statusPanelSection
                        .homeSectionAppear(index: 0)

                    // 2. Cookie login (필요 시 상단 노출)
                    if appState.isLoggedIn && viewModel.needsCookieLogin {
                        cookieLoginBannerInline
                            .homeSectionAppear(index: 1)
                    }

                    // 2-1. 활성 멀티라이브 세션 strip
                    if prefShowActiveMulti {
                        HomeActiveMultiLiveStrip(liveLookup: cachedLiveLookup)
                            .homeSectionAppear(index: 1)
                    }

                    // 3. Hero + Personal Queue
                    if prefShowHero, let hero = cachedRecommendations.first {
                        topFocusSection(hero: hero)
                            .homeSectionAppear(index: 2)
                    }

                    // 4. Personal Live (인라인 재구현)
                    if prefShowPersonalLive, appState.isLoggedIn {
                        personalLiveSection
                            .homeSectionAppear(index: 3)
                    }

                    // 5/6. Continue Watching + Favorites
                    if prefShowContinue {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: sectionSpacing) {
                                HomeContinueWatchingStrip(
                                    title: "이어보기",
                                    icon: "clock.arrow.circlepath",
                                    items: recentItems,
                                    liveLookup: cachedLiveLookup
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HomeContinueWatchingStrip(
                                    title: "즐겨찾기",
                                    icon: "star.fill",
                                    items: favoriteItems,
                                    liveLookup: cachedLiveLookup
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            VStack(alignment: .leading, spacing: sectionSpacing) {
                                HomeContinueWatchingStrip(
                                    title: "이어보기",
                                    icon: "clock.arrow.circlepath",
                                    items: recentItems,
                                    liveLookup: cachedLiveLookup
                                )
                                HomeContinueWatchingStrip(
                                    title: "즐겨찾기",
                                    icon: "star.fill",
                                    items: favoriteItems,
                                    liveLookup: cachedLiveLookup
                                )
                            }
                        }
                        .homeSectionAppear(index: 4)
                    }

                    // 7. Discover (rule-based recommendations)
                    if prefShowDiscover, cachedRecommendations.count > 1 {
                        discoverSection
                            .homeSectionAppear(index: 5)
                    }

                    // 8. Top Channels (인라인 재구현)
                    if prefShowTop {
                        topChannelsInlineSection
                            .homeSectionAppear(index: 6)
                    }

                    // 9. Compact Insights
                    if prefShowInsights {
                        HomeInsightsCompactStrip(
                            totalLive: viewModel.totalLiveChannelCount,
                            totalViewers: viewModel.totalViewers,
                            categoryCount: viewModel.categoryCount,
                            followingLive: viewModel.followingLiveCount
                        )
                        .homeSectionAppear(index: 7)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
            // [Perf 2026-04-24] .refreshable 제거.
            //   macOS 에는 pull-to-refresh UI 가 없어 사실상 dead UI 였지만
            //   SwiftUI 는 invisible scroll observer + refresh state coordinator 를
            //   ScrollView 에 부착 → 스크롤 이벤트마다 추가 hit-test/state 갱신.
            //   사용자에겐 이미 CommandBar 새로고침 버튼이 있어 기능 손실 없음.
        }   // outer VStack (sticky header + ScrollView)
        .contentBackground()
        .overlay(alignment: .topTrailing) {
            if monitorEnabled {
                HomeMonitorPanel(viewModel: viewModel)
                    // sticky CommandBar 아래에 위치하도록 (CommandBar height 약 92pt + 여유)
                    .padding(.top, 100)
                    .padding(.trailing, DesignTokens.Spacing.md)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(DesignTokens.Animation.fast, value: monitorEnabled)
        .onAppear {
            // [Perf 2026-04-24] 메뉴 전환 직후 첫 프레임과 겹치는 작업을 억제.
            //   onAppear 에서 이전엔 startAutoRefresh / scheduleStoreReload /
            //   recomputeCachesIfNeeded 를 동시 실행 → NavigationSplitView detail mount,
            //   HomeSectionAppear 애니메이션, 추천 점수 계산, prefetch launch 가
            //   같은 run loop 에 몽려 첫 stutter 의 주원인.
            //   아래로 분리:
            //     - startAutoRefresh: 즉시 시작해도 첫 task wakeup 은 시간 후이므로
            //       UI 에 영향 없음.
            //     - reloadStore + recompute + prefetch: 380ms 지연 → MenuTransitionGate(350ms)
            //       해제 + 첫 프레임 렌더 완료 후에 실행.
            viewModel.startAutoRefresh()
            // [ColdStart 2026-04-25] 380ms 지연된 reloadStore 가 끝나기 전에
            // 디스크 캐시(cache.scoredRecommendations)를 즉시 hydrate → 첫 프레임에
            // Hero/Discover 가 placeholder 없이 그려진다. recompute 가 끝나면 자연스럽게
            // 덮어쓴다(stale-while-revalidate).
            if cachedRecommendations.isEmpty, let ds = appState.dataStore {
                Task { @MainActor in
                    if let cached = await HomeRecommendationCache.load(store: ds),
                       cachedRecommendations.isEmpty {
                        cachedRecommendations = cached
                    }
                }
            }
            bootTask?.cancel()
            bootTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
                await reloadStore()
                // reloadStore 가 끝에서 recomputeCachesIfNeeded 를 호출하므로
                // 추가 호출 불필요.
            }
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            loadStoreTask?.cancel()
            bootTask?.cancel()
            // [Perf 2026-04-24] 홈을 떠날 때 진행 중이던 prefetch 도 실효성 없으므로
            // 제거 — 다음 메뉴의 main actor 를 점유하지 않도록.
            HomeThumbnailPrefetcher.cancel()
        }
        // [Perf 2026-04-24] 6개 onChange → 단일 signature onChange 통합.
        // viewModel.lightRefresh() 가 liveChannels/followingChannels/allStatChannels 를
        // 같은 프레임에 갱신하면 이전엔 6개 콜백이 동시 발화 → currentSignature
                // 의 7회 hash combine 을 6번 재계산했음. SwiftUI 의 의존성 추적도 6배 단일
        // signature 값 변화에만 반응하도록 하여 메인 프레임 콜백을 1회로 감소.
        .onChange(of: currentSignature) { _, _ in
            recomputeCachesIfNeeded()
        }
    }

    // MARK: - Discover Section

    @ViewBuilder
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HomeV2SectionHeader(
                icon: "sparkles",
                title: "당신을 위한 추천",
                subtitle: "팔로잉 / 즐겨찾기 / 최근 시청 기반"
            )

            // 카테고리 칩
            HomeCategoryChips(
                channels: viewModel.allStatChannels.isEmpty ? viewModel.liveChannels : viewModel.allStatChannels,
                selected: $selectedCategory
            )
            .onChange(of: selectedCategory) {
                discoverShowAll = false
            }

            let filtered = filteredRecommendations
            if filtered.isEmpty {
                HStack {
                    Spacer()
                    Text(selectedCategory.map { "'\($0)' 카테고리에 추천이 없어요" } ?? "추천이 없어요")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.lg)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            } else {
                // 초기 노출 6개, 더 보기 시 전체 표시
                let initialCount = 6
                let visibleItems = discoverShowAll ? filtered : Array(filtered.prefix(initialCount))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: discoverGridMinimum, maximum: 340), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(visibleItems) { item in
                        HomeRecommendedCard(item: item)
                            .liveCardActions(
                                channelId: item.channel.channelId,
                                channelName: item.channel.channelName,
                                isLive: true
                            )
                    }
                }
                if !discoverShowAll, filtered.count > initialCount {
                    Button {
                        withAnimation(DesignTokens.Animation.smooth) {
                            discoverShowAll = true
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Text("더 보기 (\(filtered.count - initialCount)개)")
                                .font(DesignTokens.Typography.captionSemibold)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                } else if discoverShowAll, filtered.count > initialCount {
                    Button {
                        withAnimation(DesignTokens.Animation.smooth) {
                            discoverShowAll = false
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Text("접기")
                                .font(DesignTokens.Typography.captionSemibold)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Hero 는 그대로 두고 (🎯 🚫 카테고리 필터 적용 안 함), 나머지는 선택 카테고리로 필터
    private var filteredRecommendations: [HomeRecommendationEngine.ScoredChannel] {
        let tail = Array(cachedRecommendations.dropFirst())
        guard let cat = selectedCategory else { return Array(tail.prefix(11)) }
        return tail.filter { $0.channel.categoryName == cat }.prefix(11).map { $0 }
    }

    // MARK: - Cookie Login Banner (compact inline 버전)

    private var cookieLoginBannerInline: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "key.fill")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("라이브 조회에는 네이버 로그인이 필요합니다")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("로그인 → '네이버 로그인' 탭을 선택하세요")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Button("로그인") { router.presentSheet(.login) }
                .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        }
    }

    // MARK: - Legacy Section Bridge (제거됨 — 인라인 재구현 사용)

    private func triggerPrefetch(_ channelId: String) {
        if let svc = appState.hlsPrefetchService {
            Task { await svc.prefetch(channelId: channelId) }
        }
    }

    @ViewBuilder
    private var personalLiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HomeV2SectionHeader(
                icon: "heart.fill",
                title: "팔로잉 라이브",
                subtitle: viewModel.followingLiveCount > 0
                    ? "\(viewModel.followingLiveCount)명 라이브 중 · \(viewModel.followingLiveRate)%"
                    : nil
            )
            if viewModel.recentLiveFollowing.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(DesignTokens.Typography.subhead)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("라이브 중인 팔로잉 채널이 없어요")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.lg)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: discoverGridMinimum, maximum: 340), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(viewModel.recentLiveFollowing) { channel in
                        MiniChannelCard(channel: channel, onHoverChange: { hovering in
                            if hovering { triggerPrefetch(channel.channelId) }
                        })
                        .onTapGesture {
                            router.navigate(to: .live(channelId: channel.channelId))
                        }
                        .liveCardActions(
                            channelId: channel.channelId,
                            channelName: channel.channelName,
                            isLive: true
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topChannelsInlineSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HomeV2SectionHeader(
                icon: "flame.fill",
                title: "인기 채널",
                trailing: AnyView(
                    Button {
                        router.navigate(to: .following)
                    } label: {
                        HStack(spacing: 3) {
                            Text("전체보기")
                                .font(DesignTokens.Typography.captionMedium)
                            Image(systemName: "chevron.right")
                                .font(DesignTokens.Typography.microSemibold)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                )
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: topGridMinimum, maximum: 360), spacing: DesignTokens.Spacing.sm)],
                spacing: DesignTokens.Spacing.sm
            ) {
                ForEach(filteredTopChannels) { channel in
                    MiniChannelCard(channel: channel, onHoverChange: { hovering in
                        if hovering { triggerPrefetch(channel.channelId) }
                    })
                    .onTapGesture {
                        router.navigate(to: .live(channelId: channel.channelId))
                    }
                    .liveCardActions(
                        channelId: channel.channelId,
                        channelName: channel.channelName,
                        isLive: true
                    )
                }
            }
        }
    }

    /// 선택 카테고리가 있으면 인기 채널도 필터
    private var filteredTopChannels: [LiveChannelItem] {
        guard let cat = selectedCategory else { return viewModel.topChannels }
        return viewModel.topChannels.filter { $0.categoryName == cat }
    }

    // MARK: - Refresh

    @ViewBuilder
    private func topFocusSection(hero: HomeRecommendationEngine.ScoredChannel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: sectionSpacing) {
                HomeHeroLiveCard(item: hero, height: heroHeight)
                    .frame(maxWidth: .infinity)

                upNextQueuePanel
                    .frame(width: 360)
            }

            VStack(alignment: .leading, spacing: sectionSpacing) {
                HomeHeroLiveCard(item: hero, height: heroHeight)
                upNextQueuePanel
            }
        }
    }

    private var upNextQueuePanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HomeV2SectionHeader(
                icon: "rectangle.stack.fill",
                title: "Up Next Queue",
                subtitle: upNextSegment.rawValue
            )

            Picker("Up Next Segment", selection: upNextSegmentBinding) {
                ForEach(UpNextSegment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .onAppear {
                upNextSegment = UpNextSegment(rawValue: upNextSegmentRaw) ?? .following
            }
            .onChange(of: upNextSegmentRaw) { _, newValue in
                let restored = UpNextSegment(rawValue: newValue) ?? .following
                if restored != upNextSegment {
                    upNextSegment = restored
                }
            }

            ZStack {
                if isUpNextLoading {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(0..<4, id: \.self) { _ in
                            UpNextSkeletonRow()
                        }
                    }
                    .transition(.opacity)
                } else if currentUpNextItems.isEmpty {
                    HStack {
                        Spacer()
                        Text(upNextEmptyMessage)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, DesignTokens.Spacing.lg)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .transition(.opacity)
                } else {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(currentUpNextItems) { entry in
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Button {
                                    router.navigate(to: .live(channelId: entry.channel.channelId))
                                } label: {
                                    HStack(spacing: DesignTokens.Spacing.xs) {
                                        CachedAsyncImage(url: URL(string: entry.channel.channelImageUrl ?? "")) {
                                            Circle().fill(DesignTokens.Colors.surfaceBase)
                                        }
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .overlay {
                                            Circle().strokeBorder(DesignTokens.Colors.live.opacity(0.45), lineWidth: 1)
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(entry.channel.channelName)
                                                .font(DesignTokens.Typography.captionSemibold)
                                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                                .lineLimit(1)
                                            Text(entry.source)
                                                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    router.navigate(to: .live(channelId: entry.channel.channelId))
                                } label: {
                                    UpNextCircleActionButton(
                                        systemName: "play.fill",
                                        fgColor: .white,
                                        bgColor: DesignTokens.Colors.live.opacity(0.85)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    Task { @MainActor in
                                        await appState.multiLiveManager.addSession(
                                            channelId: entry.channel.channelId,
                                            presentationOverride: .embedded
                                        )
                                    }
                                } label: {
                                    UpNextCircleActionButton(
                                        systemName: "plus",
                                        fgColor: DesignTokens.Colors.chzzkGreen,
                                        bgColor: DesignTokens.Colors.chzzkGreen.opacity(0.14)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("멀티라이브에 추가")
                            }
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                    }
                    .id(upNextSegment)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                }
            }
            .animation(DesignTokens.Animation.smooth, value: upNextSegment)
            .animation(DesignTokens.Animation.fast, value: isUpNextLoading)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private var dataHealthPopoverContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: dataHealth.icon)
                    .foregroundStyle(dataHealth.tint)
                Text("데이터 상태: \(dataHealth.label)")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }

            Text(dataHealth.help)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                dataHealthRow(label: "최근 갱신", value: dataHealthUpdatedAtText)
                dataHealthRow(label: "통계 로딩", value: viewModel.isLoadingStats ? "진행 중" : "대기")
                dataHealthRow(label: "로컬 새로고침", value: refreshing ? "진행 중" : "대기")
                if let issue = dataIssueKind {
                    dataHealthRow(label: "오류 유형", value: issue.label)
                }
            }

            if let issue = dataIssueKind {
                VStack(alignment: .leading, spacing: 6) {
                    Text("권장 조치")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(issue.recommendation)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                if let issue = dataIssueKind, issue == .auth || viewModel.needsCookieLogin {
                    Button("로그인 열기") {
                        showDataHealthDetail = false
                        router.presentSheet(.login)
                    }
                    .controlSize(.small)
                }

                if shouldShowRefreshAction {
                    Button("지금 새로고침") {
                        showDataHealthDetail = false
                        triggerRefresh()
                    }
                    .controlSize(.small)
                }

                Button("닫기") {
                    showDataHealthDetail = false
                }
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: 300, alignment: .leading)
    }

    private func dataHealthRow(label: String, value: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func triggerRefresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { @MainActor in
            await viewModel.refresh()
            await reloadStore()
            refreshing = false
        }
    }

    private func reloadStore() async {
        guard let ds = appState.dataStore else { return }
        let recents = (try? await ds.fetchRecentItems(limit: 20)) ?? []
        let favs = (try? await ds.fetchFavoriteItems()) ?? []
        recentItems = recents
        favoriteItems = favs
        recomputeCachesIfNeeded()
    }

    private func relativeTime(_ d: Date) -> String {
        Self.relativeTimeFormatter.localizedString(for: d, relativeTo: Date())
    }

    private func classifyDataIssue(_ message: String) -> HomeDataIssueKind {
        let lowercased = message.lowercased()

        if lowercased.contains("cookie")
            || lowercased.contains("login")
            || lowercased.contains("auth")
            || lowercased.contains("401")
            || message.contains("로그인")
            || message.contains("인증") {
            return .auth
        }

        if lowercased.contains("timeout")
            || lowercased.contains("network")
            || lowercased.contains("offline")
            || lowercased.contains("dns")
            || lowercased.contains("connection")
            || message.contains("네트워크")
            || message.contains("연결")
            || message.contains("타임아웃") {
            return .network
        }

        if lowercased.contains("429")
            || lowercased.contains("rate")
            || lowercased.contains("too many")
            || message.contains("요청이 많")
            || message.contains("제한") {
            return .rateLimited
        }

        if lowercased.contains("500")
            || lowercased.contains("502")
            || lowercased.contains("503")
            || lowercased.contains("server")
            || message.contains("서버") {
            return .server
        }

        return .unknown
    }
}

private struct UpNextCircleActionButton: View {
    let systemName: String
    let fgColor: Color
    let bgColor: Color
    @State private var hovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(fgColor)
            .frame(width: 24, height: 24)
            .background(bgColor, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(hovered ? fgColor.opacity(0.4) : .clear, lineWidth: 0.8)
            }
            .scaleEffect(hovered ? 1.08 : 1.0)
            .onHover { hovering in
                hovered = hovering
            }
            .animation(DesignTokens.Animation.fast, value: hovered)
    }
}

private struct UpNextSkeletonRow: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(DesignTokens.Colors.surfaceBase)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.Colors.surfaceBase)
                    .frame(height: 9)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.Colors.surfaceBase.opacity(0.7))
                    .frame(width: 72, height: 8)
            }

            Spacer()

            Circle()
                .fill(DesignTokens.Colors.surfaceBase)
                .frame(width: 24, height: 24)
            Circle()
                .fill(DesignTokens.Colors.surfaceBase)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .redacted(reason: .placeholder)
    }
}
