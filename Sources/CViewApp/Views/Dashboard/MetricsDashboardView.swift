// MARK: - MetricsDashboardView.swift
// 메트릭 서버 전용 대시보드 — 실시간 모니터링 + 채널 통계 + 연결 관리

import SwiftUI
import Charts
import CViewCore
import CViewUI

struct MetricsDashboardView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                headerSection
                connectionStatusSection
                statsCardsRow
                chartsSection
                channelDetailSection
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.surfaceBase)
        .task {
            await viewModel.loadServerStats()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("메트릭 서버")
                    .font(DesignTokens.Typography.title2)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("cv.dododo.app 실시간 모니터링")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            if let lastUpdate = viewModel.serverLastUpdate {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red)
                        .frame(width: 8, height: 8)
                    Text(lastUpdate, format: .dateTime.hour().minute().second())
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Button {
                Task { await viewModel.loadServerStats() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            statusIndicator(
                title: "서버 상태",
                value: viewModel.isMetricsServerOnline ? "온라인" : "오프라인",
                icon: "server.rack",
                isOnline: viewModel.isMetricsServerOnline
            )
            statusIndicator(
                title: "버전",
                value: "v3.0.0",
                icon: "info.circle",
                isOnline: true
            )
            statusIndicator(
                title: "업타임",
                value: viewModel.formattedUptime,
                icon: "clock",
                isOnline: viewModel.serverUptime > 0
            )
        }
    }

    private func statusIndicator(title: String, value: String, icon: String, isOnline: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(isOnline ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.subheadSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial)
    }

    // MARK: - Stats Cards

    private var statsCardsRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            DashboardStatCard(
                title: "총 수신",
                value: formatLargeNumber(viewModel.serverTotalReceived),
                icon: "arrow.down.circle",
                accentColor: DesignTokens.Colors.chzzkGreen
            )
            DashboardStatCard(
                title: "활성 채널",
                value: "\(viewModel.serverChannelStats.count)",
                icon: "play.circle",
                accentColor: .cyan
            )
            if let webLat = viewModel.avgWebLatency {
                DashboardStatCard(
                    title: "웹 레이턴시",
                    value: String(format: "%.0fms", webLat),
                    icon: "globe",
                    subtitle: "평균",
                    accentColor: .cyan
                )
            }
            if let appLat = viewModel.avgAppLatency {
                DashboardStatCard(
                    title: "앱 레이턴시",
                    value: String(format: "%.0fms", appLat),
                    icon: "desktopcomputer",
                    subtitle: "평균",
                    accentColor: DesignTokens.Colors.chzzkGreen
                )
            }
            if let stats = viewModel.serverStats {
                let platforms = stats.resolvedPlatforms
                if !platforms.isEmpty {
                    DashboardStatCard(
                        title: "플랫폼",
                        value: platforms.map { "\($0.key): \($0.value)" }.joined(separator: ", "),
                        icon: "rectangle.stack",
                        accentColor: .purple
                    )
                }
            }
        }
    }

    // MARK: - Charts

    private var chartsSection: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            LatencyComparisonChart(history: viewModel.latencyHistory)
                .frame(maxWidth: .infinity)
            latencyDistributionChart
                .frame(maxWidth: .infinity)
        }
    }

    private var latencyDistributionChart: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("채널별 레이턴시 분포")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if viewModel.serverChannelStats.isEmpty {
                emptyChartState
            } else {
                Chart(viewModel.serverChannelStats) { stat in
                    if let webAvg = stat.web?.avg {
                        BarMark(
                            x: .value("채널", stat.channelName ?? stat.channelId.prefix(8).description),
                            y: .value("레이턴시", webAvg)
                        )
                        .foregroundStyle(.cyan.opacity(0.7))
                        .position(by: .value("타입", "웹"))
                    }
                    if let appAvg = stat.app?.avg {
                        BarMark(
                            x: .value("채널", stat.channelName ?? stat.channelId.prefix(8).description),
                            y: .value("레이턴시", appAvg)
                        )
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                        .position(by: .value("타입", "앱"))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(DesignTokens.Typography.micro)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DesignTokens.Colors.border)
                        AxisValueLabel()
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(DesignTokens.Typography.micro)
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 140)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private var emptyChartState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("데이터 수집 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 140)
    }

    // MARK: - Channel Detail

    private var channelDetailSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("채널 상세")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if viewModel.serverChannelStats.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("활성 채널이 없습니다")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("스트림을 시청하면 자동으로 메트릭이 수집됩니다")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .frame(height: 120)
                .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                    ForEach(viewModel.serverChannelStats) { stat in
                        channelDetailCard(stat)
                    }
                }
            }
        }
    }

    private func channelDetailCard(_ stat: ChannelStatsItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Header
            HStack {
                Text(stat.channelName ?? stat.channelId.prefix(12).description)
                    .font(DesignTokens.Typography.subheadSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let quality = stat.quality {
                    Text(quality)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Resolution / Bitrate
            if let resolution = stat.resolution {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    metricLabel(icon: "display", text: resolution)
                    if let bitrate = stat.bitrate {
                        metricLabel(icon: "speedometer", text: String(format: "%.1f Mbps", bitrate))
                    }
                    if let fps = stat.fps {
                        metricLabel(icon: "film", text: String(format: "%.0f fps", fps))
                    }
                }
            }

            Divider().foregroundStyle(DesignTokens.Glass.borderColor)

            // Latency comparison
            HStack(spacing: DesignTokens.Spacing.lg) {
                latencyColumn(title: "웹", stats: stat.web, color: .cyan)
                latencyColumn(title: "앱", stats: stat.app, color: DesignTokens.Colors.chzzkGreen)
                if let delta = stat.delta {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DELTA")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        if let current = delta.current {
                            Text(String(format: "%+.0fms", current))
                                .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(current > 0 ? .orange : DesignTokens.Colors.chzzkGreen)
                        }
                        if let avg = delta.avg {
                            Text(String(format: "avg %+.0f", avg))
                                .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                }
            }

            // Broadcast info
            if let broadcast = stat.broadcast, broadcast.title != nil {
                Divider().foregroundStyle(DesignTokens.Glass.borderColor)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = broadcast.title {
                        Text(title)
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let category = broadcast.category {
                            metricLabel(icon: "tag", text: category)
                        }
                        if let viewers = broadcast.concurrentUsers {
                            metricLabel(icon: "person.2", text: formatLargeNumber(viewers))
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard(cornerRadius: DesignTokens.Radius.md, material: .ultraThinMaterial)
    }

    private func latencyColumn(title: String, stats: LatencyStats?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                .foregroundStyle(color)
            if let stats {
                if let avg = stats.avg {
                    Text(String(format: "%.0fms", avg))
                        .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                HStack(spacing: 6) {
                    if let min = stats.min {
                        Text(String(format: "↓%.0f", min))
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    if let max = stats.max {
                        Text(String(format: "↑%.0f", max))
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    if let samples = stats.samples {
                        Text("n=\(samples)")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            } else {
                Text("—")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private func metricLabel(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(text)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000.0) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000.0) }
        return "\(n)"
    }
}
