// MARK: - GeneralSettingsTab.swift
// 일반 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence
import ServiceManagement
import AppKit

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("일반")

                SettingsSection(title: "앱 동작", icon: "app.badge", color: DesignTokens.Colors.chzzkGreen) {
                    SettingsRow("시작 시 자동 실행",
                                description: "로그인 시 CView를 자동으로 시작합니다",
                                icon: "power", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.general.launchAtLogin)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("메뉴바에 표시",
                                description: "상단 메뉴바에 CView 아이콘을 표시합니다",
                                icon: "menubar.rectangle", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.general.showInMenuBar)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("항상 최상위",
                                description: "창을 항상 다른 앱 위에 표시합니다",
                                icon: "macwindow.on.rectangle", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.general.alwaysOnTop)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentPurple)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("시작 시 창 복원",
                                description: "앱 시작 시 이전 창 크기와 위치를 복원합니다",
                                icon: "arrow.uturn.backward.circle", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.general.restoreWindowOnLaunch)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentOrange)
                            .labelsHidden()
                    }
                }

                SettingsSection(title: "테마", icon: "paintpalette.fill", color: DesignTokens.Colors.accentPurple) {
                    ThemePickerRow(selection: $settings.appearance.theme)
                        .onChange(of: settings.appearance.theme) {
                            Task { await settings.save() }
                        }
                    RowDivider()
                    ThemePreviewPanel(theme: settings.appearance.theme)
                }

                SettingsSection(title: "알림", icon: "bell.badge.fill", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("알림 활성화",
                                description: "라이브 시작 알림을 받습니다",
                                icon: "bell.fill", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.general.notificationsEnabled)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentOrange)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("자동 새로고침",
                                description: "라이브 목록을 주기적으로 업데이트합니다",
                                icon: "arrow.clockwise", iconColor: DesignTokens.Colors.accentBlue) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.general.autoRefreshInterval, format: .number)
                                .frame(width: 52)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                            Text("초")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }

                // 키보드 단축키 섹션
                SettingsSection(title: "키보드 단축키", icon: "keyboard.fill", color: DesignTokens.Colors.accentPurple) {
                    ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 { RowDivider() }
                        ShortcutBindingRow(
                            action: action,
                            binding: Binding(
                                get: { settings.keyboard.binding(for: action) },
                                set: { newBinding in
                                    settings.keyboard.bindings[action] = newBinding
                                    Task { await settings.save() }
                                }
                            )
                        )
                    }
                    RowDivider()
                    HStack {
                        Spacer()
                        Button("기본값 복원") {
                            settings.keyboard = .default
                            Task { await settings.save() }
                        }
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                        .buttonStyle(.plain)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onChange(of: settings.general) { _, _ in Task { await settings.save() } }
        .onChange(of: settings.appearance) { _, _ in Task { await settings.save() } }
        .onChange(of: settings.general.alwaysOnTop) { _, newValue in
            NSApplication.shared.windows.first?.level = newValue ? .floating : .normal
        }
        .onChange(of: settings.general.launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.warning("Login item \(newValue ? "register" : "unregister") failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Shortcut Binding Row

/// 단축키 행 — 액션 이름 + 현재 바인딩 표시, 클릭하면 키 레코더 진입
private struct ShortcutBindingRow: View {
    let action: ShortcutAction
    @Binding var binding: KeyBinding
    @State private var isRecording = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: action.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .frame(width: 26, height: 26)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(action.displayName)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            Spacer()
            // 키 레코더 버튼
            Text(isRecording ? "키 입력 대기중…" : binding.displayName)
                .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.textPrimary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(isRecording ? DesignTokens.Colors.accentOrange.opacity(0.12) : DesignTokens.Glass.borderColorLight)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(
                            isRecording ? DesignTokens.Colors.accentOrange : DesignTokens.Glass.borderColor,
                            lineWidth: 1
                        )
                }
                .focusable()
                .focused($isFocused)
                .onTapGesture {
                    isRecording = true
                    isFocused = true
                }
                .onKeyPress(phases: .down) { press in
                    guard isRecording else { return .ignored }
                    // Esc로 취소
                    if press.key == .escape {
                        isRecording = false
                        isFocused = false
                        return .handled
                    }
                    // 수식키만 누르면 무시 (수식키 + 일반키를 기다림)
                    if press.characters.isEmpty && press.key != .space
                        && press.key != .upArrow && press.key != .downArrow
                        && press.key != .leftArrow && press.key != .rightArrow
                        && press.key != .return && press.key != .tab && press.key != .delete {
                        return .handled
                    }
                    binding = keyBindingFromPress(press)
                    isRecording = false
                    isFocused = false
                    return .handled
                }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 11)
        .animation(DesignTokens.Animation.fast, value: isRecording)
    }

    /// KeyPress → KeyBinding 변환
    private func keyBindingFromPress(_ press: KeyPress) -> KeyBinding {
        var mods = ShortcutModifiers()
        if press.modifiers.contains(.command)  { mods.insert(.command) }
        if press.modifiers.contains(.shift)    { mods.insert(.shift) }
        if press.modifiers.contains(.option)   { mods.insert(.option) }
        if press.modifiers.contains(.control)  { mods.insert(.control) }

        let key: String
        switch press.key {
        case .space:      key = "space"
        case .upArrow:    key = "upArrow"
        case .downArrow:  key = "downArrow"
        case .leftArrow:  key = "leftArrow"
        case .rightArrow: key = "rightArrow"
        case .return:     key = "return"
        case .tab:        key = "tab"
        case .delete:     key = "delete"
        default:          key = press.characters.lowercased()
        }
        return KeyBinding(key: key, modifiers: mods)
    }
}

