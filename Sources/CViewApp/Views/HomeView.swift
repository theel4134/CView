// MARK: - HomeView.swift
// CViewApp - 홈 대시보드 (Minimal Monochrome)
// 통계 카드 + Swift Charts + 인기 채널 그리드

import SwiftUI
import CViewCore
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

                // 2. Stat Cards
                statCardsGrid

                // 3. Charts
                chartsSection

                // 4. Analytics (카테고리 분포 + 시청자 분포)
                analyticsSection

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
        .background(DesignTokens.Colors.backgroundDark)
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - 1. Dashboard Header

    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text(Date(), format: .dateTime.year().month().day().weekday(.wide))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    // 데이터 신선도 배지
                    if viewModel.isLoadingStats {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(DesignTokens.Colors.chzzkGreen)
                            Text("데이터 수집 중")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    Text("시청자 \(formatLargeNumber(viewModel.totalViewers))명")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.surface)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(DesignTokens.Colors.surface)
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
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isStale ? DesignTokens.Colors.warning : DesignTokens.Colors.chzzkGreen)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if !viewModel.categoryTypeDistribution.isEmpty {
                    Text("·  총 \(viewModel.totalLiveChannelCount)채널")
                        .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(viewModel.topThreeChannels.enumerated()), id: \.element.id) { index, channel in
                    topRankCard(rank: index + 1, channel: channel)
                        .onTapGesture {
                            router.navigate(to: .live(channelId: channel.channelId))
                        }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surface)
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
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 28)

            // 채널 아바타
            CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                Circle().fill(DesignTokens.Colors.surfaceLight)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(rankColor.opacity(0.5), lineWidth: 1.5)
            }

            // 채널 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.channelName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text(channel.formattedViewerCount)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(rankColor)

                if let cat = channel.categoryName {
                    Text(cat)
                        .font(.system(size: 9, weight: .medium))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                
                Spacer()
                
                if let lastUpdate = viewModel.serverLastUpdate {
                    Text(lastUpdate, format: .dateTime.hour().minute().second())
                        .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
        }
    }
    
    // MARK: - 4. Personal Stats

    private var personalStatsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("내 팔로잉")
                    .font(.system(size: 12, weight: .semibold))
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.live.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(DesignTokens.Colors.live.opacity(0.3), lineWidth: 0.5)
                            }
                        }

                        Text("\(viewModel.followingLiveRate)% 라이브율")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.surfaceLight)
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
                            .font(.system(size: 18))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("라이브 중인 팔로잉 채널이 없습니다")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.lg)
                .background(DesignTokens.Colors.surface)
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
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("팔로잉 조회에는 네이버 로그인이 필요합니다")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("로그인 → '네이버 로그인' 탭을 선택하세요")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            
            Spacer()
            
            Button {
                router.presentSheet(.login)
            } label: {
                Text("로그인")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(DesignTokens.Colors.chzzkGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        }
    }
    
    // MARK: - 6. Top Channels (Personal Stats도 이 섹션 번호로 통일)

    private var topChannelsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("인기 채널")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button {
                    router.navigate(to: .following)
                } label: {
                    HStack(spacing: 3) {
                        Text("전체보기")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
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
                        .fill(DesignTokens.Colors.surfaceLight)
                        .aspectRatio(16/9, contentMode: .fill)
                    
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Circle()
                            .fill(DesignTokens.Colors.surfaceLight)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DesignTokens.Colors.surfaceLight)
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DesignTokens.Colors.surfaceLight)
                                .frame(width: 60, height: 8)
                        }
                    }
                    .padding(DesignTokens.Spacing.xs)
                }
                .background(DesignTokens.Colors.surface)
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
}

// MARK: - Following View

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

