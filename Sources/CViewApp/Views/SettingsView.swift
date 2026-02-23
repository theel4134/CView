// MARK: - SettingsView.swift
// CViewApp - 설정 뷰 (macOS System Settings 스타일)

import SwiftUI
import CViewCore
import CViewNetworking
import CViewPersistence
import ServiceManagement

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
            // ── 좌측 사이드바
            settingsSidebar

            Divider()
                .background(Color.white.opacity(0.07))

            // ── 우측 콘텐츠
            ZStack {
                DesignTokens.Colors.backgroundDark.ignoresSafeArea()

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
        .background(DesignTokens.Colors.backgroundDark)
        // 설정 패널에서 채팅 설정 변경 시 실행 중인 ChatViewModel에도 즉시 반영
        .onChange(of: appState.settingsStore.chat) { _, newSettings in
            appState.chatViewModel?.applySettings(newSettings)
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(spacing: 2) {
            // 앱 헤더
            VStack(spacing: 4) {
                Image(systemName: "c.square.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("CView")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("v2.0")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .overlay(DesignTokens.Colors.border.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // 탭 목록
            ForEach(SettingsTab.allCases) { tab in
                SidebarTabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                }
            }

            Spacer()
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Colors.surface)
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
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? tab.color : tab.color.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.backgroundDark : tab.color)
                }
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tab.color.opacity(0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(tab.color.opacity(0.2), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignTokens.Colors.surfaceHover.opacity(0.5))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Shared Components

/// 설정 섹션 컨테이너
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            // 내용 카드
            VStack(spacing: 0) {
                content()
            }
            .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
            }
        }
    }
}

/// 설정 행 - 레이블 + 컨트롤
private struct SettingsRow<Control: View>: View {
    let label: String
    let description: String?
    let icon: String?
    let iconColor: Color
    @ViewBuilder let control: () -> Control

