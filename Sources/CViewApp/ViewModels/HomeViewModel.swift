// MARK: - HomeViewModel.swift
// CViewApp - Home screen ViewModel
// Dashboard 통계 데이터 포함

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking
import CViewPersistence

// MARK: - Home ViewModel

@Observable
@MainActor
public final class HomeViewModel {
    
    // MARK: - State
    
    public var liveChannels: [LiveChannelItem] = []     // UI 표시용 (페이지 단위 로드)
    public var allStatChannels: [LiveChannelItem] = []  // 통계 집계용 (전체 채널)
    public var recommendedChannels: [LiveChannelItem] = []
    public var followingChannels: [LiveChannelItem] = []
    
    public var isLoading = false
    public var isLoadingStats = false  // 전체 통계 수집 중 여부
    public var isLoadingFollowing = false
    public var errorMessage: String?
    public var searchQuery = ""
    
    /// 팔로잉 조회 시 NID 쿠키 부재로 인증 실패했을 때 true
    public var needsCookieLogin = false
    
    // Pagination (UI용) — 커서 기반 (concurrentUserCount + liveId)
    public var hasMoreChannels = true
    private var nextLiveCursor: LivePageCursor? = nil
    private let pageSize = 20
    
    // Dashboard stats
    public var viewerHistory: [ViewerHistoryEntry] = []
    private var lastSnapshotTime: Date?
    
    // MARK: - Metrics Server State
    
    /// 서버 전체 통계
    public var serverStats: MetricsServerStats?
    /// 서버 연결 상태
    public var isMetricsServerOnline = false
    /// 서버 채널별 통계
    public var serverChannelStats: [ChannelStatsItem] = []
    /// 레이턴시 이력 (차트용)
    public var latencyHistory: [LatencyHistoryEntry] = []
    /// 서버 업타임 (초)
    public var serverUptime: Double = 0
    /// 서버에서 수신한 총 메트릭 수
    public var serverTotalReceived: Int = 0
    /// WebSocket 연결 클라이언트 수
    public var wsClientCount: Int = 0
    /// 활성 앱 채널 수
    public var activeAppChannelCount: Int = 0
    /// 서버 마지막 갱신 시각
    public var serverLastUpdate: Date?
    
    private var metricsPollingTask: Task<Void, Never>?
    private var wsStreamTask: Task<Void, Never>?
    
    // MARK: - Computed Stats
    
    /// 통계 집계 대상: 전체 수집 완료 시 allStatChannels, 수집 중에는 liveChannels
    private var statsSource: [LiveChannelItem] {
        allStatChannels.isEmpty ? liveChannels : allStatChannels
    }
    
    /// 카테고리 탐색용: 통계 수집 완료 시 allStatChannels, 아직이면 liveChannels
    public var categoryChannels: [LiveChannelItem] {
        allStatChannels.isEmpty ? liveChannels : allStatChannels
    }
    
    public var totalViewers: Int {
        statsSource.reduce(0) { $0 + $1.viewerCount }
    }
    
    public var averageViewers: Int {
        guard !statsSource.isEmpty else { return 0 }
        return totalViewers / statsSource.count
    }
    
    public var categoryCount: Int {
        Set(statsSource.compactMap { $0.categoryName }).count
    }
    
    /// 통계용 라이브 채널 수 (전체)
    public var totalLiveChannelCount: Int { statsSource.count }
    
    public var topCategories: [CategoryStat] {
        let grouped = Dictionary(grouping: statsSource) { $0.categoryName ?? "기타" }
        return grouped.map { name, channels in
            CategoryStat(
                id: name,
                name: name,
                channelCount: channels.count,
                totalViewers: channels.reduce(0) { $0 + $1.viewerCount }
            )
        }
        .sorted { $0.totalViewers > $1.totalViewers }
        .prefix(5)
        .map { $0 }
    }
    
    public var followingLiveCount: Int {
        followingChannels.filter { $0.isLive }.count
    }
    
