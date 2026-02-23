// MARK: - PopularClipsView.swift
// CViewApp - 프리미엄 인기 클립 브라우저
// Design: YouTube/Twitch 스타일 클립 브라우저 + 호버 카드

import SwiftUI
import CViewCore
import CViewNetworking
import CViewUI

/// 인기 클립 브라우저 — 치지직 전체 인기클립 + 채널별 클립 탐색, 정렬, 재생
struct PopularClipsView: View {
    
    @Environment(AppState.self) private var appState
    
    // 탭
    @State private var selectedTab: ClipTab = .trending
    @Namespace private var tabNS
    
    // 채널 클립 탭 상태
    @State private var channelClips: [ClipInfo] = []
    @State private var channelIsLoading = false
    @State private var channelError: String?
    @State private var channelPage = 0
    @State private var channelTotalCount: Int?
    @State private var channelHasMore = true
    @State private var channelId: String = ""
    @State private var channelSortOrder: SortOrder = .popular
    @State private var isSearchFocused = false
    
    // 전체 인기클립 탭 상태
    @State private var trendingClips: [ClipInfo] = []
    @State private var trendingIsLoading = false
    @State private var trendingError: String?
    @State private var trendingFilter: TrendingFilter = .week
    @State private var trendingOrder: TrendingOrder = .popular
    
    // 공용 상태
    @State private var viewMode: ViewMode = .grid
    @State private var selectedClip: ClipInfo?
    
    // MARK: - Enums
    
