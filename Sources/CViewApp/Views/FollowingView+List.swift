// MARK: - FollowingView+List.swift
// FollowingView 확장 — 리스트 콘텐츠, 카테고리 칩, 라이브 그리드, 오프라인, 페이지네이터, 스켈레톤

import SwiftUI
import CViewCore

extension FollowingView {

    // MARK: - Category Filter Chips

    var categoryFilterChips: some View {
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
            .padding(.horizontal, layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xxs)
        }
        .drawingGroup()
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        )
    }

    func categoryChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: layout.chipLabelSize + 1, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: layout.chipCountSize + 1, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.8) : DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.14))
                } else {
                    Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                }
            }
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 1)
                } else {
                    Capsule().strokeBorder(DesignTokens.Glass.borderColor.opacity(0.15), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    func sectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 좌측 accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 20)
                .shadow(color: color.opacity(0.3), radius: 3)

            Image(systemName: icon)
                .font(.system(size: layout.sectionIconSize + 1, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text("\(count)")
                .font(.system(size: layout.sectionCountSize + 1, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())

            Spacer()
        }
    }

    // MARK: - Live Paging View

    var livePagingView: some View {
        GeometryReader { geo in
            let cardHeight = livecardHeight(for: geo.size.width)
            let maxRows = Int(ceil(Double(min(liveItemsPerPage, totalLiveCount)) / Double(liveColumns)))
            let spacing: CGFloat = layout.gridSpacing
            let gridHeight = CGFloat(max(maxRows, 1)) * (cardHeight + spacing) - spacing + DesignTokens.Spacing.xs * 2

            liveGridPage(livePageIndex)
                .frame(width: geo.size.width, height: gridHeight, alignment: .top)
                .drawingGroup()
                .id(livePageIndex)
                .transition(.opacity)
                .animation(DesignTokens.Animation.gridPageTransition, value: livePageIndex)
                .preference(key: LiveGridHeightKey.self, value: gridHeight)
        }
        .frame(height: computedLiveGridHeight)
        .clipped()
        .onPreferenceChange(LiveGridHeightKey.self) { height in
            if abs(height - computedLiveGridHeight) > 1 {
                DispatchQueue.main.async {
                    computedLiveGridHeight = height
                }
            }
        }
    }

    /// 실제 컨테이너 너비로 16:9 카드 높이 계산
    func livecardHeight(for containerWidth: CGFloat) -> CGFloat {
        let totalSpacing = layout.gridSpacing * CGFloat(liveColumns - 1)
        let cardWidth = (containerWidth - totalSpacing) / CGFloat(liveColumns)
        let imageHeight = cardWidth * (9.0 / 16.0)
        let infoHeight: CGFloat = 42
        return imageHeight + infoHeight
    }

    func liveGridPage(_ page: Int) -> some View {
        let channels = liveChannelsForPage(page)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: layout.gridSpacing), count: liveColumns),
            spacing: layout.gridSpacing
        ) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                FollowingLiveCard(channel: channel, index: index, onPlay: {
                    Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine) }
                    showMultiLive = true
                }, onPrefetch: { channelId in
                    if let service = appState.hlsPrefetchService {
                        Task { await service.prefetch(channelId: channelId) }
                    }
                }, layout: layout)
                .equatable()
                .onTapGesture {
                    router.navigate(to: .live(channelId: channel.channelId))
                }
                .contextMenu {
                    Button {
                        router.navigate(to: .channelDetail(channelId: channel.channelId))
                    } label: {
                        Label("채널 정보 보기", systemImage: "person.crop.circle")
                    }
                    if channel.isLive {
                        Button {
                            Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine) }
                            showMultiLive = true
                        } label: {
                            Label("멀티라이브에 추가", systemImage: "rectangle.split.2x2")
                        }
                        .disabled(!multiLiveManager.canAddSession)
                    }
                    Divider()
                    channelNotificationMenu(channelId: channel.channelId, channelName: channel.channelName)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - Offline Paging View

    var offlinePagingView: some View {
        GeometryReader { geo in
            offlineListPage(offlinePageIndex)
                .frame(width: geo.size.width)
                .drawingGroup()
                .id(offlinePageIndex)
                .transition(.opacity)
                .animation(DesignTokens.Animation.gridPageTransition, value: offlinePageIndex)
        }
        .frame(height: offlinePageHeight)
        .clipped()
    }

    var offlinePageHeight: CGFloat {
        let count = min(offlineItemsPerPage, max(1, totalOfflineCount))
        let rowHeight: CGFloat = layout.offlineRowHeight
        return CGFloat(count) * rowHeight
    }

    func offlineListPage(_ page: Int) -> some View {
        let channels = offlineChannelsForPage(page)
        return LazyVStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { idx, channel in
                FollowingOfflineRow(channel: channel, index: idx, layout: layout)
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
    func channelNotificationMenu(channelId: String, channelName: String) -> some View {
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

    func pageNavigator(currentPage: Binding<Int>, totalPages: Int, accentColor: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer()

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    currentPage.wrappedValue = max(0, currentPage.wrappedValue - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: layout.pageChevronSize + 1, weight: .semibold))
                    .foregroundStyle(currentPage.wrappedValue > 0 ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.3))
                    .frame(width: layout.pageButtonSize + 2, height: layout.pageButtonSize + 2)
                    .background(
                        currentPage.wrappedValue > 0
                            ? AnyShapeStyle(accentColor.opacity(0.10))
                            : AnyShapeStyle(Color.clear),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                currentPage.wrappedValue > 0 ? accentColor.opacity(0.15) : Color.clear,
                                lineWidth: 0.5
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(currentPage.wrappedValue == 0)

            if totalPages <= 7 {
                HStack(spacing: 4) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        Capsule()
                            .fill(page == currentPage.wrappedValue ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.20))
                            .frame(width: page == currentPage.wrappedValue ? layout.pageIndicatorWidth : 6, height: 6)
                            .shadow(color: page == currentPage.wrappedValue ? accentColor.opacity(0.3) : .clear, radius: 3)
                            .animation(DesignTokens.Animation.micro, value: currentPage.wrappedValue)
                            .onTapGesture {
                                withAnimation(DesignTokens.Animation.snappy) {
                                    currentPage.wrappedValue = page
                                }
                            }
                    }
                }
            } else {
                Text("\(currentPage.wrappedValue + 1) / \(totalPages)")
                    .font(.system(size: layout.pageTextSize, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    currentPage.wrappedValue = min(totalPages - 1, currentPage.wrappedValue + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: layout.pageChevronSize + 1, weight: .semibold))
                    .foregroundStyle(currentPage.wrappedValue < totalPages - 1 ? accentColor : DesignTokens.Colors.textTertiary.opacity(0.3))
                    .frame(width: layout.pageButtonSize + 2, height: layout.pageButtonSize + 2)
                    .background(
                        currentPage.wrappedValue < totalPages - 1
                            ? AnyShapeStyle(accentColor.opacity(0.10))
                            : AnyShapeStyle(Color.clear),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                currentPage.wrappedValue < totalPages - 1 ? accentColor.opacity(0.15) : Color.clear,
                                lineWidth: 0.5
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(currentPage.wrappedValue == totalPages - 1)

            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    // MARK: - Skeleton Loading View

    var skeletonLoadingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignTokens.Spacing.xl) {
                skeletonHeaderCard

                widgetCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        sectionHeader(icon: "dot.radiowaves.left.and.right", title: "라이브 중", count: 0, color: DesignTokens.Colors.live)
                            .redacted(reason: .placeholder)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: layout.gridSpacing), count: liveColumns),
                            spacing: layout.gridSpacing
                        ) {
                            ForEach(0..<8, id: \.self) { idx in
                                SkeletonLiveCard(layout: layout)
                                    .opacity(skeletonAppeared ? 1 : 0)
                                    .animation(
                                        DesignTokens.Animation.normal.delay(Double(idx) * 0.03),
                                        value: skeletonAppeared
                                    )
                            }
                        }
                    }
                }

                widgetCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        sectionHeader(icon: "moon.zzz.fill", title: "오프라인", count: 0, color: DesignTokens.Colors.textTertiary)
                            .redacted(reason: .placeholder)

                        VStack(spacing: DesignTokens.Spacing.xxs) {
                            ForEach(0..<5, id: \.self) { _ in
                                HStack(spacing: 10) {
                                    Circle().fill(DesignTokens.Colors.surfaceElevated).frame(width: layout.skeletonProfileSize, height: layout.skeletonProfileSize).shimmer()
                                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
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

    var skeletonHeaderCard: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                .frame(width: layout.skeletonHeaderIconSize, height: layout.skeletonHeaderIconSize)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                    .frame(width: layout.skeletonHeaderTitleWidth, height: 16)
                    .shimmer()
                RoundedRectangle(cornerRadius: DesignTokens.Radius.full)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.3))
                    .frame(width: layout.skeletonHeaderTitleWidth * 1.4, height: 10)
                    .shimmer()
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.lg)
    }

    // MARK: - Empty Search Result

    var emptySearchResult: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: layout.emptyIconSize, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("검색 결과가 없습니다")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if !searchText.isEmpty {
                    Text("'\(searchText)'와 일치하는 채널이 없습니다")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
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
                    withAnimation(DesignTokens.Animation.normal) {
                        searchText = ""
                        selectedCategory = nil
                        filterLiveOnly = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .medium))
                        Text("모든 필터 초기화")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(DesignTokens.Colors.surfaceElevated.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.top, DesignTokens.Spacing.lg)
    }

    func filterResetButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9, weight: .regular))
                Text(label).font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 3)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 위젯 카드 래퍼 (모던 글래스 카드)
    func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceBase.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .strokeBorder(
                                DesignTokens.Glass.borderColor.opacity(0.35),
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}
