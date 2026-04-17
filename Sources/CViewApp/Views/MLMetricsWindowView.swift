// MARK: - MLMetricsWindowView.swift
// 메트릭 전송 현황 — 독립 윈도우 래퍼
// MetricsForwardingStatusView를 독립 창에서 사용할 수 있도록 래핑

import SwiftUI
import CViewCore

struct MLMetricsWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // ── 헤더 ──
            header
            Divider()

            // ── 메트릭 전송 현황 ──
            ScrollView {
                MetricsForwardingStatusView()
                    .padding(DesignTokens.Spacing.md)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(DesignTokens.Colors.surfaceBase)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3)
                .foregroundStyle(.cyan)

            Text("메트릭 전송 현황")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }
}
