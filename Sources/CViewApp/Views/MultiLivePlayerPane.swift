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

    var body: some View {
        ZStack {
            // 비디오 영역
            videoLayer

            // 오버레이 컨트롤
            if isHovering || isCompact {
                controlOverlay
            }

            // 로딩 / 에러 상태
            stateOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? DesignTokens.Radius.sm : 0))
        .overlay {
            if isSelected && isCompact {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen, lineWidth: 2)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            scheduleHideControls()
        }
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

    // MARK: - 컨트롤 오버레이

    private var controlOverlay: some View {
        VStack {
            // 상단: 채널 정보
            HStack(spacing: DesignTokens.Spacing.xs) {
                AsyncImage(url: session.profileImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: isCompact ? 20 : 28, height: isCompact ? 20 : 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.channelName)
                        .font(isCompact ? .caption : .callout)
                        .fontWeight(.semibold)
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

                // 시청자 수
                if session.loadState == .playing {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                        Text("\(session.viewerCount)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.4)))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, DesignTokens.Spacing.sm)

            Spacer()

            // 하단: 재생 컨트롤
            if !isCompact {
                HStack(spacing: DesignTokens.Spacing.md) {
                    // 음소거 토글
                    Button {
                        session.playerViewModel.toggleMute()
                    } label: {
                        Image(systemName: session.playerViewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // 채팅 토글
                    Button {
                        withAnimation(DesignTokens.Animation.normal) {
                            showChat.toggle()
                        }
                    } label: {
                        Image(systemName: showChat ? "message.fill" : "message")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        )
    }

    // MARK: - 상태 오버레이

    @ViewBuilder
    private var stateOverlay: some View {
        switch session.loadState {
        case .loading:
            ZStack {
                Color.black.opacity(0.3)
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    Text("연결 중...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

        case .error(let message):
            ZStack {
                Color.black.opacity(0.5)
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("재시도") {
                        Task { await session.start() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        case .idle:
            Color.black

        case .playing:
            EmptyView()
        }
    }

    // MARK: - 채팅 패널

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // 채팅 헤더
            HStack {
                Text("\(session.channelName) 채팅")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(.ultraThinMaterial)

            // 채팅 메시지
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
