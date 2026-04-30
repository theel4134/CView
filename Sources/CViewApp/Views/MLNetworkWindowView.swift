// MARK: - MLNetworkWindowView.swift
// 멀티라이브 네트워크 모니터링 — 독립 윈도우 래퍼
// 세션 선택 피커 + MLNetworkTab 실시간 모니터링
//
// 2026-04-30 집계 안정화 작업:
// - "전체" 합산 모드 추가 (모든 세션의 대역폭/요청/헬스 통합 표시)
// - CSV 내보내기 (현재 세션의 60-샘플 히스토리)
// - 세션 별 sparkline 60s 추세선

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CViewCore
import CViewPersistence

struct MLNetworkWindowView: View {

    /// 윈도우의 표시 모드 — 단일 세션 vs 전체 합산.
    private enum DisplayMode: Hashable {
        case all
        case session(UUID)
    }

    @Environment(AppState.self) private var appState
    @State private var displayMode: DisplayMode = .all
    @State private var exportError: String?

    private var manager: MultiLiveManager { appState.multiLiveManager }
    private var sessions: [MultiLiveSession] { manager.sessions }

    private var activeSessions: [MultiLiveSession] {
        sessions.filter { if case .playing = $0.loadState { return true } else { return false } }
    }

    private var selectedSession: MultiLiveSession? {
        if case .session(let id) = displayMode {
            return sessions.first { $0.id == id }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 460, minHeight: 360)
        .background(DesignTokens.Colors.surfaceBase)
        .onAppear {
            // 초기 모드 결정 — 세션 2개 이상이면 전체, 1개면 그 세션, 0개면 전체(빈 상태).
            if activeSessions.count >= 2 {
                displayMode = .all
            } else if let only = activeSessions.first ?? sessions.first {
                displayMode = .session(only.id)
            } else {
                displayMode = .all
            }
            applyShowFlag()
        }
        .onDisappear {
            for s in sessions { s.showNetworkMetrics = false }
        }
        .onChange(of: manager.sessions.map(\.id)) { _, _ in
            if case .session(let id) = displayMode, !sessions.contains(where: { $0.id == id }) {
                displayMode = sessions.first.map { .session($0.id) } ?? .all
            }
            applyShowFlag()
        }
        .onChange(of: displayMode) { _, _ in
            applyShowFlag()
        }
        .alert("내보내기 실패", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } })) {
            Button("확인") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .all:
            ScrollView {
                MLNetworkAggregateTab(sessions: sessions)
                    .padding(DesignTokens.Spacing.md)
            }
        case .session:
            if let session = selectedSession {
                ScrollView {
                    MLNetworkTab(session: session, settingsStore: appState.settingsStore)
                        .padding(DesignTokens.Spacing.md)
                }
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            Text("네트워크 모니터")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            modePicker
            exportButton
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private var modePicker: some View {
        Picker("모드", selection: $displayMode) {
            Text("전체").tag(DisplayMode.all)
            ForEach(sessions) { session in
                Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                    .tag(DisplayMode.session(session.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
    }

    @ViewBuilder
    private var exportButton: some View {
        Button {
            exportCSV()
        } label: {
            Label("CSV", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .help("현재 보기를 CSV 로 내보내기")
        .buttonStyle(.borderless)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("활성 세션 없음")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("멀티라이브에서 채널을 추가하면\n네트워크 모니터링이 시작됩니다")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// MLNetworkTab 의 onAppear/onDisappear 에 의존하지 않고, 모드 전환 시 한 번에
    /// showNetworkMetrics 플래그를 갱신해 프록시 폴링 태스크를 시작/중단한다.
    private func applyShowFlag() {
        switch displayMode {
        case .all:
            for s in sessions { s.showNetworkMetrics = true }
        case .session(let id):
            for s in sessions { s.showNetworkMetrics = (s.id == id) }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let suffix: String
        switch displayMode {
        case .all:
            suffix = "all-sessions"
        case .session(let id):
            let s = sessions.first { $0.id == id }
            suffix = s?.channelName.replacingOccurrences(of: " ", with: "_") ?? "session"
        }
        panel.nameFieldStringValue = "cview-network-\(suffix)-\(stamp).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let csv: String
        switch displayMode {
        case .all:
            csv = aggregateCSV()
        case .session:
            csv = selectedSession?.networkHistory.csvDump() ?? ""
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// 전체 모드 CSV — 세션 별 한 행 요약(현재 스냅샷).
    private func aggregateCSV() -> String {
        let snap = MLNetworkAggregateTab.aggregate(sessions)
        var lines = ["channel,engine,health,bandwidth_kbps,fps,resolution,warnings"]
        for r in snap.perSession {
            let kbps = r.bandwidthBytesPerSec * 8.0 / 1000.0
            lines.append("\"\(r.channelName)\",\(r.engine),\(String(format: "%.3f", r.healthScore)),\(String(format: "%.1f", kbps)),\(String(format: "%.1f", r.fps)),\"\(r.resolution ?? "")\",\(r.warningCount)")
        }
        lines.append("")
        lines.append("# summary")
        lines.append("active_sessions,\(snap.activeSessions)")
        lines.append("total_bandwidth_kbps,\(String(format: "%.1f", snap.totalBandwidthBytesPerSec * 8.0 / 1000.0))")
        lines.append("avg_health,\(String(format: "%.3f", snap.avgHealthScore))")
        lines.append("avg_buffer,\(String(format: "%.3f", snap.avgBufferHealth))")
        lines.append("total_requests,\(snap.totalRequests)")
        lines.append("cache_hit_ratio,\(String(format: "%.3f", snap.cacheHitRatio))")
        lines.append("active_connections,\(snap.activeConnections)")
        lines.append("total_drops,\(snap.totalDropsDelta)")
        lines.append("total_late,\(snap.totalLateDelta)")
        return lines.joined(separator: "\n")
    }
}
