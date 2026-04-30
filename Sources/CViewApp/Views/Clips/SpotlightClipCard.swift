// MARK: - SpotlightClipCard.swift
// CViewApp - 클립 메뉴: 트렌딩 첫 번째 클립을 강조하는 큰 spotlight 카드.
// 2026-04-30 CL-1 Phase 1 분해 — PopularClipsView.swift에서 이전.

import SwiftUI
import AppKit
import CViewCore
import CViewNetworking
import CViewUI



// MARK: - Spotlight Clip Card

/// 트렌딩 첫 번째 클립을 강조하는 큰 카드. 자동재생 없이 큰 thumbnail + play 버튼만 둔다.
/// [2026-04-30 Pass2] 정밀화
///   - 그라디언트 3-스톱(0 → 0.35 → 0.78) 으로 가독성 개선
///   - 좌상단 #1 랭크 배지 + Spotlight 라벨 한 줄로 묶음
///   - 우상단 duration: 글래스 모피즘
///   - 메타 행: pill 형 readCount + 날짜 + 큰 재생 버튼
struct SpotlightClipCard: View {
    let clip: ClipInfo
    let onTap: () -> Void
    let onPlay: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                Group {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) { placeholder }
                    } else {
                        placeholder
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

                // 가독성 보호 그라디언트 — 3 스톱
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0),  location: 0.0),
                        .init(color: .black.opacity(0.18), location: 0.45),
                        .init(color: .black.opacity(0.78), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                // 좌상단: #1 + Spotlight (한 묶음)
                VStack {
                    HStack(spacing: 8) {
                        rankSpotlightBadge
                        Spacer()
                        durationGlassBadge
                    }
                    Spacer()
                }
                .padding(DesignTokens.Spacing.md)
                .allowsHitTesting(false)

                // Title + meta + play (시각적 표시 — 외부 Button 의 onTap 으로 처리됨)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(clip.clipTitle)
                        .font(DesignTokens.Typography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)

                    HStack(spacing: 10) {
                        if let channel = clip.channel {
                            HStack(spacing: 5) {
                                if let chURL = channel.channelImageURL {
                                    CachedAsyncImage(url: chURL) {
                                        Circle().fill(.white.opacity(0.18))
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                    .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.6) }
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(DesignTokens.Typography.caption)
                                }
                                Text(channel.channelName)
                                    .font(DesignTokens.Typography.captionSemibold)
                            }
                            .foregroundStyle(.white.opacity(0.95))
                        }

                        metaPill(icon: "eye.fill", text: formattedCount(clip.readCount))

                        if let dateStr = relativeDate(clip.createdDate) {
                            metaPill(icon: "clock", text: dateStr)
                        }

                        Spacer()

                        // [2026-04-30] nested Button 제거 → 시각적 capsule 만 (외부 onTap 으로 재생)
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("재생")
                                .font(DesignTokens.Typography.captionSemibold)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.chzzkGreen,
                                    DesignTokens.Colors.chzzkGreen.opacity(0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6) }
                        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.45), radius: 8, y: 3)
                    }
                }
                .padding(DesignTokens.Spacing.md)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: 880)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.32)
                            : DesignTokens.Glass.borderColor,
                        lineWidth: 0.6
                    )
            }
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 14 : 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }

    /// #1 + Spotlight 합쳐진 배지
    private var rankSpotlightBadge: some View {
        HStack(spacing: 0) {
            // #1 영역
            HStack(spacing: 3) {
                Text("#")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("1")
                    .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.accentPink,
                        DesignTokens.Colors.accentOrange
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            // Spotlight 영역
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("Spotlight")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55))
        }
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
    }

    private var durationGlassBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .bold))
            Text(formattedDuration)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 9.5))
            Text(text)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.10), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(DesignTokens.Colors.surfaceBase)
            .overlay {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }

    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
