// MARK: - MetricsChannelModels.swift
// CViewCore - 채널별 메트릭, 동기화 추천, PDT, 활성 채널 모델

import Foundation

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
