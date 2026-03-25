// MARK: - FollowingView.swift
// CViewApp - 팔로잉 채널 목록 탭
// 글래스모피즘 + 모던 인터랙션 + 부드러운 애니메이션

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

// MARK: - Preference Key for Live Grid Height

private struct LiveGridHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Following View

struct FollowingView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    @State private var sortOrder: FollowingSortOrder = .liveFirst
    @State private var filterLiveOnly: Bool = false
    @State private var searchText: String = ""
    @State private var _searchDebounceTask: Task<Void, Never>?
    @State private var selectedCategory: String? = nil
    // 페이징
    @State private var livePageIndex: Int = 0
    @State private var offlinePageIndex: Int = 0
    // 멀티라이브 통합
    @State private var showMultiLive: Bool = false
    @State private var showMLAddChannel: Bool = false
    @State private var showMLSettings: Bool = false
    @State private var mlAddError: String?
    @State private var mlPanelWidth: CGFloat = 560
    @State private var hideFollowingList: Bool = false
    @State private var isDraggingDivider: Bool = false
    @GestureState private var dividerDragOffset: CGFloat = 0
    private var multiLiveManager: MultiLiveManager { appState.multiLiveManager }
    private let liveColumns = 4
    private let liveItemsPerPage = 16   // 4열 × 4행
    private let offlineItemsPerPage = 10

    // 캐싱된 필터 결과 — 입력 변경 시에만 재산출 (body 중복 호출 방지)
    @State private var cachedLive: [LiveChannelItem] = []
    @State private var cachedAllOffline: [LiveChannelItem] = []
    @State private var cachedLiveCategoryCounts: [(name: String, count: Int)] = []
    @State private var computedLiveGridHeight: CGFloat = 500

    private var totalLiveCount: Int { cachedLive.count }
    private var totalOfflineCount: Int { cachedAllOffline.count }
    private var liveCategoryCounts: [(name: String, count: Int)] { cachedLiveCategoryCounts }
    private var liveCategories: [String] { cachedLiveCategoryCounts.map { $0.name } }

    private var totalLivePages: Int { max(1, Int(ceil(Double(totalLiveCount) / Double(liveItemsPerPage)))) }
    private var totalOfflinePages: Int { max(1, Int(ceil(Double(totalOfflineCount) / Double(offlineItemsPerPage)))) }

    private func liveChannelsForPage(_ page: Int) -> [LiveChannelItem] {
        let start = page * liveItemsPerPage
        let end = min(start + liveItemsPerPage, totalLiveCount)
        guard start < end else { return [] }
        return Array(cachedLive[start..<end])
    }

    private func offlineChannelsForPage(_ page: Int) -> [LiveChannelItem] {
        let start = page * offlineItemsPerPage
        let end = min(start + offlineItemsPerPage, totalOfflineCount)
        guard start < end else { return [] }
        return Array(cachedAllOffline[start..<end])
    }

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

    /// 페이지 리셋 + 필터 재계산 (정렬/필터 조건 변경 시 사용)
    private func resetPaginationAndRecompute() {
        livePageIndex = 0
        offlinePageIndex = 0
        recomputeFiltered()
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // 배경 그라디언트 효과
            LinearGradient(
                colors: colorScheme == .light
                    ? [
                        DesignTokens.Colors.chzzkGreen.opacity(0.04),
                        Color.clear,
                        DesignTokens.Colors.accentBlue.opacity(0.03)
                    ]
                    : [
                        DesignTokens.Colors.surfaceBase.opacity(0.3),
                        Color.clear,
                        DesignTokens.Colors.surfaceElevated.opacity(0.15)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if !appState.isLoggedIn {
                followingGateView(
                    icon: "person.crop.circle.badge.questionmark",
                    iconColor: DesignTokens.Colors.textTertiary,
                    title: "로그인이 필요합니다",
                    subtitle: "로그인하면 팔로잉 채널을 확인할 수 있습니다",
                    buttonLabel: "로그인",
                    action: { router.presentSheet(.login) }
                )
                .transition(.opacity)
            } else if viewModel.needsCookieLogin {
                followingGateView(
                    icon: "key.fill",
                    iconColor: DesignTokens.Colors.accentOrange,
                    title: "네이버 로그인이 필요합니다",
                    subtitle: "팔로잉 목록을 보려면 '네이버 로그인'으로 다시 로그인하세요",
                    buttonLabel: "네이버 로그인",
                    action: { router.presentSheet(.login) }
                )
                .transition(.opacity)
            } else if viewModel.followingChannels.isEmpty {
                if viewModel.isLoadingFollowing {
                    skeletonLoadingView
                        .transition(.opacity)
                } else {
                    followingGateView(
                        icon: "heart",
                        iconColor: DesignTokens.Colors.accentPink,
                        title: "팔로잉 채널이 없습니다",
                        subtitle: "치지직에서 채널을 팔로우하면 여기서 확인할 수 있어요",
                        buttonLabel: nil,
                        action: nil
                    )
                    .transition(.opacity)
                }
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .navigationTitle("")
        .toolbar(.hidden)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenuButton
            }
        }
        // 필터/정렬 관련 값 변경 시 1회만 recomputeFiltered() 호출되도록 통합
        .onChange(of: sortOrder) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: filterLiveOnly) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: selectedCategory) { _, _ in resetPaginationAndRecompute() }
        .onChange(of: searchText) { _, _ in
            _searchDebounceTask?.cancel()
            _searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                recomputeFiltered()
            }
        }
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

    // MARK: - Header Section (v1-inspired gradient hero)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // 그라디언트 아이콘
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.chzzkGreen.opacity(0.15),
                                    DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)


                    Image(systemName: "person.2.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("팔로잉")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    HStack(spacing: 6) {
                        Text("내가 팔로우하는 채널")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        if !viewModel.followingChannels.isEmpty {
                            Text("•")
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(viewModel.followingChannels.count)개")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }

                        if viewModel.followingLiveCount > 0 {
                            Text("•")
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 6, height: 6)
                                Text("\(viewModel.followingLiveCount)개 라이브")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                        }
                    }
                }

                Spacer()

                // 새로고침 버튼
                Button {
                    Task { await viewModel.loadFollowingChannels() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(viewModel.isLoadingFollowing ? 0.6 : 1.0)
                        Text("새로고침")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DesignTokens.Gradients.primary)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                        }
                    )

                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingFollowing)

                // 멀티라이브 토글 버튼
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showMultiLive.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.split.2x2")
                            .font(.system(size: 13, weight: .semibold))
                        Text("멀티라이브")
                            .font(.system(size: 13, weight: .semibold))
                        if !multiLiveManager.sessions.isEmpty {
                            Text("\(multiLiveManager.sessions.count)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.2)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(showMultiLive
                                    ? LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : DesignTokens.Gradients.primary)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                        }
                    )
                }
                .buttonStyle(.plain)

                // 팔로잉 목록 숨기기/보이기 (멀티라이브 활성 시)
                if showMultiLive {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideFollowingList.toggle()
                        }
                    } label: {
                        Image(systemName: hideFollowingList ? "sidebar.leading" : "sidebar.squares.leading")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DesignTokens.Colors.surfaceOverlay)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(hideFollowingList ? "팔로잉 목록 보이기" : "팔로잉 목록 숨기기")
                    .transition(.scale.combined(with: .opacity))
                }

                // 업데이트 시간
                if let cachedAt = viewModel.followingCachedAt {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(cachedAt, style: .relative)
                            .font(.system(size: 10, weight: .regular).monospacedDigit())
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignTokens.Colors.surfaceOverlay, in: Capsule())
                    .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5))
                }
            }

            // 핵심 통계 인라인 (라이브 채널이 있을 때)
            if viewModel.followingLiveCount > 0 || viewModel.followingTotalViewers > 0 {
                HStack(spacing: DesignTokens.Spacing.lg) {
                    statIndicator(
                        icon: "heart.fill",
                        value: "\(viewModel.followingChannels.count)",
                        label: "팔로잉",
                        color: DesignTokens.Colors.accentPink
                    )
                    statIndicator(
                        icon: "dot.radiowaves.left.and.right",
                        value: "\(viewModel.followingLiveCount)",
                        label: "라이브",
                        color: DesignTokens.Colors.live
                    )
                    if viewModel.followingTotalViewers > 0 {
                        statIndicator(
                            icon: "eye.fill",
                            value: formatShortCount(viewModel.followingTotalViewers),
                            label: "시청 중",
                            color: DesignTokens.Colors.accentBlue
                        )
                    }
                    if viewModel.followingLiveRate > 0 {
                        statIndicator(
                            icon: "chart.bar.fill",
                            value: "\(viewModel.followingLiveRate)%",
                            label: "라이브율",
                            color: DesignTokens.Colors.accentPurple
                        )
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Search & Filter Card (v1-inspired)

    private var searchAndFilterCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("검색 및 필터")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            VStack(spacing: DesignTokens.Spacing.md) {
                // 검색바
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            searchText.isEmpty
                                ? DesignTokens.Colors.textTertiary
                                : DesignTokens.Colors.chzzkGreen
                        )

                    TextField("채널 검색...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular))

                    if !searchText.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { searchText = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.Colors.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            searchText.isEmpty
                                ? DesignTokens.Glass.borderColor
                                : DesignTokens.Colors.chzzkGreen.opacity(0.3),
                            lineWidth: 0.5
                        )
                )

                // 필터 버튼들 (전체/라이브)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    filterToggleButton(
                        isActive: !filterLiveOnly,
                        icon: "person.3.fill",
                        title: "전체",
                        count: viewModel.followingChannels.count
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            filterLiveOnly = false
                            selectedCategory = nil
                        }
                    }

                    filterToggleButton(
                        isActive: filterLiveOnly,
                        icon: "dot.radiowaves.left.and.right",
                        title: "라이브",
                        count: viewModel.followingLiveCount
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            filterLiveOnly = true
                            selectedCategory = nil
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Filter Toggle Button

    private func filterToggleButton(isActive: Bool, icon: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isActive ? DesignTokens.Colors.textOnOverlay.opacity(0.8) : DesignTokens.Colors.textTertiary)
                }
            }
            .foregroundStyle(isActive ? DesignTokens.Colors.textOnOverlay : DesignTokens.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignTokens.Gradients.primary)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignTokens.Colors.surfaceElevated)
                    }
                }
            )

        }
        .buttonStyle(.plain)
    }

    private func statIndicator(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - Main Content (widget-style card layout)

    private let mlPanelMinWidth: CGFloat = 400
    private let mlPanelMaxRatio: CGFloat = 0.85

    private var mainContent: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let effectiveWidth = mlPanelWidth - dividerDragOffset
            let clampedPanelWidth = min(max(effectiveWidth, mlPanelMinWidth), totalWidth * mlPanelMaxRatio)

            HStack(spacing: 0) {
                // 왼쪽: 팔로잉 채널 목록
                if !hideFollowingList || !showMultiLive {
                    followingListContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // 오른쪽: 멀티라이브 패널 (활성화 시)
                if showMultiLive {
                    if !hideFollowingList {
                        mlDividerHandle
                    }

                    multiLiveInlinePanel
                        .frame(width: hideFollowingList ? totalWidth : clampedPanelWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(isDraggingDivider ? nil : .easeInOut(duration: 0.3), value: showMultiLive)
        .animation(isDraggingDivider ? nil : .easeInOut(duration: 0.3), value: hideFollowingList)
    }

    private var mlDividerHandle: some View {
        Rectangle()
            .fill(isDraggingDivider ? DesignTokens.Colors.chzzkGreen.opacity(0.6) : DesignTokens.Glass.dividerColor.opacity(0.5))
            .frame(width: isDraggingDivider ? 3 : 1)
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isDraggingDivider ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    .frame(width: 4, height: 36)
                    .opacity(isDraggingDivider ? 1 : 0.6)
            }
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dividerDragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onChanged { _ in
                        isDraggingDivider = true
                    }
                    .onEnded { value in
                        mlPanelWidth -= value.translation.width
                        isDraggingDivider = false
                    }
            )
    }

    // MARK: - Following List Content

    private var followingListContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.xl) {
                // 헤더 섹션
                headerSection

                // 검색 및 필터 카드
                searchAndFilterCard

                // 카테고리 필터 칩 (라이브가 있을 때만)
                if !liveCategories.isEmpty {
                    categoryFilterChips
                }

                // 검색 결과 없음
                if cachedLive.isEmpty && cachedAllOffline.isEmpty {
                    widgetCard {
                        emptySearchResult
                    }
                } else {
                    // ── 라이브 채널 카드 그리드 (위젯 카드)
                    if !cachedLive.isEmpty {
                        widgetCard {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                                sectionHeader(
                                    icon: "dot.radiowaves.left.and.right",
                                    title: "라이브 중",
                                    count: totalLiveCount,
                                    color: DesignTokens.Colors.live
                                )

                                livePagingView

                                if totalLivePages > 1 {
                                    pageNavigator(
                                        currentPage: $livePageIndex,
                                        totalPages: totalLivePages,
                                        accentColor: DesignTokens.Colors.live
                                    )
                                }
                            }
                        }
                    }

                    // ── 오프라인 채널 리스트 (위젯 카드)
                    if !filterLiveOnly && totalOfflineCount > 0 {
                        widgetCard {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                                sectionHeader(
                                    icon: "moon.zzz.fill",
                                    title: "오프라인",
                                    count: totalOfflineCount,
                                    color: DesignTokens.Colors.textTertiary
                                )

                                offlinePagingView

                                if totalOfflinePages > 1 {
                                    pageNavigator(
                                        currentPage: $offlinePageIndex,
                                        totalPages: totalOfflinePages,
                                        accentColor: DesignTokens.Colors.accentPurple
                                    )
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xl)
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    /// 위젯 스타일 카드 래퍼 (v1-inspired material card)
    private func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                    )
            )
            .shadow(
                color: DesignTokens.Shadow.card.color,
                radius: DesignTokens.Shadow.card.radius,
                y: DesignTokens.Shadow.card.y
            )
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
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textOnOverlay : DesignTokens.Colors.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.textOnOverlay.opacity(0.85) : DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs + 1)
            .background {
                if isSelected {
                    Capsule().fill(
                        LinearGradient(
                            colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                } else {
                    Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.8))
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.7) : DesignTokens.Glass.borderColor,
                    lineWidth: isSelected ? 1.0 : 0.5
                )
            )

        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }

            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(color.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 0.5))

            // 얇은 구분선
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.05), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)

            Spacer()
        }
    }

    // MARK: - Live Paging View (슬라이딩 페이지 전환)

    private var livePagingView: some View {
        GeometryReader { geo in
            let cardHeight = livecardHeight(for: geo.size.width)
            let maxRows = Int(ceil(Double(min(liveItemsPerPage, totalLiveCount)) / Double(liveColumns)))
            let spacing: CGFloat = DesignTokens.Spacing.sm
            let gridHeight = CGFloat(max(maxRows, 1)) * (cardHeight + spacing) - spacing + DesignTokens.Spacing.xs * 2

            // 현재 페이지만 렌더링 — 보이지 않는 페이지의 LivePulseBadge 애니메이션 제거
            liveGridPage(livePageIndex)
                .frame(width: geo.size.width, height: gridHeight, alignment: .top)
                .id(livePageIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: livePageIndex)
                .preference(key: LiveGridHeightKey.self, value: gridHeight)
        }
        .frame(height: computedLiveGridHeight)
        .clipped()
        .onPreferenceChange(LiveGridHeightKey.self) { height in
            if abs(height - computedLiveGridHeight) > 1 {
                computedLiveGridHeight = height
            }
        }
    }

    /// 실제 컨테이너 너비로 16:9 카드 높이 계산
    private func livecardHeight(for containerWidth: CGFloat) -> CGFloat {
        let totalSpacing = DesignTokens.Spacing.sm * CGFloat(liveColumns - 1)
        let cardWidth = (containerWidth - totalSpacing) / CGFloat(liveColumns)
        let imageHeight = cardWidth * (9.0 / 16.0)  // 16:9 비율
        let infoHeight: CGFloat = 42
        return imageHeight + infoHeight
    }

    private func liveGridPage(_ page: Int) -> some View {
        let channels = liveChannelsForPage(page)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), count: liveColumns),
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                FollowingLiveCard(channel: channel, index: page * liveItemsPerPage + index) {
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
                    if channel.isLive {
                        Button {
                            Task { await multiLiveManager.addSession(channelId: channel.channelId) }
                            showMultiLive = true
                        } label: {
                            Label("멀티라이브에 추가", systemImage: "rectangle.split.2x2")
                        }
                        .disabled(!multiLiveManager.canAddSession)
                        Divider()
                    }
                    channelNotificationMenu(channelId: channel.channelId, channelName: channel.channelName)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - Offline Paging View (슬라이딩 페이지 전환)

    private var offlinePagingView: some View {
        GeometryReader { geo in
            // 현재 페이지만 렌더링
            offlineListPage(offlinePageIndex)
                .frame(width: geo.size.width)
                .id(offlinePageIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: offlinePageIndex)
        }
        .frame(height: offlinePageHeight)
        .clipped()
    }

    private var offlinePageHeight: CGFloat {
        let count = min(offlineItemsPerPage, max(1, totalOfflineCount))
        let rowHeight: CGFloat = 44
        return CGFloat(count) * rowHeight
    }

    private func offlineListPage(_ page: Int) -> some View {
        let channels = offlineChannelsForPage(page)
        return LazyVStack(spacing: 2) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { idx, channel in
                FollowingOfflineRow(channel: channel, index: idx)
                    .equatable()
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
                    Task { appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("방송 시작 알림", systemImage: "dot.radiowaves.left.and.right")
            }

            Toggle(isOn: Binding(
                get: { setting.notifyOnCategoryChange },
                set: { newValue in
                    var updated = setting
                    updated.notifyOnCategoryChange = newValue
                    Task { appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("카테고리 변경 알림", systemImage: "tag")
            }

            Toggle(isOn: Binding(
                get: { setting.notifyOnTitleChange },
                set: { newValue in
                    var updated = setting
                    updated.notifyOnTitleChange = newValue
                    Task { appState.settingsStore.updateChannelNotification(updated) }
                }
            )) {
                Label("제목 변경 알림", systemImage: "textformat")
            }
        }
    }

    // MARK: - Page Navigator

    private func pageNavigator(currentPage: Binding<Int>, totalPages: Int, accentColor: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()

            // 이전 버튼
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPage.wrappedValue = max(0, currentPage.wrappedValue - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(currentPage.wrappedValue > 0 ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.4))
                    .frame(width: 26, height: 26)
                    .background(
                        currentPage.wrappedValue > 0
                            ? AnyShapeStyle(accentColor.opacity(0.1))
                            : AnyShapeStyle(DesignTokens.Colors.surfaceElevated.opacity(0.5)),
                        in: Circle()
                    )
                    .overlay(Circle()
                        .strokeBorder(
                            currentPage.wrappedValue > 0
                                ? accentColor.opacity(0.25)
                                : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        ))
            }
            .buttonStyle(.plain)
            .disabled(currentPage.wrappedValue == 0)

            // 페이지 인디케이터
            if totalPages <= 7 {
                HStack(spacing: 4) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        Capsule()
                            .fill(page == currentPage.wrappedValue ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.3))
                            .frame(
                                width: page == currentPage.wrappedValue ? 16 : 5,
                                height: 5
                            )
                            .animation(.easeInOut(duration: 0.2), value: currentPage.wrappedValue)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    currentPage.wrappedValue = page
                                }
                            }
                    }
                }
            } else {
                Text("\(currentPage.wrappedValue + 1) / \(totalPages)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            // 다음 버튼
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPage.wrappedValue = min(totalPages - 1, currentPage.wrappedValue + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(currentPage.wrappedValue < totalPages - 1 ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.4))
                    .frame(width: 26, height: 26)
                    .background(
                        currentPage.wrappedValue < totalPages - 1
                            ? AnyShapeStyle(accentColor.opacity(0.1))
                            : AnyShapeStyle(DesignTokens.Colors.surfaceElevated.opacity(0.5)),
                        in: Circle()
                    )
                    .overlay(Circle()
                        .strokeBorder(
                            currentPage.wrappedValue < totalPages - 1
                                ? accentColor.opacity(0.25)
                                : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        ))
            }
            .buttonStyle(.plain)
            .disabled(currentPage.wrappedValue == totalPages - 1)

            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - Skeleton Loading View

    @State private var skeletonAppeared = false

    private var skeletonLoadingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.xl) {
                // 스켈레톤 헤더
                skeletonHeaderCard

                // 라이브 스켈레톤 카드
                widgetCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        sectionHeader(icon: "dot.radiowaves.left.and.right", title: "라이브 중", count: 0, color: DesignTokens.Colors.live)
                            .redacted(reason: .placeholder)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), count: liveColumns),
                            spacing: DesignTokens.Spacing.sm
                        ) {
                            ForEach(0..<8, id: \.self) { idx in
                                SkeletonLiveCard()
                                    .opacity(skeletonAppeared ? 1 : 0)
                                    .offset(y: skeletonAppeared ? 0 : 6)
                                    .animation(
                                        .easeOut(duration: 0.3).delay(Double(idx) * 0.03),
                                        value: skeletonAppeared
                                    )
                            }
                        }
                    }
                }

                // 오프라인 스켈레톤 카드
                widgetCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        sectionHeader(icon: "moon.zzz.fill", title: "오프라인", count: 0, color: DesignTokens.Colors.textTertiary)
                            .redacted(reason: .placeholder)

                        VStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                HStack(spacing: 10) {
                                    Circle().fill(DesignTokens.Colors.surfaceElevated).frame(width: 34, height: 34).shimmer()
                                    VStack(alignment: .leading, spacing: 4) {
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                            .fill(DesignTokens.Colors.surfaceElevated)
                                            .frame(height: 10).shimmer()
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                            .fill(DesignTokens.Colors.surfaceElevated)
                                            .frame(width: 60, height: 8).shimmer()
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onAppear { skeletonAppeared = true }
    }

    /// 스켈레톤 헤더 카드
    private var skeletonHeaderCard: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Circle()
                .fill(DesignTokens.Colors.surfaceElevated)
                .frame(width: 52, height: 52)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 100, height: 20)
                    .shimmer()
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 160, height: 12)
                    .shimmer()
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase)
        )
    }

    // MARK: - Empty Search / Gate Views

    private var emptySearchResult: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // 아이콘 (더블 링)
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.textTertiary.opacity(0.04))
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(DesignTokens.Colors.textTertiary.opacity(0.08), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(DesignTokens.Colors.textTertiary.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 48, height: 48)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            VStack(spacing: 6) {
                Text("검색 결과가 없습니다")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if !searchText.isEmpty {
                    Text("'\(searchText)'와 일치하는 채널이 없습니다")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            // 필터 초기화 버튼들
            HStack(spacing: 6) {
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
            }

            if !searchText.isEmpty || selectedCategory != nil || filterLiveOnly {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        searchText = ""
                        selectedCategory = nil
                        filterLiveOnly = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("모든 필터 초기화")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surfaceOverlay, in: Capsule())
                    .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, DesignTokens.Spacing.xl)
    }

    private func filterResetButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .medium))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5))
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
        VStack(spacing: DesignTokens.Spacing.xl) {
            // 아이콘 (더블 링 + 글로우)
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.06))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(iconColor.opacity(0.1), lineWidth: 1)
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(iconColor.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(iconColor)
            }

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if let label = buttonLabel, let action {
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                        Text(label)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
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
                    withAnimation(.easeInOut(duration: 0.25)) { sortOrder = order }
                } label: {
                    HStack {
                        Label(order.rawValue, systemImage: order.icon)
                        if sortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sortOrder.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(sortOrder.rawValue)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Inline Multi-Live Panel

    private var multiLiveInlinePanel: some View {
        VStack(spacing: 0) {
            // 탭 바
            MLTabBar(
                manager: multiLiveManager,
                isGridLayout: Binding(
                    get: { multiLiveManager.isGridLayout },
                    set: { multiLiveManager.isGridLayout = $0 }
                ),
                onAdd: { withAnimation(DesignTokens.Animation.snappy) {
                    showMLAddChannel.toggle()
                    if showMLAddChannel { showMLSettings = false }
                }},
                isAddPanelOpen: showMLAddChannel,
                onSettings: { withAnimation(DesignTokens.Animation.snappy) {
                    showMLSettings.toggle()
                    if showMLSettings { showMLAddChannel = false }
                }},
                isSettingsPanelOpen: showMLSettings,
                hideFollowingList: hideFollowingList,
                onToggleFollowingList: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideFollowingList = false
                    }
                }
            )

            // 콘텐츠 영역
            HStack(spacing: 0) {
                ZStack {
                    if multiLiveManager.sessions.isEmpty {
                        MLEmptyState(onAdd: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                showMLAddChannel = true
                            }
                        })
                    } else if multiLiveManager.isGridLayout && multiLiveManager.sessions.count >= 2 {
                        MLGridLayout(manager: multiLiveManager, appState: appState, onAdd: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                showMLAddChannel = true
                            }
                        })
                    } else {
                        // [VLC 충돌 방지] 안정 컨테이너 패턴: opacity/zIndex로 가시성 전환
                        ForEach(multiLiveManager.sessions) { session in
                            let isActive = session.id == multiLiveManager.selectedSessionId
                            MLPlayerPane(session: session, appState: appState, isActive: isActive)
                                .opacity(isActive ? 1 : 0)
                                .zIndex(isActive ? 1 : 0)
                                .allowsHitTesting(isActive)
                                .transaction { $0.animation = nil }
                        }
                        .animation(nil, value: multiLiveManager.sessions.count)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // 채널 추가 슬라이드 패널
                if showMLAddChannel {
                    MLAddChannelPanel(
                        manager: multiLiveManager,
                        appState: appState,
                        isPresented: $showMLAddChannel,
                        onError: { mlAddError = $0 }
                    )
                    .environment(appState)
                    .transition(.move(edge: .trailing))
                    .animation(DesignTokens.Animation.contentTransition, value: showMLAddChannel)
                }

                // 설정 슬라이드 패널
                if showMLSettings {
                    MLSettingsPanel(
                        manager: multiLiveManager,
                        settingsStore: appState.settingsStore,
                        isPresented: $showMLSettings
                    )
                    .transition(.move(edge: .trailing))
                    .animation(DesignTokens.Animation.contentTransition, value: showMLSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(multiLiveManager.sessions.isEmpty ? DesignTokens.Colors.background : Color.black)
        .clipped()
        .task {
            if multiLiveManager.sessions.isEmpty {
                await multiLiveManager.restoreState(appState: appState)
            }
        }
        .alert("채널 추가 실패", isPresented: Binding(
            get: { mlAddError != nil },
            set: { if !$0 { mlAddError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(mlAddError ?? "")
        }
    }
}
