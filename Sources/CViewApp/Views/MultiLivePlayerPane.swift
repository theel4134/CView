// MARK: - MultiLivePlayerPane.swift
// CViewApp — 멀티라이브 개별 플레이어 패널
// 비디오 + 오버레이 컨트롤

import SwiftUI
import CViewCore
import CViewPlayer

struct MultiLivePlayerPane: View {

    let session: MultiLiveSession
    let isSelected: Bool
    let isCompact: Bool

    @Environment(AppState.self) private var appState
    @State private var isHovering = false
    @State private var hideControlsTask: Task<Void, Never>?

    private var showControls: Bool {
        isHovering && session.loadState == .playing
    }

    var body: some View {
        ZStack {
            videoLayer
            stateOverlay

            if showControls {
                controlOverlay
                    .transition(.opacity)
            }

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
    }

    // MARK: - 비디오 레이어

    private var videoLayer: some View {
        PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
            .background(Color.black)
    }

    // MARK: - 컴팩트 배지

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

    // MARK: - 컨트롤 오버레이

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

            // 하단: 컨트롤
            HStack(spacing: DesignTokens.Spacing.md) {
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

                if isCompact {
                    Button {
                        Task {
                            await appState.multiLiveManager.removeSession(id: session.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
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
