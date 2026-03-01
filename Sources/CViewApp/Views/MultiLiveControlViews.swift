// MARK: - MultiLiveControlViews.swift
// CViewApp - MLVideoArea + MLControlOverlay
// Extracted from MultiLiveOverlays.swift

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Video Area (탭 모드 전용)
struct MLVideoArea: View {
    let session: MultiLiveSession
    let appState: AppState
    var settingsStore: SettingsStore? = nil
    @State private var showOverlay = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()

            if session.playerViewModel.isAudioOnly {
                ZStack {
                    Color.black
                    if let url = session.thumbnailURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                                .blur(radius: 30).opacity(0.28)
                        } placeholder: { Color.clear }
                        .ignoresSafeArea()
                    }
                    Color.black.opacity(0.62)
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.11))
                                .frame(width: 84, height: 84)
                            Circle()
                                .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.22), lineWidth: 1)
                                .frame(width: 84, height: 84)
                            Image(systemName: "waveform")
                                .font(DesignTokens.Typography.custom(size: 32, weight: .light))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                .symbolEffect(.pulse)
                        }
                        VStack(spacing: 5) {
                            let name = session.channelName.isEmpty ? session.channelId : session.channelName
                            Text(name)
                                .font(DesignTokens.Typography.bodySemibold)
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .lineLimit(1)
                            Text("오디오 전용 모드")
                                .font(DesignTokens.Typography.caption).foregroundStyle(.white.opacity(0.42))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // [중복 제거] 버퍼링/연결 스피너는 MLPlayerPane의 상태 오버레이에서 통합 관리.
            // MLVideoArea에서 별도 표시하면 2개가 겹쳐 보이는 문제 발생.
            // 그리드 모드 MLGridCell에서도 별도 스피너를 관리하므로 여기서는 생략.

            if session.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "tv.slash").font(DesignTokens.Typography.captionMedium)
                    Text("방송 종료").font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial.opacity(0.9))
                .clipShape(Capsule())
            }

            // 엔진 뱃지
            VStack {
                HStack {
                    PlayerEngineBadge(engineType: session.playerViewModel.currentEngineType)
                        .padding(DesignTokens.Spacing.xs)
                    Spacer()
                }
                Spacer()
            }

            // 오버레이 (hover 시)
            if showOverlay {
                MLControlOverlay(session: session, appState: appState, settingsStore: settingsStore, onHideCancel: { hideTask?.cancel() }, onScheduleHide: { scheduleHide() })
                    .transition(.opacity.animation(DesignTokens.Animation.fast))
            }
        }
        .clipped()
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
        .onTapGesture {
            hideTask?.cancel()
            withAnimation { showOverlay.toggle() }
            if showOverlay { scheduleHide() }
        }
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

// MARK: - Control Overlay (탭 모드 전용)
struct MLControlOverlay: View {
    let session: MultiLiveSession
    let appState: AppState
    var settingsStore: SettingsStore? = nil
    var onHideCancel: (() -> Void)? = nil
    var onScheduleHide: (() -> Void)? = nil
    @State private var showQualityPopover = false
    @State private var showAdvancedSettings = false

    private var isPlaying: Bool {
        session.playerViewModel.playerEngine?.isPlaying ?? false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
            }
            VStack {
                topBar.padding(.horizontal, DesignTokens.Spacing.md).padding(.top, DesignTokens.Spacing.sm)
                Spacer()
                bottomBar.padding(.horizontal, DesignTokens.Spacing.md).padding(.bottom, DesignTokens.Spacing.sm)
            }

