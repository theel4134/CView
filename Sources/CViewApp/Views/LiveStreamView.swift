// MARK: - LiveStreamView.swift
// CViewApp - Integrated live stream view (player + chat)
// P6 리팩토링: PlayerControlsView, ChatPanelView 추출

import SwiftUI
import CViewCore
import CViewPlayer
import CViewChat
import CViewNetworking
import CViewMonitoring
import CViewPersistence

// MARK: - Live Stream View

struct LiveStreamView: View {

    let channelId: String
    /// 새 창(player-window)으로 열린 경우 true — stream 중지 없이 화면만 바인딩
    var isDetachedWindow: Bool = false

    @Environment(AppState.self) var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    @AppStorage("chatPanelWidth") private var savedChatWidth: Double = 300
    @State private var liveChatWidth: Double = 300
    @State private var isDraggingChatResize = false
    @State private var showOverlay = true
    @State var isLoadingStream = false
    @State var loadError: String?
    @State private var showDebugOverlay = false
    @State var isFavorite = false
    @State var watchStartedAt: Date?
    @State var liveStatusTask: Task<Void, Never>?
    @State var isStreamOffline = false
    @State var viewerCount: Int = 0
    @State var metricsFeedTask: Task<Void, Never>?
    @State private var showSettings = false
    /// 채팅 클램핑·오버레이 크기 계산용 — GeometryReader 대신 경량 onGeometryChange로 추적
    @State private var containerSize: CGSize = .zero

    /// AppState의 공유 PerformanceMonitor 사용 (MetricsForwarder와 동일 인스턴스)
    var performanceMonitor: PerformanceMonitor { appState.performanceMonitor }

    var playerVM: PlayerViewModel? { appState.playerViewModel }
    var chatVM: ChatViewModel? { appState.chatViewModel }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                // Player area + overlay chat
                ZStack {
                    playerArea
                        .overlay(alignment: .topTrailing) {
                            if showDebugOverlay {
                                PerformanceOverlayView(monitor: performanceMonitor)
                                    .padding(DesignTokens.Spacing.xs)
                            }
                        }

                    // 오버레이 모드: 플레이어 위에 반투명 채팅
                    if chatVM?.displayMode == .overlay {
                        ChatOverlayView(chatVM: chatVM, containerSize: containerSize)
                            .allowsHitTesting(true)
                            .transition(.blurReplace)
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .layoutPriority(0)

                // 사이드 모드: 드래그 핸들 + 채팅 패널
                if chatVM?.displayMode == .side {
                    ChatResizeHandle(isDragging: $isDraggingChatResize, currentWidth: liveChatWidth) { newWidth in
                        liveChatWidth = min(max(newWidth, 120), containerSize.width * 0.5)
                    } onDragEnd: {
                        savedChatWidth = liveChatWidth
                    }

                    ChatPanelView(chatVM: chatVM) {
                        router.presentSheet(.chatSettings)
                    }
                    .frame(width: liveChatWidth, alignment: .trailing)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                }
            }
            // GeometryReader 제거 — 리사이즈마다 전체 자식 뷰 트리 재렌더링 유발
            // onGeometryChange로 컨테이너 크기만 경량 추적 → 채팅 클램핑·오버레이 크기 계산
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                containerSize = newSize
            }

