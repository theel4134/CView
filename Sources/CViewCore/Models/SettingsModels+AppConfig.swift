// MARK: - SettingsModels+AppConfig.swift
// CViewCore — 일반/외관/네트워크 설정 + 프리셋 + 앱 테마

import Foundation

/// 일반 설정
public struct GeneralSettings: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var showInMenuBar: Bool
    public var notificationsEnabled: Bool
    public var autoRefreshInterval: TimeInterval
    public var autoRefreshEnabled: Bool
    public var alwaysOnTop: Bool
    public var restoreWindowOnLaunch: Bool

    public init(
        launchAtLogin: Bool = false,
        showInMenuBar: Bool = true,
        notificationsEnabled: Bool = true,
        autoRefreshInterval: TimeInterval = 60,
        autoRefreshEnabled: Bool = true,
        alwaysOnTop: Bool = false,
        restoreWindowOnLaunch: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.showInMenuBar = showInMenuBar
        self.notificationsEnabled = notificationsEnabled
        self.autoRefreshInterval = autoRefreshInterval
        self.autoRefreshEnabled = autoRefreshEnabled
        self.alwaysOnTop = alwaysOnTop
        self.restoreWindowOnLaunch = restoreWindowOnLaunch
    }

    // Codable: 구 버전 저장본에 autoRefreshEnabled가 없어도 true 기본값으로 디코딩
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, showInMenuBar, notificationsEnabled
        case autoRefreshInterval, autoRefreshEnabled
        case alwaysOnTop, restoreWindowOnLaunch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        self.notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        self.autoRefreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .autoRefreshInterval) ?? 60
        self.autoRefreshEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? true
        self.alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        self.restoreWindowOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .restoreWindowOnLaunch) ?? true
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
    public var debugMode: Bool

    public init(
        theme: AppTheme = .dark,
        sidebarWidth: CGFloat = 250,
        compactMode: Bool = false,
        hardwareDecoding: Bool = true,
        maxMemoryMB: Int = 512,
        debugMode: Bool = false
    ) {
        self.theme = theme
        self.sidebarWidth = sidebarWidth
        self.compactMode = compactMode
        self.hardwareDecoding = hardwareDecoding
        self.maxMemoryMB = maxMemoryMB
        self.debugMode = debugMode
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

    // MARK: 연결 타임아웃
    public var connectionTimeout: Int
    public var streamConnectionTimeout: Int

    // MARK: 재연결 간격
    public var reconnectBaseDelay: Double

    // MARK: 동시 연결 수
    public var maxConnectionsPerHost: Int

    // MARK: 스트림 프록시
    public var forceStreamProxy: Bool

    public init(
        requestRateLimit: Int = 10,
        cacheExpiry: Int = 300,
        retryCount: Int = 3,
        maxReconnectAttempts: Int = 10,
        autoReconnect: Bool = true,
        connectionTimeout: Int = 15,
        streamConnectionTimeout: Int = 10,
        reconnectBaseDelay: Double = 1.0,
        maxConnectionsPerHost: Int = 6,
        forceStreamProxy: Bool = true
    ) {
        self.requestRateLimit = requestRateLimit
        self.cacheExpiry = cacheExpiry
        self.retryCount = retryCount
        self.maxReconnectAttempts = maxReconnectAttempts
        self.autoReconnect = autoReconnect
        self.connectionTimeout = connectionTimeout
        self.streamConnectionTimeout = streamConnectionTimeout
        self.reconnectBaseDelay = reconnectBaseDelay
        self.maxConnectionsPerHost = maxConnectionsPerHost
        self.forceStreamProxy = forceStreamProxy
    }

    public static let `default` = NetworkSettings()

    /// 프리셋에 정의된 값과 현재 값이 같은지 비교하여 프리셋 자동 감지
    public func matchingPreset() -> NetworkPreset {
        for preset in NetworkPreset.allCases where preset != .custom {
            if self == preset.settings { return preset }
        }
        return .custom
    }
}

// MARK: - 네트워크 프리셋

public enum NetworkPreset: String, Codable, Sendable, CaseIterable {
    case balanced
    case stability
    case lowLatency
    case performance
    case custom

    public var displayName: String {
        switch self {
        case .balanced:    return "밸런스"
        case .stability:   return "안정 우선"
        case .lowLatency:  return "저지연 우선"
        case .performance: return "고성능"
        case .custom:      return "커스텀"
        }
    }

    public var description: String {
        switch self {
        case .balanced:    return "일반 시청에 적합한 기본 설정"
        case .stability:   return "느린 네트워크에서도 끊김 없는 안정적인 연결"
        case .lowLatency:  return "빠른 응답 우선. 불안정한 네트워크에서 끊김 가능"
        case .performance: return "멀티라이브 등 다수 동시 스트림에 최적화"
        case .custom:      return "수동으로 각 항목을 직접 조정"
        }
    }

    public var icon: String {
        switch self {
        case .balanced:    return "scale.3d"
        case .stability:   return "shield.checkered"
        case .lowLatency:  return "bolt.fill"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .custom:      return "slider.horizontal.3"
        }
    }

    public var settings: NetworkSettings {
        switch self {
        case .balanced:
            return NetworkSettings()
        case .stability:
            return NetworkSettings(
                requestRateLimit: 5, cacheExpiry: 600, retryCount: 5,
                maxReconnectAttempts: 20, autoReconnect: true,
                connectionTimeout: 30, streamConnectionTimeout: 20,
                reconnectBaseDelay: 2.0, maxConnectionsPerHost: 4, forceStreamProxy: true
            )
        case .lowLatency:
            return NetworkSettings(
                requestRateLimit: 20, cacheExpiry: 60, retryCount: 2,
                maxReconnectAttempts: 5, autoReconnect: true,
                connectionTimeout: 8, streamConnectionTimeout: 5,
                reconnectBaseDelay: 0.5, maxConnectionsPerHost: 10, forceStreamProxy: true
            )
        case .performance:
            return NetworkSettings(
                requestRateLimit: 15, cacheExpiry: 600, retryCount: 3,
                maxReconnectAttempts: 15, autoReconnect: true,
                connectionTimeout: 20, streamConnectionTimeout: 15,
                reconnectBaseDelay: 1.5, maxConnectionsPerHost: 16, forceStreamProxy: true
            )
        case .custom:
            return NetworkSettings()
        }
    }
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
