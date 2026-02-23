// MARK: - CategoryBrowseView.swift
// CViewApp - 카테고리 목록 → 채널 목록 탐색

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Category Browse View

struct CategoryBrowseView: View {
    
    @Bindable var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router
    
    @State private var selectedCategory: String? = nil
    @State private var channelSearchText: String = ""
    @State private var isRefreshing: Bool = false
    @State private var contentWidth: CGFloat = 900
    @State private var selectedTypeFilter: String? = nil   // nil=전체, "GAME", "SPORTS", "ETC"

    private var channelGridColumns: [GridItem] {
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let available = max(300, contentWidth - 32)
        let count = max(2, min(6, Int(available / (cardWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private var gridColumns: [GridItem] {
        let cardWidth: CGFloat = 160
        let spacing: CGFloat = 12
        let available = max(300, contentWidth - 32)
        let count = max(3, min(8, Int(available / (cardWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// 현재 소스: 전체 수집 완료 시 allStatChannels, 아직이면 liveChannels
    private var sourceChannels: [LiveChannelItem] {
        viewModel.categoryChannels
    }

    private var categorizedChannels: [(category: String, channels: [LiveChannelItem])] {
        let filtered = selectedTypeFilter == nil
            ? sourceChannels
            : sourceChannels.filter { $0.categoryType == selectedTypeFilter }
        let grouped = Dictionary(grouping: filtered) { $0.categoryName ?? "기타" }
        return grouped
            .map { (category: $0.key, channels: $0.value) }
            .sorted { $0.channels.count > $1.channels.count }
    }

    private var channelsInCategory: [LiveChannelItem] {
        guard let cat = selectedCategory else { return [] }
        let base = sourceChannels.filter { ($0.categoryName ?? "기타") == cat }
        guard !channelSearchText.isEmpty else { return base }
        let q = channelSearchText.lowercased()
        return base.filter {
            $0.channelName.lowercased().contains(q) ||
            $0.liveTitle.lowercased().contains(q)
        }
    }
    
    var body: some View {
        ZStack {
            if let category = selectedCategory {
                channelListView(for: category)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                categoryGridView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectedCategory)
        .background(DesignTokens.Colors.backgroundDark)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
        .task {
            if viewModel.liveChannels.isEmpty {
                await viewModel.loadLiveChannels()
            }
            if viewModel.allStatChannels.isEmpty && !viewModel.isLoadingStats {
                await viewModel.loadAllStatsChannels()
            }
        }
    }

    // MARK: - 카테고리 그리드

    private var categoryGridView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                categoryHeader
                    .padding(.bottom, 16)
                if viewModel.isLoading && viewModel.liveChannels.isEmpty {
                    loadingPlaceholder
                } else if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty {
                    statsLoadingBanner
                    if categorizedChannels.isEmpty {
                        loadingPlaceholder
                    } else {
                        categoryTypeFilter
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(categorizedChannels, id: \.category) { group in
                                CategoryGridCard(
                                    category: group.category,
                                    liveCount: group.channels.count,
                                    previewChannels: Array(group.channels.prefix(2)),
                                    accentColor: accentColor(for: group.category)
                                ) {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                        selectedCategory = group.category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                } else if categorizedChannels.isEmpty {
                    emptyState("라이브 중인 카테고리가 없습니다")
                } else {
                    categoryTypeFilter
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(categorizedChannels, id: \.category) { group in
                            CategoryGridCard(
                                category: group.category,
                                liveCount: group.channels.count,
                                previewChannels: Array(group.channels.prefix(2)),
                                accentColor: accentColor(for: group.category)
                            ) {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                    selectedCategory = group.category
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var categoryHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("CATEGORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .tracking(1.8)
                }
                Text("카테고리")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                HStack(spacing: 6) {
                    Text("\(categorizedChannels.count)개 카테고리")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("·")
                        .foregroundStyle(DesignTokens.Colors.border)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("\(sourceChannels.count)개 라이브 중")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.live.opacity(0.9))
                    }
                    if viewModel.isLoadingStats {
                        HStack(spacing: 4) {
                            Text("·")
                                .foregroundStyle(DesignTokens.Colors.border)
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(DesignTokens.Colors.chzzkGreen)
                            Text("전체 수집 중")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.8))
                        }
                    }
                }
            }
            Spacer()
            Button {
                Task {
                    isRefreshing = true
                    await viewModel.loadLiveChannels()
                    viewModel.allStatChannels = []
                    await viewModel.loadAllStatsChannels()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isRefreshing ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                        value: isRefreshing
                    )
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.surfaceLight)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - 채널 목록

    private func channelListView(for category: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                channelListHeader(for: category)
                    .padding(.bottom, 14)
                channelSearchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                if channelsInCategory.isEmpty && !channelSearchText.isEmpty {
                    emptyState("'\(channelSearchText)' 검색 결과가 없습니다")
                } else if channelsInCategory.isEmpty {
                    emptyState("\(category) 카테고리 라이브가 없습니다")
                } else {
                    LazyVGrid(columns: channelGridColumns, spacing: 12) {
                        ForEach(channelsInCategory) { channel in
                            CategoryChannelCard(channel: channel)
                                .onTapGesture {
                                    router.navigate(to: .live(channelId: channel.channelId))
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func channelListHeader(for category: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        selectedCategory = nil
                        channelSearchText = ""
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("카테고리")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(DesignTokens.Colors.surfaceLight)
                    .clipShape(Capsule())
                    .overlay { Capsule().strokeBorder(DesignTokens.Colors.border.opacity(0.6), lineWidth: 0.5) }
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor(for: category))
                        .frame(width: 4, height: 24)
                    Text(category)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                let count = sourceChannels.filter { ($0.categoryName ?? "기타") == category }.count
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 5, height: 5)
                    Text("\(count)개 라이브 중")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.live.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private var channelSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(channelSearchText.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.chzzkGreen)
            TextField("채널, 방송 제목 검색...", text: $channelSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if !channelSearchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { channelSearchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    channelSearchText.isEmpty ? DesignTokens.Colors.border : DesignTokens.Colors.chzzkGreen.opacity(0.4),
                    lineWidth: 0.75
                )
        }
        .animation(.easeOut(duration: 0.2), value: channelSearchText.isEmpty)
    }

    // MARK: - 카테고리 타입 필터

    private var categoryTypeFilter: some View {
        HStack(spacing: 8) {
            typeFilterButton(label: "전체", icon: "square.grid.2x2", value: nil)
            typeFilterButton(label: "게임", icon: "gamecontroller.fill", value: "GAME")
            typeFilterButton(label: "스포츠", icon: "sportscourt.fill", value: "SPORTS")
            typeFilterButton(label: "기타", icon: "ellipsis.circle.fill", value: "ETC")
            Spacer()
        }
    }

    private func typeFilterButton(label: String, icon: String, value: String?) -> some View {
        let isSelected = selectedTypeFilter == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedTypeFilter = value
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.backgroundDark : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen
                    : DesignTokens.Colors.surfaceLight,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.border,
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.fast, value: isSelected)
    }

    // MARK: - 공통 서브뷰

    private var statsLoadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DesignTokens.Colors.chzzkGreen)
            Text("모든 카테고리 로드 중...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.1)
            Text("불러오는 중...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "tv.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, 40)
    }

    private func accentColor(for category: String) -> Color {
        let palette: [Color] = [
            DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.accentBlue,
            DesignTokens.Colors.accentPurple, DesignTokens.Colors.accentPink,
            DesignTokens.Colors.accentOrange, Color(hex: 0x00C9A7),
            Color(hex: 0xFF6B6B), Color(hex: 0x4ECDC4),
        ]
        return palette[abs(category.hashValue) % palette.count]
    }
}

// MARK: - Category Grid Card

private struct CategoryGridCard: View {
    let category: String
    let liveCount: Int
    let previewChannels: [LiveChannelItem]
    let accentColor: Color
    let onTap: () -> Void

    @State private var isHovered = false

    private var categoryIcon: String {
        let icons = [
            "gamecontroller.fill", "trophy.fill", "star.fill", "flame.fill",
            "bolt.fill", "music.note", "sportscourt.fill", "theatermasks.fill",
            "paintbrush.fill", "waveform", "mic.fill", "tv.fill",
            "cube.fill", "map.fill", "person.3.fill", "sparkles"
        ]
        return icons[abs(category.hashValue) % icons.count]
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // 배경 그라디언트
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.28),
                        accentColor.opacity(0.10),
                        DesignTokens.Colors.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 중앙 아이콘 (약간 위로 오프셋)
                Image(systemName: categoryIcon)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.52))
                    // Metal 3: 동적 glow shadow 제거 — hover 마다 GPU blur 연산 방지
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -10)

                // 하단 어두운 페이드 오버레이
                LinearGradient(
                    colors: [.black.opacity(0.70), .black.opacity(0.12), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // 하단 텍스트 정보
                VStack(alignment: .leading, spacing: 3) {
                    Text(category)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("라이브 \(liveCount)개")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

                // 라이브 수 뱃지 (우상단)
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Circle()
                                .fill(DesignTokens.Colors.live)
                                .frame(width: 5, height: 5)
                                .shadow(color: DesignTokens.Colors.live.opacity(0.9), radius: 3)
                            Text("\(liveCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.52), in: Capsule())
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered ? accentColor.opacity(0.65) : DesignTokens.Colors.border.opacity(0.5),
                        lineWidth: isHovered ? 1.5 : 0.75
                    )
            }
            // Metal 3: 카드 내부 5+ 레이어 → 단일 Metal 텍스처 합성
            .drawingGroup(opaque: false)
        }
        .buttonStyle(.plain)
        // Metal 3: scaleEffect 제거 (GPU texture scale 연산 제거)
        // Metal 3: 동적 shadow → 정적 shadow (hover 마다 GPU blur 연산 방지)
        .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 3)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Category Channel Card

private struct CategoryChannelCard: View {
    let channel: LiveChannelItem
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 썸네일 — LiveThumbnailView (45초 자동 갱신)
            LiveThumbnailView(
                channelId: channel.channelId,
                thumbnailUrl: URL(string: channel.thumbnailUrl ?? "")
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fill)
            .clipped()

            // 하단 그라디언트
            LinearGradient(
                colors: [.black.opacity(0.90), .black.opacity(0.28), .clear],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )

            // 하단 채널 정보
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                        Circle().fill(DesignTokens.Colors.surface)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.20), lineWidth: 0.75) }

                    Text(channel.channelName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                }
                Text(channel.liveTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // LIVE + 시청자 수 (좌상단)
            VStack {
                HStack(spacing: 5) {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(DesignTokens.Colors.live, in: RoundedRectangle(cornerRadius: 3))
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                        Text(channel.formattedViewerCount)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.55) : DesignTokens.Colors.border.opacity(0.5),
                    lineWidth: isHovered ? 1.5 : 0.75
                )
        }
        // Metal 3: 카드 비디오+배지+텍스트 레이어 → 단일 Metal 텍스처
        .drawingGroup(opaque: false)
        // Metal 3: scaleEffect 제거, 동적 shadow → 정적
        .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 3)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
