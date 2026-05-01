// MARK: - Statistics/Tabs/WatchHistoryStatsView.swift
// 기록 탭 — 총 시청시간 / 평균 세션 / Top 채널 / 시간대 히스토그램 / 카테고리 파이 / 최근 기록.

import SwiftUI
import Charts
import CViewCore
import CViewPersistence
import CViewUI

struct WatchHistoryStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var watchHistory: [CViewPersistence.WatchHistoryData] = []
    @State private var totalWatchTime: TimeInterval = 0
    @State private var avgSession: TimeInterval = 0
    @State private var topChannels: [(channelName: String, duration: TimeInterval)] = []
    @State private var byHour: [Int: TimeInterval] = [:]
    @State private var byCategory: [(category: String, duration: TimeInterval)] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 시청 요약 (4 KPI)
                StatSection("시청 요약", icon: "clock.fill", color: DesignTokens.Colors.accentOrange) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "총 시청 시간",
                            value: formattedTotalTime,
                            icon: "clock.fill",
                            color: DesignTokens.Colors.accentOrange
                        )
                        StatCard(
                            title: "평균 세션",
                            value: formatDuration(avgSession),
                            icon: "stopwatch.fill",
                            color: DesignTokens.Colors.accentCyan
                        )
                        StatCard(
                            title: "시청 횟수",
                            value: "\(watchHistory.count)회",
                            icon: "play.tv.fill",
                            color: DesignTokens.Colors.accentBlue
                        )
                        StatCard(
                            title: "채널 수",
                            value: "\(uniqueChannelCount)개",
                            icon: "person.2.fill",
                            color: DesignTokens.Colors.accentPurple
                        )
                    }
                }

                // ── Top 채널
                if !topChannels.isEmpty {
                    StatSection("채널별 시청 시간", icon: "chart.bar.fill", color: DesignTokens.Colors.accentBlue) {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(Array(topChannels.enumerated()), id: \.offset) { idx, entry in
                                channelBarRow(rank: idx + 1, name: entry.channelName, duration: entry.duration)
                            }
                        }
                    }
                }

                // ── 시간대 히스토그램 (신규)
                if !byHour.isEmpty {
                    StatSection("시간대별 시청 패턴", icon: "clock.arrow.2.circlepath", color: DesignTokens.Colors.accentPink) {
                        hourlyChart
                            .padding(DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                            }
                    }
                }

                // ── 카테고리 파이 (신규)
                if !byCategory.isEmpty {
                    StatSection("카테고리 분포", icon: "tag.fill", color: DesignTokens.Colors.chzzkGreen) {
                        categoryPie
                            .padding(DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                            }
                    }
                }

                // ── 최근 시청 기록
                StatSection("최근 시청 기록", icon: "clock.arrow.circlepath", color: DesignTokens.Colors.accentOrange) {
                    if isLoading {
                        HStack { Spacer(); ProgressView().tint(DesignTokens.Colors.accentOrange); Spacer() }
                            .frame(minHeight: 80)
                    } else if watchHistory.isEmpty {
                        EmptyStatePlaceholder(
                            icon: "clock.arrow.circlepath",
                            title: "시청 기록이 없습니다",
                            subtitle: "라이브 방송을 시청하면 여기에 자동으로 기록됩니다"
                        )
                    } else {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(watchHistory.prefix(20)) { record in
                                watchHistoryRow(record)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .contentBackground()
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
    }

    // MARK: - Hourly chart

    @ViewBuilder
    private var hourlyChart: some View {
        let data: [(hour: Int, minutes: Double)] = (0..<24).map { h in
            (h, (byHour[h] ?? 0) / 60.0)
        }
        Chart(data, id: \.hour) { item in
            BarMark(
                x: .value("시", item.hour),
                y: .value("분", item.minutes),
                width: .ratio(0.7)
            )
            .foregroundStyle(LinearGradient(
                colors: [DesignTokens.Colors.accentPink.opacity(0.85),
                         DesignTokens.Colors.accentPurple.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            ))
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: stride(from: 0, through: 23, by: 3).map { $0 }) { v in
                AxisGridLine().foregroundStyle(DesignTokens.Colors.border.opacity(0.2))
                AxisValueLabel {
                    if let h = v.as(Int.self) {
                        Text(String(format: "%02d시", h))
                            .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(DesignTokens.Colors.border.opacity(0.3))
                AxisValueLabel()
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .chartYAxisLabel("시청 시간 (분)")
        .frame(height: 160)
    }

    // MARK: - Category pie

    @ViewBuilder
    private var categoryPie: some View {
        let total = byCategory.reduce(0) { $0 + $1.duration }
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            Chart(byCategory, id: \.category) { item in
                SectorMark(
                    angle: .value("시간", item.duration),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("카테고리", item.category))
                .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .frame(width: 180, height: 180)

            // 범례 (직접 작성 — 비율 표기 포함)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(byCategory.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(categoryColor(idx))
                            .frame(width: 12, height: 12)
                        Text(item.category)
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if total > 0 {
                            Text(String(format: "%.0f%%", item.duration / total * 100))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categoryColor(_ idx: Int) -> Color {
        // SwiftUI Chart 가 자동 배정하는 팔레트와 가깝게 매핑 (범례용 시각 단서).
        let palette: [Color] = [
            DesignTokens.Colors.chzzkGreen,
            DesignTokens.Colors.accentBlue,
            DesignTokens.Colors.accentOrange,
            DesignTokens.Colors.accentPurple,
            DesignTokens.Colors.accentPink,
            DesignTokens.Colors.accentCyan,
            .yellow,
            .red
        ]
        return palette[idx % palette.count]
    }

    // MARK: - Channel bar row (이전 구현 그대로)

    @ViewBuilder
    private func channelBarRow(rank: Int, name: String, duration: TimeInterval) -> some View {
        let maxDuration = topChannels.first?.duration ?? 1
        let ratio = min(1.0, duration / maxDuration)
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text("\(rank)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 18, alignment: .trailing)
            Text(name)
                .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(LinearGradient(
                            colors: [DesignTokens.Colors.accentBlue.opacity(0.7),
                                     DesignTokens.Colors.accentPurple.opacity(0.9)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(formatDuration(duration))
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.accentBlue)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - Watch history row

    @ViewBuilder
    private func watchHistoryRow(_ record: CViewPersistence.WatchHistoryData) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if let thumbStr = record.thumbnailURL, let url = URL(string: thumbStr) {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 54, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 54, height: 30)
                    .overlay {
                        Image(systemName: "play.tv")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let cat = record.categoryName, !cat.isEmpty {
                        Text(cat)
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(record.formattedDate)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            if record.duration > 60 {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(DesignTokens.Typography.micro)
                    Text(record.formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.accentOrange)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.accentOrange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - Computed / formatters

    private var formattedTotalTime: String {
        let hours = Int(totalWatchTime) / 3600
        let minutes = (Int(totalWatchTime) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)분" }
        return "0분"
    }

    private var uniqueChannelCount: Int {
        Set(watchHistory.map(\.channelId)).count
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        if t <= 0 { return "-" }
        let hours = Int(t) / 3600
        let minutes = (Int(t) % 3600) / 60
        let seconds = Int(t) % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)분" }
        return "\(seconds)초"
    }

    // MARK: - Loading

    private func loadHistory() async {
        guard let ds = appState.dataStore else { isLoading = false; return }
        isLoading = true
        watchHistory = (try? await ds.fetchWatchHistory(limit: 50)) ?? []
        totalWatchTime = (try? await ds.totalWatchTime()) ?? 0
        avgSession = (try? await ds.averageSessionDuration()) ?? 0
        topChannels = (try? await ds.watchTimeByChannel(limit: 5)) ?? []
        byHour = (try? await ds.watchTimeByHour()) ?? [:]
        byCategory = (try? await ds.watchTimeByCategory(limit: 8)) ?? []
        isLoading = false
    }
}
