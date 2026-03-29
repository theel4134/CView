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
    /// 백그라운드 및 비활성 상태에서도 라이브 방송 재생을 유지할지 여부
    public var continuePlaybackInBackground: Bool

    // MARK: - VLC 4.0 고급 설정

    /// 이퀄라이저 프리셋 이름 (nil = 비활성화)
    public var equalizerPreset: String?
    /// 이퀄라이저 프리앰프 (dB, -20~+20)
    public var equalizerPreAmp: Float
    /// 이퀄라이저 밴드 값 (dB, -20~+20, 최대 10밴드)
    public var equalizerBands: [Float]

    /// 비디오 필터 활성화 여부
    public var videoAdjustEnabled: Bool
    /// 밝기 (0~2, 기본 1.0)
    public var videoBrightness: Float
    /// 대비 (0~2, 기본 1.0)
    public var videoContrast: Float
    /// 채도 (0~3, 기본 1.0)
    public var videoSaturation: Float
    /// 색조 (-180~180, 기본 0)
    public var videoHue: Float
    /// 감마 (0~10, 기본 1.0)
    public var videoGamma: Float

    /// 화면 비율 (nil = 기본, "16:9", "4:3", "21:9" 등)
    public var aspectRatio: String?

    /// 오디오 스테레오 모드 (0=Stereo, 1=Mono, 2=Left, 3=Right 등)
    public var audioStereoMode: Int
    /// 오디오 믹스 모드 (0=기본, 1=스테레오, 2=바이노럴, 3=4.0, 4=5.1, 5=7.1)
    public var audioMixMode: UInt32
    /// 오디오 지연 (마이크로초)
    public var audioDelay: Int64

    // MARK: - 레이턴시 동기화 설정

    /// 레이턴시 프리셋 ("webSync", "default", "ultraLow", "custom")
    public var latencyPreset: String
    /// 목표 레이턴시 (초)
    public var latencyTarget: Double
    /// 최대 허용 레이턴시 (초)
    public var latencyMax: Double
    /// 최소 허용 레이턴시 (초)
    public var latencyMin: Double
    /// 최대 재생 속도 (캐치업)
    public var latencyMaxRate: Double
    /// 최소 재생 속도 (슬로우다운)
    public var latencyMinRate: Double
    /// 캐치업 시작 임계값 (초)
    public var latencyCatchUpThreshold: Double
    /// 슬로우다운 시작 임계값 (초)
    public var latencySlowDownThreshold: Double
    /// PID Kp (비례 이득)
    public var latencyPidKp: Double
    /// PID Ki (적분 이득)
    public var latencyPidKi: Double
    /// PID Kd (미분 이득)
    public var latencyPidKd: Double

    public init(
        quality: StreamQuality = .auto,
        preferredEngine: PlayerEngineType = .avPlayer,
        lowLatencyMode: Bool = true,
        catchupRate: Double = 1.05,
        bufferDuration: TimeInterval = 2.0,
        volumeLevel: Float = 1.0,
        autoPlay: Bool = true,
        continuePlaybackInBackground: Bool = true,
        equalizerPreset: String? = nil,
        equalizerPreAmp: Float = 0,
        equalizerBands: [Float] = [],
        videoAdjustEnabled: Bool = false,
        videoBrightness: Float = 1.0,
        videoContrast: Float = 1.0,
        videoSaturation: Float = 1.0,
        videoHue: Float = 0,
        videoGamma: Float = 1.0,
        aspectRatio: String? = nil,
        audioStereoMode: Int = 0,
        audioMixMode: UInt32 = 0,
        audioDelay: Int64 = 0,
        latencyPreset: String = "webSync",
        latencyTarget: Double = 6.0,
        latencyMax: Double = 10.0,
        latencyMin: Double = 3.0,
        latencyMaxRate: Double = 1.15,
        latencyMinRate: Double = 0.90,
        latencyCatchUpThreshold: Double = 0.5,
        latencySlowDownThreshold: Double = 0.3,
        latencyPidKp: Double = 1.2,
        latencyPidKi: Double = 0.15,
        latencyPidKd: Double = 0.08
    ) {
        self.quality = quality
        self.preferredEngine = preferredEngine
        self.lowLatencyMode = lowLatencyMode
        self.catchupRate = catchupRate
        self.bufferDuration = bufferDuration
        self.volumeLevel = volumeLevel
        self.autoPlay = autoPlay
        self.continuePlaybackInBackground = continuePlaybackInBackground
        self.equalizerPreset = equalizerPreset
        self.equalizerPreAmp = equalizerPreAmp
        self.equalizerBands = equalizerBands
        self.videoAdjustEnabled = videoAdjustEnabled
        self.videoBrightness = videoBrightness
        self.videoContrast = videoContrast
        self.videoSaturation = videoSaturation
        self.videoHue = videoHue
        self.videoGamma = videoGamma
        self.aspectRatio = aspectRatio
        self.audioStereoMode = audioStereoMode
        self.audioMixMode = audioMixMode
        self.audioDelay = audioDelay
        self.latencyPreset = latencyPreset
        self.latencyTarget = latencyTarget
        self.latencyMax = latencyMax
        self.latencyMin = latencyMin
        self.latencyMaxRate = latencyMaxRate
        self.latencyMinRate = latencyMinRate
        self.latencyCatchUpThreshold = latencyCatchUpThreshold
        self.latencySlowDownThreshold = latencySlowDownThreshold
        self.latencyPidKp = latencyPidKp
        self.latencyPidKi = latencyPidKi
        self.latencyPidKd = latencyPidKd
    }

    // MARK: - Backward-compatible Decoding

    enum CodingKeys: String, CodingKey {
        case quality, preferredEngine, lowLatencyMode, catchupRate, bufferDuration, volumeLevel
        case autoPlay, continuePlaybackInBackground
        case equalizerPreset, equalizerPreAmp, equalizerBands
        case videoAdjustEnabled, videoBrightness, videoContrast, videoSaturation, videoHue, videoGamma
        case aspectRatio, audioStereoMode, audioMixMode, audioDelay
        case latencyPreset, latencyTarget, latencyMax, latencyMin
        case latencyMaxRate, latencyMinRate
        case latencyCatchUpThreshold, latencySlowDownThreshold
        case latencyPidKp, latencyPidKi, latencyPidKd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quality = try c.decode(StreamQuality.self, forKey: .quality)
        preferredEngine = try c.decode(PlayerEngineType.self, forKey: .preferredEngine)
        lowLatencyMode = try c.decode(Bool.self, forKey: .lowLatencyMode)
        catchupRate = try c.decode(Double.self, forKey: .catchupRate)
        bufferDuration = try c.decode(TimeInterval.self, forKey: .bufferDuration)
        volumeLevel = try c.decode(Float.self, forKey: .volumeLevel)
        autoPlay = try c.decode(Bool.self, forKey: .autoPlay)
        continuePlaybackInBackground = try c.decode(Bool.self, forKey: .continuePlaybackInBackground)
        equalizerPreset = try c.decodeIfPresent(String.self, forKey: .equalizerPreset)
        equalizerPreAmp = try c.decodeIfPresent(Float.self, forKey: .equalizerPreAmp) ?? 0
        equalizerBands = try c.decodeIfPresent([Float].self, forKey: .equalizerBands) ?? []
        videoAdjustEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoAdjustEnabled) ?? false
        videoBrightness = try c.decodeIfPresent(Float.self, forKey: .videoBrightness) ?? 1.0
        videoContrast = try c.decodeIfPresent(Float.self, forKey: .videoContrast) ?? 1.0
        videoSaturation = try c.decodeIfPresent(Float.self, forKey: .videoSaturation) ?? 1.0
        videoHue = try c.decodeIfPresent(Float.self, forKey: .videoHue) ?? 0
        videoGamma = try c.decodeIfPresent(Float.self, forKey: .videoGamma) ?? 1.0
        aspectRatio = try c.decodeIfPresent(String.self, forKey: .aspectRatio)
        audioStereoMode = try c.decodeIfPresent(Int.self, forKey: .audioStereoMode) ?? 0
        audioMixMode = try c.decodeIfPresent(UInt32.self, forKey: .audioMixMode) ?? 0
        audioDelay = try c.decodeIfPresent(Int64.self, forKey: .audioDelay) ?? 0
        latencyPreset = try c.decodeIfPresent(String.self, forKey: .latencyPreset) ?? "webSync"
        latencyTarget = try c.decodeIfPresent(Double.self, forKey: .latencyTarget) ?? 6.0
        latencyMax = try c.decodeIfPresent(Double.self, forKey: .latencyMax) ?? 10.0
        latencyMin = try c.decodeIfPresent(Double.self, forKey: .latencyMin) ?? 3.0
        latencyMaxRate = try c.decodeIfPresent(Double.self, forKey: .latencyMaxRate) ?? 1.15
        latencyMinRate = try c.decodeIfPresent(Double.self, forKey: .latencyMinRate) ?? 0.90
        latencyCatchUpThreshold = try c.decodeIfPresent(Double.self, forKey: .latencyCatchUpThreshold) ?? 0.5
        latencySlowDownThreshold = try c.decodeIfPresent(Double.self, forKey: .latencySlowDownThreshold) ?? 0.3
        latencyPidKp = try c.decodeIfPresent(Double.self, forKey: .latencyPidKp) ?? 1.2
        latencyPidKi = try c.decodeIfPresent(Double.self, forKey: .latencyPidKi) ?? 0.15
        latencyPidKd = try c.decodeIfPresent(Double.self, forKey: .latencyPidKd) ?? 0.08
    }

    public static let `default` = PlayerSettings()

    // MARK: - 레이턴시 프리셋

    /// 레이턴시 프리셋 정의
    public enum LatencyPreset: String, CaseIterable, Sendable {
        case webSync = "webSync"
        case standard = "default"
        case ultraLow = "ultraLow"
        case custom = "custom"

        public var displayName: String {
            switch self {
            case .webSync:   "웹 동기화"
            case .standard:  "기본"
            case .ultraLow:  "초저지연"
            case .custom:    "사용자 지정"
            }
        }

        public var icon: String {
            switch self {
            case .webSync:   "globe"
            case .standard:  "gauge.with.dots.needle.50percent"
            case .ultraLow:  "bolt.fill"
            case .custom:    "slider.horizontal.3"
            }
        }

        public var description: String {
            switch self {
            case .webSync:   "웹 브라우저와 동일한 재생 위치 (6초 지연)"
            case .standard:  "안정적인 재생 (3초 지연)"
            case .ultraLow:  "최소 지연, 끊김 가능 (1.5초 지연)"
            case .custom:    "모든 파라미터를 직접 조정"
            }
        }

        /// 프리셋 기본 값 (목표 지연, 최대, 최소, 최대속도, 최소속도, 캐치업임계, 슬로우다운임계, Kp, Ki, Kd)
        public var values: (target: Double, max: Double, min: Double, maxRate: Double, minRate: Double,
                            catchUp: Double, slowDown: Double, kp: Double, ki: Double, kd: Double) {
            switch self {
            case .webSync:   (6.0, 10.0, 3.0, 1.15, 0.90, 0.5, 0.3, 1.2, 0.15, 0.08)
            case .standard:  (3.0,  8.0, 1.0, 1.15, 0.90, 1.2, 0.5, 0.8, 0.12, 0.06)
            case .ultraLow:  (1.5,  5.0, 0.5, 1.20, 0.85, 1.0, 0.3, 1.0, 0.15, 0.08)
            case .custom:    (6.0, 10.0, 3.0, 1.15, 0.90, 0.5, 0.3, 1.2, 0.15, 0.08)
            }
        }
    }

    /// 현재 선택된 프리셋 enum
    public var currentPreset: LatencyPreset {
        get { LatencyPreset(rawValue: latencyPreset) ?? .webSync }
        set { latencyPreset = newValue.rawValue }
    }

    /// 프리셋 값을 현재 설정에 적용
    public mutating func applyLatencyPreset(_ preset: LatencyPreset) {
        latencyPreset = preset.rawValue
        guard preset != .custom else { return }
        let v = preset.values
        latencyTarget = v.target
        latencyMax = v.max
        latencyMin = v.min
        latencyMaxRate = v.maxRate
        latencyMinRate = v.minRate
        latencyCatchUpThreshold = v.catchUp
        latencySlowDownThreshold = v.slowDown
        latencyPidKp = v.kp
        latencyPidKi = v.ki
        latencyPidKd = v.kd
    }
}

