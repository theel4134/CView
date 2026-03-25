// MARK: - MultiLivePlayerPane.swift
import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Player Pane
struct MLPlayerPane: View {
    let session: MultiLiveSession
    let appState: AppState
    /// 이 패인이 현재 활성(포그라운드) 상태인지 여부
    /// false이면 비디오 뷰만 유지하고 오버레이/채팅 등 무거운 UI 렌더링을 생략
    var isActive: Bool = true
    /// 채팅 패널 너비 (드래그로 조절 가능, 앱 재시작 시 유지)
    @AppStorage("multiLiveChatPanelWidth") private var savedChatPaneWidth: Double = 300
    @State private var liveChatPaneWidth: Double = 300
    @State private var isDraggingChatResize = false
    @State private var showChatSettings = false

    var body: some View {
        // ZStack으로 래핑해 크기가 항상 부모 컨테이너 범위를 지키도록 함
        // [핵심] PlayerVideoView(NSView)를 loadState와 무관하게 항상 렌더링.
        // VLC는 play() 호출 시 drawable이 window hierarchy에 있어야 vout을 초기화한다.
        //
        // [VLC 안정 컨테이너 패턴]
        // isActive=false인 세션도 PlayerVideoView(NSView)를 뷰 계층에 유지하여
        // VLC drawable 연결이 끊기지 않도록 한다. 오버레이/채팅 등 무거운 SwiftUI 렌더링만 생략.
        ZStack {
            // ── 비디오 레이어: 항상 최하위에 렌더링 (loadState 무관, isActive 무관) ──
            // [크래시 방지] GeometryReader + 동적 .frame() 조합은 NSViewRepresentable 포함 시
            // layout 측정→렌더→layout 피드백 루프로 constraint 재진입 크래시를 유발한다.
            // HStack + .frame(maxWidth: .infinity) 패턴으로 대체하여 자연스러운 flex 레이아웃을 사용한다.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if isActive {
                        // 활성 패인: 전체 오버레이 포함 비디오 영역
                        MLVideoArea(session: session, appState: appState, settingsStore: appState.settingsStore)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        // 비활성 패인: PlayerVideoView(NSView)만 유지 → VLC drawable 연결 보존
                        // 오버레이/hover 등 SwiftUI 렌더링 비용 제거
                        PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .clipped()
                    }
                    if isActive && session.isChatVisible {
                        ChatResizeHandle(isDragging: $isDraggingChatResize, currentWidth: liveChatPaneWidth) { newWidth in
                            liveChatPaneWidth = min(max(newWidth, 200), geo.size.width * 0.6)
                        } onDragEnd: {
                            savedChatPaneWidth = liveChatPaneWidth
                        }
                        ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: { showChatSettings = true })
                            .frame(width: liveChatPaneWidth)
                    }
                }
            }

            // ── 상태 오버레이: 활성 패인에서만 비디오 위에 표시 ──
            // 비활성 패인에서는 불필요한 SwiftUI 렌더링 방지
            if isActive {
                switch session.loadState {
            case .idle:
                Color.black.overlay(ProgressView().tint(.white))
            case .loading:
                // 경량 로딩 오버레이 (GPU 절감)
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    if !session.channelName.isEmpty {
                        Text(session.channelName)
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text("연결 중...")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            case .playing:
                // [VLC 안정성 개선] 재생 중 재버퍼링/재연결 시 소형 스피너만 표시
                // 기존: 전체 화면 StreamLoadingOverlay → 비디오 완전 차단
                // 개선: 반투명 소형 인디케이터 → VLC 비디오 레이어가 보이면서 상태 표시
                // VLC 버퍼링 중에도 일부 프레임이 출력되므로 사용자 경험 크게 개선
                if session.playerViewModel.streamPhase == .buffering
                    || session.playerViewModel.streamPhase == .connecting
                    || session.playerViewModel.streamPhase == .reconnecting {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.1)
                            .tint(.white)
                        Text(session.playerViewModel.streamPhase == .reconnecting
                             ? "재연결 중..." : "버퍼링 중...")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        // [GPU 최적화] 버퍼링 중 일시적 오버레이에 Material blur 불필요
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.black.opacity(0.7))
                    )
                    .transition(.opacity.animation(DesignTokens.Animation.fast))
                }
            case .offline:
                MLSessionStatusOverlay(
                    session: session,
                    appState: appState,
                    icon: "tv.slash",
                    iconColor: .white.opacity(0.5),
                    accentColor: .white,
                    title: "방송이 종료되었습니다",
                    subtitle: session.channelName.isEmpty ? session.channelId : session.channelName,
                    buttonLabel: "다시 확인",
                    blurRadius: 30,
                    overlayOpacity: 0.65
                )
            case .error(let msg):
                MLSessionStatusOverlay(
                    session: session,
                    appState: appState,
                    icon: "wifi.exclamationmark",
                    iconColor: DesignTokens.Colors.warning,
                    accentColor: DesignTokens.Colors.warning,
                    title: "연결 오류",
                    subtitle: msg,
                    buttonLabel: "재시도",
                    blurRadius: 24,
                    overlayOpacity: 0.68
                )
            }
            } // end if isActive
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { liveChatPaneWidth = savedChatPaneWidth }
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsView(overrideChatVM: session.chatViewModel)
                .environment(appState)
        }
    }
}

