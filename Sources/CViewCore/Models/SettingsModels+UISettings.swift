// MARK: - SettingsModels+UISettings.swift
// CViewCore — 키보드 단축키 + 알림 + 메트릭 + 멀티라이브 설정

import Foundation

// MARK: - Keyboard Shortcut Settings

/// 단축키 액션 정의
public enum ShortcutAction: String, Codable, Sendable, CaseIterable, Hashable {
    case togglePlay
    case toggleMute
    case toggleFullscreen
    case toggleChat
    case togglePiP
    case screenshot
    case volumeUp
    case volumeDown

    public var displayName: String {
        switch self {
        case .togglePlay:       "재생/일시정지"
        case .toggleMute:       "음소거 전환"
        case .toggleFullscreen: "전체화면 전환"
        case .toggleChat:       "채팅 표시/숨기기"
        case .togglePiP:        "PiP 전환"
        case .screenshot:       "스크린샷"
        case .volumeUp:         "볼륨 올리기"
        case .volumeDown:       "볼륨 내리기"
        }
    }

    public var icon: String {
        switch self {
        case .togglePlay:       "play.fill"
        case .toggleMute:       "speaker.slash.fill"
        case .toggleFullscreen: "arrow.up.left.and.arrow.down.right"
        case .toggleChat:       "bubble.left.and.bubble.right"
        case .togglePiP:        "pip"
        case .screenshot:       "camera.fill"
        case .volumeUp:         "speaker.wave.3.fill"
        case .volumeDown:       "speaker.wave.1.fill"
        }
    }
}

/// 단축키 수식 키 조합
public struct ShortcutModifiers: OptionSet, Codable, Sendable, Equatable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command  = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift    = ShortcutModifiers(rawValue: 1 << 1)
    public static let option   = ShortcutModifiers(rawValue: 1 << 2)
    public static let control  = ShortcutModifiers(rawValue: 1 << 3)

    public var displaySymbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// 키 바인딩 (키 + 수식키)
public struct KeyBinding: Codable, Sendable, Equatable, Hashable {
    public var key: String
    public var modifiers: ShortcutModifiers

    public init(key: String, modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public var keyDisplayName: String {
        switch key {
        case "space":      "Space"
        case "upArrow":    "↑"
        case "downArrow":  "↓"
        case "leftArrow":  "←"
        case "rightArrow": "→"
        case "return":     "⏎"
        case "escape":     "Esc"
        case "tab":        "⇥"
        case "delete":     "⌫"
        default:           key.uppercased()
        }
    }

    public var displayName: String {
        modifiers.displaySymbols + keyDisplayName
    }
}

/// 키보드 단축키 설정
public struct KeyboardShortcutSettings: Codable, Sendable, Equatable {
    public var bindings: [ShortcutAction: KeyBinding]

    public init(bindings: [ShortcutAction: KeyBinding]? = nil) {
        self.bindings = bindings ?? Self.defaultBindings
    }

    public static let defaultBindings: [ShortcutAction: KeyBinding] = [
        .togglePlay:       KeyBinding(key: "space"),
        .toggleMute:       KeyBinding(key: "m"),
        .toggleFullscreen: KeyBinding(key: "f"),
        .toggleChat:       KeyBinding(key: "c"),
        .togglePiP:        KeyBinding(key: "p"),
        .screenshot:       KeyBinding(key: "s", modifiers: .command),
        .volumeUp:         KeyBinding(key: "upArrow"),
        .volumeDown:       KeyBinding(key: "downArrow"),
    ]

    public func binding(for action: ShortcutAction) -> KeyBinding {
        bindings[action] ?? Self.defaultBindings[action] ?? KeyBinding(key: "")
    }

    public static let `default` = KeyboardShortcutSettings()
}

// MARK: - Channel Notification Setting

/// 채널별 알림 세분 설정
public struct ChannelNotificationSetting: Codable, Sendable, Equatable, Identifiable {
    public let channelId: String
    public var channelName: String
    public var notifyOnLive: Bool
    public var notifyOnCategoryChange: Bool
    public var notifyOnTitleChange: Bool

    public var id: String { channelId }

    public var isAllDisabled: Bool {
        !notifyOnLive && !notifyOnCategoryChange && !notifyOnTitleChange
    }

    public init(
        channelId: String,
        channelName: String,
        notifyOnLive: Bool = true,
        notifyOnCategoryChange: Bool = true,
        notifyOnTitleChange: Bool = true
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.notifyOnLive = notifyOnLive
        self.notifyOnCategoryChange = notifyOnCategoryChange
        self.notifyOnTitleChange = notifyOnTitleChange
    }

    public static func defaultSetting(channelId: String, channelName: String) -> ChannelNotificationSetting {
        ChannelNotificationSetting(channelId: channelId, channelName: channelName)
    }
}

/// 채널별 알림 설정 저장소
public struct ChannelNotificationSettings: Codable, Sendable, Equatable {
    public var settings: [String: ChannelNotificationSetting]

