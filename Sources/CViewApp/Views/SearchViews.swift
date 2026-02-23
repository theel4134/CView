// MARK: - SearchViews.swift
// CViewApp - 검색 뷰 (프리미엄 디자인)
// Design: Spotlight/Raycast 스타일 검색 + 모던 결과 카드

import SwiftUI
import AppKit
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
            } else {
                ProgressView()
                    .onAppear {
                        if let apiClient = appState.apiClient {
                            viewModel = SearchViewModel(apiClient: apiClient)
                        }
                    }
            }
        }
        .background(DesignTokens.Colors.backgroundDark)
    }
}

struct SearchContentView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(AppRouter.self) private var router
    @State private var isSearchBarFocused = false
    @State private var selectedClip: ClipInfo?
    
    var body: some View {
        VStack(spacing: 0) {
            // Premium search bar
            searchBar
            
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
                        .font(.system(size: 13, weight: .medium))
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSearchBarFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
            
            TextField("채널, 라이브, 비디오 검색...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .onSubmit { Task { await viewModel.performSearch() } }
            
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
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
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            isSearchBarFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Colors.border,
                            lineWidth: isSearchBarFocused ? 1.5 : 0.5
                        )
                }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .animation(DesignTokens.Animation.fast, value: isSearchBarFocused)
        .animation(DesignTokens.Animation.fast, value: viewModel.query.isEmpty)
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        Button("전체 삭제") { viewModel.clearRecentSearches() }
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                    
                    ForEach(viewModel.recentSearches, id: \.self) { term in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text(term)
                                .font(.system(size: 14))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Spacer()
                            Button {
                                viewModel.removeRecentSearch(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 8)
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
                        .font(.system(size: 30))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.6))
                }
                
                VStack(spacing: DesignTokens.Spacing.xs) {
                    Text("검색어를 입력하세요")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    
                    Text("채널명, 라이브 방송, 비디오, 클립을 검색할 수 있습니다")
                        .font(.system(size: 13))
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
                            SearchChannelRow(channel: channel)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    router.navigate(to: .channelDetail(channelId: channel.channelId))
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
                                    ForEach(SearchViewModel.LiveSortOption.allCases, id: \.self) { opt in
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
                            SearchLiveRow(live: live)
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
                            SearchVideoRow(video: video)
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
                            SearchClipRow(clip: clip)
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
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 60)
            Spacer()
        }
    }
    
    private func searchEmptyState(_ type: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(type) 검색 결과가 없습니다")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Search Tab Button

struct SearchTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .black : DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surface)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.fast, value: isSelected)
    }
}

// MARK: - Search Result Rows (Premium)

struct SearchChannelRow: View {
    let channel: ChannelInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: 채널 아바타 Circle+stroke → 단일 Metal 텍스처
            CachedAsyncImage(url: channel.channelImageURL) {
                Circle().fill(DesignTokens.Colors.surfaceLight)
                    .overlay { Image(systemName: "person.fill").foregroundStyle(DesignTokens.Colors.textTertiary) }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
            }
            .drawingGroup(opaque: false)  // 아바타 클립+stroke 합성 단일 패스
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(channel.channelName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if channel.verifiedMark {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.accentBlue)
                    }
                }
                Text("팔로워 \(formatKoreanCount(channel.followerCount))")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceHover.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

struct SearchLiveRow: View {
    let live: LiveInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Thumbnail with live badge
            // Metal 3: ZStack(thumbnail + LIVE badge) → 단일 Metal 텍스처
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: live.resolvedLiveImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceLight)
                        .overlay { Image(systemName: "video").foregroundStyle(DesignTokens.Colors.textTertiary) }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                // Mini LIVE badge
                Text("LIVE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(DesignTokens.Colors.live.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .drawingGroup(opaque: false)  // 썸네일+뱃지 합성 단일 패스
            
            VStack(alignment: .leading, spacing: 3) {
                Text(live.liveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    Text(live.channel?.channelName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    if let cat = live.liveCategoryValue {
                        Text(cat)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                    Text("\(formatKoreanCount(live.concurrentUserCount))명")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceHover.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

struct SearchVideoRow: View {
    let video: VODInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: ZStack(thumbnail + duration badge) → 단일 Metal 텍스처
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: video.videoImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceLight)
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                // Duration badge
                Text(video.formattedDuration)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .drawingGroup(opaque: false)  // 썸네일+길이 뱃지 합성 단일 패스
            
            VStack(alignment: .leading, spacing: 3) {
                Text(video.videoTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(video.channel?.channelName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                        Text(formatKoreanCount(video.readCount))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceHover.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Search Clip Row

struct SearchClipRow: View {
    let clip: ClipInfo
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Metal 3: ZStack(thumbnail + clip badge) → 단일 Metal 텍스처
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: clip.thumbnailImageURL) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(DesignTokens.Colors.surfaceLight)
                        .overlay { Image(systemName: "film.stack").foregroundStyle(DesignTokens.Colors.textTertiary) }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                
                HStack(spacing: 2) {
                    Image(systemName: "scissors")
                        .font(.system(size: 7))
                    Text(formattedDuration)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(4)
            }
            .drawingGroup(opaque: false)  // 썸네일+클립 뱃지 합성 단일 패스
            
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.clipTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(clip.channel?.channelName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                        Text(formatKoreanCount(clip.readCount))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(isHovered ? DesignTokens.Colors.surfaceHover.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .onHover { hovering in isHovered = hovering }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
    
    private var formattedDuration: String {
        let minutes = clip.duration / 60
        let seconds = clip.duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Korean Count Formatter

private func formatKoreanCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f억", Double(count) / 100_000_000)
    } else if count >= 10_000 {
        return String(format: "%.1f만", Double(count) / 10_000)
    } else if count >= 1_000 {
        return String(format: "%.1f천", Double(count) / 1_000)
    }
    return "\(count)"
}
