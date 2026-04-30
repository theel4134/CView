// MARK: - SystemUsageWindowView.swift
// CViewApp - 앱 프로세스 시스템 사용률 모니터 창
// - 상단 앱 메뉴바 "보기 > 시스템 사용률 모니터"로 열림
// - CPU / GPU / Memory / Threads 실시간(1s) 모니터링

import SwiftUI
import CViewCore
import CViewMonitoring

struct SystemUsageWindowView: View {

    @Environment(AppState.self) private var appState

    @State private var snapshot: PerformanceMonitor.SystemUsageSnapshot?
    @State private var pollTask: Task<Void, Never>?
    @State private var history: [Double] = []  // CPU 사용률 히스토리 (0~maxCPU)
    @State private var memHistory: [Double] = [] // 메모리 MB 히스토리

    private let maxCPU: Double = Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0
    private let historyLimit = 60  // 60초

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header
            Divider()
            if let s = snapshot {
                gaugeRow(snapshot: s)
                Divider()
                metricsGrid(snapshot: s)
                Divider()
                sparklineSection
            } else {
                placeholder
            }
            Spacer()
            footer
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minWidth: 380, minHeight: 420)
        .background(DesignTokens.Colors.background)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "cpu")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            Text("앱 시스템 사용률")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: 6, height: 6)
                Text("실시간")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    // MARK: - Gauges

    private func gaugeRow(snapshot s: PerformanceMonitor.SystemUsageSnapshot) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            gauge(
                title: "CPU",
                value: s.cpuPercent,
                ratio: min(max(s.cpuPercent / maxCPU, 0), 1),
                display: String(format: "%.1f%%", s.cpuPercent),
                subtitle: "\(ProcessInfo.processInfo.activeProcessorCount) cores"
            )
            gauge(
                title: "GPU",
                value: s.gpuPercent,
                ratio: min(max(s.gpuPercent / 100.0, 0), 1),
                display: String(format: "%.1f%%", s.gpuPercent),
                subtitle: "Device"
            )
        }
    }

    private func gauge(title: String, value: Double, ratio: Double, display: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Colors.surfaceElevated, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(barColor(for: ratio), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: ratio)

                VStack(spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(display)
                        .font(DesignTokens.Typography.custom(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
            }
            .frame(width: 110, height: 110)

            Text(subtitle)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metrics Grid

    private func metricsGrid(snapshot s: PerformanceMonitor.SystemUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("메트릭")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack(spacing: DesignTokens.Spacing.xs) {
                metricTile(icon: "memorychip", title: "메모리", value: formatMB(s.memoryMB), color: memoryColor(s.memoryMB))
                metricTile(icon: "square.stack.3d.up", title: "스레드", value: "\(s.threadCount)", color: DesignTokens.Colors.textSecondary)
                if s.gpuMemoryMB > 0 {
                    metricTile(icon: "display", title: "GPU Mem", value: formatMB(s.gpuMemoryMB), color: DesignTokens.Colors.textSecondary)
                }
            }
        }
    }

    private func metricTile(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10))
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text(value)
                .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - Sparkline

    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU 추이 (60s)")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                if let last = history.last {
                    Text(String(format: "%.0f%%", last))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            GeometryReader { geo in
                sparkPath(in: geo.size, values: history, max: maxCPU)
                    .stroke(DesignTokens.Colors.chzzkGreen, lineWidth: 1.5)
            }
            .frame(height: 44)
            .padding(DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    private func sparkPath(in size: CGSize, values: [Double], max maxValue: Double) -> Path {
        Path { p in
            guard values.count >= 2, maxValue > 0 else { return }
            let step = size.width / CGFloat(max(values.count - 1, 1))
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height * (1 - CGFloat(min(v / maxValue, 1)))
                if i == 0 {
                    p.move(to: CGPoint(x: x, y: y))
                } else {
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    // MARK: - Placeholder / Footer

    private var placeholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("사용률 측정 중...")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("1초마다 갱신")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Spacer()
            if let s = snapshot {
                Text(s.timestamp, style: .time)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        let first = appState.performanceMonitor.systemUsageSnapshot()
        snapshot = first
        appendHistory(cpu: first.cpuPercent, mem: first.memoryMB)

        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                let s = appState.performanceMonitor.systemUsageSnapshot()
                snapshot = s
                appendHistory(cpu: s.cpuPercent, mem: s.memoryMB)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func appendHistory(cpu: Double, mem: Double) {
        history.append(cpu)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        memHistory.append(mem)
        if memHistory.count > historyLimit { memHistory.removeFirst(memHistory.count - historyLimit) }
    }

    // MARK: - Helpers

    private func barColor(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.5: return DesignTokens.Colors.chzzkGreen
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    private func memoryColor(_ mb: Double) -> Color {
        switch mb {
        case ..<500: return DesignTokens.Colors.textPrimary
        case ..<1000: return .yellow
        default: return .red
        }
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }
}
