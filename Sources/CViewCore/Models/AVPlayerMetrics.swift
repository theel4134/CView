// MARK: - AVPlayerMetrics.swift
// AVPlayer 실시간 메트릭 스냅샷 (CViewCore — 모듈 간 공유 타입)

import Foundation

/// AVPlayer에서 수집한 실시간 재생 메트릭.
/// AVPlayerEngine이 주기적으로 계산하여 콜백으로 전달합니다.
public struct AVPlayerLiveMetrics: Sendable {

    // MARK: - 비디오

    /// AccessLog 기반 추정 비트레이트 (bps)
    public let indicatedBitrate: Double

    /// 누적 드롭 프레임 수 (AccessLog)
    public let droppedFrames: Int

    /// 이전 수집 이후 드롭 프레임 증분
    public let droppedFramesDelta: Int

    // MARK: - 레이턴시

    /// 현재 측정 지연 시간 (초)
    public let measuredLatency: Double

    // MARK: - 해상도

    /// 현재 비디오 해상도 문자열 (예: "1920x1080"), 없으면 nil
    public let resolution: String?

    // MARK: - 재생 상태

    /// 현재 재생 속도 (1.0 = 정상)
    public let playbackRate: Float

    /// 버퍼 건강도 0.0~1.0 (isPlaybackLikelyToKeepUp 기반)
    public let bufferHealth: Double

    // MARK: - 기타

    /// 스냅샷 생성 시각
    public let timestamp: Date

    // MARK: - 계산 프로퍼티

    /// 비트레이트 kbps 단위
    public var bitrateKbps: Double {
        indicatedBitrate / 1000.0
    }

    /// 종합 건강 점수 0.0~1.0
    public var healthScore: Double {
        let bitrateScore: Double = indicatedBitrate > 0 ? 1.0 : 0.0
        let dropScore: Double = droppedFramesDelta == 0 ? 1.0 : max(0.3, 1.0 - Double(droppedFramesDelta) * 0.05)
        let bufScore: Double = bufferHealth
        let latencyScore: Double = measuredLatency < 5.0 ? 1.0 : max(0.3, 1.0 - (measuredLatency - 5.0) * 0.05)
        return bitrateScore * 0.20 + dropScore * 0.25 + bufScore * 0.30 + latencyScore * 0.25
    }

    // MARK: - Init

    public init(
        indicatedBitrate: Double,
        droppedFrames: Int,
        droppedFramesDelta: Int,
        measuredLatency: Double,
        resolution: String?,
        playbackRate: Float,
        bufferHealth: Double,
        timestamp: Date = Date()
    ) {
        self.indicatedBitrate = indicatedBitrate
        self.droppedFrames = droppedFrames
        self.droppedFramesDelta = droppedFramesDelta
        self.measuredLatency = measuredLatency
        self.resolution = resolution
        self.playbackRate = playbackRate
        self.bufferHealth = bufferHealth
        self.timestamp = timestamp
    }
}
