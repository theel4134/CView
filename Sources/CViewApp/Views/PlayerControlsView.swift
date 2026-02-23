// MARK: - PlayerControlsView.swift
// CViewApp - 프리미엄 플레이어 컨트롤 오버레이
// Design: Apple TV+ / Netflix 스타일 오버레이 + 글래스모피즘

import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Player Overlay (Top Bar + Bottom Controls)

struct PlayerOverlayView: View {
    let playerVM: PlayerViewModel?
    let onTogglePiP: () -> Void
    var onOpenNewWindow: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil

    var body: some View {
        VStack {
            // Top bar — stream info
            StreamInfoBar(playerVM: playerVM)

            Spacer()

            // Bottom controls — playback buttons
            PlayerControlsBar(
                playerVM: playerVM,
                onTogglePiP: onTogglePiP,
                onOpenNewWindow: onOpenNewWindow,
                onScreenshot: onScreenshot
            )
        }
    }
}

// MARK: - Stream Info Bar (Top)

struct StreamInfoBar: View {
    let playerVM: PlayerViewModel?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(playerVM?.channelName ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text(playerVM?.liveTitle ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer()

            // Stream info badges with glass effect
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let quality = playerVM?.currentQuality {
                    InfoBadge(text: quality.name, icon: "sparkles.tv", color: DesignTokens.Colors.accentBlue)
                }

                if let latency = playerVM?.formattedLatency, latency != "-" {
                    InfoBadge(text: latency, icon: "clock", color: DesignTokens.Colors.chzzkGreen)
                }

                if let rate = playerVM?.formattedPlaybackRate, rate != "1.0x" {
                    InfoBadge(text: rate, icon: "speedometer", color: DesignTokens.Colors.accentOrange)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.mdl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Gradients.playerOverlayTop)
    }
}

// MARK: - Player Controls Bar (Bottom)

struct PlayerControlsBar: View {
    let playerVM: PlayerViewModel?
    let onTogglePiP: () -> Void
    var onOpenNewWindow: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    @State private var isVolumeHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.mdl) {
            // Play/Pause with hover effect
            PlayerButton(icon: playerVM?.streamPhase == .playing ? "pause.fill" : "play.fill", size: 22, isPrimary: true) {
                Task { await playerVM?.togglePlayPause() }
            }

            // Volume control
            HStack(spacing: 6) {
                PlayerButton(icon: volumeIcon, size: 16) {
                    playerVM?.toggleMute()
                }

                if isVolumeHovered {
                    Slider(value: Binding(
                        get: { Double(playerVM?.volume ?? 1.0) },
                        set: { playerVM?.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 80)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .onHover { hovering in
                withAnimation(DesignTokens.Animation.smooth) {
                    isVolumeHovered = hovering
                }
            }

            // Volume percentage
            if let vm = playerVM {
                Text("\(Int(vm.volume * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Quality selector
            Menu {
                ForEach(playerVM?.availableQualities ?? []) { quality in
                    Button {
                        Task { await playerVM?.switchQuality(quality) }
                    } label: {
                        HStack {
                            Text(quality.name)
                            if quality.id == playerVM?.currentQuality?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    if let quality = playerVM?.currentQuality {
                        Text(quality.name)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Audio-only mode
            PlayerButton(
                icon: playerVM?.isAudioOnly == true ? "speaker.wave.2.fill" : "eye.slash",
                size: 14
            ) {
                playerVM?.toggleAudioOnly()
            }
            .help(playerVM?.isAudioOnly == true ? "영상 켜기" : "오디오만 듣기")

            // Playback speed
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        Task { await playerVM?.setPlaybackRate(rate) }
                    } label: {
                        HStack {
                            Text(rate == 1.0 ? "1.0x (기본)" : String(format: "%.2gx", rate))
                            if abs((playerVM?.playbackRate ?? 1.0) - rate) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 12))
                    Text(playerVM?.formattedPlaybackRate ?? "1.0x")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // 새 창에서 재생
            if onOpenNewWindow != nil {
                PlayerButton(icon: "rectangle.on.rectangle", size: 14) {
                    onOpenNewWindow?()
                }
                .help("새 창에서 재생")
            }

            // PiP
            PlayerButton(icon: PiPController.shared.isActive ? "pip.exit" : "pip.enter", size: 15) {
                onTogglePiP()
            }
            .help("PiP (P)")

            // Screenshot
            PlayerButton(icon: "camera.fill", size: 14) {
                onScreenshot?()
            }
            .help("스크린샷 (⌘S)")

            // Fullscreen
            PlayerButton(
                icon: playerVM?.isFullscreen == true
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: 14
            ) {
                playerVM?.toggleFullscreen()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.mdl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Gradients.playerOverlayBottom)
    }

    private var volumeIcon: String {
        guard let vm = playerVM else { return "speaker.fill" }
        if vm.isMuted || vm.volume == 0 { return "speaker.slash.fill" }
        if vm.volume < 0.33 { return "speaker.wave.1.fill" }
        if vm.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Player Button

struct PlayerButton: View {
    let icon: String
    let size: CGFloat
    var isPrimary: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: isPrimary ? 44 : 36, height: isPrimary ? 44 : 36)
                .background {
                    if isPrimary {
                        Circle()
                            .fill(isHovered ? .white.opacity(0.25) : .white.opacity(0.12))
                    } else {
                        Circle()
                            .fill(isHovered ? .white.opacity(0.15) : .clear)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Info Badge (Premium)

struct InfoBadge: View {
    let text: String
    var icon: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5)
        }
        .clipShape(Capsule())
    }
}
