// MARK: - CViewIntegrationModels.swift
// CViewCore - CView 앱 통합 모델 (connect/heartbeat/sync/chat-relay/stats)

import Foundation

// MARK: - CView Connect

/// POST /api/cview/connect 요청
public struct CViewConnectPayload: Codable, Sendable {
    public let clientId: String
    public let appVersion: String
    public let platform: String
    public let engine: String
    public let channelId: String?
    public let channelName: String?
    
    public init(
        clientId: String,
        appVersion: String,
        platform: String = "macOS",
        engine: String = "VLC",
        channelId: String? = nil,
        channelName: String? = nil
    ) {
        self.clientId = clientId
        self.appVersion = appVersion
        self.platform = platform
        self.engine = engine
        self.channelId = channelId
        self.channelName = channelName
    }
}

/// POST /api/cview/connect 응답
public struct CViewConnectResponse: Codable, Sendable {
    public let success: Bool
    public let clientId: String?
    public let serverVersion: String?
    public let serverTime: Int?
    public let channelStats: CViewChannelStatsData?
    public let syncData: CViewSyncData?
    public let activeChannels: [CViewActiveChannel]?
    public let connectedClients: Int?
}

/// POST /api/cview/disconnect 요청
public struct CViewDisconnectPayload: Codable, Sendable {
    public let clientId: String
    public let channelId: String?
    
    public init(clientId: String, channelId: String? = nil) {
        self.clientId = clientId
        self.channelId = channelId
    }
}

// MARK: - CView Heartbeat

/// POST /api/cview/heartbeat 요청
public struct CViewHeartbeatPayload: Codable, Sendable {
    public let clientId: String
    public let channelId: String
    public let channelName: String
    public let latency: Double
    public let resolution: String?
    public let bitrate: Int?
    public let fps: Double?
    public let bufferHealth: Double?
    public let playbackRate: Double?
    public let droppedFrames: Int?
    public let healthScore: Double?
    public let engine: String
    public let vlcMetrics: CViewVLCMetrics?
    // 서버 정밀 분석용 확장 필드
    public let targetLatency: Double?
    public let connectionState: String?
    public let connectionQuality: String?
    public let isBuffering: Bool?
    public let latePictures: Int?
    // 정밀 동기화용 위치/PDT 필드
    public let currentTime: Double?
    public let pdtTimestamp: Double?
    public let pdtLatency: Double?
    public let latencyUnit: String?
    
    public init(
        clientId: String,
        channelId: String,
        channelName: String,
        latency: Double,
        resolution: String? = nil,
        bitrate: Int? = nil,
        fps: Double? = nil,
        bufferHealth: Double? = nil,
        playbackRate: Double? = nil,
        droppedFrames: Int? = nil,
        healthScore: Double? = nil,
        engine: String = "VLC",
        vlcMetrics: CViewVLCMetrics? = nil,
        targetLatency: Double? = nil,
        connectionState: String? = nil,
        connectionQuality: String? = nil,
        isBuffering: Bool? = nil,
        latePictures: Int? = nil,
        currentTime: Double? = nil,
        pdtTimestamp: Double? = nil,
        pdtLatency: Double? = nil,
        latencyUnit: String? = "ms"
    ) {
        self.clientId = clientId
        self.channelId = channelId
        self.channelName = channelName
        self.latency = latency
        self.resolution = resolution
        self.bitrate = bitrate
        self.fps = fps
        self.bufferHealth = bufferHealth
        self.playbackRate = playbackRate
        self.droppedFrames = droppedFrames
        self.healthScore = healthScore
        self.engine = engine
        self.vlcMetrics = vlcMetrics
        self.targetLatency = targetLatency
        self.connectionState = connectionState
        self.connectionQuality = connectionQuality
        self.isBuffering = isBuffering
        self.latePictures = latePictures
        self.currentTime = currentTime
        self.pdtTimestamp = pdtTimestamp
        self.pdtLatency = pdtLatency
        self.latencyUnit = latencyUnit
    }
}

/// CView 하트비트에 포함되는 VLC 미디어 통계
public struct CViewVLCMetrics: Codable, Sendable {
    public let inputBitrate: Double?
    public let demuxBitrate: Double?
    public let demuxCorrupted: Int?
    public let demuxDiscontinuity: Int?
    public let decodedVideo: Int?
    public let decodedAudio: Int?
    public let displayedPictures: Int?
    public let lostPictures: Int?
    public let playedAudioBuffers: Int?
    public let lostAudioBuffers: Int?
    public let readBytes: Int?
    public let demuxReadBytes: Int?
    
