// MARK: - HomeV2Components.swift
// CViewApp - HomeView_v2 전용 재사용 컴포넌트 묶음
// 새 홈 정보구조용 작은 뷰들 (CommandBar / HeroLiveCard / FollowingRail / RecommendationCard /
// ContinueWatchingStrip / InsightsCompactStrip / SectionHeaderV2)

import SwiftUI
import CViewCore
import CViewUI
import CViewPlayer
import CViewPersistence

// MARK: - Section Header

struct HomeV2SectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            Text(title)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.Colors.textPrimary, DesignTokens.Colors.textPrimary.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            if let subtitle {
                Text("·  \(subtitle)")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            trailing
        }
    }
}

struct HomeV2StatusPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }
}

// MARK: - Command Bar (검색 진입 + 빠른 액션)

struct HomeCommandBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    let greeting: String
    let isRefreshing: Bool
    let monitorEnabled: Bool
    let onToggleMonitor: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                AnimatedGradientText(
                    text: greeting,
                    font: DesignTokens.Typography.titleSemibold,
                    animate: false
                )
                Text("오늘의 라이브를 한눈에 둘러보세요")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            // Search entry (전역 ⌘K Command Palette 열기 — 토글 X, 항상 open)
            Button {
                // [hit-test 진단 2026-04-24]
                // ⌘K 메뉴는 동작하지만 검색 버튼은 동작 안 한다는 보고.
                // toggle() 이 어떤 이유로 두 번 불려 false 로 돌아가는 가능성을 차단하기 위해
                // 명시적으로 = true 로 설정. (검색 진입 버튼이라 닫기 의미가 없음)
                NSLog("[HomeCommandBar] search tapped → open palette")
                appState.showCommandPalette = true
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("채널/카테고리 검색")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Spacer(minLength: DesignTokens.Spacing.lg)
                    Text("⌘K")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(width: 240)
                .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                }                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))            }
            .buttonStyle(.plain)
            .help("검색 (⌘K)")

            // Multilive shortcut
            //   1) FollowingView 의 멀티라이브 패널을 강제로 on (이전에 숨겼던 경우 대비)
            //   2) 세션이 이미 롬으면 채팅 패널도 상시 표시
            //   3) 사이드바를 팔로잉(멀티라이브 통합)으로 이동
            iconButton(systemName: "square.grid.2x2.fill", help: "멀티라이브 열기") {
                appState.followingViewState.showMultiLive = true
                if !appState.multiLiveManager.sessions.isEmpty {
                    appState.followingViewState.showMultiChat = true
                }
                router.selectSidebar(.following)
            }

            // Performance monitor toggle
            iconButton(
                systemName: monitorEnabled ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.0percent",
                help: monitorEnabled ? "성능 모니터 숨기기" : "성능 모니터 보기",
                tinted: monitorEnabled,
                action: onToggleMonitor
            )

            // Refresh
            iconButton(systemName: "arrow.clockwise", help: "새로고침", spinning: isRefreshing) {
                onRefresh()
            }
        }
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    @ViewBuilder
    private func iconButton(systemName: String, help: String, spinning: Bool = false, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tinted ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    tinted
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                        : DesignTokens.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(
                            tinted
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.45)
                                : DesignTokens.Glass.borderColor,
                            lineWidth: tinted ? 1.0 : 0.5
                        )
                }
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : DesignTokens.Animation.smooth,
                    value: spinning
                )
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Hero Live Card

