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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor ?? DesignTokens.Colors.textTertiary)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.numericText())

                Spacer()

                if let trend {
                    trendBadge(trend)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
        }
    }
    
    @ViewBuilder
    private func trendBadge(_ value: Int) -> some View {
        let isPositive = value >= 0
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(abs(value))%")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isPositive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            (isPositive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surfaceLight)
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
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.live)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                        Text(channel.formattedViewerCount)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                }
                .padding(6)
            }
            
            // Info
            HStack(spacing: DesignTokens.Spacing.xs) {
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    Circle().fill(DesignTokens.Colors.surfaceLight)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.channelName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(channel.liveTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                    
                    if let cat = channel.categoryName {
                        Text(cat)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : DesignTokens.Colors.border.opacity(0.3),
                    lineWidth: 0.5
                )
        }
        // Metal 3: hover scaleEffect 제거 — GPU texture scale 연산 방지
        .drawingGroup(opaque: false)  // 카드 내부 레이어 단일 Metal 패스
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
