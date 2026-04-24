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
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            Text(title)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
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

// MARK: - Command Bar (검색 진입 + 빠른 액션)

struct HomeCommandBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    let greeting: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(DesignTokens.Typography.titleSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("오늘의 라이브를 한눈에 둘러보세요")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            // Search entry (Spotlight-style invocation)
            Button {
                router.selectSidebar(.search)
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
                }
            }
            .buttonStyle(.plain)
            .help("검색 (⌘K)")

            // Multilive shortcut
            iconButton(systemName: "square.grid.2x2.fill", help: "멀티라이브") {
                router.selectSidebar(.following)
            }

            // Refresh
            iconButton(systemName: "arrow.clockwise", help: "새로고침", spinning: isRefreshing) {
                onRefresh()
            }
        }
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    @ViewBuilder
    private func iconButton(systemName: String, help: String, spinning: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                }
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: spinning)
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

    var body: some View {
        Button {
            router.navigate(to: .live(channelId: item.channel.channelId))
        } label: {
            ZStack(alignment: .bottomLeading) {
                LiveThumbnailView(
                    channelId: item.channel.channelId,
                    thumbnailUrl: URL(string: item.channel.thumbnailUrl ?? "")
                )
                .aspectRatio(16/9, contentMode: .fill)
                .frame(maxWidth: .infinity)
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
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

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
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 360)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
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
            Circle().fill(.white).frame(width: 5, height: 5)
            Text("LIVE")
                .font(DesignTokens.Typography.custom(size: 10, weight: .black))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 3)
        .background(DesignTokens.Colors.live, in: Capsule())
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

    var body: some View {
        Button {
            router.navigate(to: .live(channelId: item.channel.channelId))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LiveThumbnailView(
                        channelId: item.channel.channelId,
                        thumbnailUrl: URL(string: item.channel.thumbnailUrl ?? "")
                    )
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: DesignTokens.Radius.sm,
                        topTrailingRadius: DesignTokens.Radius.sm
                    ))

                    if let reason = item.reasons.first {
                        Text(reason)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(DesignTokens.Spacing.xs)
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
                        hovered ? DesignTokens.Colors.chzzkGreen.opacity(0.4) : DesignTokens.Glass.borderColor,
                        lineWidth: hovered ? 1.0 : 0.5
                    )
            }
            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
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
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 8, height: 8)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
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
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent ?? DesignTokens.Colors.chzzkGreen)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(DesignTokens.Typography.headlineBold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    private func formatLarge(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000.0) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000.0) }
        return "\(n)"
    }
}
