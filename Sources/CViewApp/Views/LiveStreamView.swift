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

    @State private var chatWidth: CGFloat = 340
    @State private var isChatVisible = true
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

    /// AppState의 공유 PerformanceMonitor 사용 (MetricsForwarder와 동일 인스턴스)
    private var performanceMonitor: PerformanceMonitor { appState.performanceMonitor }

    private var playerVM: PlayerViewModel? { appState.playerViewModel }
    private var chatVM: ChatViewModel? { appState.chatViewModel }

    var body: some View {
        HSplitView {
            // Player area
            playerArea
                .frame(minWidth: 400)
                .overlay(alignment: .topTrailing) {
                    if showDebugOverlay {
                        PerformanceOverlayView(monitor: performanceMonitor)
                            .padding(8)
                    }
                }

            // Chat area (extracted to ChatPanelView)
            if isChatVisible {
                ChatPanelView(chatVM: chatVM) {
                    router.presentSheet(.chatSettings)
                }
                .frame(width: chatWidth, alignment: .trailing)
            }
        }
        .toolbar { streamToolbar }
        .id(channelId)
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
        .onKeyPress(.space) {
            Task { await playerVM?.togglePlayPause() }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "m")) { _ in
            playerVM?.toggleMute()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "f")) { _ in
            playerVM?.toggleFullscreen()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "c")) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isChatVisible.toggle() }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "p")) { _ in
            togglePiP()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "s")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            playerVM?.takeScreenshot()
            return .handled
        }
        .onKeyPress(.upArrow) {
            playerVM?.setVolume(min(1.0, (playerVM?.volume ?? 0.5) + 0.05))
            return .handled
        }
        .onKeyPress(.downArrow) {
            playerVM?.setVolume(max(0.0, (playerVM?.volume ?? 0.5) - 0.05))
            return .handled
        }
    }

    // MARK: - Player Area

    private var playerArea: some View {
        ZStack {
            PlayerVideoView(videoView: playerVM?.currentVideoView)
                .background(Color.black)
                // isAudioOnly 시 AVPlayerLayer.isHidden / VLC videoTrack으로 처리.
                // SwiftUI .opacity()는 동적 값이면 오프스크린 compositing 버퍼를 강제 생성 → GPU 낭비.

            // Audio-only overlay
            if playerVM?.isAudioOnly == true {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        // .variableColor.iterative는 매 프레임 GPU 드로우 → 오디오 절약 모드와 역행.
                        // .pulse는 간헐적 불투명도 변화만 발생하므로 GPU 부담 최소화.
                        .symbolEffect(.pulse)
                    Text("오디오 전용 모드")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("영상 비활성화로 데이터 절약 중")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.Colors.backgroundDark)
            }

            // Player overlay (extracted to PlayerControlsView)
            if showOverlay {
                PlayerOverlayView(
                    playerVM: playerVM,
                    onTogglePiP: togglePiP,
                    onOpenNewWindow: { openWindow(id: "player-window", value: channelId) },
                    onScreenshot: { playerVM?.takeScreenshot() }
                )
            }

            // Buffering
            if isLoadingStream || playerVM?.streamPhase == .buffering || playerVM?.streamPhase == .connecting {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Load error
            if let loadErr = loadError {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(loadErr)
                        .foregroundStyle(.white)
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
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(msg)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }

            // Stream offline
            if isStreamOffline {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("방송이 종료되었습니다")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("스트리머가 방송을 종료했습니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
        .overlay(alignment: .topLeading) {
            if let vm = playerVM {
                PlayerEngineBadge(engineType: vm.currentEngineType)
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { showOverlay = hovering }
            if hovering { playerVM?.showControlsTemporarily() }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { showOverlay.toggle() }
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
                withAnimation(.easeInOut(duration: 0.2)) { isChatVisible.toggle() }
            } label: {
                Image(systemName: isChatVisible ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .foregroundStyle(isChatVisible ? Color.accentColor : .secondary)
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
                        .font(.system(size: 10))
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

            let liveInfo = try await apiClient.liveDetail(channelId: channelId)

            guard let playbackJSON = liveInfo.livePlaybackJSON,
                  let jsonData = playbackJSON.data(using: .utf8) else {
                loadError = "재생 정보를 찾을 수 없습니다."
                isLoadingStream = false
                return
            }

            let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
            let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                ?? playback.media.first

            guard let mediaPath = media?.path,
                  let streamURL = URL(string: mediaPath) else {
                loadError = "HLS 스트림 URL을 찾을 수 없습니다."
                isLoadingStream = false
                return
            }

            let channelName = liveInfo.channel?.channelName ?? ""
            let liveTitle = liveInfo.liveTitle

            let ps = appState.settingsStore.player

            // ─── 영상 즉시 시작 + 로딩 오버레이 즉시 해제 ───
            Task { @MainActor in
                // 재생 직전 최신 설정의 엔진 타입 반영 (앱 실행 중 설정 변경 대응)
                playerVM?.preferredEngineType = ps.preferredEngine
                await playerVM?.startStream(
                    channelId: channelId,
                    streamUrl: streamURL,
                    channelName: channelName,
                    liveTitle: liveTitle
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

            Task { await recordWatch(channelName: _channelName, thumbnailURL: liveInfo.liveImageURL?.absoluteString, categoryName: liveInfo.liveCategoryValue) }

            // ─── 채팅 준비: 백그라운드에서 병렬 로드 (영상과 동시 진행) ───
            if let chatChannelId = liveInfo.chatChannelId {
                let _channelId = channelId
                let _chatVM = chatVM
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

                        Log.chat.info("채널 이모티콘: \(emoMap.count)개 로드 완료 (팩 \(loadedPacks.count)개)")
                        _chatVM?.channelEmoticons = emoMap
                        _chatVM?.emoticonPacks = loadedPacks

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
        metricsFeedTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
    }
}
