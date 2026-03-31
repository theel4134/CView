// MARK: - FollowingView+Header.swift
// FollowingView 확장 — 헤더 섹션, 검색/필터 카드, 정렬 메뉴

import SwiftUI
import CViewCore

extension FollowingView {

    // MARK: - Header Section (모던 리디자인)

    var headerSection: some View {
        VStack(alignment: .leading, spacing: layout.sizeClass == .ultraCompact ? 6 : DesignTokens.Spacing.md) {
            // 상단: 타이틀 + 액션
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("팔로잉")
                            .font(.system(size: layout.sizeClass == .ultraCompact ? 20 : 26, weight: .bold, design: .rounded))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        // 라이브 카운트 인라인 배지
                        if viewModel.followingLiveCount > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: DesignTokens.Colors.live.opacity(0.5), radius: 3)
                                Text("\(viewModel.followingLiveCount) LIVE")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(DesignTokens.Colors.live.opacity(0.12))
                            )
                        }
                    }

                    // 서브타이틀: 시청자 요약
                    if viewModel.followingTotalViewers > 0 && !layout.sizeClass.isNarrow {
                        Text("총 시청자 \(formatShortCount(viewModel.followingTotalViewers))명")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                if let cachedAt = viewModel.followingCachedAt, !layout.sizeClass.isNarrow {
                    Text(cachedAt, style: .relative)
                        .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                }

                headerActionButtons
            }

            // 하단: 스탯 배지 (narrow이 아닐 때만 별도 행)
            if !layout.sizeClass.isNarrow {
                headerStatBadges
            }
        }
        .padding(.horizontal, layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.lg)
        .padding(.vertical, layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.lg)
    }

    /// 헤더 통계 배지 (채널수, 라이브수, 시청자수)
    var headerStatBadges: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if !viewModel.followingChannels.isEmpty {
                headerBadge(
                    icon: "heart.fill",
                    text: "\(viewModel.followingChannels.count)",
                    color: DesignTokens.Colors.accentPink
                )
            }
            if viewModel.followingLiveCount > 0 {
                headerBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "\(viewModel.followingLiveCount) 라이브",
                    color: DesignTokens.Colors.live
                )
            }
            if viewModel.followingTotalViewers > 0 {
                headerBadge(
                    icon: "eye.fill",
                    text: formatShortCount(viewModel.followingTotalViewers),
                    color: DesignTokens.Colors.accentBlue
                )
            }
            if viewModel.followingLiveRate > 0 {
                headerBadge(
                    icon: "chart.bar.fill",
                    text: "\(viewModel.followingLiveRate)%",
                    color: DesignTokens.Colors.accentPurple
                )
            }
        }
    }

    func headerBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    /// 헤더 액션 버튼 그룹
    var headerActionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 새로고침
            Button {
                Task { await viewModel.loadFollowingChannels() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(viewModel.isLoadingFollowing ? 360 : 0))
                    .animation(viewModel.isLoadingFollowing ? DesignTokens.Animation.loadingSpin : .default, value: viewModel.isLoadingFollowing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .frame(width: 28, height: 28)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
            .disabled(viewModel.isLoadingFollowing)
            .help("새로고침")

            // 멀티라이브 토글
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    showMultiLive.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.split.2x2")
                        .font(.system(size: 11, weight: .medium))
                    if !layout.sizeClass.isNarrow {
                        Text("멀티라이브")
                            .font(.system(size: 11, weight: .medium))
                    }
                    if !multiLiveManager.sessions.isEmpty {
                        Text("\(multiLiveManager.sessions.count)/\(multiLiveManager.effectiveMaxSessions)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.2)))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, layout.sizeClass.isNarrow ? 8 : 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(showMultiLive
                            ? DesignTokens.Colors.accentBlue
                            : DesignTokens.Colors.chzzkGreen)
                )
            }
            .buttonStyle(.plain)

            // 멀티채팅 토글
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    showMultiChat.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11, weight: .medium))
                    if !layout.sizeClass.isNarrow {
                        Text("멀티채팅")
                            .font(.system(size: 11, weight: .medium))
                    }
                    if !chatSessionManager.sessions.isEmpty {
                        Text("\(chatSessionManager.sessions.count)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.2)))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, layout.sizeClass.isNarrow ? 8 : 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(showMultiChat
                            ? DesignTokens.Colors.accentBlue
                            : DesignTokens.Colors.accentOrange)
                )
            }
            .buttonStyle(.plain)

            if showMultiLive || showMultiChat {
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        hideFollowingList.toggle()
                    }
                } label: {
                    Image(systemName: hideFollowingList ? "sidebar.trailing" : "sidebar.squares.trailing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(DesignTokens.Colors.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                .help(hideFollowingList ? "라이브 목록 보이기" : "라이브 목록 숨기기")
                .transition(.opacity)
            }
        }
    }

    // MARK: - Search & Filter Card

    /// 활성 필터 수 (검색 + 라이브필터 + 카테고리)
    private var activeFilterCount: Int {
        var count = 0
        if !searchText.isEmpty { count += 1 }
        if filterLiveOnly { count += 1 }
        if selectedCategory != nil { count += 1 }
        return count
    }

    var searchAndFilterCard: some View {
        Group {
            if layout.sizeClass == .ultraCompact {
                VStack(spacing: DesignTokens.Spacing.xs) {
                    searchBarContent
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        filterSegmentContent
                        sortMenuButton
                        if activeFilterCount > 0 { activeFilterBadge }
                    }
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    searchBarContent
                    filterSegmentContent
                    sortMenuButton
                    if activeFilterCount > 0 { activeFilterBadge }
                }
            }
        }
        .padding(.horizontal, layout.sizeClass == .ultraCompact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.lg)
    }

    /// 활성 필터 배지 — 클릭 시 모든 필터 초기화
    private var activeFilterBadge: some View {
        Button {
            withAnimation(DesignTokens.Animation.snappy) {
                searchText = ""
                filterLiveOnly = false
                selectedCategory = nil
            }
        } label: {
            HStack(spacing: 3) {
                Text("필터 \(activeFilterCount)개")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(DesignTokens.Colors.accentOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DesignTokens.Colors.accentOrange.opacity(0.12))
                    .overlay(Capsule().strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .help("모든 필터 초기화")
    }

    var searchBarContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    searchText.isEmpty
                        ? DesignTokens.Colors.textTertiary
                        : DesignTokens.Colors.chzzkGreen
                )

            TextField("채널, 방송 제목, 카테고리 검색...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: layout.sizeClass == .ultraCompact ? 12 : 13, weight: .regular))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    withAnimation(DesignTokens.Animation.micro) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, layout.sizeClass == .ultraCompact ? 7 : 9)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    isSearchFocused
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Glass.borderColor.opacity(0.3),
                    lineWidth: isSearchFocused ? 1.5 : 0.5
                )
        )
        .shadow(color: isSearchFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.08) : .clear, radius: 8)
        .animation(DesignTokens.Animation.micro, value: isSearchFocused)
    }

    var filterSegmentContent: some View {
        HStack(spacing: 2) {
            filterSegment(
                isActive: !filterLiveOnly,
                icon: "person.3.fill",
                title: "전체",
                count: viewModel.followingChannels.count
            ) {
                withAnimation(DesignTokens.Animation.snappy) {
                    filterLiveOnly = false
                    selectedCategory = nil
                }
            }
            filterSegment(
                isActive: filterLiveOnly,
                icon: "dot.radiowaves.left.and.right",
                title: "라이브",
                count: viewModel.followingLiveCount
            ) {
                withAnimation(DesignTokens.Animation.snappy) {
                    filterLiveOnly = true
                    selectedCategory = nil
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .strokeBorder(DesignTokens.Glass.borderColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    func filterSegment(isActive: Bool, icon: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .white.opacity(0.8) : DesignTokens.Colors.textTertiary)
                }
            }
            .foregroundStyle(isActive ? .white : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isActive {
                        Capsule()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.3), radius: 4, y: 1)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Menu

    var sortMenuButton: some View {
        Menu {
            ForEach(FollowingSortOrder.allCases) { order in
                Button {
                    withAnimation(DesignTokens.Animation.normal) { sortOrder = order }
                } label: {
                    HStack {
                        Label(order.rawValue, systemImage: order.icon)
                        if sortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: sortOrder.icon)
                    .font(.system(size: layout.sortIconSize, weight: .medium))
                Text(sortOrder.rawValue)
                    .font(.system(size: 10, weight: .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: layout.sortChevronSize, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.4), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Gate / Empty Views

    func followingGateView(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        buttonLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: layout.gateIconSize, weight: .ultraLight))
                .foregroundStyle(iconColor.opacity(0.6))

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if let label = buttonLabel, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