struct HomeHeroLiveCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    let item: HomeRecommendationEngine.ScoredChannel
    var height: CGFloat = 320
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LiveThumbnailView(
                channelId: item.channel.channelId,
                thumbnailUrl: URL(string: item.channel.thumbnailUrl ?? "")
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 1.0)
            }

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    liveBadge
                    viewerBadge
                    if !item.reasons.isEmpty {
                        ForEach(item.reasons.prefix(2), id: \.self) { r in
                            reasonBadge(r)
                        }
                    }
                }
                Text(item.channel.liveTitle)
                    .font(DesignTokens.Typography.headlineBold)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: DesignTokens.Spacing.xs) {
                    CachedAsyncImage(url: URL(string: item.channel.channelImageUrl ?? "")) {
                        Circle().fill(.white.opacity(0.2))
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    Text(item.channel.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    if let cat = item.channel.categoryName, !cat.isEmpty {
                        Text("·  \(cat)")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Task { @MainActor in
                            await appState.multiLiveManager.addSession(
                                channelId: item.channel.channelId,
                                presentationOverride: .embedded
                            )
                        }
                    } label: {
                        Label("+ 멀티", systemImage: "plus")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered ? 1 : 0)
                    .animation(DesignTokens.Animation.fast, value: hovered)
                }
                Spacer()
            }
            .padding(DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .scaleEffect(hovered ? 1.012 : 1.0, anchor: .center)
        // [Perf 2026-04-24] shadow radius 는 Gaussian blur 커널이라 값이 바뀌면
        // 매 프레임 재계산. 대형 카드(320pt)에서 14↔24 진행은 비용이 큼 → 14 고정,
        // color/y 만 hover 에 따라 보간.
        .shadow(
            color: hovered ? DesignTokens.Colors.chzzkGreen.opacity(0.35) : .black.opacity(0.18),
            radius: 9,
            y: hovered ? 7 : 4
        )
        .animation(DesignTokens.Animation.smooth, value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onTapGesture {
            router.navigate(to: .live(channelId: item.channel.channelId))
        }
        .homeAccentPulse(color: DesignTokens.Colors.chzzkGreen, cornerRadius: DesignTokens.Radius.lg, enabled: hovered)
        .onHover { hovering in
            hovered = hovering
            if hovering {
                if let svc = appState.hlsPrefetchService {
                    Task { await svc.prefetch(channelId: item.channel.channelId) }
                }
            }
        }
        .customCursor(.pointingHand)
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            LivePulseDot(size: 5, color: .white, animate: false)
            Text("LIVE")
                .font(DesignTokens.Typography.custom(size: 10, weight: .black))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [DesignTokens.Colors.live, DesignTokens.Colors.live.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .shadow(color: DesignTokens.Colors.live.opacity(0.32), radius: 3, y: 1)
    }

    private var viewerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.fill").font(.system(size: 9))
            Text(item.channel.formattedViewerCount)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 3)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private func reasonBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.Colors.chzzkGreen.opacity(0.18), in: Capsule())
            .overlay {
                Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.5), lineWidth: 0.5)
            }
    }
}

// MARK: - Recommended Card (작은 카드 + 사유 배지)

struct HomeRecommendedCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    let item: HomeRecommendationEngine.ScoredChannel
    @State private var hovered = false

    /// 이미 멀티라이브 세션에 포함된 채널인지 (시각 안내용)
    private var isAlreadyWatching: Bool {
        appState.multiLiveManager.sessions.contains { $0.channelId == item.channel.channelId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topTrailing) {
                    LiveThumbnailView(
                        channelId: item.channel.channelId,
                        thumbnailUrl: URL(string: item.channel.thumbnailUrl ?? ""),
                        // [Perf 2026-04-24] 홈 추천 그리드는 한 화면에 6-12개 카드가 동시에
                        // 떠 있어 .liveLoop 사용 시 N개의 45s 타이머가 누적되며 fade-in 동시
                        // 발생. .once 로 전환 — 첫 fetch 후 정지 (사용자가 새로고침 버튼을 누르면
                        // viewModel.refresh() 가 데이터를 갱신하고 카드 자체가 재마운트되며
                        // 다시 1회 fetch 됨).
                        refreshPolicy: .once
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .scaleEffect(hovered ? 1.04 : 1.0, anchor: .center)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: DesignTokens.Radius.sm,
                        topTrailingRadius: DesignTokens.Radius.sm
                    ))
                    .animation(DesignTokens.Animation.smooth, value: hovered)

                    // 호버 시 그라디언트 오버레이
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen.opacity(hovered ? 0.18 : 0), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: DesignTokens.Radius.sm,
                        topTrailingRadius: DesignTokens.Radius.sm
                    ))
                    .allowsHitTesting(false)
                    .animation(DesignTokens.Animation.smooth, value: hovered)

                    if let reason = item.reasons.first {
                        Text(reason)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(DesignTokens.Spacing.xs)
                    }

                    Button {
                        Task { @MainActor in
                            await appState.multiLiveManager.addSession(
                                channelId: item.channel.channelId,
                                presentationOverride: .embedded
                            )
                        }
                    } label: {
                        Label("+ 멀티", systemImage: "plus")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.9), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(DesignTokens.Spacing.xs)
                    .opacity(hovered ? 1 : 0.92)

                    // 이미 멀티라이브 세션에 포함된 채널이면 "시청 중" 뱃지 (우상단)
                    if isAlreadyWatching {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("시청 중")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.85), in: Capsule())
                        .padding(DesignTokens.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.channel.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.channel.liveTitle)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "person.fill").font(.system(size: 8))
                    Text(item.channel.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                    if let cat = item.channel.categoryName, !cat.isEmpty {
                        Text("·  \(cat)").lineLimit(1)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    hovered ? DesignTokens.Colors.chzzkGreen.opacity(0.55) : DesignTokens.Glass.borderColor,
                    lineWidth: hovered ? 1.2 : 0.5
                )
        }
        .scaleEffect(hovered ? 1.022 : 1.0, anchor: .center)
        .offset(y: hovered ? -2 : 0)
        // [Perf 2026-04-24] radius 고정 (Gaussian blur 재계산 방지). 색/y 만 보간.
        .shadow(
            color: hovered ? DesignTokens.Colors.chzzkGreen.opacity(0.20) : .black.opacity(0.07),
            radius: 5,
            y: hovered ? 4 : 1
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onTapGesture {
            router.navigate(to: .live(channelId: item.channel.channelId))
        }
        .onHover { hovering in
            hovered = hovering
            if hovering {
                if let svc = appState.hlsPrefetchService {
                    Task { await svc.prefetch(channelId: item.channel.channelId) }
                }
            }
        }
        .animation(DesignTokens.Animation.fast, value: hovered)
        .customCursor(.pointingHand)
    }
}

