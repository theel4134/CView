// MARK: - LiveStreamHeader.swift
// CViewApp — 싱글라이브 재생 화면 in-app 헤더
// 멀티라이브 (MLTabBar + MLSessionInfoBar) 와 동일한 디자인 토큰/레이아웃 사용
//
// 구성:
//   - SLTabBar       : 높이 40, MLTabBar와 동일한 surfaceBase 배경 + 하단 그라데이션 디바이더
//                      좌측: SLChannelChip (현재 재생 채널 정보)
//                      우측: SLToolButton 들 (즐겨찾기, 채팅모드, 새창, 디버그, 설정)
//   - SLSessionInfoBar : 채널명 · 라이브 제목 · 시청자수 · 업타임
//                       MLSessionInfoBar 와 동일 디자인

import SwiftUI
import CViewCore
import CViewPlayer
import CViewChat

// MARK: - SLTabBar (Single Live Tab Bar)

/// 싱글라이브 재생 화면 상단 in-app 탭바.
/// MLTabBar 와 동일한 시각 토큰(surfaceBase, height=40, bottom gradient divider, shadow) 사용.
struct SLTabBar: View {
    let channelName: String
    let liveTitle: String
    let isFavorite: Bool
    let chatDisplayMode: ChatDisplayMode
    let isDebugOverlayOn: Bool
    let isSettingsOpen: Bool
    let isPiPActive: Bool

    let onToggleFavorite: () -> Void
    let onCycleChatMode: () -> Void
    let onOpenNewWindow: () -> Void
    let onToggleDebug: () -> Void
    let onToggleSettings: () -> Void
    let onTogglePiP: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            channelChip
            Spacer(minLength: DesignTokens.Spacing.sm)
            toolGroup
        }
        .frame(height: 40)
        .background { DesignTokens.Colors.surfaceBase }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
        // [Depth] 멀티라이브 MLTabBar 와 동일한 헤더 그림자
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    // MARK: Channel Chip (현재 채널 — MLTabChip 단순 버전)

    private var channelChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(
                    colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 4, y: 1)

            Text(channelName.isEmpty ? "재생 중" : channelName)
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.10))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.30), lineWidth: 1.0)
        }
        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.10), radius: 4, y: 1)
        .padding(.leading, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: Tool Group

    private var toolGroup: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            SLToolButton(
                icon: isFavorite ? "star.fill" : "star",
                isActive: isFavorite,
                tint: isFavorite ? .yellow : nil,
                help: "즐겨찾기"
            ) { onToggleFavorite() }

            SLToolButton(
                icon: chatIconName,
                isActive: chatDisplayMode != .hidden,
                help: chatHelpText
            ) { onCycleChatMode() }

            SLToolButton(
                icon: isPiPActive ? "pip.exit" : "pip.enter",
                isActive: isPiPActive,
                help: "PiP (화면 속 화면)"
            ) { onTogglePiP() }

            SLToolButton(
                icon: "rectangle.on.rectangle",
                isActive: false,
                help: "새 창에서 재생"
            ) { onOpenNewWindow() }

            slDivider

            SLToolButton(
                icon: isDebugOverlayOn
                    ? "gauge.open.with.lines.needle.33percent.badge.arrow.down"
                    : "gauge.open.with.lines.needle.33percent",
                isActive: isDebugOverlayOn,
                help: "성능 오버레이"
            ) { onToggleDebug() }

            SLToolButton(
                icon: isSettingsOpen ? "gearshape.fill" : "gearshape",
                isActive: isSettingsOpen,
                help: "재생 설정"
            ) { onToggleSettings() }
        }
        .padding(.trailing, DesignTokens.Spacing.sm)
    }

    private var chatIconName: String {
        switch chatDisplayMode {
        case .side:    return "bubble.left.and.bubble.right.fill"
        case .overlay: return "bubble.left.and.text.bubble.right.fill"
        case .hidden:  return "bubble.left.and.bubble.right"
        }
    }

    private var chatHelpText: String {
        switch chatDisplayMode {
        case .side:    return "채팅: 사이드 모드 (클릭: 오버레이)"
        case .overlay: return "채팅: 오버레이 모드 (클릭: 숨김)"
        case .hidden:  return "채팅: 숨김 (클릭: 사이드)"
        }
    }

    private var slDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColorLight)
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, DesignTokens.Spacing.xxs)
    }
}

// MARK: - SLToolButton (MLToolButton 과 동일 스펙 · 외부 접근용 별도 타입)

struct SLToolButton: View {
    let icon: String
    let isActive: Bool
    var tint: Color? = nil
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(
                    tint
                        ?? (isActive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                )
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill((tint ?? DesignTokens.Colors.chzzkGreen).opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder((tint ?? DesignTokens.Colors.chzzkGreen).opacity(0.15), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(0.3))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - SLSessionInfoBar (MLSessionInfoBar 와 동일 디자인)

/// 싱글라이브 정보 바 — SLTabBar 아래에 표시.
/// 채널명 · 라이브 제목 · 시청자수 · 업타임 · 엔진 배지.
/// MLSessionInfoBar 와 동일한 surfaceBase 배경 + 하단 디바이더 사용.
struct SLSessionInfoBar: View {
    let channelName: String
    let liveTitle: String
    let viewerCount: Int
    let formattedViewerCount: String
    let uptime: String
    let isMuted: Bool
    let engineType: PlayerEngineType

    var body: some View {
        HStack(spacing: 6) {
            // 오디오 활성/뮤트 표시
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(isMuted ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen)

            Text(channelName.isEmpty ? "재생 준비 중" : channelName)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            if !liveTitle.isEmpty {
                Text("·")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(liveTitle)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // 엔진 배지 (compact)
            HStack(spacing: 3) {
                Circle()
                    .fill(engineAccent)
                    .frame(width: 5, height: 5)
                Text(engineLabel)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .help("재생 엔진")

            if viewerCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "eye.fill")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                    Text(formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .help("현재 시청자 수")
            }

            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(DesignTokens.Typography.custom(size: 8, weight: .medium))
                Text(uptime)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.85))
            .help("재생 경과 시간")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor.opacity(0.2))
                .frame(height: 0.5)
        }
    }

    private var engineLabel: String {
        switch engineType {
        case .vlc:      "VLC"
        case .avPlayer: "AV"
        case .hlsjs:    "HLS.js"
        }
    }

    private var engineAccent: Color {
        switch engineType {
        case .vlc:      Color(red: 1.0, green: 0.55, blue: 0.0)
        case .avPlayer: Color(red: 0.24, green: 0.52, blue: 1.0)
        case .hlsjs:    Color(red: 0.0, green: 0.78, blue: 0.55)
        }
    }
}
