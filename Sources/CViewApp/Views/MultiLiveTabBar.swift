// MARK: - MultiLiveTabBar.swift
import SwiftUI
import CViewCore
import UniformTypeIdentifiers

// MARK: - Tab Bar
struct MLTabBar: View {
    let manager: MultiLiveManager
    @Binding var isGridLayout: Bool
    let onAdd: () -> Void
    var isAddPanelOpen: Bool = false
    var onSettings: (() -> Void)? = nil
    var isSettingsPanelOpen: Bool = false
    var showFollowingList: Bool = false
    var onFollowingToggle: (() -> Void)? = nil
    // 멀티채팅 토글 (인라인 패널 전용 — 스탠드얼론에서는 숨김)
    var showMultiChatToggle: Bool = false
    var isMultiChatOpen: Bool = false
    var multiChatSessionCount: Int = 0
    var onMultiChatToggle: (() -> Void)? = nil

    @State private var showStopAllConfirm = false
    @State private var draggingSessionId: UUID?

    private var layoutModeIcon: String {
        switch manager.gridLayoutMode {
        case .preset:    return "rectangle.grid.2x2"
        case .custom:    return "rectangle.split.3x1.fill"
        case .focusLeft: return "rectangle.leadinghalf.inset.filled"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            tabScrollArea
            Spacer(minLength: 0)
            gridToolbar
            settingsArea
            multiChatToggleArea
            followingListArea
        }
        // [hiddenTitleBar 대응 2026-04-21] 창 최상단 ~10pt 는 macOS 전통적으로
        // 트래픽 라이트/드래그 영역으로 인지되는 구간이므로, 탭 칩을 해당 구간
        // 아래로 밀어 상단이 "잘려 보이는" 착시를 제거한다.
        // [2026-04-22] 하단 4pt 여유 + 실선 Divider 로 영상 영역과 명확히 분리.
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(height: MSTokens.tabBarHeight)
        // [Refined Classic 2026-04-22] Material 제거, solid surfaceBase + subtle
        // 그라데이션으로 칩 주변 콘텐츠 대비 확보. 하단 hairline divider.
        .background {
            ZStack {
                DesignTokens.Colors.surfaceBase
                // 상단 살짝 밝은 톤으로 높이감 부여
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.03),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor.opacity(0.35))
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        .zIndex(2)
    }

    // MARK: - Tab Scroll Area

    private var tabScrollArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(manager.sessions) { session in
                    MLTabChip(
                        session: session,
                        manager: manager,
                        isSelected: manager.selectedSessionId == session.id,
                        isAudioActive: (manager.audioSessionId ?? manager.selectedSessionId) == session.id,
                        isGridMode: isGridLayout,
                        onSelect: {
                            withAnimation(DesignTokens.Animation.micro) {
                                manager.select(session)
                            }
                        },
                        onClose: { Task { await manager.removeSession(session) } },
                        onMoveLeft:  { manager.moveSessionLeft(session) },
                        onMoveRight: { manager.moveSessionRight(session) }
                    )
                    .onDrag {
                        draggingSessionId = session.id
                        return NSItemProvider(object: session.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: MLTabReorderDropDelegate(
                        targetSession: session,
                        manager: manager,
                        draggingSessionId: $draggingSessionId
                    ))
                    .opacity(draggingSessionId == session.id ? 0.4 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: draggingSessionId)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            // [탭 클리핑 해소 2026-04-21] ScrollView 내부 수직 패딩을 최소화 — 칩 상하 패딩(4pt)과
            // 합해 칩 시각높이가 tabBarHeight(44pt)를 초과하지 않도록 조정.
            .padding(.vertical, 2)
        }
    }

    // MARK: - Grid Toolbar

    @ViewBuilder
    private var gridToolbar: some View {
        if manager.sessions.count >= 2 {
            if isGridLayout {
                layoutModeMenu
                ratioResetButton
                multiAudioToggle
            }
            gridTabToggle
        }
    }

