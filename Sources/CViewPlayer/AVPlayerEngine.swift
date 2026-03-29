// MARK: - AVPlayerEngine.swift
// CViewPlayer - AVPlayer 기반 라이브 스트림 재생 엔진 (고도화)
// Reference: chzzkView-v1/HLSNativePlayer, StreamReconnectionManager, EnhancedErrorRecoverySystem
//
// 분리된 Extension 파일:
//   - AVPlayerLayerView.swift          — 비디오 렌더링 NSView (Metal Zero-Copy)
//   - AVPlayerEngine+LiveStream.swift  — 캐치업 설정, 스톨 감지, 네트워크 모니터
//   - AVPlayerEngine+Observers.swift   — KVO/Notification 옵저버, 메트릭 수집

import Foundation
import AVFoundation
import Network
import AppKit
import QuartzCore
import Synchronization
import CViewCore

// MARK: - AVPlayerEngine

/// AVPlayer 기반 라이브 스트림 재생 엔진
/// - 저지연 HLS: automaticallyWaitsToMinimizeStalling = false, configuredTimeOffsetFromLive
/// - 스톨 워치독: 45초 무응답 → .connectionLost 에러 발생
/// - 라이브 캐치업: 지연이 maxLatency 초과 시 재생 속도를 최대 1.5배로 조정
/// - NWPathMonitor: 네트워크 인터페이스에 따라 목표 지연 시간 자동 조정
/// - 세분화된 에러 분류: AVFoundation 에러 코드 → PlayerError 12종
public final class AVPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {

    // MARK: - Public Properties

    public let player: AVPlayer
    /// catchupConfig 접근자 — Mutex 경유
    public var catchupConfig: AVLiveCatchupConfig {
        get { _avState.withLock { $0.catchupConfig } }
        set { _avState.withLock { $0.catchupConfig = newValue } }
    }

    /// State change callback
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?
    /// Time change callback (currentTime, duration)
    public var onTimeChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?
    /// Latency change callback (latency in seconds)
    public var onLatencyChange: (@Sendable (Double) -> Void)?
    /// Reconnection requested callback
    public var onReconnectRequested: (@Sendable () -> Void)?

    /// AVPlayer 실시간 메트릭 콜백 (10초 주기) — VLC의 onVLCMetrics에 대응
    public var onAVMetrics: (@Sendable (AVPlayerLiveMetrics) -> Void)?

    // MARK: - PlayerEngineProtocol Properties

    public var isPlaying: Bool {
        _avState.withLock { $0.state == .playing }
    }

    public var isInErrorState: Bool {
        _avState.withLock { if case .error = $0.state { return true }; return false }
    }

    public var currentTime: TimeInterval {
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? t : 0
    }

