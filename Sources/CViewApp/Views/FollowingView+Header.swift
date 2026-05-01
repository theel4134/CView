// MARK: - FollowingView+Header.swift
// FollowingView 확장 — 헤더 섹션, 검색/필터 카드, 정렬 메뉴

import SwiftUI
import CViewCore

extension FollowingView {

    // MARK: - Live Hub Top Bar (2026-04-27 Final Redesign)
    //
    // 도큐먼트 지침: 상단에는 `탐색 / 시청 / 멀티` 3개 모드 버튼만 둔다.
    // 검색·팔로잉 도구·필터는 모두 하단 Bottom Sheet로 이동.
    // Quality/Tools/Inspector 등은 Command Palette 또는 stage popover로 격리.

    var liveHubTopBar: some View {
        GeometryReader { proxy in
            // [Fix 2026-05-01 v2] 본문 카드(`overviewStage`)와 동일한 좌·우 24pt 인셋을 적용해
            // 상단 컨트롤이 카드 가장자리와 한 컬럼 그리드처럼 정렬되도록 한다.
            //   - 좌측: 모드 토글 (탐색/시청/멀티) → 카드 좌측 가장자리
            //   - 우측: 액션 rail (LIVE n / Command / 더보기 등) → 카드 우측 가장자리
            // 배경/경계선은 GeometryReader 바깥의 .background / .overlay 가 스테이지 폭 전체로 그려준다.
            let stageWidth = proxy.size.width
            let inset: CGFloat = DesignTokens.Spacing.xl  // 24pt (overviewStage 와 동일)
            let controlWidth = max(stageWidth - inset * 2, 0)
            let metrics = liveTopBarMetrics(for: controlWidth)

            HStack(spacing: DesignTokens.Spacing.md) {
                hubModeSegment(style: metrics.modeStyle)
                    .layoutPriority(10)

                Spacer(minLength: 0)

                actionRail(tier: metrics.actionTier)
                    .layoutPriority(1)
            }
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 48)
        // [Refine 2026-05-01] 좌→우 chzzkGreen 0.08 wash 가 본문 색감과 충돌해
        // 시각적으로 단절된 "스트라이프"처럼 보이는 문제를 제거.
        // `menuTopChrome` 으로 통일된 수직 페이드 + 페이드 hairline 디바이더 적용.
        .menuTopChrome()
    }

    // MARK: - Top Bar V2 Metrics

    private enum LiveTopBarActionTier: Int, CaseIterable {
        case tier0Full
        case tier1CommandCompact
        case tier2MoreCompact
        case tier3MoreOnly
    }

    private enum LiveTopBarModeStyle {
        case wide
        case regular
        case compact
    }

    private struct LiveTopBarMetrics {
        let actionTier: LiveTopBarActionTier
        let modeStyle: LiveTopBarModeStyle
    }

    /// `availableWidth` = 좌·우 인셋(24pt × 2)을 제외한 실제 컨트롤 영역 폭.
    /// 이 안에 모드 토글 + Spacer + 액션 rail 이 들어가야 하므로,
    /// 모드 dock 너비와 액션 rail 너비의 합 + 안전 여백이 들어갈 수 있는 가장 풍부한 tier 를 선택한다.
    private func liveTopBarMetrics(for availableWidth: CGFloat) -> LiveTopBarMetrics {
        let modeStyle: LiveTopBarModeStyle = availableWidth < 720 ? .compact : (availableWidth < 1080 ? .regular : .wide)
        let modeDockWidth = modeDockWidth(for: modeStyle)

        // Tier 우선값 — 폭이 넓을수록 풍부한 정보 노출
        let preferredTier: LiveTopBarActionTier
        switch availableWidth {
        case ..<720: preferredTier = .tier3MoreOnly
        case ..<880: preferredTier = .tier2MoreCompact
        case ..<1080: preferredTier = .tier1CommandCompact
        default: preferredTier = .tier0Full
        }

        // 보호 계산: 모드 dock + 액션 rail 이 컨트롤 영역에 못 들어가면 tier 강등
        let candidates = LiveTopBarActionTier.allCases
            .filter { $0.rawValue >= preferredTier.rawValue }
            .sorted { $0.rawValue < $1.rawValue }

        let selectedTier = candidates.first { tier in
            let actionWidth = actionRailWidth(for: tier)
            // 24pt = 모드/액션 사이 최소 간격(가독성), DesignTokens.Spacing.md == 12pt 두 개 분
            let required = modeDockWidth + actionWidth + 24
            return required <= availableWidth
        } ?? .tier3MoreOnly

        return LiveTopBarMetrics(
            actionTier: selectedTier,
            modeStyle: modeStyle
        )
    }

