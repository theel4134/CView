// MARK: - StatisticsView.swift
// CViewApp - 통계/분석 대시보드 (라우터)
//
// 6 개 탭으로 구성:
//   .session   세션      — 사용자/플레이어 상태 (구 SessionStatsView 확장)
//   .streaming 스트리밍   — 비트레이트/지연/버퍼 (구 StreamingStatsView 확장)
//   .performance 성능    — FPS/CPU/GPU/메모리 (신규, AsyncStream 구독)
//   .chat      채팅      — 메시지/속도/Top 채터 (구 ChatStatsView 확장 + CSV)
//   .history   기록      — 시청 기록/시간대/카테고리 (확장)
//   .server    서버 동기화 — MetricsForwarder + Grafana 임베드 (신규)
//
// 각 탭 본체는 `Sources/CViewApp/Views/Statistics/Tabs/*.swift` 에 위치한다.

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI

struct StatisticsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: StatTab = .session

    enum StatTab: String, CaseIterable, Identifiable {
        case session = "세션"
        case streaming = "스트리밍"
        case performance = "성능"
        case chat = "채팅"
        case history = "기록"
        case server = "서버 동기화"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .session: "person.crop.circle.fill"
            case .streaming: "waveform"
            case .performance: "speedometer"
            case .chat: "bubble.left.and.bubble.right.fill"
            case .history: "clock.arrow.circlepath"
            case .server: "antenna.radiowaves.left.and.right"
            }
        }

        var color: Color {
            switch self {
            case .session: DesignTokens.Colors.accentBlue
            case .streaming: DesignTokens.Colors.chzzkGreen
            case .performance: DesignTokens.Colors.accentCyan
            case .chat: DesignTokens.Colors.accentPurple
            case .history: DesignTokens.Colors.accentOrange
            case .server: DesignTokens.Colors.accentPink
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("통계")
                        .font(DesignTokens.Typography.bodyBold)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

                List(StatTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(selectedTab == tab ? tab.color : DesignTokens.Colors.textSecondary)
                            .frame(width: 20)
                        Text(tab.rawValue)
                            .font(DesignTokens.Typography.custom(
                                size: 13,
                                weight: selectedTab == tab ? .semibold : .regular
                            ))
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 170)
            .contentBackground()
        } detail: {
            tabContent
                .id(selectedTab)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .session:     SessionStatsView()
        case .streaming:   StreamingStatsView()
        case .performance: PerformanceStatsView()
        case .chat:        ChatStatsView()
        case .history:     WatchHistoryStatsView()
        case .server:      ServerSyncStatsView()
        }
    }
}

// MARK: - Active Player Resolution
//
// 통계 탭에서는 단일 라이브(LiveStreamView) 와 멀티라이브(MultiLiveSession) 어느 쪽에서
// 재생 중이든 동일하게 동작해야 한다. 단일 PVM 만 보면 멀티라이브 사용 중일 때 모두 비어
// 보이는 회귀가 발생하므로, "현재 활성" PVM 을 다음 우선순위로 고른다:
//   1. appState.playerViewModel 이 idle 이 아니면 그대로 사용
//   2. multiLiveManager.selectedSession?.playerViewModel 이 idle 이 아니면 사용
//   3. 활성 세션이 없으면 단일 PVM 폴백 (UI 가 placeholder 처리)
extension AppState {
    var activePlayerViewModel: PlayerViewModel? {
        if let pvm = playerViewModel, !Self.isIdlePhase(pvm.streamPhase) {
            return pvm
        }
        if let sel = multiLiveManager.selectedSession?.playerViewModel,
           !Self.isIdlePhase(sel.streamPhase) {
            return sel
        }
        // 모든 멀티라이브 세션 중 재생 중인 것이 있으면 그것 (선택 세션이 idle 인 경우)
        if let any = multiLiveManager.sessions.first(where: { !Self.isIdlePhase($0.playerViewModel.streamPhase) }) {
            return any.playerViewModel
        }
        return playerViewModel ?? multiLiveManager.selectedSession?.playerViewModel
    }

    private static func isIdlePhase(_ phase: StreamCoordinator.StreamPhase) -> Bool {
        switch phase {
        case .idle: return true
        default: return false
        }
    }
}
