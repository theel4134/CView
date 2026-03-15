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
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Gradients.primary)
                        .frame(width: 20, height: 20)
                    
                    Text("C")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .black))
                        .foregroundStyle(DesignTokens.Colors.onPrimary)
                }
                
                Text("CView")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                if let lastUpdated = appState.backgroundUpdateService.lastUpdated {
                    Text(lastUpdated, style: .relative)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
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
            .background(DesignTokens.Colors.background)

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
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text(appState.isLoggedIn
                         ? "현재 방송 중인 팔로잉 채널이 없습니다"
                         : "로그인하면 팔로잉 채널을 확인할 수 있습니다")
                        .font(DesignTokens.Typography.caption)
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
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.xxs)
                
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(onlineChannels) { channel in
                            MenuBarChannelRow(channel: channel)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
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
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        Text("새로고침")
                            .font(DesignTokens.Typography.captionMedium)
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
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        Text("앱 열기")
                            .font(DesignTokens.Typography.captionMedium)
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

    var body: some View {
        Button {
            openWindow(id: "player-window", value: channel.channelId)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // Live indicator with pulse animation
                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Text(channel.liveTitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Viewer count badge
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.custom(size: 8))
                    Text(channel.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.surfaceElevated)
                .clipShape(Capsule())
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .customCursor(.pointingHand)
    }
}
