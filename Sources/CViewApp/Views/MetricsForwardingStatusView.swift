// MARK: - MetricsForwardingStatusView.swift
// 메트릭 전송 현황 — 싱글/멀티라이브 설정 패널 공용 컴포넌트

import SwiftUI
import CViewCore
import CViewMonitoring

/// 메트릭 서버 전송 현황을 표시하는 설정 패널 내장 뷰
/// PlayerAdvancedSettingsView, MLSettingsPanel 양쪽에서 사용
struct MetricsForwardingStatusView: View {
    @Environment(AppState.self) private var appState

    @State private var snapshot: MetricsForwarder.Snapshot?
    @State private var isServerOnline = false
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {

            // ── 전송 상태 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("전송 상태", icon: "paperplane.fill", color: .cyan)

                if let snap = snapshot {
                    // 활성화 상태 배지
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(statusColor(snap))
                            .frame(width: 10, height: 10)
                        Text(statusLabel(snap))
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(snap.isEnabled ? "활성" : "비활성")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(snap.isEnabled ? .green : DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(snap.isEnabled ? Color.green.opacity(0.12) : DesignTokens.Colors.surfaceElevated.opacity(0.5))
                            )
                    }

                    // 현재 채널
                    if let name = snap.channelName {
                        HStack(spacing: 6) {
                            Image(systemName: "tv")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            Text(name)
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }

                    // 전송 주기 & 핑 주기
                    HStack(spacing: DesignTokens.Spacing.md) {
                        miniStat(icon: "timer", label: "전송 주기", value: String(format: "%.0f초", snap.forwardInterval))
                        miniStat(icon: "heart.fill", label: "핑 주기", value: String(format: "%.0f초", snap.pingInterval))
                    }
                } else {
                    disabledPlaceholder("메트릭 포워더가 초기화되지 않았습니다")
                }
            }

            if let snap = snapshot, snap.isEnabled {
                Divider()

                // ── 전송 통계 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("전송 통계", icon: "chart.bar.fill", color: .mint)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                        statCard("전송 성공", "\(snap.totalSent)", icon: "checkmark.circle", color: .green)
                        statCard("전송 실패", "\(snap.totalErrors)", icon: "xmark.circle", color: snap.totalErrors > 0 ? .orange : DesignTokens.Colors.textTertiary)
                        statCard("핑 전송", "\(snap.totalPings)", icon: "heart.circle", color: .cyan)
                        statCard("성공률", successRateText(snap), icon: "percent", color: successRateColor(snap))
                    }

                    // 마지막 전송 시각
                    if let lastSent = snap.lastSentAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("마지막 전송: \(timeAgo(lastSent))")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }

                    // 마지막 오류
                    if let errorAt = snap.lastErrorAt, let msg = snap.lastErrorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("오류: \(msg)")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                        HStack(spacing: 4) {
                            Spacer().frame(width: 13)
                            Text(timeAgo(errorAt))
                                .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                }

                Divider()

                // ── 서버 상태 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("서버 연결", icon: "server.rack", color: DesignTokens.Colors.accentBlue)

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(isServerOnline ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(isServerOnline ? "온라인" : "오프라인")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            .foregroundStyle(isServerOnline ? .green : .red)
                        Spacer()
                        if let vm = appState.homeViewModel {
                            Text("업타임 \(vm.formattedUptime)")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }

                    if let vm = appState.homeViewModel {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            miniStat(icon: "number", label: "총 수신", value: formatLargeNumber(vm.serverTotalReceived))
                            miniStat(icon: "dot.radiowaves.left.and.right", label: "활성 채널", value: "\(vm.serverChannelStats.count)")
                        }
                    }
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { pollingTask?.cancel() }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshSnapshot()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshSnapshot() async {
        if let forwarder = appState.metricsForwarder {
            snapshot = await forwarder.snapshot
        }
        if let vm = appState.homeViewModel {
            isServerOnline = vm.isMetricsServerOnline
        }
    }

    // MARK: - Helpers

    private func statusColor(_ snap: MetricsForwarder.Snapshot) -> Color {
        if !snap.isEnabled { return .gray }
        if snap.isForwarding { return .green }
        return .orange
    }

    private func statusLabel(_ snap: MetricsForwarder.Snapshot) -> String {
        if !snap.isEnabled { return "메트릭 전송 비활성화됨" }
        if snap.isForwarding { return "전송 중" }
        return "대기 (채널 없음)"
    }

    private func successRateText(_ snap: MetricsForwarder.Snapshot) -> String {
        let total = snap.totalSent + snap.totalErrors
        guard total > 0 else { return "—" }
        let rate = Double(snap.totalSent) / Double(total) * 100
        return String(format: "%.0f%%", rate)
    }

    private func successRateColor(_ snap: MetricsForwarder.Snapshot) -> Color {
        let total = snap.totalSent + snap.totalErrors
        guard total > 0 else { return DesignTokens.Colors.textTertiary }
        let rate = Double(snap.totalSent) / Double(total)
        if rate > 0.95 { return .green }
        if rate > 0.7 { return .orange }
        return .red
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "방금" }
        if seconds < 60 { return "\(seconds)초 전" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        return "\(seconds / 3600)시간 전"
    }

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
        }
    }

    private func statCard(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    private func miniStat(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func disabledPlaceholder(_ message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }
}
