// MARK: - FollowingView+List.swift
// FollowingView 확장 — 리스트 콘텐츠, 카테고리 칩, 라이브 그리드, 오프라인, 페이지네이터, 스켈레톤

import SwiftUI
import CViewCore

extension FollowingView {

    // MARK: - Category Filter Chips

    private var maxVisibleChips: Int { 8 }

    var categoryFilterChips: some View {
        let visibleCategories = Array(liveCategoryCounts.prefix(maxVisibleChips))
        let overflowCategories = liveCategoryCounts.count > maxVisibleChips
            ? Array(liveCategoryCounts.dropFirst(maxVisibleChips))
            : []
        let isOverflowSelected = overflowCategories.contains { $0.name == selectedCategory }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // 전체 칩
                categoryChip(label: "전체", count: 0, isSelected: selectedCategory == nil) {
                    withAnimation(DesignTokens.Animation.indicator) {
                        selectedCategory = nil
                    }
                }
                ForEach(visibleCategories, id: \.name) { cat in
                    categoryChip(label: cat.name, count: cat.count, isSelected: selectedCategory == cat.name) {
                        withAnimation(DesignTokens.Animation.indicator) {
                            selectedCategory = selectedCategory == cat.name ? nil : cat.name
                        }
                    }
                }
                // 오버플로우 „더보기" 메뉴
                if !overflowCategories.isEmpty {
                    Menu {
                        ForEach(overflowCategories, id: \.name) { cat in
                            Button {
                                withAnimation(DesignTokens.Animation.indicator) {
                                    selectedCategory = selectedCategory == cat.name ? nil : cat.name
                                }
                            } label: {
                                HStack {
                                    Text(cat.name)
                                    Spacer()
                                    Text("\(cat.count)")
                                        .foregroundStyle(.secondary)
                                    if selectedCategory == cat.name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("+\(overflowCategories.count)")
                                .font(DesignTokens.Typography.custom(size: layout.chipLabelSize + 1, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(isOverflowSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isOverflowSelected
                                      ? DesignTokens.Colors.chzzkGreen.opacity(0.14)
                                      : DesignTokens.Colors.surfaceElevated.opacity(0.5))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    isOverflowSelected
                                        ? DesignTokens.Colors.chzzkGreen.opacity(0.35)
                                        : DesignTokens.Glass.borderColorLight.opacity(0.35),
                                    lineWidth: isOverflowSelected ? 1 : 0.5
                                )
                        }
                        .overlay(alignment: .bottom) {
                            if isOverflowSelected {
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(DesignTokens.Colors.chzzkGreen)
                                    .frame(height: 2)
                                    .padding(.horizontal, 3)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .scrollClipDisabled(false)
    }

    func categoryChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: layout.chipLabelSize + 1, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.custom(size: layout.chipCountSize + 1, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.8) : DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))

                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "categoryChipPill", in: categoryPillNS)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(height: 2)
                        .padding(.horizontal, 3)
                        .matchedGeometryEffect(id: "categoryChipBar", in: categoryPillNS)
                }
            }
            .fixedSize()
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
    }

    // MARK: - Section Header

    func sectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {        HStack(spacing: DesignTokens.Spacing.sm) {
            // 좌측 accent bar
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                .fill(color)
                .frame(width: 3.5, height: 22)

            Image(systemName: icon)
                .font(.system(size: layout.sectionIconSize + 2, weight: .bold))
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .speed(0.5), value: count)

            Text(title)
                .font(DesignTokens.Typography.custom(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            // 카운트 배지
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: layout.sectionCountSize + 1, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(color.opacity(0.75), in: Capsule())
                .animation(DesignTokens.Animation.snappy, value: count)

            Spacer()
        }
    }

    // MARK: - Live Avatar Strip (프로필 이미지 기반 수평 스크롤)

    var liveAvatarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: layout.liveAvatarSpacing) {
                ForEach(Array(cachedLive.enumerated()), id: \.element.id) { index, channel in
                    FollowingLiveAvatarItem(
                        channel: channel,
                        index: index,
                        onPlay: {
                            // [2026-04-19] 라이브 메뉴는 항상 단일 인스턴스(.embedded) 경로 사용 —
                            // 설정의 useSeparateProcesses 값과 무관하게 인라인 멀티라이브 패널로 표시.
                            Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine, presentationOverride: .embedded) }
                            showMultiLive = true
                        },
                        layout: layout
                    )
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
                                // [2026-04-19] 라이브 메뉴 컨텍스트 메뉴: 항상 .embedded 경로
                                Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine, presentationOverride: .embedded) }
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
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .scrollClipDisabled(false)
    }

    // MARK: - Live Paging View

    var livePagingView: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            let cardHeight = livecardHeight(for: pageWidth)
            let maxRows = Int(ceil(Double(min(liveItemsPerPage, totalLiveCount)) / Double(liveColumns)))
            let spacing: CGFloat = layout.gridSpacing
            let gridHeight = CGFloat(max(maxRows, 1)) * (cardHeight + spacing) - spacing + DesignTokens.Spacing.xs * 2

            // 현재 페이지 ± 1 동시 렌더 — 슬라이딩 전환
            let pages = liveVisiblePages
            let firstPage = pages.first ?? livePageIndex

            // 경계 저항감: 첫/마지막 페이지 과도 드래그 시 로그 감쇠
            let clampedDrag: CGFloat = {
                let raw = livePageDragOffset
                let atStart = livePageIndex == 0 && raw > 0
                let atEnd = livePageIndex >= totalLivePages - 1 && raw < 0
                if atStart || atEnd {
                    let sign: CGFloat = raw > 0 ? 1 : -1
                    return sign * min(abs(raw), pageWidth * 0.15) * 0.4
                }
                return raw
            }()

            HStack(alignment: .top, spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    liveGridPage(page)
                        .frame(width: pageWidth, height: gridHeight, alignment: .top)
                }
            }
            .offset(x: -CGFloat(livePageIndex - firstPage) * pageWidth + clampedDrag)
            .gesture(
                totalLivePages > 1 ?
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                        livePageDragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold: CGFloat = pageWidth * 0.18
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        var newPage = livePageIndex

                        if value.translation.width < -threshold || velocity < -150 {
                            newPage = min(livePageIndex + 1, totalLivePages - 1)
                        } else if value.translation.width > threshold || velocity > 150 {
                            newPage = max(livePageIndex - 1, 0)
                        }

                        withAnimation(DesignTokens.Animation.gridPageTransition) {
                            livePageIndex = newPage
                            livePageDragOffset = 0
                        }
                    }
                : nil
            )
            .animation(DesignTokens.Animation.interactive, value: livePageDragOffset)
            .animation(livePageDragOffset == 0 ? DesignTokens.Animation.gridPageTransition : nil, value: livePageIndex)
            .preference(key: LiveGridHeightKey.self, value: gridHeight)
        }
        .frame(height: computedLiveGridHeight)
        .clipped()
        .contentShape(Rectangle())
        .onPreferenceChange(LiveGridHeightKey.self) { height in
            if abs(height - computedLiveGridHeight) > 1 {
                DispatchQueue.main.async {
                    computedLiveGridHeight = height
                }
            }
        }
    }

    /// 현재 페이지 ± 1 범위의 유효 페이지 인덱스
    private var liveVisiblePages: [Int] {
        let maxPage = totalLivePages - 1
        let clampedIndex = min(max(0, livePageIndex), maxPage)
        let lower = max(0, clampedIndex - 1)
        let upper = min(maxPage, clampedIndex + 1)
        guard lower <= upper else { return [0] }
        return Array(lower...upper)
    }

    /// 실제 컨테이너 너비로 16:9 카드 높이 계산
    /// - Note: infoArea 가 `minHeight: layout.cardInfoHeight + 4` 로 렌더되므로 +4 포함해야
    ///         그리드 총 높이와 실제 렌더 높이가 일치함. (2026-04-23: 스크롤 시 하단 카드 잘림/정렬 깨짐 수정)
    func livecardHeight(for containerWidth: CGFloat) -> CGFloat {
        let totalSpacing = layout.gridSpacing * CGFloat(liveColumns - 1)
        let cardWidth = (containerWidth - totalSpacing) / CGFloat(liveColumns)
        let imageHeight = cardWidth * (9.0 / 16.0)
        let infoHeight = layout.cardInfoHeight + 4
        return imageHeight + infoHeight
    }

    func liveGridPage(_ page: Int) -> some View {
        let channels = liveChannelsForPage(page)
        // [2026-04-23] 카드별 높이 편차로 LazyVGrid row 정렬이 깨지고 스크롤 시 점프/잘림이 발생하여
        //              containerWidth 기반 결정적 높이를 각 셀에 직접 부여.
        let containerWidth = followingContentWidth
        let cellHeight = livecardHeight(for: containerWidth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: layout.gridSpacing), count: liveColumns),
            spacing: layout.gridSpacing
        ) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                FollowingLiveCard(channel: channel, index: index, onPlay: {
                    // [2026-04-19] 라이브 그리드: 항상 .embedded 경로 (단일 인스턴스)
                    Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine, presentationOverride: .embedded) }
                    showMultiLive = true
                }, onPrefetch: { channelId in
                    if let service = appState.hlsPrefetchService {
                        Task { await service.prefetch(channelId: channelId) }
                    }
                }, layout: layout)
                .equatable()
                .frame(height: cellHeight)  // [2026-04-23] 결정적 카드 높이
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
                            // [2026-04-19] 라이브 그리드 컨텍스트 메뉴: 항상 .embedded 경로
                            Task { await multiLiveManager.addSession(channelId: channel.channelId, preferredEngine: appState.settingsStore.player.preferredEngine, presentationOverride: .embedded) }
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
            let pageWidth = geo.size.width
            let pages = offlineVisiblePages
            let firstPage = pages.first ?? offlinePageIndex

            let clampedDrag: CGFloat = {
                let raw = offlinePageDragOffset
                let atStart = offlinePageIndex == 0 && raw > 0
                let atEnd = offlinePageIndex >= totalOfflinePages - 1 && raw < 0
                if atStart || atEnd {
                    let sign: CGFloat = raw > 0 ? 1 : -1
                    return sign * min(abs(raw), pageWidth * 0.15) * 0.4
                }
                return raw
            }()

            HStack(alignment: .top, spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    offlineListPage(page)
                        .frame(width: pageWidth)
                }
            }
            .offset(x: -CGFloat(offlinePageIndex - firstPage) * pageWidth + clampedDrag)
            .gesture(
                totalOfflinePages > 1 ?
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                        offlinePageDragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold: CGFloat = pageWidth * 0.18
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        var newPage = offlinePageIndex

                        if value.translation.width < -threshold || velocity < -150 {
                            newPage = min(offlinePageIndex + 1, totalOfflinePages - 1)
                        } else if value.translation.width > threshold || velocity > 150 {
                            newPage = max(offlinePageIndex - 1, 0)
                        }

                        withAnimation(DesignTokens.Animation.gridPageTransition) {
                            offlinePageIndex = newPage
                            offlinePageDragOffset = 0
                        }
                    }
                : nil
            )
            .animation(DesignTokens.Animation.interactive, value: offlinePageDragOffset)
            .animation(offlinePageDragOffset == 0 ? DesignTokens.Animation.gridPageTransition : nil, value: offlinePageIndex)
        }
        .frame(height: offlinePageHeight)
        .clipped()
        .contentShape(Rectangle())
    }

    /// 오프라인 현재 페이지 ± 1 범위
    private var offlineVisiblePages: [Int] {
        let range = max(0, offlinePageIndex - 1)...min(totalOfflinePages - 1, offlinePageIndex + 1)
        return Array(range)
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
                withAnimation(DesignTokens.Animation.gridPageTransition) {
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
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
            .disabled(currentPage.wrappedValue == 0)

            if totalPages <= 7 {
                HStack(spacing: 4) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        let isActive = page == currentPage.wrappedValue
                        ZStack {
                            Capsule()
                                .fill(DesignTokens.Colors.textTertiary.opacity(0.20))
                                .frame(width: 6, height: 6)

                            if isActive {
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: layout.pageIndicatorWidth, height: 6)
                                    // [GPU] shadow 고정 — matchedGeometry 대상 뷰에 radius 애니메이션은 과부하
                                    .shadow(color: accentColor.opacity(0.35), radius: 3)
                                    .matchedGeometryEffect(id: "pageIndicatorActive", in: pageIndicatorNS)
                            }
                        }
                        .frame(width: isActive ? layout.pageIndicatorWidth : 6, height: 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(DesignTokens.Animation.gridPageTransition) {
                                currentPage.wrappedValue = page
                            }
                        }
                    }
                }
                .animation(DesignTokens.Animation.gridPageTransition, value: currentPage.wrappedValue)
            } else {
                Text("\(currentPage.wrappedValue + 1) / \(totalPages)")
                    .font(.system(size: layout.pageTextSize, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .contentTransition(.numericText())
            }

            Button {
                withAnimation(DesignTokens.Animation.gridPageTransition) {
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
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
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
                                .padding(.vertical, DesignTokens.Spacing.sm)
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
                .symbolEffect(.pulse.byLayer, options: .speed(0.7).repeat(.continuous))

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
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.4), in: Capsule())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    /// 위젯 카드 래퍼 (모던 미니멀 카드 — 경량 렌더링)
    func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceBase.opacity(0.65))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .strokeBorder(
                                DesignTokens.Colors.surfaceElevated.opacity(0.6),
                                lineWidth: 0.5
                            )
                    }
            }
            // 카드 입장 — 부드러운 페이드인
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
