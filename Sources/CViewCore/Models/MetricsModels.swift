// MARK: - MetricsModels.swift
// 메트릭 서버(cv.dododo.app) API 응답/요청 모델
// v4.0.3 서버 호환 + v3.0.0 하위 호환

import Foundation

// MARK: - Server Stats (GET /api/stats)

public struct MetricsServerStats: Codable, Sendable {
    // v4.0.3 nested format
    public let success: Bool?
    public let stats: ServerStatsDetail?
    public let channelStats: [ChannelStatsItem]?
    public let channelCount: Int?
    public let liveAggregation: LiveAggregation?

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

// MARK: - Channel Stats Item

public struct ChannelStatsItem: Codable, Sendable, Identifiable {
    public var id: String { channelId }
    public let channelId: String
    public let channelName: String?
    public let resolution: String?
    public let fps: Double?
    public let bitrate: Double?
    public let quality: String?
    public let web: LatencyStats?
    public let app: LatencyStats?
    public let delta: DeltaStats?
    public let broadcast: BroadcastStats?
    public let createdAt: Double?
}

public struct LatencyStats: Codable, Sendable {
    public let avg: Double?
    public let min: Double?
    public let max: Double?
    public let samples: Int?
    public let last: Double?
    public let lastUpdate: String?
    public let lastUpdated: Double?
    public let lastLatencySource: String?
}

public struct DeltaStats: Codable, Sendable {
    public let current: Double?
    public let avg: Double?
    public let webAvg: Double?
    public let appAvg: Double?
}

public struct BroadcastStats: Codable, Sendable {
    public let title: String?
    public let category: String?
    public let concurrentUsers: Int?
    public let accumulateCount: Int?
    public let durationSeconds: Int?
    public let isAdult: Bool?
    public let status: String?
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

// MARK: - Channel Detail (GET /api/channel/:id/stats)

public struct ChannelMetricsDetail: Codable, Sendable {
    public let success: Bool?
    public let channelId: String?
    public let channelName: String?
    public let web: LatencyStats?
    public let app: LatencyStats?
    public let delta: DeltaStats?
    public let broadcast: BroadcastStats?
}

// MARK: - Real Latency (GET /api/channel/:id/real-latency)

public struct RealLatencyResponse: Codable, Sendable {
    public let success: Bool?
    public let channelId: String?
    public let latency: Double?
    public let source: String?
    public let timestamp: String?
}

// MARK: - Sync Recommendation (GET /api/channel/:id/sync-recommendation)

public struct SyncRecommendationResponse: Codable, Sendable {
    public let success: Bool?
    public let recommendation: SyncRecommendation?
}

public struct SyncRecommendation: Codable, Sendable {
    public let action: String?          // catchup, slowdown, seek, hold
    public let targetSpeed: Double?
    public let seekTarget: Double?
    public let confidence: Double?
    public let reasoning: String?
    public let currentState: SyncCurrentState?
    public let serverStats: SyncServerStats?
}

public struct SyncCurrentState: Codable, Sendable {
    public let appLatency: Double?
    public let webLatency: Double?
    public let delta: Double?
    public let streamStartTime: String?
    public let streamElapsedSeconds: Double?
}

public struct SyncServerStats: Codable, Sendable {
    public let webSamples: Int?
    public let appSamples: Int?
    public let avgDelta: Double?
}

// MARK: - PDT Sync (GET /api/channel/:id/pdt-sync)

public struct PDTSyncResponse: Codable, Sendable {
    public let success: Bool?
    public let channelId: String?
    public let drift: Double?
    public let avgDrift: Double?
    public let driftTrend: Double?
    public let sampleCount: Int?
}

// MARK: - Active Channels (GET /api/app/channels/active)

public struct ActiveAppChannelsResponse: Codable, Sendable {
    public let success: Bool?
    public let channels: [ActiveChannel]?
}

public struct ActiveChannel: Codable, Sendable, Identifiable {
    public var id: String { channelId }
    public let channelId: String
    public let channelName: String?
    public let source: String?
    public let lastPing: String?
}

// MARK: - POST Request Bodies

public struct AppLatencyPayload: Codable, Sendable {
    public let channelId: String
    public let channelName: String
    public let latency: Double
    public let targetLatency: Double?
    public let bitrate: Int?
    public let resolution: String?
    public let frameRate: Double?
    public let droppedFrames: Int?
    public let bufferHealth: Double?
    public let playbackRate: Double?
    public let engine: String
    public let healthScore: Double?
    public let latencySource: String?
    public let isBroadcastBased: Bool?
    
