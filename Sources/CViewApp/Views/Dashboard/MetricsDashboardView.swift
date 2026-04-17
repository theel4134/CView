// MARK: - MetricsDashboardView.swift
// CView 서버 대시보드 — Modern Dashboard UI

import SwiftUI
import Charts
import CViewCore
import CViewUI

struct MetricsDashboardView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState
    @State private var appearAnimated = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                heroHeader
                serverOverviewBar
                systemHealthSection
                metricsGrid
                analyticsSection
                channelDetailSection
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.surfaceBase)
        .task {
            await viewModel.loadServerStats()
            await viewModel.loadSystemStats()
            withAnimation(DesignTokens.Animation.smooth) {
                appearAnimated = true
            }
        }
        .refreshable {
            await viewModel.loadServerStats()
            await viewModel.loadSystemStats()
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        // 글로우 도트
                        ZStack {
                            Circle()
                                .fill(viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red)
                                .frame(width: 10, height: 10)
                            if viewModel.isMetricsServerOnline {
                                Circle()
                                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.4))
                                    .frame(width: 10, height: 10)
                                    .scaleEffect(appearAnimated ? 2.2 : 1.0)
                                    .opacity(appearAnimated ? 0 : 0.6)
                                    .animation(DesignTokens.Animation.pulse, value: appearAnimated)
                            }
                        }
                        Text("CView 서버")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }

                    Text("cv.dododo.app")
                        .font(DesignTokens.Typography.monoMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Spacer()

                HStack(spacing: DesignTokens.Spacing.sm) {
                    // 연결 모드 배지
                    connectionBadge

                    // 마지막 업데이트
                    if let lastUpdate = viewModel.serverLastUpdate {
                        Text(lastUpdate, format: .dateTime.hour().minute().second())
                            .font(DesignTokens.Typography.monoMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }

                    // 새로고침
                    Button {
                        Task { await viewModel.loadServerStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.bodyMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 28, height: 28)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 악센트 라인
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)
                .opacity(appearAnimated ? 1 : 0)
                .scaleEffect(x: appearAnimated ? 1 : 0, anchor: .leading)
                .animation(DesignTokens.Animation.smooth, value: appearAnimated)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: viewModel.isWebSocketConnected ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 9, weight: .bold))
            Text(viewModel.isWebSocketConnected ? "실시간" : "폴링")
                .font(DesignTokens.Typography.captionSemibold)
        }
        .foregroundStyle(viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            (viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen : Color.gray)
                .opacity(0.1),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : Color.clear,
                lineWidth: 0.5
            )
        )
    }

    // MARK: - Server Overview Bar

    private var serverOverviewBar: some View {
        HStack(spacing: 0) {
            overviewCell(
                icon: "server.rack",
                title: "상태",
                value: viewModel.isMetricsServerOnline ? "온라인" : "오프라인",
                color: viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red
            )
            overviewDivider
            overviewCell(
                icon: "tag",
                title: "버전",
                value: viewModel.serverStats?.serverVersion ?? "—",
                color: DesignTokens.Colors.accentBlue
            )
            overviewDivider
            overviewCell(
                icon: "clock",
                title: "업타임",
                value: viewModel.formattedUptime,
                color: DesignTokens.Colors.accentCyan
            )
            overviewDivider
            overviewCell(
                icon: "arrow.down.circle",
                title: "총 수신",
                value: formatLargeNumber(viewModel.serverTotalReceived),
                color: DesignTokens.Colors.chzzkGreen
            )
            overviewDivider
            overviewCell(
                icon: "play.circle",
                title: "활성 채널",
                value: "\(viewModel.serverChannelStats.count)",
                color: DesignTokens.Colors.accentCyan
            )
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func overviewCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(value)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColor)
            .frame(width: 0.5, height: 32)
    }

    // MARK: - System Health

    private var systemHealthSection: some View {
        sectionContainer(title: "시스템 헬스", icon: "heart.text.square") {
            if let sys = viewModel.systemStats {
                VStack(spacing: DesignTokens.Spacing.md) {
                    // DB 상태 카드
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        healthCard(
                            name: "InfluxDB",
                            status: sys.influxdb?.status,
                            detail: sys.influxdb?.version,
                            icon: "cylinder",
                            color: DesignTokens.Colors.accentOrange
                        )
                        healthCard(
                            name: "PostgreSQL",
                            status: sys.postgres,
                            detail: nil,
                            icon: "tablecells",
                            color: DesignTokens.Colors.accentBlue
                        )
                        healthCard(
                            name: "Redis",
                            status: sys.redis?.status,
                            detail: sys.redis?.usedMemory,
                            icon: "memorychip",
                            color: DesignTokens.Colors.accentPurple
                        )
                    }

                    // 레코드 수
                    if let records = sys.recordCounts {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            recordPill(title: "채널", count: records.channels, icon: "play.circle", color: DesignTokens.Colors.accentCyan)
                            recordPill(title: "VLC", count: records.vlcMetrics, icon: "desktopcomputer", color: DesignTokens.Colors.chzzkGreen)
                            recordPill(title: "웹", count: records.webMetrics, icon: "globe", color: DesignTokens.Colors.accentBlue)
                            recordPill(title: "일간", count: records.dailyStats, icon: "calendar", color: DesignTokens.Colors.accentPurple)
                            recordPill(title: "시간별", count: records.hourlyStats, icon: "clock", color: DesignTokens.Colors.accentOrange)
                        }
                    }

                    // 마지막 체크 시각
                    if let checkedAt = sys.checkedAt {
                        HStack {
                            Spacer()
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                Text("마지막 체크 \(checkedAt)")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                    }
                }
            } else {
                systemLoadingPlaceholder
            }
        }
    }

    private func healthCard(name: String, status: String?, detail: String?, icon: String, color: Color) -> some View {
        let isOk = status?.lowercased() == "connected" || status?.lowercased() == "ok" || status?.lowercased() == "healthy"
        let statusColor = isOk ? DesignTokens.Colors.chzzkGreen : .red

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(status ?? "알 수 없음")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(statusColor)
                    .textCase(.uppercase)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func recordPill(title: String, count: Int?, icon: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(count.map { formatLargeNumber($0) } ?? "—")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private var systemLoadingPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("시스템 데이터 로딩 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        sectionContainer(title: "수집 메트릭", icon: "chart.bar.doc.horizontal") {
            VStack(spacing: DesignTokens.Spacing.sm) {
                // 첫 줄: 트래픽 메트릭
                HStack(spacing: DesignTokens.Spacing.sm) {
                    metricTile(
                        title: "실시간 수신",
                        value: viewModel.wsMessageCount > 0 ? formatLargeNumber(viewModel.wsMessageCount) : "—",
                        subtitle: viewModel.wsMessageCount > 0 ? "WebSocket" : "대기 중",
                        icon: "bolt.circle.fill",
                        color: viewModel.wsMessageCount > 0 ? .yellow : .gray
                    )
                    metricTile(
                        title: "웹 레이턴시",
                        value: viewModel.avgWebLatency.map { String(format: "%.0fms", $0) } ?? "—",
                        subtitle: viewModel.avgWebLatency != nil ? "평균" : "데이터 없음",
                        icon: "globe",
                        color: viewModel.avgWebLatency != nil ? DesignTokens.Colors.accentCyan : .gray
                    )
                    metricTile(
                        title: "CView 레이턴시",
                        value: viewModel.avgAppLatency.map { String(format: "%.0fms", $0) } ?? "—",
                        subtitle: viewModel.avgAppLatency != nil ? "평균" : "데이터 없음",
                        icon: "desktopcomputer",
                        color: viewModel.avgAppLatency != nil ? DesignTokens.Colors.chzzkGreen : .gray
                    )
                }

                // 둘째 줄: 클라이언트 메트릭
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let stats = viewModel.serverStats {
                        let platforms = stats.resolvedPlatforms
                        metricTile(
                            title: "플랫폼",
                            value: platforms.isEmpty ? "—" : platforms.map { "\($0.key): \($0.value)" }.joined(separator: ", "),
                            subtitle: nil,
                            icon: "rectangle.stack",
                            color: platforms.isEmpty ? .gray : DesignTokens.Colors.accentPurple
                        )
                    }
                    metricTile(
                        title: "CView 클라이언트",
                        value: "\(viewModel.serverStats?.cviewSummary?.connectedClients ?? 0)",
                        subtitle: viewModel.serverStats?.cviewSummary.map { cviewSyncLabel($0) },
                        icon: "monitor.and.phone",
                        color: (viewModel.serverStats?.cviewSummary?.connectedClients ?? 0) > 0 ? DesignTokens.Colors.accentPurple : .gray
                    )
                    syncQualityTile
                }
            }
        }
    }

    private func metricTile(title: String, value: String, subtitle: String?, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Text(value)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var syncQualityTile: some View {
        if let cview = viewModel.serverStats?.cviewSummary {
            if let grade = cview.aggregate?.qualityGrade, grade != "-" {
                metricTile(
                    title: "동기화 품질",
                    value: grade,
                    subtitle: cviewAggregateSubtitle(cview),
                    icon: "gauge.with.needle",
                    color: gradeColor(grade)
                )
            } else if let agg = cview.aggregate, (agg.waitingChannels ?? 0) > 0 {
                metricTile(
                    title: "동기화 품질",
                    value: "–",
                    subtitle: "웹 데이터 대기 중 (\(agg.waitingChannels ?? 0)채널)",
                    icon: "gauge.with.needle",
                    color: .gray
                )
            } else {
                metricTile(
                    title: "동기화 품질",
                    value: "—",
                    subtitle: "대기 중",
                    icon: "gauge.with.needle",
                    color: .gray
                )
            }
        } else {
            metricTile(
                title: "동기화 품질",
                value: "—",
                subtitle: "대기 중",
                icon: "gauge.with.needle",
                color: .gray
            )
        }
    }

    // MARK: - Analytics

    private var analyticsSection: some View {
        sectionContainer(title: "분석", icon: "chart.xyaxis.line") {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                LatencyComparisonChart(history: viewModel.latencyHistory)
                    .frame(maxWidth: .infinity)
                latencyDistributionChart
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var latencyDistributionChart: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("채널별 레이턴시 분포")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                // 범례
                HStack(spacing: DesignTokens.Spacing.sm) {
                    legendDot(color: .cyan, label: "웹")
                    legendDot(color: DesignTokens.Colors.chzzkGreen, label: "앱")
                }
            }

            if viewModel.serverChannelStats.isEmpty {
                emptyChartState
            } else {
                let hasAnyData = viewModel.serverChannelStats.contains { ch in
                    ((ch.web?.samples ?? 0) > 0 && ch.web?.avg != nil) ||
                    ((ch.app?.samples ?? 0) > 0 && ch.app?.avg != nil)
                }
                if !hasAnyData {
                    emptyChartState
                } else {
                    Chart(viewModel.serverChannelStats) { stat in
                        let channelName = stat.channelName ?? stat.channelId.prefix(8).description
                        if let web = stat.web, (web.samples ?? 0) > 0, let webAvg = web.avg {
                            BarMark(
                                x: .value("채널", channelName),
                                y: .value("레이턴시", webAvg)
                            )
                            .foregroundStyle(.cyan.opacity(0.75))
                            .position(by: .value("타입", "웹"))
                            .cornerRadius(3)
                            .annotation(position: .top, spacing: 2) {
                                Text(String(format: "%.0f", webAvg))
                                    .font(DesignTokens.Typography.custom(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                        if let app = stat.app, (app.samples ?? 0) > 0, let appAvg = app.avg {
                            BarMark(
                                x: .value("채널", channelName),
                                y: .value("레이턴시", appAvg)
                            )
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.75))
                            .position(by: .value("타입", "앱"))
                            .cornerRadius(3)
                            .annotation(position: .top, spacing: 2) {
                                Text(String(format: "%.0f", appAvg))
                                    .font(DesignTokens.Typography.custom(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
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
                    .chartLegend(.hidden)
                    .frame(height: 160)
                    .drawingGroup()
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private var emptyChartState: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                Text("데이터 수집 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 160)
    }

    // MARK: - Channel Detail

    private var channelDetailSection: some View {
        sectionContainer(title: "채널 상세", icon: "antenna.radiowaves.left.and.right") {
            if viewModel.serverChannelStats.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                        Text("활성 채널이 없습니다")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("스트림을 시청하면 자동으로 메트릭이 수집됩니다")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                    ForEach(viewModel.serverChannelStats) { stat in
                        channelDetailCard(stat)
                    }
                }
            }
        }
    }

    private func channelDetailCard(_ stat: ChannelStatsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text(stat.channelName ?? stat.channelId.prefix(12).description)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let quality = stat.quality {
                    Text(quality)
                        .font(DesignTokens.Typography.microSemibold)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: Capsule())
                }
            }
            .padding(DesignTokens.Spacing.md)

            // 스트림 정보 태그
            if let resolution = stat.resolution {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    streamTag(icon: "display", text: resolution)
                    if let bitrate = stat.bitrate {
                        streamTag(icon: "speedometer", text: String(format: "%.1f Mbps", bitrate))
                    }
                    if let fps = stat.fps {
                        streamTag(icon: "film", text: String(format: "%.0f fps", fps))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
            }

            // 레이턴시 비교 바
            HStack(spacing: 0) {
                latencyCell(title: "웹", stats: stat.web, color: .cyan)
                Rectangle().fill(DesignTokens.Glass.borderColor).frame(width: 0.5)
                latencyCell(title: "CView", stats: stat.app, color: DesignTokens.Colors.chzzkGreen)
                if let delta = stat.delta {
                    Rectangle().fill(DesignTokens.Glass.borderColor).frame(width: 0.5)
                    deltaCell(delta: delta)
                }
            }
            .background(DesignTokens.Colors.surfaceBase.opacity(0.5))

            // 방송 정보
            if let broadcast = stat.broadcast, broadcast.title != nil {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    if let title = broadcast.title {
                        Text(title)
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let category = broadcast.category {
                            streamTag(icon: "tag", text: category)
                        }
                        if let viewers = broadcast.concurrentUsers {
                            streamTag(icon: "person.2", text: formatLargeNumber(viewers))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }

            // CView 동기화 정보
            if let syncChannel = viewModel.serverStats?.cviewSummary?.syncChannels?.first(where: { $0.channelId == stat.channelId }),
               let rec = syncChannel.recommendation {
                Rectangle().fill(DesignTokens.Glass.borderColor).frame(height: 0.5)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: cviewActionIcon(rec.action))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(syncActionColor(rec.action))
                    Text(cviewActionLabel(rec.action))
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(syncActionColor(rec.action))

                    Spacer()

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let tier = rec.tier {
                            syncBadge(text: tier)
                        }
                        if let speed = rec.suggestedSpeed, speed != 1.0 {
                            syncBadge(text: String(format: "%.2fx", speed))
                        }
                        if let delta = rec.delta {
                            syncBadge(text: String(format: "%+.0fms", delta))
                        }
                        if let confidence = rec.confidence {
                            syncBadge(text: String(format: "%.0f%%", confidence * 100))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func streamTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(text)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 2)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.6), in: Capsule())
    }

    private func latencyCell(title: String, stats: LatencyStats?, color: Color) -> some View {
        let hasSamples = (stats?.samples ?? 0) > 0
        return VStack(spacing: DesignTokens.Spacing.xs) {
            Text(title.uppercased())
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                .foregroundStyle(color)
                .tracking(0.5)

            if let stats, hasSamples, let avg = stats.avg {
                Text(String(format: "%.0fms", avg))
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: DesignTokens.Spacing.xs) {
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
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func deltaCell(delta: DeltaStats) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text("DELTA")
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .tracking(0.5)

            if let current = delta.current {
                Text(String(format: "%+.0fms", current))
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(current > 0 ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.chzzkGreen)
            }
            if let avg = delta.avg {
                Text(String(format: "avg %+.0f", avg))
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func syncBadge(text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, 2)
            .background(DesignTokens.Colors.surfaceBase.opacity(0.6), in: Capsule())
    }

    private func syncActionColor(_ action: String?) -> Color {
        switch action {
        case "hold": return DesignTokens.Colors.chzzkGreen
        case "speed_up": return DesignTokens.Colors.accentOrange
        case "slow_down": return DesignTokens.Colors.accentBlue
        case "waiting": return DesignTokens.Colors.textTertiary
        default: return DesignTokens.Colors.textTertiary
        }
    }

    // MARK: - Section Container

    private func sectionContainer<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Rectangle()
                    .fill(DesignTokens.Glass.borderColor)
                    .frame(height: 0.5)
            }
            content()
        }
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000.0) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000.0) }
        return "\(n)"
    }

    private func cviewSyncLabel(_ summary: CViewStatsSummary) -> String {
        guard let channels = summary.syncChannels, !channels.isEmpty else {
            return "대기 중"
        }
        let actions = channels.compactMap { $0.recommendation?.action }
        if actions.allSatisfy({ $0 == "hold" }) { return "동기화 양호" }
        if actions.contains("speed_up") { return "가속 중" }
        if actions.contains("slow_down") { return "감속 중" }
        return "대기 중"
    }

    private func cviewActionIcon(_ action: String?) -> String {
        switch action {
        case "hold": return "checkmark.circle"
        case "speed_up": return "hare"
        case "slow_down": return "tortoise"
        case "waiting": return "hourglass"
        default: return "questionmark.circle"
        }
    }

    private func cviewActionLabel(_ action: String?) -> String {
        switch action {
        case "hold": return "동기화 양호"
        case "speed_up": return "가속 필요"
        case "slow_down": return "감속 필요"
        case "waiting": return "대기 중"
        default: return "알 수 없음"
        }
    }

    private func cviewAggregateSubtitle(_ summary: CViewStatsSummary) -> String {
        guard let agg = summary.aggregate else { return "" }
        let rate = agg.syncRate ?? 0
        let avg = agg.avgDeltaAbs ?? 0
        return String(format: "%.0f%% · %.0fms", rate, avg)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "S": return DesignTokens.Colors.chzzkGreen
        case "A": return DesignTokens.Colors.accentCyan
        case "B": return DesignTokens.Colors.accentOrange
        case "C": return DesignTokens.Colors.accentOrange
        case "D": return .red
        default: return .gray
        }
    }
}