    init(
        _ label: String,
        description: String? = nil,
        icon: String? = nil,
        iconColor: Color = DesignTokens.Colors.textSecondary,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.description = description
        self.icon = icon
        self.iconColor = iconColor
        self.control = control
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 42)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
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
                }

                SettingsSection(title: "테마", icon: "paintpalette.fill", color: DesignTokens.Colors.accentPurple) {
                    ThemePickerRow(selection: $settings.appearance.theme)
                        .onChange(of: settings.appearance.theme) {
                            Task { await settings.save() }
                        }
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
                                description: "팔로잉 목록을 주기적으로 업데이트합니다",
                                icon: "arrow.clockwise", iconColor: DesignTokens.Colors.accentBlue) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.general.autoRefreshInterval, format: .number)
                                .frame(width: 52)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                            Text("초")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.general) { _, _ in Task { await settings.save() } }
        .onChange(of: settings.appearance) { _, _ in Task { await settings.save() } }
        .onChange(of: settings.general.launchAtLogin) { _, newValue in
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Player Settings

struct PlayerSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "재생 설정", icon: "play.circle.fill", color: DesignTokens.Colors.chzzkGreen) {
                    SettingsRow("기본 화질", icon: "4k.tv.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Picker("", selection: $settings.player.quality) {
                            ForEach(StreamQuality.allCases, id: \.self) { q in
                                Text(q.displayName).tag(q)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("재생 엔진", icon: "cpu", iconColor: DesignTokens.Colors.accentBlue) {
                        Picker("", selection: $settings.player.preferredEngine) {
                            ForEach(PlayerEngineType.allCases, id: \.self) { e in
                                Text(e.displayName).tag(e)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("자동 재생",
                                description: "채널 진입 시 즉시 재생을 시작합니다",
                                icon: "play.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.player.autoPlay)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .labelsHidden()
                    }
                }

                SettingsSection(title: "저지연 최적화", icon: "bolt.circle.fill", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("저지연 모드",
                                description: "딜레이를 최소화합니다. 네트워크 부하가 증가할 수 있습니다",
                                icon: "bolt.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.player.lowLatencyMode)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("버퍼 시간",
                                description: "낮을수록 지연이 줄지만 끊김이 발생할 수 있습니다",
                                icon: "clock.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.player.bufferDuration, in: 0.5...8, step: 0.5)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                            Text(String(format: "%.1f초", settings.player.bufferDuration))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                    RowDivider()
                    SettingsRow("캐치업 속도",
                                description: "딜레이가 쌓일 때 재생 속도를 높여 따라잡습니다",
                                icon: "forward.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.player.catchupRate, in: 1.0...1.3, step: 0.01)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                            Text(String(format: "×%.2f", settings.player.catchupRate))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                }

                SettingsSection(title: "볼륨", icon: "speaker.wave.2.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("기본 볼륨", icon: "speaker.wave.2.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Slider(value: $settings.player.volumeLevel, in: 0...1, step: 0.05)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentPurple)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(Int(settings.player.volumeLevel * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 36)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.player) { _, _ in Task { await settings.save() } }
    }
}

// MARK: - Chat Settings

struct ChatSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var showBlockedUsers = false
    @State private var newKeyword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                // ── 표시 설정 ──────────────────────────────────────
                SettingsSection(title: "표시 설정", icon: "textformat.size", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("글꼴 크기", icon: "textformat", iconColor: DesignTokens.Colors.accentPurple) {
                        HStack(spacing: 6) {
                            Text("가").font(.system(size: 10)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Slider(value: $settings.chat.fontSize, in: 10...24, step: 1)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("가").font(.system(size: 16)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(Int(settings.chat.fontSize))pt")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 34)
                        }
                    }
                    RowDivider()
                    SettingsRow("투명도", icon: "circle.lefthalf.filled", iconColor: .gray) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.chat.chatOpacity, in: 0.3...1.0, step: 0.05)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("\(Int(settings.chat.chatOpacity * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 34)
                        }
                    }
                    RowDivider()
                    SettingsRow("줄 간격", icon: "arrow.up.and.down.text.horizontal",
                                iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.chat.lineSpacing, in: 0...8, step: 1)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text(String(format: "%.0fpt", settings.chat.lineSpacing))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 38)
                        }
                    }
                    RowDivider()
                    SettingsRow("타임스탬프 표시",
                                icon: "clock", iconColor: DesignTokens.Colors.textSecondary) {
                        Toggle("", isOn: $settings.chat.showTimestamp)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("뱃지 표시",
                                icon: "shield.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.showBadge)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("멘션 강조",
                                description: "내 닉네임 언급 시 하이라이트",
                                icon: "at", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.chat.highlightMentions)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                }

                // ── 콘텐츠 설정 ────────────────────────────────────
                SettingsSection(title: "콘텐츠", icon: "sparkles", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("이모티콘 표시",
                                icon: "face.smiling", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.chat.emoticonEnabled)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("도네이션 표시",
                                icon: "heart.fill", iconColor: DesignTokens.Colors.live) {
                        Toggle("", isOn: $settings.chat.showDonation)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("도네이션만 표시",
                                description: "일반 채팅 숨기고 도네이션만 표시",
                                icon: "line.3.horizontal.decrease.circle", iconColor: DesignTokens.Colors.live) {
                        Toggle("", isOn: $settings.chat.showDonationsOnly)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
                    }
                }

                // ── 필터 설정 ──────────────────────────────────────
                SettingsSection(title: "필터 & 스크롤", icon: "line.3.horizontal.decrease.circle.fill",
                                color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("자동 스크롤",
                                icon: "arrow.down.to.line", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.autoScroll)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("채팅 필터 활성화",
                                description: "차단 키워드가 포함된 메시지를 숨깁니다",
                                icon: "line.3.horizontal.decrease.circle", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.chatFilterEnabled)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("최대 메시지 수",
                                description: "초과 시 오래된 메시지부터 제거",
                                icon: "list.bullet", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.chat.maxVisibleMessages, format: .number)
                                .frame(width: 64)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                            Text("개")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }

                    // 차단 키워드 입력
                    if settings.chat.chatFilterEnabled {
                        RowDivider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("차단 키워드")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 6)

                            if !settings.chat.blockedWords.isEmpty {
                                SettingsFlowTagView(tags: settings.chat.blockedWords) { kw in
                                    settings.chat.blockedWords.removeAll { $0 == kw }
                                    Task { await settings.save() }
                                }
                                .padding(.horizontal, 14)
                            }

                            HStack(spacing: 6) {
                                TextField("키워드 입력 후 +", text: $newKeyword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .onSubmit { addKeyword() }
                                Button { addKeyword() } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                                        .font(.system(size: 18))
                                }
                                .buttonStyle(.plain)
                                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                        }
                    }
                }

                // ── 사용자 관리 ────────────────────────────────────
                SettingsSection(title: "사용자 관리", icon: "person.2.fill", color: DesignTokens.Colors.live) {
                    Button {
                        showBlockedUsers = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.live)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("차단된 사용자 관리")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text("\(settings.chat.blockedUsers.count)명 차단됨")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.chat) { _, _ in Task { await settings.save() } }
        .sheet(isPresented: $showBlockedUsers) {
            BlockedUsersView(chatVM: nil)
        }
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !settings.chat.blockedWords.contains(kw) else { return }
        settings.chat.blockedWords.append(kw)
        newKeyword = ""
        Task { await settings.save() }
    }
}

/// SettingsView 내 태그 흐름 레이아웃 (차단 키워드용)
private struct SettingsFlowTagView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        SettingsFlexibleLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                    Button { onRemove(tag) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.Colors.accentBlue.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

private struct SettingsFlexibleLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowH + verticalSpacing; x = 0; rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + verticalSpacing; x = bounds.minX; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
    }
}


