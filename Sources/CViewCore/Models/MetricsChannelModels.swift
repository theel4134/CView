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
    
    // MARK: - Real-time Update Helpers
    
    /// 웹 레이턴시가 업데이트된 복사본 반환
    public func withUpdatedWebLatency(_ latency: Double) -> ChannelStatsItem {
        let newWeb = LatencyStats(
            avg: web.map { ($0.avg ?? latency + latency) / 2.0 } ?? latency,
            min: web.map { Swift.min($0.min ?? latency, latency) } ?? latency,
            max: web.map { Swift.max($0.max ?? latency, latency) } ?? latency,
            samples: (web?.samples ?? 0) + 1,
            last: latency,
            lastUpdate: nil,
            lastUpdated: Date().timeIntervalSince1970,
            lastLatencySource: web?.lastLatencySource
        )
        let newDelta: DeltaStats? = if let appAvg = app?.avg {
            DeltaStats(current: latency - (app?.last ?? appAvg), avg: newWeb.avg.map { $0 - appAvg }, webAvg: newWeb.avg, appAvg: appAvg)
        } else {
            delta
        }
        return ChannelStatsItem(channelId: channelId, channelName: channelName, resolution: resolution, fps: fps, bitrate: bitrate, quality: quality, web: newWeb, app: app, delta: newDelta, broadcast: broadcast, createdAt: createdAt)
    }
    
    /// 앱 레이턴시가 업데이트된 복사본 반환
    public func withUpdatedAppLatency(_ latency: Double) -> ChannelStatsItem {
        let newApp = LatencyStats(
            avg: app.map { ($0.avg ?? latency + latency) / 2.0 } ?? latency,
            min: app.map { Swift.min($0.min ?? latency, latency) } ?? latency,
            max: app.map { Swift.max($0.max ?? latency, latency) } ?? latency,
            samples: (app?.samples ?? 0) + 1,
            last: latency,
            lastUpdate: nil,
            lastUpdated: Date().timeIntervalSince1970,
            lastLatencySource: app?.lastLatencySource
        )
        let newDelta: DeltaStats? = if let webAvg = web?.avg {
            DeltaStats(current: (web?.last ?? webAvg) - latency, avg: webAvg - (newApp.avg ?? latency), webAvg: webAvg, appAvg: newApp.avg)
        } else {
            delta
        }
        return ChannelStatsItem(channelId: channelId, channelName: channelName, resolution: resolution, fps: fps, bitrate: bitrate, quality: quality, web: web, app: newApp, delta: newDelta, broadcast: broadcast, createdAt: createdAt)
    }
    
    /// 최소 데이터로 새 항목 생성
    public static func makeMinimal(channelId: String, channelName: String, latency: Double, isWeb: Bool) -> ChannelStatsItem {
        let stats = LatencyStats(avg: latency, min: latency, max: latency, samples: 1, last: latency, lastUpdate: nil, lastUpdated: Date().timeIntervalSince1970, lastLatencySource: nil)
        return ChannelStatsItem(
            channelId: channelId, channelName: channelName,
            resolution: nil, fps: nil, bitrate: nil, quality: nil,
            web: isWeb ? stats : nil, app: isWeb ? nil : stats,
            delta: nil, broadcast: nil, createdAt: Date().timeIntervalSince1970
        )
    }
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
