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
                Circle().strokeBorder(
                    channel.openLive ? DesignTokens.Colors.live : DesignTokens.Colors.border,
                    lineWidth: channel.openLive ? 2 : 0.5
                )
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
                    // 라이브 / 오프라인 상태 배지
                    if channel.openLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.live.gradient)
                        .clipShape(Capsule())
                    } else {
                        Text("오프라인")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.Colors.surfaceElevated)
                            .overlay {
                                Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                            }
                            .clipShape(Capsule())
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
    /// [Redesign 2026-04-29] 검색 결과 행 빠른 액션. nil이면 표시하지 않는다.
    var onAddMultiLive: (() -> Void)? = nil
    var onAddMultiChat: (() -> Void)? = nil
    var onOpenChannel: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    /// 멀티라이브에 이미 추가되어 있는지 (버튼 disabled 표시)
    var isAlreadyInMultiLive: Bool = false
    /// 멀티채팅에 이미 추가되어 있는지
    var isAlreadyInMultiChat: Bool = false
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

            // [Redesign 2026-04-29] 빠른 액션 — hover 시 표시
            if isHovered {
                quickActions
                    .transition(.opacity)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceOverlay.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .contextMenu { contextMenuContent }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if let onAddMultiLive {
                quickActionButton(
                    icon: isAlreadyInMultiLive ? "checkmark.rectangle.stack.fill" : "rectangle.stack.badge.plus",
                    help: isAlreadyInMultiLive ? "멀티라이브에 이미 추가됨" : "멀티라이브에 추가",
                    disabled: isAlreadyInMultiLive,
                    action: onAddMultiLive
                )
            }
            if let onAddMultiChat {
                quickActionButton(
                    icon: isAlreadyInMultiChat ? "bubble.left.fill" : "bubble.left.and.bubble.right",
                    help: isAlreadyInMultiChat ? "멀티채팅에 이미 추가됨" : "멀티채팅에 추가",
                    disabled: isAlreadyInMultiChat,
                    action: onAddMultiChat
                )
            }
            if let onOpenChannel {
                quickActionButton(
                    icon: "person.crop.circle",
                    help: "채널 상세",
                    action: onOpenChannel
                )
            }
        }
    }

    private func quickActionButton(
        icon: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(disabled ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen)
                .frame(width: 26, height: 26)
                .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let onAddMultiLive {
            Button {
                onAddMultiLive()
            } label: {
                Label(isAlreadyInMultiLive ? "멀티라이브에 추가됨" : "멀티라이브에 추가",
                      systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(isAlreadyInMultiLive)
        }
        if let onAddMultiChat {
            Button {
                onAddMultiChat()
            } label: {
                Label(isAlreadyInMultiChat ? "멀티채팅에 추가됨" : "멀티채팅에 추가",
                      systemImage: "bubble.left.and.bubble.right")
            }
            .disabled(isAlreadyInMultiChat)
        }
        if let onOpenChannel {
            Button {
                onOpenChannel()
            } label: {
                Label("채널 상세", systemImage: "person.crop.circle")
            }
        }
        if let onCopyLink {
            Divider()
            Button {
                onCopyLink()
            } label: {
                Label("링크 복사", systemImage: "link")
            }
        }
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

struct EquatableSearchChannelRow: View, Equatable {
    let channel: ChannelInfo
    var body: some View { SearchChannelRow(channel: channel) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.channel == rhs.channel }
}

struct EquatableSearchLiveRow: View, Equatable {
    let live: LiveInfo
    /// [Redesign 2026-04-29] 빠른 액션은 Equatable 비교 대상이 아니다 (closure는 비교 불가).
    /// 외부에서 동일한 row를 매 frame 다시 만들어도 `live`만 같으면 body는 재계산되지 않는다.
    var onAddMultiLive: (() -> Void)? = nil
    var onAddMultiChat: (() -> Void)? = nil
    var onOpenChannel: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    var isAlreadyInMultiLive: Bool = false
    var isAlreadyInMultiChat: Bool = false
    var body: some View {
        SearchLiveRow(
            live: live,
            onAddMultiLive: onAddMultiLive,
            onAddMultiChat: onAddMultiChat,
            onOpenChannel: onOpenChannel,
            onCopyLink: onCopyLink,
            isAlreadyInMultiLive: isAlreadyInMultiLive,
            isAlreadyInMultiChat: isAlreadyInMultiChat
        )
    }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.live == rhs.live
            && lhs.isAlreadyInMultiLive == rhs.isAlreadyInMultiLive
            && lhs.isAlreadyInMultiChat == rhs.isAlreadyInMultiChat
    }
}

struct EquatableSearchVideoRow: View, Equatable {
    let video: VODInfo
    var body: some View { SearchVideoRow(video: video) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.video == rhs.video }
}

struct EquatableSearchClipRow: View, Equatable {
    let clip: ClipInfo
    var body: some View { SearchClipRow(clip: clip) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.clip == rhs.clip }
}
