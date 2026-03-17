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
    
    // 통계 수집 진행률
    public var statsCollectionProgress: Double = 0
    public var statsCollectedCount: Int = 0
    public var statsEstimatedTotal: Int? = nil
    
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
    /// 활성 앱 채널 수
    public var activeAppChannelCount: Int = 0
    /// 서버 마지막 갱신 시각
    public var serverLastUpdate: Date?
    
    private var metricsPollingTask: Task<Void, Never>?
    private var wsStreamTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    
    // MARK: - Cached Stats (데이터 변경 시 1회 계산, body 접근 시 O(1))
    
    /// 카테고리 탐색용: 통계 수집 완료 시 allStatChannels, 아직이면 liveChannels
    public var categoryChannels: [LiveChannelItem] {
        allStatChannels.isEmpty ? liveChannels : allStatChannels
    }
    
    public private(set) var totalViewers: Int = 0
    public private(set) var averageViewers: Int = 0
    public private(set) var categoryCount: Int = 0
    public private(set) var totalLiveChannelCount: Int = 0
    public private(set) var topCategories: [CategoryStat] = []
    public private(set) var followingLiveCount: Int = 0
    public private(set) var recentLiveFollowing: [LiveChannelItem] = []
    public private(set) var topChannels: [LiveChannelItem] = []
    public private(set) var categoryTypeDistribution: [CategoryTypeStat] = []
    public private(set) var viewerBuckets: [ViewerBucket] = []
    public private(set) var medianViewers: Int = 0
    public private(set) var followingLiveRate: Int = 0
    public private(set) var followingTotalViewers: Int = 0
    public private(set) var topThreeChannels: [LiveChannelItem] = []

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
    
    /// CView 전체 통계 집계 (품질 등급, 동기화율 등)
    public var cviewAggregate: CViewAggregate? {
        serverStats?.cviewSummary?.aggregate
    }
    
    /// CView 연결 클라이언트 수
    public var cviewConnectedClients: Int {
        serverStats?.cviewSummary?.connectedClients ?? 0
    }
    
    /// CView 동기화 채널 목록
    public var cviewSyncChannels: [CViewStatsSyncChannel] {
        serverStats?.cviewSummary?.syncChannels ?? []
    }

    /// 서버 버전
    public var serverVersion: String? {
        serverStats?.serverVersion
    }
    
    /// 서버 포맷 업타임
    public var formattedUptime: String {
        let hours = Int(serverUptime) / 3600
        let mins = (Int(serverUptime) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// statsSource 변경 시 1회 호출 — O(N) ~ O(N log N) 연산을 body 밖에서 수행
    private func recomputeStats() {
        let raw = allStatChannels.isEmpty ? liveChannels : allStatChannels
        
        // 방어적 channelId 중복 제거
        var seen = Set<String>()
        let source = raw.filter { seen.insert($0.id).inserted }

        totalLiveChannelCount = source.count
        totalViewers = source.reduce(0) { $0 + $1.viewerCount }
        averageViewers = source.isEmpty ? 0 : totalViewers / source.count

        let categories = Set(source.compactMap { $0.categoryName })
        categoryCount = categories.count

        let grouped = Dictionary(grouping: source) { $0.categoryName ?? "기타" }
        topCategories = grouped.map { name, channels in
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

        let sorted = source.sorted { $0.viewerCount > $1.viewerCount }
        topThreeChannels = Array(sorted.prefix(3))
        topChannels = Array(liveChannels.sorted { $0.viewerCount > $1.viewerCount }.prefix(6))

        // 카테고리 타입별 분포
        if !source.isEmpty {
            let typeGrouped = Dictionary(grouping: source) { $0.categoryType ?? "ETC" }
            let total = source.count
            categoryTypeDistribution = typeGrouped.map { type, channels in
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
        } else {
            categoryTypeDistribution = []
        }

        // 시청자 구간별 분포 — O(N)
        let defs: [(label: String, min: Int, max: Int)] = [
            ("0~100", 0, 100), ("100~1K", 100, 1_000),
            ("1K~1만", 1_000, 10_000), ("1만+", 10_000, Int.max)
        ]
        var counts = Array(repeating: 0, count: defs.count)
        for item in source {
            let v = item.viewerCount
            if v < 100 { counts[0] += 1 }
            else if v < 1_000 { counts[1] += 1 }
            else if v < 10_000 { counts[2] += 1 }
            else { counts[3] += 1 }
        }
        viewerBuckets = defs.enumerated().map { idx, d in
            ViewerBucket(id: d.label, label: d.label, count: counts[idx], minViewers: d.min, maxViewers: d.max)
        }

        // 중앙값 — O(N log N)
        let viewersSorted = source.map { $0.viewerCount }.sorted()
        if viewersSorted.isEmpty {
            medianViewers = 0
        } else {
            let mid = viewersSorted.count / 2
            medianViewers = viewersSorted.count % 2 == 0 ? (viewersSorted[mid - 1] + viewersSorted[mid]) / 2 : viewersSorted[mid]
        }
    }

    /// followingChannels 변경 시 1회 호출
    private func recomputeFollowingStats() {
        let live = followingChannels.filter { $0.isLive }
        followingLiveCount = live.count
        recentLiveFollowing = Array(live.prefix(6))
        followingTotalViewers = live.reduce(0) { $0 + $1.viewerCount }
        followingLiveRate = followingChannels.isEmpty ? 0 : followingLiveCount * 100 / followingChannels.count
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
            recomputeStats()
            recomputeFollowingStats()
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
    
    // MARK: - Auto Refresh (홈 화면 표시 중 90초 주기)
    
    /// 홈 화면 표시 시 90초 주기 경량 자동 갱신 시작
    /// - 라이브 채널 첫 페이지 + 팔로잉만 갱신 (가벼운 API 2회)
    /// - 전체 통계(allStatsChannels)는 수동 새로고침 시에만 수행 (무거운 전체 페이지 순회)
    /// - 메트릭 서버는 별도 30초 폴링으로 관리
    public func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            for await _ in AsyncTimerSequence(interval: .seconds(90), tolerance: .seconds(10)) {
                guard !Task.isCancelled else { break }
                await self?.lightRefresh()
            }
        }
    }
    
    /// 홈 화면 이탈 시 자동 갱신 중지
    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
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
            recomputeStats()
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
    
    /// 통계 집계용 전체 라이브 채널 수집 (진행률 + 중복 제거 + 에러 탄력성)
    public func loadAllStatsChannels() async {
        guard !isLoadingStats else { return }
        isLoadingStats = true
        statsCollectionProgress = 0
        statsCollectedCount = 0
        statsEstimatedTotal = nil
        
        do {
            let all = try await apiClient.allLiveChannelsProgressive(batchSize: 50) { [weak self] progress in
                guard let self else { return }
                self.statsCollectedCount = progress.currentCount
                self.statsEstimatedTotal = progress.estimatedTotal
                if let total = progress.estimatedTotal, total > 0 {
                    self.statsCollectionProgress = min(Double(progress.currentCount) / Double(total), 1.0)
                }
                // 매 5페이지마다 중간 통계 갱신
                if progress.currentPage % 5 == 0 {
                    self.updateStatsFromPartial(all: nil)
                }
            }
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
            statsCollectionProgress = 1.0
            statsCollectedCount = items.count
            recomputeStats()
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
    
    /// 부분 수집 중 중간 통계 갱신
    private func updateStatsFromPartial(all: [LiveChannelItem]?) {
        if let all {
            allStatChannels = all
        }
        recomputeStats()
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
            recomputeStats()
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
            recomputeFollowingStats()
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
    
    /// 전체 새로고침 (수동 새로고침 시 사용)
    public func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadLiveChannels() }       // UI용 첫 페이지 (빠름)
            group.addTask { await self.loadAllStatsChannels() }   // 통계용 전체 (백그라운드)
            group.addTask { await self.loadFollowingChannels() }
            group.addTask { await self.loadServerStats() }
        }
    }
    
    /// 경량 갱신 (자동 갱신용 — 무거운 전체 통계 제외)
    public func lightRefresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadLiveChannels() }
            group.addTask { await self.loadFollowingChannels() }
        }
    }
    
    // MARK: - Metrics Server Data Loading
    
    /// 서버 통계 로드
    public func loadServerStats() async {
        guard let client = metricsClient else { return }
        do {
            // v4.5 overview API 우선 시도
            let overview = try await client.fetchOverview()
            isMetricsServerOnline = true
            serverTotalReceived = overview.data?.totalMetrics ?? 0
            activeAppChannelCount = overview.data?.activeChannels ?? 0
            serverLastUpdate = Date()
            
            // health에서 uptime 보완
            if let health = try? await client.fetchHealth() {
                serverUptime = health.uptime ?? 0
            }
            
            // legacy /api/stats에서 채널 상세·CView 요약 등 대시보드 전용 데이터 로드
            if let stats = try? await client.fetchStats() {
                serverStats = stats
                serverChannelStats = stats.channelStats ?? []
            }
            
            recordLatencySnapshot()
            logger.info("메트릭 서버 통계 로드 (v4.5): 활성 \(overview.data?.activeChannels ?? 0)채널, 라이브 \(overview.data?.liveCount ?? 0)")
        } catch {
            // v4.5 실패 시 legacy /api/stats 폴백
            do {
                let stats = try await client.fetchStats()
                serverStats = stats
                isMetricsServerOnline = true
                serverChannelStats = stats.channelStats ?? []
                serverUptime = stats.resolvedUptime
                serverTotalReceived = stats.resolvedTotalReceived
                serverLastUpdate = Date()
                recordLatencySnapshot()
                logger.info("메트릭 서버 통계 로드 (legacy): \(self.serverChannelStats.count) 채널")
            } catch {
                isMetricsServerOnline = false
                logger.debug("메트릭 서버 연결 실패: \(error.localizedDescription)")
            }
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