// MARK: - Continue Watching Strip (최근/즐겨찾기 — 라이브 여부 무관)

struct HomeContinueWatchingStrip: View {
    @Environment(AppRouter.self) private var router
    let title: String
    let icon: String
    let items: [ChannelListData]
    /// 채널이 라이브 중인지 빠르게 조회 (channelId → LiveChannelItem)
    let liveLookup: [String: LiveChannelItem]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HomeV2SectionHeader(icon: icon, title: title)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(items.prefix(12)) { it in
                            row(it)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ it: ChannelListData) -> some View {
        let live = liveLookup[it.channelId]
        Button {
            if live != nil {
                router.navigate(to: .live(channelId: it.channelId))
            } else {
                router.navigate(to: .channelDetail(channelId: it.channelId))
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: URL(string: it.imageURL ?? "")) {
                        Circle().fill(DesignTokens.Colors.surfaceBase)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(
                            live != nil ? DesignTokens.Colors.live : DesignTokens.Glass.borderColor,
                            lineWidth: live != nil ? 1.5 : 0.5
                        )
                    }
                    if live != nil {
                        LivePulseDot(size: 8, animate: false)
                            .padding(2)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(it.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if let live {
                        Text(live.liveTitle)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.live)
                            .lineLimit(1)
                    } else {
                        Text(it.lastWatched.map(relativeTime) ?? "오프라인")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(width: 220)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .homeHoverLift(
            lift: 1,
            scale: 1.018,
            accent: live != nil ? DesignTokens.Colors.live : DesignTokens.Colors.chzzkGreen,
            cornerRadius: DesignTokens.Radius.sm
        )
        .customCursor(.pointingHand)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.subhead)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("아직 기록이 없어요")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func relativeTime(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "ko_KR")
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Compact Insights Strip (하단 접이식)

struct HomeInsightsCompactStrip: View {
    let totalLive: Int
    let totalViewers: Int
    let categoryCount: Int
    let followingLive: Int
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            DisclosureGroup(isExpanded: $expanded) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    stat("전체 라이브", "\(totalLive)", icon: "dot.radiowaves.left.and.right")
                    stat("총 시청자", formatLarge(totalViewers), icon: "person.3.fill")
                    stat("카테고리", "\(categoryCount)", icon: "square.grid.2x2.fill")
                    stat("팔로잉 라이브", "\(followingLive)", icon: "heart.fill", accent: .pink)
                }
                .padding(.top, DesignTokens.Spacing.xs)
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("간이 통계")
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("자세한 통계는 메트릭 메뉴에서 확인할 수 있어요")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .accentColor(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func stat(_ title: String, _ value: String, icon: String, accent: Color? = nil) -> some View {
        InsightsStatCard(title: title, value: value, icon: icon, accent: accent ?? DesignTokens.Colors.chzzkGreen)
    }

    private func formatLarge(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000.0) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000.0) }
        return "\(n)"
    }
}

// MARK: - Insights Stat Card (호버 틴트 + 넘버 트랜지션)

private struct InsightsStatCard: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                    .scaleEffect(hovered ? 1.15 : 1.0)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(DesignTokens.Typography.headlineBold)
                .foregroundStyle(
                    hovered
                        ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(DesignTokens.Colors.textPrimary)
                )
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.sm)
        .background(
            (hovered ? accent.opacity(0.10) : DesignTokens.Colors.surfaceBase),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    hovered ? accent.opacity(0.45) : Color.clear,
                    lineWidth: hovered ? 1.0 : 0
                )
        }
        .scaleEffect(hovered ? 1.025 : 1.0, anchor: .center)
        .onHover { hovered = $0 }
        .animation(DesignTokens.Animation.smooth, value: hovered)
    }
}