// MARK: - Network Settings

struct NetworkSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "API 설정", icon: "server.rack", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("요청 제한",
                                description: "초당 최대 API 요청 수 (너무 낮으면 실시간 업데이트에 영향)",
                                icon: "speedometer", iconColor: DesignTokens.Colors.accentBlue) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.network.requestRateLimit, format: .number)
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                            Text("req/s")
                                .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    RowDivider()
                    SettingsRow("캐시 유효 시간",
                                description: "API 응답을 캐시로 유지하는 시간",
                                icon: "clock.arrow.circlepath", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.network.cacheExpiry, format: .number)
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                            Text("초")
                                .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    RowDivider()
                    SettingsRow("재시도 횟수",
                                description: "요청 실패 시 재시도 횟수",
                                icon: "arrow.clockwise", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.network.retryCount, format: .number)
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                            Text("회")
                                .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }

                SettingsSection(title: "WebSocket", icon: "bolt.horizontal.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("자동 재연결",
                                description: "채팅 연결이 끊어졌을 때 자동으로 재연결합니다",
                                icon: "antenna.radiowaves.left.and.right", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.network.autoReconnect)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("최대 재연결 시도",
                                description: "연속 실패 후 포기하기까지의 시도 횟수",
                                icon: "arrow.triangle.2.circlepath", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.network.maxReconnectAttempts, format: .number)
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                            Text("회")
                                .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.network) { _, newValue in
            Task {
                await settings.save()
                await appState.apiClient?.updateRetryCount(newValue.retryCount)
            }
        }
    }
}

// MARK: - Performance Settings

