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

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    @AppStorage("chatPanelWidth") private var savedChatWidth: Double = 340
    @State private var liveChatWidth: Double = 340
    @State private var isDraggingChatResize = false
    @State private var showOverlay = true
    @State private var isLoadingStream = false
    @State private var loadError: String?
    @State private var showDebugOverlay = false
    @State private var isFavorite = false
    @State private var watchStartedAt: Date?
    @State private var liveStatusTask: Task<Void, Never>?
    @State private var isStreamOffline = false
    @State private var viewerCount: Int = 0
    @State private var metricsFeedTask: Task<Void, Never>?
    @State private var showSettings = false

    /// AppState의 공유 PerformanceMonitor 사용 (MetricsForwarder와 동일 인스턴스)
    private var performanceMonitor: PerformanceMonitor { appState.performanceMonitor }

    private var playerVM: PlayerViewModel? { appState.playerViewModel }
    private var chatVM: ChatViewModel? { appState.chatViewModel }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
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
                            ChatOverlayView(chatVM: chatVM, containerSize: geo.size)
                                .allowsHitTesting(true)
                                .transition(.opacity)
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                    // 사이드 모드: 드래그 핸들 + 채팅 패널
                    if chatVM?.displayMode == .side {
                        ChatResizeHandle(isDragging: $isDraggingChatResize, currentWidth: liveChatWidth) { newWidth in
                            liveChatWidth = min(max(newWidth, 250), geo.size.width * 0.5)
                        } onDragEnd: {
                            savedChatWidth = liveChatWidth
                        }

                        ChatPanelView(chatVM: chatVM) {
                            router.presentSheet(.chatSettings)
                        }
                        .frame(width: liveChatWidth, alignment: .trailing)
                    }
                }
            }
            .clipped()

            // ── 설정 슬라이드 패널 (push 방식 — 멀티라이브와 동일) ──
            if showSettings {
                PlayerAdvancedSettingsView(
                    playerVM: playerVM,
                    settingsStore: appState.settingsStore,
                    isPresented: $showSettings
                )
                .transition(.move(edge: .trailing))
                .animation(DesignTokens.Animation.contentTransition, value: showSettings)
            }
        }
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
            if let chatVM, !chatVM.streamAlerts.isEmpty {
                StreamAlertOverlayView(
                    alerts: chatVM.streamAlerts,
                    onDismiss: { chatVM.dismissStreamAlert($0) }
                )
                .allowsHitTesting(!showOverlay)
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
                    Rectangle().fill(Color(hex: 0x1C1C1E))
                    RadialGradient(
                        colors: [Color.white.opacity(0.03), Color.clear],
                        center: .center, startRadius: 20, endRadius: 260
                    )
                    VStack(spacing: 22) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 100, height: 100)
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                .frame(width: 100, height: 100)
                            Image(systemName: "tv.slash")
                                .font(DesignTokens.Typography.custom(size: 38, weight: .light))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        VStack(spacing: 8) {
                            Text("방송이 종료되었습니다")
                                .font(DesignTokens.Typography.subhead)
                                .foregroundStyle(.white)
                            Text("스트리머가 방송을 종료했습니다.")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(.white.opacity(0.6))
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
                            .foregroundStyle(.white)
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .background(
                                Capsule().fill(Color(hex: 0x2C2C2E))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            )
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

    // MARK: - PiP

    private func togglePiP() {
        guard let engine = playerVM?.mediaPlayer else { return }
        // PiP 컨트롤러에 콜백 주입
        PiPController.shared.onToggleMute = { playerVM?.toggleMute() }
        PiPController.shared.isMuted = playerVM?.isMuted ?? false
        PiPController.shared.onReturnToMain = nil  // bringToFront는 PiPController 내부에서 처리
        PiPController.shared.togglePiP(vlcEngine: engine, avEngine: nil, title: playerVM?.channelName ?? "PiP")
    }

    // MARK: - Stream + Chat Start

    private func startStreamAndChat() async {
        guard !isLoadingStream else { return }

        // --- 새 창(분리 창) 케이스: 동일 채널이 이미 재생 중이면 엔진 재생성 없이 화면만 바인딩 ---
        // VLCVideoView.updateNSView가 makeNSView 시 이 창의 native view를 drawable로 자동 설정함
        if isDetachedWindow,
           let vm = playerVM,
           vm.streamPhase == .playing || vm.streamPhase == .buffering,
           vm.currentChannelId == channelId {
            isLoadingStream = false
            loadError = nil
            viewerCount = vm.viewerCount
            isFavorite = (try? await appState.dataStore?.isFavorite(channelId: channelId)) ?? false
            startLiveStatusPolling()
            startMetricsFeed()
            return
        }
        isLoadingStream = true
        loadError = nil

        do {
            guard let apiClient = appState.apiClient else {
                loadError = "API 클라이언트가 초기화되지 않았습니다."
                isLoadingStream = false
                return
            }

            // ─── P2: 프리페치 캐시 확인 — 호버 시 미리 가져온 결과 사용 ───
            let liveInfo: LiveInfo
            let streamURL: URL
            let channelName: String
            let liveTitle: String
            var prefetchedManifest: MasterPlaylist? = nil

            if let prefetched = await appState.hlsPrefetchService?.consumePrefetchedStream(channelId: channelId) {
                // 캐시 히트: API 호출 생략 (~400ms 절약)
                liveInfo = prefetched.liveInfo
                streamURL = prefetched.streamURL
                channelName = prefetched.channelName
                liveTitle = prefetched.liveTitle
                // [Opt: Single VLC] 프리페치 매니페스트도 전달 → variant 해석 네트워크 절약
                prefetchedManifest = prefetched.masterPlaylist
            } else {
                // 캐시 미스: 기존 경로로 liveDetail API 호출
                let info = try await apiClient.liveDetail(channelId: channelId)

                guard let playbackJSON = info.livePlaybackJSON,
                      let jsonData = playbackJSON.data(using: .utf8) else {
                    loadError = "재생 정보를 찾을 수 없습니다."
                    isLoadingStream = false
                    return
                }

                let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
                let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                    ?? playback.media.first

                guard let mediaPath = media?.path,
                      let url = URL(string: mediaPath) else {
                    loadError = "HLS 스트림 URL을 찾을 수 없습니다."
                    isLoadingStream = false
                    return
                }

                liveInfo = info
                streamURL = url
                channelName = info.channel?.channelName ?? ""
                liveTitle = info.liveTitle
            }

            let ps = appState.settingsStore.player

            // ─── 영상 즉시 시작 + 로딩 오버레이 즉시 해제 ───
            let _prefetchedManifest = prefetchedManifest
            let _channelId = channelId
            let _apiClient = appState.apiClient
            Task { @MainActor in
                // 재생 직전 최신 설정의 엔진 타입 반영 (앱 실행 중 설정 변경 대응)
                playerVM?.preferredEngineType = ps.preferredEngine
                // 방송 종료 확인 콜백 설정 — 재연결 시 API로 라이브 상태 확인
                playerVM?.onCheckStreamEnded = { [weak _apiClient] in
                    guard let api = _apiClient else { return false }
                    do {
                        let status = try await api.liveStatus(channelId: _channelId)
                        return status.status == .close
                    } catch {
                        return false
                    }
                }
                isStreamOffline = false
                await playerVM?.startStream(
                    channelId: channelId,
                    streamUrl: streamURL,
                    channelName: channelName,
                    liveTitle: liveTitle,
                    thumbnailURL: liveInfo.liveImageURL,
                    prefetchedManifest: _prefetchedManifest,
                    playerSettings: ps
                )
                playerVM?.applySettings(volume: ps.volumeLevel, lowLatency: ps.lowLatencyMode, catchupRate: ps.catchupRate)
            }
            isLoadingStream = false  // 영상 버퍼링은 VLC streamPhase 스피너가 처리

            // ─── 메트릭/시청기록 fire-and-forget (크리티컬 패스 외) ───
            let _channelName = channelName
            let _streamURL = streamURL
            Task { await appState.metricsForwarder?.activateChannel(channelId: channelId, channelName: _channelName, streamUrl: _streamURL.absoluteString) }

            // VLC 메트릭 콜백 연결 — VLCPlayerEngine의 2초 타이머 → MetricsForwarder
            let _forwarder = appState.metricsForwarder
            playerVM?.setVLCMetricsCallback { metrics in
                Task { await _forwarder?.updateVLCMetrics(metrics) }
            }

            // 서버 동기화 추천 → VLC 재생 속도 적용 콜백
            let _playerVM = playerVM
            Task {
                await _forwarder?.setSyncSpeedCallback { [weak _playerVM] speed in
                    Task { @MainActor [weak _playerVM] in _playerVM?.applySyncSpeed(speed) }
                }
                // VLC 엔진의 liveCaching 값을 targetLatency로 전달
                if let vlc = _playerVM?.playerEngine as? VLCPlayerEngine {
                    await _forwarder?.setTargetLatency(Double(vlc.streamingProfile.liveCaching))
                }
            }

            Task { await recordWatch(channelName: _channelName, thumbnailURL: liveInfo.liveImageURL?.absoluteString, categoryName: liveInfo.liveCategoryValue) }

            // ─── 채팅 준비: 백그라운드에서 병렬 로드 (영상과 동시 진행) ───
            if let chatChannelId = liveInfo.chatChannelId {
                let _channelId = channelId
                let _chatVM = chatVM

                // 캐시된 기본 이모티콘 즉시 적용 (API 로드 전에 사용 가능)
                let cachedMap = appState.cachedBasicEmoticonMap
                let cachedPacks = appState.cachedBasicEmoticonPacks
                if !cachedMap.isEmpty {
                    _chatVM?.channelEmoticons = cachedMap
                    _chatVM?.emoticonPacks = cachedPacks
                }

                Task { [isLoggedIn = appState.isLoggedIn, fallbackUid = appState.isLoggedIn ? appState.userChannelId : nil] in
                    do {
                        let tokenTask = Task { try await apiClient.chatAccessToken(chatChannelId: chatChannelId) }
                        let userTask  = Task<UserStatusInfo?, Never> {
                            guard isLoggedIn else { return nil }
                            return try? await apiClient.userStatus()
                        }
                        let packsTask = Task { await apiClient.basicEmoticonPacks(channelId: _channelId) }

                        let tokenInfo = try await tokenTask.value
                        let userInfo  = await userTask.value
                        let packs     = await packsTask.value
                        let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(packs)

                        // 채널별 이모티콘을 캐시된 기본 이모티콘과 병합
                        let mergedMap = cachedMap.merging(emoMap) { _, channel in channel }
                        let mergedPacks = cachedPacks + loadedPacks.filter { pack in
                            !cachedPacks.contains(where: { $0.id == pack.id })
                        }

                        Log.chat.info("채널 이모티콘: \(mergedMap.count)개 로드 완료 (팩 \(mergedPacks.count)개, 기본 \(cachedMap.count)개 포함)")
                        _chatVM?.channelEmoticons = mergedMap
                        _chatVM?.emoticonPacks = mergedPacks

                        let uid: String? = userInfo?.userIdHash ?? fallbackUid
                        if let uid { _chatVM?.currentUserUid = uid }
                        _chatVM?.currentUserNickname = userInfo?.nickname

                        await _chatVM?.connect(
                            chatChannelId: chatChannelId,
                            accessToken: tokenInfo.accessToken,
                            extraToken: tokenInfo.extraToken,
                            uid: uid,
                            channelId: _channelId
                        )
                    } catch {
                        Log.chat.error("채팅 연결 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            isLoadingStream = false
        } catch {
            loadError = "스트림 로드 실패: \(error.localizedDescription)"
            Log.app.error("스트림 로드 실패: \(error.localizedDescription, privacy: .public)")
            isLoadingStream = false
        }
    }

    // MARK: - Favorite & Watch History

    private func loadFavoriteStatus() async {
        guard let dataStore = appState.dataStore else { return }
        do {
            isFavorite = try await dataStore.isFavorite(channelId: channelId)
        } catch {
            Log.app.error("즐겨찾기 상태 로드 실패: \(error.localizedDescription)")
        }
    }

    private func toggleFavorite() async {
        guard let dataStore = appState.dataStore else { return }
        do {
            if let apiClient = appState.apiClient {
                let channelInfo = try await apiClient.channelInfo(channelId: channelId)
                try await dataStore.saveChannel(channelInfo, isFavorite: !isFavorite)
            }
            isFavorite.toggle()
        } catch {
            Log.app.error("즐겨찾기 토글 실패: \(error.localizedDescription)")
        }
    }

    private func recordWatch(channelName: String, thumbnailURL: String?, categoryName: String?) async {
        guard let dataStore = appState.dataStore else { return }
        do {
            if let apiClient = appState.apiClient {
                let info = try await apiClient.channelInfo(channelId: channelId)
                try await dataStore.saveChannel(info)
            }
            try await dataStore.updateLastWatched(channelId: channelId)

            // WatchHistory 기록 시작
            _ = try await dataStore.startWatchRecord(
                channelId: channelId,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                categoryName: categoryName
            )
            watchStartedAt = .now
        } catch {
            Log.app.error("시청 기록 저장 실패: \(error.localizedDescription)")
        }
    }

    private func endWatchRecord() async {
        guard let dataStore = appState.dataStore, let startedAt = watchStartedAt else { return }
        do {
            try await dataStore.endWatchRecord(channelId: channelId, startedAt: startedAt)
        } catch {
            Log.app.error("시청 종료 기록 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Live Status Polling

    private func startLiveStatusPolling() {
        liveStatusTask?.cancel()
        liveStatusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await pollLiveStatus()
            }
        }
    }

    private func pollLiveStatus() async {
        guard let apiClient = appState.apiClient else { return }
        do {
            let status = try await apiClient.liveStatus(channelId: channelId)
            viewerCount = status.concurrentUserCount
            if status.status == .close {
                isStreamOffline = true
                await playerVM?.stopStream()
            }
        } catch {
            Log.app.debug("방송 상태 폴링 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var formattedViewerCount: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f만", Double(viewerCount) / 10_000.0)
        }
        return "\(viewerCount)"
    }
    
    private func startMetricsFeed() {
        metricsFeedTask?.cancel()
        metricsFeedTask = Task { @MainActor in
            while !Task.isCancelled {
                // [최적화] 1초 → 2초: VLC statTimer(2초)와 동기화, actor hop 50% 감소
                // latency/buffer는 빠른 변동이 없으므로 2초 주기로 충분
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if let vm = playerVM {
                    let latency = vm.latencyInfo?.current ?? 0
                    let bufferPct = vm.bufferHealth?.currentLevel ?? 0
                    await performanceMonitor.updateLatency(latency * 1000)
                    await performanceMonitor.updateBufferHealth(bufferPct * 100)
                }
            }
        }
    }
}

// MARK: - Player Engine Badge

/// 현재 재생 중인 플레이어 엔진 표시 뱃지 (LiveStreamView / MLVideoArea 공용)
struct PlayerEngineBadge: View {
    let engineType: PlayerEngineType

    private var badgeLabel: String {
        switch engineType {
        case .vlc:      "VLC"
        case .avPlayer: "AVPlayer"
        }
    }

    private var accentColor: Color {
        switch engineType {
        case .vlc:      Color(red: 1.0, green: 0.55, blue: 0.0)   // VLC 오렌지
        case .avPlayer: Color(red: 0.24, green: 0.52, blue: 1.0)  // 시스템 블루
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)
            Text(badgeLabel)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
    }
}
