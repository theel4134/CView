// MARK: - DashboardModels.swift
// 대시보드 통계 관련 모델 (HomeViewModel에서 추출)

import Foundation

// MARK: - Viewer History Entry

public struct ViewerHistoryEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let totalViewers: Int

    public init(timestamp: Date, totalViewers: Int) {
        self.timestamp = timestamp
        self.totalViewers = totalViewers
    }
}

// MARK: - Category Stat

public struct CategoryStat: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let channelCount: Int
    public let totalViewers: Int

    public init(id: String, name: String, channelCount: Int, totalViewers: Int) {
        self.id = id
        self.name = name
        self.channelCount = channelCount
        self.totalViewers = totalViewers
    }
}

// MARK: - Category Type Stat (GAME / SPORTS / ETC)

public struct CategoryTypeStat: Identifiable, Sendable {
    public let id: String
    public let type: String
    public let displayName: String
    public let channelCount: Int
    public let totalViewers: Int
    public let percentage: Double

    public init(id: String, type: String, displayName: String, channelCount: Int, totalViewers: Int, percentage: Double) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.channelCount = channelCount
        self.totalViewers = totalViewers
        self.percentage = percentage
    }

    public static func displayName(for type: String) -> String {
        switch type {
        case "GAME":   return "게임"
        case "SPORTS": return "스포츠"
        default:       return "기타"
        }
    }
}

// MARK: - Viewer Bucket (시청자수 분포)

public struct ViewerBucket: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let count: Int
    public let minViewers: Int
    public let maxViewers: Int

    public init(id: String, label: String, count: Int, minViewers: Int, maxViewers: Int) {
        self.id = id
        self.label = label
        self.count = count
        self.minViewers = minViewers
        self.maxViewers = maxViewers
    }
}

// MARK: - Latency History Entry (메트릭 서버 데이터)

public struct LatencyHistoryEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let webLatency: Double?
    public let appLatency: Double?

    public init(timestamp: Date, webLatency: Double?, appLatency: Double?) {
        self.timestamp = timestamp
        self.webLatency = webLatency
        self.appLatency = appLatency
    }
}
