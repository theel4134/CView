// MARK: - SettingsView.swift
// CViewApp - 설정 진입점 (Redesign 2026-04-29)
//
// [Redesign 2026-04-29] Settings Command Center 도입
// - 메인 앱 사이드바 모드 → SettingsContentView() 가 SettingsWorkspace(showRail: false) 표시
//   (좌측 슬라이드 사이드바가 그룹 rail 역할 — MainContentView.settingsSidebarContent)
// - 독립 Settings 윈도우(Cmd+,) → SettingsView() 가 SettingsWorkspace(showRail: true) 표시
//
// 콘텐츠 구성/검색/Inspector/시나리오는 SettingsWorkspace.swift 에 위치한다.
// 기존 *SettingsTab.swift 파일들은 그룹 컨텐츠 내부에서 그대로 재사용된다.

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Settings Content View (메인 앱 디테일 영역 — rail 없음)

struct SettingsContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        SettingsWorkspace(
            settings: appState.settingsStore,
            selectedGroup: Binding(
                get: { router.selectedSettingsGroup },
                set: { router.selectedSettingsGroup = $0 }
            ),
            showRail: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentBackground()
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }
}

// MARK: - Settings View (독립 Settings 윈도우 — Cmd+, / 앱 메뉴)

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedGroup: AppRouter.SettingsGroup = .overview

    var body: some View {
        SettingsWorkspace(
            settings: appState.settingsStore,
            selectedGroup: $selectedGroup,
            showRail: true
        )
        .frame(minWidth: 880, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentBackground()
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }
}