    public init(
        channelId: String, channelName: String, latency: Double,
        targetLatency: Double? = nil, bitrate: Int? = nil, resolution: String? = nil,
        frameRate: Double? = nil, droppedFrames: Int? = nil, bufferHealth: Double? = nil,
        playbackRate: Double? = nil, engine: String = "VLC", healthScore: Double? = nil,
        latencySource: String? = "native", isBroadcastBased: Bool? = false
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.latency = latency
        self.targetLatency = targetLatency
        self.bitrate = bitrate
        self.resolution = resolution
        self.frameRate = frameRate
        self.droppedFrames = droppedFrames
        self.bufferHealth = bufferHealth
        self.playbackRate = playbackRate
        self.engine = engine
        self.healthScore = healthScore
        self.latencySource = latencySource
        self.isBroadcastBased = isBroadcastBased
    }
}

public struct AppLatencyPostResponse: Codable, Sendable {
    public let success: Bool?
    public let latency: Double?
    public let message: String?
    public let received: Int?
    public let channelStats: ChannelStatsItem?
    public let webLatency: WebLatencyInfo?
}

public struct ChannelActivatePayload: Codable, Sendable {
    public let channelId: String
    public let channelName: String
    public let streamUrl: String?
    public let source: String
    
    public init(channelId: String, channelName: String, streamUrl: String? = nil, source: String = "VLC") {
        self.channelId = channelId
        self.channelName = channelName
        self.streamUrl = streamUrl
        self.source = source
    }
}

public struct ChannelActivateResponse: Codable, Sendable {
    public let success: Bool?
    public let data: ChannelActivateData?
}

public struct ChannelActivateData: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let broadcastedTo: Int?
}

public struct PDTSyncPayload: Codable, Sendable {
    public let channelId: String
    public let channelName: String
    public let appPDT: Double
    public let currentTime: Double
    public let latency: Double
    public let latencySource: String?
    
    public init(channelId: String, channelName: String, appPDT: Double, currentTime: Double, latency: Double, latencySource: String? = "native") {
        self.channelId = channelId
        self.channelName = channelName
        self.appPDT = appPDT
        self.currentTime = currentTime
        self.latency = latency
        self.latencySource = latencySource
    }
}

// MARK: - WebSocket Message

public struct MetricsWebSocketMessage: Codable, Sendable {
    public let type: String
    public let channelId: String?
    public let channelName: String?
    public let latency: Double?
    public let platform: String?
    public let engine: String?
    public let source: String?
    public let totalReceived: Int?
    public let action: String?
    public let targetSpeed: Double?
    public let channels: [ActiveChannel]?
    public let data: MetricsWebSocketData?

    // Chat latency fields
    public let chatLatency: Double?
    public let avgChatLatency: Double?
    public let videoLatency: Double?
    public let sampleCount: Int?
}

/// WebSocket "data" 필드 (metric, web_position, live_channels_update 등)
public struct MetricsWebSocketData: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let platform: String?
    public let source: String?
    public let latency: Double?
    public let timestamp: Double?
    public let currentTime: Double?
    public let duration: Double?
    public let bufferedEnd: Double?
    public let bufferLength: Double?
    public let totalLive: Int?
    public let totalViewers: Int?
}

/// 웹 레이턴시 정보 (POST /api/metrics 응답에 포함)
public struct WebLatencyInfo: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let latency: Double?
    public let source: String?
    public let timestamp: Double?
}
