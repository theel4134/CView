// MARK: - MultiLivePlayerPane.swift
import SwiftUI
import CViewCore
import CViewPlayer
import UniformTypeIdentifiers

// MARK: - Player Pane (video-only — chat은 FollowingView에서 관리)
struct MLPlayerPane: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
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
            // [VLC/AVPlayer 안정 컨테이너 패턴] MLVideoArea를 항상 유지하여
            // isActive 전환 시 PlayerVideoView(NSViewRepresentable) 재마운트로 인한
            // AVPlayerLayer 재바인딩/프레임 드롭을 방지. 컨트롤 오버레이(showControls/Stats)는
            // MLVideoArea 내부에서 자체 제어되므로 비활성 상태에서도 렌더 비용이 크지 않다.
            MLVideoArea(session: session, appState: appState, settingsStore: appState.settingsStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(isActive)

            if isActive {
                loadStateOverlay
            }

            // [Donation Alerts 2026-04-18] 싱글라이브와 동일한 후원/구독/공지 알림 오버레이.
            // MultiLiveSession.chatViewModel.streamAlerts 가 ChatViewModel+Processing 에서
            // 채팅 이벤트(.donations / .subscription / .notice) 수신 시 자동 큐잉됨.
            // 비활성 패인에서는 토스트가 떠도 사용자가 못 보므로 isActive 일 때만 렌더.
            if isActive {
                StreamAlertOverlayView(
                    alerts: session.chatViewModel.streamAlerts,
                    onDismiss: { session.chatViewModel.dismissStreamAlert($0) }
                )
                .allowsHitTesting(true)
                .animation(DesignTokens.Animation.contentTransition,
                           value: session.chatViewModel.streamAlerts)
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
            MLStreamEndedOverlay(
                session: session,
                appState: appState,
                manager: manager,
                compact: false
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(DesignTokens.Animation.normal, value: session.loadState)
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
    // [Buffering Unify 2026-04-18] 싱글라이브의 StreamLoadingOverlay 와 동일한 디자인으로
    // 통일하여 멀티라이브에서도 풀 프레임 블러 + 회전 호 스피너 + 단계별 텍스트를 표시한다.
    @ViewBuilder
    private var mlBufferingOverlay: some View {
        if session.playerViewModel.streamPhase == .buffering
            || session.playerViewModel.streamPhase == .connecting
            || session.playerViewModel.streamPhase == .reconnecting {
            StreamLoadingOverlay(
                channelId: session.channelId,
                channelName: session.channelName,
                liveTitle: session.liveTitle,
                thumbnailURL: session.thumbnailURL,
                streamPhase: session.playerViewModel.streamPhase,
                bufferLevel: session.playerViewModel.bufferHealth.map { Double($0.currentLevel) },
                isApiLoading: false
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
                VStack(spacing: 6) {
                    MLGridCell(
                        session: focused,
                        manager: manager,
                        appState: appState,
                        focusedSessionId: $focusedSessionId,
                        isFocused: true
                    )
                    if !others.isEmpty {
                        HStack(spacing: 6) {
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
        // [Modern Curves 2026-04-21] 라운드 그리드 셀 외곽 패딩 — 창 자체 역사다가에 잘리지 않도록
        .padding(6)
        // [Resize 최적화] 정수 픽셀 스냅 + 변경 가드 → 리사이즈 시 N개 셀 frame 재계산 폭주 차단
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(
                width: proxy.size.width.rounded(.down),
                height: proxy.size.height.rounded(.down)
            )
        } action: { newSize in
            guard newSize != containerSize else { return }
            containerSize = newSize
            // [Quality 2026-04-24] 그리드 컨테이너 크기 변화를 BW 코디네이터에 전달.
            //   manager 내부에서 200ms 디바운스 후 paneSize 갱신 → ABR 캡 재산출.
            manager.reportStageSize(newSize)
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
    @State private var isHeaderHovered = false
    @State private var isDropTargeted = false

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // 채널 헤더 (멀티채팅 스타일)
            HStack(spacing: 6) {
                // 드래그 핸들 (hover 시 표시)
                Image(systemName: "line.3.horizontal")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(isHeaderHovered ? 0.9 : 0.0))
                    .frame(width: 10)
                    .help("드래그하여 순서 변경")

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
                        Image(systemName: "eye.fill")
                            .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                        Text(session.formattedViewerCount)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .help("현재 시청자 수")
                }

                if session.accumulateCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                        Text(session.formattedAccumulateCount)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.85))
                    .help("누적 시청자 수")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // [Modern Curves 2026-04-21] 헤더 상단만 라운드 (하단은 비디오와 붙음) + 이중 레이어 배경
            .background(
                DesignTokens.Colors.surfaceBase
                    .clipShape(
                        .rect(
                            topLeadingRadius: DesignTokens.Radius.lg,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: DesignTokens.Radius.lg,
                            style: .continuous
                        )
                    )
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(DesignTokens.Animation.fast) { isHeaderHovered = hovering }
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDrag {
                NSCursor.closedHand.set()
                return NSItemProvider(object: session.id.uuidString as NSString)
            }

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

            // 버퍼링 인디케이터
            // [GPU 최적화] Material → Color.black.opacity — 일시적 스피너 배경에 blur 불필요
            if session.playerViewModel.streamPhase == .buffering
                || session.playerViewModel.streamPhase == .connecting {
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.white)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Glass.thin, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 0.5)
                    }
            }

            // 세션 상태 오버레이 (loading / offline / error)
            switch session.loadState {
            case .loading:
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Glass.thin, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 0.5)
                    }
            case .offline:
                MLStreamEndedOverlay(
                    session: session,
                    appState: appState,
                    manager: manager,
                    compact: true
                )
                .transition(.opacity)
                .animation(DesignTokens.Animation.normal, value: session.loadState)
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
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(DesignTokens.Glass.thin)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
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
                withAnimation(DesignTokens.Animation.fast) { showOverlay = true }
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
                            withAnimation(DesignTokens.Animation.fast) { showOverlay.toggle() }
                            if showOverlay { scheduleHide() }
                        }
                )
        )
        .onDisappear { hideTask?.cancel(); hideTask = nil }
        // [리사이즈 최적화] 그리드 셀에 전파되는 implicit 애니메이션 차단
        .transaction { $0.animation = nil }
        } // VStack
        // [Modern Curves 2026-04-21] 곡선 디자인 — 16pt continuous + 오디오 활성 곡선 테두리
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay {
            // 오디오 활성 셀 곡선 테두리 (셀 전체 outline)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    isAudioActive
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.55)
                        : DesignTokens.Glass.borderColor.opacity(0.5),
                    lineWidth: isAudioActive ? 1.5 : 0.5
                )
                .allowsHitTesting(false)
                .animation(DesignTokens.Animation.fast, value: isAudioActive)
        }
        .overlay {
            // 드롭 타겟 하이라이트
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // [Depth] 오디오 활성 시 부드러운 그린 글로우
        // [GPU 정밀 튜닝 2026-04-23] LowPower 모드에서는 Gaussian shadow radius 를 절반 이하로 축소.
        // 셀 크기(보통 1080p) × radius 10 = 매 리사이즈/리레이아웃마다 큰 영역 blur 재계산 → 절감.
        .shadow(
            color: isAudioActive ? DesignTokens.Colors.chzzkGreen.opacity(0.22) : .clear,
            radius: isAudioActive
                ? (ProcessInfo.processInfo.isLowPowerModeEnabled ? 4 : 10)
                : 0,
            x: 0, y: 0
        )
        .onDrop(
            of: [UTType.text],
            delegate: MLGridCellDropDelegate(
                targetSessionId: session.id,
                manager: manager,
                isTargeted: $isDropTargeted
            )
        )
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(DesignTokens.Animation.fast) { showOverlay = false }
        }
    }
}


