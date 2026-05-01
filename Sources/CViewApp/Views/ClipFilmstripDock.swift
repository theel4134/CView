// MARK: - ClipFilmstripDock.swift
// CViewApp - 클립 메뉴 하단 도크 (Phase 4: 재생 큐 + 나중에 보기 상시 노출)
// 2026-04-30 정밀 리디자인 §3.7
//
// 디자인 규칙 (문서 기준):
//   - 큐가 비어있고 저장도 비어있으면 부모에서 dock 자체를 숨긴다 → 항상 표시될 때
//     높이 84-104pt 유지.
//   - 좌측 헤더 + 가로 썸네일 스트립 + 우측 액션
//   - 팝오버는 보조 (전체 관리), 도크는 빠른 접근 + 진행 상태 표시

import SwiftUI
import CViewCore
import CViewUI

struct ClipFilmstripDock: View {
    let queueClips: [ClipInfo]
    let watchLaterClips: [ClipInfo]
    let onPlay: (ClipInfo) -> Void
    let onPreview: (ClipInfo) -> Void
    let onRemoveFromQueue: (ClipInfo) -> Void
    let onClearQueue: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            // ── 헤더 라벨 + 카운트
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "list.and.film")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("클립 도크")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                Text(summary)
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            // ── divider
            Rectangle()
                .fill(DesignTokens.Glass.borderColorLight.opacity(0.5))
                .frame(width: 1, height: 56)

            // ── 큐 / 저장 가로 strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !queueClips.isEmpty {
                        sectionLabel("재생 큐", color: DesignTokens.Colors.chzzkGreen)
                        ForEach(Array(queueClips.enumerated()), id: \.element.clipUID) { idx, clip in
                            FilmstripThumb(
                                clip: clip,
                                position: idx + 1,
                                accent: DesignTokens.Colors.chzzkGreen,
                                onPlay: { onPlay(clip) },
                                onPreview: { onPreview(clip) },
                                onRemove: { onRemoveFromQueue(clip) }
                            )
                        }
                    }

                    if !queueClips.isEmpty && !watchLaterClips.isEmpty {
                        Rectangle()
                            .fill(DesignTokens.Glass.borderColorLight.opacity(0.4))
                            .frame(width: 1, height: 56)
                            .padding(.horizontal, 4)
                    }

                    if !watchLaterClips.isEmpty {
                        sectionLabel("나중에 보기", color: DesignTokens.Colors.accentOrange)
                        ForEach(watchLaterClips.prefix(8), id: \.clipUID) { clip in
                            FilmstripThumb(
                                clip: clip,
                                position: nil,
                                accent: DesignTokens.Colors.accentOrange,
                                onPlay: { onPlay(clip) },
                                onPreview: { onPreview(clip) },
                                onRemove: nil
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── 우측 액션
            if !queueClips.isEmpty {
                Button(action: onClearQueue) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                        Text("큐 비우기")
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                    .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.96))
                .customCursor(.pointingHand)
                .help("재생 큐 모두 비우기")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(height: 92)
        .background {
            Rectangle()
                .fill(DesignTokens.Colors.surfaceBase)
                .overlay {
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.chzzkGreen.opacity(0.04),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
    }

    private var summary: String {
        switch (queueClips.count, watchLaterClips.count) {
        case (0, 0): return "비어있음"
        case (let q, 0): return "큐 \(q)개"
        case (0, let s): return "저장 \(s)개"
        case (let q, let s): return "큐 \(q) · 저장 \(s)"
        }
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Thumb

private struct FilmstripThumb: View {
    let clip: ClipInfo
    /// 큐 순번 표시 (없으면 nil).
    let position: Int?
    let accent: Color
    let onPlay: () -> Void
    let onPreview: () -> Void
    let onRemove: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button(action: onPreview) {
            ZStack(alignment: .topLeading) {
                // 썸네일
                Group {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                        }
                    } else {
                        Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                    }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                // hover 다크닝 + 재생 버튼
                if isHovered {
                    LinearGradient(
                        colors: [.black.opacity(0.0), .black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .allowsHitTesting(false)

                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .background(.white.opacity(0.95), in: Circle())
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                    .buttonStyle(.plain)
                    .customCursor(.pointingHand)
                    .position(x: 50, y: 28)
                }

                // 좌상단: 순번
                if let position {
                    Text("\(position)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(accent, in: Capsule())
                        .padding(4)
                        .allowsHitTesting(false)
                }

                // 우상단: 제거 버튼
                if isHovered, let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(.black.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .customCursor(.pointingHand)
                    .help("큐에서 제거")
                    .position(x: 90, y: 10)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isHovered ? accent.opacity(0.6) : DesignTokens.Glass.borderColorLight.opacity(0.3),
                        lineWidth: isHovered ? 1.0 : 0.5
                    )
            }
            .frame(width: 100, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .help(clip.clipTitle)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