    private var layoutModeMenu: some View {
        Menu {
            Button {
                withAnimation(DesignTokens.Animation.snappy) { manager.gridLayoutMode = .preset }
                manager.saveState()
            } label: {
                Label("프리셋 그리드", systemImage: "rectangle.grid.2x2")
                if manager.gridLayoutMode == .preset { Image(systemName: "checkmark") }
            }
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    manager.gridLayoutMode = .custom
                    manager.resetLayoutRatios()
                }
                manager.saveState()
            } label: {
                Label("커스텀 리사이즈", systemImage: "rectangle.split.3x1")
                if manager.gridLayoutMode == .custom { Image(systemName: "checkmark") }
            }
            Button {
                withAnimation(DesignTokens.Animation.snappy) { manager.gridLayoutMode = .focusLeft }
                manager.saveState()
            } label: {
                Label("포커스 레이아웃 (1+N)", systemImage: "rectangle.leadinghalf.inset.filled")
                if manager.gridLayoutMode == .focusLeft { Image(systemName: "checkmark") }
            }
        } label: {
            MLToolButton(icon: layoutModeIcon, isActive: manager.gridLayoutMode != .preset, help: "레이아웃 모드 변경") {}
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, DesignTokens.Spacing.xxs)
    }

    @ViewBuilder
    private var ratioResetButton: some View {
        if manager.gridLayoutMode == .custom || manager.gridLayoutMode == .focusLeft {
            MLToolButton(icon: "arrow.counterclockwise", isActive: false, help: "레이아웃 비율 초기화") {
                withAnimation(DesignTokens.Animation.snappy) { manager.resetLayoutRatios() }
            }
            .padding(.trailing, DesignTokens.Spacing.xxs)
        }
    }

    private var multiAudioToggle: some View {
        MLToolButton(
            icon: manager.isMultiAudioMode ? "speaker.wave.3.fill" : "speaker.wave.1.fill",
            isActive: manager.isMultiAudioMode,
            help: manager.isMultiAudioMode ? "단일 오디오 모드로 전환" : "멀티 오디오 모드 (여러 채널 동시 청취)"
        ) {
            withAnimation(DesignTokens.Animation.snappy) { manager.toggleMultiAudioMode() }
        }
        .padding(.trailing, DesignTokens.Spacing.xxs)
    }

    private var gridTabToggle: some View {
        MLToolButton(
            icon: isGridLayout ? "rectangle.split.3x1" : "rectangle.grid.2x2",
            isActive: isGridLayout,
            help: isGridLayout ? "탭 모드로 전환" : "그리드 모드로 전환"
        ) {
            // [렌더링 최적화] 레이아웃 전환만 애니메이션, VLC 상태 변경은 프레임 드롭 방지를 위해 분리
            withAnimation(DesignTokens.Animation.snappy) {
                isGridLayout.toggle()
            }
            // VLC/오디오 상태 업데이트 — 애니메이션 블록 외부에서 실행
            if isGridLayout {
                for s in manager.sessions { s.setBackgroundMode(false) }
                let count = manager.sessions.count
                for s in manager.sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: count) }
                if !manager.isMultiAudioMode {
                    if let sel = manager.selectedSession {
                        for s in manager.sessions { s.setMuted(s.id != sel.id) }
                        manager.audioSessionId = sel.id
                    }
                }
            } else {
                for s in manager.sessions { s.setBackgroundMode(s.id != manager.selectedSessionId) }
                manager.isMultiAudioMode = false
                manager.audioEnabledSessionIds.removeAll()
                if !manager.isMultiAudioMode {
                    manager.audioSessionId = nil
                    for s in manager.sessions { s.setMuted(s.id != manager.selectedSessionId) }
                }
            }
            manager.saveState()
            // [drawable 복구] 그리드↔탭 전환 시 drawable 재바인딩은
            // PlayerContainerView.attachVideoView()에서 자동 처리.
            // 여기서 중복 호출하면 추가 검은 프레임 플래시 발생.
        }
        .padding(.trailing, DesignTokens.Spacing.xxs)
    }

    // MARK: - Settings Area

    @ViewBuilder
    private var settingsArea: some View {
        if !manager.sessions.isEmpty {
            mlDivider
            MLToolButton(
                icon: isSettingsPanelOpen ? "gearshape.fill" : "gearshape",
                isActive: isSettingsPanelOpen,
                help: "멀티라이브 설정"
            ) { onSettings?() }
            .padding(.trailing, DesignTokens.Spacing.xxs)

            // 전체 해제
            MLToolButton(
                icon: "xmark.circle",
                isActive: false,
                help: "전체 채널 해제"
            ) { showStopAllConfirm = true }
            .padding(.trailing, DesignTokens.Spacing.xxs)
            .confirmationDialog(
                "멀티라이브 전체 해제",
                isPresented: $showStopAllConfirm,
                titleVisibility: .visible
            ) {
                Button("전체 해제", role: .destructive) {
                    Task { await manager.stopAll() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("\(manager.sessions.count)개 채널의 스트림을 모두 해제할까요?")
            }
        }
    }

    // MARK: - Multi-Chat Toggle Area

    @ViewBuilder
    private var multiChatToggleArea: some View {
        if showMultiChatToggle, let onToggle = onMultiChatToggle {
            if !manager.sessions.isEmpty { mlDivider }
            MSChipButton(
                icon: isMultiChatOpen
                    ? "bubble.left.and.bubble.right.fill"
                    : "bubble.left.and.bubble.right",
                title: "멀티채팅",
                style: .accent,
                isActive: isMultiChatOpen,
                count: multiChatSessionCount,
                action: onToggle
            )
            .padding(.trailing, DesignTokens.Spacing.xxs)
            .help(isMultiChatOpen ? "멀티채팅 닫기" : "멀티채팅 열기")
        }
    }

    // MARK: - Following List Toggle Area

    @ViewBuilder
    private var followingListArea: some View {
        if !manager.sessions.isEmpty || showMultiChatToggle { mlDivider }
        MSChipButton(
            icon: "sidebar.left",
            title: "팔로잉",
            style: .accent,
            isActive: showFollowingList,
            action: { onFollowingToggle?() }
        )
        .padding(.trailing, DesignTokens.Spacing.sm)
        .help(showFollowingList ? "팔로잉 목록 닫기" : "팔로잉 목록 열기")
    }

    // MARK: - Divider Helper

    private var mlDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColorLight)
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, DesignTokens.Spacing.xxs)
    }
}

