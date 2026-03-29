// MARK: - MetricsServerModels.swift
// CViewCore - 메트릭 서버 통계/시스템/카테고리/랭킹 응답 모델

import Foundation

// MARK: - Server Stats (GET /api/stats — legacy v4.0.3)

public struct MetricsServerStats: Codable, Sendable {
    // v4.0.3 nested format
    public let success: Bool?
    public let stats: ServerStatsDetail?
    public let channelStats: [ChannelStatsItem]?
    public let channelCount: Int?
    public let liveAggregation: LiveAggregation?

    // CView 앱 요약 (from /api/stats)
    public let cviewSummary: CViewStatsSummary?

    // 서버 버전 (v4.0.3+)
    public let serverVersion: String?

    // v3.0.0 flat format fallback
    public let totalReceived: Int?
    public let uptime: Double?
    public let connected: Bool?
    public let totalChannels: Int?
    public let platforms: [String: Int]?
    public let sources: [String: Int]?

    /// v3/v4 공통 접근 헬퍼
    public var resolvedUptime: Double {
        stats?.uptime ?? uptime ?? 0
    }
    public var resolvedTotalReceived: Int {
        stats?.totalReceived ?? totalReceived ?? 0
    }
    public var resolvedChannelCount: Int {
        channelCount ?? totalChannels ?? channelStats?.count ?? 0
    }
    public var resolvedPlatforms: [String: Int] {
        stats?.platforms ?? platforms ?? [:]
    }
    public var resolvedSources: [String: Int] {
        stats?.sources ?? sources ?? [:]
    }
}

// MARK: - Stats Overview (GET /api/stats/overview — v4.5+)

public struct MetricsOverviewResponse: Codable, Sendable {
    public let status: String?
    public let data: MetricsOverviewData?
}

public struct MetricsOverviewData: Codable, Sendable {
    public let activeChannels: Int?
    public let avgBitrate: Double?
    public let avgFps: Double?
    public let avgHealthScore: Double?
    public let avgLatency: Double?
    public let liveCount: Int?
    public let totalChannels: Int?
    public let totalMetrics: Int?
}

// MARK: - Stats System (GET /api/stats/system — v4.5+)

public struct MetricsSystemResponse: Codable, Sendable {
    public let status: String?
    public let data: MetricsSystemData?
}

public struct MetricsSystemData: Codable, Sendable {
    public let checkedAt: String?
    public let influxdb: InfluxDBStatus?
    public let postgres: String?
    public let recordCounts: RecordCounts?
    public let redis: RedisStatus?
}

public struct InfluxDBStatus: Codable, Sendable {
    public let status: String?
    public let version: String?
}

public struct RedisStatus: Codable, Sendable {
    public let status: String?
    public let usedMemory: String?
}

public struct RecordCounts: Codable, Sendable {
    public let channels: Int?
    public let dailyStats: Int?
    public let hourlyStats: Int?
    public let vlcMetrics: Int?
    public let webMetrics: Int?
}

// MARK: - Stats Categories (GET /api/stats/categories — v4.5+)

public struct MetricsCategoriesResponse: Codable, Sendable {
    public let status: String?
    public let data: [MetricsCategoryItem]?
}

public struct MetricsCategoryItem: Codable, Sendable, Identifiable {
    public var id: String { category }
    public let avgViewers: String?
    public let category: String
    public let liveCount: Int?
    public let totalViewers: Int?
}

// MARK: - Stats Channel Ranking (GET /api/stats/channels/ranking — v4.5+)

public struct MetricsChannelRankingResponse: Codable, Sendable {
    public let status: String?
    public let data: [MetricsRankedChannel]?
    public let meta: RankingMeta?
}

public struct MetricsRankedChannel: Codable, Sendable, Identifiable {
    public var id: String { channelId }
    public let category: String?
    public let channelId: String
    public let channelName: String?
    public let imageUrl: String?
    public let rank: Int?
    public let title: String?
    public let viewers: Int?
}

public struct RankingMeta: Codable, Sendable {
    public let sort: String?
}

// MARK: - Server Stats Detail

public struct ServerStatsDetail: Codable, Sendable {
    public let totalReceived: Int?
    public let uptime: Double?
    public let lastReceived: String?
    public let sources: [String: Int]?
    public let platforms: [String: Int]?
    public let engines: [String: Int]?
    public let bitrate: BitrateStats?
    public let memory: ServerMemory?
}

public struct BitrateStats: Codable, Sendable {
    public let total: Double?
    public let count: Int?
    public let avg: Double?
    public let min: Double?
    public let max: Double?
    public let last: Double?
}

public struct ServerMemory: Codable, Sendable {
    public let rss: Int?
    public let heapTotal: Int?
    public let heapUsed: Int?
    public let external: Int?
}

public struct LiveAggregation: Codable, Sendable {
    public let totalLive: Int?
    public let totalViewers: Int?
    public let categoryStats: [String: Int]?
    public let updatedAt: Double?
}

// MARK: - Health (GET /health)

public struct MetricsHealthResponse: Codable, Sendable {
    public let status: String
    public let uptime: Double?
    public let version: String?
    public let channels: Int?
    public let connected: Bool?
    public let database: HealthDatabase?
    // v3.0.0 fallback
    public let totalReceived: Int?
    public let activeAppChannels: Int?
    public let activeWebFetchers: Int?
}

public struct HealthDatabase: Codable, Sendable {
    public let available: Bool?
    public let connected: Bool?
    public let healthy: Bool?
    public let redis_connected: Bool?
}
