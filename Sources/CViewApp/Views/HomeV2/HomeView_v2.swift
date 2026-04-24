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

    /// 캐시된 추천 결과 — 입력 시그니처가 바뀔 때만 재계산 (매 렌더 O(N log N) 회피)
    @State private var cachedRecommendations: [HomeRecommendationEngine.ScoredChannel] = []
    /// channelId → LiveChannelItem 맵 캐시 (이어보기 라이브 표시용)
    @State private var cachedLiveLookup: [String: LiveChannelItem] = [:]
    /// 추천/룩업 캐시 무효화용 시그니처 (정렬 입력의 카운트/해시)
    @State private var cacheSignature: Int = 0

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
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // 1. Command Bar
                HomeCommandBar(
                    greeting: greeting,
                    isRefreshing: refreshing,
                    monitorEnabled: monitorEnabled,
                    onToggleMonitor: { monitorEnabled.toggle() },
                    onRefresh: { triggerRefresh() }
                )

                // 2. Cookie login (필요 시 상단 노출)
                if appState.isLoggedIn && viewModel.needsCookieLogin {
                    cookieLoginBannerInline
                }

                // 3. Hero
                if let hero = cachedRecommendations.first {
                    HomeHeroLiveCard(item: hero)
                }

                // 4. Personal Live (인라인 재구현)
                if appState.isLoggedIn {
                    personalLiveSection
                }

                // 5/6. Continue Watching + Favorites
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

                // 7. Discover (rule-based recommendations)
                if cachedRecommendations.count > 1 {
                    discoverSection
                }

                // 8. Top Channels (인라인 재구현)
                topChannelsInlineSection

                // 9. Compact Insights
                HomeInsightsCompactStrip(
                    totalLive: viewModel.totalLiveChannelCount,
                    totalViewers: viewModel.totalViewers,
                    categoryCount: viewModel.categoryCount,
                    followingLive: viewModel.followingLiveCount
                )
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .contentBackground()
        .overlay(alignment: .topTrailing) {
            if monitorEnabled {
                HomeMonitorPanel(viewModel: viewModel)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.trailing, DesignTokens.Spacing.md)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
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
        .animation(DesignTokens.Animation.smooth, value: cachedRecommendations.count)
        .animation(DesignTokens.Animation.fast, value: monitorEnabled)
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DesignTokens.Spacing.sm)],
                spacing: DesignTokens.Spacing.sm
            ) {
                ForEach(Array(cachedRecommendations.dropFirst().prefix(11))) { item in
                    HomeRecommendedCard(item: item)
                }
            }
        }
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
                ForEach(viewModel.topChannels) { channel in
                    MiniChannelCard(channel: channel, onHoverChange: { hovering in
                        if hovering { triggerPrefetch(channel.channelId) }
                    })
                    .onTapGesture {
                        router.navigate(to: .live(channelId: channel.channelId))
                    }
                }
            }
        }
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