struct FollowingView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var sortOrder: FollowingSortOrder = .liveFirst
    @State private var filterLiveOnly: Bool = false
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var displayedOfflineCount: Int = 10
    @State private var showAllOffline: Bool = false
    private let offlinePageSize = 10

    // 라이브 페이징 — 한 번에 렌더링되는 카드 수 제한 → GPU 동시 로드 감소
    @State private var displayedLiveCount: Int = 12
    @State private var showAllLive: Bool = false
    private let livePageSize = 12

    // 캐싱된 필터 결과 — 입력 변경 시에만 재산출 (body 중복 호출 방지)
    @State private var cachedLive: [LiveChannelItem] = []
    @State private var cachedAllOffline: [LiveChannelItem] = []
    @State private var cachedLiveCategoryCounts: [(name: String, count: Int)] = []

    // 페이징된 라이브 채널 (displayedLiveCount 이하만 렌더링)
    private var liveChannels: [LiveChannelItem] {
        showAllLive ? cachedLive : Array(cachedLive.prefix(displayedLiveCount))
    }

    private var totalLiveCount: Int { cachedLive.count }

    private var offlineChannels: [LiveChannelItem] {
        showAllOffline ? cachedAllOffline : Array(cachedAllOffline.prefix(displayedOfflineCount))
    }

    private var totalOfflineCount: Int { cachedAllOffline.count }
    private var liveCategoryCounts: [(name: String, count: Int)] { cachedLiveCategoryCounts }
    private var liveCategories: [String] { cachedLiveCategoryCounts.map { $0.name } }

    private func formatShortCount(_ n: Int) -> String {
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

    var body: some View {
        VStack(spacing: 0) {
            // ── 컨트롤 바 (검색 + 필터)
            controlBar

            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.5))
                .frame(height: 0.5)

            // ── 메인 컨텐츠
            if !appState.isLoggedIn {
                followingGateView(
                    icon: "person.crop.circle.badge.questionmark",
                    iconColor: DesignTokens.Colors.textTertiary,
                    title: "로그인이 필요합니다",
                    subtitle: "로그인하면 팔로잉 채널을 확인할 수 있습니다",
                    buttonLabel: "로그인",
                    action: { router.presentSheet(.login) }
                )
            } else if viewModel.needsCookieLogin {
                followingGateView(
                    icon: "key.fill",
                    iconColor: DesignTokens.Colors.accentOrange,
                    title: "네이버 로그인이 필요합니다",
                    subtitle: "팔로잉 목록을 보려면 '네이버 로그인'으로 다시 로그인하세요",
                    buttonLabel: "네이버 로그인",
                    action: { router.presentSheet(.login) }
                )
            } else if viewModel.followingChannels.isEmpty {
                if viewModel.isLoadingFollowing {
                    skeletonLoadingView
                } else {
                    followingGateView(
                        icon: "heart",
                        iconColor: DesignTokens.Colors.accentPink,
                        title: "팔로잉 채널이 없습니다",
                        subtitle: "치지직에서 채널을 팔로우하면 여기서 확인할 수 있어요",
                        buttonLabel: nil,
                        action: nil
                    )
                }
            } else {
                mainContent
            }
        }
        .background(DesignTokens.Colors.backgroundDark)
        .navigationTitle("팔로잉")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenuButton
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.loadFollowingChannels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .help("새로고침")
            }
        }
        .onChange(of: sortOrder) { _, _ in
            displayedOfflineCount = offlinePageSize
            displayedLiveCount = livePageSize
            showAllOffline = false
            showAllLive = false
            recomputeFiltered()
        }
        .onChange(of: filterLiveOnly) { _, _ in
            displayedOfflineCount = offlinePageSize
            displayedLiveCount = livePageSize
            showAllOffline = false
            showAllLive = false
            recomputeFiltered()
        }
        .onChange(of: selectedCategory) { _, _ in
            displayedOfflineCount = offlinePageSize
            displayedLiveCount = livePageSize
            showAllOffline = false
            showAllLive = false
            recomputeFiltered()
        }
        .onChange(of: searchText) { _, _ in recomputeFiltered() }
        .onChange(of: viewModel.followingChannels) { _, _ in recomputeFiltered() }
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

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 5) {
            // Row 1: 검색창 + 로딩 / 업데이트 시간
            HStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(searchText.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen)
                    TextField("채널 검색", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DesignTokens.Colors.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    searchText.isEmpty ? DesignTokens.Colors.border : DesignTokens.Colors.chzzkGreen.opacity(0.5),
                    lineWidth: searchText.isEmpty ? 0.5 : 1
                ))

                Spacer()

                if viewModel.isLoadingFollowing {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(DesignTokens.Colors.chzzkGreen)
                } else if let cachedAt = viewModel.followingCachedAt {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text(cachedAt, style: .relative)
                            .font(.system(size: 10))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .onTapGesture {
                        Task { await viewModel.loadFollowingChannels() }
                    }
                }
            }

            // Row 2: 라이브 필터 토글 + 통계 배지
            HStack(spacing: DesignTokens.Spacing.xs) {
                // 라이브만 보기 토글
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        filterLiveOnly.toggle()
                        if filterLiveOnly { selectedCategory = nil }
                    }
                } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(filterLiveOnly ? DesignTokens.Colors.live : DesignTokens.Colors.live.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                        Text("라이브 \(viewModel.followingLiveCount)")
                            .font(.system(size: 11, weight: filterLiveOnly ? .bold : .medium))
                            .foregroundStyle(filterLiveOnly ? DesignTokens.Colors.live : DesignTokens.Colors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(filterLiveOnly ? DesignTokens.Colors.live.opacity(0.12) : DesignTokens.Colors.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        filterLiveOnly ? DesignTokens.Colors.live.opacity(0.4) : DesignTokens.Colors.border,
                        lineWidth: 0.5
                    ))
                }
                .buttonStyle(.plain)

                Spacer()

                // 통계 배지
                if !viewModel.followingChannels.isEmpty {
                    statPill(value: "\(viewModel.followingChannels.count)", label: "팔로잉",
                             color: DesignTokens.Colors.accentPurple)
                    if viewModel.followingTotalViewers > 0 {
                        statPill(value: formatShortCount(viewModel.followingTotalViewers), label: "명 시청",
                                 color: DesignTokens.Colors.accentBlue)
                    }
                    if viewModel.followingLiveRate > 0 {
                        statPill(value: "\(viewModel.followingLiveRate)%", label: "라이브율",
                                 color: DesignTokens.Colors.chzzkGreen)
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.backgroundDark)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 카테고리 필터 칩
                if !liveCategories.isEmpty && !filterLiveOnly {
                    categoryFilterChips
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)
                }

                // 검색 결과 없음
                if cachedLive.isEmpty && cachedAllOffline.isEmpty {
                    emptySearchResult
                } else {
                    // 라이브 섹션
                    if !cachedLive.isEmpty {
                        sectionHeader(
                            icon: "dot.radiowaves.left.and.right",
                            title: "라이브 중",
                            count: totalLiveCount,
                            color: DesignTokens.Colors.live
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)

                        liveGrid
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.xs)

                        // 라이브 더 보기 (페이징)
                        if !showAllLive && displayedLiveCount < totalLiveCount {
                            loadMoreLiveButton
                                .padding(.top, DesignTokens.Spacing.xs)
                                .padding(.bottom, DesignTokens.Spacing.xs)
                        }
                    }

                    // 오프라인 섹션
                    if !filterLiveOnly && totalOfflineCount > 0 {
                        sectionHeader(
                            icon: "moon.zzz",
                            title: "오프라인",
                            count: totalOfflineCount,
                            color: DesignTokens.Colors.textTertiary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.md)

                        offlineList
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.xs)

                        // 더 보기
                        if !showAllOffline && displayedOfflineCount < totalOfflineCount {
                            loadMoreOfflineButton
                                .padding(.top, DesignTokens.Spacing.xs)
                                .padding(.bottom, DesignTokens.Spacing.sm)
                        }
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xl)
            }
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }

    // MARK: - Category Filter Chips

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // 전체 칩
                categoryChip(label: "전체", count: 0, isSelected: selectedCategory == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedCategory = nil
                    }
                }
                ForEach(liveCategoryCounts, id: \.name) { cat in
                    categoryChip(label: cat.name, count: cat.count, isSelected: selectedCategory == cat.name) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCategory = selectedCategory == cat.name ? nil : cat.name
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? .black : DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surfaceLight)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.12) : DesignTokens.Colors.surface
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.4) : DesignTokens.Colors.border,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Live Grid (16:9 스트림 카드)

    private var liveGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.sm)],
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(Array(liveChannels.enumerated()), id: \.element.id) { index, channel in
                FollowingLiveCard(channel: channel, index: index) {
                    router.navigate(to: .live(channelId: channel.channelId))
                }
                .equatable()
                .onTapGesture {
                    router.navigate(to: .live(channelId: channel.channelId))
                }
            }
        }
    }

    // MARK: - Offline List (컴팩트 행)

    private var offlineList: some View {
        // LazyVStack — 단일 열 목록에 열 수 계산 오버헤드 없음
        // offlineChannels는 prefix(displayedOfflineCount)로 슬라이스된 배열 → 렌더링 범위 명확히 제한
        LazyVStack(spacing: 2) {
            ForEach(offlineChannels, id: \.id) { channel in
                FollowingOfflineRow(channel: channel, index: 0)
                    .equatable()  // channel 데이터 동일 시 렌더링 스킵
                    .onTapGesture {
                        router.navigate(to: .channelDetail(channelId: channel.channelId))
                    }
            }
        }
    }

    // MARK: - Load More Live

    private var loadMoreLiveButton: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    displayedLiveCount = min(displayedLiveCount + livePageSize, totalLiveCount)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(totalLiveCount - displayedLiveCount)개 더 보기")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showAllLive = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10, weight: .semibold))
                    Text("전체 \(totalLiveCount)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.live)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.live.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.live.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Load More Offline

    private var loadMoreOfflineButton: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    displayedOfflineCount = min(displayedOfflineCount + offlinePageSize, totalOfflineCount)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(totalOfflineCount - displayedOfflineCount)개 더 보기")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showAllOffline = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10, weight: .semibold))
                    Text("전체 \(totalOfflineCount)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.accentPurple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.accentPurple.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.accentPurple.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Skeleton Loading View

    private var skeletonLoadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(icon: "dot.radiowaves.left.and.right", title: "라이브 중", count: 0, color: DesignTokens.Colors.live)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .redacted(reason: .placeholder)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonLiveCard()
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.md)

                sectionHeader(icon: "moon.zzz", title: "오프라인", count: 0, color: DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .redacted(reason: .placeholder)

                VStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 10) {
                            Circle().fill(DesignTokens.Colors.surfaceLight).frame(width: 30, height: 30).shimmer()
                            RoundedRectangle(cornerRadius: 3).fill(DesignTokens.Colors.surfaceLight).frame(height: 10).shimmer()
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    // MARK: - Empty Search / Gate Views

    private var emptySearchResult: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("검색 결과가 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if !searchText.isEmpty {
                Text("'\(searchText)'와 일치하는 채널이 없습니다")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            // 필터 초기화 버튼들
            VStack(spacing: 6) {
                if !searchText.isEmpty {
                    filterResetButton(label: "검색 초기화", icon: "xmark.circle") {
                        searchText = ""
                    }
                }
                if selectedCategory != nil {
                    filterResetButton(label: "카테고리 초기화", icon: "tag.slash") {
                        selectedCategory = nil
                    }
                }
                if filterLiveOnly {
                    filterResetButton(label: "라이브만 해제", icon: "dot.radiowaves.left.and.right.slash") {
                        filterLiveOnly = false
                    }
                }
                if searchText.isEmpty == false || selectedCategory != nil || filterLiveOnly {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            searchText = ""
                            selectedCategory = nil
                            filterLiveOnly = false
                        }
                    } label: {
                        Text("모든 필터 초기화")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, DesignTokens.Spacing.xl)
    }

    private func filterResetButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func followingGateView(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        buttonLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(iconColor)
            }
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let label = buttonLabel, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(DesignTokens.Colors.chzzkGreen)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Sort Menu

    private var sortMenuButton: some View {
        Menu {
            ForEach(FollowingSortOrder.allCases) { order in
                Button {
                    withAnimation(DesignTokens.Animation.fast) { sortOrder = order }
                } label: {
                    HStack {
                        Label(order.rawValue, systemImage: order.icon)
                        if sortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                Text(sortOrder.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Live Channel Card (라이브 전용)

@MainActor
struct FollowingLiveCard: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveCard, rhs: FollowingLiveCard) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 이미지 영역 ──────────────────────────────────────────
            // overlay 패턴: 베이스 뷰가 크기를 결정, 배지/hover는 합성만
            // ZStack 내 조건부 분기 제거 → isHovered 토글 시 ZStack 전체 재평가 없음
            imageBase
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)  // 16:9 스트림 썸네일 비율
                .clipped()
                .overlay(alignment: .top) { badgeBar }          // LIVE 배지 + 시청자수 (상단)
                .overlay { if isHovered { hoverLayer } }        // hover 레이어 (독립)
                .overlay(alignment: .bottomLeading) { avatarBadge } // 채널 아바타 (좌하단)

            // ── 정보 영역 ────────────────────────────────────────────
            infoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.live.opacity(0.5) : DesignTokens.Colors.live.opacity(0.12),
                    lineWidth: 0.5
                )
        }
        // scaleEffect 제거 — 전체 카드 재합성 유발
        // shadow(radius:14) 제거 — macOS 고비용 blur 패스
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: appeared)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .cursor(.pointingHand)
    }

    // MARK: - Sub-views (분리로 body 재평가 범위 최소화)

    @ViewBuilder
    private var imageBase: some View {
        // 스트림 썸네일(16:9) 우선, 없으면 채널 프로필 이미지 폴백
        let url = [channel.thumbnailUrl, channel.channelImageUrl]
            .lazy.compactMap { $0.flatMap(URL.init) }.first
        if let url {
            CachedAsyncImage(url: url) {
                thumbnailPlaceholder
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        LinearGradient(
            colors: [DesignTokens.Colors.surfaceLight, DesignTokens.Colors.surface],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // 채널 아바타 (썸네일 좌하단 고정) — infoArea 공간 절약
    private var avatarBadge: some View {
        CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceLight)
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
        .drawingGroup(opaque: false)  // 아바타 원형 클립+스트로크 단일 Metal 패스
        .padding(.leading, 7)
        .padding(.bottom, 6)
    }

    private var badgeBar: some View {
        HStack(alignment: .center) {
            LivePulseBadge()
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "person.fill").font(.system(size: 8))
                Text(channel.formattedViewerCount)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.4), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var hoverLayer: some View {
        ZStack {
            Color.black.opacity(0.22)
            Button(action: onPlay) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                    Text("바로 시청").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DesignTokens.Colors.chzzkGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.12)))
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(channel.channelName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Text(channel.liveTitle)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let cat = channel.categoryName {
                HStack {
                    Text(cat)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor(for: channel.categoryType).opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .drawingGroup(opaque: false)  // 정보 영역 텍스트+뱃지 레이어 단일 Metal 패스
    }

    private func categoryColor(for type: String?) -> Color {
        switch type?.uppercased() {
        case "GAME":   return DesignTokens.Colors.accentPurple
        case "SPORTS": return DesignTokens.Colors.accentBlue
        default:       return DesignTokens.Colors.surfaceLight
        }
    }
}
// MARK: - Offline Channel Row (컴팩트)

struct FollowingOfflineRow: View, Equatable {
    nonisolated static func == (lhs: FollowingOfflineRow, rhs: FollowingOfflineRow) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            // 아바타 (오프라인 — saturation 제거: GPU ColorSpace 변환 패스 절감)
            CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                ZStack {
                    Circle().fill(DesignTokens.Colors.surfaceLight)
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .opacity(0.5)  // saturation(0.25) 제거 — opacity만으로 오프라인 dim 표현

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                if let cat = channel.categoryName, !isHovered {
                    Text(cat)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 11))
                    Text("채널 보기").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .transition(.opacity)  // scale 제거 — geometry 재계산 없이 alpha만
            } else {
                Text("오프라인")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isHovered ? DesignTokens.Colors.surface : .clear)
        )
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }
        }
        // offset 진입 애니메이션 제거 — geometry 재계산 없이 alpha만 변경
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: appeared)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .cursor(.pointingHand)
    }
}

