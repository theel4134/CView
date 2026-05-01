// MARK: - MLSingleChannelStage.swift
// 멀티라이브 "탭 모드" 또는 단일 활성 세션을 풀-임베드로 표시하는 스테이지.
// 일반 라이브 메뉴(LiveStreamView) 와 비슷한 풍부한 헤더 오버레이(채널 프로필 + 채널명 + 라이브 제목 + 시청자수)
// 를 제공해 "채널별 싱글 화면" 처럼 보이도록 한다.
//
// MLPlayerPane 위에 자동 페이드 헤더 오버레이를 합성한다.
// 호버 / 탭 시 헤더가 페이드인 → 일정 시간 후 자동 페이드아웃.

import SwiftUI
import CViewCore
import CViewUI
import CViewPlayer

struct MLSingleChannelStage: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    let appState: AppState
    var onShowFollowingSheet: (() -> Void)? = nil

    @State private var isHeaderVisible: Bool = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showSettingsPopover: Bool = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .top) {
            // ── 비디오 영역 (기존 MLPlayerPane 재사용) ──
            MLPlayerPane(session: session, manager: manager, appState: appState, isActive: true,
                         showHoverControls: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // [2026-04-22] 헤더 오버레이 제거 — 탭 칩이 이미 채널 프로필·채널명·LIVE 상태·
            // 라이브 제목·시청자 수를 모두 표시하므로 영상 위 헤더가 중복 겹침의 원인.
        }
        // 싱글 시청 모드: 하단 팔로잉 시트 대신 항상 보이는 컨트롤 바
        .safeAreaInset(edge: .bottom, spacing: 0) {
            singleLiveControlBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - 싱글 시청 컨트롤 바 (하단 고정)

    private var singleLiveControlBar: some View {
        HStack(spacing: 12) {
            // 재생/일시정지
            controlButton(
                icon: session.playerViewModel.streamPhase == .playing ? "pause.fill" : "play.fill",
                help: session.playerViewModel.streamPhase == .playing ? "일시정지" : "재생"
            ) {
                Task { await session.playerViewModel.togglePlayPause() }
            }

            // 음소거 토글
            controlButton(
                icon: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: session.isMuted ? "음소거 해제" : "음소거",
                isActive: !session.isMuted
            ) {
                session.setMuted(!session.isMuted)
            }

            // 볼륨 슬라이더
            if !session.isMuted {
                OverlayVolumeSlider(
                    value: Binding(
                        get: { Double(session.playerViewModel.volume) },
                        set: { session.playerViewModel.setVolume(Float($0)) }
                    ),
                    trackColor: DesignTokens.Colors.chzzkGreen,
                    width: 100
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }

            Spacer(minLength: 0)

            // 통계 토글
            controlButton(
                icon: session.showStats ? "chart.bar.fill" : "chart.bar",
                help: session.showStats ? "통계 숨기기" : "통계 표시",
                isActive: session.showStats
            ) {
                session.showStats.toggle()
            }


            // 영상 설정
            Button {
                showSettingsPopover.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                    .foregroundStyle(showSettingsPopover
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(showSettingsPopover
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                            : DesignTokens.Colors.surfaceElevated.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
            .help("영상 설정")
            .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
                singleLiveSettingsPopover
                    .frame(width: 240)
                    .padding(DesignTokens.Spacing.md)
            }

            // 팔로잉 시트 열기 (채널 전환)
            Button {
                onShowFollowingSheet?()
            } label: {
                Label("채널 전환", systemImage: "rectangle.portrait.and.arrow.up")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("채널 목록에서 전환")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: 48)
        .background(
            ZStack {
                DesignTokens.Colors.surfaceBase
                LinearGradient(
                    colors: [DesignTokens.Colors.chzzkGreen.opacity(0.05), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 0.5)
        }
        .animation(DesignTokens.Animation.fast, value: session.isMuted)
    }

    @ViewBuilder
    private func controlButton(icon: String, help: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(isActive
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                        : DesignTokens.Colors.surfaceElevated.opacity(0.8))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }


    // MARK: - 영상 설정 팝오버

    @ViewBuilder
    private var singleLiveSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("영상 설정")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("재생 품질", systemImage: "slider.horizontal.3")
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("개별 세션 컨트롤은 그리드의 채널 카드 hover 시 표시되는 컨트롤 오버레이를 사용합니다.")
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                settingsWindowButton("네트워크 모니터", icon: "network") {
                    openWindow(id: "ml-network-window")
                    showSettingsPopover = false
                }
                settingsWindowButton("메트릭", icon: "chart.line.uptrend.xyaxis") {
                    openWindow(id: "ml-metrics-window")
                    showSettingsPopover = false
                }
                settingsWindowButton("시스템 사용률 모니터", icon: "cpu") {
                    openWindow(id: "system-usage-window")
                    showSettingsPopover = false
                }
                settingsWindowButton("통계 창", icon: "chart.bar.doc.horizontal") {
                    openWindow(id: "statistics-window")
                    showSettingsPopover = false
                }
            }

            Divider()

            Button {
                Task { await manager.stopAll() }
                showSettingsPopover = false
            } label: {
                Label("모든 채널 해제", systemImage: "xmark.circle")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.live)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func settingsWindowButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }


    // MARK: - Header

    @ViewBuilder
    private var headerOverlay: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            // 채널 프로필
            if let url = session.profileImageURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !session.isOffline {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(DesignTokens.Colors.error)
                            )
                    }
                    Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                        .font(DesignTokens.Typography.custom(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !session.liveTitle.isEmpty {
                    Text(session.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            // 시청자 / 누적
            HStack(spacing: DesignTokens.Spacing.sm) {
                if session.viewerCount > 0 {
                    Label {
                        Text(session.formattedViewerCount)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .help("현재 시청자 수")
                }
                if session.accumulateCount > 0 {
                    Label {
                        Text(session.formattedAccumulateCount)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .rounded))
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .help("누적 시청자 수")
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm + 2)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Auto-hide

    private func showHeader() {
        hideTask?.cancel()
        if !isHeaderVisible {
            withAnimation(DesignTokens.Animation.snappy) {
                isHeaderVisible = true
            }
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DesignTokens.Animation.contentTransition) {
                isHeaderVisible = false
            }
        }
    }
}