// MARK: - Grid Layout
struct MLGridLayout: View {
    let manager: MultiLiveManager
    let appState: AppState
    var onAdd: (() -> Void)? = nil

    /// 포커스 모드: 더블클릭 시 해당 셀을 메인으로 확대
    @State private var focusedSessionId: UUID? = nil

    // ── 드래그 재정렬 상태 ──
    @State private var dragOverIndex: Int? = nil
    @State private var dragSourceIndex: Int? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        let sessions = manager.sessions
        GeometryReader { geo in
            if let focusedId = focusedSessionId,
               let focused = sessions.first(where: { $0.id == focusedId }) {
                // ── 포커스 모드: 메인 셀 + 하단 썸네일 스트립 ──
                let others = sessions.filter { $0.id != focusedId }
                VStack(spacing: 2) {
                    MLGridCell(
                        session: focused,
                        manager: manager,
                        appState: appState,
                        focusedSessionId: $focusedSessionId,
                        isFocused: true
                    )
                    if !others.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(others) { session in
                                MLGridCell(
                                    session: session,
                                    manager: manager,
                                    appState: appState,
                                    focusedSessionId: $focusedSessionId,
                                    isFocused: false
                                )
                                .frame(height: min(geo.size.height * 0.22, 140))
                            }
                        }
                        .frame(height: min(geo.size.height * 0.22, 140))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if manager.gridLayoutMode == .focusLeft {
                // ── 포커스 레이아웃 (1+N) ──
                MLFocusLeftLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    containerSize: geo.size,
                    onAdd: onAdd
                )
                .transition(.opacity)
            } else if manager.gridLayoutMode == .custom {
                // ── 커스텀 레이아웃 (리사이즈 + 드래그 재정렬) ──
                MLCustomGridLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    containerSize: geo.size,
                    onAdd: onAdd
                )
                .transition(.opacity)
            } else {
                // ── 일반 프리셋 그리드 모드 (드래그 재정렬 지원) ──
                MLPresetGridLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    onAdd: onAdd
                )
                .transition(.opacity)
            }
        }
        // [60fps 최적화] .animation() 제거 — 호출부에서 withAnimation 사용 중이므로
        // 여기서 propagation하면 viewerCount/bufferHealth 등 비관련 @Observable 변경에도
        // spring 애니메이션이 전체 그리드에 전파되어 불필요한 레이아웃 재계산 유발
    }
}

// NOTE: MLPresetGridLayout, MLDraggableGridCell, MLDragHandle, MLCustomGridLayout,
// MLResizeDivider → MultiLiveGridLayouts.swift로 이동


