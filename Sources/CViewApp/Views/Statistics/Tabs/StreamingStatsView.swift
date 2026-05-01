// MARK: - Statistics/Tabs/StreamingStatsView.swift
// 스트리밍 탭 — 지연·버퍼·재생속도 + 지연 차트 + 네트워크 진단(비트레이트/다운속도/드랍프레임)
// 보강: 화질 리스트에 해상도 표기, PerformanceMonitor.currentMetrics 폴링으로 네트워크 진단 추가.

import SwiftUI
import Charts
import CViewCore
import CViewMonitoring
import CViewPlayer
import CViewUI

struct StreamingStatsView: View {
    @Environment(AppState.self) private var appState

    /// PerformanceMonitor.currentMetrics 스냅샷 (5초 폴링). actor hop 비용 절감 위해 Task 한 개로 통일.
    @State private var perf: PerformanceMonitor.Metrics? = nil
    @State private var pollTask: Task<Void, Never>? = nil

    /// 단일/멀티라이브 어느 쪽이든 현재 재생 중인 PVM
    private var activePVM: PlayerViewModel? { appState.activePlayerViewModel }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 핵심 KPI 3개
                StatSection("스트리밍 품질", icon: "waveform", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "지연 시간",
                            value: activePVM?.formattedLatency ?? "-",
                            icon: "clock.arrow.2.circlepath",
                            color: latencyChartColor
                        )
                        StatCard(
                            title: "버퍼 상태",
                            value: bufferStatusText,
                            icon: "chart.bar.fill",
                            color: bufferStatusColor
                        )
                        StatCard(
                            title: "재생 속도",
                            value: activePVM?.formattedPlaybackRate ?? "1.0x",
                            icon: "speedometer",
                            color: DesignTokens.Colors.accentOrange
                        )
                    }
                }

                // ── 레이턴시 추이 차트
                if let history = activePVM?.latencyHistory, history.count >= 2 {
                    latencyChartSection(history: history)
                } else {
                    StatSection("레이턴시 추이", icon: "chart.xyaxis.line", color: DesignTokens.Colors.accentBlue) {
                        EmptyStatePlaceholder(
                            icon: "chart.xyaxis.line",
                            title: "데이터 수집 중",
                            subtitle: "재생 시작 후 몇 초가 지나면 차트가 표시됩니다"
                        )
                    }
                }

                // ── 네트워크 진단 (신규 섹션)
                StatSection("네트워크 진단", icon: "network", color: DesignTokens.Colors.accentCyan) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        KPICard(
                            title: "비트레이트",
                            value: bitrateText,
                            subValue: "kbps",
                            icon: "bolt.horizontal",
                            color: DesignTokens.Colors.accentCyan
                        )
                        KPICard(
                            title: "다운로드 속도",
                            value: downloadSpeedText,
                            subValue: downloadSpeedUnit,
                            icon: "arrow.down.circle.fill",
                            color: DesignTokens.Colors.accentBlue
                        )
                        KPICard(
                            title: "드랍 프레임",
                            value: droppedFramesText,
                            subValue: nil,
                            icon: "exclamationmark.triangle.fill",
                            color: droppedFramesColor,
                            status: droppedFramesStatus
                        )
                    }
                }

                // ── 화질 정보
                StatSection("화질 정보", icon: "sparkles", color: DesignTokens.Colors.accentBlue) {
                    if let qualities = activePVM?.availableQualities, !qualities.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(qualities) { q in
                                qualityRow(q)
                            }
                        }
                    } else {
                        EmptyStatePlaceholder(
                            icon: "sparkles",
                            title: "화질 정보 없음",
                            subtitle: nil
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .contentBackground()
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel(); pollTask = nil }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        let monitor = appState.performanceMonitor
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                self.perf = await monitor.currentMetrics
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    // MARK: - Buffer status (idle 일 때는 "-" 표시, 재생 중이면 health 기준)

    private var bufferStatusText: String {
        guard let pvm = activePVM, pvm.streamPhase != .idle else { return "-" }
        if let bh = pvm.bufferHealth { return bh.isHealthy ? "정상" : "부족" }
        return "-"
    }

    private var bufferStatusColor: Color {
        guard let pvm = activePVM, pvm.streamPhase != .idle else { return DesignTokens.Colors.textTertiary }
        if let bh = pvm.bufferHealth {
            return bh.isHealthy ? DesignTokens.Colors.chzzkGreen : .red
        }
        return DesignTokens.Colors.textTertiary
    }

    // MARK: - Latency Chart Section

    @ViewBuilder
    private func latencyChartSection(history: [LatencyDataPoint]) -> some View {
        StatSection("레이턴시 추이", icon: "chart.xyaxis.line", color: latencyChartColor) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if let current = activePVM?.latencyInfo?.current {
                    HStack(spacing: 6) {
                        Circle().fill(latencyColor(for: current)).frame(width: 8, height: 8)
                        Text(String(format: "현재 %.1f초", current))
                            .font(DesignTokens.Typography.custom(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(latencyColor(for: current))
                    }
                }

                Chart(history) { point in
                    AreaMark(
                        x: .value("시간", point.timestamp),
                        y: .value("레이턴시", point.latency)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [latencyChartColor.opacity(0.3), latencyChartColor.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("시간", point.timestamp),
                        y: .value("레이턴시", point.latency)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(latencyChartColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYAxisLabel("레이턴시 (초)")
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DesignTokens.Colors.border.opacity(0.3))
                        AxisValueLabel()
                            .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(DesignTokens.Colors.border.opacity(0.2))
                        AxisValueLabel(format: .dateTime.minute().second())
                            .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(height: 180)

                HStack(spacing: DesignTokens.Spacing.md) {
                    legendDot(color: .green, label: "< 3초")
                    legendDot(color: .yellow, label: "3-5초")
                    legendDot(color: .red, label: "> 5초")
                }
                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Quality row

    @ViewBuilder
    private func qualityRow(_ q: StreamQualityInfo) -> some View {
        let isCurrent = (q.id == activePVM?.currentQuality?.id)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(q.name)
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let res = perf?.resolution, isCurrent {
                    Text(res)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            if isCurrent {
                HStack(spacing: 4) {
                    Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 6, height: 6)
                    Text("현재")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            isCurrent ? DesignTokens.Colors.chzzkGreen.opacity(0.08) : DesignTokens.Colors.surfaceBase
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - Helpers

    private var latencyChartColor: Color {
        guard let current = activePVM?.latencyInfo?.current else { return .green }
        return latencyColor(for: current)
    }

    private func latencyColor(for value: Double) -> Color {
        if value < 3 { return .green }
        if value < 5 { return .yellow }
        return .red
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Network diagnostics formatters

    private var bitrateText: String {
        guard let v = perf?.inputBitrateKbps, v > 0 else { return "-" }
        return String(format: "%.0f", v)
    }

    private var downloadSpeedText: String {
        guard let bps = perf?.networkSpeedBytesPerSec, bps > 0 else { return "-" }
        let mb = Double(bps) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f", mb)
        }
        let kb = Double(bps) / 1024.0
        return String(format: "%.0f", kb)
    }

    private var downloadSpeedUnit: String? {
        guard let bps = perf?.networkSpeedBytesPerSec, bps > 0 else { return nil }
        let mb = Double(bps) / (1024.0 * 1024.0)
        return mb >= 1.0 ? "MB/s" : "KB/s"
    }

    private var droppedFramesText: String {
        guard let d = perf?.droppedFrames else { return "0" }
        return "\(d)"
    }

    private var droppedFramesColor: Color {
        guard let d = perf?.droppedFrames, d > 0 else { return DesignTokens.Colors.textTertiary }
        if d < 10 { return .yellow }
        return .red
    }

    private var droppedFramesStatus: KPICard.Status? {
        guard let d = perf?.droppedFrames else { return .good }
        if d == 0 { return .good }
        if d < 10 { return .warning }
        return .critical
    }
}
