// MARK: - FollowingCardViews.swift
// CViewApp - 팔로잉 채널 카드 컴포넌트
// 모던 플루이드 디자인 — 가벼운 글래스 카드 + 마이크로 인터랙션

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Live Channel Card (Fluid Glass Card)

@MainActor
struct FollowingLiveCard: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveCard, rhs: FollowingLiveCard) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void
    var onPrefetch: ((String) -> Void)? = nil
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .clipped()

            infoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.45)
                        : DesignTokens.Glass.borderColor.opacity(0.35),
                    lineWidth: isHovered ? 1 : 0.5
                )
        }
        .compositingGroup()
        .shadow(
            color: isHovered
                ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                : .black.opacity(0.06),
            radius: isHovered ? 12 : 4,
            y: isHovered ? 5 : 2
        )
        .scaleEffect(isHovered ? 1.02 : (appeared ? 1.0 : 0.96))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onPrefetch?(channel.channelId) }
        }
        .onAppear {
            if !appeared {
                withAnimation(DesignTokens.Animation.cardAppear.delay(Double(index) * 0.04)) {
                    appeared = true
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
    }

    // MARK: - Thumbnail Area

    private var thumbnailURL: URL? {
        if let thumb = channel.thumbnailUrl, !thumb.isEmpty {
            return URL(string: thumb)
        }
        return nil
    }

    private var profileURL: URL? { URL(string: channel.channelImageUrl ?? "") }

    @ViewBuilder
    private var thumbnailArea: some View {
        ZStack {
            DesignTokens.Colors.surfaceElevated

            if let url = thumbnailURL ?? profileURL {
                CachedAsyncImage(url: url) {
                    thumbnailFallback
                }
                .scaledToFill()
                .clipped()
            } else {
                thumbnailFallback
            }

            // 소프트 하단 베일
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: .bottom
                )
                .frame(height: 60)
            }

            // 배지 + 방송 정보 레이아웃
            VStack(spacing: 0) {
                // 상단 배지 바
                HStack(alignment: .top, spacing: 4) {
                    LivePulseBadge()

                    if let openDate = channel.openDate {
                        uptimeBadge(since: openDate)
                    }

                    Spacer()

                    viewerBadge
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                // 하단 방송 정보
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.liveTitle)
                        .font(.system(size: layout.liveTitleFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let cat = channel.categoryName {
                        categoryTag(cat)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 호버 오버레이
            if isHovered { hoverOverlay }
        }
    }

    private var thumbnailFallback: some View {
        ZStack {
            DesignTokens.Colors.surfaceElevated
            Image(systemName: "play.tv")
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.3))
        }
    }

    // MARK: - Viewer Badge (Frosted Pill)

    private var viewerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: layout.viewerIconSize + 1))
            Text(channel.formattedViewerCount)
                .font(.system(size: layout.viewerFontSize + 1, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: - Uptime Badge

    private func uptimeBadge(since date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(date)
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            let text = hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"

            HStack(spacing: 2) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 6))
                Text(text)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    // MARK: - Category Tag

    private func categoryTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: layout.categoryFontSize + 1, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial.opacity(0.7), in: Capsule())
    }

    // MARK: - Hover Overlay

    private var hoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .transition(.opacity)

            VStack(spacing: 10) {
                // 메인: 멀티라이브에 추가
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.split.2x2.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("멀티라이브")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.accentBlue)
                            .shadow(color: DesignTokens.Colors.accentBlue.opacity(0.3), radius: 10, y: 3)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity.animation(DesignTokens.Animation.micro))
    }

    // MARK: - Info Area (채널 정보 — 미니멀 하단 바)

    private var infoArea: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 프로필 아바타
            ZStack(alignment: .bottomTrailing) {
                if let url = profileURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                    }
                    .frame(width: layout.cardProfileSize, height: layout.cardProfileSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            isHovered
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                                : DesignTokens.Glass.borderColor.opacity(0.25),
                            lineWidth: 0.5
                        )
                    )
                }

                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(.system(size: layout.cardNameFontSize, weight: .semibold))
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.textPrimary
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 호버 시 채널 뷰 힌트
            if isHovered {
                Text("클릭: 채널 보기")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: layout.cardInfoHeight + 4, alignment: .leading)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.95))
    }
}

// MARK: - Offline Channel Row (Minimal Hover Row)

struct FollowingOfflineRow: View, Equatable {
    nonisolated static func == (lhs: FollowingOfflineRow, rhs: FollowingOfflineRow) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 프로필
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    ZStack {
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: layout.offlineProfileSize, height: layout.offlineProfileSize)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        DesignTokens.Glass.borderColor.opacity(isHovered ? 0.4 : 0.2),
                        lineWidth: 0.5
                    )
                )
                .drawingGroup()
                .grayscale(isHovered ? 0 : 0.5)
                .opacity(isHovered ? 0.9 : 0.5)

                Circle()
                    .fill(DesignTokens.Colors.textTertiary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(.system(size: layout.offlineNameFontSize, weight: .medium))
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)

                if let cat = channel.categoryName, !cat.isEmpty {
                    Text(cat)
                        .font(.system(size: layout.offlineInfoFontSize, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            ZStack {
                HStack(spacing: 3) {
                    Text("채널 보기")
                        .font(.system(size: layout.offlineInfoFontSize, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: layout.offlineInfoFontSize - 2, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .opacity(isHovered ? 1 : 0)

                Text("오프라인")
                    .font(.system(size: layout.offlineInfoFontSize, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                    .opacity(isHovered ? 0 : 1)
            }
            .animation(DesignTokens.Animation.micro, value: isHovered)
        }
        .padding(.horizontal, layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.md)
        .padding(.vertical, layout.sizeClass == .ultraCompact ? 4 : (layout.sizeClass == .compact ? 6 : 8))
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(
                    isHovered
                        ? DesignTokens.Colors.surfaceElevated.opacity(0.5)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .strokeBorder(
                            isHovered ? DesignTokens.Glass.borderColor.opacity(0.2) : Color.clear,
                            lineWidth: 0.5
                        )
                )
        }
        .opacity(appeared ? 1 : 0)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(DesignTokens.Animation.normal.delay(Double(index) * 0.012)) {
                appeared = true
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        .customCursor(.pointingHand)
    }
}

// MARK: - Skeleton Loading Card (Soft Shimmer)

struct SkeletonLiveCard: View {
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 썸네일 (16:9)
            Rectangle()
                .fill(DesignTokens.Colors.surfaceElevated)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    HStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                            .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.3))
                            .frame(width: 36, height: 13)
                        Spacer()
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                            .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.3))
                            .frame(width: 40, height: 13)
                    }
                    .padding(8)
                }
                .shimmer()

            // 정보 영역
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.3))
                    .frame(width: layout.skeletonProfileSize, height: layout.skeletonProfileSize)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                        .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.3))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                        .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.2))
                        .frame(width: 50, height: 8)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: layout.cardInfoHeight, alignment: .leading)
            .background(DesignTokens.Colors.surfaceBase.opacity(0.85))
            .shimmer()
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColor.opacity(0.3), lineWidth: 0.5)
        }
        .drawingGroup()
    }
}
