// MARK: - PlayerControlsView.swift
// CViewApp - 프리미엄 플레이어 컨트롤 오버레이
// Design: Apple TV+ / Netflix 스타일 오버레이 + 글래스모피즘
// U6: 볼륨 슬라이더, 품질 선택 팝업, VOD 프로그레스 바, LIVE 뱃지, 애니메이션 개선

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence
import CViewUI

// MARK: - Player Overlay (Top Bar + Progress + Bottom Controls)

struct PlayerOverlayView: View {
    let playerVM: PlayerViewModel?
    let onTogglePiP: () -> Void
    var onOpenNewWindow: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onToggleRecording: (() -> Void)? = nil
    var settingsStore: SettingsStore? = nil
    var onToggleSettings: (() -> Void)? = nil
    var isSettingsOpen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — stream info
            StreamInfoBar(playerVM: playerVM)

            Spacer()

            // Bottom area — progress bar (VOD) or LIVE badge + controls
            VStack(spacing: 0) {
                // VOD progress bar or LIVE indicator
                PlayerProgressSection(playerVM: playerVM)

                // Bottom controls — playback buttons
                PlayerControlsBar(
                    playerVM: playerVM,
                    onTogglePiP: onTogglePiP,
                    onOpenNewWindow: onOpenNewWindow,
                    onScreenshot: onScreenshot,
                    onToggleRecording: onToggleRecording,
                    settingsStore: settingsStore,
                    onToggleSettings: onToggleSettings,
                    isSettingsOpen: isSettingsOpen
                )
            }
        }
        .transition(.opacity.animation(DesignTokens.Animation.normal))
    }
}

// MARK: - Progress Section (VOD seekbar / LIVE badge)

/// VOD일 때 시크 가능한 프로그레스 바, 라이브일 때 LIVE 뱃지를 표시
struct PlayerProgressSection: View {
    let playerVM: PlayerViewModel?

    /// VOD 시크 중 로컬 시간 트래킹
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var isHovering = false
    @State private var hoverPosition: CGFloat = 0

    private var isLive: Bool {
        playerVM?.isLiveStream ?? true
    }

    private var currentTime: TimeInterval {
        isDragging ? dragTime : (playerVM?.currentTime ?? 0)
    }

    private var duration: TimeInterval {
        playerVM?.duration ?? 0
    }

    var body: some View {
        if isLive {
            // LIVE badge
            HStack {
                LiveBadge()
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, DesignTokens.Spacing.sm)
        } else if duration > 0 {
            // VOD seekable progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let progress = duration > 0 ? CGFloat(currentTime / duration) : 0

                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: isHovering || isDragging ? 8 : 4)

                        // Progress fill
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(
                                width: max(0, min(width, width * progress)),
                                height: isHovering || isDragging ? 8 : 4
                            )

                        // Thumb
                        if isHovering || isDragging {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen)
                                .frame(width: 14, height: 14)
                                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.4), radius: 4)
                                .offset(x: max(0, min(width - 14, width * progress - 7)))
                        }

                        // Hover time tooltip
                        if isHovering && !isDragging {
                            let hoverTime = duration * Double(max(0, min(1, hoverPosition / width)))
                            Text(PlayerViewModel.formatTimeInterval(hoverTime))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                                .overlay {
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                                }
                                .offset(x: max(20, min(width - 50, hoverPosition - 25)), y: -24)
                        }
                    }
                    .frame(height: isHovering || isDragging ? 8 : 4)
                    .contentShape(Rectangle().size(width: width, height: 24))
                    .onHover { hovering in
                        withAnimation(DesignTokens.Animation.fast) {
                            isHovering = hovering
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPosition = location.x
                        case .ended:
                            break
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let fraction = max(0, min(1, Double(value.location.x / width)))
                                dragTime = duration * fraction
                            }
                            .onEnded { value in
                                let fraction = max(0, min(1, Double(value.location.x / width)))
                                let seekTime = duration * fraction
                                playerVM?.seek(to: seekTime)
                                isDragging = false
                            }
                    )
                    .accessibilityLabel("재생 위치")
                    .accessibilityValue("\(PlayerViewModel.formatTimeInterval(currentTime)) / \(PlayerViewModel.formatTimeInterval(duration))")
                }
                .frame(height: 24)

                // Time labels
                HStack {
                    Text(PlayerViewModel.formatTimeInterval(currentTime))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text(PlayerViewModel.formatTimeInterval(duration))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, DesignTokens.Spacing.xs)
        }
    }
}

// MARK: - LIVE Badge

struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            // shadow radius 고정 — opacity 변화만으로 펄스 표현 (GPU blur 재계산 방지)
            Circle()
                .fill(DesignTokens.Colors.textOnOverlay)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 1.0 : 0.5)

            Text("LIVE")
                .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(Capsule().fill(DesignTokens.Gradients.live))
        .clipShape(Capsule())
        .shadow(color: DesignTokens.Colors.live.opacity(0.35), radius: 6, y: 2)
        .onAppear {
            if let anim = DesignTokens.Animation.motionSafe(DesignTokens.Animation.pulse) {
                withAnimation(anim) {
                    isPulsing = true
                }
            }
        }
        .accessibilityLabel("라이브 방송 중")
    }
}

// MARK: - Stream Info Bar (Top)

struct StreamInfoBar: View {
    let playerVM: PlayerViewModel?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(playerVM?.channelName ?? "")
                    .font(DesignTokens.Typography.custom(size: 15, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)

                Text(playerVM?.liveTitle ?? "")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // Stream info badges with glass effect
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let quality = playerVM?.currentQuality {
                    InfoBadge(text: quality.name, icon: "sparkles", color: DesignTokens.Colors.accentBlue)
                }

                if let latency = playerVM?.formattedLatency, latency != "-" {
                    InfoBadge(text: latency, icon: "clock", color: DesignTokens.Colors.chzzkGreen)
                }

                if let rate = playerVM?.formattedPlaybackRate, rate != "1.0x" {
                    InfoBadge(text: rate, icon: "speedometer", color: DesignTokens.Colors.accentOrange)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Player Controls Bar (Bottom)

struct PlayerControlsBar: View {
    let playerVM: PlayerViewModel?
    let onTogglePiP: () -> Void
    var onOpenNewWindow: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onToggleRecording: (() -> Void)? = nil
    var settingsStore: SettingsStore? = nil
    var onToggleSettings: (() -> Void)? = nil
    var isSettingsOpen: Bool = false
    @State private var isVolumeHovered = false
    @State private var showQualityPopover = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            // Play/Pause with hover effect
            PlayerButton(icon: playerVM?.streamPhase == .playing ? "pause.fill" : "play.fill", size: 22, isPrimary: true) {
                Task { await playerVM?.togglePlayPause() }
            }
            .accessibilityLabel(playerVM?.streamPhase == .playing ? "일시정지" : "재생")

            // Volume control — hover to expand slider, click icon to mute
            HStack(spacing: 6) {
                PlayerButton(icon: volumeIcon, size: 16) {
                    playerVM?.toggleMute()
                }
                .accessibilityLabel(playerVM?.isMuted == true ? "음소거 해제" : "음소거")

                if isVolumeHovered {
                    HStack(spacing: 6) {
                        OverlayVolumeSlider(
                            value: Binding(
                                get: { Double(playerVM?.volume ?? 1.0) },
                                set: { playerVM?.setVolume(Float($0)) }
                            ),
                            trackColor: DesignTokens.Colors.chzzkGreen,
                            width: 80
                        )
                        .accessibilityLabel("볼륨")
                        .accessibilityValue("\(Int((playerVM?.volume ?? 1.0) * 100))%")

                        Text("\(Int((playerVM?.volume ?? 1.0) * 100))%")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, alignment: .trailing)
                    }
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

            Spacer()

            // Quality selector — inline popup with checkmark
            QualitySelector(playerVM: playerVM)

            // VLC 4.0 고급 설정 (이퀄라이저, 비디오 필터, 화면 비율, 자막, 오디오)
            PlayerButton(icon: "slider.horizontal.3", size: 14) {
                onToggleSettings?()
            }
            .help("고급 설정")
            .overlay {
                if isSettingsOpen {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.25))
                        .allowsHitTesting(false)
                }
            }

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
                        .font(DesignTokens.Typography.caption)
                    Text(playerVM?.formattedPlaybackRate ?? "1.0x")
                        .font(DesignTokens.Typography.captionMedium)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
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

            // Record — 녹화 버튼
            RecordButton(
                isRecording: playerVM?.isRecording ?? false,
                recordingDuration: playerVM?.formattedRecordingDuration ?? "0:00"
            ) {
                onToggleRecording?()
            }

            // Fullscreen
            PlayerButton(
                icon: playerVM?.isFullscreen == true
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: 14
            ) {
                playerVM?.toggleFullscreen()
            }
            .accessibilityLabel("전체화면")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private var volumeIcon: String {
        guard let vm = playerVM else { return "speaker.fill" }
        if vm.isMuted || vm.volume == 0 { return "speaker.slash.fill" }
        if vm.volume < 0.33 { return "speaker.wave.1.fill" }
        if vm.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Quality Selector (Inline Popup)

/// 인라인 품질 선택 팝업 — 현재 선택된 품질 강조 + 해상도/대역폭 정보
struct QualitySelector: View {
    let playerVM: PlayerViewModel?
    @State private var showPopover = false
    @State private var isHovered = false

    private var qualities: [StreamQualityInfo] {
        playerVM?.availableQualities ?? []
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(DesignTokens.Typography.captionMedium)
                if let quality = playerVM?.currentQuality {
                    Text(quality.name)
                        .font(DesignTokens.Typography.captionMedium)
                }
            }
            .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.9))
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            QualityPopoverContent(
                qualities: qualities,
                currentQuality: playerVM?.currentQuality,
                onSelect: { quality in
                    Task { await playerVM?.switchQuality(quality) }
                    showPopover = false
                }
            )
        }
        .accessibilityLabel("화질 선택")
        .accessibilityValue(playerVM?.currentQuality?.name ?? "자동")
    }
}