// MARK: - Tool Button
private struct MLToolButton: View {
    let icon: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(
                    isActive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary
                )
                .symbolEffect(.bounce, value: isActive)
                .frame(width: 28, height: 28)
                // [Modern Curves 2026-04-21] 정사각형 배경 → 원형 Capsule
                .background {
                    if isActive {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.10))
                            .overlay {
                                Circle()
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.20), lineWidth: 0.5)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    } else if isHovered {
                        Circle()
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(0.4))
                            .transition(.opacity)
                    }
                }
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .help(help)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .animation(DesignTokens.Animation.snappy, value: isActive)
    }
}

// MARK: - Tab Reorder Drop Delegate

private struct MLTabReorderDropDelegate: DropDelegate {
    let targetSession: MultiLiveSession
    let manager: MultiLiveManager
    @Binding var draggingSessionId: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingSessionId,
              dragId != targetSession.id,
              let fromIndex = manager.sessions.firstIndex(where: { $0.id == dragId }),
              let toIndex = manager.sessions.firstIndex(where: { $0.id == targetSession.id })
        else { return }

        withAnimation(DesignTokens.Animation.fast) {
            manager.sessions.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSessionId = nil
        manager.saveState()
        return true
    }

    func dropExited(info: DropInfo) {}

    func validateDrop(info: DropInfo) -> Bool {
        draggingSessionId != nil
    }
}

