// MARK: - HLSJSPlayerEngine.swift
// CViewPlayer — hls.js 기반 LL-HLS 플레이어 엔진
//
// [설계 원칙]
// • WKWebView + hls.js로 Low-Latency HLS 스트림 재생
// • PlayerEngineProtocol 준수 — VLC/AVPlayer와 동일한 인터페이스
// • 메트릭 수집: JS 2초 폴링 → Swift 콜백
// • 녹화 미지원 (WKWebView 제약)

import Foundation
import AppKit
import CViewCore

// MARK: - HLS.js 스트리밍 프로파일

/// hls.js LL-HLS 시나리오별 프로파일
public enum HLSJSStreamingProfile: Sendable {
    case ultraLow       // 최저 지연 (타겟 ~1초)
    case lowLatency     // 저지연 기본값 (타겟 ~2초)
    case multiLive      // 멀티라이브 (메모리 절약, 타겟 ~3초)
    /// [P2-3 / 2026-04-25] hls.js 기본값 그대로 사용 — 웹 임베디드 플레이어와
    /// 동일한 버퍼/지연 상한으로 재생. PDT 관찰/비교/디버그 용도.
    /// liveSyncDurationCount=3, liveMaxLatencyDurationCount=10, lowLatencyMode=false.
    case mirror

    var profileKey: String {
        switch self {
        case .ultraLow: return "ultraLow"
        case .lowLatency: return "lowLatency"
        case .multiLive: return "multiLive"
        case .mirror: return "mirror"
        }
    }

    /// 멀티라이브 그리드 최대 해상도 (height)
    func maxHeight(isSelected: Bool) -> Int {
        switch self {
        case .ultraLow, .lowLatency, .mirror: return 1080
        case .multiLive: return isSelected ? 1080 : 720
        }
    }
}

// MARK: - HLS.js 플레이어 엔진

/// hls.js(WKWebView) 기반 스트림 플레이어 엔진.
/// LL-HLS Part 로딩, Worker demux 등 저지연 최적화.
@preconcurrency
public final class HLSJSPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {

    // MARK: - Public Properties

    /// 스트리밍 프로파일 (play() 이전에 설정)
    public var streamingProfile: HLSJSStreamingProfile = .lowLatency

    /// 멀티라이브 선택 세션 여부
    public var isSelectedSession: Bool = true

    /// 대역폭 코디네이터 최대 해상도 높이 캡 (0 = 제한 없음)
    public var maxAdaptiveHeight: Int = 0

    /// 상태 변경 콜백
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?

    /// HLS.js 실시간 메트릭 콜백 (2초 주기)
    public var onHLSJSMetrics: (@Sendable (HLSJSLiveMetrics) -> Void)?

    /// 트랙 이벤트 콜백 (PlayerEngineProtocol 요구사항)
    public var onTrackEvent: (@Sendable (TrackEvent) -> Void)?

    /// HLS.js 이벤트 콜백
    public var onHLSJSEvent: (@Sendable (HLSJSEvent) -> Void)?

    /// 재생 정체 감지 콜백
    public var onPlaybackStalled: (@Sendable () -> Void)?

    // MARK: - PlayerEngineProtocol

    public private(set) var isPlaying: Bool = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var rate: Float = 1.0
    public var isRecording: Bool { false }
    public var isInErrorState: Bool = false

    /// 비디오 렌더링 뷰 (WKWebView 호스트)
    public var videoView: NSView { playerView }

    // MARK: - Private

    private let playerView: HLSJSVideoView
    private var currentURL: URL?
    private var _volume: Float = 1.0
    private var _isMuted: Bool = false

    // MARK: - Init

    public override init() {
        self.playerView = HLSJSVideoView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        super.init()
        setupCallbacks()
    }