    public var recentLiveFollowing: [LiveChannelItem] {
        Array(followingChannels.filter { $0.isLive }.prefix(6))
    }
    
    public var topChannels: [LiveChannelItem] {
        Array(liveChannels.sorted { $0.viewerCount > $1.viewerCount }.prefix(6))
    }
    
    /// 서버 채널 중 평균 웹 레이턴시
    public var avgWebLatency: Double? {
        let vals = serverChannelStats.compactMap { $0.web?.avg }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
    
    /// 서버 채널 중 평균 앱 레이턴시
    public var avgAppLatency: Double? {
        let vals = serverChannelStats.compactMap { $0.app?.avg }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
    
    /// 서버 포맷 업타임
    public var formattedUptime: String {
        let hours = Int(serverUptime) / 3600
        let mins = (Int(serverUptime) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// 카테고리 타입별 분포 (GAME / SPORTS / ETC)
    public var categoryTypeDistribution: [CategoryTypeStat] {
        let source = statsSource
        guard !source.isEmpty else { return [] }
        let grouped = Dictionary(grouping: source) { $0.categoryType ?? "ETC" }
        let total = source.count
        return grouped.map { type, channels in
            CategoryTypeStat(
                id: type,
                type: type,
                displayName: CategoryTypeStat.displayName(for: type),
                channelCount: channels.count,
                totalViewers: channels.reduce(0) { $0 + $1.viewerCount },
                percentage: Double(channels.count) / Double(total) * 100
            )
        }
        .sorted { $0.channelCount > $1.channelCount }
    }

    /// 시청자수 구간별 분포 버킷 — 단일 패스 O(N) 계산
    public var viewerBuckets: [ViewerBucket] {
        let source = statsSource
        let defs: [(label: String, min: Int, max: Int)] = [
            ("0~100", 0, 100),
            ("100~1K", 100, 1_000),
            ("1K~1만", 1_000, 10_000),
            ("1만+", 10_000, Int.max)
        ]
        var counts = Array(repeating: 0, count: defs.count)
        for item in source {
            let v = item.viewerCount
            if v < 100 { counts[0] += 1 }
            else if v < 1_000 { counts[1] += 1 }
            else if v < 10_000 { counts[2] += 1 }
            else { counts[3] += 1 }
        }
        return defs.enumerated().map { idx, d in
            ViewerBucket(id: d.label, label: d.label, count: counts[idx], minViewers: d.min, maxViewers: d.max)
        }
    }

    /// 시청자수 중앙값
    public var medianViewers: Int {
        let sorted = statsSource.map { $0.viewerCount }.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// 팔로잉 라이브 비율 (0~100)
    public var followingLiveRate: Int {
        guard !followingChannels.isEmpty else { return 0 }
        return followingLiveCount * 100 / followingChannels.count
    }

    /// 팔로잉 라이브 채널 전체 시청자 합계
    public var followingTotalViewers: Int {
        followingChannels.filter { $0.isLive }.reduce(0) { $0 + $1.viewerCount }
    }

    /// 라이브 상위 3 채널
    public var topThreeChannels: [LiveChannelItem] {
        Array(statsSource.sorted { $0.viewerCount > $1.viewerCount }.prefix(3))
    }
    
    // MARK: - Dependencies
    
    private let apiClient: ChzzkAPIClient
    private var metricsClient: MetricsAPIClient?
    private var wsClient: MetricsWebSocketClient?
    private let logger = AppLogger.app

    // MARK: - Cache

    /// 로컬 캐시 저장소 (설정 후 자동으로 캐시 복원)
    public var dataStore: DataStore? {
        didSet { Task { await loadFromCache() } }
    }

    public var liveChannelsCachedAt: Date?
    public var allStatCachedAt: Date?
    public var followingCachedAt: Date?

    private enum CacheKey {
        static let liveChannels      = "cache.liveChannels"
        static let allStatChannels   = "cache.allStatChannels"
        static let followingChannels = "cache.followingChannels"
        static let liveChannelsCachedAt      = "cache.liveChannels.ts"
        static let allStatCachedAt           = "cache.allStatChannels.ts"
        static let followingCachedAt         = "cache.followingChannels.ts"
    }

    /// 캐시에서 데이터 복원 (앱 재실행 시 즉시 표시용)
    public func loadFromCache() async {
        guard let store = dataStore else { return }
        do {
            if let cached = try await store.loadSetting(key: CacheKey.liveChannels, as: [LiveChannelItem].self), !cached.isEmpty {
                if liveChannels.isEmpty { liveChannels = cached }
            }
            if let cached = try await store.loadSetting(key: CacheKey.allStatChannels, as: [LiveChannelItem].self), !cached.isEmpty {
                if allStatChannels.isEmpty { allStatChannels = cached }
            }
            if let cached = try await store.loadSetting(key: CacheKey.followingChannels, as: [LiveChannelItem].self), !cached.isEmpty {
                if followingChannels.isEmpty { followingChannels = cached }
            }
            liveChannelsCachedAt      = try await store.loadSetting(key: CacheKey.liveChannelsCachedAt, as: Date.self)
            allStatCachedAt           = try await store.loadSetting(key: CacheKey.allStatCachedAt, as: Date.self)
            followingCachedAt         = try await store.loadSetting(key: CacheKey.followingCachedAt, as: Date.self)
            let lc = liveChannels.count, sc = allStatChannels.count, fc = followingChannels.count
            logger.info("캐시 복원: 라이브 \(lc)개, 전체통계 \(sc)개, 팔로잉 \(fc)개")
        } catch {
            logger.error("캐시 로드 실패: \(error)")
        }
    }
    
    // MARK: - Initialization
    
    public init(apiClient: ChzzkAPIClient, metricsClient: MetricsAPIClient? = nil, wsClient: MetricsWebSocketClient? = nil) {
        self.apiClient = apiClient
        self.metricsClient = metricsClient
        self.wsClient = wsClient
    }
    
    /// 메트릭 서비스 설정 (앱 초기화 후 호출)
    public func configureMetrics(client: MetricsAPIClient, wsClient: MetricsWebSocketClient) {
        self.metricsClient = client
        self.wsClient = wsClient
        startMetricsPolling()
        startWebSocketStream()
    }
    
    /// 메트릭 폴링 중지
    public func stopMetrics() {
        metricsPollingTask?.cancel()
        metricsPollingTask = nil
        wsStreamTask?.cancel()
        wsStreamTask = nil
        Task { await wsClient?.disconnect() }
    }

    /// 메트릭 폴링 일시 완속화 — 앱 비활성 시 120s 간격으로 전환
    public func pauseMetricsPolling() {
        guard metricsClient != nil else { return }
        metricsPollingTask?.cancel()
        metricsPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await self?.loadServerStats()
            }
        }
    }

    /// 메트릭 폴링 재개 — 앱 활성화 시 즉시 1회 갱신 후 30s 간격 복구
    public func resumeMetricsPolling() {
        guard metricsClient != nil else { return }
        metricsPollingTask?.cancel()
        metricsPollingTask = Task { [weak self] in
            await self?.loadServerStats()  // 즉시 1회 갱신
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.loadServerStats()
            }
        }
    }
    
    // MARK: - Data Loading
    
    /// UI용 첫 페이지 로드 (pageSize개, 빠른 표시용)
    public func loadLiveChannels() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nextLiveCursor = nil  // 커서 초기화
        
        do {
            let response = try await apiClient.topLives(size: pageSize)
            let items = response.data.map { info in
                LiveChannelItem(
                    id: info.channel?.channelId ?? "\(info.liveId)",
                    channelName: info.channel?.channelName ?? "Unknown",
                    channelImageUrl: info.channel?.channelImageURL?.absoluteString,
                    liveTitle: info.liveTitle,
                    viewerCount: info.concurrentUserCount,
                    categoryName: info.liveCategoryValue,
                    categoryType: info.categoryType,
                    thumbnailUrl: info.resolvedLiveImageURL?.absoluteString,
                    channelId: info.channel?.channelId ?? ""
                )
            }
            liveChannels = items
            nextLiveCursor = response.page?.next
            hasMoreChannels = nextLiveCursor != nil
            recordViewerSnapshot()
            logger.info("Loaded \(items.count) live channels")
            // 캐시 저장
            let now = Date()
            liveChannelsCachedAt = now
            Task { [store = dataStore, channels = items, ts = now] in
                guard let store else { return }
                try? await store.saveSetting(key: CacheKey.liveChannels, value: channels)
                try? await store.saveSetting(key: CacheKey.liveChannelsCachedAt, value: ts)
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load live channels: \(error)")
        }
        
        isLoading = false
    }
    
    /// 통계 집계용 전체 라이브 채널 수집 (1페이지 ~ 끝페이지 커서 순회)
    public func loadAllStatsChannels() async {
        guard !isLoadingStats else { return }
        isLoadingStats = true
        
        do {
            let all = try await apiClient.allLiveChannels(batchSize: 50)
            let items = all.map { info in
                LiveChannelItem(
                    id: info.channel?.channelId ?? "\(info.liveId)",
                    channelName: info.channel?.channelName ?? "Unknown",
                    channelImageUrl: info.channel?.channelImageURL?.absoluteString,
                    liveTitle: info.liveTitle,
                    viewerCount: info.concurrentUserCount,
                    categoryName: info.liveCategoryValue,
                    categoryType: info.categoryType,
                    thumbnailUrl: info.liveImageURL?.absoluteString,
                    channelId: info.channel?.channelId ?? ""
                )
            }
            allStatChannels = items
            recordViewerSnapshot()
            logger.info("» 전체 라이브 통계 수집 완료: \(items.count)개 채널, 총 \(items.reduce(0) { $0 + $1.viewerCount })명")
            // 캐시 저장
            let now = Date()
            allStatCachedAt = now
            Task { [store = dataStore, stat = items, ts = now] in
                guard let store else { return }
                try? await store.saveSetting(key: CacheKey.allStatChannels, value: stat)
                try? await store.saveSetting(key: CacheKey.allStatCachedAt, value: ts)
            }
        } catch {
            logger.error("전체 통계 수집 실패: \(error)")
        }
        
        isLoadingStats = false
    }
    
    /// Load more channels (커서 기반 페이지네이션)
    public func loadMoreChannels() async {
        guard hasMoreChannels, !isLoading else { return }
        isLoading = true

        do {
            let response = try await apiClient.topLives(
                size: pageSize,
                concurrentUserCount: nextLiveCursor?.concurrentUserCount,
                liveId: nextLiveCursor?.liveId
            )
            let items = response.data.map { info in
                LiveChannelItem(
                    id: info.channel?.channelId ?? "\(info.liveId)",
                    channelName: info.channel?.channelName ?? "Unknown",
                    channelImageUrl: info.channel?.channelImageURL?.absoluteString,
                    liveTitle: info.liveTitle,
                    viewerCount: info.concurrentUserCount,
                    categoryName: info.liveCategoryValue,
                    categoryType: info.categoryType,
                    thumbnailUrl: info.resolvedLiveImageURL?.absoluteString,
                    channelId: info.channel?.channelId ?? ""
                )
            }
            liveChannels.append(contentsOf: items)
            nextLiveCursor = response.page?.next
            hasMoreChannels = nextLiveCursor != nil
        } catch {
            logger.error("Failed to load more channels: \(error)")
        }

        isLoading = false
    }
    
    /// Load following channels
    public func loadFollowingChannels() async {
        isLoadingFollowing = true
        defer { isLoadingFollowing = false }
        do {
            let response = try await apiClient.fetchFollowingChannels()
            followingChannels = response
            needsCookieLogin = false
            logger.info("팔로잉 채널 로드 완료: \(response.count)개")
            // 캐시 저장
            let now = Date()
            followingCachedAt = now
            Task { [store = dataStore, following = response, ts = now] in
                guard let store else { return }
                try? await store.saveSetting(key: CacheKey.followingChannels, value: following)
                try? await store.saveSetting(key: CacheKey.followingCachedAt, value: ts)
            }
        } catch let error as APIError where error == .unauthorized {
            needsCookieLogin = true
            logger.warning("팔로잉 조회 실패: 쿠키 인증 필요 — 네이버 로그인으로 NID 쿠키를 획득하세요")
        } catch {
            logger.error("팔로잉 채널 로드 실패: \(error)")
        }
    }
    
    /// Refresh all data
    public func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadLiveChannels() }       // UI용 첫 페이지 (빠름)
            group.addTask { await self.loadAllStatsChannels() }   // 통계용 전체 (븱그라운드)
            group.addTask { await self.loadFollowingChannels() }
            group.addTask { await self.loadServerStats() }
        }
    }
    
    // MARK: - Metrics Server Data Loading
    
    /// 서버 통계 로드
    public func loadServerStats() async {
        guard let client = metricsClient else { return }
        do {
            let stats = try await client.fetchStats()
            serverStats = stats
            isMetricsServerOnline = true
            serverChannelStats = stats.channelStats ?? []
            serverUptime = stats.stats?.uptime ?? 0
            serverTotalReceived = stats.stats?.totalReceived ?? 0
            wsClientCount = stats.wsClients ?? 0
            serverLastUpdate = Date()
            
            // 레이턴시 스냅샷 기록
            recordLatencySnapshot()
            
            logger.info("메트릭 서버 통계 로드: \(self.serverChannelStats.count) 채널")
        } catch {
            isMetricsServerOnline = false
            logger.debug("메트릭 서버 연결 실패: \(error.localizedDescription)")
        }
    }
    
    /// 30초 주기 메트릭 폴링 시작
    private func startMetricsPolling() {
        metricsPollingTask?.cancel()
        metricsPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadServerStats()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    
    /// WebSocket 실시간 스트림 구독
    private func startWebSocketStream() {
        guard let ws = wsClient else { return }
        wsStreamTask?.cancel()
        wsStreamTask = Task { [weak self] in
            let stream = await ws.connect()
            for await message in stream {
                guard !Task.isCancelled else { break }
                await self?.handleWebSocketMessage(message)
            }
        }
    }
    
    /// WebSocket 메시지 처리
    @MainActor
    private func handleWebSocketMessage(_ msg: MetricsWebSocketMessage) {
        switch msg.type {
        case "stats":
            if let total = msg.totalReceived {
                serverTotalReceived = total
            }
        case "metric":
            // 실시간 메트릭 → 개별 채널 데이터는 다음 폴링에서 반영
            break
        case "app_active_channels":
            activeAppChannelCount = msg.channels?.count ?? 0
        default:
            break
        }
    }
    
    /// 레이턴시 스냅샷 기록
    private func recordLatencySnapshot() {
        guard let web = avgWebLatency, let app = avgAppLatency else { return }
        let now = Date()
        latencyHistory.append(LatencyHistoryEntry(timestamp: now, webLatency: web, appLatency: app))
        if latencyHistory.count > 30 {
            latencyHistory.removeFirst(latencyHistory.count - 30)
        }
    }
    
    // MARK: - Viewer History
    
    private func recordViewerSnapshot() {
        let now = Date()
        // 최소 30초 간격으로 스냅샷
        if let last = lastSnapshotTime, now.timeIntervalSince(last) < 30 { return }
        lastSnapshotTime = now
        viewerHistory.append(ViewerHistoryEntry(timestamp: now, totalViewers: totalViewers))
        // 최근 30개만 유지
        if viewerHistory.count > 30 {
            viewerHistory.removeFirst(viewerHistory.count - 30)
        }
    }
}
