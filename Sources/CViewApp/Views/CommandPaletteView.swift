// MARK: - CommandPaletteView.swift
// CViewApp - Spotlight/Raycast-style command palette (⌘K)
// Design: Floating panel with fuzzy search, categories, keyboard navigation

import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Command Category

enum CommandCategory: String, CaseIterable, Sendable {
    case navigation = "탐색"
    case action = "액션"
    case settings = "설정"
    case channel = "최근 채널"

    var icon: String {
        switch self {
        case .navigation: "arrow.triangle.turn.up.right.diamond.fill"
        case .action: "bolt.fill"
        case .settings: "gearshape.fill"
        case .channel: "play.tv.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .navigation: DesignTokens.Colors.chzzkGreen
        case .action: DesignTokens.Colors.accentBlue
        case .settings: DesignTokens.Colors.accentPurple
        case .channel: DesignTokens.Colors.accentOrange
        }
    }
}

// MARK: - Command Item

struct CommandItem: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let category: CommandCategory
    let shortcut: String?
    let action: @MainActor @Sendable () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        category: CommandCategory,
        shortcut: String? = nil,
        action: @MainActor @Sendable @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.shortcut = shortcut
        self.action = action
    }
}

// MARK: - Fuzzy Match

/// Fuzzy-match: characters must appear in order but not consecutively.
/// Returns a score (lower is better, nil means no match).
private func fuzzyMatch(query: String, target: String) -> Int? {
    guard !query.isEmpty else { return 0 }
    let queryChars = Array(query.lowercased())
    let targetChars = Array(target.lowercased())
    var queryIndex = 0
    var score = 0
    var lastMatchIndex = -1

    for (i, char) in targetChars.enumerated() {
        guard queryIndex < queryChars.count else { break }
        if char == queryChars[queryIndex] {
            // Penalize gaps between matched characters
            if lastMatchIndex >= 0 {
                score += (i - lastMatchIndex - 1)
            }
            lastMatchIndex = i
            queryIndex += 1
        }
    }

    // All query characters matched?
    return queryIndex == queryChars.count ? score : nil
}

// MARK: - Command Palette View

struct CommandPaletteView: View {

    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    // MARK: - Commands

