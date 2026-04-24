// MARK: - FollowingCardViews.swift
// CViewApp - 팔로잉 채널 카드 컴포넌트
// 모던 미니멀 디자인 — 경량 렌더링 + 깔끔한 인터랙션

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Live Channel Avatar Item (경량 프로필 아바타)

@MainActor
struct FollowingLiveAvatarItem: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveAvatarItem, rhs: FollowingLiveAvatarItem) -> Bool {
        lhs.channel == rhs.channel && lhs.layout == rhs.layout
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var appeared = false

    private var profileURL: URL? { URL(string: channel.channelImageUrl ?? "") }

    private var outerSize: CGFloat {
        layout.liveAvatarSize + layout.liveAvatarRingWidth * 2 + 4
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // 라이브 링 — [GPU] stroke lineWidth는 고정, 그라디언트 밝기만 변화
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen,
                                DesignTokens.Colors.chzzkGreen.opacity(isHovered ? 0.8 : 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: layout.liveAvatarRingWidth
                    )
                    .frame(width: outerSize, height: outerSize)

                // 간격용 링
                Circle()
                    .fill(DesignTokens.Colors.surfaceBase)
                    .frame(width: layout.liveAvatarSize + 4, height: layout.liveAvatarSize + 4)

                // 프로필 이미지
                profileImage
                    .frame(width: layout.liveAvatarSize, height: layout.liveAvatarSize)
                    .clipShape(Circle())

                // 시청자수 배지 (하단)
                VStack {
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: layout.liveAvatarViewerFontSize - 1))
                        Text(channel.formattedViewerCount)
                            .font(DesignTokens.Typography.custom(
                                size: layout.liveAvatarViewerFontSize,
                                weight: .bold, design: .rounded
                            ))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .offset(y: isHovered ? 2 : 4)
                }
                .frame(width: outerSize, height: outerSize)
            }
            // [GPU] 링·프로필·배지 전체를 하나의 compositing 그룹으로 묶고 단일 scale 적용
            .compositingGroup()
            .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.05 : 1.0))
            .shadow(
                color: DesignTokens.Colors.chzzkGreen.opacity(isHovered ? 0.28 : 0),
                radius: 6  // 고정
            )

            // 채널명
            Text(channel.channelName)
                .font(DesignTokens.Typography.custom(
                    size: layout.liveAvatarNameFontSize,
                    weight: isHovered ? .semibold : .medium
                ))
                .foregroundStyle(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.textPrimary
                )
                .lineLimit(1)
                .frame(width: layout.liveAvatarItemWidth)
        }
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 6)
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .animation(DesignTokens.Animation.micro, value: isPressed)
        .animation(DesignTokens.Animation.motionSafe(DesignTokens.Animation.cardAppear), value: appeared)
        .onAppear {
            let delay = min(Double(index) * 0.025, 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { appeared = true }
        }
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .help("\(channel.liveTitle)\(channel.categoryName.map { "\n\($0)" } ?? "")")
        .contentShape(Circle())
        .customCursor(.pointingHand)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let url = profileURL {
            CachedAsyncImage(url: url) {
                Circle().fill(DesignTokens.Colors.surfaceElevated)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: layout.liveAvatarSize * 0.35, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }
        } else {
            Circle().fill(DesignTokens.Colors.surfaceElevated)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: layout.liveAvatarSize * 0.35, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
        }
    }
}

// MARK: - Live Channel Card (Modern Flat Card)

@MainActor
struct FollowingLiveCard: View, Equatable {
    nonisolated static func == (lhs: FollowingLiveCard, rhs: FollowingLiveCard) -> Bool {
        lhs.channel == rhs.channel && lhs.layout == rhs.layout
    }

    let channel: LiveChannelItem
    let index: Int
    let onPlay: () -> Void
    var onPrefetch: ((String) -> Void)? = nil
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .clipped()

