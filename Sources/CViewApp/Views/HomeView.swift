// MARK: - HomeView.swift
// CViewApp - 홈 대시보드 (Minimal Monochrome)
// 통계 카드 + Swift Charts + 인기 채널 그리드

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI

// MARK: - Home Dashboard View

struct HomeView: View {
    
    @Bindable var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
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
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // 1. Header
                dashboardHeader

                // 2. Stat Cards (skeleton when loading with no data)
                if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty && viewModel.liveChannels.isEmpty {
                    skeletonStatCards
                } else {
                    statCardsGrid
                }

                // 3. Charts (skeleton when loading)
                if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty {
                    skeletonChartsSection
                } else {
                    chartsSection
                }

                // 4. Analytics (카테고리 분포 + 시청자 분포)
                if !(viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty) {
                    analyticsSection
                }

                // 5. Metrics Server Section
                if viewModel.isMetricsServerOnline {
                    metricsServerSection
                }

                // 6. Personal Stats (Following)
                if appState.isLoggedIn {
                    personalStatsSection
                }

                // 7. Top Channels Grid
                topChannelsSection
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .contentBackground()
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Prefetch Helper

    /// 채널 카드 호버 시 HLS 매니페스트 프리페치를 비동기로 트리거
    private func triggerPrefetch(channelId: String) {
        if let service = appState.hlsPrefetchService {
            Task { await service.prefetch(channelId: channelId) }
        }
    }
    
