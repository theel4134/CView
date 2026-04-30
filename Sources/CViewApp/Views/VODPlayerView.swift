// MARK: - VODPlayerView.swift
// VOD 재생 화면

import SwiftUI
import CViewCore
import CViewUI
import CViewPlayer
import CViewNetworking

/// VOD 재생 뷰
struct VODPlayerView: View {
    
    let videoNo: Int
    @State private var viewModel: VODPlayerViewModel
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    
    init(videoNo: Int, apiClient: ChzzkAPIClient) {
        self.videoNo = videoNo
        self._viewModel = State(initialValue: VODPlayerViewModel(apiClient: apiClient))
    }
    
    var body: some View {
        ZStack {
            // Video area
            Color.black
            
            if let engine = viewModel.playerEngine {
                AVVideoView(playerEngine: engine)
            }
            
            // Loading overlay
            if viewModel.playbackState == .loading || viewModel.playbackState == .buffering {
                CViewLoadingIndicator(message: "로딩 중...")
            }
            
            // Error overlay
            if case .error(let msg) = viewModel.playbackState {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.custom(size: 40))
                        .foregroundStyle(.yellow)
                    Text(msg)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    Button("다시 시도") {
                        Task { await viewModel.startVOD(videoNo: videoNo) }
                    }
                    .buttonStyle(CViewButtonStyle())
                }
            }
            
            // Ended overlay
            if viewModel.playbackState == .ended {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 50))
                        .foregroundStyle(DesignTokens.Colors.textOnDarkMedia.opacity(0.8))
                    Text("재생 완료")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    Button("다시 재생") {
                        viewModel.togglePlayPause()
                    }
                    .buttonStyle(CViewButtonStyle())
                }
            }
            
            // Controls overlay
            if showControls && viewModel.playbackState != .idle {
                controlsOverlay
            }
        }
        .background(.black)
        .task {
            await viewModel.startVOD(videoNo: videoNo)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onHover { hovering in
            showControls = hovering
            resetControlsTimer()
        }
        .navigationTitle(viewModel.videoTitle)
        .onKeyPress(.space) {
            viewModel.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.seekRelative(-5)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.seekRelative(5)
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.adjustVolume(0.05)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.adjustVolume(-0.05)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "m")) { _ in
            viewModel.toggleMute()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "f")) { _ in
            viewModel.toggleFullscreen()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "p")) { _ in
            if let engine = viewModel.playerEngine {
                PiPController.shared.togglePiP(vlcEngine: nil, avEngine: engine, title: viewModel.videoTitle)
            }
            return .handled
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Speed selector
                Menu {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Button {
                            viewModel.setSpeed(speed)
                        } label: {
                            HStack {
                                Text(speed.displayName)
                                if viewModel.playbackSpeed == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(viewModel.playbackSpeed.displayName, systemImage: "speedometer")
                }
                
                // Volume
                Button {
                    viewModel.toggleMute()
                } label: {
                    Label("음소거", systemImage: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                
                // Fullscreen
                Button {
                    viewModel.toggleFullscreen()
                } label: {
                    Label("전체화면", systemImage: viewModel.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            // Top gradient + title
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.videoTitle)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .lineLimit(1)
                    if !viewModel.channelName.isEmpty {
                        Text(viewModel.channelName)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textOnDarkMediaMuted)
                    }
                }
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
            )
            
            Spacer()
            
            // Center play/pause button
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: playPauseIcon)
                    .font(DesignTokens.Typography.custom(size: 50))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .shadow(radius: 4)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 8) {
                // Timeline
                TimelineSlider(
                    currentTime: $viewModel.currentTime,
                    duration: viewModel.duration,
                    onSeek: { time in
                        viewModel.seek(to: time)
                    }
                )
                
                // Bottom row
                HStack(spacing: 16) {
                    // Play/Pause
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: playPauseIcon)
                            .font(DesignTokens.Typography.custom(size: 16))
                    }
                    .buttonStyle(.plain)
                    
                    // Volume
                    HStack(spacing: 4) {
                        Button {
                            viewModel.toggleMute()
                        } label: {
                            Image(systemName: volumeIcon)
                                .font(DesignTokens.Typography.body)
                        }
                        .buttonStyle(.plain)
                        
                        Slider(value: Binding(
                            get: { Double(viewModel.volume) },
                            set: { viewModel.setVolume(Float($0)) }
                        ), in: 0...1)
                        .frame(width: 80)
                    }
                    
                    // Time
                    Text("\(VODPlayerViewModel.formatTime(viewModel.currentTime)) / \(VODPlayerViewModel.formatTime(viewModel.duration))")
                        .font(DesignTokens.Typography.custom(size: 12, design: .monospaced))
                    
                    Spacer()
                    
                    // Speed
                    Menu {
                        ForEach(PlaybackSpeed.allCases) { speed in
                            Button(speed.displayName) {
                                viewModel.setSpeed(speed)
                            }
                        }
                    } label: {
                        Text(viewModel.playbackSpeed.displayName)
                            .font(DesignTokens.Typography.captionMedium)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
                    }
                    .menuStyle(.borderlessButton)
                    
                    // Fullscreen
                    Button {
                        viewModel.toggleFullscreen()
                    } label: {
                        Image(systemName: viewModel.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(DesignTokens.Typography.body)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
        }
        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
    }
    
    // MARK: - Helpers
    
    private var playPauseIcon: String {
        switch viewModel.playbackState {
        case .playing: "pause.fill"
        case .paused, .ended: "play.fill"
        default: "play.fill"
        }
    }
    
    private var volumeIcon: String {
        if viewModel.isMuted || viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.3 {
            return "speaker.fill"
        } else if viewModel.volume < 0.7 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                showControls = false
            }
        }
    }
}
