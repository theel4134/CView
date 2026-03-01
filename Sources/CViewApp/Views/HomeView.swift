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
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
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
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text(Date(), format: .dateTime.year().month().day().weekday(.wide))
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    // 데이터 신선도 배지
                    if viewModel.isLoadingStats {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(DesignTokens.Colors.chzzkGreen)
                            Text("데이터 수집 중")
                                .font(DesignTokens.Typography.footnoteMedium)
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                        .clipShape(Capsule())
                    } else if let cachedAt = viewModel.allStatCachedAt ?? viewModel.liveChannelsCachedAt {
                        dataFreshnessBadge(cachedAt: cachedAt)
                    }
                }
            }

            Spacer()

            // 통계 요약 배지
            if viewModel.totalLiveChannelCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(DesignTokens.Colors.live).frame(width: 5, height: 5)
                        Text("\(viewModel.totalLiveChannelCount)채널 라이브")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    Text("시청자 \(formatLargeNumber(viewModel.totalViewers))명")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
            .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
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
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
            Text(label)
                .font(DesignTokens.Typography.footnoteMedium)
        }
        .foregroundStyle(isStale ? DesignTokens.Colors.warning : DesignTokens.Colors.chzzkGreen)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background((isStale ? DesignTokens.Colors.warning : DesignTokens.Colors.chzzkGreen).opacity(0.08))
        .clipShape(Capsule())
    }
    
    // MARK: - 2. Stat Cards

    private var statCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)
            ],
            spacing: DesignTokens.Spacing.sm
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
                    subtitle: "WS \(viewModel.wsClientCount)클라이언트",
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 섹션 헤더
            HStack {
                Text("스트리밍 분석")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if !viewModel.categoryTypeDistribution.isEmpty {
                    Text("·  총 \(viewModel.totalLiveChannelCount)채널")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
            }

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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("시청자 TOP 3")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(viewModel.topThreeChannels.enumerated()), id: \.element.id) { index, channel in
                    topRankCard(rank: index + 1, channel: channel)
                        .onHover { hovering in
                            if hovering { triggerPrefetch(channelId: channel.channelId) }
                        }
                        .onTapGesture {
                            router.navigate(to: .live(channelId: channel.channelId))
                        }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
        }
    }

    private func topRankCard(rank: Int, channel: LiveChannelItem) -> some View {
        let rankColors: [Color] = [.yellow, Color(red: 0.75, green: 0.75, blue: 0.78), DesignTokens.Colors.accentOrange]
        let rankColor = rank <= 3 ? rankColors[rank - 1] : DesignTokens.Colors.textTertiary

        return HStack(spacing: DesignTokens.Spacing.sm) {
            // 순위 뱃지
            Text("#\(rank)")
                .font(DesignTokens.Typography.custom(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 28)

            // 채널 아바타
            CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                Circle().fill(DesignTokens.Colors.surfaceElevated)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(rankColor.opacity(0.5), lineWidth: 1.5)
            }

            // 채널 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.micro)
                    Text(channel.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(rankColor)

                if let cat = channel.categoryName {
                    Text(cat)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(rankColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(rankColor.opacity(0.15), lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 5. Metrics Server Section

    private var metricsServerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 6, height: 6)
                    Text("메트릭 서버")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                
                Spacer()
                
                if let lastUpdate = viewModel.serverLastUpdate {
                    Text(lastUpdate, format: .dateTime.hour().minute().second())
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            // Server Stats Cards Row
            HStack(spacing: DesignTokens.Spacing.sm) {
                serverMiniStat(icon: "clock", title: "업타임", value: viewModel.formattedUptime)
                serverMiniStat(icon: "antenna.radiowaves.left.and.right", title: "WS 클라이언트", value: "\(viewModel.wsClientCount)")
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
        }
    }
    
    // MARK: - 6. Personal Stats

    private var personalStatsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("내 팔로잉")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // 라이브 비율 배지
                if viewModel.followingChannels.count > 0 {
                    HStack(spacing: 6) {
                        if viewModel.followingLiveCount > 0 {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 6, height: 6)
                                Text("\(viewModel.followingLiveCount)명 라이브 중")
                                    .font(DesignTokens.Typography.captionSemibold)
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.live.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(DesignTokens.Colors.live.opacity(0.3), lineWidth: 0.5)
                            }
                        }

                        Text("\(viewModel.followingLiveRate)% 라이브율")
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.surfaceElevated)
                            .clipShape(Capsule())
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
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
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
            
            Button {
                router.presentSheet(.login)
            } label: {
                Text("로그인")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.onPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(DesignTokens.Colors.chzzkGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        }
    }
    
    // MARK: - 7. Top Channels

    private var topChannelsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("인기 채널")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button {
                    router.navigate(to: .following)
                } label: {
                    HStack(spacing: 3) {
                        Text("전체보기")
                            .font(DesignTokens.Typography.captionMedium)
                        Image(systemName: "chevron.right")
                            .font(DesignTokens.Typography.microSemibold)
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.8))
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
                .background(DesignTokens.Colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
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
            .background(DesignTokens.Colors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }

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
            .background(DesignTokens.Colors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }
        }
    }
}
