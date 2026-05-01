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
//
// [Shape Tolerance 2026-04-28]
// 실제 cv.dododo.app 서버는 nested `{data:{...}}` 가 아니라 flat 형태로 응답한다.
//   {"success": true, "activeChannels": 0, "totalMetrics24h": 168124, "avgLatency1h": null, "connectedClients": 0}
// 또한 v4.5 명세는 `totalMetrics` / `avgLatency` 키를 쓰는 반면 실제 서버는
// `totalMetricsXX h` / `avgLatencyXh` 등 윈도우 접미사가 붙은 키를 쓴다.
// 양쪽 형태를 모두 받아들이는 관용 디코더를 구현한다.

public struct MetricsOverviewResponse: Codable, Sendable {
    public let status: String?
    public let data: MetricsOverviewData?

    public init(status: String? = nil, data: MetricsOverviewData? = nil) {
        self.status = status
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case status, data, success
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // status: 명시 status 또는 success(bool) 도출
        if let s = try c.decodeIfPresent(String.self, forKey: .status) {
            self.status = s
        } else if let ok = try c.decodeIfPresent(Bool.self, forKey: .success) {
            self.status = ok ? "ok" : "error"
        } else {
            self.status = nil
        }
        // data 가 있으면 그대로, 없으면 top-level 에서 합성
        if let nested = try c.decodeIfPresent(MetricsOverviewData.self, forKey: .data) {
            self.data = nested
        } else {
            self.data = try? MetricsOverviewData(from: decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(data, forKey: .data)
    }
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
    /// cv.dododo.app 의 connectedClients (overview flat 응답).
    public let connectedClients: Int?

    public init(
        activeChannels: Int? = nil,
        avgBitrate: Double? = nil,
        avgFps: Double? = nil,
        avgHealthScore: Double? = nil,
        avgLatency: Double? = nil,
        liveCount: Int? = nil,
        totalChannels: Int? = nil,
        totalMetrics: Int? = nil,
        connectedClients: Int? = nil
    ) {
        self.activeChannels = activeChannels
        self.avgBitrate = avgBitrate
        self.avgFps = avgFps
        self.avgHealthScore = avgHealthScore
        self.avgLatency = avgLatency
        self.liveCount = liveCount
        self.totalChannels = totalChannels
        self.totalMetrics = totalMetrics
        self.connectedClients = connectedClients
    }

    private enum CodingKeys: String, CodingKey {
        case activeChannels, avgBitrate, avgFps, avgHealthScore, avgLatency
        case liveCount, totalChannels, totalMetrics, connectedClients
        // cv.dododo.app flat 응답 alias
        case totalMetrics24h, totalMetrics1h, avgLatency1h, avgLatency24h
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeChannels = try c.decodeIfPresent(Int.self, forKey: .activeChannels)
        avgBitrate = try c.decodeIfPresent(Double.self, forKey: .avgBitrate)
        avgFps = try c.decodeIfPresent(Double.self, forKey: .avgFps)
        avgHealthScore = try c.decodeIfPresent(Double.self, forKey: .avgHealthScore)
        avgLatency = try c.decodeIfPresent(Double.self, forKey: .avgLatency)
            ?? c.decodeIfPresent(Double.self, forKey: .avgLatency1h)
            ?? c.decodeIfPresent(Double.self, forKey: .avgLatency24h)
        liveCount = try c.decodeIfPresent(Int.self, forKey: .liveCount)
        totalChannels = try c.decodeIfPresent(Int.self, forKey: .totalChannels)
        totalMetrics = try c.decodeIfPresent(Int.self, forKey: .totalMetrics)
            ?? c.decodeIfPresent(Int.self, forKey: .totalMetrics24h)
            ?? c.decodeIfPresent(Int.self, forKey: .totalMetrics1h)
        connectedClients = try c.decodeIfPresent(Int.self, forKey: .connectedClients)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(activeChannels, forKey: .activeChannels)
        try c.encodeIfPresent(avgBitrate, forKey: .avgBitrate)
        try c.encodeIfPresent(avgFps, forKey: .avgFps)
        try c.encodeIfPresent(avgHealthScore, forKey: .avgHealthScore)
        try c.encodeIfPresent(avgLatency, forKey: .avgLatency)
        try c.encodeIfPresent(liveCount, forKey: .liveCount)
        try c.encodeIfPresent(totalChannels, forKey: .totalChannels)
        try c.encodeIfPresent(totalMetrics, forKey: .totalMetrics)
        try c.encodeIfPresent(connectedClients, forKey: .connectedClients)
    }
}

// MARK: - Stats System (GET /api/stats/system — v4.5+)
//
// [Shape Tolerance 2026-04-28]
// cv.dododo.app 실제 응답은 다음과 같다:
//   {"success": true,
//    "db": {"size_bytes": 965514931},
//    "records": {"last_24h": 168124, "total": 1218583},
//    "services": {"cview-api": "healthy"}}
// 명세상의 nested `data: {influxdb, postgres, redis, recordCounts}` 와 다르므로
// flat 응답을 services 맵 + recordCounts 합성으로 매핑한다.

public struct MetricsSystemResponse: Codable, Sendable {
    public let status: String?
    public let data: MetricsSystemData?

    public init(status: String? = nil, data: MetricsSystemData? = nil) {
        self.status = status
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case status, data, success
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try c.decodeIfPresent(String.self, forKey: .status) {
            self.status = s
        } else if let ok = try c.decodeIfPresent(Bool.self, forKey: .success) {
            self.status = ok ? "ok" : "error"
        } else {
            self.status = nil
        }
        if let nested = try c.decodeIfPresent(MetricsSystemData.self, forKey: .data) {
            self.data = nested
        } else {
            self.data = try? MetricsSystemData(from: decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(data, forKey: .data)
    }
}

public struct MetricsSystemData: Codable, Sendable {
    public let checkedAt: String?
    public let influxdb: InfluxDBStatus?
    public let postgres: String?
    public let recordCounts: RecordCounts?
    public let redis: RedisStatus?

    /// flat 응답 추가 필드 — DB 디스크 크기.
    public let dbSizeBytes: Int?
    /// flat 응답 추가 필드 — 24시간 레코드 수.
    public let recordsLast24h: Int?
    /// flat 응답 추가 필드 — 누적 레코드 수.
    public let recordsTotal: Int?
    /// flat 응답 추가 필드 — 서비스 healthcheck 맵 (예: ["cview-api": "healthy"]).
    public let services: [String: String]?

    public init(
        checkedAt: String? = nil,
        influxdb: InfluxDBStatus? = nil,
        postgres: String? = nil,
        recordCounts: RecordCounts? = nil,
        redis: RedisStatus? = nil,
        dbSizeBytes: Int? = nil,
        recordsLast24h: Int? = nil,
        recordsTotal: Int? = nil,
        services: [String: String]? = nil
    ) {
        self.checkedAt = checkedAt
        self.influxdb = influxdb
        self.postgres = postgres
        self.recordCounts = recordCounts
        self.redis = redis
        self.dbSizeBytes = dbSizeBytes
        self.recordsLast24h = recordsLast24h
        self.recordsTotal = recordsTotal
        self.services = services
    }

    private enum CodingKeys: String, CodingKey {
        case checkedAt, influxdb, postgres, recordCounts, redis
        case dbSizeBytes, recordsLast24h, recordsTotal, services
        // flat 응답 키
        case db, records
    }

    private struct DBField: Decodable {
        let size_bytes: Int?
    }
    private struct RecordsField: Decodable {
        let last_24h: Int?
        let total: Int?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try c.decodeIfPresent(String.self, forKey: .checkedAt)
        influxdb = try c.decodeIfPresent(InfluxDBStatus.self, forKey: .influxdb)
        postgres = try c.decodeIfPresent(String.self, forKey: .postgres)
        recordCounts = try c.decodeIfPresent(RecordCounts.self, forKey: .recordCounts)
        redis = try c.decodeIfPresent(RedisStatus.self, forKey: .redis)

        // 명시 필드 우선
        if let direct = try c.decodeIfPresent(Int.self, forKey: .dbSizeBytes) {
            dbSizeBytes = direct
        } else if let dbField = try c.decodeIfPresent(DBField.self, forKey: .db) {
            dbSizeBytes = dbField.size_bytes
        } else {
            dbSizeBytes = nil
        }

        if let direct = try c.decodeIfPresent(Int.self, forKey: .recordsLast24h) {
            recordsLast24h = direct
        } else if let rec = try c.decodeIfPresent(RecordsField.self, forKey: .records) {
            recordsLast24h = rec.last_24h
        } else {
            recordsLast24h = nil
        }

        if let direct = try c.decodeIfPresent(Int.self, forKey: .recordsTotal) {
            recordsTotal = direct
        } else if let rec = try c.decodeIfPresent(RecordsField.self, forKey: .records) {
            recordsTotal = rec.total
        } else {
            recordsTotal = nil
        }

        services = try c.decodeIfPresent([String: String].self, forKey: .services)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(checkedAt, forKey: .checkedAt)
        try c.encodeIfPresent(influxdb, forKey: .influxdb)
        try c.encodeIfPresent(postgres, forKey: .postgres)
        try c.encodeIfPresent(recordCounts, forKey: .recordCounts)
        try c.encodeIfPresent(redis, forKey: .redis)
        try c.encodeIfPresent(dbSizeBytes, forKey: .dbSizeBytes)
        try c.encodeIfPresent(recordsLast24h, forKey: .recordsLast24h)
        try c.encodeIfPresent(recordsTotal, forKey: .recordsTotal)
        try c.encodeIfPresent(services, forKey: .services)
    }
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
