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

    // MARK: - Layout Preferences (P2-1)
    @AppStorage("home.v2.show.hero")        private var prefShowHero: Bool = true
    @AppStorage("home.v2.show.personalLive") private var prefShowPersonalLive: Bool = true
    @AppStorage("home.v2.show.continue")    private var prefShowContinue: Bool = true
    @AppStorage("home.v2.show.discover")    private var prefShowDiscover: Bool = true
    @AppStorage("home.v2.show.top")         private var prefShowTop: Bool = true
    @AppStorage("home.v2.show.insights")    private var prefShowInsights: Bool = true
    @AppStorage("home.v2.show.activeMulti") private var prefShowActiveMulti: Bool = true

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
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // 1. Command Bar
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

                // 3. Hero
                if prefShowHero, let hero = cachedRecommendations.first {
                    HomeHeroLiveCard(item: hero)
                        .homeSectionAppear(index: 2)
                }

                // 4. Personal Live (인라인 재구현)
                if prefShowPersonalLive, appState.isLoggedIn {
                    personalLiveSection
                        .homeSectionAppear(index: 3)
                }

                // 5/6. Continue Watching + Favorites
                if prefShowContinue {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
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
            .padding(DesignTokens.Spacing.xl)
        }
        .contentBackground()
        .overlay(alignment: .topTrailing) {
            if monitorEnabled {
                HomeMonitorPanel(viewModel: viewModel)
                    // CommandBar(아이콘 버튼 row) 아래로 내려서 상단 버튼 클릭을 막지 않도록 한다.
                    // (이전: .padding(.top, .md) 만 두어 우상단 검색바/멀티라이브/모니터/새로고침/편집 버튼들과
                    //  hit-test 가 겹쳐서 버튼이 "눌러도 반응 없음" 상태로 보였음)
                    .padding(.top, 64)
                    .padding(.trailing, DesignTokens.Spacing.md)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(DesignTokens.Animation.fast, value: monitorEnabled)
        .refreshable {
            await viewModel.refresh()
            await reloadStore()
            recomputeCachesIfNeeded()
        }
        .onAppear {
            viewModel.startAutoRefresh()
            scheduleStoreReload()
            recomputeCachesIfNeeded()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            loadStoreTask?.cancel()
        }
        // 캐시 무효화 트리거 — 데이터 변동 시에만 재계산
        .onChange(of: viewModel.allStatChannels.count) { _, _ in recomputeCachesIfNeeded() }
        .onChange(of: viewModel.liveChannels.count) { _, _ in recomputeCachesIfNeeded() }
        .onChange(of: viewModel.followingChannels.count) { _, _ in recomputeCachesIfNeeded() }
        .onChange(of: recentItems.count) { _, _ in recomputeCachesIfNeeded() }
        .onChange(of: favoriteItems.count) { _, _ in recomputeCachesIfNeeded() }
        .onChange(of: appState.multiLiveManager.sessions.count) { _, _ in recomputeCachesIfNeeded() }
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(filtered) { item in
                        HomeRecommendedCard(item: item)
                            .liveCardActions(
                                channelId: item.channel.channelId,
                                channelName: item.channel.channelName,
                                isLive: true
                            )
                    }
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
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DesignTokens.Spacing.sm)],
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
                columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: DesignTokens.Spacing.sm)],
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

    private func triggerRefresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { @MainActor in
            await viewModel.refresh()
            await reloadStore()
            refreshing = false
        }
    }

    private func scheduleStoreReload() {
        loadStoreTask?.cancel()
        loadStoreTask = Task { @MainActor in
            await reloadStore()
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
}
