// MARK: - DashboardCharts.swift
// Swift Charts — 시청자 트렌드 + 카테고리 TOP5 + 레이턴시 비교 + 서버 채널 통계

import SwiftUI
import Charts
import CViewCore

// MARK: - Viewer Trend Chart

struct ViewerTrendChart: View {
    let history: [ViewerHistoryEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("시청자 트렌드")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            if history.count < 2 {
                emptyState
            } else {
                Chart(history) { entry in
                    AreaMark(
                        x: .value("시간", entry.timestamp),
                        y: .value("시청자", entry.totalViewers)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen.opacity(0.2),
                                DesignTokens.Colors.chzzkGreen.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("시간", entry.timestamp),
                        y: .value("시청자", entry.totalViewers)
                    )
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
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
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .frame(height: 140)
                .drawingGroup()
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
    
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
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
}

// MARK: - Category Bar Chart

struct CategoryBarChart: View {
    let categories: [CategoryStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("인기 카테고리 TOP 5")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            if categories.isEmpty {
                emptyState
            } else {
                Chart(categories) { cat in
                    BarMark(
                        x: .value("시청자", cat.totalViewers),
                        y: .value("카테고리", cat.name)
                    )
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                    .cornerRadius(DesignTokens.Radius.xs)
                    .annotation(position: .trailing, spacing: 4) {
                        Text(formatViewerCount(cat.totalViewers))
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .frame(height: CGFloat(categories.count) * 32 + 16)
                .drawingGroup()
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
    
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("카테고리 데이터 없음")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 100)
    }
    
    private func formatViewerCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// MARK: - Latency Comparison Chart (Web vs App)

struct LatencyComparisonChart: View {
    let history: [LatencyHistoryEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("레이턴시 비교")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                HStack(spacing: 12) {
                    legendDot(color: .cyan, label: "웹")
                    legendDot(color: DesignTokens.Colors.chzzkGreen, label: "앱")
                }
            }
            
            if history.isEmpty {
                latencyEmptyState
            } else {
                Chart {
                    ForEach(history) { entry in
                        if let web = entry.webLatency {
                            LineMark(
                                x: .value("시간", entry.timestamp),
                                y: .value("레이턴시", web),
                                series: .value("종류", "웹")
                            )
                            .foregroundStyle(.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)
                        }
                        
                        if let app = entry.appLatency {
                            LineMark(
                                x: .value("시간", entry.timestamp),
                                y: .value("레이턴시", app),
                                series: .value("종류", "앱")
                            )
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
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
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .frame(height: 140)
                .drawingGroup()
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
    
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
    
    private var latencyEmptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("레이턴시 데이터 수집 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 140)
    }
}

// MARK: - Category Type Donut Chart (GAME / SPORTS / ETC)

struct CategoryTypeDonutChart: View {
    let distribution: [CategoryTypeStat]

    private func color(for type: String) -> Color {
        switch type {
        case "GAME":   return DesignTokens.Colors.accentBlue
        case "SPORTS": return DesignTokens.Colors.accentOrange
        default:       return DesignTokens.Colors.accentPurple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("콘텐츠 유형 분포")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if distribution.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "chart.pie")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("데이터 수집 중...")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                    Chart(distribution) { item in
                        SectorMark(
                            angle: .value("채널수", item.channelCount),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(color(for: item.type))
                        .cornerRadius(DesignTokens.Radius.xs)
                    }
                    .frame(width: 110, height: 110)
                    .drawingGroup()

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(distribution) { item in
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                    .fill(color(for: item.type))
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(DesignTokens.Typography.captionSemibold)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    Text(String(format: "%.0f%%  ·  %d채널", item.percentage, item.channelCount))
                                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
}

// MARK: - Viewer Distribution Chart (시청자수 구간 분포)

struct ViewerDistributionChart: View {
    let buckets: [ViewerBucket]
    let medianViewers: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("시청자수 분포")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if medianViewers > 0 {
                    HStack(spacing: 4) {
                        Text("중앙값")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text(formatViewerCount(medianViewers))
                            .font(DesignTokens.Typography.custom(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                    .clipShape(Capsule())
                }
            }

            if buckets.isEmpty || buckets.allSatisfy({ $0.count == 0 }) {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("데이터 수집 중...")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("구간", bucket.label),
                        y: .value("채널수", bucket.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.accentBlue.opacity(0.9),
                                DesignTokens.Colors.accentBlue.opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(DesignTokens.Radius.xs)
                    .annotation(position: .top, spacing: 3) {
                        if bucket.count > 0 {
                            Text("\(bucket.count)")
                                .font(DesignTokens.Typography.microSemibold)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DesignTokens.Colors.border)
                        AxisValueLabel()
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(DesignTokens.Typography.micro)
                    }
                }
                .chartPlotStyle { plotArea in plotArea.background(Color.clear) }
                .frame(height: 120)
                .drawingGroup()
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private func formatViewerCount(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1f만", Double(count) / 10_000.0) }
        if count >= 1_000  { return String(format: "%.1f천", Double(count) / 1_000.0) }
        return "\(count)"
    }
}

// MARK: - Server Channel Stats View

struct ServerChannelStatsView: View {
    let channelStats: [ChannelStatsItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("채널별 레이턴시")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            if channelStats.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("활성 채널 없음")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .frame(height: 140)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(channelStats.prefix(5))) { stat in
                        channelStatRow(stat)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
    
    private func channelStatRow(_ stat: ChannelStatsItem) -> some View {
        HStack(spacing: 8) {
            Text(stat.channelName ?? stat.channelId.prefix(8).description)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let webAvg = stat.web?.avg {
                HStack(spacing: 3) {
                    Circle().fill(.cyan).frame(width: 4, height: 4)
                    Text(String(format: "%.0f", webAvg))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(width: 50, alignment: .trailing)
            }
            
            if let appAvg = stat.app?.avg {
                HStack(spacing: 3) {
                    Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 4, height: 4)
                    Text(String(format: "%.0f", appAvg))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(width: 50, alignment: .trailing)
            }
            
            if let delta = stat.delta?.avg {
                Text(String(format: "%+.0f", delta))
                    .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(delta > 0 ? .orange : DesignTokens.Colors.chzzkGreen)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .background(DesignTokens.Glass.borderColor.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
    }
}
