// MARK: - SearchViews.swift
// CViewApp - 검색 뷰 (프리미엄 디자인)
// Design: Spotlight/Raycast 스타일 검색 + 모던 결과 카드

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Search View

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel: SearchViewModel?
    
    var body: some View {
        VStack(spacing: 0) {
            if let vm = viewModel {
                SearchContentView(viewModel: vm)
                    .task(id: appState.homeViewModel?.followingChannels.count) {
                        if let homeVM = appState.homeViewModel {
                            vm.followingChannelNames = homeVM.followingChannels.map(\.channelName)
                        }
                    }
            } else {
                ProgressView()
                    .onAppear {
                        if let apiClient = appState.apiClient {
                            let vm = SearchViewModel(apiClient: apiClient)
                            // 팔로잉 채널명 주입 (자동완성 용)
                            if let homeVM = appState.homeViewModel {
                                vm.followingChannelNames = homeVM.followingChannels.map(\.channelName)
                            }
                            viewModel = vm
                        }
                    }
            }
        }
        .contentBackground()
    }
}

struct SearchContentView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(AppRouter.self) private var router
    @State private var isSearchBarFocused = false
    @State private var selectedClip: ClipInfo?
    @State private var selectedChannelId: String?
    
    var body: some View {
        HStack(spacing: 0) {
            // 왼쪽: 검색 리스트
            searchListContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 오른쪽: 채널 상세 패널 (push-left 슬라이드)
            if let channelId = selectedChannelId {
                Divider()
                
                channelDetailPanel(channelId: channelId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(DesignTokens.Animation.contentTransition, value: selectedChannelId)
    }
    
    // MARK: - Search List Content
    
    private var searchListContent: some View {
        VStack(spacing: 0) {
            // Premium search bar
            searchBar
            
            // Autocomplete suggestions dropdown
            if viewModel.showAutocomplete && !viewModel.autocompleteSuggestions.isEmpty {
                autocompleteDropdown
            }
            
            // Tab picker
            tabPicker
            
            // Results
            let allSearching = viewModel.isSearchingChannels && viewModel.isSearchingLives && viewModel.isSearchingVideos && viewModel.isSearchingClips
            let allEmpty = viewModel.channelResults.isEmpty && viewModel.liveResults.isEmpty && viewModel.videoResults.isEmpty && viewModel.clipResults.isEmpty
            if allSearching && allEmpty {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("검색 중...")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                ErrorStateView(message: error) {
                    Task { await viewModel.performSearch() }
                }
                Spacer()
            } else if viewModel.query.isEmpty {
                searchEmptyPrompt
            } else {
                searchResultsList
            }
        }
    }
    
    // MARK: - Channel Detail Panel
    
    @ViewBuilder
    private func channelDetailPanel(channelId: String) -> some View {
        VStack(spacing: 0) {
            // 패널 헤더: 닫기 버튼
            HStack {
                Button {
                    selectedChannelId = nil
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(DesignTokens.Typography.captionSemibold)
                        Text("검색 결과")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    router.navigate(to: .channelDetail(channelId: channelId))
                    selectedChannelId = nil
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text("전체 화면")
                            .font(DesignTokens.Typography.captionMedium)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceBase)
            
            Divider()
            
            ChannelInfoView(channelId: channelId)
                .id(channelId)
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.subhead)
                .foregroundStyle(isSearchBarFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
            
            TextField("채널, 라이브, 비디오 검색...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.custom(size: 15))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .onSubmit { Task { await viewModel.performSearch() } }
            
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(
                    isSearchBarFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Glass.borderColorLight,
                    lineWidth: isSearchBarFocused ? 1.5 : 0.5
                )
        }
        .shadow(color: isSearchBarFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.1) : .clear, radius: 8)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .animation(DesignTokens.Animation.fast, value: isSearchBarFocused)
        .animation(DesignTokens.Animation.micro, value: viewModel.query.isEmpty)
    }
    
    // MARK: - Autocomplete Dropdown

    private var autocompleteDropdown: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.autocompleteSuggestions) { suggestion in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: suggestion.kind == .recent ? "clock" : "person.circle")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(
                            suggestion.kind == .recent
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.chzzkGreen
                        )
                        .frame(width: 18)

                    Text(suggestion.text)
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if suggestion.kind == .following {
                        Text("팔로잉")
                            .font(DesignTokens.Typography.microSemibold)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // 검색어에 삽입 버튼
                    Button {
                        viewModel.query = suggestion.text
                    } label: {
                        Image(systemName: "arrow.up.left")
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.query = suggestion.text
                    Task { await viewModel.performSearch() }
                }
                .background(Color.clear)

                if suggestion.id != viewModel.autocompleteSuggestions.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .shadow(color: DesignTokens.Colors.background.opacity(0.5), radius: 6, y: 4)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(DesignTokens.Animation.fast, value: viewModel.autocompleteSuggestions.count)
    }

    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach([SearchType.channel, .live, .video, .clip], id: \.self) { tab in
                SearchTabButton(
                    title: tabTitle(for: tab),
                    icon: tabIcon(for: tab),
                    isSelected: viewModel.selectedTab == tab,
                    count: tabCount(for: tab)
                ) {
                    Task { await viewModel.onTabChanged(tab) }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }
    
    private func tabTitle(for tab: SearchType) -> String {
        switch tab {
        case .channel: "채널"
        case .live: "라이브"
        case .video: "비디오"
        case .clip: "클립"
        }
    }
    
    private func tabIcon(for tab: SearchType) -> String {
        switch tab {
        case .channel: "person.2"
        case .live: "play.tv"
        case .video: "film"
        case .clip: "film.stack"
        }
    }
    
    private func tabCount(for tab: SearchType) -> Int {
        switch tab {
        case .channel: viewModel.channelResults.count
        case .live: viewModel.liveResults.count
        case .video: viewModel.videoResults.count
        case .clip: viewModel.clipResults.count
        }
    }
    
    // MARK: - Empty Prompt
    
    private var searchEmptyPrompt: some View {
        VStack(spacing: 0) {
            if !viewModel.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("최근 검색어")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        Button("전체 삭제") { viewModel.clearRecentSearches() }
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                    
                    ForEach(viewModel.recentSearches, id: \.self) { term in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "clock")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text(term)
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Spacer()
                            Button {
                                viewModel.removeRecentSearch(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.query = term
                            Task { await viewModel.performSearch() }
                        }
                    }
                    
                    Divider()
                        .padding(.top, DesignTokens.Spacing.sm)
                }
            }
            
            VStack(spacing: DesignTokens.Spacing.lg) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.custom(size: 30))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.6))
                }
                
                VStack(spacing: DesignTokens.Spacing.xs) {
                    Text("검색어를 입력하세요")
                        .font(DesignTokens.Typography.custom(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    
                    Text("채널명, 라이브 방송, 비디오, 클립을 검색할 수 있습니다")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch viewModel.selectedTab {
                case .channel:
                    if viewModel.channelResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingChannels {
                            tabLoadingView
                        } else {
                            searchEmptyState("채널")
                        }
                    } else {
                        ForEach(viewModel.channelResults) { channel in
                            EquatableSearchChannelRow(channel: channel)
                                .equatable()
                                .contentShape(Rectangle())
                                .background(
                                    selectedChannelId == channel.channelId
                                        ? DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                )
                                .onTapGesture {
                                    if selectedChannelId == channel.channelId {
                                        selectedChannelId = nil
                                    } else {
                                        selectedChannelId = channel.channelId
                                    }
                                }
                                .onAppear {
                                    if channel.id == viewModel.channelResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }
                    
                case .live:
                    if viewModel.liveResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingLives {
                            tabLoadingView
                        } else {
                            searchEmptyState("라이브")
                        }
                    } else {
                        if !viewModel.liveResults.isEmpty {
                            HStack {
                                Spacer()
                                Picker("", selection: $viewModel.liveSortOption) {
                                    ForEach(LiveSortOption.allCases, id: \.self) { opt in
                                        Text(opt.rawValue).tag(opt)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                            }
                        }
                        ForEach(viewModel.liveResults) { live in
                            EquatableSearchLiveRow(live: live)
                                .equatable()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let chId = live.channel?.channelId {
                                        router.navigate(to: .live(channelId: chId))
                                    }
                                }
                                .onAppear {
                                    if live.id == viewModel.liveResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }
                    
                case .video:
                    if viewModel.videoResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingVideos {
                            tabLoadingView
                        } else {
                            searchEmptyState("비디오")
                        }
                    } else {
                        ForEach(viewModel.videoResults) { video in
                            EquatableSearchVideoRow(video: video)
                                .equatable()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    router.navigate(to: .vod(videoNo: video.videoNo))
                                }
                                .onAppear {
                                    if video.id == viewModel.videoResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }
                    
                case .clip:
                    if viewModel.clipResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingClips {
                            tabLoadingView
                        } else {
                            searchEmptyState("클립")
                        }
                    } else {
                        ForEach(viewModel.clipResults) { clip in
                            EquatableSearchClipRow(clip: clip)
                                .equatable()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedClip = clip
                                }
                                .onAppear {
                                    if clip.id == viewModel.clipResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }
                }
                
                if viewModel.isSearching && !viewModel.query.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
        }
        .sheet(item: $selectedClip) { clip in
            ClipPlayerView(clipInfo: clip)
                .frame(minWidth: 640, minHeight: 400)
        }
    }
    
    private var tabLoadingView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: DesignTokens.Spacing.md) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 100, height: 56)
                        .shimmer()
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(height: 12)
                            .shimmer()
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 80, height: 10)
                            .shimmer()
                    }
                    Spacer()
                }
                .padding(DesignTokens.Spacing.sm)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }
    
    private func searchEmptyState(_ type: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(type) 검색 결과가 없습니다")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