    /// 지연 렌더링된 프레임 수
    public let latePictures: Int?
    
    public init(from vlcMetrics: VLCLiveMetrics) {
        self.inputBitrate = vlcMetrics.inputBitrateKbps.safeForJSON
        self.demuxBitrate = vlcMetrics.demuxBitrateKbps.safeForJSON
        self.demuxCorrupted = vlcMetrics.demuxCorruptedDelta
        self.demuxDiscontinuity = vlcMetrics.demuxDiscontinuityDelta
        self.decodedVideo = vlcMetrics.decodedFramesDelta
        self.decodedAudio = vlcMetrics.decodedAudioDelta
        self.latePictures = vlcMetrics.latePicturesDelta
        self.displayedPictures = vlcMetrics.displayedPicturesDelta
        self.lostPictures = vlcMetrics.droppedFramesDelta
        self.playedAudioBuffers = vlcMetrics.playedAudioBuffersDelta
        self.lostAudioBuffers = vlcMetrics.lostAudioBuffersDelta
        self.readBytes = vlcMetrics.readBytesDelta
        self.demuxReadBytes = vlcMetrics.demuxReadBytesDelta
    }
}

/// POST /api/cview/heartbeat 응답 (양방향 — 서버→앱 동기화 데이터)
public struct CViewHeartbeatResponse: Codable, Sendable {
    public let success: Bool
    public let syncData: CViewSyncData?
    public let channelStats: CViewChannelStatsData?
    public let recommendation: CViewSyncRecommendation?
    public let serverTime: Int?
}

// MARK: - CView Sync Data

/// 동기화 데이터 (서버→앱)
public struct CViewSyncData: Codable, Sendable {
    public let webPosition: CViewPositionData?
    public let appPosition: CViewPositionData?
    public let webLatency: Double?
    public let appLatency: Double?
    public let latencyDelta: Double?
    public let timestamp: Int?
}

/// 위치 데이터 (웹 또는 앱)
public struct CViewPositionData: Codable, Sendable {
    public let timestamp: Int?
    public let channelId: String?
    public let channelName: String?
    public let currentTime: Double?
    public let bufferHealth: Double?
    public let latency: Double?
    public let resolution: String?
    public let bitrate: Double?
    public let fps: Double?
    public let engine: String?
}

/// 동기화 추천 (서버→앱) — 정밀 5단계 분석
public struct CViewSyncRecommendation: Codable, Sendable {
    public let action: String?          // hold, speed_up, slow_down, waiting
    public let suggestedSpeed: Double?
    public let reason: String?
    public let delta: Double?
    // 정밀 집계 필드
    public let avgDelta: Double?
    public let weightedDelta: Double?
    public let confidence: Double?
    public let tier: String?            // excellent, good, adjust, drift, critical
    public let trend: String?           // stable, worsening, improving
    public let samples: CViewSyncSamples?
}

/// 동기화 추천 샘플 카운트
public struct CViewSyncSamples: Codable, Sendable {
    public let web: Int?
    public let app: Int?
}

// MARK: - CView Channel Stats

/// CView 채널 통합 통계 (서버 응답)
public struct CViewChannelStatsData: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let web: LatencyStats?
    public let app: LatencyStats?
    public let delta: DeltaStats?
    public let broadcast: BroadcastStats?
    public let resolution: String?
    public let bitrate: Double?
    public let fps: Double?
}

/// GET /api/cview/channel-stats/{channelId} 응답
public struct CViewChannelStatsResponse: Codable, Sendable {
    public let success: Bool
    public let channelStats: CViewChannelStatsData?
    public let syncData: CViewSyncData?
    public let serverTime: Int?
}

/// GET /api/cview/sync-status/{channelId} 응답
public struct CViewSyncStatusResponse: Codable, Sendable {
    public let success: Bool
    public let channelId: String?
    public let syncData: CViewSyncData?
    public let recommendation: CViewSyncRecommendation?
    public let hybridSync: CViewHybridSyncInfo?
    public let cviewClients: Int?
    public let serverTime: Int?
}

/// 하이브리드 동기화 정보
public struct CViewHybridSyncInfo: Codable, Sendable {
    public let active: Bool?
    public let vlcClients: Int?
    public let webClients: Int?
    public let lastVlcPDT: Double?
    public let lastWebPDT: Double?
}

// MARK: - Hybrid Heartbeat