            // ── 설정 슬라이드 패널 (push 방식 — 멀티라이브와 동일) ──
            if showSettings {
                PlayerAdvancedSettingsView(
                    playerVM: playerVM,
                    settingsStore: appState.settingsStore,
                    isPresented: $showSettings
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(DesignTokens.Animation.contentTransition, value: showSettings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { streamToolbar }
        .id(channelId)
        .onAppear { liveChatWidth = savedChatWidth }
        .task(id: channelId) {
            await startStreamAndChat()
            await performanceMonitor.start()
            await loadFavoriteStatus()
            startLiveStatusPolling()
            startMetricsFeed()
        }
        .onDisappear {
            liveStatusTask?.cancel()
            liveStatusTask = nil
            metricsFeedTask?.cancel()
            metricsFeedTask = nil
            Task {
                await endWatchRecord()
                // 분리 창(새 창)이 이 채널을 재생 중이면 스트림·채팅 유지
                // → 사용자가 메인 앱에서 다른 탭으로 이동해도 새 창에서 계속 재생됨
                let hasDetachedWindow = appState.detachedChannelIds.contains(channelId)
                if !isDetachedWindow && !hasDetachedWindow {
                    await playerVM?.stopStream()
                    await chatVM?.disconnect()
                    // 메트릭 포워더 채널 비활성화
                    await appState.metricsForwarder?.deactivateCurrentChannel()
                }
                await performanceMonitor.stop()
            }
        }
        .onKeyPress(.escape) {
            if showSettings {
                withAnimation(DesignTokens.Animation.contentTransition) { showSettings = false }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(phases: .down) { press in
            handleShortcutKeyPress(press)
        }
    }

    // MARK: - Keyboard Shortcut Handling

    /// 설정에서 키 바인딩을 읽어 동적으로 매칭
    private func handleShortcutKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let shortcuts = appState.settingsStore.keyboard

        for action in ShortcutAction.allCases {
            let binding = shortcuts.binding(for: action)
            guard matchesBinding(press, binding) else { continue }

            switch action {
            case .togglePlay:
                Task { await playerVM?.togglePlayPause() }
            case .toggleMute:
                playerVM?.toggleMute()
            case .toggleFullscreen:
                playerVM?.toggleFullscreen()
            case .toggleChat:
                withAnimation(DesignTokens.Animation.normal) {
                    switch chatVM?.displayMode ?? .side {
                    case .side: chatVM?.displayMode = .overlay
                    case .overlay: chatVM?.displayMode = .hidden
                    case .hidden: chatVM?.displayMode = .side
                    }
                }
            case .togglePiP:
                togglePiP()
            case .screenshot:
                playerVM?.takeScreenshot()
            case .volumeUp:
                playerVM?.setVolume(min(1.0, (playerVM?.volume ?? 0.5) + 0.05))
            case .volumeDown:
                playerVM?.setVolume(max(0.0, (playerVM?.volume ?? 0.5) - 0.05))
            }
            return .handled
        }
        return .ignored
    }

    /// KeyPress가 KeyBinding과 일치하는지 확인
    private func matchesBinding(_ press: KeyPress, _ binding: KeyBinding) -> Bool {
        // 수식키 확인
        let mods = binding.modifiers
        if mods.contains(.command)  != press.modifiers.contains(.command)  { return false }
        if mods.contains(.shift)    != press.modifiers.contains(.shift)    { return false }
        if mods.contains(.option)   != press.modifiers.contains(.option)   { return false }
        if mods.contains(.control)  != press.modifiers.contains(.control)  { return false }

        // 키 확인
        switch binding.key {
        case "space":      return press.key == .space
        case "upArrow":    return press.key == .upArrow
        case "downArrow":  return press.key == .downArrow
        case "leftArrow":  return press.key == .leftArrow
        case "rightArrow": return press.key == .rightArrow
        case "return":     return press.key == .return
        case "escape":     return press.key == .escape
        case "tab":        return press.key == .tab
        case "delete":     return press.key == .delete
        default:
            return press.characters.lowercased() == binding.key.lowercased()
        }
    }

    // MARK: - Player Area

    private var playerArea: some View {
        ZStack {
            PlayerVideoView(videoView: playerVM?.currentVideoView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                // isAudioOnly 시 AVPlayerLayer.isHidden / VLC videoTrack으로 처리.
                // SwiftUI .opacity()는 동적 값이면 오프스크린 compositing 버퍼를 강제 생성 → GPU 낭비.

            // Audio-only overlay
            if playerVM?.isAudioOnly == true {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "waveform")
                        .font(DesignTokens.Typography.custom(size: 48))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        // .variableColor.iterative는 매 프레임 GPU 드로우 → 오디오 절약 모드와 역행.
                        // .pulse는 간헐적 불투명도 변화만 발생하므로 GPU 부담 최소화.
                        .symbolEffect(.pulse)
                    Text("오디오 전용 모드")
                        .font(DesignTokens.Typography.custom(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("영상 비활성화로 데이터 절약 중")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.Colors.background)
            }

            // Player overlay (extracted to PlayerControlsView)
            if showOverlay {
                PlayerOverlayView(
                    playerVM: playerVM,
                    onTogglePiP: togglePiP,
                    onOpenNewWindow: { openWindow(id: "player-window", value: channelId) },
                    onScreenshot: { playerVM?.takeScreenshot() },
                    onToggleRecording: { Task { await playerVM?.toggleRecording() } },
                    settingsStore: appState.settingsStore,
                    onToggleSettings: {
                        withAnimation(DesignTokens.Animation.snappy) {
                            showSettings.toggle()
                        }
                    },
                    isSettingsOpen: showSettings
                )
            }

            // Stream alert overlay (후원/구독/공지 알림 토스트)
            // [MVVM] 애니메이션을 View 레이어에서 .animation(value:)로 구동
            // ViewModel은 순수 상태 변이만 수행 → 관심사 분리 + 테스트 용이
            if let chatVM {
                StreamAlertOverlayView(
                    alerts: chatVM.streamAlerts,
                    onDismiss: { chatVM.dismissStreamAlert($0) }
                )
                .allowsHitTesting(!showOverlay)
                .animation(DesignTokens.Animation.contentTransition, value: chatVM.streamAlerts)
            }

            // Buffering / Connecting / Reconnecting overlay
            if isLoadingStream || playerVM?.streamPhase == .buffering
                || playerVM?.streamPhase == .connecting
                || playerVM?.streamPhase == .reconnecting {
                StreamLoadingOverlay(
                    channelId: channelId,
                    channelName: playerVM?.channelName ?? "",
                    liveTitle: playerVM?.liveTitle ?? "",
                    thumbnailURL: playerVM?.thumbnailURL,
                    streamPhase: playerVM?.streamPhase,
                    bufferLevel: playerVM?.bufferHealth.map { Double($0.currentLevel) },
                    isApiLoading: isLoadingStream
                )
                .transition(.opacity.animation(DesignTokens.Animation.normal))
            }

            // Load error
            if let loadErr = loadError {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(DesignTokens.Typography.custom(size: 36))
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Text(loadErr)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .multilineTextAlignment(.center)
                    Button("다시 시도") {
                        Task { await startStreamAndChat() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Colors.chzzkGreen)
                }
            }

            // Stream error
            if case .error(let msg) = playerVM?.streamPhase {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(DesignTokens.Typography.custom(size: 36))
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Text(msg)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .multilineTextAlignment(.center)
                }
            }

            // Stream offline
            if isStreamOffline || playerVM?.streamPhase == .streamEnded {
                ZStack {
                    Rectangle().fill(DesignTokens.Colors.background)
                    RadialGradient(
                        colors: [DesignTokens.Colors.textPrimary.opacity(0.03), Color.clear],
                        center: .center, startRadius: 20, endRadius: 260
                    )
                    VStack(spacing: 22) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.textPrimary.opacity(0.03))
                                .frame(width: 96, height: 96)
                            Circle()
                                .strokeBorder(DesignTokens.Colors.textPrimary.opacity(0.08), lineWidth: 0.5)
                                .frame(width: 96, height: 96)
                            Image(systemName: "tv.slash")
                                .font(DesignTokens.Typography.custom(size: 36, weight: .light))
                                .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.45))
                        }
                        VStack(spacing: 8) {
                            Text("방송이 종료되었습니다")
                                .font(DesignTokens.Typography.subhead)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Text("스트리머가 방송을 종료했습니다.")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.5))
                        }
                        Button {
                            Task { await startStreamAndChat() }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.clockwise")
                                    .font(DesignTokens.Typography.captionSemibold)
                                Text("다시 확인")
                                    .font(DesignTokens.Typography.bodySemibold)
                            }
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(DesignTokens.Colors.textPrimary.opacity(0.12), lineWidth: 0.5)
                                    }
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            if let vm = playerVM {
                PlayerEngineBadge(engineType: vm.currentEngineType)
                    .padding(DesignTokens.Spacing.md)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) { showOverlay = hovering }
            if hovering { playerVM?.showControlsTemporarily() }
        }
        .onTapGesture {
            withAnimation(DesignTokens.Animation.fast) { showOverlay.toggle() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var streamToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                openWindow(id: "player-window", value: channelId)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
            }
            .help("새 창에서 재생")

            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }

            Button {
                withAnimation(DesignTokens.Animation.normal) {
                    // 채팅 모드 순환: side → overlay → hidden → side
                    switch chatVM?.displayMode ?? .side {
                    case .side: chatVM?.displayMode = .overlay
                    case .overlay: chatVM?.displayMode = .hidden
                    case .hidden: chatVM?.displayMode = .side
                    }
                }
            } label: {
                Image(systemName: chatVM?.displayMode == .hidden ? "bubble.left.and.bubble.right" : "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(chatVM?.displayMode == .hidden ? .secondary : Color.accentColor)
            }

            Button {
                showDebugOverlay.toggle()
            } label: {
                Image(systemName: showDebugOverlay ? "gauge.open.with.lines.needle.33percent.badge.arrow.down" : "gauge.open.with.lines.needle.33percent")
                    .foregroundStyle(showDebugOverlay ? .green : .secondary)
            }

            if viewerCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(formattedViewerCount)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text(playerVM?.formattedUptime ?? "00:00")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

}