    public init(settings: [String: ChannelNotificationSetting] = [:]) {
        self.settings = settings
    }

    public func setting(for channelId: String, channelName: String = "") -> ChannelNotificationSetting {
        settings[channelId] ?? .defaultSetting(channelId: channelId, channelName: channelName)
    }

    public mutating func update(_ setting: ChannelNotificationSetting) {
        settings[setting.channelId] = setting
    }

    public func isLiveNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnLive ?? true
    }

    public func isCategoryChangeNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnCategoryChange ?? true
    }

    public func isTitleChangeNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnTitleChange ?? true
    }

    public static let `default` = ChannelNotificationSettings()
}

/// 메트릭 서버 전송 설정
public struct MetricsSettings: Codable, Sendable, Equatable {
    /// 기본 서버 URL (코드 전체에서 이 상수만 참조)
    public static let defaultServerURL = "https://cv.dododo.app"
    /// 기본 WebSocket URL
    public static let defaultWebSocketURL = "wss://cv.dododo.app/ws"

    public var metricsEnabled: Bool
    public var serverURL: String
    public var forwardInterval: TimeInterval
    public var pingInterval: TimeInterval

    public init(
        metricsEnabled: Bool = false,
        serverURL: String = MetricsSettings.defaultServerURL,
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

// MARK: - MultiLive Layout Mode

public enum MultiLiveLayoutMode: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    case preset = "preset"
    case focus = "focus"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .preset: "균등 분할"
        case .focus:  "포커스 모드"
        }
    }
}

/// 멀티라이브 설정
public struct MultiLiveSettings: Codable, Sendable, Equatable {
    public var maxConcurrentSessions: Int
    public var preferredEngine: PlayerEngineType
    public var defaultLayoutMode: MultiLiveLayoutMode
    public var multiAudioEnabled: Bool
    public var secondaryVolume: Float
    public var backgroundQualityReduction: Bool
    public var autoReconnect: Bool
    public var autoReconnectMaxRetries: Int
    public var chatOverlayInGrid: Bool
    public var chatOverlayOpacity: Double
    public var chatOverlayFontSize: Double

    // MARK: - 대역폭 코디네이터 (flashls 기반)
    /// 대역폭 코디네이터가 세션 간 대역폭을 자동 분배
    public var bandwidthCoordinationEnabled: Bool
    /// 화면 크기 기반 자동 화질 캡핑 (패인보다 높은 해상도 방지)
    public var levelCappingEnabled: Bool
    /// 선택 세션에 할당하는 대역폭 가중치 (1.0=균등, 2.0=2배)
    public var selectedSessionBWWeight: Double

    public init(
        maxConcurrentSessions: Int = 4,
        preferredEngine: PlayerEngineType = .vlc,
        defaultLayoutMode: MultiLiveLayoutMode = .preset,
        multiAudioEnabled: Bool = false,
        secondaryVolume: Float = 0.3,
        backgroundQualityReduction: Bool = true,
        autoReconnect: Bool = true,
        autoReconnectMaxRetries: Int = 10,
        chatOverlayInGrid: Bool = false,
        chatOverlayOpacity: Double = 0.5,
        chatOverlayFontSize: Double = 12,
        bandwidthCoordinationEnabled: Bool = true,
        levelCappingEnabled: Bool = true,
        selectedSessionBWWeight: Double = 1.5
    ) {
        self.maxConcurrentSessions = maxConcurrentSessions
        self.preferredEngine = preferredEngine
        self.defaultLayoutMode = defaultLayoutMode
        self.multiAudioEnabled = multiAudioEnabled
        self.secondaryVolume = secondaryVolume
        self.backgroundQualityReduction = backgroundQualityReduction
        self.autoReconnect = autoReconnect
        self.autoReconnectMaxRetries = autoReconnectMaxRetries
        self.chatOverlayInGrid = chatOverlayInGrid
        self.chatOverlayOpacity = chatOverlayOpacity
        self.chatOverlayFontSize = chatOverlayFontSize
        self.bandwidthCoordinationEnabled = bandwidthCoordinationEnabled
        self.levelCappingEnabled = levelCappingEnabled
        self.selectedSessionBWWeight = selectedSessionBWWeight
    }

    public static let `default` = MultiLiveSettings()
}

// MARK: - 멀티채팅 세션 영속성

/// 저장용 멀티채팅 세션 정보
public struct SavedChatSession: Codable, Sendable, Equatable, Hashable {
    public let channelId: String
    public let channelName: String

    public init(channelId: String, channelName: String) {
        self.channelId = channelId
        self.channelName = channelName
    }
}

/// 멀티채팅 세션 설정 (영속 저장용)
public struct MultiChatSettings: Codable, Sendable, Equatable {
    public var savedSessions: [SavedChatSession]
    public var selectedChannelId: String?

    public init(
        savedSessions: [SavedChatSession] = [],
        selectedChannelId: String? = nil
    ) {
        self.savedSessions = savedSessions
        self.selectedChannelId = selectedChannelId
    }

    public static let `default` = MultiChatSettings()
}