/// 채팅 표시 모드
public enum ChatDisplayMode: String, Codable, Sendable, CaseIterable {
    /// 사이드 패널 (기본) — HSplitView 오른쪽 영역
    case side
    /// 비디오 오버레이 — 플레이어 위에 반투명하게 표시
    case overlay
    /// 숨김 — 채팅 UI 비표시
    case hidden

    public var label: String {
        switch self {
        case .side: "사이드"
        case .overlay: "화면 위"
        case .hidden: "숨김"
        }
    }

    public var icon: String {
        switch self {
        case .side: "sidebar.right"
        case .overlay: "text.bubble"
        case .hidden: "eye.slash"
        }
    }
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

    // TTS (Text-to-Speech)
    public var ttsEnabled: Bool
    public var ttsVolume: Float
    public var ttsRate: Float

    // 채팅 표시 모드
    public var displayMode: ChatDisplayMode

    // 오버레이 모드 설정
    public var overlayWidth: CGFloat
    public var overlayHeight: CGFloat
    public var overlayBackgroundOpacity: Double
    public var overlayShowInput: Bool

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
        blockedUsers: [String] = [],
        ttsEnabled: Bool = false,
        ttsVolume: Float = 0.8,
        ttsRate: Float = 200,
        displayMode: ChatDisplayMode = .side,
        overlayWidth: CGFloat = 340,
        overlayHeight: CGFloat = 400,
        overlayBackgroundOpacity: Double = 0.5,
        overlayShowInput: Bool = false
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
        self.ttsEnabled = ttsEnabled
        self.ttsVolume = ttsVolume
        self.ttsRate = ttsRate
        self.displayMode = displayMode
        self.overlayWidth = overlayWidth
        self.overlayHeight = overlayHeight
        self.overlayBackgroundOpacity = overlayBackgroundOpacity
        self.overlayShowInput = overlayShowInput
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
        theme: AppTheme = .dark,
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

