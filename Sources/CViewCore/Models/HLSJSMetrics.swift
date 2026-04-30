// MARK: - HLSJSMetrics.swift
// HLS.js 엔진 실시간 메트릭 스냅샷 (CViewCore — 모듈 간 공유 타입)

import Foundation

/// HLS.js(WKWebView) 엔진에서 수집한 실시간 재생 메트릭.
/// HLSJSPlayerEngine이 2초마다 JS 브릿지를 통해 수집하여 콜백으로 전달합니다.
public struct HLSJSLiveMetrics: Sendable, Decodable {

    // MARK: - 비디오

    /// 초당 표시된 프레임 수 (FPS) — video.getVideoPlaybackQuality()
    public let fps: Double

    /// 누적 드롭 프레임 수
    public let droppedFrames: Int

    /// 이전 수집 이후 드롭 프레임 증분
    public let droppedFramesDelta: Int

    // MARK: - 네트워크

    /// 현재 비트레이트 kbps (hls.js bandwidthEstimate 기반)
    public let bitrateKbps: Double

    // MARK: - 레이턴시

    /// hls.js.latency — 라이브 엣지 대비 현재 지연 시간 (초)
    public let latency: Double

    // MARK: - 버퍼

    /// 현재 버퍼 길이 (초)
    public let bufferLength: Double

    // MARK: - 해상도

    /// 현재 비디오 해상도 문자열 (예: "1920x1080")
    public let resolution: String?

    // MARK: - 재생 상태

    /// 현재 재생 속도 (1.0 = 정상)
    public let playbackRate: Float

    /// 재생 일시정지 여부
    public let paused: Bool

    /// video.currentTime (Watchdog 정체 감지용)
    public let currentTime: TimeInterval

    /// 버퍼 건강도 0.0~1.0
    public let bufferHealth: Double

    // MARK: - HLS.js 전용

    /// hls.js 현재 레벨 인덱스
    public let currentLevel: Int

    /// 현재 세그먼트 길이 (초)
    public let fragmentDuration: Double

    // MARK: - 스냅샷 시각

    /// 스냅샷 생성 시각
    public let timestamp: Date

    // MARK: - 계산 프로퍼티

    /// 종합 건강 점수 0.0~1.0
    public var healthScore: Double {
        let bitrateScore: Double = bitrateKbps > 0 ? 1.0 : 0.0
        let dropScore: Double = droppedFramesDelta == 0 ? 1.0 : max(0.3, 1.0 - Double(droppedFramesDelta) * 0.05)
        let bufScore: Double = bufferHealth
        let latencyScore: Double = latency < 3.0 ? 1.0 : max(0.3, 1.0 - (latency - 3.0) * 0.1)
        return bitrateScore * 0.20 + dropScore * 0.25 + bufScore * 0.30 + latencyScore * 0.25
    }

    // MARK: - Init

    public init(
        fps: Double = 0,
        droppedFrames: Int = 0,
        droppedFramesDelta: Int = 0,
        bitrateKbps: Double = 0,
        latency: Double = 0,
        bufferLength: Double = 0,
        resolution: String? = nil,
        playbackRate: Float = 1.0,
        paused: Bool = false,
        currentTime: TimeInterval = 0,
        bufferHealth: Double = 0,
        currentLevel: Int = -1,
        fragmentDuration: Double = 0,
        timestamp: Date = Date()
    ) {
        self.fps = fps
        self.droppedFrames = droppedFrames
        self.droppedFramesDelta = droppedFramesDelta
        self.bitrateKbps = bitrateKbps
        self.latency = latency
        self.bufferLength = bufferLength
        self.resolution = resolution
        self.playbackRate = playbackRate
        self.paused = paused
        self.currentTime = currentTime
        self.bufferHealth = bufferHealth
        self.currentLevel = currentLevel
        self.fragmentDuration = fragmentDuration
        self.timestamp = timestamp
    }
}
