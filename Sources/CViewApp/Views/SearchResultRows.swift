// MARK: - SearchResultRows.swift
// CViewApp - 검색 결과 행 컴포넌트 (탭 버튼 · 채널/라이브/VOD/클립 행)

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Korean Count Formatter (검색 결과용)

func formatKoreanCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f억", Double(count) / 100_000_000)
    } else if count >= 10_000 {
        return String(format: "%.1f만", Double(count) / 10_000)
    } else if count >= 1_000 {
        return String(format: "%.1f천", Double(count) / 1_000)
    }
    return "\(count)"
}

// MARK: - Search Tab Button

struct SearchTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.caption)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(isSelected ? .black : DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(isSelected ? DesignTokens.Colors.chzzkGreen : Color.clear)
                        .overlay {
                            if !isSelected {
                                Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                            }
                        }
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .overlay {
                            Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.25), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.fast, value: isSelected)
    }
}

// MARK: - Search Result Rows (Premium)

struct SearchChannelRow: View {
    let channel: ChannelInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: 채널 아바타 Circle+stroke → 단일 Metal 텍스처
            CachedAsyncImage(url: channel.channelImageURL) {
                Circle().fill(DesignTokens.Colors.surfaceElevated)
                    .overlay { Image(systemName: "person.fill").foregroundStyle(DesignTokens.Colors.textTertiary) }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if channel.verifiedMark {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.accentBlue)
                    }
                }
                Text("팔로워 \(formatKoreanCount(channel.followerCount))")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceOverlay.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

struct SearchLiveRow: View {
    let live: LiveInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Thumbnail with live badge
            // Metal 3: ZStack(thumbnail + LIVE badge) → 단일 Metal 텍스처
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: live.resolvedLiveImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceElevated)
                        .overlay { Image(systemName: "video").foregroundStyle(DesignTokens.Colors.textTertiary) }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                // Mini LIVE badge
                Text("LIVE")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.live.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .padding(DesignTokens.Spacing.xxs)
            }

            
            VStack(alignment: .leading, spacing: 3) {
                Text(live.liveTitle)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    Text(live.channel?.channelName ?? "")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    if let cat = live.liveCategoryValue {
                        Text(cat)
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.custom(size: 8))
                    Text("\(formatKoreanCount(live.concurrentUserCount))명")
                        .font(DesignTokens.Typography.captionMedium)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceOverlay.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

struct SearchVideoRow: View {
    let video: VODInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: ZStack(thumbnail + duration badge) → 단일 Metal 텍스처
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: video.videoImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                // Duration badge
                Text(video.formattedDuration)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .padding(DesignTokens.Spacing.xxs)
            }

            
            VStack(alignment: .leading, spacing: 3) {
                Text(video.videoTitle)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(video.channel?.channelName ?? "")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                            .font(DesignTokens.Typography.micro)
                        Text(formatKoreanCount(video.readCount))
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceOverlay.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Search Clip Row

struct SearchClipRow: View {
    let clip: ClipInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: ZStack(thumbnail + clip badge) → 단일 Metal 텍스처
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: clip.thumbnailImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceElevated)
                        .overlay { Image(systemName: "film.stack").foregroundStyle(DesignTokens.Colors.textTertiary) }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                HStack(spacing: 2) {
                    Image(systemName: "scissors")
                        .font(DesignTokens.Typography.custom(size: 7))
                    Text(formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                }
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(.horizontal, DesignTokens.Spacing.xxs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                .padding(DesignTokens.Spacing.xxs)
            }

            
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.clipTitle)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(clip.channel?.channelName ?? "")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                            .font(DesignTokens.Typography.micro)
                        Text(formatKoreanCount(clip.readCount))
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceOverlay.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
    
    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Equatable Wrappers (re-render 방지)

struct EquatableSearchChannelRow: View, @preconcurrency Equatable {
    let channel: ChannelInfo
    var body: some View { SearchChannelRow(channel: channel) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.channel == rhs.channel }
}

struct EquatableSearchLiveRow: View, @preconcurrency Equatable {
    let live: LiveInfo
    var body: some View { SearchLiveRow(live: live) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.live == rhs.live }
}

struct EquatableSearchVideoRow: View, @preconcurrency Equatable {
    let video: VODInfo
    var body: some View { SearchVideoRow(video: video) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.video == rhs.video }
}

struct EquatableSearchClipRow: View, @preconcurrency Equatable {
    let clip: ClipInfo
    var body: some View { SearchClipRow(clip: clip) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.clip == rhs.clip }
}