// MARK: - Theme Preview Colors

/// 각 테마별 명시적 프리뷰 색상
private struct ThemePreviewColors: Sendable {
    let background: Color
    let backgroundElevated: Color
    let surface: Color
    let surfaceLight: Color
    let surfaceHover: Color
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    static func colors(for theme: AppTheme) -> ThemePreviewColors {
        switch theme {
        case .dark:
            return ThemePreviewColors(
                background: Color(hex: 0x0A0A0A),
                backgroundElevated: Color(hex: 0x111111),
                surface: Color(hex: 0x161616),
                surfaceLight: Color(hex: 0x1E1E1E),
                surfaceHover: Color(hex: 0x262626),
                border: Color(hex: 0x2A2A2A),
                textPrimary: .white,
                textSecondary: Color(hex: 0x888888),
                textTertiary: Color(hex: 0x555555)
            )
        case .light:
            return ThemePreviewColors(
                background: Color(hex: 0xF2F2F7),
                backgroundElevated: Color(hex: 0xEAEAF0),
                surface: .white,
                surfaceLight: Color(hex: 0xF0F0F5),
                surfaceHover: Color(hex: 0xE4E4EB),
                border: Color(hex: 0xDDDDDD),
                textPrimary: Color(hex: 0x111111),
                textSecondary: Color(hex: 0x444444),
                textTertiary: Color(hex: 0x888888)
            )
        case .system:
            return ThemePreviewColors(
                background: Color(nsColor: .windowBackgroundColor),
                backgroundElevated: Color(nsColor: .controlBackgroundColor),
                surface: Color(nsColor: .textBackgroundColor),
                surfaceLight: Color(nsColor: .controlBackgroundColor),
                surfaceHover: Color(nsColor: .selectedContentBackgroundColor).opacity(0.3),
                border: Color(nsColor: .separatorColor),
                textPrimary: Color(nsColor: .labelColor),
                textSecondary: Color(nsColor: .secondaryLabelColor),
                textTertiary: Color(nsColor: .tertiaryLabelColor)
            )
        }
    }
}

// MARK: - Theme Picker Row

