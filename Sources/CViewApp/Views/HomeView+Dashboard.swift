// MARK: - HomeView+Dashboard.swift
// CViewApp - Dashboard Header + Analytics Cards

import SwiftUI
import CViewCore
import CViewUI

extension HomeView {
    
    // MARK: - 1. Dashboard Header

    var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Hero greeting row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(viewModel.liveChannelsCachedAt ?? Date(), format: .dateTime.year().month().day().weekday(.wide))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if viewModel.isLoadingStats {
                            HStack(spacing: 4) {
                                ProgressView(value: viewModel.statsCollectionProgress)
                                    .frame(width: 40)
                                    .controlSize(.mini)
                                if let total = viewModel.statsEstimatedTotal, total > 0 {
                                    Text("수집 중 \(viewModel.statsCollectedCount)/\(total) (\(Int(viewModel.statsCollectionProgress * 100))%)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("수집 중 \(viewModel.statsCollectedCount)개")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
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
                    .animation(viewModel.isLoading ? .linear(duration: 0.6) : .default, value: viewModel.isLoading)
                }
            }

            Divider()
        }
    }

    func dataFreshnessBadge(cachedAt: Date) -> some View {
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

    var statCardsGrid: some View {
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

    // MARK: - 4. Analytics Section (도넛차트 + 시청자 분포)

    var analyticsSection: some View {
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
    var topThreeSection: some View {
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

    func topRankCard(rank: Int, channel: LiveChannelItem) -> some View {
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
}
