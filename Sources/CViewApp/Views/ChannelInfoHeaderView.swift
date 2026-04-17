// MARK: - ChannelInfoHeaderView.swift
// CViewApp - 채널 상세 정보 히어로 헤더 + 퀵 액션 바

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Hero Header

struct ChannelInfoHeroHeader: View {
    let channelInfo: ChannelInfo
    let liveInfo: LiveInfo?

    private var isLive: Bool { liveInfo != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 배너 배경 — 라이브 썸네일 or 그라데이션
            bannerBackground

            // 하단 그라데이션 오버레이
            LinearGradient(
                colors: [.clear, DesignTokens.Colors.background.opacity(0.7), DesignTokens.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )

            // 채널 메타 정보
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.md) {
                // 아바타
                ZStack {
                    if isLive {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [DesignTokens.Colors.live, DesignTokens.Colors.accentOrange],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 98, height: 98)
                    } else {
                        Circle()
                            .strokeBorder(DesignTokens.Colors.border, lineWidth: 2)
                            .frame(width: 98, height: 98)
                    }
                    CachedAsyncImage(url: channelInfo.channelImageURL) {
                        ZStack {
                            Circle().fill(DesignTokens.Colors.surfaceElevated)
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.custom(size: 32))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                }

                // 채널명 + 배지 + 팔로워
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(channelInfo.channelName)
                            .font(DesignTokens.Typography.titleSemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .shadow(color: .black.opacity(0.5), radius: 4)

                        if channelInfo.verifiedMark {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(DesignTokens.Colors.accentBlue)
                                .font(DesignTokens.Typography.custom(size: 15))
                        }
                    }

                    HStack(spacing: 8) {
                        // 라이브 / 오프라인 상태 배지
                        if isLive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .black))
                                    .foregroundStyle(Color.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.live.gradient)
                            .clipShape(Capsule())
                            .shadow(color: DesignTokens.Colors.live.opacity(0.5), radius: 4)
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(DesignTokens.Colors.textTertiary)
                                    .frame(width: 6, height: 6)
                                Text("OFFLINE")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .black))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.surfaceElevated.opacity(0.85))
                            .overlay {
                                Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                            }
                            .clipShape(Capsule())
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            Text("팔로워 \(formatChannelNumber(channelInfo.followerCount))")
                                .font(DesignTokens.Typography.captionMedium)
                        }
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .frame(height: 200)
        .clipped()
    }

    @ViewBuilder
    private var bannerBackground: some View {
        if let live = liveInfo, let thumbURL = live.liveImageURL ?? live.defaultThumbnailImageURL {
            CachedAsyncImage(url: thumbURL) {
                LinearGradient(
                    colors: [DesignTokens.Colors.chzzkGreen.opacity(0.25), DesignTokens.Colors.background],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 8)
            .scaleEffect(1.05)
            .drawingGroup(opaque: true)
        } else {
            LinearGradient(
                colors: [DesignTokens.Colors.surfaceBase, DesignTokens.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

// MARK: - Quick Action Bar

struct ChannelInfoQuickActionBar: View {
    let channelId: String
    let liveInfo: LiveInfo?
    @Binding var isFavorite: Bool
    let channelMemo: String
    @Binding var showMemoSheet: Bool
    let onToggleFavorite: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            // 라이브 시청
            if liveInfo != nil {
                quickActionButton(
                    title: "바로 시청",
                    icon: "play.fill",
                    color: DesignTokens.Colors.chzzkGreen,
                    style: .filled
                ) {
                    router.navigate(to: .live(channelId: channelId))
                }

                quickActionButton(
                    title: "채팅만 보기",
                    icon: "bubble.left.fill",
                    color: DesignTokens.Colors.accentBlue,
                    style: .outlined
                ) {
                    router.navigate(to: .chatOnly(channelId: channelId))
                }
            }

            // 즐겨찾기
            quickActionButton(
                title: isFavorite ? "즐겨찾기됨" : "즐겨찾기",
                icon: isFavorite ? "star.fill" : "star",
                color: .yellow,
                style: isFavorite ? .tinted : .outlined
            ) {
                onToggleFavorite()
            }

            // 치지직에서 열기
            quickActionButton(
                title: "치지직 열기",
                icon: "arrow.up.right.square",
                color: DesignTokens.Colors.textSecondary,
                style: .outlined
            ) {
                if let url = URL(string: "https://chzzk.naver.com/\(channelId)") {
                    NSWorkspace.shared.open(url)
                }
            }

            // 메모
            quickActionButton(
                title: channelMemo.isEmpty ? "메모" : "메모 있음",
                icon: channelMemo.isEmpty ? "note.text" : "note.text.badge.plus",
                color: .orange,
                style: channelMemo.isEmpty ? .outlined : .tinted
            ) {
                showMemoSheet = true
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    // MARK: - Quick Action Style

    private enum QuickActionStyle { case filled, outlined, tinted }

    private func quickActionButton(
        title: String, icon: String, color: Color,
        style: QuickActionStyle, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionSemibold)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .foregroundStyle(style == .filled ? .black : color)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background {
                switch style {
                case .filled:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(color)
                case .outlined:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                        }
                case .tinted:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(color.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