    // MARK: 연결 타임아웃
    /// API 요청 타임아웃 (초). 너무 짧으면 느린 네트워크에서 빈번한 오류.
    public var connectionTimeout: Int
    /// 스트리밍 초기 연결 대기 최대 시간 (초).
    public var streamConnectionTimeout: Int

    // MARK: 재연결 간격
    /// 재연결 최초 대기 시간 (초). 이후 지수 백오프로 증가.
    public var reconnectBaseDelay: Double

    // MARK: 동시 연결 수
    /// HTTP 호스트당 최대 동시 연결 수.
    public var maxConnectionsPerHost: Int

    // MARK: 스트림 프록시
    /// CDN Content-Type 수정 로컬 프록시 강제 활성.
    /// 비활성 시 VLC/AVPlayer가 CDN에 직접 연결. (기본: 자동)
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
/// 네트워크 설정을 용도에 맞게 최적화하는 프리셋
public enum NetworkPreset: String, Codable, Sendable, CaseIterable {
    case balanced    // 밸런스 (기본)
    case stability   // 안정 우선
    case lowLatency  // 저지연 우선
    case performance // 고성능 (멀티라이브 최적)
    case custom      // 커스텀

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
        case .balanced:
            return "일반 시청에 적합한 기본 설정"
        case .stability:
            return "느린 네트워크에서도 끊김 없는 안정적인 연결"
        case .lowLatency:
            return "빠른 응답 우선. 불안정한 네트워크에서 끊김 가능"
        case .performance:
            return "멀티라이브 등 다수 동시 스트림에 최적화"
        case .custom:
            return "수동으로 각 항목을 직접 조정"
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

