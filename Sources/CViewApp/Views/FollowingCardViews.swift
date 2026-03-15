// MARK: - FollowingCardViews.swift
// CViewApp - 팔로잉 채널 카드 컴포넌트
// 치지직 스타일 라이브 카드 + 모던 오프라인 카드 + 스켈레톤

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Live Channel Card (Chzzk-Style Rich Card)

@MainActor
struct FollowingLiveCard: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveCard, rhs: FollowingLiveCard) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void
    var onPrefetch: ((String) -> Void)? = nil

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 썸네일 영역 (16:9)
            thumbnailArea
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .clipped()

            // ── 정보 영역
            infoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Glass.borderColor,
                    lineWidth: isHovered ? 1.2 : 0.5
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onPrefetch?(channel.channelId) }
        }
        .onAppear {
            if !appeared { appeared = true }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .customCursor(.pointingHand)
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

            // 메인 이미지 (썸네일 우선, 없으면 프로필)
            if let url = thumbnailURL ?? profileURL {
                CachedAsyncImage(url: url) {
                    thumbnailFallback
                }
                .scaledToFill()
                .clipped()
            } else {
                thumbnailFallback
            }

            // 하단 그라디언트 (단순화 — 2 stop)
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            // ── 오버레이 배지 레이아웃
            VStack(spacing: 0) {
                // 상단: LIVE + 시청자 + 방송 시간
                HStack(alignment: .top, spacing: 4) {
                    LivePulseBadge()

                    if let openDate = channel.openDate {
                        uptimeBadge(since: openDate)
                    }

                    Spacer()

                    viewerBadge
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.sm)

                Spacer()

                // 하단: 방송 제목 + 카테고리 (썸네일 위에 직접 표시)
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.liveTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let cat = channel.categoryName {
                        categoryTag(cat)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── 호버 오버레이
            if isHovered { hoverOverlay }
        }
    }

    private var thumbnailFallback: some View {
        ZStack {
            DesignTokens.Colors.surfaceElevated
            Image(systemName: "play.tv")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.35))
        }
    }

    // MARK: - Viewer Badge (Glass Pill)

    private var viewerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill")
                .font(.system(size: 7))
            Text(channel.formattedViewerCount)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
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
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    // MARK: - Category Tag

    private func categoryTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(.black.opacity(0.4), in: Capsule())
    }

    // MARK: - Hover Overlay

    private var hoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)

            VStack(spacing: 8) {
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("시청하기")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.2), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity.animation(.easeOut(duration: 0.15)))
    }

    // MARK: - Info Area (채널 정보 - 심플 하단 바)

    private var infoArea: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 프로필 아바타 (라이브 링)
            ZStack(alignment: .bottomTrailing) {
                if let url = profileURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            DesignTokens.Colors.chzzkGreen.opacity(isHovered ? 0.6 : 0.35),
                            lineWidth: 1.5
                        )
                    )
                }

                // 라이브 점
                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            // 채널명
            Text(channel.channelName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.textPrimary
                )
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm + 2)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(DesignTokens.Colors.surfaceBase)
    }
}

// MARK: - Offline Channel Row (Modern Compact Card)

struct FollowingOfflineRow: View, Equatable {
    nonisolated static func == (lhs: FollowingOfflineRow, rhs: FollowingOfflineRow) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 프로필 아바타 (오프라인 링 + 상태 점)
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    ZStack {
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        isHovered
                            ? DesignTokens.Colors.textSecondary.opacity(0.5)
                            : DesignTokens.Colors.border.opacity(0.35),
                        lineWidth: 1
                    )
                )
                .saturation(isHovered ? 0.9 : 0.35)
                .opacity(isHovered ? 0.95 : 0.55)

                // 오프라인 상태 점
                Circle()
                    .fill(DesignTokens.Colors.textTertiary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            // 채널 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.channelName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)

                if let cat = channel.categoryName, !cat.isEmpty {
                    Text(cat)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 호버: 채널 보기 / 기본: 오프라인 텍스트
            Group {
                if isHovered {
                    HStack(spacing: 4) {
                        Text("채널 보기")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
                } else {
                    Text("오프라인")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isHovered)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(
                    isHovered
                        ? DesignTokens.Colors.surfaceElevated.opacity(0.5)
                        : Color.clear
                )
        }
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25).delay(Double(index) * 0.015)) {
                appeared = true
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .customCursor(.pointingHand)
    }
}

// MARK: - Skeleton Loading Card (Modern Shimmer)

struct SkeletonLiveCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 썸네일 영역 (16:9)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .aspectRatio(16/9, contentMode: .fit)
                    .shimmer()

                // 가짜 배지 위치
                HStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceOverlay)
                        .frame(width: 38, height: 14)
                        .shimmer()
                    Spacer()
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                        .fill(DesignTokens.Colors.surfaceOverlay)
                        .frame(width: 42, height: 14)
                        .shimmer()
                }
                .padding(DesignTokens.Spacing.sm)
            }

            // 정보 영역
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 28, height: 28)
                    .shimmer()

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(height: 11)
                        .shimmer()
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 60, height: 8)
                        .shimmer()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm + 2)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(DesignTokens.Colors.surfaceBase)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
}
