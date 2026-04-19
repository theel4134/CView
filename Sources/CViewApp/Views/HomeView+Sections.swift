// MARK: - HomeView+Sections.swift
// CViewApp - Metrics Server, Personal Stats, Top Channels, Skeleton Views

import SwiftUI
import CViewCore
import CViewUI

extension HomeView {
    
    // MARK: - 5. Metrics Server Section

    var metricsServerSection: some View {
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    LatencyComparisonChart(history: viewModel.latencyHistory)
                        .frame(maxWidth: .infinity)

                    ServerChannelStatsView(channelStats: viewModel.serverChannelStats)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    LatencyComparisonChart(history: viewModel.latencyHistory)
                    ServerChannelStatsView(channelStats: viewModel.serverChannelStats)
                }
            }
        }
    }
    
    func serverMiniStat(icon: String, title: String, value: String) -> some View {
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

    var personalStatsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader(title: "내 라이브", subtitle: nil)

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
                            .font(DesignTokens.Typography.subhead)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("라이브 중인 채널이 없습니다")
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
                        MiniChannelCard(channel: channel, onHoverChange: { hovering in
                            if hovering { triggerPrefetch(channelId: channel.channelId) }
                        })
                            .onTapGesture {
                                router.navigate(to: .live(channelId: channel.channelId))
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - Cookie Login Banner
    
    var cookieLoginBanner: some View {
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

    var topChannelsSection: some View {
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
                        MiniChannelCard(channel: channel, onHoverChange: { hovering in
                            if hovering { triggerPrefetch(channelId: channel.channelId) }
                        })
                            .onTapGesture {
                                router.navigate(to: .live(channelId: channel.channelId))
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - Loading
    
    var loadingPlaceholder: some View {
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
    
    // MARK: - Skeleton: Stat Cards

    var skeletonStatCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 360), spacing: DesignTokens.Spacing.sm)],
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
                .surfaceCard(cornerRadius: DesignTokens.Radius.md, fillColor: DesignTokens.Colors.surfaceElevated, border: false)
                .shimmer()
            }
        }
    }

    // MARK: - Skeleton: Charts Section

    var skeletonChartsSection: some View {
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
            .surfaceCard(cornerRadius: DesignTokens.Radius.md, fillColor: DesignTokens.Colors.surfaceElevated, border: false)

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
            .surfaceCard(cornerRadius: DesignTokens.Radius.md, fillColor: DesignTokens.Colors.surfaceElevated, border: false)
        }
    }
}