// MARK: - Skeleton Loading View

private struct SkeletonLiveCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(DesignTokens.Colors.surfaceLight)
                .aspectRatio(16/9, contentMode: .fill)
                .shimmer()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DesignTokens.Radius.md, topTrailingRadius: DesignTokens.Radius.md))

            HStack(spacing: 10) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceLight)
                    .frame(width: 34, height: 34)
                    .shimmer()
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignTokens.Colors.surfaceLight)
                        .frame(height: 10)
                        .shimmer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignTokens.Colors.surfaceLight)
                        .frame(width: 80, height: 8)
                        .shimmer()
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignTokens.Colors.surface)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: DesignTokens.Radius.md, bottomTrailingRadius: DesignTokens.Radius.md))
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Colors.border.opacity(0.5), lineWidth: 0.5)
        }
    }
}

// pointingHand cursor helper
private extension View {
    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active: cursor.push()
            case .ended:  NSCursor.pop()
            }
        }
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.warning.opacity(0.1))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Colors.warning)
            }
            
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("오류가 발생했습니다")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: retryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("다시 시도")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DesignTokens.Colors.chzzkGreen)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

// MARK: - Shimmer Effect

// Metal 3: TimelineView 드라이브 shimmer — CPU @State 애니메이션 루프 제거
// @State phase 변이 사이클 없이 GPU 타임라인에서 직접 phase 계산
struct ShimmerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                TimelineView(.animation) { timeline in
                    GeometryReader { geometry in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.5) / 1.5)
                        LinearGradient(
                            colors: [
                                .clear,
                                DesignTokens.Colors.textPrimary.opacity(0.1),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                        // Metal 오프스크린 합성 — TimelineView 드라이브 GPU 갱신
                        .drawingGroup()
                    }
                    .clipped()
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Live Pulse Badge
// Metal 3: TimelineView 드라이브 — CPU @State repeatForever 루프 제거
// sin 파형으로 GPU 직접 계산, 30fps 최소 간격으로 쓸데없는 렌더 방지

private struct LivePulseBadge: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 0.25 ~ 1.0 사이 sin 진동 (주기 1.8s = easeInOut 0.9s × 2)
            let opacity = sin(t * .pi / 0.9) * 0.375 + 0.625
            HStack(spacing: 4) {
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(opacity)
                Text("LIVE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DesignTokens.Colors.live)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .drawingGroup(opaque: false)  // 배지 전체를 단일 Metal 텍스처로 격리
    }
}
