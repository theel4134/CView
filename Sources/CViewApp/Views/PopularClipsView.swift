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
                .frame(height: DesignTokens.Spacing.xxs)
            
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
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.accentPink.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "film.stack.fill")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.accentPink)
                    }
                    Text("클립")
                        .font(DesignTokens.Typography.bodySemibold)
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
                            withAnimation(DesignTokens.Animation.indicator) { viewMode = mode }
                        } label: {
                            Image(systemName: mode.icon)
                                .font(DesignTokens.Typography.captionSemibold)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
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
        .contentBackground()
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
                            .font(DesignTokens.Typography.captionMedium)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(trendingFilter == filter ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                            )
                            .foregroundStyle(trendingFilter == filter ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
            
            // 정렬 순서
            HStack(spacing: 2) {
                ForEach(TrendingOrder.allCases) { order in
                    Button {
                        trendingOrder = order
                        Task { await loadTrendingClips() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(DesignTokens.Typography.micro)
                            Text(order.rawValue).font(DesignTokens.Typography.captionMedium)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(trendingOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(trendingOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
        }
    }
    
    // 채널별 클립 탭 컨트롤
    private var channelControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 검색 필드
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(isSearchFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                TextField("채널 ID 입력", text: $channelId)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.caption)
                    .frame(width: 150)
                    .onSubmit { loadChannelClips(reset: true) }
                if !channelId.isEmpty {
                    Button { loadChannelClips(reset: true) } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(isSearchFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Glass.borderColor, lineWidth: 1)
            )
            
            // 정렬
            HStack(spacing: 2) {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        channelSortOrder = order
                        loadChannelClips(reset: true)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(DesignTokens.Typography.micro)
                            Text(order.rawValue).font(DesignTokens.Typography.captionMedium)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(channelSortOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(channelSortOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
        }
    }
    
    // 탭 바 (matchedGeometryEffect 슬라이딩 언더라인)
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ClipTab.allCases) { tab in
                Button {
                    withAnimation(DesignTokens.Animation.indicator) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(DesignTokens.Typography.caption)
                            Text(tab.rawValue)
                                .font(DesignTokens.Typography.custom(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .scaleEffect(selectedTab == tab ? 1.02 : 1.0)
                        .animation(DesignTokens.Animation.indicator, value: selectedTab)
                        
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
        .contentBackground()
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
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            Text("인기 클립을 불러올 수 없습니다")
                .font(DesignTokens.Typography.bodyMedium)
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
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.accentPink)
            }
            Text("채널 ID를 입력하여 클립을 검색하세요")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("채널 페이지 URL에서 채널 ID를 확인할 수 있습니다")
                .font(DesignTokens.Typography.caption)
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
                            EquatableClipGridCard(clip: clip, showChannel: showChannelBadge) {
                                selectedClip = clip
                            }
                            .equatable()
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            case .list:
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(clips) { clip in
                            EquatableClipListRow(clip: clip) {
                                selectedClip = clip
                            }
                            .equatable()
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
                            EquatableClipGridCard(clip: clip, showChannel: showChannelBadge) {
                                selectedClip = clip
                            }
                            .equatable()
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
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.bottom, DesignTokens.Spacing.sm)
                    }
                }
            case .list:
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(clips) { clip in
                            EquatableClipListRow(clip: clip) {
                                selectedClip = clip
                            }
                            .equatable()
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
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .padding()
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                    
                    if let total = channelTotalCount {
                        Text("\(clips.count) / \(total)개")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.bottom, DesignTokens.Spacing.sm)
                    }
                }
            }
        }
    }
    
    // MARK: - 공용 상태 뷰
    
    private func loadingView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.large).tint(DesignTokens.Colors.chzzkGreen)
            Text(message).font(DesignTokens.Typography.captionMedium).foregroundStyle(DesignTokens.Colors.textSecondary)
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
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
            }
            Text(error).font(DesignTokens.Typography.captionMedium)
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

