// MARK: - MultiLiveTabBar.swift
import SwiftUI
import CViewCore

// MARK: - Tab Bar
struct MLTabBar: View {
    let manager: MultiLiveSessionManager
    @Binding var isGridLayout: Bool
    let onAdd: () -> Void
    var isAddPanelOpen: Bool = false

    private var layoutModeIcon: String {
        switch manager.gridLayoutMode {
        case .preset:    return "rectangle.grid.2x2"
        case .custom:    return "rectangle.split.3x1.fill"
        case .focusLeft: return "rectangle.leadinghalf.inset.filled"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── 채널 탭 스크롤 영역 ──
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
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
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }

            Spacer(minLength: 0)

            // ── 그리드/탭 전환 토글 ──
            if manager.sessions.count >= 2 {
                // 커스텀/프리셋 토글 (그리드 모드일 때만)
                if isGridLayout {
                    // 레이아웃 모드 메뉴
                    Menu {
                        Button {
                            withAnimation(DesignTokens.Animation.snappy) {
                                manager.gridLayoutMode = .preset
                            }
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
                            withAnimation(DesignTokens.Animation.snappy) {
                                manager.gridLayoutMode = .focusLeft
                            }
                            manager.saveState()
                        } label: {
                            Label("포커스 레이아웃 (1+N)", systemImage: "rectangle.leadinghalf.inset.filled")
                            if manager.gridLayoutMode == .focusLeft { Image(systemName: "checkmark") }
                        }
                    } label: {
                        MLToolButton(
                            icon: layoutModeIcon,
                            isActive: manager.gridLayoutMode != .preset,
                            help: "레이아웃 모드 변경"
                        ) {}
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.trailing, DesignTokens.Spacing.xxs)

                    // 비율 리셋 (커스텀 또는 포커스 모드일 때)
                    if manager.gridLayoutMode == .custom || manager.gridLayoutMode == .focusLeft {
                        MLToolButton(
                            icon: "arrow.counterclockwise",
                            isActive: false,
                            help: "레이아웃 비율 초기화"
                        ) {
                            withAnimation(DesignTokens.Animation.snappy) {
                                manager.resetLayoutRatios()
                            }
                        }
                        .padding(.trailing, DesignTokens.Spacing.xxs)
                    }

                    // 멀티 오디오 토글
                    MLToolButton(
                        icon: manager.isMultiAudioMode
                            ? "speaker.wave.3.fill"
                            : "speaker.wave.1.fill",
                        isActive: manager.isMultiAudioMode,
                        help: manager.isMultiAudioMode
                            ? "단일 오디오 모드로 전환"
                            : "멀티 오디오 모드 (여러 채널 동시 청취)"
                    ) {
                        withAnimation(DesignTokens.Animation.snappy) {
                            manager.toggleMultiAudioMode()
                        }
                    }
                    .padding(.trailing, DesignTokens.Spacing.xxs)
                }

                MLToolButton(
                    icon: isGridLayout ? "rectangle.split.3x1" : "rectangle.grid.2x2",
                    isActive: isGridLayout,
                    help: isGridLayout ? "탭 모드로 전환" : "그리드 모드로 전환"
                ) {
                    withAnimation(DesignTokens.Animation.snappy) {
                        isGridLayout.toggle()
                        if isGridLayout {
                            // 그리드 모드: 모든 세션 포그라운드 (모두 화면 표시)
                            for s in manager.sessions { s.setBackgroundMode(false) }
                            let count = manager.sessions.count
                            for s in manager.sessions {
                                s.playerViewModel.applyMultiLiveConstraints(paneCount: count)
                            }
                            if !manager.isMultiAudioMode {
                                if let sel = manager.selectedSession {
                                    for s in manager.sessions { s.setMuted(s.id != sel.id) }
                                    manager.audioSessionId = sel.id
                                }
                            }
                        } else {
                            // 탭 모드: 선택된 세션만 포그라운드, 나머지 배경
                            for s in manager.sessions {
                                s.setBackgroundMode(s.id != manager.selectedSessionId)
                            }
                            manager.isMultiAudioMode = false
                            manager.audioEnabledSessionIds.removeAll()
                            if !manager.isMultiAudioMode {
                                manager.audioSessionId = nil
                                for s in manager.sessions { s.setMuted(s.id != manager.selectedSessionId) }
                            }
                        }
                    }
                    manager.saveState()
                    // [VLC 안정 컨테이너 패턴] 그리드↔탭 모드 전환 시
                    // SwiftUI 뷰 컨테이너가 변경되어 NSView가 재마운트됨.
                    // 레이아웃 완료 후 모든 VLC 엔진의 drawable을 재바인딩하여
                    // 화면 출력이 끊기지 않도록 보장한다.
                    Task { @MainActor in
                        // RunLoop 1프레임 대기 → SwiftUI 레이아웃 완료 직후 실행
                        await MainActor.run {}
                        try? await Task.sleep(nanoseconds: 16_000_000) // 1프레임 (16ms)
                        for s in manager.sessions {
                            s.playerViewModel.mediaPlayer?.refreshDrawable()
                        }
                    }
                }
                .padding(.trailing, DesignTokens.Spacing.xxs)
            }

            // ── 채널 추가 버튼 ──
            if manager.sessions.count < MultiLiveSessionManager.maxSessions {
                if !manager.sessions.isEmpty {
                    Rectangle()
                        .fill(.white.opacity(DesignTokens.Glass.borderOpacityLight))
                        .frame(width: 0.5, height: 16)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                }
                Button(action: onAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: isAddPanelOpen ? "xmark" : "plus")
                            .font(DesignTokens.Typography.micro)
                        Text(isAddPanelOpen ? "닫기" : "채널 추가")
                            .font(DesignTokens.Typography.captionSemibold)
                    }
                    .foregroundStyle(isAddPanelOpen ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(isAddPanelOpen
                                ? Color.white.opacity(0.1)
                                : DesignTokens.Colors.chzzkGreen.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(isAddPanelOpen
                                        ? Color.white.opacity(0.2)
                                        : DesignTokens.Colors.chzzkGreen.opacity(0.28),
                                            lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, DesignTokens.Spacing.sm)
                .animation(DesignTokens.Animation.fast, value: isAddPanelOpen)
            }
        }
        .frame(height: 52)
        .background(.thinMaterial)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacityLight))
                .frame(height: 0.5)
        }
    }
}