    enum ClipTab: String, CaseIterable, Identifiable {
        case trending = "전체 인기클립"
        case channel = "채널별 클립"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .trending: "flame.fill"
            case .channel: "person.text.rectangle"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable, Identifiable {
        case popular = "인기순"
        case recent = "최신순"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .popular: "flame"
            case .recent: "clock"
            }
        }
    }
    
    enum TrendingFilter: String, CaseIterable, Identifiable {
        case today = "오늘"
        case week = "이번 주"
        case month = "이번 달"
        
        var id: String { rawValue }
        var apiValue: String {
            switch self {
            case .today: "WITHIN_1_DAY"
            case .week: "WITHIN_7_DAYS"
            case .month: "WITHIN_30_DAYS"
            }
        }
    }
    
    enum TrendingOrder: String, CaseIterable, Identifiable {
        case popular = "인기순"
        case recommend = "추천순"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .popular: "flame"
            case .recommend: "sparkles"
            }
        }
        var apiValue: String {
            switch self {
            case .popular: "POPULAR"
            case .recommend: "RECOMMEND"
            }
        }
    }
    
    enum ViewMode: String, CaseIterable {
        case grid = "grid"
        case list = "list"
        var icon: String {
            switch self {
            case .grid: "square.grid.2x2"
            case .list: "list.bullet"
            }
        }
    }
    
    private let pageSize = 20
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            // 탭 전환 컨텐츠
            switch selectedTab {
            case .trending:
                trendingContent
                    .transition(.opacity)
            case .channel:
                channelContent
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(item: $selectedClip) { clip in
            ClipPlayerView(clipInfo: clip)
                .frame(minWidth: 640, minHeight: 400)
        }
        .task {
            if trendingClips.isEmpty {
                await loadTrendingClips()
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // 타이틀
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignTokens.Colors.accentPink.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.Colors.accentPink)
                    }
                    Text("클립")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                
                Spacer()
                
                // 탭별 컨트롤
                if selectedTab == .trending {
                    trendingControls
                } else {
                    channelControls
                }
                
                // 보기 모드
                HStack(spacing: 2) {
                    ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { viewMode = mode }
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewMode == mode ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                                )
                                .foregroundStyle(viewMode == mode ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs + 2)
            
            // 탭 바
            tabBar
        }
        .background(DesignTokens.Colors.backgroundDark)
    }
    
    // 전체 인기클립 탭 컨트롤
    private var trendingControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 기간 필터
            HStack(spacing: 2) {
                ForEach(TrendingFilter.allCases) { filter in
                    Button {
                        trendingFilter = filter
                        Task { await loadTrendingClips() }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(trendingFilter == filter ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                            )
                            .foregroundStyle(trendingFilter == filter ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.surface))
            
            // 정렬 순서
            HStack(spacing: 2) {
                ForEach(TrendingOrder.allCases) { order in
                    Button {
                        trendingOrder = order
                        Task { await loadTrendingClips() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(.system(size: 9))
                            Text(order.rawValue).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(trendingOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(trendingOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.surface))
        }
    }
    
    // 채널별 클립 탭 컨트롤
    private var channelControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 검색 필드
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSearchFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                TextField("채널 ID 입력", text: $channelId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 150)
                    .onSubmit { loadChannelClips(reset: true) }
                if !channelId.isEmpty {
                    Button { loadChannelClips(reset: true) } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(isSearchFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Colors.border, lineWidth: 1)
                    )
            )
            
            // 정렬
            HStack(spacing: 2) {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        channelSortOrder = order
                        loadChannelClips(reset: true)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(.system(size: 9))
                            Text(order.rawValue).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(channelSortOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(channelSortOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Colors.surface))
        }
    }
    
    // 탭 바 (matchedGeometryEffect 슬라이딩 언더라인)
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ClipTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                        .padding(.vertical, 8)
                        .scaleEffect(selectedTab == tab ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedTab)
                        
                        if selectedTab == tab {
                            Rectangle()
                                .fill(DesignTokens.Colors.chzzkGreen)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "clipTabUnderline", in: tabNS)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.backgroundDark)
    }
    
    // MARK: - 전체 인기클립 컨텐츠
    
    private var trendingContent: some View {
        Group {
            if trendingIsLoading && trendingClips.isEmpty {
                loadingView(message: "치지직 인기 클립을 불러오는 중...")
            } else if let error = trendingError, trendingClips.isEmpty {
                errorView(error) { Task { await loadTrendingClips() } }
            } else if trendingClips.isEmpty {
                trendingEmptyView
            } else {
                clipList(clips: trendingClips, showChannelBadge: true)
            }
        }
    }
    
    private var trendingEmptyView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "flame.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            Text("인기 클립을 불러올 수 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Button("새로고침") { Task { await loadTrendingClips() } }
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 채널별 클립 컨텐츠
    
    private var channelContent: some View {
        Group {
            if channelIsLoading && channelClips.isEmpty {
                loadingView(message: "클립을 불러오는 중...")
            } else if let error = channelError, channelClips.isEmpty {
                errorView(error) { loadChannelClips(reset: true) }
            } else if channelClips.isEmpty {
                channelEmptyView
            } else {
                clipListWithInfiniteScroll(clips: channelClips, showChannelBadge: false)
            }
        }
    }
    
    private var channelEmptyView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accentPink.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "film.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Colors.accentPink)
            }
            Text("채널 ID를 입력하여 클립을 검색하세요")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("채널 페이지 URL에서 채널 ID를 확인할 수 있습니다")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 공용 클립 목록 뷰
    
    private func clipList(clips: [ClipInfo], showChannelBadge: Bool) -> some View {
        Group {
            switch viewMode {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: DesignTokens.Spacing.md)
                    ], spacing: DesignTokens.Spacing.md) {
                        ForEach(clips) { clip in
                            ClipGridCard(clip: clip, showChannel: showChannelBadge) {
                                selectedClip = clip
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            case .list:
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(clips) { clip in
                            ClipListRow(clip: clip) {
                                selectedClip = clip
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                }
            }
        }
    }
    
    /// 채널 클립 전용: 마지막 아이템 도달 시 자동으로 다음 페이지 로드
    private func clipListWithInfiniteScroll(clips: [ClipInfo], showChannelBadge: Bool) -> some View {
        Group {
            switch viewMode {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: DesignTokens.Spacing.md)
                    ], spacing: DesignTokens.Spacing.md) {
                        ForEach(clips) { clip in
                            ClipGridCard(clip: clip, showChannel: showChannelBadge) {
                                selectedClip = clip
                            }
                            .onAppear {
                                if clip.id == clips.last?.id && channelHasMore && !channelIsLoading {
                                    loadMoreChannelClips()
                                }
                            }
                        }
                        if channelIsLoading {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(DesignTokens.Colors.chzzkGreen)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                    
                    if let total = channelTotalCount {
                        Text("\(clips.count) / \(total)개")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.bottom, 12)
                    }
                }
            case .list:
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(clips) { clip in
                            ClipListRow(clip: clip) {
                                selectedClip = clip
                            }
                            .onAppear {
                                if clip.id == clips.last?.id && channelHasMore && !channelIsLoading {
                                    loadMoreChannelClips()
                                }
                            }
                        }
                        if channelIsLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(DesignTokens.Colors.chzzkGreen)
                                Text("더 불러오는 중...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .padding()
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                    
                    if let total = channelTotalCount {
                        Text("\(clips.count) / \(total)개")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }
    
    // MARK: - 공용 상태 뷰
    
    private func loadingView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.large).tint(DesignTokens.Colors.chzzkGreen)
            Text(message).font(.system(size: 13)).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accentOrange.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
            }
            Text(error).font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도", action: retry).buttonStyle(.bordered).tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 데이터 로딩
    
    @MainActor
    private func loadTrendingClips() async {
        trendingIsLoading = true
        trendingError = nil
        defer { trendingIsLoading = false }
        
        guard let client = appState.apiClient else {
            trendingError = "API 클라이언트가 초기화되지 않았습니다"
            return
        }
        
        do {
            let clips = try await client.homePopularClips(
                filterType: trendingFilter.apiValue,
                orderType: trendingOrder.apiValue
            )
            trendingClips = clips
        } catch {
            trendingError = "인기 클립 로드 실패: \(error.localizedDescription)"
        }
    }
    
    private func loadChannelClips(reset: Bool) {
        let trimmedId = channelId.trimmingCharacters(in: .whitespaces)
        guard !trimmedId.isEmpty else { return }
        
        if reset {
            channelPage = 0
            channelHasMore = true
        }
        
        Task {
            channelIsLoading = true
            channelError = nil
            
            do {
                guard let client = appState.apiClient else {
                    channelError = "API 클라이언트가 초기화되지 않았습니다"
                    channelIsLoading = false
                    return
                }
                
                let result = try await client.clipList(
                    channelId: trimmedId,
                    page: channelPage,
                    size: pageSize
                )
                
                if reset {
                    channelClips = result.data
                } else {
                    channelClips.append(contentsOf: result.data)
                }
                channelTotalCount = result.totalCount
                channelHasMore = result.data.count >= pageSize
                
                if channelSortOrder == .popular {
                    channelClips.sort { $0.readCount > $1.readCount }
                }
            } catch {
                channelError = "클립 로드 실패: \(error.localizedDescription)"
            }
            
            channelIsLoading = false
        }
    }
    
    private func loadMoreChannelClips() {
        guard channelHasMore, !channelIsLoading else { return }
        channelPage += 1
        loadChannelClips(reset: false)
    }
}