// MARK: - MLGridCellDropDelegate
/// 그리드 셀 간 드래그 재정렬용 Drop Delegate.
/// 헤더에서 시작된 드래그 UUID 문자열을 수신해 `manager.sessions`를 재배열한다.
private struct MLGridCellDropDelegate: DropDelegate {
    let targetSessionId: UUID
    let manager: MultiLiveManager
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        withAnimation(DesignTokens.Animation.fast) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        withAnimation(DesignTokens.Animation.fast) { isTargeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(DesignTokens.Animation.fast) { isTargeted = false }

        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        let targetId = targetSessionId
        let mgr = manager

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? NSString,
                  let sourceId = UUID(uuidString: raw as String),
                  sourceId != targetId else { return }
            Task { @MainActor in
                guard let fromIndex = mgr.sessions.firstIndex(where: { $0.id == sourceId }),
                      let toIndex = mgr.sessions.firstIndex(where: { $0.id == targetId })
                else { return }
                withAnimation(DesignTokens.Animation.fast) {
                    mgr.moveSession(
                        from: IndexSet(integer: fromIndex),
                        to: toIndex > fromIndex ? toIndex + 1 : toIndex
                    )
                }
            }
        }
        return true
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
                    Image(systemName: "eye.fill")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    Text(session.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .help("현재 시청자 수")
            }

