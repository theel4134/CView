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
        .frame(height: 40)
        .background { DesignTokens.Colors.surfaceBase }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
        // [Depth] 탭바 하단 그림자 — 콘텐츠 위에 떠 있는 헤더 느낌
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
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
            .padding(.vertical, DesignTokens.Spacing.xs)
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
            Button { onToggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: isMultiChatOpen
                          ? "bubble.left.and.bubble.right.fill"
                          : "bubble.left.and.bubble.right")
                        .font(DesignTokens.Typography.microSemibold)
                    Text("멀티채팅")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    if multiChatSessionCount > 0 {
                        Text("\(multiChatSessionCount)")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(
                                    isMultiChatOpen
                                        ? DesignTokens.Colors.controlOnDarkMediaHover
                                        : DesignTokens.Colors.chzzkGreen.opacity(0.18)
                                )
                            )
                    }
                }
                .foregroundStyle(
                    isMultiChatOpen ? .white : DesignTokens.Colors.chzzkGreen
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isMultiChatOpen
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.chzzkGreen.opacity(0.10)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isMultiChatOpen
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                            : DesignTokens.Colors.chzzkGreen.opacity(0.22),
                        lineWidth: 0.5
                    )
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, DesignTokens.Spacing.xxs)
            .animation(DesignTokens.Animation.fast, value: isMultiChatOpen)
            .help(isMultiChatOpen ? "멀티채팅 닫기" : "멀티채팅 열기")
        }
    }

    // MARK: - Following List Toggle Area

    @ViewBuilder
    private var followingListArea: some View {
        if !manager.sessions.isEmpty || showMultiChatToggle { mlDivider }
        Button { onFollowingToggle?() } label: {
            HStack(spacing: 4) {
                Image(systemName: "sidebar.left")
                    .font(DesignTokens.Typography.microSemibold)
                Text("팔로잉")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            }
            .foregroundStyle(
                showFollowingList ? .white : DesignTokens.Colors.chzzkGreen
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    showFollowingList
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.chzzkGreen.opacity(0.10)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    showFollowingList
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Colors.chzzkGreen.opacity(0.22),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, DesignTokens.Spacing.sm)
        .animation(DesignTokens.Animation.fast, value: showFollowingList)
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
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.15), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(0.3))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
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
        HStack(spacing: 6) {
            avatarView
            channelInfo
            if isHovered || isSelected { reorderArrows }
            closeButton
        }
        .padding(.leading, 6)
        .padding(.trailing, isHovered ? 4 : 6)
        .padding(.vertical, 4)
        .background(chipBackground)
        .clipShape(Capsule(style: .continuous))
        .overlay(chipBorder)
        .shadow(
            color: isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.10) : .clear,
            radius: 4, y: 1
        )
    }

    // MARK: - Channel Info

    private var channelInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(tabTitle)
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)
                audioIndicator
            }
            statusSubtext
        }
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

    // MARK: - Chip Border

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.30)
                    : (isHovered ? DesignTokens.Glass.borderColorLight.opacity(0.5) : Color.clear),
                lineWidth: isSelected ? 1.0 : 0.5
            )
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [avatarColor, avatarColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(
                            isAudioActive && isGridMode ? DesignTokens.Colors.chzzkGreen : Color.clear,
                            lineWidth: 1.5
                        )
                    )
                Text(String(tabTitle.prefix(1)).uppercased())
                    .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            statusDot
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.loadState {
        case .playing:
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 10, height: 10)
                Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 7, height: 7)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.5), radius: 2)
            }
            .offset(x: 3, y: 3)
        case .loading:
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 10, height: 10)
                ProgressView().scaleEffect(0.36).tint(DesignTokens.Colors.chzzkGreen)
            }
            .offset(x: 3, y: 3)
        case .error:
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 10, height: 10)
                Circle().fill(DesignTokens.Colors.error).frame(width: 7, height: 7)
                    .shadow(color: DesignTokens.Colors.error.opacity(0.4), radius: 2)
            }
            .offset(x: 3, y: 3)
        case .offline:
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 10, height: 10)
                Circle().fill(DesignTokens.Colors.textTertiary).frame(width: 7, height: 7)
            }
            .offset(x: 3, y: 3)
        default:
            EmptyView()
        }
    }

    // MARK: - Status Subtext

    @ViewBuilder
    private var statusSubtext: some View {
        switch session.loadState {
        case .playing:
            if !session.liveTitle.isEmpty {
                Text(session.liveTitle)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                    .help(session.liveTitle)
            } else if session.viewerCount > 0 {
                MLViewerCountText(session: session)
            } else {
                liveBadge
            }
        case .loading:
            Text("연결 중")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        case .error:
            Text("오류")
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.error)
        case .offline:
            Text("종료")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        case .idle:
            Text("대기")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(DesignTokens.Typography.custom(size: 8, weight: .black))
            .kerning(0.3)
            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, 1)
            .background(Capsule().fill(DesignTokens.Colors.live))
    }

    // MARK: - Chip Background

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            ZStack {
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.75))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen.opacity(0.10),
                                DesignTokens.Colors.chzzkGreen.opacity(0.04),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        } else if isHovered {
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.25))
        } else {
            Color.clear
        }
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
            DesignTokens.Colors.accentBlue.opacity(0.8),
            DesignTokens.Colors.accentPurple.opacity(0.75),
            DesignTokens.Colors.accentPink.opacity(0.75),
            DesignTokens.Colors.accentOrange.opacity(0.75),
            DesignTokens.Colors.chzzkGreen.opacity(0.65),
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
