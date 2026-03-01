// MARK: - MultiLiveOverlays.swift
// CViewApp - 멀티라이브 오버레이/컨트롤 뷰
// MultiLivePlayerPane.swift에서 분리

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Grid Control Overlay (셀 전용)
struct MLGridControlOverlay: View {
    let session: MultiLiveSession
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let isFocused: Bool
    var onHideCancel: (() -> Void)? = nil
    var onScheduleHide: (() -> Void)? = nil
    @State private var showQualityPopover = false
    @State private var showAdvancedSettings = false

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    private var isPlaying: Bool {
        session.playerViewModel.playerEngine?.isPlaying ?? false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // [60fps 최적화] 4-stop gradient → 2개의 2-stop gradient로 분할
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
            }
            VStack {
                // 상단: 채널명 + 시청자 + 포커스 버튼
                HStack(spacing: 6) {
                    if case .playing = session.loadState {
                        HStack(spacing: 3) {
                            Circle().fill(DesignTokens.Colors.live).frame(width: 5, height: 5)
                            Text("LIVE").font(DesignTokens.Typography.custom(size: 9, weight: .black)).foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, 2.5)
                        .background(DesignTokens.Colors.live.opacity(0.85))
                        .clipShape(Capsule())
                    }

                    Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                        .font(DesignTokens.Typography.captionSemibold).foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .lineLimit(1)

                    Spacer()

                    if session.viewerCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill").font(DesignTokens.Typography.micro)
                            Text(session.formattedViewerCount).font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, 2.5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                        }
                    }

                    // 포커스 토글 버튼
                    Button {
                        withAnimation(DesignTokens.Animation.indicator) {
                            focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
                        }
                    } label: {
                        Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help(isFocused ? "포커스 해제" : "포커스 확대")
                }
                .padding(.horizontal, DesignTokens.Spacing.md).padding(.top, DesignTokens.Spacing.md)

                Spacer()

                // 하단: 컨트롤
                HStack(spacing: 6) {
                    // 재생/일시정지
                    Button {
                        Task { await session.playerViewModel.togglePlayPause() }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "일시정지" : "재생")

                    // 오디오 라우팅 버튼
                    Button {
                        manager.routeAudio(to: session)
                    } label: {
                        Image(systemName: isAudioActive
                              ? (session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                              : "speaker.zzz.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isAudioActive
                                             ? (session.isMuted ? .orange : DesignTokens.Colors.chzzkGreen)
                                             : .white.opacity(0.6))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(
                                isAudioActive
                                    ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                                    : Color.black.opacity(0.4)
                            ))
                    }
                    .buttonStyle(.plain)
                    .help(isAudioActive ? "현재 오디오 채널" : "이 채널로 오디오 전환")

                    if isAudioActive {
                        HStack(spacing: 5) {
                            Button { session.setMuted(!session.isMuted) } label: {
                                Image(systemName: session.isMuted ? "speaker.slash" : "speaker.fill")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(session.isMuted ? .orange : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

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
                            .frame(width: 70)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .disabled(session.isMuted)
                            .opacity(session.isMuted ? 0.4 : 1)

                            Text("\(Int((session.isMuted ? 0 : session.playerViewModel.volume) * 100))%")
                                .font(DesignTokens.Typography.custom(size: 9, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 26, alignment: .leading)
                        }
                    }

                    Spacer()

                    // 고급 설정
                    Button {
                        onHideCancel?()
                        showAdvancedSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(showAdvancedSettings ? DesignTokens.Colors.chzzkGreen : .white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help("고급 설정")
                    .popover(isPresented: $showAdvancedSettings, arrowEdge: .top) {
                        PlayerAdvancedSettingsView(playerVM: session.playerViewModel, settingsStore: appState.settingsStore)
                    }
                    .onChange(of: showAdvancedSettings) { _, newVal in
                        if !newVal { onScheduleHide?() }
                    }

                    // 통계 토글
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) { session.showStats.toggle() }
                    } label: {
                        Image(systemName: session.showStats ? "chart.bar.xaxis" : "chart.bar")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(session.showStats ? DesignTokens.Colors.chzzkGreen : .white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(
                                session.showStats
                                    ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                                    : .clear
                            ))
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help(session.showStats ? "통계 숨기기" : "통계 보기")

                    // 새로고침
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.refreshStream(using: api, appState: appState) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help("영상 새로고침")

                    // 스크린샷
                    Button {
                        session.playerViewModel.takeScreenshot()
                    } label: {
                        Image(systemName: "camera")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
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
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .help("PiP")

                    // 오프라인/에러 상태에서 재시도 버튼
                    if case .offline = session.loadState {
                        retryButton()
                    } else if case .error = session.loadState {
                        retryButton()
                    }

                    // 화질 선택
                    if let quality = session.playerViewModel.currentQuality {
                        Button {
                            onHideCancel?()
                            showQualityPopover = true
                        } label: {
                            Text(quality.name)
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold)).foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, DesignTokens.Spacing.xxs)
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
                }
                .padding(.horizontal, DesignTokens.Spacing.md).padding(.bottom, DesignTokens.Spacing.md)
            }

            // 통계 오버레이
            if session.showStats {
                MLStatsOverlay(session: session, compact: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private func retryButton() -> some View {
        Button {
            guard let api = appState.apiClient else { return }
            Task { await session.retry(using: api, appState: appState) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.footnoteMedium)
                Text("재시도")
                    .font(DesignTokens.Typography.footnoteMedium)
            }
            .foregroundStyle(DesignTokens.Colors.warning)
            .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.xxs)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

}

