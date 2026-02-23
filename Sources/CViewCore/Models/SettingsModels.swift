// MARK: - CViewCore/Models/SettingsModels.swift
// 설정 도메인 모델 — 카테고리별 분리

import Foundation

/// 플레이어 설정
public struct PlayerSettings: Codable, Sendable, Equatable {
    public var quality: StreamQuality
    public var preferredEngine: PlayerEngineType
    public var lowLatencyMode: Bool
    public var catchupRate: Double
    public var bufferDuration: TimeInterval
    public var volumeLevel: Float
    public var autoPlay: Bool

    public init(
        quality: StreamQuality = .auto,
        preferredEngine: PlayerEngineType = .vlc,
        lowLatencyMode: Bool = true,
        catchupRate: Double = 1.05,
        bufferDuration: TimeInterval = 2.0,
        volumeLevel: Float = 1.0,
        autoPlay: Bool = true
    ) {
        self.quality = quality
        self.preferredEngine = preferredEngine
        self.lowLatencyMode = lowLatencyMode
        self.catchupRate = catchupRate
        self.bufferDuration = bufferDuration
        self.volumeLevel = volumeLevel
        self.autoPlay = autoPlay
    }

    public static let `default` = PlayerSettings()
}

/// 채팅 설정
public struct ChatSettings: Codable, Sendable, Equatable {
    public var fontSize: CGFloat
    public var chatOpacity: Double
    public var lineSpacing: CGFloat
    public var showTimestamp: Bool
    public var showBadge: Bool
    public var highlightMentions: Bool
    public var maxVisibleMessages: Int
    public var emoticonEnabled: Bool
    public var showDonation: Bool
    public var showDonationsOnly: Bool
    public var autoScroll: Bool
    public var chatFilterEnabled: Bool
    public var blockedWords: [String]
    public var blockedUsers: [String]

    public init(
        fontSize: CGFloat = 14,
        chatOpacity: Double = 1.0,
        lineSpacing: CGFloat = 2.0,
        showTimestamp: Bool = true,
        showBadge: Bool = true,
        highlightMentions: Bool = true,
        maxVisibleMessages: Int = 1000,
        emoticonEnabled: Bool = true,
        showDonation: Bool = true,
        showDonationsOnly: Bool = false,
        autoScroll: Bool = true,
        chatFilterEnabled: Bool = false,
        blockedWords: [String] = [],
        blockedUsers: [String] = []
    ) {
        self.fontSize = fontSize
        self.chatOpacity = chatOpacity
        self.lineSpacing = lineSpacing
        self.showTimestamp = showTimestamp
        self.showBadge = showBadge
        self.highlightMentions = highlightMentions
        self.maxVisibleMessages = maxVisibleMessages
        self.emoticonEnabled = emoticonEnabled
        self.showDonation = showDonation
        self.showDonationsOnly = showDonationsOnly
        self.autoScroll = autoScroll
        self.chatFilterEnabled = chatFilterEnabled
        self.blockedWords = blockedWords
        self.blockedUsers = blockedUsers
    }

    public static let `default` = ChatSettings()
}

/// 일반 설정
public struct GeneralSettings: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var showInMenuBar: Bool
    public var notificationsEnabled: Bool
    public var autoRefreshInterval: TimeInterval

    public init(
        launchAtLogin: Bool = false,
        showInMenuBar: Bool = true,
        notificationsEnabled: Bool = true,
        autoRefreshInterval: TimeInterval = 60
    ) {
        self.launchAtLogin = launchAtLogin
        self.showInMenuBar = showInMenuBar
        self.notificationsEnabled = notificationsEnabled
        self.autoRefreshInterval = autoRefreshInterval
    }

    public static let `default` = GeneralSettings()
}

/// 외관 설정
public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var theme: AppTheme
    public var sidebarWidth: CGFloat
    public var compactMode: Bool
    public var hardwareDecoding: Bool
    public var maxMemoryMB: Int

    public init(
        theme: AppTheme = .system,
        sidebarWidth: CGFloat = 250,
        compactMode: Bool = false,
        hardwareDecoding: Bool = true,
        maxMemoryMB: Int = 512
    ) {
        self.theme = theme
        self.sidebarWidth = sidebarWidth
        self.compactMode = compactMode
        self.hardwareDecoding = hardwareDecoding
        self.maxMemoryMB = maxMemoryMB
    }

    public static let `default` = AppearanceSettings()
}

/// 네트워크 설정
public struct NetworkSettings: Codable, Sendable, Equatable {
    public var requestRateLimit: Int
    public var cacheExpiry: Int
    public var retryCount: Int
    public var maxReconnectAttempts: Int
    public var autoReconnect: Bool

    public init(
        requestRateLimit: Int = 10,
        cacheExpiry: Int = 300,
        retryCount: Int = 3,
        maxReconnectAttempts: Int = 10,
        autoReconnect: Bool = true
    ) {
        self.requestRateLimit = requestRateLimit
        self.cacheExpiry = cacheExpiry
        self.retryCount = retryCount
        self.maxReconnectAttempts = maxReconnectAttempts
        self.autoReconnect = autoReconnect
    }

    public static let `default` = NetworkSettings()
}

/// 앱 테마
public enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "시스템"
        case .light: "라이트"
        case .dark: "다크"
        }
    }
}

/// 메트릭 서버 전송 설정
public struct MetricsSettings: Codable, Sendable, Equatable {
    /// 메트릭 서버로 라이브 재생 데이터를 전송할지 여부
    public var metricsEnabled: Bool
    /// 메트릭 서버 URL (기본: https://cv.dododo.app)
    public var serverURL: String
    /// 레이턴시 데이터 전송 주기 (초)
    public var forwardInterval: TimeInterval
    /// Keep-alive 핑 전송 주기 (초)
    public var pingInterval: TimeInterval

    public init(
        metricsEnabled: Bool = false,
        serverURL: String = "https://cv.dododo.app",
        forwardInterval: TimeInterval = 5.0,
        pingInterval: TimeInterval = 30.0
    ) {
        self.metricsEnabled = metricsEnabled
        self.serverURL = serverURL
        self.forwardInterval = forwardInterval
        self.pingInterval = pingInterval
    }

    public static let `default` = MetricsSettings()
}
