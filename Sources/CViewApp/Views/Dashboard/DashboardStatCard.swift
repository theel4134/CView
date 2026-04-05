// MARK: - DashboardStatCard.swift
// 대시보드 통계 카드 — Minimal Monochrome

import SwiftUI
import CViewCore
import CViewUI

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    var subtitle: String? = nil
    var trend: Int? = nil
    var accentColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(accentColor ?? DesignTokens.Colors.textTertiary)

                Text(title)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(value)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                if let trend {
                    trendBadge(trend)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.footnoteMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .surfaceCard(cornerRadius: DesignTokens.Radius.md, fillColor: DesignTokens.Colors.surfaceElevated)
        .hoverCard(cornerRadius: DesignTokens.Radius.md, scale: 1.015)
    }
    
    @ViewBuilder
    private func trendBadge(_ value: Int) -> some View {
        let isPositive = value >= 0
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
            Text("\(abs(value))%")
                .font(DesignTokens.Typography.captionSemibold)
        }
        .foregroundStyle(isPositive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(
            (isPositive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surfaceElevated)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Mini Channel Card (Dashboard Grid)

struct MiniChannelCard: View {
    let channel: LiveChannelItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                LiveThumbnailView(
                    channelId: channel.channelId,
                    thumbnailUrl: URL(string: channel.thumbnailUrl ?? "")
                )
                .aspectRatio(16/9, contentMode: .fill)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DesignTokens.Radius.sm, topTrailingRadius: DesignTokens.Radius.sm))
                
                // Viewer count + LIVE badge
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .black))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.live)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(DesignTokens.Typography.custom(size: 8))
                        Text(channel.formattedViewerCount)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                }
                .padding(DesignTokens.Spacing.xs)
            }
            
            // Info
            HStack(spacing: DesignTokens.Spacing.xs) {
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(channel.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                    
                    if let cat = channel.categoryName {
                        Text(cat)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.35) : DesignTokens.Glass.borderColor,
                    lineWidth: isHovered ? 1.0 : 0.5
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
    }
}
