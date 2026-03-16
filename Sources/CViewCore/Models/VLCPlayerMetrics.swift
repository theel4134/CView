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

    /// 해당 구간에서 디코딩된 오디오 샘플 수
    public let decodedAudioDelta: Int

    /// 해당 구간에서 재생된 오디오 버퍼 수
    public let playedAudioBuffersDelta: Int

    // MARK: - I/O

    /// 해당 구간에서 입력에서 읽은 바이트 수
    public let readBytesDelta: Int

    /// 해당 구간에서 디먹서가 읽은 바이트 수
    public let demuxReadBytesDelta: Int

    /// 해당 구간에서 화면에 표시된 프레임 수
    public let displayedPicturesDelta: Int

    // MARK: - 스트림 품질 (VLCKit 4.0)

    /// 해당 구간에서 지연 렌더링된 프레임 수 (디코딩은 됐으나 표시 시점 초과)
    public let latePicturesDelta: Int

    /// 해당 구간에서 손상된 demux 패킷 수 (CDN/네트워크 오류 지표)
    public let demuxCorruptedDelta: Int

    /// 해당 구간에서 발생한 demux 불연속 수 (타임스탬프 점프 / 세그먼트 누락)
    public let demuxDiscontinuityDelta: Int

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
    /// fps, bufferHealth, dropRatio, audioLost, lateFrames, demuxErrors를 가중 평균
    /// 60fps 스트림 정규화: fps를 targetFps (추정값) 기준으로 정규화
    public var healthScore: Double {
        // 60fps 스트림 대응: fps 30 이상이면 60fps 기준, 그 이하는 30fps 기준
        let targetFps = fps > 35 ? 60.0 : 30.0
        let fpsScore:    Double = min(fps / targetFps, 1.0)
        let bufScore:    Double = bufferHealth
        let dropScore:   Double = max(0.0, 1.0 - dropRatio * 10.0)
        let audioScore:  Double = lostAudioBuffersDelta == 0 ? 1.0 : 0.7
        let lateScore:   Double = latePicturesDelta == 0 ? 1.0 : max(0.5, 1.0 - Double(latePicturesDelta) * 0.05)
        let demuxScore:  Double = (demuxCorruptedDelta + demuxDiscontinuityDelta) == 0 ? 1.0 : 0.6
        return (fpsScore * 0.30 + bufScore * 0.25 + dropScore * 0.20 + audioScore * 0.10
                + lateScore * 0.10 + demuxScore * 0.05)
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
        decodedAudioDelta: Int = 0,
        playedAudioBuffersDelta: Int = 0,
        readBytesDelta: Int = 0,
        demuxReadBytesDelta: Int = 0,
        displayedPicturesDelta: Int = 0,
        latePicturesDelta: Int = 0,
        demuxCorruptedDelta: Int = 0,
        demuxDiscontinuityDelta: Int = 0,
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
        self.decodedAudioDelta = decodedAudioDelta
        self.playedAudioBuffersDelta = playedAudioBuffersDelta
        self.readBytesDelta = readBytesDelta
        self.demuxReadBytesDelta = demuxReadBytesDelta
        self.displayedPicturesDelta = displayedPicturesDelta
        self.latePicturesDelta = latePicturesDelta
        self.demuxCorruptedDelta = demuxCorruptedDelta
        self.demuxDiscontinuityDelta = demuxDiscontinuityDelta
        self.timestamp = timestamp
    }
}
