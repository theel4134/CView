// MARK: - SettingsView.swift
// CViewApp - 설정 뷰
// 메인 앱: 사이드바 슬라이드 메뉴 → 디테일 영역에 콘텐츠만 표시
// Settings 윈도우 (Cmd+,): 독립 사이드바 + 콘텐츠 레이아웃
// 각 탭은 별도 파일로 분리됨:
//   GeneralSettingsTab.swift, PlayerSettingsTab.swift, ChatSettingsTab.swift,
//   NetworkSettingsTab.swift, PerformanceSettingsTab.swift, MetricsSettingsTab.swift
// 공유 컴포넌트: SettingsSharedComponents.swift

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Settings Content View (디테일 영역 전용 — 사이드바 없음)

struct SettingsContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            settingsTabContent(for: router.selectedSettingsTab, settings: appState.settingsStore)
                .id(router.selectedSettingsTab)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentBackground()
        .animation(DesignTokens.Animation.snappy, value: router.selectedSettingsTab)
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }

    @ViewBuilder
    private func settingsTabContent(for tab: AppRouter.SettingsTab, settings: SettingsStore) -> some View {
        switch tab {
        case .general:      GeneralSettingsTab(settings: settings)
        case .player:       PlayerSettingsTab(settings: settings)
        case .chat:         ChatSettingsTab(settings: settings)
        case .network:      NetworkSettingsTab(settings: settings)
        case .performance:  PerformanceSettingsTab(settings: settings)
        case .metrics:      MetricsSettingsTab(settings: settings)
        case .multiLive:    MultiLiveSettingsTab(settings: settings)
        }
    }
}

// MARK: - Settings View (독립 Settings 윈도우용 — Cmd+, / 앱 메뉴)

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppRouter.SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()

                settingsTabContent(for: selectedTab, settings: appState.settingsStore)
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DesignTokens.Animation.snappy, value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentBackground()
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }

    @ViewBuilder
    private func settingsTabContent(for tab: AppRouter.SettingsTab, settings: SettingsStore) -> some View {
        switch tab {
        case .general:      GeneralSettingsTab(settings: settings)
        case .player:       PlayerSettingsTab(settings: settings)
        case .chat:         ChatSettingsTab(settings: settings)
        case .network:      NetworkSettingsTab(settings: settings)
        case .performance:  PerformanceSettingsTab(settings: settings)
        case .metrics:      MetricsSettingsTab(settings: settings)
        case .multiLive:    MultiLiveSettingsTab(settings: settings)
        }
    }

    // MARK: - Sidebar (Settings 윈도우 전용)

    private var settingsSidebar: some View {
        VStack(spacing: 2) {
            // 미니멀 헤더
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "c.square.fill")
                    .font(DesignTokens.Typography.custom(size: 16))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("CView 설정")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.xs)

            ForEach(AppRouter.SettingsTab.allCases) { tab in
                SettingsWindowTabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(DesignTokens.Animation.snappy) { selectedTab = tab }
                }
            }

            Spacer()
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Glass.sidebar)
    }
}

// MARK: - Settings Window Tab Button (macOS System Settings 스타일)

private struct SettingsWindowTabButton: View {
    let tab: AppRouter.SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(DesignTokens.Typography.custom(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : tab.color)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(Color.accentColor)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(Color.primary.opacity(0.06))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.indicator, value: isSelected)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
