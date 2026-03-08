// MARK: - PopularClipCards.swift
// CViewApp - 클립 그리드 카드 & 리스트 행 컴포넌트

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

// MARK: - Premium Clip Grid Card

struct ClipGridCard: View {
    let clip: ClipInfo
    var showChannel: Bool = false
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail with overlay on hover
                ZStack(alignment: .bottomTrailing) {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            thumbnailPlaceholder
                        }
                    } else {
                        thumbnailPlaceholder
                    }
                    
                    // Play overlay on hover
                    if isHovered {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Image(systemName: "play.fill")
                                .font(DesignTokens.Typography.custom(size: 26))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .shadow(color: .black.opacity(0.4), radius: 4)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    
                    // Duration badge
                    Text(formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5) }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(DesignTokens.Spacing.xs)
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                
                // Title
                Text(clip.clipTitle)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Meta
                HStack(spacing: 8) {
                    if showChannel, let channel = clip.channel {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.custom(size: 8))
                            Text(channel.channelName)
                                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.9))
                    } else if let channel = clip.channel {
                        Text(channel.channelName)
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(DesignTokens.Typography.custom(size: 8))
                            Text(formattedCount(clip.readCount))
                                .font(DesignTokens.Typography.footnoteMedium)
                        }
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        if let dateStr = relativeDate(clip.createdDate) {
                            Text(dateStr)
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(.ultraThinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(DesignTokens.Colors.surfaceBase.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) { isHovered = hovering }
        }
        .cursor(.pointingHand)
        // Metal 3: hover scaleEffect+동적 shadow 제거 — GPU blur+scale 연산 방지
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            thumbnailPlaceholder
                        }
                        .frame(width: 140, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    } else {
                        thumbnailPlaceholder
                    }
                    
                    // Duration badge
                    Text(formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5) }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(DesignTokens.Spacing.xxs)
                }
                .frame(width: 140, height: 80)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.clipTitle)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                    
                    if let channel = clip.channel {
                        Text(channel.channelName)
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    
                    HStack(spacing: DesignTokens.Spacing.md) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(DesignTokens.Typography.micro)
                            Text(formattedCount(clip.readCount))
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        }
                        
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(DesignTokens.Typography.micro)
                            Text(formattedDuration)
                                .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                        }
                        
                        if let dateStr = relativeDate(clip.createdDate) {
                            Text(dateStr)
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        }
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                
                Spacer()
                
                // Play icon on hover
                if isHovered {
                    Image(systemName: "play.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 22, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.indicator) { isHovered = hovering }
        }
        .cursor(.pointingHand)
    }
    
    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(DesignTokens.Colors.surfaceBase)
            .frame(width: 140, height: 80)
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