/// 품질 선택 팝업 콘텐츠 — 리스트 형태로 품질 옵션 표시
struct QualityPopoverContent: View {
    let qualities: [StreamQualityInfo]
    let currentQuality: StreamQualityInfo?
    let onSelect: (StreamQualityInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("화질")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)

            Divider()

            // Quality list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(qualities) { quality in
                        QualityRow(
                            quality: quality,
                            isSelected: quality.id == currentQuality?.id,
                            onSelect: { onSelect(quality) }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 200)
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }
}

/// 개별 품질 옵션 행
struct QualityRow: View {
    let quality: StreamQualityInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.name)
                        .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : .primary)

                    if !quality.resolution.isEmpty {
                        Text(quality.resolution)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .accessibilityLabel(quality.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Custom Volume Slider (macOS Slider .tint() 렌더링 버그 대응)

/// macOS 기본 Slider가 다크 오버레이 위에서 .tint()을 무시하고 노란색 트랙 + 🚫 렌더링되는 문제 해결
struct OverlayVolumeSlider: View {
    @Binding var value: Double
    var trackColor: Color = DesignTokens.Colors.chzzkGreen
    var width: CGFloat = 80
    var trackHeight: CGFloat = 4

    @State private var isDragging = false
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let progress = CGFloat(max(0, min(1, value)))
            let thumbSize: CGFloat = (isHovered || isDragging) ? 12 : 8

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: trackHeight)

                // Filled track
                Capsule()
                    .fill(trackColor)
                    .frame(width: max(trackHeight, w * progress), height: trackHeight)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: max(0, min(w - thumbSize, w * progress - thumbSize / 2)))
                    .animation(DesignTokens.Animation.fast, value: isHovered)
            }
            .frame(height: max(trackHeight, 14))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        value = max(0, min(1, Double(drag.location.x / w)))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { isHovered = $0 }
        }
        .frame(width: width, height: 14)
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
                .font(DesignTokens.Typography.custom(size: size, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                .frame(width: isPrimary ? 42 : 32, height: isPrimary ? 42 : 32)
                .background {
                    if isPrimary {
                        Circle()
                            .fill(isHovered ? .white.opacity(0.28) : .white.opacity(0.14))
                            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    } else {
                        Circle()
                            .fill(isHovered ? .white.opacity(0.14) : .clear)
                    }
                }
                .scaleEffect(isHovered ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable()
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
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
                    .font(DesignTokens.Typography.microSemibold)
            }
            Text(text)
                .font(DesignTokens.Typography.micro)
        }
        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs + 1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5)
        }
    }
}

// MARK: - Record Button

/// 녹화 버튼 — 빨간 원 아이콘 / 녹화 중일 때 펄싱 빨간 점 + 경과시간 표시
struct RecordButton: View {
    let isRecording: Bool
    let recordingDuration: String
    let action: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // 빨간 원 (녹화 중: 펄싱) — drawingGroup으로 shadow+scale 오프스크린 격리
                Circle()
                    .fill(isRecording ? DesignTokens.Colors.live : DesignTokens.Colors.live.opacity(0.8))
                    .frame(width: isRecording ? 10 : 8, height: isRecording ? 10 : 8)
                    .scaleEffect(isRecording && isPulsing ? 1.3 : 1.0)
                    .opacity(isRecording && isPulsing ? 0.6 : 1.0)

                // 녹화 중이면 경과 시간 표시
                if isRecording {
                    Text(recordingDuration)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                }
            }
            .padding(.horizontal, isRecording ? 10 : 0)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(minWidth: 36, minHeight: 36)
            .background {
                if isRecording {
                    Capsule()
                        .fill(DesignTokens.Colors.live.opacity(0.25))
                        .overlay(
                            Capsule().strokeBorder(DesignTokens.Colors.live.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(isHovered ? .white.opacity(0.15) : .clear)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .help(isRecording ? "녹화 중지 (⌘R)" : "녹화 시작 (⌘R)")
        .accessibilityLabel(isRecording ? "녹화 중지" : "녹화 시작")
        .accessibilityValue(isRecording ? recordingDuration : "")
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                if let anim = DesignTokens.Animation.motionSafe(DesignTokens.Animation.pulse) {
                    withAnimation(anim) {
                        isPulsing = true
                    }
                }
            } else {
                isPulsing = false
            }
        }
    }
}