struct PerformanceSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var showResetAlert = false
    @State private var showCacheAlert = false
    @State private var cacheSize: String = "계산 중..."

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "하드웨어 & 메모리", icon: "cpu.fill", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("하드웨어 디코딩",
                                description: "GPU 가속을 사용해 CPU 부하를 줄입니다",
                                icon: "memorychip", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.appearance.hardwareDecoding)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("메모리 제한",
                                description: "초과 시 이미지 캐시를 자동으로 정리합니다",
                                icon: "memorychip.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        Picker("", selection: $settings.appearance.maxMemoryMB) {
                            Text("256 MB").tag(256)
                            Text("512 MB").tag(512)
                            Text("1 GB").tag(1024)
                            Text("2 GB").tag(2048)
                        }
                        .frame(width: 130)
                        .labelsHidden()
                    }
                }

                SettingsSection(title: "외관", icon: "paintbrush.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("콤팩트 모드",
                                description: "UI 요소 간격을 줄여 더 많은 정보를 표시합니다",
                                icon: "rectangle.compress.vertical", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.appearance.compactMode)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("사이드바 너비", icon: "sidebar.left", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.appearance.sidebarWidth, in: 180...400, step: 10)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("\(Int(settings.appearance.sidebarWidth))px")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 46)
                        }
                    }
                }

                SettingsSection(title: "캐시 & 초기화", icon: "trash.fill", color: DesignTokens.Colors.live) {
                    // 캐시 크기 표시
                    SettingsRow("현재 캐시 크기",
                                icon: "internaldrive", iconColor: DesignTokens.Colors.textSecondary) {
                        Text(cacheSize)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    RowDivider()
                    Button {
                        URLCache.shared.removeAllCachedResponses()
                        if let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                            try? FileManager.default.removeItem(at: dir.appendingPathComponent("image_cache"))
                        }
                        showCacheAlert = true
                        cacheSize = "0 MB"
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                                .frame(width: 18)
                            Text("캐시 전체 삭제")
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    Button(role: .destructive) {
                        Task {
                            await settings.resetAll()
                            showResetAlert = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.live)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("모든 설정 초기화")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DesignTokens.Colors.live)
                                Text("되돌릴 수 없습니다")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { cacheSize = measureCacheSize() }
        .onChange(of: settings.appearance) { _, _ in Task { await settings.save() } }
        .alert("설정 초기화 완료", isPresented: $showResetAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text("모든 설정이 기본값으로 초기화되었습니다.") }
        .alert("캐시 삭제 완료", isPresented: $showCacheAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text("URL 캐시 및 이미지 캐시가 삭제되었습니다.") }
    }

    private func measureCacheSize() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = base else { return "알 수 없음" }
        let total = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)
            .compactMap { try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($0).path)[.size] as? Int }
            .reduce(0, +)) ?? 0
        let mb = Double(total) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", mb * 1024) : String(format: "%.1f MB", mb)
    }
}

/// Reusable info row (구 코드 호환용, 현재 미사용이나 참조 가능)
private struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    var body: some View {
        HStack {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textSecondary).frame(width: 18)
            Text(label)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}

// MARK: - Theme Picker Row

private struct ThemePickerRow: View {
    @Binding var selection: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    ThemeCard(theme: theme, isSelected: selection == theme)
                        .onTapGesture { selection = theme }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool

    private var previewBg: Color {
        switch theme {
        case .system: Color(nsColor: .windowBackgroundColor)
        case .light: Color(hue: 0, saturation: 0, brightness: 0.96)
        case .dark: Color(hue: 0, saturation: 0, brightness: 0.12)
        }
    }
    private var previewSurface: Color {
        switch theme {
        case .system: Color(nsColor: .controlBackgroundColor)
        case .light: Color(hue: 0, saturation: 0, brightness: 0.88)
        case .dark: Color(hue: 0, saturation: 0, brightness: 0.20)
        }
    }
    private var previewText: Color {
        switch theme {
        case .system: Color(nsColor: .labelColor)
        case .light: .black.opacity(0.8)
        case .dark: .white.opacity(0.85)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // 미니 미리보기
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(previewBg)
                    .frame(height: 68)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle().fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(previewText.opacity(0.7))
                            .frame(width: 40, height: 5)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(previewSurface)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(previewSurface)
                        .frame(width: 55, height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(previewSurface)
                        .frame(width: 40, height: 12)
                }
                .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.chzzkGreen : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            }

            // 라벨 + 선택 인디케이터
            HStack(spacing: 4) {
                Image(systemName: theme.icon)
                    .font(.system(size: 10))
                Text(theme.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - MetricsSettingsTab

/// 메트릭 서버 전송 설정 탭
@MainActor
private struct MetricsSettingsTab: View {

    @Bindable var settings: SettingsStore
    @Environment(AppState.self) private var appState

    // MARK: 연결 테스트 상태
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false

    private enum ConnectionTestResult {
        case success(latencyMs: Double, message: String)
        case failure(message: String)

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .failure: "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .success: .green
            case .failure: .red
            }
        }
        var text: String {
            switch self {
            case .success(let ms, let msg): String(format: "연결 성공 (%.0fms) %@", ms, msg)
            case .failure(let msg): "연결 실패: \(msg)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ─── 헤더 ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Label("메트릭 서버 전송", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))

                    Text("VLC 플레이어 라이브 재생 데이터를 cv.dododo.app 메트릭 서버로 전송합니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                // ─── 기본 설정 ────────────────────────────────
                GroupBox {
                    VStack(spacing: 12) {
                        // 메트릭 전송 토글
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("메트릭 전송 활성화")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text("라이브 시청 시 레이턴시·FPS·버퍼 데이터를 서버로 전송합니다.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.metrics.metricsEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        Divider()
                            .background(Color.white.opacity(0.08))

                        // 서버 URL 입력
                        VStack(alignment: .leading, spacing: 6) {
                            Text("서버 URL")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            TextField("https://cv.dododo.app", text: $settings.metrics.serverURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(2)
                } label: {
                    Label("서버 설정", systemImage: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 연결 테스트 ──────────────────────────────
                GroupBox {
                    VStack(spacing: 10) {
                        // 테스트 버튼
                        Button {
                            Task {
                                isTesting = true
                                testResult = nil
                                let result = await appState.testMetricsConnection()
                                if result.success {
                                    testResult = .success(latencyMs: result.latencyMs, message: result.message)
                                } else {
                                    testResult = .failure(message: result.message)
                                }
                                isTesting = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 11))
                                }
                                Text(isTesting ? "테스트 중…" : "연결 테스트")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.9))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTesting)

                        // 테스트 결과
                        if let result = testResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.icon)
                                    .foregroundStyle(result.color)
                                    .font(.system(size: 12))
                                Text(result.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(result.color.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(2)
                } label: {
                    Label("연결 확인", systemImage: "network.badge.shield.half.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 전송 주기 ────────────────────────────────
                GroupBox {
                    VStack(spacing: 14) {
                        // 메트릭 전송 주기
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("메트릭 전송 주기")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.0f초", settings.metrics.forwardInterval))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Slider(
                                value: $settings.metrics.forwardInterval,
                                in: 2...30,
                                step: 1
                            )
                            .tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            Text("레이턴시·FPS·버퍼 상태를 서버로 전송하는 주기 (2~30초)")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }

                        Divider()
                            .background(Color.white.opacity(0.08))

                        // 핑 주기
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Keep-alive 핑 주기")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.0f초", settings.metrics.pingInterval))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Slider(
                                value: $settings.metrics.pingInterval,
                                in: 10...120,
                                step: 5
                            )
                            .tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            Text("서버에 시청 중임을 알리는 핑 전송 주기 (10~120초)")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .padding(2)
                } label: {
                    Label("전송 주기", systemImage: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 전송 데이터 안내 ──────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        payloadRow(icon: "timer",            label: "레이턴시",  desc: "PDT 기반 스트림 지연 (ms)")
                        payloadRow(icon: "film.stack",       label: "FPS",       desc: "VLC 초당 프레임 수")
                        payloadRow(icon: "backward.frame",   label: "드롭 프레임", desc: "VLC 손실 프레임 수")
                        payloadRow(icon: "waveform.path",    label: "버퍼 상태",  desc: "버퍼 충전률 (%)")
                        payloadRow(icon: "play.fill",        label: "플레이어",   desc: "엔진 식별자 (VLC)")
                    }
                    .padding(2)
                } label: {
                    Label("전송 데이터 목록", systemImage: "list.bullet.clipboard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        // 설정 변경 시 MetricsForwarder / APIClient에 즉시 적용
        .onChange(of: settings.metrics) { _, _ in
            Task {
                await settings.save()
                await appState.applyMetricsSettings()
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func payloadRow(icon: String, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(width: 70, alignment: .leading)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}

// MARK: - MetricsGroupBoxStyle

private struct MetricsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
