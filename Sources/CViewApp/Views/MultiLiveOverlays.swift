// MARK: - MultiLiveOverlays.swift
// MLGridControlOverlay, MLVideoArea, MLEmptyState, MLAddChannelPanel 등
// MultiLivePlayerPane.swift에서 분리된 오버레이 뷰

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - MLVideoArea
/// 활성 패인의 비디오 영역 + 컨트롤 오버레이
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

            // 호버 시 컨트롤 오버레이
            if showControls {
                MLControlOverlay(session: session, appState: appState)
                    .transition(.opacity.animation(DesignTokens.Animation.fast))
            }

            // Stats 오버레이 (좌상단)
            if session.showStats {
                MLStatsOverlay(
                    metrics: session.latestMetrics,
                    proxyStats: session.latestProxyStats
                )
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hideTask?.cancel()
            if hovering {
                withAnimation { showControls = true }
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
            withAnimation { showControls = false }
        }
    }
}

// MARK: - MLControlOverlay
/// 싱글 모드 컨트롤 오버레이 (볼륨, 플레이/일시정지 등)
struct MLControlOverlay: View {
    let session: MultiLiveSession
    let appState: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: DesignTokens.Spacing.md) {
                // 재생/일시정지
                Button {
                    Task { await session.playerViewModel.togglePlayPause() }
                } label: {
                    Image(systemName: session.playerViewModel.streamPhase == .playing ? "pause.fill" : "play.fill")
                        .font(DesignTokens.Typography.titleSemibold)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                // 음소거 토글
                Button {
                    session.setMuted(!session.isMuted)
                } label: {
                    Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // 채팅 토글
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        session.isChatVisible.toggle()
                    }
                } label: {
                    Image(systemName: session.isChatVisible ? "bubble.left.fill" : "bubble.left")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Stats 토글
                Button {
                    session.showStats.toggle()
                } label: {
                    Image(systemName: session.showStats ? "chart.bar.fill" : "chart.bar")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(session.showStats ? DesignTokens.Colors.chzzkGreen : .white)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - MLGridControlOverlay
/// 그리드 셀 호버 시 표시되는 컨트롤 오버레이
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
            // 반투명 배경
            Color.black.opacity(0.4)

            VStack(spacing: DesignTokens.Spacing.sm) {
                // 채널명
                Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: DesignTokens.Spacing.md) {
                    // 오디오 토글
                    Button {
                        onHideCancel()
                        manager.toggleSessionAudio(session)
                        onScheduleHide()
                    } label: {
                        Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    // 포커스 토글
                    Button {
                        withAnimation(DesignTokens.Animation.indicator) {
                            focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
                        }
                    } label: {
                        Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    // 제거
                    Button {
                        Task { await manager.removeSession(session) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                // 볼륨 슬라이더 (오디오 활성 셀에서만)
                if !session.isMuted {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                        Slider(
                            value: Binding(
                                get: { Double(session.playerViewModel.volume) },
                                set: { session.playerViewModel.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 80)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}

// MARK: - MLEmptyState
/// 세션이 없을 때 표시되는 빈 상태 뷰
struct MLEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            // 2x2 그리드 미리보기
            mlGridPreview

            // 타이틀 + 설명
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("멀티 라이브")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("최대 4개 채널을 동시에 시청하세요")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            // 채널 추가 버튼
            Button(action: onAdd) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "plus")
                    Text("채널 추가")
                }
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
            }
            .buttonStyle(.plain)

            // 키보드 단축키 안내
            mlShortcutHints
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    // 2x2 빈 슬롯 그리드 미리보기
    private var mlGridPreview: some View {
        let slotSize: CGFloat = 80
        let gap: CGFloat = 2
        return VStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { col in
                        let index = row * 2 + col
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: index == 0 ? "play.fill" : "plus")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(
                                            index == 0
                                                ? DesignTokens.Colors.chzzkGreen
                                                : DesignTokens.Colors.textTertiary
                                        )
                                    if index == 0 {
                                        Text("CH 1")
                                            .font(DesignTokens.Typography.micro)
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    }
                                }
                            )
                            .frame(width: slotSize, height: slotSize * 9 / 16)
                    }
                }
            }
        }
    }

    // 키보드 단축키 안내
    private var mlShortcutHints: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            shortcutPill("⌘1-4", "탭 전환")
            shortcutPill("⌘G", "그리드 전환")
        }
    }

    private func shortcutPill(_ key: String, _ label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(key)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                )
            Text(label)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
}

// MARK: - MLAddChannelPanel
/// 사이드 패널: 채널 추가 UI
struct MLAddChannelPanel: View {
    @Bindable var manager: MultiLiveManager
    let appState: AppState
    @Binding var isPresented: Bool
    let onError: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "rectangle.split.2x2.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)

                VStack(alignment: .leading, spacing: 1) {
                    Text("채널 추가")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("최대 \(MultiLiveManager.maxSessions)개 채널 동시 시청")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Spacer()

                // 세션 카운터
                HStack(spacing: 4) {
                    ForEach(0..<MultiLiveManager.maxSessions, id: \.self) { i in
                        Circle()
                            .fill(i < manager.sessions.count ? DesignTokens.Colors.chzzkGreen : DesignTokens.Glass.borderColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6)))

                Button {
                    withAnimation(DesignTokens.Animation.snappy) { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            // 콘텐츠
            MultiLiveAddSheet(manager: manager, isPresented: $isPresented)
                .environment(appState)
        }
        .frame(width: 380)
        .background(
            DesignTokens.Colors.surfaceBase.opacity(0.92)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.Glass.borderColor)
                .frame(width: 0.5)
        }

    }
}

// MARK: - MLStatsOverlay
/// 멀티라이브 실시간 네트워크/재생 모니터링 오버레이
struct MLStatsOverlay: View {
    let metrics: VLCLiveMetrics?
    let proxyStats: ProxyNetworkStats?

    private let monoFont = Font.system(size: 10, weight: .regular, design: .monospaced)
    private let labelFont = Font.system(size: 10, weight: .medium, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 헤더
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text("LIVE MONITOR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Divider().overlay(.white.opacity(0.15))

            // 비디오 메트릭
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

            // 프록시 메트릭
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
        .padding(8)
        .frame(width: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(Color.black.opacity(0.75))
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Components

    private func statsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                .padding(.top, 2)
            content()
        }
    }

    private func statRow(_ label: String, value: String, color: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(labelFont)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 62, alignment: .leading)
            Spacer()
            Text(value)
                .font(monoFont)
                .foregroundStyle(color.opacity(0.9))
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
