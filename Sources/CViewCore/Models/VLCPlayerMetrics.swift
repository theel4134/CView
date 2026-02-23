// MARK: - VLCPlayerMetrics.swift
// VLC 플레이어 실시간 메트릭 스냅샷 (CViewCore — 모듈 간 공유 타입)

import Foundation

/// VLC 플레이어에서 수집한 실시간 재생 메트릭.
/// VLCPlayerEngine이 2초마다 계산하여 콜백으로 전달합니다.
public struct VLCLiveMetrics: Sendable {

    // MARK: - 비디오

    /// 초당 표시된 프레임 수 (FPS)
    public let fps: Double

    /// 해당 구간에서 드롭된 프레임 수 (누적 delta)
    public let droppedFramesDelta: Int

    /// 해당 구간에서 디코딩된 총 프레임 수 (누적 delta)
    public let decodedFramesDelta: Int

    // MARK: - 네트워크

    /// 초당 수신 바이트 (bytes/sec)
    public let networkBytesPerSec: Int

    /// 입력 비트레이트 kbps (VLC inputBitrate → KB/s → kbps 변환)
    public let inputBitrateKbps: Double

    /// 디먹싱 비트레이트 kbps
    public let demuxBitrateKbps: Double

    // MARK: - 영상 정보

    /// 해상도 문자열 (예: "1920x1080"), 알 수 없으면 nil
    public let resolution: String?

    /// 비디오 가로 픽셀 (0 = 알 수 없음)
    public let videoWidth: Double

    /// 비디오 세로 픽셀
    public let videoHeight: Double

    // MARK: - 재생 상태

    /// 현재 재생 배율 (1.0 = 정상)
    public let playbackRate: Float

    /// 버퍼 건강도 0.0~1.0 (1.0 = 완전 건강)
    public let bufferHealth: Double

    // MARK: - 오디오

    /// 해당 구간에서 손실된 오디오 버퍼 수
    public let lostAudioBuffersDelta: Int

    // MARK: - 기타

    /// 스냅샷 생성 시각
    public let timestamp: Date

    // MARK: - 계산 프로퍼티

    /// 드롭 프레임 비율 0.0~1.0 (droppedDelta / (droppedDelta + decodedDelta))
    public var dropRatio: Double {
        let total = droppedFramesDelta + decodedFramesDelta
        guard total > 0 else { return 0 }
        return Double(droppedFramesDelta) / Double(total)
    }

    /// 종합 건강 점수 0.0~1.0
    /// fps, bufferHealth, dropRatio, audioLost를 가중 평균
    public var healthScore: Double {
        let fpsScore:    Double = min(fps / 30.0, 1.0)         // 30fps 기준 정규화
        let bufScore:    Double = bufferHealth
        let dropScore:   Double = max(0.0, 1.0 - dropRatio * 10.0)   // 10% drop → 0
        let audioScore:  Double = lostAudioBuffersDelta == 0 ? 1.0 : 0.7
        return (fpsScore * 0.35 + bufScore * 0.30 + dropScore * 0.25 + audioScore * 0.10)
    }

    // MARK: - Init

    public init(
        fps: Double,
        droppedFramesDelta: Int,
        decodedFramesDelta: Int,
        networkBytesPerSec: Int,
        inputBitrateKbps: Double,
        demuxBitrateKbps: Double,
        resolution: String?,
        videoWidth: Double,
        videoHeight: Double,
        playbackRate: Float,
        bufferHealth: Double,
        lostAudioBuffersDelta: Int,
        timestamp: Date = Date()
    ) {
        self.fps = fps
        self.droppedFramesDelta = droppedFramesDelta
        self.decodedFramesDelta = decodedFramesDelta
        self.networkBytesPerSec = networkBytesPerSec
        self.inputBitrateKbps = inputBitrateKbps
        self.demuxBitrateKbps = demuxBitrateKbps
        self.resolution = resolution
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.playbackRate = playbackRate
        self.bufferHealth = bufferHealth
        self.lostAudioBuffersDelta = lostAudioBuffersDelta
        self.timestamp = timestamp
    }
}
