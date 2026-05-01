// MARK: - Statistics/Tabs/PerformanceStatsView.swift
// 성능 탭 (신규) — FPS / CPU / GPU / 메모리 / Thermal
// 데이터: PerformanceMonitor.metrics() AsyncStream 직접 구독.
// 직전 60 포인트(약 10분)를 in-view 누적해 4-시리즈 라인 차트로 표시한다.

import SwiftUI
import Charts
import CViewCore
import CViewMonitoring
import CViewUI

struct PerformanceStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var samples: [PerformanceMonitor.Metrics] = []
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var memoryWarningCount: Int = 0

    /// 최근 sparkline 표시용 (최근 20포인트)
    private var fpsSparkline: [Double] { samples.suffix(20).map { $0.fps } }
    private var cpuSparkline: [Double] { samples.suffix(20).map { $0.cpuUsage } }
    private var gpuSparkline: [Double] { samples.suffix(20).map { $0.gpuUsagePercent } }
    private var memSparkline: [Double] { samples.suffix(20).map { $0.memoryUsageMB } }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── Thermal 경고 배너
                if let latest = samples.last, isThermalWarning(latest.thermalState) {
                    thermalBanner(state: latest.thermalState)
                }

                // ── 핵심 KPI
                StatSection("리소스 사용량", icon: "speedometer", color: DesignTokens.Colors.accentCyan) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        KPICard(
                            title: "FPS",
                            value: fpsValue,
                            subValue: "fps",
                            icon: "gauge.with.dots.needle.50percent",
                            color: DesignTokens.Colors.chzzkGreen,
                            sparkline: fpsSparkline.count >= 2 ? fpsSparkline : nil,
                            status: fpsStatus
                        )
                        KPICard(
                            title: "CPU",
                            value: cpuValue,
                            subValue: "%",
                            icon: "cpu.fill",
                            color: DesignTokens.Colors.accentBlue,
                            sparkline: cpuSparkline.count >= 2 ? cpuSparkline : nil,
                            status: cpuStatus
                        )
                        KPICard(
                            title: "GPU",
                            value: gpuValue,
                            subValue: "%",
                            icon: "rectangle.stack.fill.badge.person.crop",
                            color: DesignTokens.Colors.accentPurple,
                            sparkline: gpuSparkline.count >= 2 ? gpuSparkline : nil,
                            status: gpuStatus
                        )
                        KPICard(
                            title: "메모리",
                            value: memValue,
                            subValue: "MB",
                            icon: "memorychip.fill",
                            color: DesignTokens.Colors.accentOrange,
                            sparkline: memSparkline.count >= 2 ? memSparkline : nil
                        )
                    }
                }

                // ── 부가 KPI
                StatSection("시스템 상태", icon: "thermometer.medium", color: DesignTokens.Colors.accentPink) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "Thermal",
                            value: thermalText,
                            icon: "thermometer.medium",
                            color: thermalColor
                        )
                        StatCard(
                            title: "GPU 메모리",
                            value: gpuMemText,
                            icon: "memorychip",
                            color: DesignTokens.Colors.accentPurple
                        )
                        StatCard(
                            title: "메모리 경고",
                            value: "\(memoryWarningCount)회",
                            icon: "exclamationmark.triangle.fill",
                            color: memoryWarningCount > 0 ? .red : DesignTokens.Colors.textTertiary
                        )
                    }
                }

                // ── 4-시리즈 시계열 차트
                StatSection("리소스 추이", icon: "chart.line.uptrend.xyaxis", color: DesignTokens.Colors.accentBlue) {
                    if samples.count >= 2 {
                        timeseriesChart
                            .padding(DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                            }
                    } else {
                        EmptyStatePlaceholder(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "데이터 수집 중",
                            subtitle: "PerformanceMonitor 가 약 10초 간격으로 샘플링합니다"
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .contentBackground()
        .onAppear { startStreaming() }
        .onDisappear { streamTask?.cancel(); streamTask = nil }
    }

    // MARK: - Stream subscription

    private func startStreaming() {
        streamTask?.cancel()
        let monitor = appState.performanceMonitor
        streamTask = Task { @MainActor in
            // 1) 초기 스냅샷이 있으면 미리 채워넣기 (탭 진입 즉시 빈 화면 방지)
            if let initial = await monitor.currentMetrics {
                samples = [initial]
            }
            // 2) AsyncStream 으로 신규 샘플 수신
            for await m in await monitor.metrics() {
                if Task.isCancelled { break }
                samples.append(m)
                // 직전 60 포인트(약 10분)만 유지
                if samples.count > 60 { samples.removeFirst(samples.count - 60) }
            }
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private func thermalBanner(state: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "thermometer.high")
                .font(DesignTokens.Typography.bodyBold)
                .foregroundStyle(thermalColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Thermal: \(state)")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("시스템 열 상태가 높습니다. 화질을 낮추거나 다른 앱을 종료해 보세요.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .background(thermalColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(thermalColor.opacity(0.4), lineWidth: 0.7)
        }
    }

    // MARK: - Multi-series chart

    @ViewBuilder
    private var timeseriesChart: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Chart {
                ForEach(samples, id: \.timestamp) { s in
                    LineMark(
                        x: .value("시간", s.timestamp),
                        y: .value("값", s.fps),
                        series: .value("series", "FPS")
                    )
                    .foregroundStyle(by: .value("시리즈", "FPS"))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("시간", s.timestamp),
                        y: .value("값", s.cpuUsage),
                        series: .value("series", "CPU%")
                    )
                    .foregroundStyle(by: .value("시리즈", "CPU%"))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("시간", s.timestamp),
                        y: .value("값", s.gpuUsagePercent),
                        series: .value("series", "GPU%")
                    )
                    .foregroundStyle(by: .value("시리즈", "GPU%"))
                    .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale([
                "FPS": DesignTokens.Colors.chzzkGreen,
                "CPU%": DesignTokens.Colors.accentBlue,
                "GPU%": DesignTokens.Colors.accentPurple
            ])
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(DesignTokens.Colors.border.opacity(0.2))
                    AxisValueLabel(format: .dateTime.minute().second())
                        .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
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
            .frame(height: 200)

            // 메모리는 단위가 다르므로 별도 미니 차트
            Text("메모리 (MB)")
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Chart {
                ForEach(samples, id: \.timestamp) { s in
                    AreaMark(
                        x: .value("시간", s.timestamp),
                        y: .value("MB", s.memoryUsageMB)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(
                        colors: [DesignTokens.Colors.accentOrange.opacity(0.35),
                                 DesignTokens.Colors.accentOrange.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(
                        x: .value("시간", s.timestamp),
                        y: .value("MB", s.memoryUsageMB)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(DesignTokens.Colors.border.opacity(0.3))
                    AxisValueLabel()
                        .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .frame(height: 70)
        }
    }

    // MARK: - Computed values

    private var latest: PerformanceMonitor.Metrics? { samples.last }

    private var fpsValue: String {
        guard let v = latest?.fps else { return "-" }
        return String(format: "%.0f", v)
    }
    private var cpuValue: String {
        guard let v = latest?.cpuUsage else { return "-" }
        return String(format: "%.0f", v)
    }
    private var gpuValue: String {
        guard let v = latest?.gpuUsagePercent else { return "-" }
        return String(format: "%.0f", v)
    }
    private var memValue: String {
        guard let v = latest?.memoryUsageMB else { return "-" }
        return String(format: "%.0f", v)
    }
    private var gpuMemText: String {
        guard let v = latest?.gpuMemoryUsedMB, v > 0 else { return "-" }
        return String(format: "%.0f MB", v)
    }

    // MARK: - Status

    private var fpsStatus: KPICard.Status? {
        guard let v = latest?.fps, v > 0 else { return nil }
        if v >= 55 { return .good }
        if v >= 30 { return .warning }
        return .critical
    }
    private var cpuStatus: KPICard.Status? {
        guard let v = latest?.cpuUsage else { return nil }
        if v < 50 { return .good }
        if v < 80 { return .warning }
        return .critical
    }
    private var gpuStatus: KPICard.Status? {
        guard let v = latest?.gpuUsagePercent else { return nil }
        if v < 60 { return .good }
        if v < 85 { return .warning }
        return .critical
    }

    // MARK: - Thermal

    private var thermalText: String {
        latest?.thermalState ?? "-"
    }

    private var thermalColor: Color {
        switch latest?.thermalState {
        case "nominal": return DesignTokens.Colors.chzzkGreen
        case "fair": return .yellow
        case "serious": return .orange
        case "critical": return .red
        default: return DesignTokens.Colors.textTertiary
        }
    }

    private func isThermalWarning(_ state: String) -> Bool {
        state == "serious" || state == "critical"
    }
}
