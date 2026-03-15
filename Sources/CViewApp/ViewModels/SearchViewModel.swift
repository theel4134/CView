// MARK: - SearchViewModel.swift
// CViewApp - 검색 뷰모델
// 4-tab 검색 (채널/라이브/비디오/클립) + debounce + 페이지네이션 + 전체 탭 동시 검색

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking

@Observable
@MainActor
public final class SearchViewModel {
    
    // MARK: - State
    
    public var query: String = "" {
        didSet { scheduleSearch() }
    }
    public var selectedTab: SearchType = .channel
    
    // Results
    public var channelResults: [ChannelInfo] = []
    public var liveResults: [LiveInfo] = []
    public var videoResults: [VODInfo] = []
    public var clipResults: [ClipInfo] = []
    
    // Loading — 탭별 개별 로딩 상태
    public var isSearchingChannels = false
    public var isSearchingLives = false
    public var isSearchingVideos = false
    public var isSearchingClips = false
    public var hasMoreChannels = true
    public var hasMoreLives = true
    public var hasMoreVideos = true
    public var hasMoreClips = true
    public var errorMessage: String?

    // 최근 검색어
    public var recentSearches: [String] = []
    private let recentSearchesKey = "CView.recentSearches"
    private let maxRecentSearches = 10

    // 라이브 정렬
    public var liveSortOption: LiveSortOption = .viewerCount {
        didSet { sortLiveResults() }
    }

    // MARK: - Autocomplete

    /// 팔로잉 채널 이름 목록 (외부에서 주입)
    public var followingChannelNames: [String] = []

