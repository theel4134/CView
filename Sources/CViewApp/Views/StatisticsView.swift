// MARK: - StatisticsView.swift
// CViewApp - 프리미엄 통계/분석 대시보드
// Design: 모던 대시보드 + 그라데이션 카드

import SwiftUI
import Charts
import CViewCore
import CViewMonitoring
import CViewPersistence
import CViewUI
import CViewChat

/// 스트리밍 통계 대시보드
struct StatisticsView: View {
    
    @Environment(AppState.self) private var appState
    @State private var selectedTab: StatTab = .session
    
    enum StatTab: String, CaseIterable, Identifiable {
        case session = "세션"
        case streaming = "스트리밍"
        case chat = "채팅"
        case history = "기록"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .session: "clock"
            case .streaming: "waveform"
            case .chat: "bubble.left.and.bubble.right"
            case .history: "calendar"
            }
        }
        
        var color: Color {
            switch self {
            case .session: DesignTokens.Colors.accentBlue
            case .streaming: DesignTokens.Colors.chzzkGreen
            case .chat: DesignTokens.Colors.accentPurple
            case .history: DesignTokens.Colors.accentOrange
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Stats header
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("통계")
                        .font(DesignTokens.Typography.bodyBold)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                
                List(StatTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(selectedTab == tab ? tab.color : DesignTokens.Colors.textSecondary)
                            .frame(width: 20)
                        
                        Text(tab.rawValue)
                            .font(DesignTokens.Typography.custom(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 150)
            .background(DesignTokens.Colors.background)
        } detail: {
            tabContent
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .session:
            SessionStatsView()
        case .streaming:
            StreamingStatsView()
        case .chat:
            ChatStatsView()
        case .history:
            WatchHistoryStatsView()
        }
    }
}

// MARK: - Session Stats

struct SessionStatsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Session Overview
                statsSection("세션 개요", icon: "clock.fill", color: DesignTokens.Colors.accentBlue) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(title: "앱 시작 시간", value: formattedLaunchTime, icon: "clock.fill", color: .blue)
                        StatCard(title: "현재 상태", value: appState.playerViewModel?.streamPhase == .playing ? "재생 중" : "대기", icon: "play.circle.fill", color: .green)
                        StatCard(title: "로그인", value: appState.isLoggedIn ? "로그인됨" : "비로그인", icon: "person.fill", color: .purple)
                    }
                }
                
                // Player State
                statsSection("플레이어 상태", icon: "play.rectangle.fill", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "채널",
                            value: appState.playerViewModel?.channelName ?? "-",
                            icon: "tv",
                            color: .orange
                        )
                        StatCard(
                            title: "화질",
                            value: appState.playerViewModel?.currentQuality?.name ?? "-",
                            icon: "sparkles.tv",
                            color: .cyan
                        )
                        StatCard(
                            title: "볼륨",
                            value: "\(Int((appState.playerViewModel?.volume ?? 0) * 100))%",
                            icon: "speaker.wave.2.fill",
                            color: .indigo
                        )
                        StatCard(
                            title: "재생 시간",
                            value: appState.playerViewModel?.formattedUptime ?? "00:00",
                            icon: "timer",
                            color: .mint
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
    }
    
    private var formattedLaunchTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: appState.launchTime)
    }
    
    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
        }
    }
}
