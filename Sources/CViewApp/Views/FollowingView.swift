// MARK: - FollowingView.swift
// CViewApp - 팔로잉 채널 목록 탭
// 정렬, 필터, 카테고리 칩, 라이브/오프라인 분리 표시

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI

// MARK: - Sort Order

enum FollowingSortOrder: String, CaseIterable, Identifiable {
    case liveFirst    = "라이브 우선"
    case viewers      = "시청자 많은 순"
    case nameAsc      = "채널명 가나다순"
    case original     = "기본 순서"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .liveFirst: return "dot.radiowaves.left.and.right"
        case .viewers:   return "person.2"
        case .nameAsc:   return "textformat.abc"
        case .original:  return "list.bullet"
        }
    }

    func sort(_ channels: [LiveChannelItem]) -> [LiveChannelItem] {
        switch self {
        case .liveFirst:
            return channels.sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive }
                return lhs.viewerCount > rhs.viewerCount
            }
        case .viewers:
            return channels.sorted { $0.viewerCount > $1.viewerCount }
        case .nameAsc:
            return channels.sorted { $0.channelName < $1.channelName }
        case .original:
            return channels
        }
    }
}

// MARK: - Following View

struct FollowingView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var sortOrder: FollowingSortOrder = .liveFirst
    @State private var filterLiveOnly: Bool = false
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var displayedOfflineCount: Int = 10
    @State private var showAllOffline: Bool = false
    private let offlinePageSize = 10

    // 라이브 페이징 — 한 번에 렌더링되는 카드 수 제한 → GPU 동시 로드 감소
    @State private var displayedLiveCount: Int = 12
    @State private var showAllLive: Bool = false
    private let livePageSize = 12

    // 캐싱된 필터 결과 — 입력 변경 시에만 재산출 (body 중복 호출 방지)
    @State private var cachedLive: [LiveChannelItem] = []
    @State private var cachedAllOffline: [LiveChannelItem] = []
    @State private var cachedLiveCategoryCounts: [(name: String, count: Int)] = []

    // 페이징된 라이브 채널 (displayedLiveCount 이하만 렌더링)
    private var liveChannels: [LiveChannelItem] {
        showAllLive ? cachedLive : Array(cachedLive.prefix(displayedLiveCount))
    }

    private var totalLiveCount: Int { cachedLive.count }

    private var offlineChannels: [LiveChannelItem] {
        showAllOffline ? cachedAllOffline : Array(cachedAllOffline.prefix(displayedOfflineCount))
    }

    private var totalOfflineCount: Int { cachedAllOffline.count }
    private var liveCategoryCounts: [(name: String, count: Int)] { cachedLiveCategoryCounts }
    private var liveCategories: [String] { cachedLiveCategoryCounts.map { $0.name } }

    private func formatShortCount(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000) }
        return "\(n)"
    }

    /// 필터/정렬 조건이 바뀔 때만 재산출 — body 중복 연산 방지
    private func recomputeFiltered() {
        var channels = sortOrder.sort(viewModel.followingChannels)
        if filterLiveOnly { channels = channels.filter { $0.isLive } }
        if let cat = selectedCategory { channels = channels.filter { $0.categoryName == cat } }
        if !searchText.isEmpty {
            channels = channels.filter { $0.channelName.localizedCaseInsensitiveContains(searchText) }
        }
        cachedLive = channels.filter { $0.isLive }
        cachedAllOffline = channels.filter { !$0.isLive }

        var counts: [String: Int] = [:]
        viewModel.followingChannels
            .filter { $0.isLive }
            .compactMap { $0.categoryName }
            .forEach { counts[$0, default: 0] += 1 }
        cachedLiveCategoryCounts = counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    /// 페이지네이션 리셋 + 필터 재계산 (정렬/필터 조건 변경 시 사용)
    private func resetPaginationAndRecompute() {
        displayedOfflineCount = offlinePageSize
        displayedLiveCount = livePageSize
        showAllOffline = false
        showAllLive = false
        recomputeFiltered()
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 컨트롤 바 (검색 + 필터)
            controlBar

            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.5))
                .frame(height: 0.5)

            // ── 메인 컨텐츠
            if !appState.isLoggedIn {
                followingGateView(
                    icon: "person.crop.circle.badge.questionmark",
                    iconColor: DesignTokens.Colors.textTertiary,
                    title: "로그인이 필요합니다",
                    subtitle: "로그인하면 팔로잉 채널을 확인할 수 있습니다",
                    buttonLabel: "로그인",
                    action: { router.presentSheet(.login) }
                )
            } else if viewModel.needsCookieLogin {
                followingGateView(
                    icon: "key.fill",
                    iconColor: DesignTokens.Colors.accentOrange,
                    title: "네이버 로그인이 필요합니다",
                    subtitle: "팔로잉 목록을 보려면 '네이버 로그인'으로 다시 로그인하세요",
                    buttonLabel: "네이버 로그인",
                    action: { router.presentSheet(.login) }
                )
            } else if viewModel.followingChannels.isEmpty {
                if viewModel.isLoadingFollowing {
                    skeletonLoadingView
                } else {
                    followingGateView(
                        icon: "heart",
                        iconColor: DesignTokens.Colors.accentPink,
                        title: "팔로잉 채널이 없습니다",
                        subtitle: "치지직에서 채널을 팔로우하면 여기서 확인할 수 있어요",
                        buttonLabel: nil,
                        action: nil
                    )
                }
            } else {
                mainContent
            }
        }
        .background(DesignTokens.Colors.background)
        .navigationTitle("팔로잉")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenuButton
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.loadFollowingChannels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionMedium)
                }
                .help("새로고침")
            }
        }
        // 필터/정렬 관련 값 변경 시 1회만 recomputeFiltered() 호출되도록 통합
        .onChange(of: sortOrder) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: filterLiveOnly) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: selectedCategory) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: searchText) { _, _ in recomputeFiltered() }
        .onChange(of: viewModel.followingChannels) { _, _ in recomputeFiltered() }
        .task {
            // 데이터 있고 캐시가 5분 이내면 재로드 스킵
            let isFresh = viewModel.followingCachedAt.map { Date().timeIntervalSince($0) < 300 } ?? false
            guard viewModel.followingChannels.isEmpty || !isFresh else {
                recomputeFiltered()
                return
            }
            guard !viewModel.isLoadingFollowing else { return }
            await viewModel.loadFollowingChannels()
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 5) {
            // Row 1: 검색창 + 로딩 / 업데이트 시간
            HStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(searchText.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen)
                    TextField("채널 검색", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.caption)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    searchText.isEmpty ? DesignTokens.Colors.border : DesignTokens.Colors.chzzkGreen.opacity(0.5),
                    lineWidth: searchText.isEmpty ? 0.5 : 1
                ))

                Spacer()

                if viewModel.isLoadingFollowing {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(DesignTokens.Colors.chzzkGreen)
                } else if let cachedAt = viewModel.followingCachedAt {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.custom(size: 8))
                        Text(cachedAt, style: .relative)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .onTapGesture {
                        Task { await viewModel.loadFollowingChannels() }
                    }
                }
            }

            // Row 2: 라이브 필터 토글 + 통계 배지
            HStack(spacing: DesignTokens.Spacing.xs) {
                // 라이브만 보기 토글
                Button {
                    withAnimation(DesignTokens.Animation.indicator) {
                        filterLiveOnly.toggle()
                        if filterLiveOnly { selectedCategory = nil }
                    }
                } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(filterLiveOnly ? DesignTokens.Colors.live : DesignTokens.Colors.live.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                        Text("라이브 \(viewModel.followingLiveCount)")
                            .font(DesignTokens.Typography.custom(size: 11, weight: filterLiveOnly ? .bold : .medium))
                            .foregroundStyle(filterLiveOnly ? DesignTokens.Colors.live : DesignTokens.Colors.textSecondary)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background {
                        if filterLiveOnly {
                            DesignTokens.Colors.live.opacity(0.12)
                        } else {
                            Rectangle().fill(.ultraThinMaterial)
                        }
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        filterLiveOnly ? DesignTokens.Colors.live.opacity(0.4) : DesignTokens.Colors.border,
                        lineWidth: 0.5
                    ))
                }
                .buttonStyle(.plain)

                Spacer()

                // 통계 배지
                if !viewModel.followingChannels.isEmpty {
                    statPill(value: "\(viewModel.followingChannels.count)", label: "팔로잉",
                             color: DesignTokens.Colors.accentPurple)
                    if viewModel.followingTotalViewers > 0 {
                        statPill(value: formatShortCount(viewModel.followingTotalViewers), label: "명 시청",
                                 color: DesignTokens.Colors.accentBlue)
                    }
                    if viewModel.followingLiveRate > 0 {
                        statPill(value: "\(viewModel.followingLiveRate)%", label: "라이브율",
                                 color: DesignTokens.Colors.chzzkGreen)
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.background)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(color)
            Text(label)
                .font(DesignTokens.Typography.footnoteMedium)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 카테고리 필터 칩
                if !liveCategories.isEmpty && !filterLiveOnly {
                    categoryFilterChips
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)
                }

                // 검색 결과 없음
                if cachedLive.isEmpty && cachedAllOffline.isEmpty {
                    emptySearchResult
                } else {
                    // 라이브 섹션
                    if !cachedLive.isEmpty {
                        sectionHeader(
                            icon: "dot.radiowaves.left.and.right",
                            title: "라이브 중",
                            count: totalLiveCount,
                            color: DesignTokens.Colors.live
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)

                        liveGrid
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.xs)

                        // 라이브 더 보기 (페이징)
                        if !showAllLive && displayedLiveCount < totalLiveCount {
                            loadMoreLiveButton
                                .padding(.top, DesignTokens.Spacing.xs)
                                .padding(.bottom, DesignTokens.Spacing.xs)
                        }
                    }

                    // 오프라인 섹션
                    if !filterLiveOnly && totalOfflineCount > 0 {
                        sectionHeader(
                            icon: "moon.zzz",
                            title: "오프라인",
                            count: totalOfflineCount,
                            color: DesignTokens.Colors.textTertiary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.md)

                        offlineList
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.xs)

                        // 더 보기
                        if !showAllOffline && displayedOfflineCount < totalOfflineCount {
                            loadMoreOfflineButton
                                .padding(.top, DesignTokens.Spacing.xs)
                                .padding(.bottom, DesignTokens.Spacing.sm)
                        }
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xl)
            }
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }

    // MARK: - Category Filter Chips

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // 전체 칩
                categoryChip(label: "전체", count: 0, isSelected: selectedCategory == nil) {
                    withAnimation(DesignTokens.Animation.indicator) {
                        selectedCategory = nil
                    }
                }
                ForEach(liveCategoryCounts, id: \.name) { cat in
                    categoryChip(label: cat.name, count: cat.count, isSelected: selectedCategory == cat.name) {
                        withAnimation(DesignTokens.Animation.indicator) {
                            selectedCategory = selectedCategory == cat.name ? nil : cat.name
                        }
                    }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xxs)
        }
    }

    private func categoryChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? .black : DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surfaceElevated)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isSelected {
                    DesignTokens.Colors.chzzkGreen.opacity(0.12)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.4) : DesignTokens.Colors.border,
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Live Grid (16:9 스트림 카드)

    private var liveGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.sm)],
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(Array(liveChannels.enumerated()), id: \.element.id) { index, channel in
                FollowingLiveCard(channel: channel, index: index) {
                    router.navigate(to: .live(channelId: channel.channelId))
                } onPrefetch: { channelId in
                    if let service = appState.hlsPrefetchService {
                        Task { await service.prefetch(channelId: channelId) }
                    }
                }
                .equatable()
                .onTapGesture {
                    router.navigate(to: .live(channelId: channel.channelId))
                }
                .contextMenu {
                    channelNotificationMenu(channelId: channel.channelId, channelName: channel.channelName)
                }
            }
        }
    }

    // MARK: - Offline List (컴팩트 행)

    private var offlineList: some View {
        // LazyVStack — 단일 열 목록에 열 수 계산 오버헤드 없음
        // offlineChannels는 prefix(displayedOfflineCount)로 슬라이스된 배열 → 렌더링 범위 명확히 제한
        LazyVStack(spacing: 2) {
            ForEach(offlineChannels, id: \.id) { channel in
                FollowingOfflineRow(channel: channel, index: 0)
                    .equatable()  // channel 데이터 동일 시 렌더링 스킵
                    .onTapGesture {
                        router.navigate(to: .channelDetail(channelId: channel.channelId))
                    }
                    .contextMenu {
                        channelNotificationMenu(channelId: channel.channelId, channelName: channel.channelName)
                    }
            }
        }
    }

    // MARK: - Channel Notification Context Menu

    @ViewBuilder
    private func channelNotificationMenu(channelId: String, channelName: String) -> some View {
        let setting = appState.settingsStore.channelNotificationSetting(for: channelId, channelName: channelName)

        Section("알림 설정 — \(channelName)") {
            Toggle(isOn: Binding(
                get: { setting.notifyOnLive },
                set: { newValue in
                    var updated = setting
                    updated.notifyOnLive = newValue
                    Task { await appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("방송 시작 알림", systemImage: "dot.radiowaves.left.and.right")
            }

            Toggle(isOn: Binding(
                get: { setting.notifyOnCategoryChange },
                set: { newValue in
                    var updated = setting
                    updated.notifyOnCategoryChange = newValue
                    Task { await appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("카테고리 변경 알림", systemImage: "tag")
            }

            Toggle(isOn: Binding(
                get: { setting.notifyOnTitleChange },
                set: { newValue in
                    var updated = setting
                    updated.notifyOnTitleChange = newValue
                    Task { await appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("제목 변경 알림", systemImage: "textformat")
            }
        }
    }

    // MARK: - Load More Live

    private var loadMoreLiveButton: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    displayedLiveCount = min(displayedLiveCount + livePageSize, totalLiveCount)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    Text("\(totalLiveCount - displayedLiveCount)개 더 보기")
                        .font(DesignTokens.Typography.captionMedium)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    showAllLive = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    Text("전체 \(totalLiveCount)")
                        .font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(DesignTokens.Colors.live)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.Colors.live.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.live.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Load More Offline

    private var loadMoreOfflineButton: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    displayedOfflineCount = min(displayedOfflineCount + offlinePageSize, totalOfflineCount)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    Text("\(totalOfflineCount - displayedOfflineCount)개 더 보기")
                        .font(DesignTokens.Typography.captionMedium)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    showAllOffline = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    Text("전체 \(totalOfflineCount)")
                        .font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(DesignTokens.Colors.accentPurple)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.Colors.accentPurple.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.accentPurple.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Skeleton Loading View

    private var skeletonLoadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(icon: "dot.radiowaves.left.and.right", title: "라이브 중", count: 0, color: DesignTokens.Colors.live)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .redacted(reason: .placeholder)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: DesignTokens.Spacing.sm)],
                    spacing: DesignTokens.Spacing.sm
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonLiveCard()
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.md)

                sectionHeader(icon: "moon.zzz", title: "오프라인", count: 0, color: DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .redacted(reason: .placeholder)

                VStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 10) {
                            Circle().fill(DesignTokens.Colors.surfaceElevated).frame(width: 30, height: 30).shimmer()
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(DesignTokens.Colors.surfaceElevated).frame(height: 10).shimmer()
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                }
            }
        }
    }

    // MARK: - Empty Search / Gate Views

    private var emptySearchResult: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("검색 결과가 없습니다")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if !searchText.isEmpty {
                Text("'\(searchText)'와 일치하는 채널이 없습니다")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            // 필터 초기화 버튼들
            VStack(spacing: 6) {
                if !searchText.isEmpty {
                    filterResetButton(label: "검색 초기화", icon: "xmark.circle") {
                        searchText = ""
                    }
                }
                if selectedCategory != nil {
                    filterResetButton(label: "카테고리 초기화", icon: "tag.slash") {
                        selectedCategory = nil
                    }
                }
                if filterLiveOnly {
                    filterResetButton(label: "라이브만 해제", icon: "dot.radiowaves.left.and.right.slash") {
                        filterLiveOnly = false
                    }
                }
                if searchText.isEmpty == false || selectedCategory != nil || filterLiveOnly {
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) {
                            searchText = ""
                            selectedCategory = nil
                            filterLiveOnly = false
                        }
                    } label: {
                        Text("모든 필터 초기화")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, DesignTokens.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, DesignTokens.Spacing.xl)
    }

    private func filterResetButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                Text(label).font(DesignTokens.Typography.captionMedium)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func followingGateView(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        buttonLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(iconColor)
            }
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.subheadSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let label = buttonLabel, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(DesignTokens.Typography.captionMedium)
                        Text(label)
                            .font(DesignTokens.Typography.bodySemibold)
                    }
                    .foregroundStyle(DesignTokens.Colors.onPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(DesignTokens.Colors.chzzkGreen)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Sort Menu

    private var sortMenuButton: some View {
        Menu {
            ForEach(FollowingSortOrder.allCases) { order in
                Button {
                    withAnimation(DesignTokens.Animation.fast) { sortOrder = order }
                } label: {
                    HStack {
                        Label(order.rawValue, systemImage: order.icon)
                        if sortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DesignTokens.Typography.captionMedium)
                Text(sortOrder.rawValue)
                    .font(DesignTokens.Typography.captionMedium)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
