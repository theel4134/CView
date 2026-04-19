// MARK: - MultiLiveOverlays.swift
import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - MLVideoArea
struct MLVideoArea: View {
    let session: MultiLiveSession
    let appState: AppState
    let settingsStore: SettingsStore

    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()

            if showControls {
                MLControlOverlay(session: session, appState: appState)
                    .transition(.opacity.animation(DesignTokens.Animation.fast))
            }

            if session.showStats {
                MLStatsOverlay(
                    metrics: session.latestMetrics,
                    proxyStats: session.latestProxyStats
                )
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            hideTask?.cancel()
            if hovering {
                withAnimation(DesignTokens.Animation.fast) { showControls = true }
                scheduleHide()
            } else {
                scheduleHide()
            }
        }
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(DesignTokens.Animation.fast) { showControls = false }
        }
    }
}

// MARK: - MLControlOverlay
struct MLControlOverlay: View {
    let session: MultiLiveSession
    let appState: AppState

    var body: some View {
        VStack {
            Spacer()
            controlBar
        }
    }

    private var controlBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            controlButton(
                icon: session.playerViewModel.streamPhase == .playing ? "pause.fill" : "play.fill",
                size: 18
            ) {
                Task { await session.playerViewModel.togglePlayPause() }
            }

            Spacer()

            // 볼륨 슬라이더
            if !session.isMuted {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                    OverlayVolumeSlider(
                        value: Binding(
                            get: { Double(session.playerViewModel.volume) },
                            set: { session.playerViewModel.setVolume(Float($0)) }
                        ),
                        trackColor: DesignTokens.Colors.chzzkGreen,
                        width: 100
                    )
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                }
            }

            controlButton(
                icon: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            ) {
                session.setMuted(!session.isMuted)
            }

            controlButton(
                icon: session.showStats ? "chart.bar.fill" : "chart.bar",
                tint: session.showStats ? DesignTokens.Colors.chzzkGreen : .white
            ) {
                session.showStats.toggle()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm + 2)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    private func controlButton(
        icon: String,
        size: CGFloat = 14,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        MLOverlayControlButton(icon: icon, size: size, tint: tint, action: action)
    }
}

/// MLControlOverlay용 개별 버튼 — 호버 효과 포함
private struct MLOverlayControlButton: View {
    let icon: String
    var size: CGFloat = 14
    var tint: Color = .white
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isHovered ? DesignTokens.Colors.controlOnDarkMediaHover : Color.clear)
                )
                .contentShape(Circle())
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - MLGridControlOverlay
struct MLGridControlOverlay: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let isFocused: Bool
    let onHideCancel: () -> Void
    let onScheduleHide: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: DesignTokens.Spacing.md) {
                Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

                gridButtons
                volumeSlider

                // 더블클릭 힌트
                Text(isFocused ? "더블클릭: 그리드 복귀" : "더블클릭: 확대")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
            }
        }
    }

    private var gridButtons: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            gridActionButton(icon: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                onHideCancel()
                manager.toggleSessionAudio(session)
                onScheduleHide()
            }

            gridActionButton(
                icon: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) {
                withAnimation(DesignTokens.Animation.indicator) {
                    focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
                }
            }

            gridActionButton(icon: "xmark", opacity: 0.75) {
                Task { await manager.removeSession(session) }
            }
        }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        if !session.isMuted {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                OverlayVolumeSlider(
                    value: Binding(
                        get: { Double(session.playerViewModel.volume) },
                        set: { session.playerViewModel.setVolume(Float($0)) }
                    ),
                    trackColor: DesignTokens.Colors.chzzkGreen,
                    width: 86
                )
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
            }
        }
    }

    private func gridActionButton(
        icon: String,
        opacity: CGFloat = 1.0,
        action: @escaping () -> Void
    ) -> some View {
        MLGridActionButton(icon: icon, opacity: opacity, action: action)
    }
}

/// MLGridControlOverlay용 개별 액션 버튼 — 호버 효과 포함
private struct MLGridActionButton: View {
    let icon: String
    var opacity: CGFloat = 1.0
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textOnDarkMedia.opacity(opacity))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isHovered ? DesignTokens.Colors.controlOnDarkMediaHover : DesignTokens.Colors.controlOnDarkMedia)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - MLEmptyState
struct MLEmptyState: View {
    let onAdd: () -> Void
    @State private var isAddHovered = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            emptyGridPreview
            emptyDescription
            addButton
            shortcutHints
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, y: 8)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    private var emptyGridPreview: some View {
        let size: CGFloat = 72
        let gap: CGFloat = 2
        return VStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { col in
                        let idx = row * 2 + col
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(idx == 0 ? 0.6 : 0.3))
                            .overlay {
                                VStack(spacing: 3) {
                                    Image(systemName: idx == 0 ? "play.fill" : "plus")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(
                                            idx == 0 ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary
                                        )
                                    if idx == 0 {
                                        Text("CH 1")
                                            .font(DesignTokens.Typography.micro)
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    }
                                }
                            }
                            .frame(width: size, height: size * 9 / 16)
                    }
                }
            }
        }
    }

    private var emptyDescription: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text("멀티 라이브")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("최대 4개 채널을 동시에 시청하세요")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "plus")
                Text("채널 추가")
            }
            .font(DesignTokens.Typography.bodySemibold)
            .foregroundStyle(DesignTokens.Colors.onPrimary)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                Capsule()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    // [GPU 최적화] radius 고정 → blur 캐시 재사용, opacity만 애니메이션
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(isAddHovered ? 0.5 : 0.2), radius: 8, y: 3)
            )
            .scaleEffect(isAddHovered ? 1.05 : 1.0)
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isAddHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isAddHovered)
    }

    private var shortcutHints: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            shortcutPill("⌘1-4", "탭 전환")
            shortcutPill("⌘G", "그리드 전환")
        }
    }

    private func shortcutPill(_ key: String, _ label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(key)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                )
            Text(label)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
}

