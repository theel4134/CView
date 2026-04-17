// MARK: - CViewCore/Models/SettingsModels.swift
// 설정 도메인 모델 — 카테고리별 분리

import Foundation

/// 스크린샷 저장 포맷
public enum ScreenshotFormat: String, Codable, Sendable, CaseIterable {
    case png
    case jpeg

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    public var fileExtension: String { rawValue }
}

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
    /// 항상 최고 화질(1080p60) 유지 — ABR 하향/해상도 캡핑/프레임 스킵 비활성화
    public var forceHighestQuality: Bool

    // MARK: - 스크린샷 설정
    /// 스크린샷 저장 경로
    public var screenshotPath: String
    /// 스크린샷 저장 포맷
    public var screenshotFormat: ScreenshotFormat

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

    /// 선명한 화면 — nearest-neighbor 스케일링 (픽셀 엣지 선명)
    /// AV엔진: AVPlayerLayer.magnificationFilter = .nearest
    /// VLC엔진: VLCLayerHostView 레이어 및 서브레이어 magnificationFilter = .nearest
    public var sharpPixelScaling: Bool

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
        forceHighestQuality: Bool = true,
        screenshotPath: String = "~/Pictures/CView Screenshots",
        screenshotFormat: ScreenshotFormat = .png,
        equalizerPreset: String? = nil,
        equalizerPreAmp: Float = 0,
        equalizerBands: [Float] = [],
        videoAdjustEnabled: Bool = false,
        sharpPixelScaling: Bool = false,
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
        self.forceHighestQuality = forceHighestQuality
        self.screenshotPath = screenshotPath
        self.screenshotFormat = screenshotFormat
        self.equalizerPreset = equalizerPreset
        self.equalizerPreAmp = equalizerPreAmp
        self.equalizerBands = equalizerBands
        self.sharpPixelScaling = sharpPixelScaling
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
        case forceHighestQuality
        case screenshotPath, screenshotFormat
        case equalizerPreset, equalizerPreAmp, equalizerBands
        case videoAdjustEnabled, videoBrightness, videoContrast, videoSaturation, videoHue, videoGamma
        case sharpPixelScaling
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
        forceHighestQuality = try c.decodeIfPresent(Bool.self, forKey: .forceHighestQuality) ?? true
        screenshotPath = try c.decodeIfPresent(String.self, forKey: .screenshotPath) ?? "~/Pictures/CView Screenshots"
        screenshotFormat = try c.decodeIfPresent(ScreenshotFormat.self, forKey: .screenshotFormat) ?? .png
        equalizerPreset = try c.decodeIfPresent(String.self, forKey: .equalizerPreset)
        sharpPixelScaling = try c.decodeIfPresent(Bool.self, forKey: .sharpPixelScaling) ?? false
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
    public var highlightRoles: Bool
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
    public var ttsVoiceIdentifier: String?

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
        highlightRoles: Bool = true,
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
        ttsVoiceIdentifier: String? = nil,
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
        self.highlightRoles = highlightRoles
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
        self.ttsVoiceIdentifier = ttsVoiceIdentifier
        self.displayMode = displayMode
        self.overlayWidth = overlayWidth
        self.overlayHeight = overlayHeight
        self.overlayBackgroundOpacity = overlayBackgroundOpacity
        self.overlayShowInput = overlayShowInput
    }

    public static let `default` = ChatSettings()
}