            infoArea
                .frame(height: layout.cardInfoHeight + 4)  // [2026-04-23] 결정적 높이 — minHeight → height
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)  // [2026-04-23] 셀 크기 채움
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.6)
                        : DesignTokens.Colors.surfaceElevated.opacity(0.3),
                    lineWidth: 1  // [GPU] 고정 — 다중 엘리먼트가 동시 애니메이션 시 CAShapeLayer re-tessellation 발생 방지
                )
        }
        .compositingGroup()
        // [GPU] shadow radius는 고정. color의 opacity만 변화 — 섹명 회피를 위해 일정한 10pt 유지
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: 10, y: 4)
        .scaleEffect(isPressed ? 0.985 : (isHovered ? 1.02 : 1.0))
        .offset(y: isHovered ? -1 : 0)
        .opacity(appeared ? 1.0 : 0.0)
        // [GPU] animation 모디파이어 통합 — transaction 단일 패스로 모든 상태변화 적용
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .animation(DesignTokens.Animation.micro, value: isPressed)
        .animation(DesignTokens.Animation.motionSafe(DesignTokens.Animation.cardAppear), value: appeared)
        .onAppear {
            let delay = min(Double(index) * 0.025, 0.24)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { appeared = true }
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering { onPrefetch?(channel.channelId) }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
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

            // 라이브 채널: LiveThumbnailView로 주기적 자동 갱신 (메트릭 서버 + 90s TTL)
            // 백그라운드/숨김 시 자동 중지, 복귀 시 즉시 재갱신
            LiveThumbnailView(
                channelId: channel.channelId,
                thumbnailUrl: thumbnailURL,
                isLive: channel.isLive
            )
            .scaledToFill()
            .clipped()
            // [GPU] 썸네일 확대 — 상위 .animation 이 제어 (이중 animation 제거)
            .scaleEffect(isHovered ? 1.06 : 1.0)

            // 하단 그라디언트 베일
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: .bottom
                )
                .frame(height: 56)
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
                        .help(channel.liveTitle)

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
        .compositingGroup()
    }

    // MARK: - Viewer Badge (Simple Pill)

    private var viewerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: layout.viewerIconSize + 1))
            Text(channel.formattedViewerCount)
                .font(.system(size: layout.viewerFontSize + 1, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    // MARK: - Uptime Badge

    private func uptimeBadge(since date: Date) -> some View {
        let elapsed = Date().timeIntervalSince(date)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let text = hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"

        return HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
        }
        .foregroundStyle(DesignTokens.Colors.textOnDarkMedia.opacity(0.9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.black.opacity(0.45)))
    }

    // MARK: - Category Tag

    private func categoryTag(_ name: String) -> some View {
        Text(name)
            .font(.system(size: layout.categoryFontSize + 1, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.textOnDarkMedia.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(DesignTokens.Colors.controlOnDarkMediaHover))
    }

    // MARK: - Hover Overlay

    private var hoverOverlay: some View {
        ZStack {
            // 반투명 오버레이
            Color.black.opacity(0.35)

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
                    Capsule().fill(DesignTokens.Colors.accentBlue)
                )
                // [GPU] shadow는 opacity만 변화. radius 고정.
                .shadow(color: DesignTokens.Colors.accentBlue.opacity(isHovered ? 0.45 : 0), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovered ? 1.0 : 0.85)
            .opacity(isHovered ? 1.0 : 0.0)
        }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
        .animation(DesignTokens.Animation.bouncy, value: isHovered)
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
                }

                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            Text(channel.channelName)
                .font(.system(size: layout.cardNameFontSize, weight: .semibold))
                .foregroundStyle(
                    isHovered
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.textPrimary
                )
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)  // [2026-04-23] 외부에서 height 고정
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.3))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Offline Channel Row (Clean Minimal Row)

struct FollowingOfflineRow: View, Equatable {
    nonisolated static func == (lhs: FollowingOfflineRow, rhs: FollowingOfflineRow) -> Bool {
        lhs.channel == rhs.channel
    }

    let channel: LiveChannelItem
    let index: Int
    var layout: ResponsiveFollowingLayout = .init(width: 900)

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 프로필
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                }
                .frame(width: layout.offlineProfileSize, height: layout.offlineProfileSize)
                .clipShape(Circle())
                .opacity(isHovered ? 1.0 : 0.7)
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .compositingGroup()

                Circle()
                    .fill(DesignTokens.Colors.textTertiary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(DesignTokens.Typography.custom(size: layout.offlineNameFontSize, weight: .medium))
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)

                if let cat = channel.categoryName, !cat.isEmpty {
                    Text(cat)
                        .font(DesignTokens.Typography.custom(size: layout.offlineInfoFontSize, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 우측 상태/액션 — 크로스페이드 + 슬라이드 전환
            ZStack(alignment: .trailing) {
                Text("오프라인")
                    .font(DesignTokens.Typography.custom(size: layout.offlineInfoFontSize, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                    .opacity(isHovered ? 0 : 1)
                    .offset(x: isHovered ? 6 : 0)

                HStack(spacing: 3) {
                    Text("채널 보기")
                        .font(DesignTokens.Typography.custom(size: layout.offlineInfoFontSize, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: layout.offlineInfoFontSize - 2, weight: .semibold))
                        .offset(x: isHovered ? 0 : -4)
                }
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .opacity(isHovered ? 1 : 0)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(isHovered ? DesignTokens.Colors.surfaceElevated.opacity(isPressed ? 0.6 : 0.4) : Color.clear)
        }
        .offset(x: isHovered ? 2 : 0)
        .scaleEffect(isPressed ? 0.985 : 1.0, anchor: .leading)
        .animation(DesignTokens.Animation.snappy, value: isHovered)
        .animation(DesignTokens.Animation.micro, value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
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
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .shimmer()
        .drawingGroup()
    }
}
