// MARK: - PopularClipCards.swift
// CViewApp - 클립 그리드 카드 & 리스트 행 컴포넌트
// 2026-04-30 정밀 리디자인 (Pass 2)
//   - 풀오버레이 hover 제거 → 정중앙 미니 재생 버튼 + 다크닝 그라디언트
//   - duration 배지: 글래스 모피즘 + 모노스페이스 조합
//   - 메타 라인: 좌→우 시각 흐름으로 재구성 (채널 / 조회수 · 날짜)
//   - 리스트 행: 채널 아바타 inline + 트레일링 chevron 일관화
//   - 모든 hover 전환 DesignTokens.Animation.fast 로 통일

import SwiftUI
import CViewCore
import CViewUI

// MARK: - 숫자 포맷 유틸 (클립 전용)

func formattedCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f억", Double(count) / 100_000_000)
    } else if count >= 10_000 {
        return String(format: "%.1f만", Double(count) / 10_000)
    } else if count >= 1_000 {
        return String(format: "%.1f천", Double(count) / 1_000)
    } else {
        return "\(count)"
    }
}

func relativeDate(_ date: Date?) -> String? {
    guard let date else { return nil }
    let now = Date()
    let diff = Int(now.timeIntervalSince(date))
    if diff < 60 { return "방금 전" }
    if diff < 3600 { return "\(diff / 60)분 전" }
    if diff < 86400 { return "\(diff / 3600)시간 전" }
    if diff < 604800 { return "\(diff / 86400)일 전" }
    if diff < 2_592_000 { return "\(diff / 604800)주 전" }
    if diff < 31_536_000 { return "\(diff / 2_592_000)개월 전" }
    return "\(diff / 31_536_000)년 전"
}

// MARK: - 공용 미니 재생 버튼

private struct MiniPlayBadge: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.black)
                .offset(x: size * 0.04)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Premium Clip Grid Card

struct ClipGridCard: View {
    let clip: ClipInfo
    var showChannel: Bool = false
    /// [2026-04-30 Phase1] 인스펙터에서 현재 선택된 클립 강조 표시.
    var isSelected: Bool = false
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnailLayer
                metaLayer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(isHovered
                          ? DesignTokens.Colors.surfaceElevated
                          : DesignTokens.Colors.surfaceBase.opacity(0.30))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? DesignTokens.Colors.chzzkGreen
                            : (isHovered
                               ? DesignTokens.Colors.chzzkGreen.opacity(0.32)
                               : DesignTokens.Glass.borderColorLight.opacity(0.30)),
                        lineWidth: isSelected ? 1.4 : (isHovered ? 0.8 : 0.5)
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 8, height: 8)
                        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1) }
                        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.6), radius: 4)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .shadow(
            color: .black.opacity(isHovered ? 0.16 : 0.08),
            radius: isHovered ? 8 : 4,
            x: 0, y: isHovered ? 4 : 2
        )
    }

    // MARK: thumbnail

    private var thumbnailLayer: some View {
        ZStack {
            Group {
                if let url = clip.thumbnailImageURL {
                    CachedAsyncImage(url: url) { thumbnailPlaceholder }
                } else {
                    thumbnailPlaceholder
                }
            }
            .aspectRatio(16/9, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .clipped()

            // hover 시 가독성 보호용 다크닝 그라디언트
            if isHovered {
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // hover 시 정중앙 미니 재생 버튼
            if isHovered {
                MiniPlayBadge(size: 40)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // 좌상단: 길이 (모든 상태)
            VStack {
                HStack {
                    durationBadge
                    Spacer()
                }
                Spacer()
            }
            .padding(DesignTokens.Spacing.xs)
            .allowsHitTesting(false)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
    }

    private var durationBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
            Text(formattedDuration)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.62), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    // MARK: meta

    private var metaLayer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(clip.clipTitle)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32, alignment: .top)

            HStack(spacing: 6) {
                if showChannel, let channel = clip.channel {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(DesignTokens.Typography.custom(size: 8))
                        Text(channel.channelName)
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.92))
                } else if let channel = clip.channel {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Image(systemName: "eye.fill")
                        .font(DesignTokens.Typography.custom(size: 8))
                    Text(formattedCount(clip.readCount))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)

                if let dateStr = relativeDate(clip.createdDate) {
                    Text("·")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
                    Text(dateStr)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(DesignTokens.Colors.surfaceBase)
            .aspectRatio(16/9, contentMode: .fill)
            .overlay {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }

    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Premium Clip List Row

struct ClipListRow: View {
    let clip: ClipInfo
    /// [2026-04-30 Phase1] 인스펙터 선택 상태 표시.
    var isSelected: Bool = false
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // Thumbnail
                ZStack {
                    Group {
                        if let url = clip.thumbnailImageURL {
                            CachedAsyncImage(url: url) { thumbnailPlaceholder }
                        } else {
                            thumbnailPlaceholder
                        }
                    }
                    .frame(width: 144, height: 81)
                    .clipped()

                    if isHovered {
                        LinearGradient(
                            colors: [.black.opacity(0.0), .black.opacity(0.42)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                        MiniPlayBadge(size: 30)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formattedDuration)
                                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.62), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(4)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: 144, height: 81)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.25), lineWidth: 0.5)
                }

                // Info
                VStack(alignment: .leading, spacing: 5) {
                    Text(clip.clipTitle)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)

                    if let channel = clip.channel {
                        HStack(spacing: 5) {
                            if let chURL = channel.channelImageURL {
                                CachedAsyncImage(url: chURL) {
                                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                                }
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                                .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.4), lineWidth: 0.5) }
                            }
                            Text(channel.channelName)
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(DesignTokens.Typography.micro)
                            Text(formattedCount(clip.readCount))
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        }
                        if let dateStr = relativeDate(clip.createdDate) {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(DesignTokens.Typography.micro)
                                Text(dateStr)
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            }
                        }
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Spacer(minLength: 8)

                // 트레일링: hover 시 chevron 표시
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.chzzkGreen
                            : Color.clear
                    )
                    .frame(width: 16)
                    .animation(DesignTokens.Animation.fast, value: isHovered)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs + 1)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(isHovered ? DesignTokens.Colors.surfaceElevated : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? DesignTokens.Colors.chzzkGreen
                            : (isHovered
                               ? DesignTokens.Colors.chzzkGreen.opacity(0.20)
                               : Color.clear),
                        lineWidth: isSelected ? 1.2 : 0.6
                    )
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(DesignTokens.Colors.surfaceBase)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }

    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Equatable Wrappers (re-render 방지)

/// ClipGridCard — clip.id + readCount + isSelected가 동일하면 re-render 스킵
struct EquatableClipGridCard: View, Equatable {
    let clip: ClipInfo
    let showChannel: Bool
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        ClipGridCard(clip: clip, showChannel: showChannel, isSelected: isSelected, onTap: onTap)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clip.id == rhs.clip.id &&
        lhs.clip.readCount == rhs.clip.readCount &&
        lhs.showChannel == rhs.showChannel &&
        lhs.isSelected == rhs.isSelected
    }
}

/// ClipListRow — clip.id + readCount + isSelected가 동일하면 re-render 스킵
struct EquatableClipListRow: View, Equatable {
    let clip: ClipInfo
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        ClipListRow(clip: clip, isSelected: isSelected, onTap: onTap)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clip.id == rhs.clip.id &&
        lhs.clip.readCount == rhs.clip.readCount &&
        lhs.isSelected == rhs.isSelected
    }
}