    /// 프리셋별 최적 NetworkSettings 반환
    public var settings: NetworkSettings {
        switch self {
        case .balanced:
            return NetworkSettings() // 기본값 그대로
        case .stability:
            return NetworkSettings(
                requestRateLimit: 5,
                cacheExpiry: 600,
                retryCount: 5,
                maxReconnectAttempts: 20,
                autoReconnect: true,
                connectionTimeout: 30,
                streamConnectionTimeout: 20,
                reconnectBaseDelay: 2.0,
                maxConnectionsPerHost: 4,
                forceStreamProxy: true
            )
        case .lowLatency:
            return NetworkSettings(
                requestRateLimit: 20,
                cacheExpiry: 60,
                retryCount: 2,
                maxReconnectAttempts: 5,
                autoReconnect: true,
                connectionTimeout: 8,
                streamConnectionTimeout: 5,
                reconnectBaseDelay: 0.5,
                maxConnectionsPerHost: 10,
                forceStreamProxy: true
            )
        case .performance:
            return NetworkSettings(
                requestRateLimit: 15,
                cacheExpiry: 600,
                retryCount: 3,
                maxReconnectAttempts: 15,
                autoReconnect: true,
                connectionTimeout: 20,
                streamConnectionTimeout: 15,
                reconnectBaseDelay: 1.5,
                maxConnectionsPerHost: 16,
                forceStreamProxy: true
            )
        case .custom:
            return NetworkSettings() // 커스텀은 현재 값 유지
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
    public var key: String            // "space", "upArrow", "downArrow", or single char like "m"
    public var modifiers: ShortcutModifiers

    public init(key: String, modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 사용자에게 표시할 키 이름
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

    /// 수식키 포함 전체 표시 문자열
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
    /// 방송 시작 알림
    public var notifyOnLive: Bool
    /// 카테고리 변경 알림
    public var notifyOnCategoryChange: Bool
    /// 제목 변경 알림
    public var notifyOnTitleChange: Bool

    public var id: String { channelId }

    /// 모든 알림이 비활성화인지
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

    /// 기본값 (모든 알림 활성화)
    public static func defaultSetting(channelId: String, channelName: String) -> ChannelNotificationSetting {
        ChannelNotificationSetting(channelId: channelId, channelName: channelName)
    }
}

/// 채널별 알림 설정 저장소 (channelId → setting 매핑)
public struct ChannelNotificationSettings: Codable, Sendable, Equatable {
    public var settings: [String: ChannelNotificationSetting]

    public init(settings: [String: ChannelNotificationSetting] = [:]) {
        self.settings = settings
    }

    /// 특정 채널 설정 조회 — 없으면 기본값(all-true) 반환
    public func setting(for channelId: String, channelName: String = "") -> ChannelNotificationSetting {
        settings[channelId] ?? .defaultSetting(channelId: channelId, channelName: channelName)
    }

    /// 특정 채널 설정 업데이트
    public mutating func update(_ setting: ChannelNotificationSetting) {
        settings[setting.channelId] = setting
    }

    /// 방송 시작 알림이 활성화된 채널인지
    public func isLiveNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnLive ?? true
    }

    /// 카테고리 변경 알림이 활성화된 채널인지
    public func isCategoryChangeNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnCategoryChange ?? true
    }

    /// 제목 변경 알림이 활성화된 채널인지
    public func isTitleChangeNotificationEnabled(for channelId: String) -> Bool {
        settings[channelId]?.notifyOnTitleChange ?? true
    }

    public static let `default` = ChannelNotificationSettings()
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

// MARK: - MultiLive Layout Mode

/// 멀티라이브 레이아웃 모드
public enum MultiLiveLayoutMode: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    /// 균등 분할 (2×2 그리드)
    case preset = "preset"
    /// 선택된 채널 포커스 + 나머지 작게
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
    /// 최대 동시 세션 수 (2~6)
    public var maxConcurrentSessions: Int
    /// 멀티라이브 기본 엔진
    public var preferredEngine: PlayerEngineType
    /// 레이아웃 모드
    public var defaultLayoutMode: MultiLiveLayoutMode
    /// 멀티오디오 활성화
    public var multiAudioEnabled: Bool
    /// 보조 스트림 볼륨 (0~1)
    public var secondaryVolume: Float
    /// 백그라운드 세션 품질 자동 저하
    public var backgroundQualityReduction: Bool
    /// 자동 재연결
    public var autoReconnect: Bool
    /// 자동 재연결 최대 시도 횟수
    public var autoReconnectMaxRetries: Int
    /// 그리드 모드에서 채팅 오버레이 표시
    public var chatOverlayInGrid: Bool
    /// 채팅 오버레이 투명도 (0~1)
    public var chatOverlayOpacity: Double
    /// 채팅 오버레이 글꼴 크기 (8~24)
    public var chatOverlayFontSize: Double

    public init(
        maxConcurrentSessions: Int = 4,
        preferredEngine: PlayerEngineType = .avPlayer,
        defaultLayoutMode: MultiLiveLayoutMode = .preset,
        multiAudioEnabled: Bool = false,
        secondaryVolume: Float = 0.3,
        backgroundQualityReduction: Bool = true,
        autoReconnect: Bool = true,
        autoReconnectMaxRetries: Int = 10,
        chatOverlayInGrid: Bool = false,
        chatOverlayOpacity: Double = 0.5,
        chatOverlayFontSize: Double = 12
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
    }

    public static let `default` = MultiLiveSettings()
}
