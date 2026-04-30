// MARK: - MetricsPayloadModels.swift
// CViewCore - 메트릭 POST 요청 페이로드 및 WebSocket 메시지 모델

import Foundation

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
    public let latencyUnit: String?
    
    public init(
        channelId: String, channelName: String, latency: Double,
        targetLatency: Double? = nil, bitrate: Int? = nil, resolution: String? = nil,
        frameRate: Double? = nil, droppedFrames: Int? = nil, bufferHealth: Double? = nil,
        playbackRate: Double? = nil, engine: String = "VLC", healthScore: Double? = nil,
        latencySource: String? = "native", isBroadcastBased: Bool? = false,
        latencyUnit: String? = "ms"
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
        self.latencyUnit = latencyUnit
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

// MARK: - Auth Cookie Sync

/// NID 쿠키 서버 동기화 페이로드
public struct AuthCookieSyncPayload: Codable, Sendable {
    public let NID_AUT: String
    public let NID_SES: String
    public let source: String

    public init(nidAut: String, nidSes: String, source: String = "app") {
        self.NID_AUT = nidAut
        self.NID_SES = nidSes
        self.source = source
    }
}

/// NID 쿠키 서버 동기화 응답
public struct AuthCookieSyncResponse: Codable, Sendable {
    public let success: Bool
    public let message: String?
    public let userIdHash: String?
}