    /// 모드 dock(탐색/시청/멀티 캡슐)의 추정 너비 — 보호 계산용.
    /// 실제 너비는 `hubModeSegment` 내부 콘텐츠가 결정하지만,
    /// tier 강등 판정에는 충분히 안전한 상한값이 필요해 모드 스타일별로 산정한다.
    private func modeDockWidth(for style: LiveTopBarModeStyle) -> CGFloat {
        switch style {
        case .wide: return 332
        case .regular: return 286
        case .compact: return 168  // 아이콘만 노출되는 compact 모드
        }
    }

    private func actionRailWidth(for tier: LiveTopBarActionTier) -> CGFloat {
        let hasLive = viewModel.followingLiveCount > 0
        switch tier {
        case .tier0Full:
            return hasLive ? 268 : 206
        case .tier1CommandCompact:
            return hasLive ? 230 : 168
        case .tier2MoreCompact:
            return hasLive ? 168 : 100
        case .tier3MoreOnly:
            return 40
        }
    }

    // MARK: - Top Bar Rails

    // [Removed 2026-05-01 v2] identityRail — 좌측 브랜드 아이콘은 사이드바 "라이브" 항목과 중복되고
    // 본문 카드 좌측 경계와의 정렬을 깨뜨려 시각적 단절을 만들어 제거.