            if session.accumulateCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    Text(session.formattedAccumulateCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.85))
                .help("누적 시청자 수")
            }
        }
        // [Modern Curves 2026-04-21] 세션 정보 바 — 부유 카드 스타일 (inner pill + outer margin)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColor.opacity(0.45), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xxs)
    }
}


// NOTE: MLGridControlOverlay, MLLoadingState, MLVideoArea, MLControlOverlay,
// MLEmptyState, MLStatsOverlay, MLQualityPopover → MultiLiveOverlays.swift로 이동

// MARK: - Stream Ended Overlay (방송 종료 애니메이션)

/// 멀티라이브에서 방송 종료 시 표시되는 시각적 오버레이.
/// 스캔라인 + 동심원 펄스 + 페이드인 애니메이션으로 종료 상태를 명확히 구별.
/// compact=true(그리드), compact=false(탭) 두 가지 모드 지원.
private struct MLStreamEndedOverlay: View {
    let session: MultiLiveSession
    let appState: AppState
    let manager: MultiLiveManager
    var compact: Bool = false

    @State private var ringPulse = false
    @State private var contentVisible = false
    @State private var containerHeight: CGFloat = 0
    @State private var scanOffset: CGFloat = -60

    var body: some View {
        ZStack {
            // ── 배경 레이어 ──
            Color.black

            // 풀모드: 썸네일 desaturated 블러 배경
            // [GPU 최적화] blur radius 30 → 18 (커널 절반 축소, 시각 차이 미미)
            if !compact, let url = session.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 18)
                        .saturation(0)
                        .opacity(0.15)
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .drawingGroup(opaque: true)
            }

            Color.black.opacity(compact ? 0.7 : 0.55)