// MARK: - Tab Chip
struct MLTabChip: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    let isSelected: Bool
    let isAudioActive: Bool
    let isGridMode: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        Button(action: onSelect) {
            chipContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .contextMenu { contextMenuItems }
    }

    // MARK: - Chip Content

    private var chipContent: some View {
        HStack(spacing: 8) {
            avatarView
            channelInfo
            closeButton
        }
        .padding(.leading, 6)
        .padding(.trailing, closeButtonVisible ? 4 : 12)
        // [Refined Classic 2026-04-22] 2줄 구조 칩, 솔리드 배경 스타일.
        // Material/specular(plusLighter) 제거하고 surfaceElevated 솔리드 + subtle gradient.
        .padding(.vertical, 5)
        .frame(minWidth: MSTokens.tabChipMinWidth, maxWidth: MSTokens.tabChipMaxWidth, alignment: .leading)
        .background(chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(chipBorder)
        // 선택 하단 언더라인 (classic Safari-pre-17 / Chrome 스타일) — 2pt green capsule
        .overlay(alignment: .bottom) {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen,
                                DesignTokens.Colors.chzzkGreen.opacity(0.75),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2.5)
                    .padding(.horizontal, 14)
                    .offset(y: 1)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.85), radius: 5, y: 0)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // 로딩 중 하단 progress bar (선택 상태가 아닐 때만)
        .overlay(alignment: .bottom) {
            if case .loading = session.loadState, !isSelected {
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                    .frame(height: 1.5)
                    .padding(.horizontal, 14)
                    .offset(y: 1)
                    .transition(.opacity)
            }
        }
        // 선택 탭만 아주 은은한 drop shadow
        .shadow(
            color: isSelected ? Color.black.opacity(0.22) : .clear,
            radius: 6, x: 0, y: 2
        )
        .animation(DesignTokens.Animation.snappy, value: isSelected)
        .help(chipTooltip)
    }

    // MARK: - Chip Background / Border (Refined Classic)

    @ViewBuilder
    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if isSelected {
            ZStack {
                // 베이스: elevated surface
                shape.fill(DesignTokens.Colors.surfaceElevated)
                // 악센트: green gradient — 선택 상태 강조
                shape.fill(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.chzzkGreen.opacity(0.28),
                            DesignTokens.Colors.chzzkGreen.opacity(0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        } else if isHovered {
            shape.fill(DesignTokens.Colors.surfaceElevated.opacity(0.55))
        } else {
            Color.clear
        }
    }

    private var chipBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.55)
                    : (isHovered
                        ? DesignTokens.Glass.borderColor.opacity(0.45)
                        : Color.clear),
                lineWidth: isSelected ? 1.2 : 0.5
            )
    }

    private var closeButtonVisible: Bool { isHovered || isSelected }

    private var chipTooltip: String {
        var parts: [String] = [tabTitle]
        if !session.liveTitle.isEmpty { parts.append(session.liveTitle) }
        switch session.loadState {
        case .playing:   break
        case .loading:   parts.append("연결 중")
        case .error:     parts.append("오류")
        case .offline:   parts.append("방송 종료")
        case .idle:      parts.append("대기")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Channel Info (premium 2-line)

    private var channelInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(tabTitle)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                // 라이브 뱃지 (playing 상태일 때만, 아주 작게)
                if case .playing = session.loadState {
                    Text("LIVE")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous).fill(DesignTokens.Colors.error)
                        )
                }

                statusBadge
            }

            // 2번째 줄: 라이브 제목 (playing) / 상태 텍스트 (그 외)
            Text(chipSubtitle)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                .foregroundStyle(chipSubtitleColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// 2번째 줄 텍스트 — 라이브 제목 우선, 없으면 상태.
    private var chipSubtitle: String {
        if case .playing = session.loadState, !session.liveTitle.isEmpty {
            return session.liveTitle
        }
        switch session.loadState {
        case .playing: return "라이브 방송 중"
        case .loading: return "연결 중…"
        case .error:   return "연결 오류"
        case .offline: return "방송 종료"
        case .idle:    return "대기 중"
        }
    }

    private var chipSubtitleColor: Color {
        switch session.loadState {
        case .error:   return DesignTokens.Colors.error.opacity(0.85)
        case .loading: return DesignTokens.Colors.chzzkGreen.opacity(0.8)
        default:       return DesignTokens.Colors.textTertiary
        }
    }

    // MARK: - Status Badge (right side, inline)

    @ViewBuilder
    private var statusBadge: some View {
        switch session.loadState {
        case .playing where isGridMode:
            audioIndicator
        case .loading:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 10, height: 10)
                .tint(DesignTokens.Colors.chzzkGreen)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.error)
        default:
            EmptyView()
        }
    }

    // MARK: - Leading Status Dot (아바타 대신 방송 상태만 점으로)

    @ViewBuilder
    private var leadingStatusDot: some View {
        // 현재 premium 디자인에서는 avatarView 가 statusDot 을 포함하므로 미사용.
        EmptyView()
    }

    // MARK: - Audio Indicator

    @ViewBuilder
    private var audioIndicator: some View {
        if isGridMode {
            if manager.isMultiAudioMode {
                Image(systemName: manager.isAudioEnabled(for: session) ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    .foregroundStyle(manager.isAudioEnabled(for: session) ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
            } else if isAudioActive {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
        }
    }

    // MARK: - Reorder Arrows

    @ViewBuilder
    private var reorderArrows: some View {
        if manager.sessions.count > 1 {
            HStack(spacing: 2) {
                reorderButton(icon: "chevron.left",  action: onMoveLeft)
                reorderButton(icon: "chevron.right", action: onMoveRight)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DesignTokens.Typography.custom(size: 8, weight: .bold))
                .foregroundStyle(
                    isCloseHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary
                )
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .background {
                    Circle().fill(
                        isCloseHovered
                            ? DesignTokens.Colors.surfaceOverlay.opacity(0.9)
                            : (isHovered ? DesignTokens.Colors.surfaceElevated.opacity(0.5) : Color.clear)
                    )
                }
                .scaleEffect(isCloseHovered ? 1.08 : 1.0)
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isCloseHovered)
        .opacity(isHovered || isSelected ? 1 : 0)
    }

    // MARK: - Avatar (refined classic, 28pt gradient + status ring)

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            // 베이스 gradient — specular 없이 깨끗한 원형
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            avatarColor,
                            avatarColor.opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(tabTitle.prefix(1)).uppercased())
                        .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                )
                .overlay(
                    Circle().stroke(avatarStrokeColor, lineWidth: avatarStrokeWidth)
                )

            statusDot
        }
    }

    /// 라이브 방송 중 여부 (avatar glow 용도)
    private var isLive: Bool {
        if case .playing = session.loadState { return true }
        return false
    }

    private var avatarStrokeColor: Color {
        if isAudioActive && isGridMode { return DesignTokens.Colors.chzzkGreen }
        if isLive { return DesignTokens.Colors.chzzkGreen.opacity(0.85) }
        if isSelected { return DesignTokens.Colors.chzzkGreen.opacity(0.65) }
        return Color.white.opacity(0.08)
    }
    private var avatarStrokeWidth: CGFloat {
        if isAudioActive && isGridMode { return 2.0 }
        if isLive { return 1.5 }
        if isSelected { return 1.0 }
        return 0.5
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.loadState {
        case .playing:
            statusDotShape(fill: DesignTokens.Colors.chzzkGreen,
                           glow: DesignTokens.Colors.chzzkGreen.opacity(0.6))
        case .loading:
            statusDotShape(fill: DesignTokens.Colors.textTertiary, glow: .clear)
        case .error:
            statusDotShape(fill: DesignTokens.Colors.error,
                           glow: DesignTokens.Colors.error.opacity(0.5))
        case .offline:
            statusDotShape(fill: DesignTokens.Colors.textTertiary, glow: .clear)
        default:
            EmptyView()
        }
    }

    /// 아바타 우하단 상태 점 — 아바타 경계 안에 배치.
    private func statusDotShape(fill: Color, glow: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 9, height: 9)
            .overlay(
                Circle().stroke(DesignTokens.Colors.surfaceBase, lineWidth: 1.6)
            )
            .shadow(color: glow, radius: 2.5)
            .offset(x: 1, y: 1)
    }

    // MARK: - Reorder Button

    private func reorderButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 7, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if isGridMode {
            if manager.isMultiAudioMode {
                Button { manager.toggleSessionAudio(session) } label: {
                    Label(
                        manager.isAudioEnabled(for: session) ? "오디오 끄기" : "오디오 켜기",
                        systemImage: manager.isAudioEnabled(for: session) ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                }
            } else {
                Button { manager.routeAudio(to: session) } label: {
                    Label("이 채널로 오디오 전환", systemImage: "speaker.wave.2.fill")
                }
            }
            Divider()
        }
        let idx = manager.sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        if idx > 0 {
            Button { onMoveLeft() } label: {
                Label("왼쪽으로 이동", systemImage: "arrow.left")
            }
        }
        if idx < manager.sessions.count - 1 {
            Button { onMoveRight() } label: {
                Label("오른쪽으로 이동", systemImage: "arrow.right")
            }
        }
        Divider()
        Button(role: .destructive) { onClose() } label: {
            Label("탭 닫기", systemImage: "xmark.circle")
        }
    }

    // MARK: - Helpers

    private var tabTitle: String { session.channelName.isEmpty ? session.channelId : session.channelName }

    private var avatarColor: Color {
        let palette: [Color] = [
            DesignTokens.Colors.accentBlue,
            DesignTokens.Colors.accentPurple,
            DesignTokens.Colors.accentPink,
            DesignTokens.Colors.accentOrange,
            DesignTokens.Colors.chzzkGreen,
        ]
        return palette[abs(session.channelId.hashValue) % palette.count]
    }
}

// MARK: - Viewer Count (렌더링 최적화)
private struct MLViewerCountText: View {
    let session: MultiLiveSession

    var body: some View {
        if session.viewerCount > 0 {
            Text(session.formattedViewerCount)
                .font(DesignTokens.Typography.custom(size: 10, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
}