    /// 자동완성이 보여야 하는지 (검색 실행 전 타이핑 중)
    public var showAutocomplete: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // 검색 결과가 이미 있으면 자동완성 숨김
        let hasResults = !channelResults.isEmpty || !liveResults.isEmpty || !videoResults.isEmpty || !clipResults.isEmpty
        let anySearching = isSearchingChannels || isSearchingLives || isSearchingVideos || isSearchingClips
        return !hasResults && !anySearching
    }

    /// 자동완성 제안 목록: 최근 검색어 매칭 + 팔로잉 채널명 매칭
    public var autocompleteSuggestions: [AutocompleteSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var suggestions: [AutocompleteSuggestion] = []

        // 최근 검색어 매칭
        let matchedRecent = recentSearches.filter { $0.lowercased().contains(trimmed) }.prefix(3)
        for term in matchedRecent {
            suggestions.append(AutocompleteSuggestion(text: term, kind: .recent))
        }

        // 팔로잉 채널명 매칭
        let matchedFollowing = followingChannelNames
            .filter { $0.lowercased().contains(trimmed) }
            .prefix(5)
        for name in matchedFollowing {
            if !suggestions.contains(where: { $0.text == name }) {
                suggestions.append(AutocompleteSuggestion(text: name, kind: .following))
            }
        }

        return Array(suggestions.prefix(8))
    }

    /// 현재 선택된 탭의 로딩 상태
    public var isSearching: Bool {
        switch selectedTab {
        case .channel: isSearchingChannels
        case .live: isSearchingLives
        case .video: isSearchingVideos
        case .clip: isSearchingClips
        }
    }
    
    // MARK: - Private
    
    private let apiClient: ChzzkAPIClient
    private var searchTask: Task<Void, Never>?
    private var channelOffset = 0
    private var liveOffset = 0
    private var videoOffset = 0
    private var clipPage = 0
    private let pageSize = 20
    private let logger = AppLogger.app
    
    // MARK: - Init
    
    public init(apiClient: ChzzkAPIClient) {
        self.apiClient = apiClient
        loadRecentSearches()
    }
    
    // MARK: - Search
    
    /// 입력 변경 시 debounce 후 검색
    private func scheduleSearch() {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }
    
    /// 검색 실행 — 채널/라이브/비디오/클립 모두 동시 검색
    public func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        saveRecentSearch(trimmed)
        errorMessage = nil
        
        // 오프셋 리셋
        channelOffset = 0
        liveOffset = 0
        videoOffset = 0
        clipPage = 0
        hasMoreChannels = true
        hasMoreLives = true
        hasMoreVideos = true
        hasMoreClips = true
        channelResults = []
        liveResults = []
        videoResults = []
        clipResults = []
        
        // 모든 탭 동시 검색
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchChannels(keyword: trimmed, reset: false) }
            group.addTask { await self.fetchLives(keyword: trimmed, reset: false) }
            group.addTask { await self.fetchVideos(keyword: trimmed, reset: false) }
            group.addTask { await self.fetchClips(keyword: trimmed, reset: false) }
        }
    }
    
    /// 탭 변경 시 해당 탭 결과 없으면 검색
    public func onTabChanged(_ tab: SearchType) async {
        selectedTab = tab
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        switch tab {
        case .channel where channelResults.isEmpty && !isSearchingChannels:
            await fetchChannels(keyword: trimmed, reset: true)
        case .live where liveResults.isEmpty && !isSearchingLives:
            await fetchLives(keyword: trimmed, reset: true)
        case .video where videoResults.isEmpty && !isSearchingVideos:
            await fetchVideos(keyword: trimmed, reset: true)
        case .clip where clipResults.isEmpty && !isSearchingClips:
            await fetchClips(keyword: trimmed, reset: true)
        default:
            break
        }
    }
    
    /// 더 불러오기
    public func loadMore() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch selectedTab {
        case .channel where hasMoreChannels && !isSearchingChannels:
            await fetchChannels(keyword: trimmed, reset: false)
        case .live where hasMoreLives && !isSearchingLives:
            await fetchLives(keyword: trimmed, reset: false)
        case .video where hasMoreVideos && !isSearchingVideos:
            await fetchVideos(keyword: trimmed, reset: false)
        case .clip where hasMoreClips && !isSearchingClips:
            await fetchClips(keyword: trimmed, reset: false)
        default:
            break
        }
    }
    
    // MARK: - Private Fetch Helpers
    
    private func fetchChannels(keyword: String, reset: Bool) async {
        if reset {
            channelOffset = 0
            hasMoreChannels = true
        }
        isSearchingChannels = true
        do {
            let result = try await apiClient.searchChannels(keyword: keyword, offset: channelOffset, size: pageSize)
            if channelOffset == 0 {
                channelResults = result.data
            } else {
                channelResults.append(contentsOf: result.data)
            }
            channelOffset += result.data.count
            hasMoreChannels = result.data.count >= pageSize
        } catch {
            logger.error("채널 검색 실패: \(error.localizedDescription)")
        }
        isSearchingChannels = false
    }
    
    private func fetchLives(keyword: String, reset: Bool) async {
        if reset {
            liveOffset = 0
            hasMoreLives = true
        }
        isSearchingLives = true
        do {
            let result = try await apiClient.searchLives(keyword: keyword, offset: liveOffset, size: pageSize)
            if liveOffset == 0 {
                liveResults = result.data
            } else {
                liveResults.append(contentsOf: result.data)
            }
            sortLiveResults()
            liveOffset += result.data.count
            hasMoreLives = result.data.count >= pageSize
        } catch {
            logger.error("라이브 검색 실패: \(error.localizedDescription)")
        }
        isSearchingLives = false
    }
    
    private func fetchVideos(keyword: String, reset: Bool) async {
        if reset {
            videoOffset = 0
            hasMoreVideos = true
        }
        isSearchingVideos = true
        do {
            let result = try await apiClient.searchVideos(keyword: keyword, offset: videoOffset, size: pageSize)
            if videoOffset == 0 {
                videoResults = result.data
            } else {
                videoResults.append(contentsOf: result.data)
            }
            videoOffset += result.data.count
            hasMoreVideos = result.data.count >= pageSize
        } catch {
            logger.error("비디오 검색 실패: \(error.localizedDescription)")
        }
        isSearchingVideos = false
    }
    
    /// 클립: 채널 검색 후 해당 채널들의 클립을 병렬로 가져온다 (Chzzk에 클립 전용 검색 API 없음)
    private func fetchClips(keyword: String, reset: Bool) async {
        if reset {
            clipPage = 0
            hasMoreClips = true
        }
        isSearchingClips = true
        do {
            // 채널 결과가 없으면 먼저 채널 검색
            let channels: [ChannelInfo]
            if channelResults.isEmpty {
                let channelResult = try await apiClient.searchChannels(keyword: keyword, offset: 0, size: 5)
                channels = channelResult.data
                if clipPage == 0 && channelResults.isEmpty {
                    channelResults = channelResult.data
                    channelOffset = channelResult.data.count
                    hasMoreChannels = channelResult.data.count >= pageSize
                }
            } else {
                channels = Array(channelResults.prefix(5))
            }
            
            guard !channels.isEmpty else {
                hasMoreClips = false
                isSearchingClips = false
                return
            }
            
            let currentPage = clipPage
            let topChannels = Array(channels.prefix(3))
            
            let allClips = try await withThrowingTaskGroup(of: [ClipInfo].self) { group in
                for channel in topChannels {
                    group.addTask {
                        try await self.apiClient.clipList(
                            channelId: channel.channelId,
                            page: currentPage,
                            size: self.pageSize
                        ).data
                    }
                }
                var results: [ClipInfo] = []
                for try await clips in group {
                    results.append(contentsOf: clips)
                }
                return results
            }
            
            // 키워드로 로컬 필터링 (제목 매칭)
            let keywordLower = keyword.lowercased()
            let filtered = allClips.filter { $0.clipTitle.localizedCaseInsensitiveContains(keywordLower) }
            let finalClips = filtered
            
            if clipPage == 0 {
                clipResults = finalClips
            } else {
                clipResults.append(contentsOf: finalClips)
            }
            clipPage += 1
            hasMoreClips = !allClips.isEmpty
        } catch {
            logger.error("클립 검색 실패: \(error.localizedDescription)")
        }
        isSearchingClips = false
    }
    
    private func clearResults() {
        channelResults = []
        liveResults = []
        videoResults = []
        clipResults = []
        channelOffset = 0
        liveOffset = 0
        videoOffset = 0
        clipPage = 0
        hasMoreChannels = true
        hasMoreLives = true
        hasMoreVideos = true
        hasMoreClips = true
        errorMessage = nil
    }

    // MARK: - Live Sort

    private func sortLiveResults() {
        switch liveSortOption {
        case .viewerCount:
            liveResults.sort { ($0.concurrentUserCount ?? 0) > ($1.concurrentUserCount ?? 0) }
        case .recent:
            liveResults.sort { ($0.openDate ?? .distantPast) > ($1.openDate ?? .distantPast) }
        }
    }

    // MARK: - Recent Searches

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }

    private func saveRecentSearch(_ keyword: String) {
        var searches = recentSearches.filter { $0 != keyword }
        searches.insert(keyword, at: 0)
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }

    public func removeRecentSearch(_ keyword: String) {
        recentSearches.removeAll { $0 == keyword }
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    public func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }
}