// MARK: - Grid Cell
struct MLGridCell: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let isFocused: Bool

    @State private var showOverlay = false
    @State private var hideTask: Task<Void, Never>?

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    var body: some View {
        ZStack {
            // [크래시 방지] GeometryReader + 명시적 .frame(width:height:) 조합은
            // NSViewRepresentable의 AppKit 레이아웃 사이클과 충돌하여 constraint 재진입 크래시를 유발한다.
            // PlayerContainerView는 autoresizingMask [.width, .height]로 부모를 꽉 채우므로
            // .frame(maxWidth: .infinity, maxHeight: .infinity)만으로 충분하다.
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()
                .overlay(alignment: .topLeading) {
                    // 채널명 + 라이브 제목 미니 배지 (오버레이 숨김 시 표시)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            // 오디오 활성 표시
                            if isAudioActive && !session.isMuted {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            }
                            Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .lineLimit(1)
                        }
                        if !session.liveTitle.isEmpty {
                            Text(session.liveTitle)
                                .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .opacity(showOverlay ? 0 : 1)
                    .animation(DesignTokens.Animation.micro, value: showOverlay)
                }
                // 오디오 활성 셀 테두리 강조
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            isAudioActive
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.65)
                                : Color.clear,
                            lineWidth: 2
                        )
                )

            // 버퍼링 인디케이터
            // [GPU 최적화] Material → Color.black.opacity — 일시적 스피너 배경에 blur 불필요
            if session.playerViewModel.streamPhase == .buffering
                || session.playerViewModel.streamPhase == .connecting {
                ProgressView().scaleEffect(0.9).tint(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 38, height: 38))
            }

            // 세션 상태 오버레이 (loading / offline / error)
            switch session.loadState {
            case .loading:
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.white)
                    // [GPU 최적화] Material → Color.black.opacity
                    .background(
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 36, height: 36)
                    )
            case .offline:
                VStack(spacing: 6) {
                    Image(systemName: "tv.slash")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("방송 종료")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        Text("다시 확인")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xs)
                // [GPU 최적화] Material → Color.black.opacity
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            case .error:
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.orange.opacity(0.85))
                    Text("연결 오류")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(.orange.opacity(0.75))
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        Text("재시도")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(.orange.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.orange.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xs)
                // [GPU 최적화] Material → Color.black.opacity
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            default:
                EmptyView()
            }

            // 컨트롤 오버레이 (hover 시)
            if showOverlay {
                MLGridControlOverlay(
                    session: session,
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: isFocused,
                    onHideCancel: { hideTask?.cancel() },
                    onScheduleHide: { scheduleHide() }
                )
                .transition(.opacity.animation(DesignTokens.Animation.fast))
            }
        }
        .contentShape(Rectangle())
        .onHover { h in
            hideTask?.cancel()
            if h {
                withAnimation { showOverlay = true }
                scheduleHide()
            } else {
                scheduleHide()
            }
        }
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    // 더블클릭 → 포커스 모드 진입/해제
                    withAnimation(DesignTokens.Animation.indicator) {
                        focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
                    }
                }
                .exclusively(before:
                    TapGesture(count: 1)
                        .onEnded {
                            hideTask?.cancel()
                            withAnimation { showOverlay.toggle() }
                            if showOverlay { scheduleHide() }
                        }
                )
        )
        .onDisappear { hideTask?.cancel(); hideTask = nil }
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showOverlay = false }
        }
    }
}


// NOTE: MLGridControlOverlay, MLLoadingState, MLVideoArea, MLControlOverlay,
// MLEmptyState, MLStatsOverlay, MLQualityPopover → MultiLiveOverlays.swift로 이동

// MARK: - Session Status Overlay (offline / error 공통)

/// MLPlayerPane의 `.offline`과 `.error` 상태에서 사용되는 공통 오버레이.
/// 배경 썸네일 블러 + 중앙 아이콘/텍스트 + 재시도 버튼으로 구성.
private struct MLSessionStatusOverlay: View {
    let session: MultiLiveSession
    let appState: AppState
    var onRemove: (() -> Void)? = nil
    let icon: String
    let iconColor: Color
    let accentColor: Color
    let title: String
    let subtitle: String
    let buttonLabel: String
    var blurRadius: CGFloat = 28
    var overlayOpacity: Double = 0.65

    var body: some View {
        ZStack {
            Color.black
            if let url = session.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: blurRadius).opacity(0.18)
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            Color.black.opacity(overlayOpacity)
            RadialGradient(
                colors: [accentColor.opacity(0.04), Color.clear],
                center: .center, startRadius: 20, endRadius: 260
            )
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.06))
                        .frame(width: 98, height: 98)
                    Circle()
                        .stroke(accentColor.opacity(0.12), lineWidth: 1)
                        .frame(width: 98, height: 98)
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.custom(size: 34, weight: .light))
                        .foregroundStyle(iconColor)
                }
                VStack(spacing: 8) {
                    Text(title)
                        .font(DesignTokens.Typography.subhead)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    Text(subtitle)
                        .font(DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                }
                HStack(spacing: DesignTokens.Spacing.md) {
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.clockwise")
                                .font(DesignTokens.Typography.captionSemibold)
                            Text(buttonLabel)
                                .font(DesignTokens.Typography.bodySemibold)
                        }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(
                            Capsule().fill(accentColor.opacity(0.15))
                                .overlay(Capsule().stroke(accentColor.opacity(0.25), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    // 세션 제거 버튼
                    if let onRemove {
                        Button {
                            onRemove()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                    .font(DesignTokens.Typography.captionSemibold)
                                Text("제거")
                                    .font(DesignTokens.Typography.bodySemibold)
                            }
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .background(
                                Capsule().fill(.white.opacity(0.08))
                                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
