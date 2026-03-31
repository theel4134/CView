// MARK: - MetricsEndpoint.swift
// 메트릭 서버(cv.dododo.app) API 엔드포인트 정의

import Foundation
import CViewCore

/// 메트릭 서버 엔드포인트
public enum MetricsEndpoint: EndpointProtocol, Sendable {
    
    // MARK: - Stats / Health
    case stats
    case health
    
    // MARK: - Dashboard Stats (v4.5+)
    case statsOverview
    case statsSystem
    case statsCategories
    case statsChannelRanking(sort: String, limit: Int)
    
    // MARK: - Channel
    case channelStats(channelId: String)
    case channelRealLatency(channelId: String)
    case channelWebLatency(channelId: String)
    case channelAppLatency(channelId: String)
    case channelSyncRecommendation(channelId: String, appLatency: Double?)
    case channelPDTSync(channelId: String)
    case channelWebPlayerInfo(channelId: String)
    
    // MARK: - Active Channels
    case activeAppChannels
    case activeWebLatency
    
    // MARK: - POST / Channel Management
    case postAppLatency(AppLatencyPayload)
    case postMetrics(AppLatencyPayload)
    case postPDTSync(PDTSyncPayload)
    case addChannel(ChannelActivatePayload)
    case removeChannel(channelId: String)
    case channelCleanup
    case pingChannel(channelId: String)
    
    // MARK: - CView App Integration
    case cviewConnect(CViewConnectPayload)
    case cviewDisconnect(CViewDisconnectPayload)
    case cviewHeartbeat(CViewHeartbeatPayload)
    case cviewChannelStats(channelId: String)
    case cviewChatRelay(CViewChatRelayPayload)
    case cviewSyncStatus(channelId: String)
    
    // MARK: - Hybrid Sync
    case hybridHeartbeat(HybridHeartbeatPayload)
    
    // MARK: - Auth Cookie Sync
    case syncAuthCookies(AuthCookieSyncPayload)
    
    // MARK: - EndpointProtocol
    
    public var path: String {
        switch self {
        case .stats:
            "/api/stats"
        case .health:
            "/health"
        case .statsOverview:
            "/api/stats/overview"
        case .statsSystem:
            "/api/stats/system"
        case .statsCategories:
            "/api/stats/categories"
        case .statsChannelRanking:
            "/api/stats/channels/ranking"
        case .channelStats(let id):
            "/api/channel/\(id)/stats"
        case .channelRealLatency(let id):
            "/api/channel/\(id)/real-latency"
        case .channelWebLatency(let id):
            "/api/channel/\(id)/web-latency"
        case .channelAppLatency(let id):
            "/api/channel/\(id)/app-latency"
        case .channelSyncRecommendation(let id, _):
            "/api/channel/\(id)/sync-recommendation"
        case .channelPDTSync(let id):
            "/api/channel/\(id)/pdt-sync"
        case .channelWebPlayerInfo(let id):
            "/api/channel/\(id)/web-player-info"
        case .activeAppChannels:
            "/api/channels"
        case .activeWebLatency:
            "/api/web-latency/active"
        case .postAppLatency:
            "/api/app-latency"
        case .postMetrics:
            "/api/metrics"
        case .postPDTSync:
            "/api/pdt-sync"
        case .addChannel:
            "/api/channels"
        case .removeChannel(let channelId):
            "/api/channels/\(channelId)"
        case .channelCleanup:
            "/api/channels/cleanup"
        case .pingChannel:
            "/api/metrics/app"
        case .cviewConnect:
            "/api/cview/connect"
        case .cviewDisconnect:
            "/api/cview/disconnect"
        case .cviewHeartbeat:
            "/api/cview/heartbeat"
        case .cviewChannelStats(let id):
            "/api/cview/channel-stats/\(id)"
        case .cviewChatRelay:
            "/api/cview/chat-relay"
        case .cviewSyncStatus(let id):
            "/api/cview/sync-status/\(id)"
        case .hybridHeartbeat:
            "/api/sync/hybrid-heartbeat"
        case .syncAuthCookies:
            "/api/auth/cookies"
        }
    }
    
    public var method: HTTPMethod {
        switch self {
        case .postAppLatency, .postMetrics, .postPDTSync, .addChannel, .channelCleanup, .pingChannel,
             .cviewConnect, .cviewDisconnect, .cviewHeartbeat, .cviewChatRelay,
             .hybridHeartbeat, .syncAuthCookies:
            .post
        case .removeChannel:
            .delete
        default:
            .get
        }
    }
    
    public var queryItems: [URLQueryItem]? {
        switch self {
        case .channelSyncRecommendation(_, let appLatency):
            if let lat = appLatency {
                return [URLQueryItem(name: "appLatency", value: "\(Int(lat))")]
            }
            return nil
        case .statsChannelRanking(let sort, let limit):
            return [URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "limit", value: "\(limit)")]
        default:
            return nil
        }
    }
    
    /// NaN/Infinity 안전한 JSON 인코더
    private static let safeEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }()

    public var body: Data? {
        switch self {
        case .postAppLatency(let payload):
            try? Self.safeEncoder.encode(payload)
        case .postMetrics(let payload):
            try? Self.safeEncoder.encode(payload)
        case .postPDTSync(let payload):
            try? Self.safeEncoder.encode(payload)
        case .addChannel(let payload):
            try? Self.safeEncoder.encode(payload)
        case .removeChannel:
            nil
        case .channelCleanup:
            nil
        case .pingChannel(let channelId):
            try? Self.safeEncoder.encode(["channelId": channelId, "source": "VLC", "platform": "app"])
        case .cviewConnect(let payload):
            try? Self.safeEncoder.encode(payload)
        case .cviewDisconnect(let payload):
            try? Self.safeEncoder.encode(payload)
        case .cviewHeartbeat(let payload):
            try? Self.safeEncoder.encode(payload)
        case .cviewChatRelay(let payload):
            try? Self.safeEncoder.encode(payload)
        case .hybridHeartbeat(let payload):
            try? Self.safeEncoder.encode(payload)
        case .syncAuthCookies(let payload):
            try? Self.safeEncoder.encode(payload)
        default:
            nil
        }
    }
    
    public var requiresAuth: Bool {
        switch method {
        case .post, .put, .delete:
            true
        case .get:
            false
        }
    }
    
    public var cachePolicy: CachePolicy {
        switch self {
        case .stats, .statsOverview:
            .returnCacheElseLoad(ttl: 10)
        case .health:
            .reloadIgnoringCache
        case .statsSystem, .statsCategories, .statsChannelRanking:
            .returnCacheElseLoad(ttl: 10)
        case .channelStats, .channelRealLatency, .channelWebLatency, .channelAppLatency:
            .returnCacheElseLoad(ttl: 5)
        case .channelSyncRecommendation, .channelPDTSync, .channelWebPlayerInfo:
            .returnCacheElseLoad(ttl: 5)
        case .activeAppChannels, .activeWebLatency:
            .returnCacheElseLoad(ttl: 10)
        case .cviewChannelStats:
            .returnCacheElseLoad(ttl: 5)
        case .cviewSyncStatus:
            .returnCacheElseLoad(ttl: 3)
        default:
            .reloadIgnoringCache
        }
    }
}
