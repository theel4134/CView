// MARK: - FollowingCardViews.swift
// CViewApp - 팔로잉 채널 카드 컴포넌트
// 라이브 카드 + 오프라인 행 + 스켈레톤 카드

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Live Channel Card (라이브 전용)

@MainActor
struct FollowingLiveCard: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveCard, rhs: FollowingLiveCard) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void
    /// 호버 시 HLS 매니페스트 프리페치를 요청하는 콜백 (channelId 전달)
    var onPrefetch: ((String) -> Void)? = nil

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 이미지 영역 ──────────────────────────────────────────
            // overlay 패턴: 베이스 뷰가 크기를 결정, 배지/hover는 합성만
            // ZStack 내 조건부 분기 제거 → isHovered 토글 시 ZStack 전체 재평가 없음
            imageBase
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)  // 16:9 스트림 썸네일 비율
                .clipped()
                .overlay(alignment: .top) { badgeBar }          // LIVE 배지 + 시청자수 (상단)
                .overlay { if isHovered { hoverLayer } }        // hover 레이어 (독립)
                .overlay(alignment: .bottomLeading) { avatarBadge } // 채널 아바타 (좌하단)

            // ── 정보 영역 ────────────────────────────────────────────
            infoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.live.opacity(0.5) : DesignTokens.Colors.live.opacity(0.12),
                    lineWidth: 0.5
                )
        }
        // scaleEffect 제거 — 전체 카드 재합성 유발
        // shadow(radius:14) 제거 — macOS 고비용 blur 패스
        .opacity(appeared ? 1 : 0)
        .animation(DesignTokens.Animation.fast, value: appeared)
        .animation(DesignTokens.Animation.micro, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onPrefetch?(channel.channelId) }
        }
        .onAppear { appeared = true }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .cursor(.pointingHand)
    }

    // MARK: - Sub-views (분리로 body 재평가 범위 최소화)

    @ViewBuilder
    private var imageBase: some View {
        // 스트림 썸네일(16:9) 우선, 없으면 채널 프로필 이미지 폴백
        let url = [channel.thumbnailUrl, channel.channelImageUrl]
            .lazy.compactMap { $0.flatMap(URL.init) }.first
        if let url {
            CachedAsyncImage(url: url) {
                thumbnailPlaceholder
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        LinearGradient(
            colors: [DesignTokens.Colors.surfaceElevated, DesignTokens.Colors.surfaceBase],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // 채널 아바타 (썸네일 좌하단 고정) — infoArea 공간 절약
    private var avatarBadge: some View {
        CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
            ZStack {
                Circle().fill(DesignTokens.Colors.surfaceElevated)
                Image(systemName: "person.fill")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 1.5))
        .drawingGroup(opaque: false)  // 아바타 원형 클립+스트로크 단일 Metal 패스
        .padding(.leading, DesignTokens.Spacing.sm)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private var badgeBar: some View {
        HStack(alignment: .center) {
            LivePulseBadge()
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "person.fill").font(DesignTokens.Typography.custom(size: 8))
                Text(channel.formattedViewerCount)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.4), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var hoverLayer: some View {
        ZStack {
            Color.black.opacity(0.22)
            Button(action: onPlay) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    Text("바로 시청").font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.Colors.chzzkGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity.animation(DesignTokens.Animation.micro))
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(channel.channelName)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Text(channel.liveTitle)
                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let cat = channel.categoryName {
                HStack {
                    Text(cat)
                        .font(DesignTokens.Typography.microSemibold)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(categoryColor(for: channel.categoryType).opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceBase)
        .drawingGroup(opaque: false)  // 정보 영역 텍스트+뱃지 레이어 단일 Metal 패스
    }

    private func categoryColor(for type: String?) -> Color {
        switch type?.uppercased() {
        case "GAME":   return DesignTokens.Colors.accentPurple
        case "SPORTS": return DesignTokens.Colors.accentBlue
        default:       return DesignTokens.Colors.surfaceElevated
        }
    }
}

// MARK: - Offline Channel Row (컴팩트)

struct FollowingOfflineRow: View, Equatable {
    nonisolated static func == (lhs: FollowingOfflineRow, rhs: FollowingOfflineRow) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            // 아바타 (오프라인 — saturation 제거: GPU ColorSpace 변환 패스 절감)
            CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                ZStack {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .opacity(0.5)  // saturation(0.25) 제거 — opacity만으로 오프라인 dim 표현

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                if let cat = channel.categoryName, !isHovered {
                    Text(cat)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right.circle.fill").font(DesignTokens.Typography.caption)
                    Text("채널 보기").font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .transition(.opacity)  // scale 제거 — geometry 재계산 없이 alpha만
            } else {
                Text("오프라인")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }
        }
        // offset 진입 애니메이션 제거 — geometry 재계산 없이 alpha만 변경
        .opacity(appeared ? 1 : 0)
        .animation(DesignTokens.Animation.fast, value: appeared)
        .animation(DesignTokens.Animation.micro, value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .cursor(.pointingHand)
    }
}

// MARK: - Skeleton Loading Card

struct SkeletonLiveCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(DesignTokens.Colors.surfaceElevated)
                .aspectRatio(16/9, contentMode: .fill)
                .shimmer()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DesignTokens.Radius.md, topTrailingRadius: DesignTokens.Radius.md))

            HStack(spacing: 10) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 34, height: 34)
                    .shimmer()
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(height: 10)
                        .shimmer()
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 80, height: 8)
                        .shimmer()
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceBase)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: DesignTokens.Radius.md, bottomTrailingRadius: DesignTokens.Radius.md))
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Colors.border.opacity(0.5), lineWidth: 0.5)
        }
    }
}
