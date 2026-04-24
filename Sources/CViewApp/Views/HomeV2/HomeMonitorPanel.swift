// MARK: - HomeMonitorPanel.swift
// CViewApp - HomeView_v2 우상단 간이 성능 모니터 패널
//
// CommandBar 의 게이지 토글로 표시/숨김. AppStorage("home.monitor.enabled") 영속.
//
// 측정 지표 (1초 폴링, PerformanceMonitor.systemUsageSnapshot — nonisolated, 가벼움):
//   • CPU%  — 프로세스 누적 (코어수×100 가능)
//   • Mem   — 프로세스 RSS (MB)
//   • GPU%  — Device Utilization (Apple Silicon)
//   • TH    — 활성 스레드 수
//   • LIVE  — viewModel.totalLiveChannelCount
//   • MULTI — appState.multiLiveManager.sessions.count
//   • WS    — viewModel.wsMessageCount (있을 경우)
//
// 패널은 PerformanceMonitor.start() 를 호출하지 않는다 (snapshot 만 사용).
// 따라서 LiveStream 미진입 상태에서도 추가 백그라운드 작업 없이 동작.

import SwiftUI
import CViewCore
import CViewMonitoring

struct HomeMonitorPanel: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState

    @State private var snapshot: PerformanceMonitor.SystemUsageSnapshot?
    @State private var pollTask: Task<Void, Never>?
    @State private var collapsed: Bool = false
    @State private var lastUpdated: Date = .init()

    private let pollInterval: TimeInterval = 1.0

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            header

            if !collapsed {
                Divider().opacity(0.3)
                metricsGrid
                Divider().opacity(0.3)
                appStateRow
                footer
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: collapsed ? 130 : 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .animation(DesignTokens.Animation.fast, value: collapsed)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            Text("모니터")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer(minLength: 0)
            Button {
                collapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(DesignTokens.Colors.surfaceBase, in: Circle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "펼치기" : "접기")
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        VStack(spacing: 4) {
            metricRow(
                icon: "cpu",
                label: "CPU",
                value: snapshot.map { String(format: "%.1f%%", $0.cpuPercent) } ?? "—",
                tint: cpuTint
            )
            metricRow(
                icon: "memorychip",
                label: "MEM",
                value: snapshot.map { String(format: "%.0f MB", $0.memoryMB) } ?? "—",
                tint: memTint
            )
            metricRow(
                icon: "display",
                label: "GPU",
                value: snapshot.map { String(format: "%.1f%%", $0.gpuPercent) } ?? "—",
                tint: gpuTint
            )
            metricRow(
                icon: "circle.grid.cross.fill",
                label: "TH",
                value: snapshot.map { "\($0.threadCount)" } ?? "—",
                tint: DesignTokens.Colors.textSecondary
            )
        }
    }

    @ViewBuilder
    private func metricRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 32, alignment: .leading)
            Spacer(minLength: 4)
            Text(value)
                .font(DesignTokens.Typography.mono)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - App State Row

    private var appStateRow: some View {
        VStack(spacing: 4) {
            kvRow(label: "LIVE", value: "\(viewModel.totalLiveChannelCount)", icon: "dot.radiowaves.left.and.right")
            kvRow(label: "MULTI", value: "\(appState.multiLiveManager.sessions.count)", icon: "square.grid.2x2")
            kvRow(label: "FOLLOW", value: "\(viewModel.followingLiveCount)/\(viewModel.followingChannels.count)", icon: "heart.fill")
        }
    }

    @ViewBuilder
    private func kvRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 14)
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 50, alignment: .leading)
            Spacer(minLength: 4)
            Text(value)
                .font(DesignTokens.Typography.monoMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DesignTokens.Colors.chzzkGreen)
                .frame(width: 5, height: 5)
                .opacity(snapshot == nil ? 0.3 : 1.0)
            Text("\(Int(Date().timeIntervalSince(lastUpdated)))초 전 갱신")
                .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Spacer()
            Text("⏱ \(Int(pollInterval))s")
                .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(.top, 2)
    }

    // MARK: - Tint helpers (임계치 기반 색상)

    private var cpuTint: Color {
        guard let s = snapshot else { return DesignTokens.Colors.textSecondary }
        switch s.cpuPercent {
        case ..<60: return DesignTokens.Colors.textPrimary
        case 60..<150: return DesignTokens.Colors.warning
        default: return DesignTokens.Colors.live
        }
    }

    private var memTint: Color {
        guard let s = snapshot else { return DesignTokens.Colors.textSecondary }
        switch s.memoryMB {
        case ..<800: return DesignTokens.Colors.textPrimary
        case 800..<1500: return DesignTokens.Colors.warning
        default: return DesignTokens.Colors.live
        }
    }

    private var gpuTint: Color {
        guard let s = snapshot else { return DesignTokens.Colors.textSecondary }
        switch s.gpuPercent {
        case ..<40: return DesignTokens.Colors.textPrimary
        case 40..<75: return DesignTokens.Colors.warning
        default: return DesignTokens.Colors.live
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        let monitor = appState.performanceMonitor
        let interval = pollInterval
        pollTask = Task { @MainActor in
            // 즉시 1회 샘플
            let first = monitor.systemUsageSnapshot()
            snapshot = first
            lastUpdated = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                let snap = monitor.systemUsageSnapshot()
                snapshot = snap
                lastUpdated = Date()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