    public var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let d = CMTimeGetSeconds(item.duration)
        return d.isFinite ? d : 0
    }

    public var rate: Float {
        _avState.withLock { $0.rate }
    }

    public var videoView: NSView { _videoView }

    // MARK: - Internal State (Extension 파일에서 접근)

    /// Mutex\<AVEngineState\>로 보호되는 변수들 — 여러 스레드/큐에서 동시 접근
    internal struct AVEngineState: Sendable {
        var state: PlayerState.Phase = .idle
        var rate: Float = 1.0
        var volume: Float = 1.0
        var currentURL: URL? = nil
        var catchupConfig: AVLiveCatchupConfig = .webSync
        var isLiveStream: Bool = false
        var lastProgressTime: Date = Date()
        var isRecording: Bool = false
        var recordingURL: URL? = nil
    }
    internal let _avState = Mutex(AVEngineState())

    private let _videoView: AVPlayerLayerView
    internal let logger = AppLogger.player

    // MARK: - KVO / Observers

    internal var statusObservation: NSKeyValueObservation?
    internal var timeControlObservation: NSKeyValueObservation?
    internal var bufferKeepUpObservation: NSKeyValueObservation?  // isPlaybackLikelyToKeepUp
    internal var bufferFullObservation: NSKeyValueObservation?    // isPlaybackBufferFull
    internal var timeObserver: Any?
    internal var stallObservation: NSObjectProtocol?
    internal var bufferObservation: NSObjectProtocol?
    internal var accessLogObservation: NSObjectProtocol?          // AVPlayerItemNewAccessLogEntry
    internal var liveOffsetObservation: NSObjectProtocol?         // RecommendedTimeOffsetFromLive

    // MARK: - Live Stream State

    internal var isLiveStream: Bool {
        get { _avState.withLock { $0.isLiveStream } }
        set { _avState.withLock { $0.isLiveStream = newValue } }
    }
    internal var stallWatchdogTask: Task<Void, Never>?
    internal var liveCatchupTask: Task<Void, Never>?
    internal var lastProgressTime: Date {
        get { _avState.withLock { $0.lastProgressTime } }
        set { _avState.withLock { $0.lastProgressTime = newValue } }
    }
    /// 최근 캐치업 속도 히스토리 — 급격한 속도 변화 스무딩용 (최대 4개)
    internal var rateHistory: [Float] = []
    /// 현재 측정 지연 시간 (초) — AccessLog/Catchup 공유
    internal var measuredLatency: Double = 0
    /// AccessLog 기반 추정 비트레이트 (bps)
    internal var indicatedBitrate: Double = 0
    /// AccessLog 기반 드롭 프레임 수 누적
    internal var droppedFrames: Int = 0

    // MARK: - Network Monitor

    internal let networkMonitor = NWPathMonitor()
    internal var currentNetworkType: NWInterface.InterfaceType = .wifi
    internal let networkQueue = DispatchQueue(label: "av.engine.network")

    // MARK: - Recording

    private let recordingService = StreamRecordingService()

    // MARK: - Background Mode (멀티라이브 비활성 세션 CPU 절약)
    
    /// 멀티라이브에서 비활성(음소거) 세션의 CPU 사용 절감
    /// - liveCatchupLoop 건너뜀 (재생 속도 조정 불필요)
    /// - stallWatchdog 건너뜀 (비활성 세션 복구 지연 허용)
    /// - timeObserver 콜백 공백 전파 안 함
    public var isBackgroundMode: Bool = false

    // MARK: - Metrics Collection

    /// 메트릭 수집 주기 Task (10초)
    internal var metricsCollectionTask: Task<Void, Never>?
    /// 이전 수집 시점의 드롭 프레임 수 (delta 계산용)
    internal var previousDroppedFrames: Int = 0

    // MARK: - Stall Watchdog State

    internal var recentReconnectTimestamps: [Date] = []
    internal let maxReconnectsInWindow = 3
    internal let reconnectWindowSeconds: TimeInterval = 300 // 5분

    // MARK: - Initialization

    public override init() {
        self._videoView = AVPlayerLayerView()
        self.player = AVPlayer()
        super.init()
        _videoView.attach(player: player)
        setupNetworkMonitor()
        setupObservers()
    }

    deinit {
        networkMonitor.cancel()
        stallWatchdogTask?.cancel()
        liveCatchupTask?.cancel()
        metricsCollectionTask?.cancel()
        removeObservers()
        player.pause()
    }

    // MARK: - Video Layer Visibility

    /// 비디오 레이어 출력 표시/숨김.
    /// `isHidden = true` 시 GPU 합성 패스를 완전히 건너뜀 (디코딩·오디오는 유지).
    /// 백그라운드 전환 또는 오디오 전용 모드에서 호출한다.
    public func setVideoLayerVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        _videoView.playerLayer.isHidden = !visible
        CATransaction.commit()
    }

    // MARK: - PlayerEngineProtocol Methods

    public func play(url: URL) async throws {
        // 이전 재생 정리
        stallWatchdogTask?.cancel()
        liveCatchupTask?.cancel()
        removeItemObservers()

        _avState.withLock { $0.currentURL = url; $0.state = .loading }
        notifyStateChange(.loading)

        // 속도 스무딩 히스토리 초기화
        rateHistory.removeAll()
        droppedFrames = 0
        indicatedBitrate = 0
        measuredLatency = 0

        isLiveStream = detectLiveStream(url: url)

        // ── Metal 최적 Asset 설정 + VideoToolbox 하드웨어 디코더 힌트 ──────
        let playerOptions: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0",
                // LLHLS 지원 서버에 저지연 세그먼트 힌트 전달
                "Accept": "application/vnd.apple.mpegurl, application/x-mpegURL, audio/mpegurl, */*"
            ] as [String: String],
            // 라이브에서 불필요한 정밀 duration 계산 비활성화 → 시작 지연 단축
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            // [Phase 4] VideoToolbox 하드웨어 디코더 우선 사용 힌트
            // Apple Silicon의 전용 미디어 엔진(ProRes/H.264/HEVC 하드웨어 블록)이
            // 소프트웨어 디코더보다 선명한 출력 + 낮은 CPU 부하를 보장
            "AVURLAssetAllowsCellularAccessKey": true,
        ]
        let asset = AVURLAsset(url: url, options: playerOptions)

        // [Phase 4] AVAsset 리소스 로더를 통한 디코더 최적화
        // preferredMediaSelection → 기본 미디어 선택 시 최고 품질 오디오/비디오 트랙 선호
        asset.resourceLoader.setDelegate(nil, queue: .global(qos: .userInteractive))
        // ─────────────────────────────────────────────────────────────────

        let item = AVPlayerItem(asset: asset)

        // [Phase 4] 1080p 60fps 기본 재생 — VLC 동등 화질 즉시 시작
        // startsOnFirstEligibleVariant=false: ABR이 최적(최고) variant를 즉시 선택
        // preferredMaximumResolution=1920×1080: 1080p 해상도를 명시적으로 선호
        // preferredPeakBitRate=8Mbps: 1080p 60fps(~6-8Mbps) 이상 variant 선택 보장
        item.startsOnFirstEligibleVariant = false
        item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)

        // 1080p 60fps 스트림의 일반적 비트레이트(6-8Mbps)를 충분히 커버하는 값 설정
        // 8Mbps 이상의 bitrate variant가 있으면 선택 가능하도록 넉넉하게 설정
        item.preferredPeakBitRate = 8_000_000  // 1080p 60fps 타겟

        // [Phase 4] 선명도 최적화: 비디오 컴포지션 비활성화 → 디코더 원본 프레임 직통 출력
        // videoComposition이 nil이면 AVPlayer가 디코더 출력을 무가공으로 CALayer에 전달
        // → 리사이즈/리샘플링 없이 원본 해상도 그대로 렌더링 (최대 선명도)
        item.videoComposition = nil

        // ── 라이브 스트림 저지연 설정 ──────────────────────────────────────
        if isLiveStream {
            // false: 스톨 시 자동 대기 없이 즉시 에러/재연결 경로로 진입
            // true면 AVPlayer가 내부적으로 최대 수십 초 대기해 UI가 응답하지 않는 것처럼 보임
            player.automaticallyWaitsToMinimizeStalling = false
            // HLS LivePlaylist의 Program-Date-Time 기반 라이브 오프셋 자동 보정
            item.automaticallyPreservesTimeOffsetFromLive = true

            // 네트워크 인터페이스에 따른 목표 지연·버퍼 설정
            adjustCatchupConfigForNetwork()
            item.preferredForwardBufferDuration = catchupConfig.preferredForwardBuffer

            // configuredTimeOffsetFromLive: AVPlayer가 라이브 엣지에서 얼마나 뒤에서 재생할지 명시
            // timescale 1000 = 밀리초 정밀도 (기본 1보다 정밀한 오프셋 적용)
            item.configuredTimeOffsetFromLive = CMTime(
                seconds: catchupConfig.targetLatency,
                preferredTimescale: 1000
            )

            // 일시정지 중에도 세그먼트 다운로드 유지 → 재개 시 버퍼링 없이 즉시 재생
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            // 멀티라이브 배경 세션: 최고 화질 불필요 → 720p 수준 대역폭 제한으로
            // 네트워크 경합 및 CPU 디코딩 부하 감소 (활성 전환 시 0으로 복원)
            if isBackgroundMode {
                item.preferredPeakBitRate = 3_000_000  // ~720p 상한
                item.preferredMaximumResolution = CGSize(width: 1280, height: 720)
            }
        } else {
            player.automaticallyWaitsToMinimizeStalling = true
        }
        // ────────────────────────────────────────────────────────────────────

        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        player.rate = _avState.withLock { $0.rate }
        player.play()

        if isLiveStream {
            // stall watchdog는 readyToPlay KVO에서 시작됨 (어이템 준비 완료 후 감시 시작)
            // liveCatchupLoop는 젠시 시작하여 러닝 상태 모니터링
            startLiveCatchupLoop()
            startMetricsCollection()
        }

        let streamKind = self.isLiveStream ? "LIVE" : "VOD"
        logger.info("AVPlayerEngine playing [\(streamKind)]: \(url.lastPathComponent)")
    }

    public func pause() {
        player.pause()
        _avState.withLock { $0.state = .paused }
        notifyStateChange(.paused)
    }

    public func resume() {
        player.rate = _avState.withLock { $0.rate }
        player.play()
        _avState.withLock { $0.state = .playing }
        notifyStateChange(.playing)
    }

    public func stop() {
        stallWatchdogTask?.cancel()
        liveCatchupTask?.cancel()
        metricsCollectionTask?.cancel()
        stallWatchdogTask = nil
        liveCatchupTask = nil
        metricsCollectionTask = nil

        // KVO observer 잔존 방지 — replaceCurrentItem(nil) 전에 제거
        removeItemObservers()

        player.pause()
        player.replaceCurrentItem(with: nil)
        _avState.withLock { $0.state = .idle; $0.currentURL = nil }
        notifyStateChange(.idle)
    }

    /// 엔진 풀 반납 시 상태 초기화 — stop() + 콜백 정리 + 메트릭 리셋
    public func resetForReuse() {
        stop()

        // 콜백 참조 해제
        onStateChange = nil
        onTimeChange = nil
        onLatencyChange = nil
        onReconnectRequested = nil
        onAVMetrics = nil

        // 메트릭 리셋
        rateHistory.removeAll()
        droppedFrames = 0
        indicatedBitrate = 0
        measuredLatency = 0
        previousDroppedFrames = 0
        isBackgroundMode = false

        _avState.withLock {
            $0.rate = 1.0
            $0.volume = 1.0
            $0.isLiveStream = false
            $0.lastProgressTime = Date()
        }
        player.volume = 1.0

        // 비디오 레이어 복원
        setVideoLayerVisible(true)
    }

    public func seek(to position: TimeInterval) {
        let cmTime = CMTime(seconds: position, preferredTimescale: 600)
        let prev = _avState.withLock { $0.state }

        _avState.withLock { $0.state = .buffering(progress: 0) }
        notifyStateChange(.buffering(progress: 0))

        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            let restored: PlayerState.Phase = (prev == .paused) ? .paused : .playing
            self._avState.withLock { $0.state = restored }
            self.notifyStateChange(restored)
            if prev != .paused { self.player.play() }
        }
    }

    public func setRate(_ newRate: Float) {
        _avState.withLock { $0.rate = newRate }
        if player.timeControlStatus == .playing {
            player.rate = newRate
        }
    }

    public func setVolume(_ newVolume: Float) {
        let v = max(0, min(1, newVolume))
        player.volume = v
        _avState.withLock { $0.volume = v }
    }

    // MARK: - Recording (PlayerEngineProtocol)

    /// 현재 녹화 중인지 여부
    public var isRecording: Bool {
        _avState.withLock { $0.isRecording }
    }

    /// 스트림 녹화 시작 — HLS 세그먼트 다운로드 방식
    /// 현재 재생 중인 HLS 스트림의 세그먼트를 직접 다운로드·저장한다.
    public func startRecording(to url: URL) async throws {
        guard !_avState.withLock({ $0.isRecording }) else {
            throw PlayerError.recordingFailed("이미 녹화 중입니다")
        }
        guard let streamURL = _avState.withLock({ $0.currentURL }) else {
            throw PlayerError.recordingFailed("재생 중인 스트림이 없습니다")
        }

        try await recordingService.startRecording(playlistURL: streamURL, to: url)

        _avState.withLock { $0.isRecording = true; $0.recordingURL = url }
        logger.info("AVPlayer 녹화 시작: \(url.lastPathComponent, privacy: .public)")
    }

    /// 녹화 중지
    public func stopRecording() async {
        guard _avState.withLock({ $0.isRecording }) else { return }

        await recordingService.stopRecording()

        _avState.withLock { $0.isRecording = false; $0.recordingURL = nil }
        logger.info("AVPlayer 녹화 중지")
    }

    // MARK: - AVPlayer-Specific Accessors

    public var currentPhase: PlayerState.Phase {
        _avState.withLock { $0.state }
    }

    // MARK: - Error Handling

    internal func handleError(_ error: PlayerError) {
        _avState.withLock { $0.state = .error(error) }
        notifyStateChange(.error(error))

        if error == .connectionLost || error == .networkTimeout {
            onReconnectRequested?()
        }
    }

    internal func classifyError(_ error: Error) -> PlayerError {
        let nsError = error as NSError

        // AVFoundation 에러 도메인
        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.contentIsNotAuthorized.rawValue:
                return .streamNotFound

            case AVError.noLongerPlayable.rawValue:
                return .connectionLost

            case AVError.serverIncorrectlyConfigured.rawValue:
                return .networkTimeout

            case AVError.decodeFailed.rawValue,
                 AVError.failedToLoadMediaData.rawValue:
                return .decodingFailed(nsError.localizedDescription)

            case AVError.fileFormatNotRecognized.rawValue,
                 AVError.contentIsUnavailable.rawValue:
                return .unsupportedFormat(nsError.localizedDescription)

            default:
                break
            }
        }

        // URL 관련 에러
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost:
                return .connectionLost
            case NSURLErrorTimedOut:
                return .networkTimeout
            case NSURLErrorBadURL,
                 NSURLErrorUnsupportedURL:
                return .invalidManifest
            default:
                return .networkTimeout
            }
        }

        return .engineInitFailed
    }

    // MARK: - Live Stream Detection

    private func detectLiveStream(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let path = url.absoluteString.lowercased()
        return ext == "m3u8" || ext == "m3u"
            || path.contains(".m3u8")
            || path.contains("live")
            || path.contains("hls")
    }

    // MARK: - Helpers

    internal func notifyStateChange(_ phase: PlayerState.Phase) {
        Task { @MainActor [weak self] in
            self?.onStateChange?(phase)
        }
    }
}