    @ViewBuilder
    private func actionRail(tier: LiveTopBarActionTier) -> some View {
        HStack(spacing: 8) {
            switch tier {
            case .tier0Full:
                liveChip(style: .full)
                commandButton(textVisible: true)
                themeCycleButton
                refreshIconButton
            case .tier1CommandCompact:
                liveChip(style: .wordOnly)
                commandButton(textVisible: false)
                themeCycleButton
                refreshIconButton
            case .tier2MoreCompact:
                liveChip(style: .dotCount)
                commandButton(textVisible: false)
                moreMenu
            case .tier3MoreOnly:
                moreMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private enum LiveChipStyle {
        case full
        case wordOnly
        case dotCount
    }

    @ViewBuilder
    private func liveChip(style: LiveChipStyle) -> some View {
        if viewModel.followingLiveCount > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 6, height: 6)
                switch style {
                case .full:
                    Text("LIVE \(min(viewModel.followingLiveCount, 999))\(viewModel.followingLiveCount > 999 ? "+" : "")")
                case .wordOnly:
                    Text("LIVE")
                case .dotCount:
                    Text("\(min(viewModel.followingLiveCount, 999))\(viewModel.followingLiveCount > 999 ? "+" : "")")
                        .monospacedDigit()
                }
            }
            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))
            .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6))
        }
    }

    private func commandButton(textVisible: Bool) -> some View {
        Button {
            appState.showCommandPalette = true
        } label: {
            HStack(spacing: textVisible ? 4 : 0) {
                Image(systemName: "command")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                if textVisible {
                    Text("Command")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, textVisible ? 9 : 0)
            .frame(width: textVisible ? nil : 28, height: 28)
            .background {
                if textVisible {
                    Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.85))
                } else {
                    Circle().fill(DesignTokens.Colors.surfaceBase.opacity(0.85))
                }
            }
            .overlay {
                if textVisible {
                    Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6)
                } else {
                    Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Command Palette (⌘K)")
    }

    private var refreshIconButton: some View {
        Button {
            guard !viewModel.isLoadingFollowing else { return }
            Task { await viewModel.loadFollowingChannels(invalidateThumbnails: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))
                .overlay(Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6))
                .rotationEffect(.degrees(viewModel.isLoadingFollowing ? refreshRotation : 0))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoadingFollowing)
        .help("새로고침")
    }

    private var moreMenu: some View {
        Menu {
            Button("Command Palette") {
                appState.showCommandPalette = true
            }

            Menu("테마") {
                Button("System") {
                    appState.settingsStore.appearance.theme = .system
                    Task { await appState.settingsStore.save() }
                }
                Button("Light") {
                    appState.settingsStore.appearance.theme = .light
                    Task { await appState.settingsStore.save() }
                }
                Button("Dark") {
                    appState.settingsStore.appearance.theme = .dark
                    Task { await appState.settingsStore.save() }
                }
            }

            Button("새로고침") {
                guard !viewModel.isLoadingFollowing else { return }
                Task { await viewModel.loadFollowingChannels(invalidateThumbnails: true) }
            }
            .disabled(viewModel.isLoadingFollowing)

            Divider()

            Button("네트워크 모니터") { openWindow(id: "ml-network-window") }
            Button("메트릭 전송") { openWindow(id: "ml-metrics-window") }

            if viewModel.followingLiveCount > 0 {
                Divider()
                Text("현재 라이브 \(viewModel.followingLiveCount)개")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))
                .overlay(Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("더보기")
    }

    // MARK: - Theme Cycle Button (2026-04-28)
    //
    // 디자인 사료 §2 Theme Mode: Light / Dark / System 3가지를 toolbar 우측에 노출.
    // 클릭 시 System → Light → Dark → System 순으로 순환 전환한다.
    private var themeCycleButton: some View {
        let theme = appState.settingsStore.appearance.theme
        return Button {
            let next: AppTheme = {
                switch theme {
                case .system: return .light
                case .light: return .dark
                case .dark: return .system
                }
            }()
            appState.settingsStore.appearance.theme = next
            Task { await appState.settingsStore.save() }
        } label: {
            Image(systemName: theme.icon)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))
                .overlay(Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .help("테마: \(theme.displayName) (클릭하여 전환)")
    }

    private func hubModeSegment(style: LiveTopBarModeStyle) -> some View {
        let horizontalPadding: CGFloat = switch style {
        case .wide: 14
        case .regular: 12
        case .compact: 9
        }
        let titleVisible = style != .compact

        return HStack(spacing: 3) {
            ForEach(FollowingHubMode.allCases, id: \.self) { mode in
                Button {
                    applyHubModePreset(mode)
                } label: {
                    HStack(spacing: titleVisible ? 5 : 0) {
                        Image(systemName: mode.icon)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        if titleVisible {
                            Text(mode.rawValue)
                                .font(DesignTokens.Typography.custom(size: 12, weight: hubMode == mode ? .bold : .medium))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(hubMode == mode ? .white : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(hubMode == mode
                                  ? AnyShapeStyle(DesignTokens.Colors.chzzkGreen)
                                  : AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.96))
                .accessibilityLabel("모드: \(mode.rawValue)")
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.85))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6)
        )
    }

    func applyHubModePreset(_ mode: FollowingHubMode) {
        withAnimation(DesignTokens.Animation.snappy) {
            ps.applyHubModePreset(mode, multiLiveManager: multiLiveManager)
        }
    }

    private var hubStageSummaryText: String {
        switch hubMode {
        case .explore: return "탐색"
        case .watch: return "시청"
        case .multi: return "멀티"
        }
    }

    private var hubModeDetailText: String {
        switch hubMode {
        case .explore: return "목록 탐색 + 필터"
        case .watch: return "현재 채널 빠른 전환"
        case .multi: return "세션 조합 + 채팅 동시"
        }
    }

    // [Removed 2026-04-28] hubDrawerSummaryText — 사용처 없음 (레거시 Inspector 문구)

    // MARK: - Header Section (모던 리디자인)

    var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 상단: 타이틀 + 액션
            HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                Text("팔로잉")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                headerActionButtons
            }

            // 하단: 스탯 배지 + 검색창 (같은 줄 — 좍은 폭에서는 검색이 유연하게 수축)
            HStack(spacing: DesignTokens.Spacing.sm) {
                headerStatBadges
                    .layoutPriority(0)
                searchBarContent
                    .layoutPriority(1)
                    .frame(minWidth: 140, maxWidth: 320)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    /// 헤더 통계 배지 (채널수, 라이브수, 시청자수) — 경량 인라인 배지
    var headerStatBadges: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if !viewModel.followingChannels.isEmpty {
                headerBadge(
                    icon: "heart.fill",
                    text: "\(viewModel.followingChannels.count)",
                    color: DesignTokens.Colors.accentPink
                )
            }
            if viewModel.followingLiveCount > 0 {
                headerBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "\(viewModel.followingLiveCount) 라이브",
                    color: DesignTokens.Colors.live
                )
            }
            if viewModel.followingTotalViewers > 0 {
                headerBadge(
                    icon: "eye.fill",
                    text: formatShortCount(viewModel.followingTotalViewers),
                    color: DesignTokens.Colors.accentBlue
                )
            }
            if viewModel.followingLiveRate > 0 {
                headerBadge(
                    icon: "chart.bar.fill",
                    text: "\(viewModel.followingLiveRate)%",
                    color: DesignTokens.Colors.accentPurple
                )
            }
        }
    }

    func headerBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(DesignTokens.Opacity.light)))
        .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 0.5))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// 헤더 액션 버튼 그룹
    var headerActionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 새로고침 + 자동 새로고침 토글 (통합)
            refreshControl

            // 멀티라이브 토글
            headerToggleChip(
                icon: "rectangle.split.2x2",
                label: "멀티라이브",
                count: multiLiveManager.sessions.isEmpty ? nil : "\(multiLiveManager.sessions.count)/\(multiLiveManager.effectiveMaxSessions)",
                isOn: showMultiLive,
                accent: DesignTokens.Colors.chzzkGreen,
                helpText: showMultiLive ? "멀티라이브 닫기" : "멀티라이브 열기"
            ) {
                withAnimation(DesignTokens.Animation.snappy) { showMultiLive.toggle() }
            }

            // 멀티채팅 토글
            headerToggleChip(
                icon: "bubble.left.and.bubble.right",
                label: "멀티채팅",
                count: chatSessionManager.sessions.isEmpty ? nil : "\(chatSessionManager.sessions.count)",
                isOn: showMultiChat,
                accent: DesignTokens.Colors.accentOrange,
                helpText: showMultiChat ? "멀티채팅 닫기" : "멀티채팅 열기"
            ) {
                withAnimation(DesignTokens.Animation.snappy) { showMultiChat.toggle() }
            }
        }
    }

    /// 헤더 토글 칩 — 중립 기본 + 활성 시 그라데이션 + 하단 2pt 악센트 바
    @ViewBuilder
    func headerToggleChip(
        icon: String,
        label: String,
        count: String?,
        isOn: Bool,
        accent: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let count {
                    Text(count)
                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isOn ? Color.white.opacity(0.22) : accent.opacity(0.18))
                        )
                        .foregroundStyle(isOn ? .white : accent)
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(isOn ? .white : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(
                              colors: [accent, accent.opacity(0.82)],
                              startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(DesignTokens.Colors.surfaceElevated.opacity(0.45)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isOn ? accent.opacity(0.35) : DesignTokens.Glass.borderColorLight.opacity(0.35),
                        lineWidth: 0.5
                    )
            )
            .overlay(alignment: .bottom) {
                if isOn {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 2)
                        .padding(.horizontal, 3)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .shadow(color: isOn ? accent.opacity(0.28) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .fixedSize()
        .animation(DesignTokens.Animation.snappy, value: isOn)
        .help(helpText)
    }
    // MARK: - Refresh Control (무한 회전 방지 + 자동 새로고침 토글)

    /// 새로고침 버튼 + 자동 새로고침 on/off (Menu)
    /// - 버튼 탭: 수동 새로고침 (중복 호출 가드 포함)
    /// - 우측 chevron: 자동 새로고침 토글 메뉴
    /// - 로딩 중에는 버튼 비활성 + 별도 @State rotation으로 안정적 스핀 (value 변경 시 즉시 정지)
    @ViewBuilder
    var refreshControl: some View {
        HStack(spacing: 2) {
            Button {
                guard !viewModel.isLoadingFollowing else { return }
                Task { await viewModel.loadFollowingChannels(invalidateThumbnails: true) }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                        .foregroundStyle(viewModel.isLoadingFollowing
                                         ? DesignTokens.Colors.chzzkGreen
                                         : DesignTokens.Colors.textTertiary)
                        .rotationEffect(.degrees(refreshRotation))
                }
            }
            .buttonStyle(IconButtonStyle())
            .disabled(viewModel.isLoadingFollowing)
            .help(viewModel.isLoadingFollowing ? "새로고침 중…" : "새로고침 (썸네일 포함)")
            .task(id: viewModel.isLoadingFollowing) {
                guard viewModel.isLoadingFollowing else {
                    withAnimation(DesignTokens.Animation.micro) { refreshRotation = 0 }
                    return
                }
                // 로딩 중인 동안만 수동 각도 증가 루프 (value가 false가 되면 즉시 종료)
                while !Task.isCancelled && viewModel.isLoadingFollowing {
                    withAnimation(.linear(duration: 0.9)) {
                        refreshRotation += 360
                    }
                    try? await Task.sleep(for: .milliseconds(900))
                }
            }

            // 자동 새로고침 메뉴
            autoRefreshMenu
        }
    }

    /// 자동 새로고침 on/off 메뉴 (체크마크 + 간격)
    @ViewBuilder
    var autoRefreshMenu: some View {
        @Bindable var bindableSettings = appState.settingsStore
        Menu {
            Toggle("자동 새로고침", isOn: Binding(
                get: { bindableSettings.general.autoRefreshEnabled },
                set: { newValue in
                    bindableSettings.general.autoRefreshEnabled = newValue
                    appState.syncAutoRefreshState()
                }
            ))

            Section("자동 새로고침 간격") {
                ForEach([30, 60, 120, 300], id: \.self) { sec in
                    Button {
                        bindableSettings.general.autoRefreshInterval = TimeInterval(sec)
                        appState.syncAutoRefreshState()
                    } label: {
                        HStack {
                            Text(sec < 60 ? "\(sec)초" : (sec % 60 == 0 ? "\(sec / 60)분" : "\(sec)초"))
                            if Int(bindableSettings.general.autoRefreshInterval) == sec {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!bindableSettings.general.autoRefreshEnabled)
                }
            }
        } label: {
            Image(systemName: appState.settingsStore.general.autoRefreshEnabled
                  ? "clock.arrow.circlepath"
                  : "clock.badge.xmark")
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(appState.settingsStore.general.autoRefreshEnabled
                                 ? DesignTokens.Colors.chzzkGreen
                                 : DesignTokens.Colors.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(appState.settingsStore.general.autoRefreshEnabled
              ? "자동 새로고침 설정 (현재 \(Int(appState.settingsStore.general.autoRefreshInterval))초)"
              : "자동 새로고침 꺼짐")
    }

    // MARK: - Search & Filter Card

    /// 활성 필터 수 (검색 + 라이브필터 + 카테고리)
    private var activeFilterCount: Int {
        var count = 0
        if !searchText.isEmpty { count += 1 }
        if filterLiveOnly { count += 1 }
        if selectedCategory != nil { count += 1 }
        return count
    }

    var searchAndFilterCard: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            filterSegmentContent
            sortMenuButton
            Spacer(minLength: 0)
            if activeFilterCount > 0 { activeFilterBadge }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .animation(DesignTokens.Animation.snappy, value: activeFilterCount > 0)
    }

    /// 활성 필터 배지 — 클릭 시 모든 필터 초기화
    private var activeFilterBadge: some View {
        Button {
            withAnimation(DesignTokens.Animation.snappy) {
                searchText = ""
                filterLiveOnly = false
                selectedCategory = nil
            }
        } label: {
            HStack(spacing: 3) {
                Text("필터 \(activeFilterCount)개")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Image(systemName: "xmark")
                    .font(DesignTokens.Typography.custom(size: 8, weight: .bold))
            }
            .foregroundStyle(DesignTokens.Colors.accentOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DesignTokens.Colors.accentOrange.opacity(0.12))
                    .overlay(Capsule().strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .transition(.scale(scale: 0.7).combined(with: .opacity))
        .help("모든 필터 초기화")
    }

    var searchBarContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(
                    searchText.isEmpty
                        ? DesignTokens.Colors.textTertiary
                        : DesignTokens.Colors.chzzkGreen
                )
                .scaleEffect(isSearchFocused ? 1.1 : 1.0)
                .animation(DesignTokens.Animation.snappy, value: isSearchFocused)

            TextField("채널, 방송 제목, 카테고리 검색...", text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.custom(size: 13))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    withAnimation(DesignTokens.Animation.snappy) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.85))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(isSearchFocused ? 0.95 : 0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSearchFocused
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Glass.borderColorLight.opacity(0.35),
                    lineWidth: isSearchFocused ? 1.2 : 0.5
                )
        )
        .shadow(
            color: isSearchFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.18) : .clear,
            radius: 6  // [GPU] 고정
        )
        .animation(DesignTokens.Animation.snappy, value: isSearchFocused)
        .animation(DesignTokens.Animation.snappy, value: searchText.isEmpty)
    }

    var filterSegmentContent: some View {
        HStack(spacing: 2) {
            filterSegment(
                isActive: !filterLiveOnly,
                icon: "person.3.fill",
                title: "전체",
                count: viewModel.followingChannels.count
            ) {
                withAnimation(DesignTokens.Animation.snappy) {
                    filterLiveOnly = false
                    selectedCategory = nil
                }
            }
            filterSegment(
                isActive: filterLiveOnly,
                icon: "dot.radiowaves.left.and.right",
                title: "라이브",
                count: viewModel.followingLiveCount
            ) {
                withAnimation(DesignTokens.Animation.snappy) {
                    filterLiveOnly = true
                    selectedCategory = nil
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.5)
        )
        .fixedSize()
    }

    func filterSegment(isActive: Bool, icon: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .symbolEffect(.bounce, value: isActive)
                Text(title)
                    .font(DesignTokens.Typography.footnoteMedium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? .white.opacity(0.85) : DesignTokens.Colors.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(isActive ? .white : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.82)],
                            startPoint: .top, endPoint: .bottom))
                        // [GPU] shadow 고정 (radius 애니메이션 제거)
                        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.3), radius: 5, y: 1)
                        .matchedGeometryEffect(id: "filterSegmentPill", in: filterPillNS)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.95))
        .fixedSize()
    }

    // MARK: - Sort Menu

    var sortMenuButton: some View {
        Menu {
            ForEach(FollowingSortOrder.allCases) { order in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) { sortOrder = order }
                } label: {
                    HStack {
                        Label(order.rawValue, systemImage: order.icon)
                        if sortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: sortOrder.icon)
                    .font(.system(size: layout.sortIconSize, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(sortOrder.rawValue)
                    .font(DesignTokens.Typography.micro)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: layout.sortChevronSize, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.4), in: Capsule())
            .animation(DesignTokens.Animation.snappy, value: sortOrder)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Gate / Empty Views

    func followingGateView(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        buttonLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: layout.gateIconSize, weight: .ultraLight))
                .foregroundStyle(iconColor.opacity(0.6))
                .symbolEffect(.pulse.byLayer, options: .speed(0.5).repeat(.continuous))

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if let label = buttonLabel, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.95))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
