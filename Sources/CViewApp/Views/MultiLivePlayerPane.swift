// MARK: - MultiLivePlayerPane.swift
import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Player Pane (video-only — chat은 FollowingView에서 관리)
struct MLPlayerPane: View {
    let session: MultiLiveSession
    let appState: AppState
    /// 이 패인이 현재 활성(포그라운드) 상태인지 여부
    /// false이면 비디오 뷰만 유지하고 오버레이/채팅 등 무거운 UI 렌더링을 생략
    var isActive: Bool = true

    var body: some View {
        videoAndStateArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 비디오 + 상태 오버레이 영역
    @ViewBuilder
    private var videoAndStateArea: some View {
        ZStack {
            // [VLC 안정 컨테이너 패턴] isActive=false여도 PlayerVideoView를 유지
            if isActive {
                MLVideoArea(session: session, appState: appState, settingsStore: appState.settingsStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipped()
            }

            if isActive {
                loadStateOverlay
            }
        }
    }

    // MARK: - 로드 상태별 오버레이
    @ViewBuilder
    private var loadStateOverlay: some View {
        switch session.loadState {
        case .idle:
            Color.black.overlay(ProgressView().tint(.white))
        case .loading:
            mlLoadingOverlay
        case .playing:
            mlBufferingOverlay
        case .offline:
            MLSessionStatusOverlay(
                session: session,
                appState: appState,
                icon: "tv.slash",
                iconColor: DesignTokens.Colors.textOnOverlay.opacity(0.5),
                accentColor: DesignTokens.Colors.textOnOverlay,
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
    }

    // MARK: - 로딩 오버레이
    @ViewBuilder
    private var mlLoadingOverlay: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
            VStack(spacing: DesignTokens.Spacing.xs) {
                if !session.channelName.isEmpty {
                    Text(session.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.8))
                        .lineLimit(1)
                }
                Text("연결 중...")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - 버퍼링/재연결 오버레이
    @ViewBuilder
    private var mlBufferingOverlay: some View {
        if session.playerViewModel.streamPhase == .buffering
            || session.playerViewModel.streamPhase == .connecting
            || session.playerViewModel.streamPhase == .reconnecting {
            VStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(.white)
                Text(session.playerViewModel.streamPhase == .reconnecting
                     ? "재연결 중..." : "버퍼링 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.85))
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.black.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
            )
            .transition(.opacity.animation(DesignTokens.Animation.fast))
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

    /// GeometryReader 대체 — onGeometryChange로 컨테이너 크기만 경량 추적
    @State private var containerSize: CGSize = .zero

    var body: some View {
        let sessions = manager.sessions
        ZStack {
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
                        HStack(spacing: 1) {
                            ForEach(others) { session in
                                MLGridCell(
                                    session: session,
                                    manager: manager,
                                    appState: appState,
                                    focusedSessionId: $focusedSessionId,
                                    isFocused: false
                                )
                                .frame(height: min(containerSize.height * 0.22, 140))
                            }
                        }
                        .frame(height: min(containerSize.height * 0.22, 140))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if manager.gridLayoutMode == .focusLeft {
                // ── 포커스 레이아웃 (1+N) ──
                MLFocusLeftLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    containerSize: containerSize,
                    onAdd: onAdd
                )
                .transition(.opacity)
            } else if manager.gridLayoutMode == .custom {
                // ── 커스텀 레이아웃 (리사이즈 + 드래그 재정렬) ──
                MLCustomGridLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    containerSize: containerSize,
                    onAdd: onAdd
                )
                .transition(.opacity)
            } else {
                // ── 일반 프리셋 그리드 모드 (드래그 재정렬 지원) ──
                MLPresetGridLayout(
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    containerSize: containerSize,
                    onAdd: onAdd
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            containerSize = newSize
        }
        .transaction { $0.animation = nil }
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
        VStack(spacing: 0) {
            // 채널 헤더 (멀티채팅 스타일)
            HStack(spacing: 6) {
                // 오디오 활성 표시
                if isAudioActive && !session.isMuted {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }

                Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                if !session.liveTitle.isEmpty {
                    Text("·")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(session.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if session.viewerCount > 0 {
                    Text(session.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surfaceBase)

            Divider().opacity(DesignTokens.Opacity.divider)

            // 비디오 영역
            ZStack {
            // [크래시 방지] GeometryReader + 명시적 .frame(width:height:) 조합은
            // NSViewRepresentable의 AppKit 레이아웃 사이클과 충돌하여 constraint 재진입 크래시를 유발한다.
            // PlayerContainerView는 autoresizingMask [.width, .height]로 부모를 꽉 채우므로
            // .frame(maxWidth: .infinity, maxHeight: .infinity)만으로 충분하다.
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()
                // 오디오 활성 셀 테두리 강조
                .overlay {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            isAudioActive
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                                : Color.clear,
                            lineWidth: 1.5
                        )
                }

            // 버퍼링 인디케이터
            // [GPU 최적화] Material → Color.black.opacity — 일시적 스피너 배경에 blur 불필요
            if session.playerViewModel.streamPhase == .buffering
                || session.playerViewModel.streamPhase == .connecting {
                ProgressView()
                    .scaleEffect(0.9)
                    .tint(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 36, height: 36)
                    )
            }

            // 세션 상태 오버레이 (loading / offline / error)
            switch session.loadState {
            case .loading:
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.white)
                    // [GPU 최적화] Material → Color.black.opacity
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 36, height: 36)
                    )
            case .offline:
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "tv.slash")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.6))
                    Text("방송 종료")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.55))
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        Text("다시 확인")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.7))
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                // [GPU 최적화] Material → Color.black.opacity
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.black.opacity(0.7))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                        }
                )
            case .error:
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.warning.opacity(0.85))
                    Text("연결 오류")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.warning.opacity(0.75))
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        Text("재시도")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.warning.opacity(0.8))
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(Capsule().fill(DesignTokens.Colors.warning.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                // [GPU 최적화] Material → Color.black.opacity
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.black.opacity(0.7))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                        }
                )
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
            } // ZStack (비디오 영역)
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
        // [리사이즈 최적화] 그리드 셀에 전파되는 implicit 애니메이션 차단
        .transaction { $0.animation = nil }
        } // VStack
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showOverlay = false }
        }
    }
}