// MARK: - MLAddChannelPanel
struct MLAddChannelPanel: View {
    @Bindable var manager: MultiLiveManager
    let appState: AppState
    @Binding var isPresented: Bool
    let onError: (String) -> Void
    @State private var isCloseHovered = false

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            MultiLiveAddSheet(manager: manager, isPresented: $isPresented)
                .environment(appState)
        }
        .frame(width: 380)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.94))
        .overlay(alignment: .leading) {
            // [Depth] 좌측 inner shadow — 메인 영역 뒤에서 나오는 깊이감
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 8)
        }
        .onKeyPress(.escape) {
            withAnimation(DesignTokens.Animation.snappy) { isPresented = false }
            return .handled
        }
    }

    private var panelHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "rectangle.split.2x2.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            VStack(alignment: .leading, spacing: 1) {
                Text("채널 추가")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("최대 \(MultiLiveManager.maxSessions)개 채널 동시 시청")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            sessionCounter

            Button {
                withAnimation(DesignTokens.Animation.snappy) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isCloseHovered ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary)
                    .scaleEffect(isCloseHovered ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .animation(DesignTokens.Animation.fast, value: isCloseHovered)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var sessionCounter: some View {
        HStack(spacing: 3) {
            ForEach(0..<MultiLiveManager.maxSessions, id: \.self) { i in
                Circle()
                    .fill(
                        i < manager.sessions.count
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.surfaceOverlay.opacity(0.5)
                    )
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }
}

// MARK: - MLStatsOverlay
struct MLStatsOverlay: View {
    let metrics: VLCLiveMetrics?
    let proxyStats: ProxyNetworkStats?

    private let monoFont = DesignTokens.Typography.custom(size: 10, design: .monospaced)
    private let labelFont = DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statsHeader
            Divider().overlay(DesignTokens.Colors.borderOnDarkMedia)
            videoMetrics
            proxyMetrics
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: 174, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(.black.opacity(0.72))
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.borderOnDarkMedia, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
    }

    // MARK: - Header

    private var statsHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text("MONITOR")
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
        }
    }

    // MARK: - Video Metrics

    @ViewBuilder
    private var videoMetrics: some View {
        if let m = metrics {
            statsSection("VIDEO") {
                statRow("FPS", value: String(format: "%.1f", m.fps), color: m.fps < 25 ? .orange : .green)
                statRow("해상도", value: m.resolution ?? "—")
                statRow("드롭", value: "\(m.droppedFramesDelta)", color: m.droppedFramesDelta > 0 ? .orange : .white)
                statRow("지연", value: "\(m.latePicturesDelta)", color: m.latePicturesDelta > 0 ? .orange : .white)
            }

            statsSection("NETWORK") {
                statRow("속도", value: formatBytesPerSec(m.networkBytesPerSec))
                statRow("입력", value: String(format: "%.0f kbps", m.inputBitrateKbps))
                statRow("Demux", value: String(format: "%.0f kbps", m.demuxBitrateKbps))
            }

            statsSection("HEALTH") {
                let score = m.healthScore
                statRow("점수", value: String(format: "%.0f%%", score * 100), color: healthColor(score))
                statRow("버퍼", value: String(format: "%.0f%%", m.bufferHealth * 100), color: healthColor(m.bufferHealth))
                statRow("오디오손실", value: "\(m.lostAudioBuffersDelta)", color: m.lostAudioBuffersDelta > 0 ? .orange : .white)
            }
        }
    }

    // MARK: - Proxy Metrics

    @ViewBuilder
    private var proxyMetrics: some View {
        if let p = proxyStats {
            statsSection("PROXY") {
                statRow("요청", value: "\(p.totalRequests)")
                statRow("캐시히트", value: String(format: "%.0f%%", p.cacheHitRatio * 100), color: p.cacheHitRatio > 0.9 ? .green : .orange)
                statRow("CDN수신", value: formatBytes(p.totalBytesReceived))
                statRow("응답시간", value: String(format: "%.0fms", p.avgResponseTime * 1000), color: p.avgResponseTime > 0.5 ? .red : p.avgResponseTime > 0.2 ? .orange : .white)
                statRow("연결", value: "\(p.activeConnections)")
                if p.errorCount > 0 {
                    statRow("에러", value: "\(p.errorCount)", color: .red)
                }
                if p.consecutive403Count > 0 {
                    statRow("403연속", value: "\(p.consecutive403Count)", color: .red)
                }
            }
        }
    }

    // MARK: - Components

    private func statsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.65))
                .padding(.top, 2)
            content()
        }
    }

    private func statRow(_ label: String, value: String, color: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(labelFont)
                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaDim)
                .frame(width: 62, alignment: .leading)
            Spacer()
            Text(value)
                .font(monoFont)
                .foregroundStyle(color.opacity(0.85))
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        guard let m = metrics else { return .gray }
        if m.healthScore > 0.8 { return .green }
        if m.healthScore > 0.5 { return .orange }
        return .red
    }

    private func healthColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .orange }
        return .red
    }

    private func formatBytesPerSec(_ bytes: Int) -> String {
        let mbps = Double(bytes) * 8.0 / 1_000_000.0
        if mbps >= 1.0 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(bytes) * 8.0 / 1_000.0
        return String(format: "%.0f kbps", kbps)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