    private var allCommands: [CommandItem] {
        var commands: [CommandItem] = []

        // ── Navigation ──
        commands.append(contentsOf: [
            CommandItem(id: "nav-home", title: "홈", subtitle: "메인 홈 화면으로 이동", icon: "house.fill", category: .navigation) { [router] in
                router.selectSidebar(.home)
            },
            CommandItem(id: "nav-following", title: "팔로잉", subtitle: "팔로잉 채널 목록", icon: "heart.fill", category: .navigation) { [router] in
                router.selectSidebar(.following)
            },
            CommandItem(id: "nav-search", title: "검색", subtitle: "채널·방송 검색", icon: "magnifyingglass", category: .navigation) { [router] in
                router.selectSidebar(.search)
            },
            CommandItem(id: "nav-settings", title: "설정", subtitle: "앱 설정", icon: "gearshape.fill", category: .navigation, shortcut: "⌘,") { [router] in
                router.selectSidebar(.settings)
            },
            CommandItem(id: "nav-multilive", title: "멀티라이브", subtitle: "여러 방송 동시 시청", icon: "rectangle.split.3x1.fill", category: .navigation) { [router] in
                router.selectSidebar(.multiLive)
            },
            CommandItem(id: "nav-multichat", title: "멀티채팅", subtitle: "여러 채팅방 동시 보기", icon: "bubble.left.and.bubble.right.fill", category: .navigation) { [router] in
                router.selectSidebar(.multiChat)
            },
            CommandItem(id: "nav-category", title: "카테고리", subtitle: "카테고리 탐색", icon: "square.grid.2x2.fill", category: .navigation) { [router] in
                router.selectSidebar(.category)
            },
            CommandItem(id: "nav-clips", title: "클립", subtitle: "인기 클립 보기", icon: "film.stack", category: .navigation) { [router] in
                router.selectSidebar(.clips)
            },
            CommandItem(id: "nav-recent", title: "최근/즐겨찾기", subtitle: "최근 본 채널 & 즐겨찾기", icon: "clock.arrow.circlepath", category: .navigation) { [router] in
                router.selectSidebar(.recentFavorites)
            },
        ])

        // ── Actions ──
        commands.append(contentsOf: [
            CommandItem(id: "act-refresh", title: "새로고침", subtitle: "현재 데이터 새로고침", icon: "arrow.clockwise", category: .action, shortcut: "⌘R") { [appState] in
                Task { await appState.homeViewModel?.refresh() }
            },
            CommandItem(id: "act-chat-clear", title: "채팅 지우기", subtitle: "채팅 메시지 모두 삭제", icon: "trash", category: .action, shortcut: "⌘⇧K") { [appState] in
                appState.chatViewModel?.clearMessages()
            },
            CommandItem(id: "act-screenshot", title: "화면 캡처", subtitle: "현재 스트림 스크린샷", icon: "camera.fill", category: .action, shortcut: "⌘S") { [appState] in
                appState.playerViewModel?.takeScreenshot()
            },
            CommandItem(id: "act-autoscroll", title: "자동 스크롤 토글", subtitle: "채팅 자동 스크롤 켜기/끄기", icon: "arrow.down.to.line", category: .action, shortcut: "⌘J") { [appState] in
                appState.chatViewModel?.toggleAutoScroll()
            },
            CommandItem(id: "act-fullscreen", title: "전체 화면", subtitle: "영상 전체 화면 토글", icon: "arrow.up.left.and.arrow.down.right", category: .action, shortcut: "⌃⌘F") { [appState] in
                appState.playerViewModel?.toggleFullscreen()
            },
            CommandItem(id: "act-pip", title: "PiP 모드", subtitle: "화면 속 화면", icon: "pip.fill", category: .action, shortcut: "⌥⌘P") { [appState] in
                if let engine = appState.playerViewModel?.mediaPlayer {
                    let avEngine: AVPlayerEngine? = nil
                    PiPController.shared.togglePiP(vlcEngine: engine, avEngine: avEngine, title: appState.playerViewModel?.channelName ?? "PiP")
                }
            },
            CommandItem(id: "act-playpause", title: "재생/일시정지", subtitle: "스트림 재생 토글", icon: "playpause.fill", category: .action, shortcut: "Space") { [appState] in
                Task { await appState.playerViewModel?.togglePlayPause() }
            },
            CommandItem(id: "act-mute", title: "음소거 토글", subtitle: "소리 켜기/끄기", icon: "speaker.slash.fill", category: .action, shortcut: "M") { [appState] in
                appState.playerViewModel?.toggleMute()
            },
        ])

        // ── Settings Quick Toggle ──
        let currentTheme = appState.settingsStore.appearance.theme
        let themeLabel = currentTheme == .dark ? "라이트모드로 전환" : "다크모드로 전환"
        commands.append(contentsOf: [
            CommandItem(id: "set-theme", title: themeLabel, subtitle: "현재: \(currentTheme.displayName)", icon: currentTheme == .dark ? "sun.max.fill" : "moon.fill", category: .settings) { [appState] in
                let newTheme: AppTheme = appState.settingsStore.appearance.theme == .dark ? .light : .dark
                appState.settingsStore.appearance.theme = newTheme
                Task { await appState.settingsStore.save() }
            },
            CommandItem(id: "set-compact", title: "컴팩트 모드 토글", subtitle: appState.settingsStore.appearance.compactMode ? "현재: 켜짐" : "현재: 꺼짐", icon: "rectangle.compress.vertical", category: .settings) { [appState] in
                appState.settingsStore.appearance.compactMode.toggle()
                Task { await appState.settingsStore.save() }
            },
        ])

        // ── Recent / Online Channels ──
        let onlineChannels = appState.backgroundUpdateService.onlineChannels
        for channel in onlineChannels.prefix(8) {
            commands.append(
                CommandItem(
                    id: "ch-\(channel.channelId)",
                    title: channel.channelName,
                    subtitle: "🔴 LIVE · \(channel.formattedViewerCount)명 시청",
                    icon: "play.tv.fill",
                    category: .channel
                ) { [router] in
                    router.navigate(to: .live(channelId: channel.channelId))
                }
            )
        }

        return commands
    }

