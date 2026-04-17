// MARK: - MLNetworkWindowView.swift
// 멀티라이브 네트워크 모니터링 — 독립 윈도우 래퍼
// 세션 선택 피커 + MLNetworkTab 실시간 모니터링

import SwiftUI
import CViewCore
import CViewPersistence

struct MLNetworkWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSessionId: UUID?

    private var manager: MultiLiveManager { appState.multiLiveManager }
    private var sessions: [MultiLiveSession] { manager.sessions }

    private var activeSession: MultiLiveSession? {
        if let id = selectedSessionId {
            return sessions.first { $0.id == id }
        }
        return manager.selectedSession ?? sessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 헤더 + 세션 선택 ──
            header
            Divider()

            // ── 네트워크 탭 콘텐츠 ──
            if let session = activeSession {
                ScrollView {
                    MLNetworkTab(session: session, settingsStore: appState.settingsStore)
                        .padding(DesignTokens.Spacing.md)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(DesignTokens.Colors.surfaceBase)
        .onAppear {
            // 초기 선택: 매니저의 선택된 세션 또는 첫 번째 세션
            if selectedSessionId == nil {
                selectedSessionId = manager.selectedSessionId ?? sessions.first?.id
            }
        }
        .onChange(of: manager.sessions.map(\.id)) { _, newIds in
            // 선택된 세션이 제거됐으면 첫 번째로 이동
            if let id = selectedSessionId, !newIds.contains(id) {
                selectedSessionId = newIds.first
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            Text("네트워크 모니터")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            if sessions.count > 1 {
                Picker("세션", selection: $selectedSessionId) {
                    ForEach(sessions) { session in
                        Text(session.channelName)
                            .tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            } else if let session = sessions.first {
                Text(session.channelName)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("활성 멀티라이브 세션 없음")
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
}
