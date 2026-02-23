// MARK: - MenuBarView.swift
// CViewApp - 프리미엄 메뉴바 팝업 뷰 (MenuBarExtra용)
// Design: 컴팩트 + 프리미엄 메뉴바 위젯

import SwiftUI
import CViewCore

/// 메뉴바에서 팔로잉 스트리머 온라인 상태를 보여주는 뷰
struct MenuBarView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branded header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DesignTokens.Gradients.primary)
                        .frame(width: 20, height: 20)
                    
                    Text("C")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black)
                }
                
                Text("CView")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                if let lastUpdated = appState.backgroundUpdateService.lastUpdated {
                    Text(lastUpdated, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                if appState.backgroundUpdateService.isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.backgroundDark)

            // Accent separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Online channels
            let onlineChannels = appState.backgroundUpdateService.onlineChannels

            if onlineChannels.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text(appState.isLoggedIn
                         ? "현재 방송 중인 팔로잉 채널이 없습니다"
                         : "로그인하면 팔로잉 채널을 확인할 수 있습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                // Online count badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 6, height: 6)
                    
                    Text("\(onlineChannels.count)개 채널 방송 중")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, 4)
                
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(onlineChannels) { channel in
                            MenuBarChannelRow(channel: channel)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 400)
            }

            // Separator
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 1)
                .padding(.horizontal, DesignTokens.Spacing.sm)

            // Footer actions
            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    if let apiClient = appState.apiClient {
                        Task {
                            await appState.backgroundUpdateService.refresh(apiClient: apiClient)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("새로고침")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow || $0.isMainWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 10, weight: .semibold))
                        Text("앱 열기")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .frame(width: 320)
        .background(DesignTokens.Colors.backgroundElevated)
    }
}

// MARK: - Menu Bar Channel Row

struct MenuBarChannelRow: View {
    let channel: OnlineChannel
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    var body: some View {
        Button {
            openWindow(id: "player-window", value: channel.channelId)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // Live indicator with pulse animation
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.live.opacity(pulseOpacity))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulseScale)

                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 7, height: 7)
                        .shadow(color: DesignTokens.Colors.live.opacity(0.7), radius: 3)
                }
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.6
                        pulseOpacity = 0.0
                    }
                }
                // pulse 레이어를 Metal 오프스크린으로 합성
                .drawingGroup(opaque: false)

                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.channelName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Text(channel.liveTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Viewer count badge
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                    Text(channel.formattedViewerCount)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignTokens.Colors.surface.opacity(0.5))
                .clipShape(Capsule())
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