// MARK: - 툴바 소형 버튼
private struct MLToolButton: View {
    let icon: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(
                    isActive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary
                )
                .frame(width: 32, height: 32)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.25), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Tab Chip
struct MLTabChip: View {
    let session: MultiLiveSession
    let manager: MultiLiveSessionManager
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
            HStack(spacing: 8) {
                // ── 아바타 + 상태 배지 ──
                avatarView

                // ── 채널 정보 ──
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(tabTitle)
                            .font(DesignTokens.Typography.custom(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(
                                isSelected
                                    ? DesignTokens.Colors.textPrimary
                                    : DesignTokens.Colors.textSecondary
                            )
                            .lineLimit(1)
                            .frame(maxWidth: 86, alignment: .leading)

                        // 그리드 모드 오디오 아이콘
                        if isGridMode {
                            if manager.isMultiAudioMode {
                                Image(systemName: manager.isAudioEnabled(for: session) ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(manager.isAudioEnabled(for: session) ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                            } else if isAudioActive {
                                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            }
                        }
                    }
                    statusSubtext
                }

                // ── 리오더 화살표 (hover 시) ──
                if isHovered && manager.sessions.count > 1 {
                    HStack(spacing: 2) {
                        reorderButton(icon: "chevron.left",  action: onMoveLeft)
                        reorderButton(icon: "chevron.right", action: onMoveRight)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                // ── 닫기 버튼 ──
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(
                            isCloseHovered
                                ? DesignTokens.Colors.textPrimary
                                : DesignTokens.Colors.textTertiary
                        )
                        .frame(width: 17, height: 17)
                        .background {
                            if isCloseHovered {
                                Circle().fill(.regularMaterial)
                            } else if isHovered {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
            }
            .padding(.leading, DesignTokens.Spacing.sm)
            .padding(.trailing, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(chipBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isSelected
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.30)
                            : (isHovered ? .white.opacity(DesignTokens.Glass.borderOpacityLight) : Color.clear),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .shadow(color: isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.08) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DesignTokens.Animation.fast) { isHovered = h } }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().stroke(
                            isAudioActive && isGridMode
                                ? DesignTokens.Colors.chzzkGreen
                                : Color.clear,
                            lineWidth: 1.5
                        )
                    )
                Text(String(tabTitle.prefix(1)).uppercased())
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            }
            statusDot
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.loadState {
        case .playing:
            ZStack {
                // backgroundElevated: 탭바 bg와 동일 → 도넛 링처럼 보임
                Circle().fill(DesignTokens.Colors.backgroundElevated).frame(width: 9, height: 9)
                Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 6, height: 6)
            }
            .offset(x: 4, y: 4)
        case .loading:
            ZStack {
                Circle().fill(DesignTokens.Colors.backgroundElevated).frame(width: 9, height: 9)
                ProgressView().scaleEffect(0.34).tint(DesignTokens.Colors.chzzkGreen)
            }
            .offset(x: 4, y: 4)
        case .error:
            ZStack {
                Circle().fill(DesignTokens.Colors.backgroundElevated).frame(width: 9, height: 9)
                Circle().fill(DesignTokens.Colors.error).frame(width: 6, height: 6)
            }
            .offset(x: 4, y: 4)
        case .offline:
            ZStack {
                Circle().fill(DesignTokens.Colors.backgroundElevated).frame(width: 9, height: 9)
                Circle().fill(DesignTokens.Colors.textTertiary).frame(width: 6, height: 6)
            }
            .offset(x: 4, y: 4)
        default:
            EmptyView()
        }
    }

    // MARK: - Status subtext

    @ViewBuilder
    private var statusSubtext: some View {
        switch session.loadState {
        case .playing:
            if session.viewerCount > 0 {
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
            .font(DesignTokens.Typography.custom(size: 8.5, weight: .black))
            .kerning(0.4)
            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, 1.5)
            .background(Capsule().fill(DesignTokens.Colors.live))
    }

    // MARK: - Chip background — 사이드바 선택 스타일과 동일 토큰 사용

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            // Glass selected — material blur + green tint
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                DesignTokens.Colors.chzzkGreen.opacity(0.08)
            }
        } else if isHovered {
            Rectangle().fill(.ultraThinMaterial)
        } else {
            Color.clear
        }
    }

    // MARK: - Reorder button

    private func reorderButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 7.5, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context menu

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

// MARK: - Viewer Count Subview (리렌더링 최적화)
/// viewerCount 변경 시 이 서브뷰만 갱신되어 부모 뷰 전체 리렌더링 방지
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
