// MARK: - MultiLivePlayerPane.swift
// CViewApp — 멀티라이브 개별 플레이어 패널
// 비디오 + 오버레이 컨트롤 + 옵셔널 채팅

import SwiftUI
import CViewCore
import CViewPlayer
import CViewChat

struct MultiLivePlayerPane: View {

    let session: MultiLiveSession
    let isSelected: Bool
    let isCompact: Bool

    @State private var showChat = false
    @State private var isHovering = false
    @State private var hideControlsTask: Task<Void, Never>?

    private var showControls: Bool {
        isHovering && session.loadState == .playing
    }

    var body: some View {
        ZStack {
            // 비디오 영역
            videoLayer

            // 오버레이 (상태별)
            stateOverlay

            // 호버 컨트롤 오버레이
            if showControls {
                controlOverlay
                    .transition(.opacity)
            }

            // 컴팩트 모드: 항상 보이는 채널명 배지
            if isCompact && !showControls {
                compactBadge
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? DesignTokens.Radius.sm : 0))
        .overlay {
            if isSelected && isCompact {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen, lineWidth: 2)
            }
        }
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) {
                isHovering = hovering
            }
            scheduleHideControls()
        }
        .animation(DesignTokens.Animation.fast, value: showControls)
        .inspector(isPresented: $showChat) {
            chatPanel
                .inspectorColumnWidth(min: 240, ideal: 300, max: 400)
        }
    }

    // MARK: - 비디오 레이어

    private var videoLayer: some View {
        PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
            .background(Color.black)
    }

    // MARK: - 컴팩트 배지 (그리드 모드에서 항상 보이는 채널명)

    private var compactBadge: some View {
        VStack {
            HStack {
                HStack(spacing: 4) {
                    if session.loadState == .playing {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 5, height: 5)
                    }
                    Text(session.channelName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.55)))

                Spacer()

                // 음소거 표시
                if session.playerViewModel.isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
            }
            .padding(6)

            Spacer()
        }
    }

    // MARK: - 컨트롤 오버레이 (호버 시)

    private var controlOverlay: some View {
        VStack(spacing: 0) {
            // 상단: 채널 정보
            HStack(spacing: DesignTokens.Spacing.xs) {
                AsyncImage(url: session.profileImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: isCompact ? 20 : 28, height: isCompact ? 20 : 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.channelName)
                        .font(isCompact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !isCompact {
                        Text(session.liveTitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 라이브 배지 + 시청자 수
                if session.loadState == .playing {
                    HStack(spacing: 6) {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))

                        HStack(spacing: 2) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                            Text("\(session.viewerCount)")
                                .font(.system(size: 10).monospacedDigit())
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, isCompact ? 8 : DesignTokens.Spacing.md)
            .padding(.top, isCompact ? 8 : DesignTokens.Spacing.md)

            Spacer()

            // 하단: 재생 컨트롤
            HStack(spacing: DesignTokens.Spacing.md) {
                // 음소거 토글
                Button {
                    session.playerViewModel.toggleMute()
                } label: {
                    Image(systemName: session.playerViewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(isCompact ? .caption : .body)
                        .foregroundStyle(.white)
                        .frame(width: isCompact ? 24 : 32, height: isCompact ? 24 : 32)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)

                Spacer()

                if !isCompact {
                    // 채팅 토글
                    Button {
                        withAnimation(DesignTokens.Animation.spring) {
                            showChat.toggle()
                        }
                    } label: {
                        Image(systemName: showChat ? "message.fill" : "message")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(showChat ? 0.25 : 0.15)))
                    }
                    .buttonStyle(.plain)
                }

                // 제거 버튼
                if isCompact {
                    Button {
                        Task {
                            await appState_manager_removeSession(id: session.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, isCompact ? 8 : DesignTokens.Spacing.md)
            .padding(.bottom, isCompact ? 8 : DesignTokens.Spacing.md)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.5), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    // 세션 제거 helper (compact모드에서만 사용)
    @Environment(AppState.self) private var appState
    private func appState_manager_removeSession(id: UUID) async {
        await appState.multiLiveManager.removeSession(id: id)
    }

    // MARK: - 상태 오버레이

    @ViewBuilder
    private var stateOverlay: some View {
        switch session.loadState {
        case .loading:
            ZStack {
                Color.black.opacity(0.4)
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    Text("연결 중...")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .transition(.opacity)

        case .error(let message):
            ZStack {
                Color.black.opacity(0.6)
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(spacing: 4) {
                        Text("연결 오류")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                    }

                    Button {
                        Task { await session.start() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("재시도")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.small)
                }
            }
            .transition(.opacity)

        case .idle:
            Color.black

        case .playing:
            EmptyView()
        }
    }

    // MARK: - 채팅 패널

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 6, height: 6)
                    Text("\(session.channelName)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(DesignTokens.Animation.spring) {
                        showChat = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                    .frame(height: 0.5)
            }

            ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: {})
        }
    }

    // MARK: - Auto-hide

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard isHovering else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(DesignTokens.Animation.normal) {
                    isHovering = false
                }
            }
        }
    }
}