    private func setupCallbacks() {
        playerView.onMetrics = { [weak self] metrics in
            guard let self else { return }
            // video.currentTime 기반 — Watchdog이 정확히 stall 감지 가능
            self.currentTime = metrics.currentTime
            self.rate = metrics.playbackRate
            // paused 상태면 isPlaying을 false로 반영
            if metrics.paused && self.isPlaying {
                self.isPlaying = false
            }
            self.onHLSJSMetrics?(metrics)
        }

        playerView.onEvent = { [weak self] event in
            guard let self else { return }
            self.onHLSJSEvent?(event)

            switch event {
            case .manifestParsed:
                self.isPlaying = true
                self.isInErrorState = false
                self.onStateChange?(.playing)
            case .fatalError:
                self.isPlaying = false
                self.isInErrorState = true
            case .error(let fatal, _, _) where fatal:
                self.isPlaying = false
                self.isInErrorState = true
            default:
                break
            }
        }

        playerView.onStateChange = { [weak self] phase in
            self?.onStateChange?(phase)
        }
    }

    // MARK: - PlayerEngineProtocol Methods

    public func play(url: URL) async throws {
        currentURL = url
        isInErrorState = false

        let profile = streamingProfile.profileKey
        let urlString = url.absoluteString
        AppLogger.player.debug("HLSJSPlayerEngine: play() (profile=\(profile, privacy: .public), url=\(urlString.prefix(80), privacy: .public))")

        await MainActor.run {
            playerView.loadSource(url: urlString, profile: profile)

            // 해상도 캡 적용
            let maxH = maxAdaptiveHeight > 0 ? maxAdaptiveHeight
                : streamingProfile.maxHeight(isSelected: isSelectedSession)
            if maxH > 0 && maxH < 1080 {
                playerView.setMaxResolution(maxH)
            }
        }

        onStateChange?(.loading)
    }

    public func pause() {
        isPlaying = false
        playerView.pause()
        onStateChange?(.paused)
    }

    public func resume() {
        isPlaying = true
        playerView.play()
        onStateChange?(.playing)
    }

    /// 라이브 엣지로 seek (백그라운드 복귀 시 사용)
    public func seekToLiveEdge() {
        playerView.seekToLiveEdge()
    }

    public func stop() {
        isPlaying = false
        currentURL = nil
        playerView.stopPlayback()
        onStateChange?(.idle)
    }

    public func seek(to position: TimeInterval) {
        playerView.seek(to: position)
    }

    public func setRate(_ rate: Float) {
        self.rate = rate
        playerView.setRate(rate)
    }

    public func setVolume(_ volume: Float) {
        _volume = volume
        if !_isMuted {
            playerView.setVolume(volume)
        }
    }

    /// 음소거 토글 (편의 메서드)
    public func setMuted(_ muted: Bool) {
        _isMuted = muted
        playerView.setMuted(muted)
    }

    // MARK: - Recording (미지원)

    public func startRecording(to url: URL) async throws {
        throw PlayerError.recordingFailed("HLS.js 엔진은 녹화를 지원하지 않습니다")
    }

    public func stopRecording() async {}

    // MARK: - Health

    public func resetRetries() {
        isInErrorState = false
    }

    // MARK: - 최대 비트레이트 캡

    /// 대역폭 코디네이터가 호출 — 최대 비트레이트 제한
    public func setMaxBitrate(_ maxKbps: Int) {
        playerView.setMaxBitrate(maxKbps)
    }

    /// 대역폭 코디네이터가 호출 — 최대 해상도 제한
    public func setMaxResolutionHeight(_ maxHeight: Int) {
        maxAdaptiveHeight = maxHeight
        playerView.setMaxResolution(maxHeight)
    }

    // MARK: - 풀 반납

    /// 엔진 풀 반납 전 초기화
    public func resetForReuse() {
        stop()
        playerView.resetForReuse()
        onStateChange = nil
        onHLSJSMetrics = nil
        onTrackEvent = nil
        onHLSJSEvent = nil
        onPlaybackStalled = nil
        isInErrorState = false
        currentTime = 0
        duration = 0
        rate = 1.0
        _volume = 1.0
        _isMuted = false
        isSelectedSession = true
        maxAdaptiveHeight = 0
        // view→engine 내부 콜백 체인 복원 (풀 재사용 시 메트릭/이벤트 전달 보장)
        setupCallbacks()
    }
}
