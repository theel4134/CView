// MARK: - MetricsEndpoint.swift
// 메트릭 서버(cv.dododo.app) API 엔드포인트 정의

import Foundation
import CViewCore

/// 메트릭 서버 엔드포인트
public enum MetricsEndpoint: EndpointProtocol, Sendable {
    
    // MARK: - Stats / Health
    case stats
    case health
    
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
    
    // MARK: - POST
    case postAppLatency(AppLatencyPayload)
    case postPDTSync(PDTSyncPayload)
    case activateChannel(ChannelActivatePayload)
    case deactivateChannel(channelId: String)
    case pingChannel(channelId: String)
    
    // MARK: - EndpointProtocol
    
    public var path: String {
        switch self {
        case .stats:
            "/stats"
        case .health:
            "/health"
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
            "/api/app/channels/active"
        case .activeWebLatency:
            "/api/web-latency/active"
        case .postAppLatency:
            "/api/app-latency"
        case .postPDTSync:
            "/api/pdt-sync"
        case .activateChannel:
            "/api/app/channel/activate"
        case .deactivateChannel:
            "/api/app/channel/deactivate"
        case .pingChannel:
            "/api/app/channel/ping"
        }
    }
    
    public var method: HTTPMethod {
        switch self {
        case .postAppLatency, .postPDTSync, .activateChannel, .deactivateChannel, .pingChannel:
            .post
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
        default:
            return nil
        }
    }
    
    public var body: Data? {
        switch self {
        case .postAppLatency(let payload):
            try? JSONEncoder().encode(payload)
        case .postPDTSync(let payload):
            try? JSONEncoder().encode(payload)
        case .activateChannel(let payload):
            try? JSONEncoder().encode(payload)
        case .deactivateChannel(let channelId):
            try? JSONEncoder().encode(["channelId": channelId])
        case .pingChannel(let channelId):
            try? JSONEncoder().encode(["channelId": channelId])
        default:
            nil
        }
    }
    
    public var requiresAuth: Bool { false }
    
    public var cachePolicy: CachePolicy {
        switch self {
        case .stats:
            .returnCacheElseLoad(ttl: 10)
        case .health:
            .reloadIgnoringCache
        case .channelStats, .channelRealLatency, .channelWebLatency, .channelAppLatency:
            .returnCacheElseLoad(ttl: 5)
        case .channelSyncRecommendation, .channelPDTSync, .channelWebPlayerInfo:
            .returnCacheElseLoad(ttl: 5)
        case .activeAppChannels, .activeWebLatency:
            .returnCacheElseLoad(ttl: 10)
        default:
            .reloadIgnoringCache
        }
    }
}