            // 비네트 (주변부 어둡게)
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.5)],
                center: .center,
                startRadius: compact ? 40 : 100,
                endRadius: compact ? 200 : 400
            )

            // ── 스캔라인 효과 (CRT 신호 끊김 연출) ──
            // [GPU 최적화] compact(그리드) 모드에서는 스캔라인 비활성화 — 4세션 종료 시
            // 무한 LinearGradient 애니메이션 4× 누적 방지 (시각적 의미 풀모드 한정)
            if !compact {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.03), location: 0.3),
                        .init(color: .white.opacity(0.06), location: 0.5),
                        .init(color: .white.opacity(0.03), location: 0.7),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: scanOffset)
                .allowsHitTesting(false)
            }

            // ── 콘텐츠 ──
            VStack(spacing: compact ? DesignTokens.Spacing.md : DesignTokens.Spacing.xl) {
                // 아이콘 + 동심원 펄스
                iconWithRings

                // 텍스트
                VStack(spacing: compact ? 2 : DesignTokens.Spacing.sm) {
                    Text(compact ? "방송 종료" : "방송이 종료되었습니다")
                        .font(compact ? DesignTokens.Typography.footnoteMedium : DesignTokens.Typography.subhead)
                        .foregroundStyle(DesignTokens.Colors.textOnDarkMediaMuted)
                    Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                        .font(compact ? DesignTokens.Typography.micro : DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                        .lineLimit(1)
                }

                // 버튼
                if compact { compactButtons } else { fullButtons }
            }
            .opacity(contentVisible ? 1 : 0)
            .scaleEffect(contentVisible ? 1 : 0.95)
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            guard containerHeight == 0 else { return }
            containerHeight = h
            // [GPU 최적화] compact 모드는 스캔라인 자체를 그리지 않으므로 애니메이션 스킵.
            // [Phase A] motionSafe 래핑 — Reduce Motion ON 시 정적 처리.
            guard !compact,
                  let anim = DesignTokens.Animation.motionSafe(
                    .linear(duration: 5).repeatForever(autoreverses: false)
                  ) else { return }
            withAnimation(anim) {
                scanOffset = h + 60
            }
        }
        .onAppear {
            // [GPU 정밀 튜닝 2026-04-23] compact 모드는 ringAnim=nil 이므로
            // ringPulse 토글이 불필요한 SwiftUI state 변경만 유발 — 풀모드에서만 트리거.
            if !compact { ringPulse = true }
            withAnimation(.easeOut(duration: 0.5)) { contentVisible = true }
        }
    }

    // MARK: - 아이콘 + 펄스 링
    @ViewBuilder
    private var iconWithRings: some View {
        let size: CGFloat = compact ? 48 : 80
        // [GPU 최적화] 동심원 펄스 개수: 풀모드 3 / compact 2 — compact 시 33% 부하 감소
        // [Phase A] Reduce Motion ON 시 무한 애니메이션 정지 (motionSafe 래핑)
        // [GPU 정밀 튜닝 2026-04-23] compact 모드(그리드 4셀 동시) 에서는 무한 펄스 자체를 비활성.
        // 풀모드(단일 표시) 한정으로만 펄스 — 4세션 동시 종료 시 GPU 누적 차단.
        let ringCount = compact ? 2 : 3
        let ringAnim: Animation? = compact
            ? nil
            : DesignTokens.Animation.motionSafe(
                .easeOut(duration: 3).repeatForever(autoreverses: false)
              )
        ZStack {
            // 동심원 펄스 (시간차)
            ForEach(0..<ringCount, id: \.self) { i in
                Circle()
                    .strokeBorder(
                        ringPulse ? Color.clear : DesignTokens.Colors.borderOnDarkMedia,
                        lineWidth: compact ? 0.5 : 1
                    )
                    .frame(
                        width: ringPulse ? size * 2.5 : size,
                        height: ringPulse ? size * 2.5 : size
                    )
                    .animation(
                        ringAnim?.delay(Double(i) * 1.0),
                        value: ringPulse
                    )
            }

            // 아이콘 원형 배경
            Circle()
                .fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.36))
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: compact ? 0.5 : 1)
                .frame(width: size, height: size)

            Image(systemName: "tv.slash")
                .font(DesignTokens.Typography.custom(size: compact ? 18 : 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                .symbolEffect(.breathe, options: .repeat(.continuous))
        }
    }

    // MARK: - 컴팩트 버튼 (그리드)
    @ViewBuilder
    private var compactButtons: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                guard let api = appState.apiClient else { return }
                Task { await session.retry(using: api, appState: appState) }
            } label: {
                Text("다시 확인")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textOnDarkMediaMuted)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(Capsule().fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.7)))
            }
            .buttonStyle(.plain)

            Button {
                Task { await manager.removeSession(session) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .semibold))
                    Text("종료")
                        .font(DesignTokens.Typography.micro)
                }
                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(Capsule().fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.5)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 풀 버튼 (탭)
    @ViewBuilder
    private var fullButtons: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                guard let api = appState.apiClient else { return }
                Task { await session.retry(using: api, appState: appState) }
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionSemibold)
                    Text("다시 확인")
                        .font(DesignTokens.Typography.bodySemibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background {
                    Capsule()
                        .fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.85))
                        .overlay { Capsule().strokeBorder(DesignTokens.Colors.borderOnDarkMediaStrong, lineWidth: 1) }
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await manager.removeSession(session) }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.captionSemibold)
                    Text("제거")
                        .font(DesignTokens.Typography.bodySemibold)
                }
                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background {
                    Capsule()
                        .fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.5))
                        .overlay { Capsule().strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 1) }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Session Status Overlay (error 상태용)

/// MLPlayerPane의 `.error` 상태에서 사용되는 오버레이.
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
                        .symbolEffect(.breathe, options: .repeat(.continuous))
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
                                    .fill(DesignTokens.Colors.controlOnDarkMedia.opacity(0.5))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 1)
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
