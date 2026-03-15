// MARK: - ChannelMediaCards.swift
// CViewApp - 채널 상세용 미디어 카드 뷰 (VOD/클립)
// CompactVODCard, CompactClipCard (정보 탭 가로스크롤용)
// VODCard, ClipCard (VOD/클립 탭 그리드용)

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Compact VOD Card (정보 탭 가로스크롤용)

struct CompactVODCard: View {
    let vod: VODInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: vod.videoImageURL) {
                        Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(DesignTokens.Typography.title3)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .clipped()

                    Text(vod.formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.black.opacity(0.5))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .padding(DesignTokens.Spacing.xs)
                }

                Text(vod.videoTitle)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                HStack(spacing: 3) {
                    Image(systemName: "eye").font(DesignTokens.Typography.micro)
                    Text(vod.readCount.formatted())
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    if let publishDate = vod.publishDate {
                        Text("·").font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        Text(publishDate, style: .relative)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(isHovered ? 1 : 0), lineWidth: 0.5)
            }
            // scaleEffect 제거 — compositingGroup 후 scale은 전체 레이어 재합성 유발
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Compact Clip Card (정보 탭 가로스크롤용)

struct CompactClipCard: View {
    let clip: ClipInfo
    let onTap: () -> Void
    @State private var isHovered = false

    private var formattedDuration: String {
        let total = clip.duration
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .overlay {
                            CachedAsyncImage(url: clip.thumbnailImageURL) {
                                Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                                    .overlay {
                                        Image(systemName: "scissors")
                                            .font(DesignTokens.Typography.title3)
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                    Text(formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.black.opacity(0.5))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .padding(DesignTokens.Spacing.xs)
                    }

                Text(clip.clipTitle)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                HStack(spacing: 3) {
                    Image(systemName: "scissors").font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                    Text(clip.readCount.formatted())
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    if let createdDate = clip.createdDate {
                        Text("·").font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        Text(createdDate, style: .relative)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(isHovered ? 1 : 0), lineWidth: 0.5)
            }
            // scaleEffect 제거 — compositingGroup 후 scale은 전체 레이어 재합성 유발
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Premium VOD Card (VOD 탭용)

struct VODCard: View {
    let vod: VODInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: vod.videoImageURL) {
                        Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(.title2)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .clipped()

                    Text(vod.formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.black.opacity(0.5))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .padding(DesignTokens.Spacing.xs)
                }

                Text(vod.videoTitle)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye").font(DesignTokens.Typography.micro)
                        Text(vod.readCount.formatted())
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                    if let publishDate = vod.publishDate {
                        Text("·")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(DesignTokens.Typography.caption)
                        Text(publishDate, style: .relative)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .opacity(isHovered ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DesignTokens.Animation.fast) { isHovered = h } }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Clip Card

struct ClipCard: View {
    let clip: ClipInfo
    let onTap: () -> Void
    @State private var isHovered = false

    private var formattedDuration: String {

        let total = clip.duration
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .overlay {
                        CachedAsyncImage(url: clip.thumbnailImageURL) {
                            Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                                .overlay {
                                    Image(systemName: "scissors")
                                        .font(.title2)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .overlay(alignment: .bottomTrailing) {
                        // 클립 시간 뱃지
                        Text(formattedDuration)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                            .padding(DesignTokens.Spacing.xs)
                    }
                    .overlay(alignment: .topTrailing) {
                        // 클립 아이콘
                        Image(systemName: "scissors")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.accentOrange)
                            .padding(DesignTokens.Spacing.xs)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(DesignTokens.Spacing.xs)
                    }

                Text(clip.clipTitle)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye").font(DesignTokens.Typography.micro)
                        Text(clip.readCount.formatted())
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                    if let createdDate = clip.createdDate {
                        Text("·")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(DesignTokens.Typography.caption)
                        Text(createdDate, style: .relative)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .opacity(isHovered ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DesignTokens.Animation.fast) { isHovered = h } }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}


// MARK: - Equatable Wrappers (re-render 방지)

struct EquatableCompactVODCard: View, @preconcurrency Equatable {
    let vod: VODInfo
    let onTap: () -> Void
    var body: some View { CompactVODCard(vod: vod, onTap: onTap) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.vod == rhs.vod }
}

struct EquatableCompactClipCard: View, @preconcurrency Equatable {
    let clip: ClipInfo
    let onTap: () -> Void
    var body: some View { CompactClipCard(clip: clip, onTap: onTap) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.clip == rhs.clip }
}

struct EquatableVODCard: View, @preconcurrency Equatable {
    let vod: VODInfo
    let onTap: () -> Void
    var body: some View { VODCard(vod: vod, onTap: onTap) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.vod == rhs.vod }
}

struct EquatableClipCard: View, @preconcurrency Equatable {
    let clip: ClipInfo
    let onTap: () -> Void
    var body: some View { ClipCard(clip: clip, onTap: onTap) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.clip == rhs.clip }
}