// MARK: - 숫자 포맷 유틸

private func formattedCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f억", Double(count) / 100_000_000)
    } else if count >= 10_000 {
        return String(format: "%.1f만", Double(count) / 10_000)
    } else if count >= 1_000 {
        return String(format: "%.1f천", Double(count) / 1_000)
    } else {
        return "\(count)"
    }
}

private func relativeDate(_ date: Date?) -> String? {
    guard let date else { return nil }
    let now = Date()
    let diff = Int(now.timeIntervalSince(date))
    if diff < 60 { return "방금 전" }
    if diff < 3600 { return "\(diff / 60)분 전" }
    if diff < 86400 { return "\(diff / 3600)시간 전" }
    if diff < 604800 { return "\(diff / 86400)일 전" }
    if diff < 2_592_000 { return "\(diff / 604800)주 전" }
    if diff < 31_536_000 { return "\(diff / 2_592_000)개월 전" }
    return "\(diff / 31_536_000)년 전"
}

// MARK: - Premium Clip Grid Card

private struct ClipGridCard: View {
    let clip: ClipInfo
    var showChannel: Bool = false
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail with overlay on hover
                ZStack(alignment: .bottomTrailing) {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            thumbnailPlaceholder
                        }
                    } else {
                        thumbnailPlaceholder
                    }
                    
                    // Play overlay on hover
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.35)
                            Image(systemName: "play.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 4)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                    
                    // Duration badge
                    Text(formattedDuration)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                
                // Title
                Text(clip.clipTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Meta
                HStack(spacing: 8) {
                    if showChannel, let channel = clip.channel {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                            Text(channel.channelName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.9))
                    } else if let channel = clip.channel {
                        Text(channel.channelName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 8))
                            Text(formattedCount(clip.readCount))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        if let dateStr = relativeDate(clip.createdDate) {
                            Text(dateStr)
                                .font(.system(size: 9))
                                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : DesignTokens.Colors.surface.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { isHovered = hovering }
        }
        // Metal 3: hover scaleEffect+동적 shadow 제거 — GPU blur+scale 연산 방지
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isHovered)
    }
    
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(DesignTokens.Colors.surface)
            .aspectRatio(16/9, contentMode: .fill)
            .overlay {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }
    
    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Premium Clip List Row

private struct ClipListRow: View {
    let clip: ClipInfo
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            thumbnailPlaceholder
                        }
                        .frame(width: 140, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    } else {
                        thumbnailPlaceholder
                    }
                    
                    // Duration badge
                    Text(formattedDuration)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
                .frame(width: 140, height: 80)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.clipTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                    
                    if let channel = clip.channel {
                        Text(channel.channelName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    
                    HStack(spacing: DesignTokens.Spacing.md) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text(formattedCount(clip.readCount))
                                .font(.system(size: 10))
                        }
                        
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(formattedDuration)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        
                        if let dateStr = relativeDate(clip.createdDate) {
                            Text(dateStr)
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                
                Spacer()
                
                // Play icon on hover
                if isHovered {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { isHovered = hovering }
        }
    }
    
    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(DesignTokens.Colors.surface)
            .frame(width: 140, height: 80)
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