    // MARK: - 1. Dashboard Header

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Hero greeting row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(Date(), format: .dateTime.year().month().day().weekday(.wide))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if viewModel.isLoadingStats {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("수집 중")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } else if let cachedAt = viewModel.allStatCachedAt ?? viewModel.liveChannelsCachedAt {
                            dataFreshnessBadge(cachedAt: cachedAt)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
                    // 라이브 요약 카드
                    if viewModel.totalLiveChannelCount > 0 {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Circle().fill(DesignTokens.Colors.live).frame(width: 6, height: 6)
                                    Text("\(viewModel.totalLiveChannelCount)채널")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                Text("시청자 \(formatLargeNumber(viewModel.totalViewers))명")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Divider().frame(height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("평균")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(formatLargeNumber(viewModel.averageViewers))
                                    .font(.system(size: 14, weight: .bold).monospaced())
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(DesignTokens.Colors.live.opacity(0.2), lineWidth: 0.5)
                        }
                    }

                    // 새로고침 버튼
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.fill.tertiary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(viewModel.isLoading ? DesignTokens.Animation.loadingSpin : .default, value: viewModel.isLoading)
                }
            }

            Divider()
        }
    }

    private func dataFreshnessBadge(cachedAt: Date) -> some View {
        let age = -cachedAt.timeIntervalSinceNow
        let isStale = age > 300  // 5분 이상
        let label: String = {
            if age < 60 { return "방금 업데이트" }
            let mins = Int(age) / 60
            return "\(mins)분 전 캐시"
        }()
        return HStack(spacing: 4) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(isStale ? Color.orange : Color.secondary)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(.fill.quaternary)
        .clipShape(Capsule())
    }

    // MARK: - 2. Stat Cards

    private var statCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
            ],
            spacing: DesignTokens.Spacing.md
        ) {
            DashboardStatCard(
                title: "라이브 채널",
                value: viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty
                    ? "\(viewModel.liveChannels.count)+"
                    : "\(viewModel.totalLiveChannelCount)",
                icon: "dot.radiowaves.left.and.right",
                subtitle: "\(viewModel.categoryCount)개 카테고리"
            )

            DashboardStatCard(
                title: "총 시청자",
                value: formatLargeNumber(viewModel.totalViewers),
                icon: "person.2",
                subtitle: "최고 \(formatLargeNumber(viewModel.topThreeChannels.first?.viewerCount ?? 0))명"
            )

            DashboardStatCard(
                title: "평균 시청자",
                value: formatLargeNumber(viewModel.averageViewers),
                icon: "chart.bar",
                subtitle: "중앙값 \(formatLargeNumber(viewModel.medianViewers))명"
            )

            if viewModel.isMetricsServerOnline {
                DashboardStatCard(
                    title: "서버 수신",
                    value: formatLargeNumber(viewModel.serverTotalReceived),
                    icon: "server.rack",
                    subtitle: "\(viewModel.serverChannelStats.count)개 채널 활성",
                    accentColor: DesignTokens.Colors.chzzkGreen
                )
            } else {
                DashboardStatCard(
                    title: "카테고리",
                    value: "\(viewModel.categoryCount)",
                    icon: "square.grid.2x2",
                    subtitle: "전체 \(viewModel.totalLiveChannelCount)채널"
                )
            }
        }
    }
    
    // MARK: - 3. Charts Section

    private var chartsSection: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ViewerTrendChart(history: viewModel.viewerHistory)
                .frame(maxWidth: .infinity)

            CategoryBarChart(categories: viewModel.topCategories)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 4. Analytics Section (도넛차트 + 시청자 분포)

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 섹션 헤더
            sectionHeader(title: "스트리밍 분석", subtitle: viewModel.categoryTypeDistribution.isEmpty ? nil : "총 \(viewModel.totalLiveChannelCount)채널")

            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                CategoryTypeDonutChart(distribution: viewModel.categoryTypeDistribution)
                    .frame(maxWidth: .infinity)

                ViewerDistributionChart(
                    buckets: viewModel.viewerBuckets,
                    medianViewers: viewModel.medianViewers
                )
                .frame(maxWidth: .infinity)
            }

            // TOP 3 랭킹 채널
            if !viewModel.topThreeChannels.isEmpty {
                topThreeSection
            }
        }
    }

    // TOP 3 랭킹 채널 카드
    private var topThreeSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionHeader(title: "시청자 TOP 3", subtitle: nil)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(viewModel.topThreeChannels.enumerated()), id: \.element.id) { index, channel in
                    topRankCard(rank: index + 1, channel: channel)
                        .onHover { hovering in
                            if hovering { triggerPrefetch(channelId: channel.channelId) }
                        }
                        .customCursor(.pointingHand)
                        .onTapGesture {
                            router.navigate(to: .live(channelId: channel.channelId))
                        }
                }
            }
        }
    }

    private func topRankCard(rank: Int, channel: LiveChannelItem) -> some View {
        let rankColors: [Color] = [.yellow, Color(red: 0.75, green: 0.75, blue: 0.78), DesignTokens.Colors.accentOrange]
        let rankColor = rank <= 3 ? rankColors[rank - 1] : DesignTokens.Colors.textTertiary
        let rankEmoji = rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉"

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 상단: 순위 + 아바타
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 순위 뱃지 (큰 숫자)
                Text(rankEmoji)
                    .font(.system(size: 20))

                Spacer()

                // 채널 아바타
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(rankColor.opacity(0.6), lineWidth: 2)
                }
                .shadow(color: rankColor.opacity(0.3), radius: 6, x: 0, y: 2)
            }

            // 채널 이름
            Text(channel.channelName)
                .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            // 시청자 수
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(DesignTokens.Typography.custom(size: 10))
                Text(channel.formattedViewerCount)
                    .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(rankColor)

            // 카테고리
            if let cat = channel.categoryName {
                Text(cat)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(rankColor.opacity(0.1), in: Capsule())
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(rankColor.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            LinearGradient(
                                colors: [rankColor.opacity(0.3), rankColor.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
    
    // MARK: - 5. Metrics Server Section

    private var metricsServerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Header
            HStack {
                sectionHeader(title: "메트릭 서버", subtitle: nil)
                if let lastUpdate = viewModel.serverLastUpdate {
                    Text(lastUpdate, format: .dateTime.hour().minute().second())
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            // Server Stats Cards Row
            HStack(spacing: DesignTokens.Spacing.sm) {
                serverMiniStat(icon: "clock", title: "업타임", value: viewModel.formattedUptime)
                serverMiniStat(icon: "number", title: "총 수신", value: formatLargeNumber(viewModel.serverTotalReceived))
                serverMiniStat(icon: "play.circle", title: "활성 채널", value: "\(viewModel.serverChannelStats.count)")
                
                if let webLat = viewModel.avgWebLatency {
                    serverMiniStat(icon: "globe", title: "웹 레이턴시", value: String(format: "%.0fms", webLat))
                }
                if let appLat = viewModel.avgAppLatency {
                    serverMiniStat(icon: "desktopcomputer", title: "앱 레이턴시", value: String(format: "%.0fms", appLat))
                }
            }
            
            // Charts Row
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                LatencyComparisonChart(history: viewModel.latencyHistory)
                    .frame(maxWidth: .infinity)
                
                ServerChannelStatsView(channelStats: viewModel.serverChannelStats)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func serverMiniStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(DesignTokens.Typography.custom(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.sm)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }
    
    // MARK: - 6. Personal Stats

    private var personalStatsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader(title: "내 팔로잉", subtitle: nil)

                // 라이브 비율 배지
                if viewModel.followingChannels.count > 0 {
                    HStack(spacing: 6) {
                        if viewModel.followingLiveCount > 0 {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 6, height: 6)
                                Text("\(viewModel.followingLiveCount)명 라이브 중")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.live.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Text("라이브 율 \(viewModel.followingLiveRate)%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if viewModel.needsCookieLogin {
                cookieLoginBanner
            } else if viewModel.recentLiveFollowing.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(DesignTokens.Typography.title3)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("라이브 중인 팔로잉 채널이 없습니다")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.lg)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(viewModel.recentLiveFollowing) { channel in
                        MiniChannelCard(channel: channel)
                            .onHover { hovering in
                                if hovering { triggerPrefetch(channelId: channel.channelId) }
                            }
                            .customCursor(.pointingHand)
                            .onTapGesture {
                                router.navigate(to: .live(channelId: channel.channelId))
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - Cookie Login Banner
    
    private var cookieLoginBanner: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "key.fill")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("팔로잉 조회에는 네이버 로그인이 필요합니다")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("로그인 → '네이버 로그인' 탭을 선택하세요")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            
            Spacer()
            
            Button("로그인") {
                router.presentSheet(.login)
            }
            .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        }
    }
    
    // MARK: - 7. Top Channels

    private var topChannelsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader(title: "인기 채널", subtitle: nil)
                
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
            }
            
            if viewModel.isLoading && viewModel.liveChannels.isEmpty {
                loadingPlaceholder
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(viewModel.topChannels) { channel in
                        MiniChannelCard(channel: channel)
                            .onHover { hovering in
                                if hovering { triggerPrefetch(channelId: channel.channelId) }
                            }
                            .customCursor(.pointingHand)
                            .onTapGesture {
                                router.navigate(to: .live(channelId: channel.channelId))
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingPlaceholder: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: DesignTokens.Spacing.sm)],
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .aspectRatio(16/9, contentMode: .fill)
                    
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Circle()
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(DesignTokens.Colors.surfaceElevated)
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(DesignTokens.Colors.surfaceElevated)
                                .frame(width: 60, height: 8)
                        }
                    }
                    .padding(DesignTokens.Spacing.xs)
                }
                .background(DesignTokens.Colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
    }
    
    // MARK: - Helpers
    
    /// macOS 네이티브 섹션 헤더
    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if let subtitle = subtitle {
                Text("·  \(subtitle)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private func formatLargeNumber(_ num: Int) -> String {
        if num >= 10_000 {
            return String(format: "%.1f만", Double(num) / 10_000.0)
        } else if num >= 1_000 {
            return String(format: "%.1f천", Double(num) / 1_000.0)
        }
        return "\(num)"
    }

    // MARK: - Skeleton: Stat Cards

    private var skeletonStatCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)
            ],
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 14, height: 14)
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 60, height: 10)
                    }
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 80, height: 22)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 50, height: 8)
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial, hasShadow: false)
                .shimmer()
            }
        }
    }

    // MARK: - Skeleton: Charts Section

    private var skeletonChartsSection: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            // Viewer trend chart skeleton
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 100, height: 12)
                    .shimmer()
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(height: 160)
                    .shimmer()
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial, hasShadow: false)

            // Category chart skeleton
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 100, height: 12)
                    .shimmer()
                VStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(0..<5, id: \.self) { i in
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(DesignTokens.Colors.surfaceElevated)
                                .frame(width: 50, height: 10)
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(DesignTokens.Colors.surfaceElevated)
                                .frame(height: 10)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 130)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial, hasShadow: false)
        }
    }
}