    private var filteredCommands: [CommandItem] {
        guard !searchText.isEmpty else { return allCommands }
        return allCommands
            .compactMap { item -> (CommandItem, Int)? in
                // Match against title and subtitle
                let titleScore = fuzzyMatch(query: searchText, target: item.title)
                let subtitleScore = item.subtitle.flatMap { fuzzyMatch(query: searchText, target: $0) }
                let categoryScore = fuzzyMatch(query: searchText, target: item.category.rawValue)
                // Take best score
                let scores = [titleScore, subtitleScore, categoryScore].compactMap { $0 }
                guard let best = scores.min() else { return nil }
                return (item, best)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacityLight))
                .frame(height: 0.5)

            // Results
            if filteredCommands.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: 560, height: min(CGFloat(filteredCommands.count) * 44 + 64, 480))
        .background(.ultraThinMaterial)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(DesignTokens.Colors.border.opacity(0.4), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.subhead)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            TextField("명령어 검색…", text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.custom(size: 16))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isSearchFocused)
                .onSubmit { executeSelected() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // ESC hint — Glass pill
            Text("ESC")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    let grouped = groupedCommands
                    ForEach(Array(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                        if let items = grouped[category], !items.isEmpty {
                            categoryHeader(category)

                            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                                let globalIndex = globalIndexOf(item)
                                commandRow(item: item, isSelected: globalIndex == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { executeCommand(item) }
                            }
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                let items = filteredCommands
                if newIndex >= 0, newIndex < items.count {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.escape) {
                isPresented = false
                return .handled
            }
            .onKeyPress(.return) {
                executeSelected()
                return .handled
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("일치하는 명령이 없습니다")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Category Header

    private func categoryHeader(_ category: CommandCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(category.tintColor.opacity(0.8))
            Text(category.rawValue.uppercased())
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .tracking(0.8)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xxs)
    }

    // MARK: - Command Row

    private func commandRow(item: CommandItem, isSelected: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(item.category.tintColor.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: item.icon)
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(item.category.tintColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(DesignTokens.Typography.custom(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Shortcut badge
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            }

            // Selection indicator
            if isSelected {
                Image(systemName: "return")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.15), lineWidth: 0.5)
                    }
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, DesignTokens.Spacing.xxs)
    }

    // MARK: - Helpers

    private var groupedCommands: [CommandCategory: [CommandItem]] {
        Dictionary(grouping: filteredCommands, by: \.category)
    }

    private func globalIndexOf(_ item: CommandItem) -> Int {
        filteredCommands.firstIndex(where: { $0.id == item.id }) ?? -1
    }

    private func moveSelection(by delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func executeSelected() {
        let items = filteredCommands
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        executeCommand(items[selectedIndex])
    }

    private func executeCommand(_ item: CommandItem) {
        withAnimation(DesignTokens.Animation.fast) {
            isPresented = false
        }
        item.action()
    }
}

// MARK: - Command Palette Overlay Modifier

struct CommandPaletteOverlay: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        // Backdrop
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(DesignTokens.Animation.fast) {
                                    isPresented = false
                                }
                            }

                        // Palette — positioned near top
                        VStack {
                            Spacer()
                                .frame(height: 80)
                            CommandPaletteView(isPresented: $isPresented)
                            Spacer()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .animation(DesignTokens.Animation.snappy, value: isPresented)
    }
}

extension View {
    func commandPaletteOverlay(isPresented: Binding<Bool>) -> some View {
        modifier(CommandPaletteOverlay(isPresented: isPresented))
    }
}
