// MARK: - MetricsModels.swift
// 메트릭 서버(cv.dododo.app) API 응답/요청 모델

import Foundation

// MARK: - Server Stats (GET /stats)

public struct MetricsServerStats: Codable, Sendable {
    public let success: Bool?
    public let stats: ServerStatsDetail?
    public let platformStats: [String: Int]?
    public let engineStats: [String: Int]?
    public let latencySourceStats: [String: Int]?
    public let channelStats: [ChannelStatsItem]?
    public let channelCount: Int?
    public let wsClients: Int?
}

public struct ServerStatsDetail: Codable, Sendable {
    public let totalReceived: Int?
    public let uptime: Double?
    public let memory: ServerMemory?
}

public struct ServerMemory: Codable, Sendable {
    public let rss: Int?
    public let heapTotal: Int?
    public let heapUsed: Int?
    public let external: Int?
}

// MARK: - Channel Stats Item

public struct ChannelStatsItem: Codable, Sendable, Identifiable {
    public var id: String { channelId }
    public let channelId: String
    public let channelName: String?
    public let web: LatencyStats?
    public let app: LatencyStats?
    public let delta: DeltaStats?
    public let broadcast: BroadcastStats?
}

public struct LatencyStats: Codable, Sendable {
    public let avg: Double?
    public let min: Double?
    public let max: Double?
    public let samples: Int?
    public let lastUpdate: String?
}

public struct DeltaStats: Codable, Sendable {
    public let avg: Double?
    public let webAvg: Double?
    public let appAvg: Double?
}

public struct BroadcastStats: Codable, Sendable {
    public let avg: Double?
    public let samples: Int?
}

// MARK: - Health (GET /health)

public struct MetricsHealthResponse: Codable, Sendable {
    public let status: String
    public let uptime: Double?
    public let totalReceived: Int?
    public let activeAppChannels: Int?
    public let activeWebFetchers: Int?
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
    public let received: Int?
    public let channelStats: ChannelStatsItem?
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
    
    // Chat latency fields
    public let chatLatency: Double?
    public let avgChatLatency: Double?
    public let videoLatency: Double?
    public let sampleCount: Int?
}
