// MARK: - CViewCore/Models/PlayerModels.swift
// 플레이어 도메인 모델

import Foundation

/// 플레이어 상태
public struct PlayerState: Sendable, Equatable {
    public var phase: Phase
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var bufferedDuration: TimeInterval
    public var playbackRate: Double
    public var volume: Float
    public var latency: TimeInterval?
    public var quality: StreamQuality

    public init(
        phase: Phase = .idle,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        bufferedDuration: TimeInterval = 0,
        playbackRate: Double = 1.0,
        volume: Float = 1.0,
        latency: TimeInterval? = nil,
        quality: StreamQuality = .auto
    ) {
        self.phase = phase
        self.currentTime = currentTime
        self.duration = duration
        self.bufferedDuration = bufferedDuration
        self.playbackRate = playbackRate
        self.volume = volume
        self.latency = latency
        self.quality = quality
    }

    /// 플레이어 재생 단계
    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case buffering(progress: Double)
        case playing
        case paused
        case error(PlayerError)
        case ended
    }

    public var isActive: Bool {
        switch phase {
        case .playing, .buffering, .paused: true
        default: false
        }
    }
}

/// 플레이어 에러
public enum PlayerError: Error, Sendable, Equatable, LocalizedError {
    case streamNotFound
    case networkTimeout
    case decodingFailed(String)
    case engineInitFailed
    case unsupportedFormat(String)
    case hlsParsingFailed(String)
    case invalidManifest
    case connectionLost
    case authRequired

    public var errorDescription: String? {
        switch self {
        case .streamNotFound: "스트림을 찾을 수 없습니다"
        case .networkTimeout: "네트워크 연결 시간 초과"
        case .decodingFailed(let detail): "디코딩 실패: \(detail)"
        case .engineInitFailed: "플레이어 엔진 초기화 실패"
        case .unsupportedFormat(let format): "지원하지 않는 포맷: \(format)"
        case .hlsParsingFailed(let detail): "HLS 파싱 실패: \(detail)"
        case .invalidManifest: "잘못된 매니페스트"
        case .connectionLost: "연결이 끊어졌습니다"
        case .authRequired: "인증이 필요합니다"
        }
    }
}

/// 재생 옵션
public struct PlaybackOptions: Sendable {
    public var quality: StreamQuality
    public var lowLatencyMode: Bool
    public var networkCaching: Int
    public var liveCaching: Int
    public var catchupEnabled: Bool
    public var maxCatchupRate: Double

    public init(
        quality: StreamQuality = .auto,
        lowLatencyMode: Bool = true,
        networkCaching: Int = 500,
        liveCaching: Int = 500,
        catchupEnabled: Bool = true,
        maxCatchupRate: Double = 1.25
    ) {
        self.quality = quality
        self.lowLatencyMode = lowLatencyMode
        self.networkCaching = networkCaching
        self.liveCaching = liveCaching
        self.catchupEnabled = catchupEnabled
        self.maxCatchupRate = maxCatchupRate
    }

    /// 프리셋: 초저지연
    public static let ultraLowLatency = PlaybackOptions(
        lowLatencyMode: true, networkCaching: 200, liveCaching: 200,
        catchupEnabled: true, maxCatchupRate: 1.25
    )

    /// 프리셋: 균형
    public static let balanced = PlaybackOptions(
        lowLatencyMode: true, networkCaching: 1000, liveCaching: 1000,
        catchupEnabled: true, maxCatchupRate: 1.1
    )

    /// 프리셋: 안정
    public static let stable = PlaybackOptions(
        lowLatencyMode: false, networkCaching: 3000, liveCaching: 3000,
        catchupEnabled: false, maxCatchupRate: 1.0
    )
}

/// 플레이어 엔진 타입
public enum PlayerEngineType: String, Sendable, Codable, CaseIterable {
    case vlc = "VLC"
    case avPlayer = "AVPlayer"

    public var displayName: String {
        switch self {
        case .vlc: "VLC (저지연)"
        case .avPlayer: "AVPlayer (안정)"
        }
    }
}
