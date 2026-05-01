// MARK: - ClipPreviewInspector.swift
// CViewApp - 클립 메뉴: 우측 inspector 패널 (선택 클립 상세 + 빠른 액션) + 보조 액션 행.
// 2026-04-30 CL-1 Phase 1 분해 — PopularClipsView.swift에서 이전.

import SwiftUI
import AppKit
import CViewCore
import CViewNetworking
import CViewUI


// MARK: - Clip Preview Inspector

/// 우측 inspector 패널. 선택된 클립의 상세를 보여주고 빠른 액션을 제공한다.
struct ClipPreviewInspector: View {
    let clip: ClipInfo
    let onPlay: () -> Void
    let onOpenChannel: () -> Void
    let onShowChannelClips: () -> Void
    let onOpenOriginal: () -> Void
    let onCopyLink: () -> Void
    let onClose: () -> Void
    /// 나중에 보기 토글 — 현재 상태와 토글 콜백.
    var isWatchLater: Bool = false
    var onToggleWatchLater: (() -> Void)? = nil
    /// 큐 토글 — 현재 큐 포함 여부와 토글 콜백.
    var isInQueue: Bool = false
    var onToggleQueue: (() -> Void)? = nil

    @State private var didCopy = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                // [2026-04-30 Pass2] 헤더 — 라벨 + 점 indicator + 닫기
                HStack(spacing: 6) {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 6, height: 6)
                        .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.5), radius: 3)
                    Text("미리보기")
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                            .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .customCursor(.pointingHand)
                    .help("닫기")
                }

                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let url = clip.thumbnailImageURL {
                            CachedAsyncImage(url: url) {
                                thumbnailPlaceholder
                            }
                        } else {
                            thumbnailPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                            .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.3), lineWidth: 0.5)
                    }

                    // Duration glass badge
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(formattedDuration)
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                    .padding(DesignTokens.Spacing.xs)
                }

                // Title
                Text(clip.clipTitle)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Meta — 채널 행 + 통계 행
                VStack(alignment: .leading, spacing: 8) {
                    if let channel = clip.channel {
                        HStack(spacing: 8) {
                            if let chURL = channel.channelImageURL {
                                CachedAsyncImage(url: chURL) {
                                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 0.7)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(channel.channelName)
                                    .font(DesignTokens.Typography.captionSemibold)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    .lineLimit(1)
                                Text("크리에이터")
                                    .font(DesignTokens.Typography.custom(size: 9.5))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        statPill(icon: "eye.fill", text: formattedCount(clip.readCount), color: DesignTokens.Colors.chzzkGreen)
                        if let dateStr = relativeDate(clip.createdDate) {
                            statPill(icon: "clock", text: dateStr, color: DesignTokens.Colors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 2)

                Divider()
                    .background(DesignTokens.Glass.borderColorLight.opacity(0.4))

                // 주 액션: 재생 — 큰 버튼
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("재생")
                            .font(DesignTokens.Typography.bodySemibold)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.7)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
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
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 0.7)
                    }
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.40), radius: 10, y: 4)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.97))
                .customCursor(.pointingHand)

                // 섹션 1: 보관
                actionSection(title: "보관") {
                    if let onToggleWatchLater {
                        inspectorActionRow(
                            icon: isWatchLater ? "bookmark.fill" : "bookmark",
                            label: isWatchLater ? "나중에 보기에서 제거" : "나중에 보기",
                            accent: isWatchLater ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.chzzkGreen,
                            action: onToggleWatchLater
                        )
                    }
                    if let onToggleQueue {
                        inspectorActionRow(
                            icon: isInQueue ? "checkmark.circle.fill" : "text.line.first.and.arrowtriangle.forward",
                            label: isInQueue ? "큐에서 제거" : "큐에 추가",
                            accent: isInQueue ? DesignTokens.Colors.accentPink : DesignTokens.Colors.chzzkGreen,
                            action: onToggleQueue
                        )
                    }
                }

                // 섹션 2: 채널
                if clip.channel != nil {
                    actionSection(title: "채널") {
                        inspectorActionRow(icon: "person.crop.rectangle", label: "채널 열기", action: onOpenChannel)
                        inspectorActionRow(icon: "film.stack", label: "이 채널의 클립 보기", action: onShowChannelClips)
                    }
                }

                // 섹션 3: 공유
                actionSection(title: "공유") {
                    inspectorActionRow(icon: "safari", label: "치지직에서 열기", action: onOpenOriginal)
                    inspectorActionRow(
                        icon: didCopy ? "checkmark" : "link",
                        label: didCopy ? "링크 복사됨" : "링크 복사",
                        accent: didCopy ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary,
                        action: {
                            onCopyLink()
                            didCopy = true
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                didCopy = false
                            }
                        }
                    )
                }

                // 미리보기 닫기 (개별 액션, 섹션 외부에 미세 강조)
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(DesignTokens.Typography.captionSemibold)
                        Text("미리보기 닫기")
                            .font(DesignTokens.Typography.captionMedium)
                        Spacer()
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                            .fill(DesignTokens.Colors.surfaceBase.opacity(0.5))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                            .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.3), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .customCursor(.pointingHand)

                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.surfaceBase)
    }

    /// 섹션 컨테이너 — 작은 헤더 라벨 + 자식 액션들을 모아둠
    @ViewBuilder
    private func actionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 4)
            VStack(spacing: 4) {
                content()
            }
        }
    }

    /// 미리보기 통계 pill
    private func statPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
            Text(text)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
        .overlay { Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5) }
    }

    private func inspectorActionRow(
        icon: String,
        label: String,
        accent: Color = DesignTokens.Colors.chzzkGreen,
        action: @escaping () -> Void
    ) -> some View {
        InspectorActionRow(icon: icon, label: label, accent: accent, action: action)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(DesignTokens.Colors.surfaceElevated)
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

// MARK: - Inspector Action Row (hover 강조 포함)

/// [2026-04-30 Pass2] 인스펙터 보조 액션 행 — hover 시 accent 보더 + 미세 배경 변화.
private struct InspectorActionRow: View {
    let icon: String
    let label: String
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionSemibold)
                    .frame(width: 18)
                    .foregroundStyle(accent)
                Text(label)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.8))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(isHovered
                          ? accent.opacity(0.10)
                          : DesignTokens.Colors.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isHovered ? accent.opacity(0.32) : DesignTokens.Glass.borderColor,
                        lineWidth: isHovered ? 0.7 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
