// MARK: - SettingsView.swift
// CViewApp - 설정 뷰 컨테이너 (macOS System Settings 스타일)
// 각 탭은 별도 파일로 분리됨:
//   GeneralSettingsTab.swift, PlayerSettingsTab.swift, ChatSettingsTab.swift,
//   NetworkSettingsTab.swift, PerformanceSettingsTab.swift, MetricsSettingsTab.swift
// 공유 컴포넌트: SettingsSharedComponents.swift

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Settings View

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general  = "일반"
        case player   = "플레이어"
        case chat     = "채팅"
        case network  = "네트워크"
        case performance = "성능"
        case metrics  = "메트릭"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:      "gearshape.fill"
            case .player:       "play.rectangle.fill"
            case .chat:         "bubble.left.and.bubble.right.fill"
            case .network:      "network"
            case .performance:  "gauge.with.dots.needle.33percent"
            case .metrics:      "chart.line.uptrend.xyaxis"
            }
        }

        var color: Color {
            switch self {
            case .general:      DesignTokens.Colors.textSecondary
            case .player:       DesignTokens.Colors.chzzkGreen
            case .chat:         DesignTokens.Colors.accentPurple
            case .network:      DesignTokens.Colors.accentBlue
            case .performance:  DesignTokens.Colors.accentOrange
            case .metrics:      Color(red: 0.2, green: 0.8, blue: 0.9)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()
                .background(.white.opacity(DesignTokens.Glass.borderOpacityLight))

            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()

                switch selectedTab {
                case .general:      GeneralSettingsTab(settings: appState.settingsStore)
                case .player:       PlayerSettingsTab(settings: appState.settingsStore)
                case .chat:         ChatSettingsTab(settings: appState.settingsStore)
                case .network:      NetworkSettingsTab(settings: appState.settingsStore)
                case .performance:  PerformanceSettingsTab(settings: appState.settingsStore)
                case .metrics:      MetricsSettingsTab(settings: appState.settingsStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(spacing: 2) {
            VStack(spacing: 4) {
                Image(systemName: "c.square.fill")
                    .font(DesignTokens.Typography.custom(size: 26))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("CView")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("v2.0")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)

            Divider()
                .overlay(.white.opacity(DesignTokens.Glass.borderOpacityLight))
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.xs)

            ForEach(SettingsTab.allCases) { tab in
                SidebarTabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                }
            }

            Spacer()
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.5))
    }
}

// MARK: - Sidebar Tab Button

private struct SidebarTabButton: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(isSelected ? tab.color : tab.color.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: tab.icon)
                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.background : tab.color)
                }
                Text(tab.rawValue)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(tab.color.opacity(0.08))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(tab.color.opacity(0.2), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.indicator, value: isSelected)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
