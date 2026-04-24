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

    /// channelId → LiveChannelItem (스트립 라이브 표시용)
    private var liveLookup: [String: LiveChannelItem] {
        var dict: [String: LiveChannelItem] = [:]
        for ch in viewModel.allStatChannels.isEmpty ? viewModel.liveChannels : viewModel.allStatChannels {
            dict[ch.channelId] = ch
        }
        return dict
    }

    /// 추천 점수 계산
    private var recommendations: [HomeRecommendationEngine.ScoredChannel] {
        let candidates = viewModel.allStatChannels.isEmpty
            ? viewModel.liveChannels
            : viewModel.allStatChannels
        let inputs = HomeRecommendationEngine.Inputs(
            candidates: candidates,
            followingChannelIds: Set(viewModel.followingChannels.map(\.channelId)),
            favoriteChannelIds: Set(favoriteItems.map(\.channelId)),
            recentChannelIds: Set(recentItems.map(\.channelId)),
            recentCategories: extractRecentCategories(),
            alreadyWatchingChannelIds: Set(appState.multiLiveManager.sessions.map(\.channelId))
        )
        return HomeRecommendationEngine.score(inputs, limit: 12)
    }

    /// 최근 시청 채널의 카테고리 (라이브 매칭이 있을 때)
    private func extractRecentCategories() -> Set<String> {
        var cats: Set<String> = []
        for r in recentItems.prefix(10) {
            if let live = liveLookup[r.channelId], let cat = live.categoryName, !cat.isEmpty {
                cats.insert(cat)
            }
        }
        return cats
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // 1. Command Bar
                HomeCommandBar(
                    greeting: greeting,
                    isRefreshing: refreshing,
                    onRefresh: { triggerRefresh() }
                )

                // 2. Cookie login (필요 시 상단 노출)
                if appState.isLoggedIn && viewModel.needsCookieLogin {
                    cookieLoginBannerInline
                }

                // 3. Hero
                if let hero = recommendations.first {
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
                        liveLookup: liveLookup
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HomeContinueWatchingStrip(
                        title: "즐겨찾기",
                        icon: "star.fill",
                        items: favoriteItems,
                        liveLookup: liveLookup
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 7. Discover (rule-based recommendations)
                if recommendations.count > 1 {
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
        .refreshable {
            await viewModel.refresh()
            await reloadStore()
        }
        .onAppear {
            viewModel.startAutoRefresh()
            scheduleStoreReload()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            loadStoreTask?.cancel()
        }
        .animation(DesignTokens.Animation.smooth, value: recommendations.count)
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
                ForEach(Array(recommendations.dropFirst().prefix(11))) { item in
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
    }
}