/// POST /api/sync/hybrid-heartbeat 요청
public struct HybridHeartbeatPayload: Codable, Sendable {
    public let channelId: String
    public let clientId: String
    public let clientType: String
    public let engine: String
    public let vlcPosition: Double?
    public let pdtTimestamp: Double?
    public let localTimestamp: Int?
    public let latencyMs: Double?
    
    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case clientId = "client_id"
        case clientType = "client_type"
        case engine
        case vlcPosition = "vlc_position"
        case pdtTimestamp = "pdt_timestamp"
        case localTimestamp = "local_timestamp"
        case latencyMs = "latency_ms"
    }
    
    public init(
        channelId: String,
        clientId: String,
        clientType: String = "vlc",
        engine: String = "VLC",
        vlcPosition: Double? = nil,
        pdtTimestamp: Double? = nil,
        localTimestamp: Int? = nil,
        latencyMs: Double? = nil
    ) {
        self.channelId = channelId
        self.clientId = clientId
        self.clientType = clientType
        self.engine = engine
        self.vlcPosition = vlcPosition
        self.pdtTimestamp = pdtTimestamp
        self.localTimestamp = localTimestamp ?? Int(Date().timeIntervalSince1970 * 1000)
        self.latencyMs = latencyMs
    }
}

/// POST /api/sync/hybrid-heartbeat 응답
public struct HybridHeartbeatResponse: Codable, Sendable {
    public let success: Bool
    public let mode: String?
    public let adjustment: Double?
    public let syncQuality: Int?
    public let targetLatency: Double?
    public let currentLatency: Double?
    public let targetPdtMs: Double?
    public let currentPdtMs: Double?
    public let clientCount: Int?
    public let engine: String?
    public let timestamp: Int?
    public let reason: String?
}

// MARK: - CView Active Channel

/// CView 활성 채널 정보 (서버 응답)
public struct CViewActiveChannel: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let webLatency: Double?
    public let appLatency: Double?
    public let isLive: Bool?
    public let concurrentUsers: Int?
}

// MARK: - CView Chat Relay

/// POST /api/cview/chat-relay 요청
public struct CViewChatRelayPayload: Codable, Sendable {
    public let clientId: String
    public let channelId: String
    public let channelName: String
    public let message: String
    public let nickname: String
    public let uid: String?
    public let badges: [String]?
    public let timestamp: Int?
    
    public init(
        clientId: String,
        channelId: String,
        channelName: String,
        message: String,
        nickname: String,
        uid: String? = nil,
        badges: [String]? = nil,
        timestamp: Int? = nil
    ) {
        self.clientId = clientId
        self.channelId = channelId
        self.channelName = channelName
        self.message = message
        self.nickname = nickname
        self.uid = uid
        self.badges = badges
        self.timestamp = timestamp ?? Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// POST /api/cview/chat-relay 응답
public struct CViewChatRelayResponse: Codable, Sendable {
    public let success: Bool
    public let message: String?
}

// MARK: - CView Stats Summary (/api/stats 에 포함)

/// `/api/stats` 응답의 cviewSummary 필드 — 정밀 집계
public struct CViewStatsSummary: Codable, Sendable {
    public let connectedClients: Int?
    public let clients: [CViewStatsSummaryClient]?
    public let syncChannels: [CViewStatsSyncChannel]?
    public let aggregate: CViewAggregate?
}

/// CView 전체 통계 집계
public struct CViewAggregate: Codable, Sendable {
    public let avgDeltaAbs: Double?
    public let syncRate: Double?
    public let syncedChannels: Int?
    public let totalSyncChannels: Int?
    public let waitingChannels: Int?
    public let qualityGrade: String?   // S, A, B, C, D, -
}

/// CView 요약 – 개별 클라이언트 정보
public struct CViewStatsSummaryClient: Codable, Sendable, Identifiable {
    public var id: String { clientId }
    public let clientId: String
    public let appVersion: String?
    public let engine: String?
    public let channelId: String?
    public let channelName: String?
    public let latency: CViewClientLatency?
}

/// 클라이언트별 레이턴시 정보
public struct CViewClientLatency: Codable, Sendable {
    public let last: Double?
    public let avg: Double?
    public let samples: Int?
}

/// CView 요약 – 채널별 동기화 정보
public struct CViewStatsSyncChannel: Codable, Sendable, Identifiable {
    public var id: String { channelId ?? UUID().uuidString }
    public let channelId: String?
    public let channelName: String?
    public let recommendation: CViewSyncRecommendation?
    public let syncData: CViewSyncData?
    public let latencyDetail: CViewLatencyDetail?
}

/// 채널별 레이턴시 상세
public struct CViewLatencyDetail: Codable, Sendable {
    public let webAvg: Double?
    public let webLast: Double?
    public let webSamples: Int?
    public let appAvg: Double?
    public let appLast: Double?
    public let appSamples: Int?
}
