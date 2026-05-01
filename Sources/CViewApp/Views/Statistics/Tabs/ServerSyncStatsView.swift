// MARK: - Statistics/Tabs/ServerSyncStatsView.swift
// 서버 동기화 탭 (신규) — MetricsForwarder 상태 + 권장 sync + Grafana 대시보드 임베드.
//
// 데이터 소스:
// - appState.metricsForwarder?.snapshot (5초 폴링)
// - 익명 접근 가능한 환경에서만 Grafana 임베드가 정상 표시됨.
//   접근 불가 시 우상단 "외부 브라우저로 열기" 버튼으로 폴백.

import SwiftUI
import CViewCore
import CViewMonitoring
import CViewUI

struct ServerSyncStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var snapshot: MetricsForwarder.Snapshot? = nil
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var dashboard: GrafanaDashboard = .overview
    @State private var showDashboard: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 포워더 상태
                StatSection("메트릭 포워더", icon: "antenna.radiowaves.left.and.right",
                            color: forwardingColor) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "전송 상태",
                            value: forwardingStatusText,
                            icon: "dot.radiowaves.up.forward",
                            color: forwardingColor
                        )
                        StatCard(
                            title: "활성 채널",
                            value: snapshot?.channelName ?? "-",
                            icon: "tv.circle",
                            color: DesignTokens.Colors.accentBlue
                        )
                        StatCard(
                            title: "전송 횟수",
                            value: "\(snapshot?.totalSent ?? 0)",
                            icon: "arrow.up.circle.fill",
                            color: DesignTokens.Colors.chzzkGreen
                        )
                        StatCard(
                            title: "오류 / 핑",
                            value: "\(snapshot?.totalErrors ?? 0) / \(snapshot?.totalPings ?? 0)",
                            icon: "exclamationmark.octagon",
                            color: (snapshot?.totalErrors ?? 0) > 0 ? .red : DesignTokens.Colors.textTertiary
                        )
                    }
                }

                // ── 동기화 권장값
                StatSection("동기화 권장", icon: "arrow.triangle.2.circlepath",
                            color: DesignTokens.Colors.accentPurple) {
                    if let rec = snapshot?.lastRecommendation {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            recommendationRow(rec)
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: DesignTokens.Spacing.md) {
                                StatCard(
                                    title: "추천 속도",
                                    value: rec.suggestedSpeed.map { String(format: "%.3fx", $0) } ?? "-",
                                    icon: "speedometer",
                                    color: DesignTokens.Colors.accentOrange
                                )
                                StatCard(
                                    title: "Delta (ms)",
                                    value: rec.delta.map { String(format: "%.0f", $0) } ?? "-",
                                    icon: "ruler",
                                    color: DesignTokens.Colors.accentCyan
                                )
                                StatCard(
                                    title: "Tier",
                                    value: rec.tier ?? "-",
                                    icon: "rosette",
                                    color: tierColor(rec.tier)
                                )
                            }
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: DesignTokens.Spacing.md) {
                                StatCard(
                                    title: "적응 간격",
                                    value: String(format: "%.1fs", snapshot?.adaptiveSyncInterval ?? 0),
                                    icon: "timer",
                                    color: DesignTokens.Colors.accentBlue
                                )
                                StatCard(
                                    title: "클라 델타",
                                    value: String(format: "%.0f ms", snapshot?.lastClientDelta ?? 0),
                                    icon: "waveform.path",
                                    color: DesignTokens.Colors.accentPink
                                )
                                StatCard(
                                    title: "마지막 전송",
                                    value: lastSentText,
                                    icon: "clock.arrow.circlepath",
                                    color: DesignTokens.Colors.textSecondary
                                )
                            }
                        }
                    } else {
                        EmptyStatePlaceholder(
                            icon: "arrow.triangle.2.circlepath",
                            title: "권장값 없음",
                            subtitle: "채널 시청을 시작하면 서버에서 동기화 권장값을 수신합니다"
                        )
                    }
                }

                // ── Grafana 대시보드 임베드
                StatSection(
                    "Grafana 대시보드",
                    icon: "chart.line.uptrend.xyaxis",
                    color: DesignTokens.Colors.accentPink,
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Picker("", selection: $dashboard) {
                                ForEach(GrafanaDashboard.allCases) { dash in
                                    Label(dash.title, systemImage: dash.icon).tag(dash)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 160)

                            Button {
                                openInBrowser()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .buttonStyle(.plain)
                            .help("외부 브라우저로 열기")
                        }
                    )
                ) {
                    DisclosureGroup(isExpanded: $showDashboard) {
                        if let url = dashboard.url() {
                            GrafanaDashboardView(url: url)
                                .frame(height: 520)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                                .overlay {
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                                }
                        }
                    } label: {
                        HStack {
                            Image(systemName: dashboard.icon)
                                .foregroundStyle(DesignTokens.Colors.accentPink)
                            Text(showDashboard ? "임베드 숨기기" : "\(dashboard.title) 임베드 보기")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Spacer()
                            Text("cv.dododo.app")
                                .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
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
        guard let forwarder = appState.metricsForwarder else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                self.snapshot = await forwarder.snapshot
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    // MARK: - Open in browser

    private func openInBrowser() {
        guard let url = dashboard.url() else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Recommendation row

    @ViewBuilder
    private func recommendationRow(_ rec: CViewSyncRecommendation) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: actionIcon(rec.action))
                .font(DesignTokens.Typography.title)
                .foregroundStyle(actionColor(rec.action))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(actionText(rec.action))
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let reason = rec.reason, !reason.isEmpty {
                    Text(reason)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let trend = rec.trend {
                Text(trend)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(trendColor(trend))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(trendColor(trend).opacity(0.12), in: Capsule())
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - Helpers

    private var forwardingColor: Color {
        guard let s = snapshot else { return DesignTokens.Colors.textTertiary }
        if !s.isEnabled { return DesignTokens.Colors.textTertiary }
        if s.totalErrors > 0 && s.lastErrorAt != nil { return .orange }
        if s.isForwarding { return DesignTokens.Colors.chzzkGreen }
        return DesignTokens.Colors.textTertiary
    }

    private var forwardingStatusText: String {
        guard let s = snapshot else { return "-" }
        if !s.isEnabled { return "비활성" }
        if s.isForwarding { return "전송 중" }
        return "대기"
    }

    private var lastSentText: String {
        guard let date = snapshot?.lastSentAt else { return "-" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private func tierColor(_ tier: String?) -> Color {
        switch tier {
        case "excellent": return DesignTokens.Colors.chzzkGreen
        case "good": return DesignTokens.Colors.accentBlue
        case "adjust": return .yellow
        case "drift": return .orange
        case "critical": return .red
        default: return DesignTokens.Colors.textTertiary
        }
    }

    private func actionIcon(_ action: String?) -> String {
        switch action {
        case "speed_up": return "forward.fill"
        case "slow_down": return "backward.fill"
        case "hold": return "equal.circle.fill"
        case "waiting": return "hourglass"
        default: return "questionmark.circle"
        }
    }

    private func actionText(_ action: String?) -> String {
        switch action {
        case "speed_up": return "속도 증가 권장"
        case "slow_down": return "속도 감소 권장"
        case "hold": return "현재 속도 유지"
        case "waiting": return "샘플 수집 중"
        default: return action ?? "-"
        }
    }

    private func actionColor(_ action: String?) -> Color {
        switch action {
        case "speed_up": return DesignTokens.Colors.accentOrange
        case "slow_down": return DesignTokens.Colors.accentBlue
        case "hold": return DesignTokens.Colors.chzzkGreen
        default: return DesignTokens.Colors.textTertiary
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "improving": return DesignTokens.Colors.chzzkGreen
        case "stable": return DesignTokens.Colors.accentBlue
        case "worsening": return .red
        default: return DesignTokens.Colors.textTertiary
        }
    }
}