            if session.showStats {
                MLStatsOverlay(session: session, compact: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .onHover { hovering in
            if hovering {
                onHideCancel?()
            } else {
                if !showAdvancedSettings && !showQualityPopover {
                    onScheduleHide?()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(DesignTokens.Colors.live).frame(width: 6, height: 6)
                Text("LIVE").font(DesignTokens.Typography.custom(size: 10, weight: .black)).foregroundStyle(DesignTokens.Colors.textOnOverlay)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.live.opacity(0.85))
            .clipShape(Capsule())

            Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                .font(DesignTokens.Typography.captionSemibold).foregroundStyle(DesignTokens.Colors.textOnOverlay)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .lineLimit(1)

            if !session.liveTitle.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(session.liveTitle)
                    .font(DesignTokens.Typography.caption).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            if session.viewerCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    Text(session.formattedViewerCount).font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, DesignTokens.Spacing.xxs)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await session.playerViewModel.togglePlayPause() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "일시정지" : "재생")

            Button { session.setMuted(!session.isMuted) } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(session.isMuted ? .orange : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help(session.isMuted ? "음소거 해제" : "음소거")

            Slider(
                value: Binding(
                    get: { Double(session.playerViewModel.volume) },
                    set: { v in
                        session.playerViewModel.setVolume(Float(v))
                        if session.isMuted && v > 0 { session.setMuted(false) }
                    }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .frame(width: 80)
            .tint(DesignTokens.Colors.chzzkGreen)
            .disabled(session.isMuted)
            .opacity(session.isMuted ? 0.4 : 1)

            Spacer()

            Text(session.playerViewModel.formattedUptime)
                .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            // 고급 설정
            Button {
                onHideCancel?()
                showAdvancedSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(showAdvancedSettings ? DesignTokens.Colors.chzzkGreen : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(
                        showAdvancedSettings
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                            : Color.white.opacity(0.12)
                    ))
            }
            .buttonStyle(.plain)
            .help("고급 설정")
            .popover(isPresented: $showAdvancedSettings, arrowEdge: .top) {
                PlayerAdvancedSettingsView(playerVM: session.playerViewModel, settingsStore: settingsStore)
            }
            .onChange(of: showAdvancedSettings) { _, newVal in
                if !newVal { onScheduleHide?() }
            }

            // 재생 속도
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        Task { await session.playerViewModel.setPlaybackRate(rate) }
                    } label: {
                        HStack {
                            Text(rate == 1.0 ? "1x (기본)" : "\(String(format: "%.2g", rate))x")
                            if abs(session.playerViewModel.playbackRate - rate) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(abs(session.playerViewModel.playbackRate - 1.0) > 0.01 ? DesignTokens.Colors.chzzkGreen : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("재생 속도")

            // 통계 토글
            Button {
                withAnimation(DesignTokens.Animation.snappy) { session.showStats.toggle() }
            } label: {
                Image(systemName: session.showStats ? "chart.bar.xaxis" : "chart.bar")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(session.showStats ? DesignTokens.Colors.chzzkGreen : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(
                        session.showStats
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                            : Color.white.opacity(0.12)
                    ))
            }
            .buttonStyle(.plain)
            .help(session.showStats ? "통계 숨기기" : "통계 보기")

            // 새로고침
            Button {
                guard let api = appState.apiClient else { return }
                Task { await session.refreshStream(using: api, appState: appState) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help("영상 새로고침")

            // 스크린샷
            Button {
                session.playerViewModel.takeScreenshot()
            } label: {
                Image(systemName: "camera")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help("스크린샷")

            // PiP
            Button {
                if let vlcEngine = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                    PiPController.shared.startPiP(vlcEngine: vlcEngine)
                }
            } label: {
                Image(systemName: "pip.enter")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help("PiP")

            // 화질 선택
            if let quality = session.playerViewModel.currentQuality {
                Button {
                    onHideCancel?()
                    showQualityPopover = true
                } label: {
                    Text(quality.name)
                        .font(DesignTokens.Typography.micro).foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.accentBlue.opacity(0.8))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("화질 선택")
                .popover(isPresented: $showQualityPopover, arrowEdge: .bottom) {
                    MLQualityPopover(session: session)
                }
                .onChange(of: showQualityPopover) { _, newVal in
                    if !newVal { onScheduleHide?() }
                }
            }

            // 오류/오프라인 상태 재시도
            switch session.loadState {
            case .error, .offline:
                Button {
                    guard let api = appState.apiClient else { return }
                    Task { await session.retry(using: api, appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.orange.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("재시도")
            default:
                EmptyView()
            }

            // 전체화면
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help("전체화면")

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    session.isChatVisible.toggle()
                }
            } label: {
                Image(systemName: session.isChatVisible
                      ? "bubble.left.and.bubble.right.fill"
                      : "bubble.left.and.bubble.right")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(session.isChatVisible ? DesignTokens.Colors.chzzkGreen : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(
                        session.isChatVisible
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                            : Color.white.opacity(0.12)
                    ))
            }
            .buttonStyle(.plain)
            .help(session.isChatVisible ? "채팅 숨기기" : "채팅 보기")
        }
    }

}