private struct ThemePickerRow: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                ThemeCard(theme: theme, isSelected: selection == theme)
                    .onTapGesture { selection = theme }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool

    private var colors: ThemePreviewColors { ThemePreviewColors.colors(for: theme) }

    var body: some View {
        VStack(spacing: 6) {
            // 미니 3패널 레이아웃 (사이드바 | 콘텐츠 | 채팅)
            HStack(spacing: 0) {
                // 사이드바
                VStack(alignment: .leading, spacing: 3) {
                    Circle().fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 5, height: 5)
                        .padding(.bottom, DesignTokens.Spacing.xxs)
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 2) {
                            Circle()
                                .fill(i == 0 ? Color(hex: 0xFF3B30) : colors.textTertiary)
                                .frame(width: 3, height: 3)
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(colors.textSecondary.opacity(i == 0 ? 1 : 0.5))
                                .frame(width: CGFloat.random(in: 16...22), height: 3)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, 0.5)
                        .background(
                            i == 0
                                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                                : nil
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(DesignTokens.Spacing.xxs)
                .frame(width: 36)
                .background(colors.surface)

                // 구분선
                Rectangle().fill(colors.border).frame(width: 0.5)

                // 콘텐츠 (플레이어)
                VStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(colors.surfaceLight)
                        Image(systemName: "play.fill")
                            .font(DesignTokens.Typography.custom(size: 7))
                            .foregroundStyle(colors.textTertiary.opacity(0.6))
                    }
                    .frame(height: 30)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(colors.textPrimary.opacity(0.6))
                            .frame(width: 28, height: 3)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 2) {
                        Circle().fill(Color(hex: 0xFF3B30)).frame(width: 3, height: 3)
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(colors.textTertiary)
                            .frame(width: 18, height: 2)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DesignTokens.Spacing.xxs)
                .frame(maxWidth: .infinity)
                .background(colors.background)

                // 구분선
                Rectangle().fill(colors.border).frame(width: 0.5)

                // 채팅 패널
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(colors.textSecondary.opacity(0.3))
                        .frame(width: 20, height: 3)
                        .padding(.bottom, DesignTokens.Spacing.xxs)
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(i == 2 ? DesignTokens.Colors.chzzkGreen.opacity(0.7) : colors.textSecondary.opacity(0.5))
                                .frame(width: CGFloat([8, 10, 6, 9][i]), height: 2)
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(colors.textTertiary.opacity(0.5))
                                .frame(width: CGFloat([14, 10, 16, 12][i]), height: 2)
                        }
                    }
                    Spacer(minLength: 0)
                    // 입력창
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(colors.surfaceLight)
                        .frame(height: 6)
                }
                .padding(DesignTokens.Spacing.xxs)
                .frame(width: 34)
                .background(colors.backgroundElevated)
            }
            .frame(height: 68)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Glass.borderColor,
                        lineWidth: isSelected ? 2 : 1
                    )
            }

            // 라벨 + 선택 인디케이터
            HStack(spacing: 4) {
                Image(systemName: theme.icon)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                Text(theme.displayName)
                    .font(DesignTokens.Typography.custom(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(DesignTokens.Animation.fast, value: isSelected)
    }
}

// MARK: - Theme Preview Panel (Detailed)

/// 선택된 테마의 상세 미리보기 — 사이드바 | 플레이어 | 채팅
private struct ThemePreviewPanel: View {
    let theme: AppTheme

    private var c: ThemePreviewColors { ThemePreviewColors.colors(for: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                Text("미리보기")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(theme.displayName)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)

            // 메인 프리뷰
            HStack(spacing: 0) {
                previewSidebar
                Rectangle().fill(c.border).frame(width: 1)
                previewContent
                Rectangle().fill(c.border).frame(width: 1)
                previewChat
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(c.border.opacity(0.6), lineWidth: 1)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .animation(DesignTokens.Animation.normal, value: theme)
        }
    }

    // MARK: - Sidebar

    private var previewSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 로고
            HStack(spacing: 5) {
                Image(systemName: "c.square.fill")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("CView")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                    .foregroundStyle(c.textPrimary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.xs)

            Rectangle().fill(c.border.opacity(0.5)).frame(height: 0.5)
                .padding(.horizontal, DesignTokens.Spacing.xs)

            // 채널 목록
            VStack(spacing: 1) {
                ForEach(Array(sidebarItems.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.isLive ? Color(hex: 0xFF3B30) : c.textTertiary.opacity(0.4))
                            .frame(width: 5, height: 5)
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(c.textPrimary.opacity(idx == 0 ? 0.85 : 0.5))
                            .frame(width: item.nameWidth, height: 4)
                        Spacer(minLength: 0)
                        if item.isLive {
                            Text("LIVE")
                                .font(DesignTokens.Typography.custom(size: 5, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .padding(.horizontal, DesignTokens.Spacing.xxs)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .background(Color(hex: 0xFF3B30), in: Capsule())
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(
                        idx == 0
                            ? RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                            : nil
                    )
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                }
            }
            .padding(.top, DesignTokens.Spacing.xs)

            Spacer(minLength: 0)
        }
        .frame(width: 90)
        .background(c.surface)
    }

    // MARK: - Content (Player)

    private var previewContent: some View {
        VStack(spacing: 0) {
            // 플레이어 영역
            ZStack {
                c.surfaceLight
                VStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                        .font(DesignTokens.Typography.subhead)
                        .foregroundStyle(c.textTertiary.opacity(0.3))
                    // 프로그레스 바
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(c.textTertiary.opacity(0.2))
                            .frame(height: 2)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
            .frame(maxWidth: .infinity)

            // 스트림 정보
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(c.textPrimary.opacity(0.8))
                        .frame(width: 80, height: 5)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        Circle().fill(Color(hex: 0xFF3B30)).frame(width: 4, height: 4)
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(c.textSecondary.opacity(0.6))
                            .frame(width: 20, height: 3)
                    }
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(c.textSecondary.opacity(0.4))
                        .frame(width: 50, height: 3)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.3))
                        .frame(width: 30, height: 3)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(c.backgroundElevated)
        }
        .frame(maxWidth: .infinity)
        .background(c.background)
    }

    // MARK: - Chat

    private var previewChat: some View {
        VStack(spacing: 0) {
            // 채팅 헤더
            HStack(spacing: 4) {
                Text("채팅")
                    .font(DesignTokens.Typography.custom(size: 7, weight: .semibold))
                    .foregroundStyle(c.textPrimary.opacity(0.8))
                Spacer(minLength: 0)
                Image(systemName: "person.2.fill")
                    .font(DesignTokens.Typography.custom(size: 6))
                    .foregroundStyle(c.textTertiary)
                Text("1.2K")
                    .font(DesignTokens.Typography.custom(size: 6))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)

            Rectangle().fill(c.border.opacity(0.5)).frame(height: 0.5)

            // 채팅 메시지
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(chatMessages.enumerated()), id: \.offset) { _, msg in
                        HStack(alignment: .top, spacing: 3) {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(msg.nameColor)
                                .frame(width: msg.nameWidth, height: 3)
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                .fill(c.textPrimary.opacity(0.45))
                                .frame(width: msg.msgWidth, height: 3)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }

            Spacer(minLength: 0)

            Rectangle().fill(c.border.opacity(0.5)).frame(height: 0.5)

            // 입력창
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(c.surfaceLight)
                    .frame(height: 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(c.textTertiary.opacity(0.3))
                            .frame(width: 28, height: 3)
                            .padding(.leading, DesignTokens.Spacing.xxs)
                    }
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.2))
                    .frame(width: 16, height: 12)
                    .overlay {
                        Image(systemName: "paperplane.fill")
                            .font(DesignTokens.Typography.custom(size: 5))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .frame(width: 100)
        .background(c.backgroundElevated)
    }

    // MARK: - Mock Data

    private struct SidebarItem {
        let nameWidth: CGFloat
        let isLive: Bool
    }

    private var sidebarItems: [SidebarItem] {
        [
            SidebarItem(nameWidth: 36, isLive: true),
            SidebarItem(nameWidth: 28, isLive: true),
            SidebarItem(nameWidth: 40, isLive: false),
            SidebarItem(nameWidth: 32, isLive: false),
            SidebarItem(nameWidth: 24, isLive: false),
        ]
    }

    private struct ChatMsg {
        let nameWidth: CGFloat
        let msgWidth: CGFloat
        let nameColor: Color
    }

    private var chatMessages: [ChatMsg] {
        [
            ChatMsg(nameWidth: 16, msgWidth: 36, nameColor: DesignTokens.Colors.chzzkGreen.opacity(0.7)),
            ChatMsg(nameWidth: 20, msgWidth: 24, nameColor: DesignTokens.Colors.accentBlue.opacity(0.7)),
            ChatMsg(nameWidth: 14, msgWidth: 40, nameColor: DesignTokens.Colors.accentPurple.opacity(0.7)),
            ChatMsg(nameWidth: 18, msgWidth: 30, nameColor: DesignTokens.Colors.accentOrange.opacity(0.7)),
            ChatMsg(nameWidth: 22, msgWidth: 20, nameColor: DesignTokens.Colors.chzzkGreen.opacity(0.7)),
            ChatMsg(nameWidth: 12, msgWidth: 34, nameColor: DesignTokens.Colors.accentPink.opacity(0.7)),
            ChatMsg(nameWidth: 18, msgWidth: 28, nameColor: DesignTokens.Colors.accentBlue.opacity(0.7)),
            ChatMsg(nameWidth: 16, msgWidth: 38, nameColor: DesignTokens.Colors.accentPurple.opacity(0.7)),
        ]
    }
}
