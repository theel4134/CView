// MARK: - MetricsModels.swift
// 메트릭 서버(cv.dododo.app) API 응답/요청 모델
// v4.0.3 서버 호환 + v3.0.0 하위 호환

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

/// 서버 v4.5+ overview 응답: {"data": {...}, "status": "ok"}
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

// MARK: - CView App Integration Models

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
        latePictures: Int? = nil
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

/// CView 활성 채널 정보 (서버 응답)
public struct CViewActiveChannel: Codable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let webLatency: Double?
    public let appLatency: Double?
    public let isLive: Bool?
    public let concurrentUsers: Int?
}

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