// MARK: - Session Info Bar (탭 모드용 — 채널명 + 라이브 제목 + 시청자 수)
/// 탭 모드에서 MLTabBar 아래에 표시되는 세션 정보 바.
/// 그리드 모드에서는 MLGridCell 헤더가 대신 사용되므로 표시하지 않음.
struct MLSessionInfoBar: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    var body: some View {
        HStack(spacing: 6) {
            // 오디오 활성 표시
            if isAudioActive && !session.isMuted {
                Image(systemName: "speaker.wave.2.fill")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }

            Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            if !session.liveTitle.isEmpty {
                Text("·")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(session.liveTitle)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if session.viewerCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    Text(session.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor.opacity(0.2))
                .frame(height: 0.5)
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

            // 썸네일 블러 배경
            if let url = session.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: blurRadius).opacity(0.16)
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .drawingGroup(opaque: true)
            }

            Color.black.opacity(overlayOpacity)

            // 은은한 방사형 강조
            RadialGradient(
                colors: [accentColor.opacity(0.03), Color.clear],
                center: .center, startRadius: 30, endRadius: 280
            )

            VStack(spacing: DesignTokens.Spacing.xl) {
                // 아이콘 영역
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.05))
                        .frame(width: 96, height: 96)
                    Circle()
                        .strokeBorder(accentColor.opacity(0.1), lineWidth: 1)
                        .frame(width: 96, height: 96)
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.custom(size: 32, weight: .light))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.pulse)
                }

                // 텍스트 영역
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text(title)
                        .font(DesignTokens.Typography.subhead)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    Text(subtitle)
                        .font(DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xxl)
                }

                // 액션 버튼
                HStack(spacing: DesignTokens.Spacing.md) {
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "arrow.clockwise")
                                .font(DesignTokens.Typography.captionSemibold)
                            Text(buttonLabel)
                                .font(DesignTokens.Typography.bodySemibold)
                        }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background {
                            Capsule()
                                .fill(accentColor.opacity(0.12))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)

                    // 세션 제거 버튼
                    if let onRemove {
                        Button {
                            onRemove()
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "xmark")
                                    .font(DesignTokens.Typography.captionSemibold)
                                Text("제거")
                                    .font(DesignTokens.Typography.bodySemibold)
                            }
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay.opacity(0.55))
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(0.07))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
