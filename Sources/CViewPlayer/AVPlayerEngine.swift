// MARK: - AVPlayerEngine.swift
// CViewPlayer - AVPlayer 기반 라이브 스트림 재생 엔진 (고도화)
// Reference: chzzkView-v1/HLSNativePlayer, StreamReconnectionManager, EnhancedErrorRecoverySystem

import Foundation
import AVFoundation
import Network
import AppKit
import CoreVideo   // CVDisplayLink
import QuartzCore  // CATransaction
import CViewCore

// MARK: - Video Rendering View

/// AVPlayerLayer를 소유하는 경량 NSView.
/// PlayerContainerView가 이 view를 subview로 추가하는 게 아니라
/// playerLayer를 직접 sublayer로 삽입하여 GPU compositing 레이어 1개 감소.
/// - 이 NSView 자체는 화면에 표시되지 않으므로 drawRect/redraw 완전 차단.
final class AVPlayerLayerView: NSView, @unchecked Sendable {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // backing store 생성은 하지만 화면 그리기에 관여하지 않음
        wantsLayer = true
        layer = playerLayer
        layerContentsRedrawPolicy = .never  // NSView drawRect 코드패스 완전 제거

        playerLayer.videoGravity   = .resizeAspect
        playerLayer.drawsAsynchronously = true // Metal async 렌더링 (GPU thread)
        playerLayer.isOpaque       = true      // 알파 블렌딩 없음 → GPU 부하 감소
        playerLayer.shouldRasterize = false    // 매 프레임 변경되므로 캐시 불필요
        playerLayer.allowsGroupOpacity = false // compositing group pass 제거

        // Retina 디스플레이 대응 — contentsScale을 backingScaleFactor에 맞춤
        // 미설정 시 1x로 렌더링 후 2x로 업스케일되어 흐릿해짐
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        playerLayer.contentsScale = scale
        
        // 스케일링 시 선명도 향상 — trilinear 필터링
        playerLayer.magnificationFilter = .trilinear
        playerLayer.minificationFilter  = .trilinear

        // 이 레이어의 모든 암묵적 애니메이션 비활성화
        playerLayer.actions = [
            "position":   NSNull(),
            "bounds":     NSNull(),
            "frame":      NSNull(),
            "contents":   NSNull(),
            "opacity":    NSNull(),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(player: AVPlayer) {
        playerLayer.player = player
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 윈도우 이동/스크린 변경 시 contentsScale 자동 업데이트
        if let scale = window?.backingScaleFactor {
            playerLayer.contentsScale = scale
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Live Catchup Configuration

/// 라이브 스트림 저지연 캐치업 설정
public struct AVLiveCatchupConfig: Sendable {
    /// 목표 지연 시간 (초)
    public var targetLatency: Double
    /// 최대 허용 지연 시간 (초) — 초과 시 캐치업 시작
    public var maxLatency: Double
    /// 최대 캐치업 재생 속도
    public var maxCatchupRate: Float
    /// 버퍼 전진 지속 시간 (초)
    public var preferredForwardBuffer: Double

    public static let lowLatency = AVLiveCatchupConfig(
        targetLatency: 3.0, maxLatency: 8.0,
        maxCatchupRate: 1.5, preferredForwardBuffer: 4.0
    )
    public static let balanced = AVLiveCatchupConfig(
        targetLatency: 6.0, maxLatency: 15.0,
        maxCatchupRate: 1.25, preferredForwardBuffer: 8.0
    )
    public static let stable = AVLiveCatchupConfig(
        targetLatency: 10.0, maxLatency: 25.0,
        maxCatchupRate: 1.1, preferredForwardBuffer: 15.0
    )

    public init(targetLatency: Double, maxLatency: Double,
                maxCatchupRate: Float, preferredForwardBuffer: Double) {
        self.targetLatency = targetLatency
        self.maxLatency = maxLatency
        self.maxCatchupRate = maxCatchupRate
        self.preferredForwardBuffer = preferredForwardBuffer
    }
}

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
    /// lock 보호: 네트워크 모니터 콜백/메인 스레드에서 동시 접근
    public var catchupConfig: AVLiveCatchupConfig {
        get { lock.withLock { _catchupConfig } }
        set { lock.withLock { _catchupConfig = newValue } }
    }
    private var _catchupConfig: AVLiveCatchupConfig = .lowLatency

    /// State change callback
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?
    /// Time change callback (currentTime, duration)
    public var onTimeChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?
    /// Latency change callback (latency in seconds)
    public var onLatencyChange: (@Sendable (Double) -> Void)?
    /// Reconnection requested callback
    public var onReconnectRequested: (@Sendable () -> Void)?

    // MARK: - PlayerEngineProtocol Properties

    public var isPlaying: Bool {
        lock.withLock { _state == .playing }
    }

    public var isInErrorState: Bool {
        lock.withLock {
            if case .error = _state { return true }
            return false
        }
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
        lock.withLock { _rate }
    }

    public var videoView: NSView { _videoView }

    // MARK: - Private State

    private let lock = NSLock()
    private var _state: PlayerState.Phase = .idle
    private var _rate: Float = 1.0
    private var _volume: Float = 1.0
    private var _currentURL: URL?

    private let _videoView: AVPlayerLayerView
    private let logger = AppLogger.player

    // MARK: - KVO / Observers

    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var bufferKeepUpObservation: NSKeyValueObservation?  // isPlaybackLikelyToKeepUp
    private var bufferFullObservation: NSKeyValueObservation?    // isPlaybackBufferFull
    private var timeObserver: Any?
    private var stallObservation: NSObjectProtocol?
    private var bufferObservation: NSObjectProtocol?
    private var accessLogObservation: NSObjectProtocol?          // AVPlayerItemNewAccessLogEntry
    private var liveOffsetObservation: NSObjectProtocol?         // RecommendedTimeOffsetFromLive

    // MARK: - Live Stream State

    /// lock 보호: play()/KVO/networkMonitor에서 동시 접근
    private var isLiveStream: Bool {
        get { lock.withLock { _isLiveStream } }
        set { lock.withLock { _isLiveStream = newValue } }
    }
    private var _isLiveStream: Bool = false
    private var stallWatchdogTask: Task<Void, Never>?
    private var liveCatchupTask: Task<Void, Never>?
    /// lock 보호: KVO/watchdog/networkMonitor에서 동시 접근
    private var lastProgressTime: Date {
        get { lock.withLock { _lastProgressTime } }
        set { lock.withLock { _lastProgressTime = newValue } }
    }
    private var _lastProgressTime: Date = Date()
    /// 최근 캐치업 속도 히스토리 — 급격한 속도 변화 스무딩용 (최대 4개)
    private var rateHistory: [Float] = []
    /// 현재 측정 지연 시간 (초) — AccessLog/Catchup 공유
    private var measuredLatency: Double = 0
    /// AccessLog 기반 추정 비트레이트 (bps)
    private(set) var indicatedBitrate: Double = 0
    /// AccessLog 기반 드롭 프레임 수 누적
    private(set) var droppedFrames: Int = 0

    // MARK: - Network Monitor

    private let networkMonitor = NWPathMonitor()
    private var currentNetworkType: NWInterface.InterfaceType = .wifi
    private var networkQueue = DispatchQueue(label: "av.engine.network")

    // MARK: - Recording

    private var _isRecording: Bool = false
    private var _recordingURL: URL?
    private let recordingService = StreamRecordingService()

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

        lock.withLock {
            _currentURL = url
            _state = .loading
        }
        notifyStateChange(.loading)

        // 속도 스무딩 히스토리 초기화
        rateHistory.removeAll()
        droppedFrames = 0
        indicatedBitrate = 0
        measuredLatency = 0

        isLiveStream = detectLiveStream(url: url)

        // ── Metal 최적 Asset 설정 ─────────────────────────────────────────
        let playerOptions: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0",
                // LLHLS 지원 서버에 저지연 세그먼트 힌트 전달
                "Accept": "application/vnd.apple.mpegurl, application/x-mpegURL, audio/mpegurl, */*"
            ] as [String: String],
            // 라이브에서 불필요한 정밀 duration 계산 비활성화 → 시작 지연 단축
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ]
        let asset = AVURLAsset(url: url, options: playerOptions)
        // ─────────────────────────────────────────────────────────────────

        let item = AVPlayerItem(asset: asset)

        // ── 화면 해상도 기반 ABR 최적화 ───────────────────────────────────
        // 전체 화면 크기 × Retina 스케일 기준 — visibleFrame 대신 frame 사용하여
        // 메뉴바/독 영역까지 포함한 최대 해상도 스트림 선택 허용
        if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            let size  = screen.frame.size
            item.preferredMaximumResolution = CGSize(
                width:  size.width  * scale,
                height: size.height * scale
            )
        }
        // 싱글 재생 시 비트레이트 무제한 — 최고 화질 variant 빠르게 선택
        item.preferredPeakBitRate = 0
        // macOS 14+: 첫 번째 적합 variant 즉시 재생 → 초기 버퍼링 시간 단축
        if #available(macOS 14.0, *) {
            item.startsOnFirstEligibleVariant = true
        }
        // ─────────────────────────────────────────────────────────────────

        // ── 라이브 스트림 저지연 설정 ──────────────────────────────────────
        if isLiveStream {
            // 스톨이 발생해도 자동으로 기다리지 않음 → 즉각적인 에러/재연결 처리
            player.automaticallyWaitsToMinimizeStalling = false
            // 라이브 세션 중 CMTime 오프셋 자동 보정 — 네트워크 지터 보상
            item.automaticallyPreservesTimeOffsetFromLive = true

            // 네트워크 품질에 따른 목표 지연 시간 설정
            adjustCatchupConfigForNetwork()
            item.preferredForwardBufferDuration = catchupConfig.preferredForwardBuffer

            // macOS 12+: 라이브 엣지로부터의 오프셋 설정
            item.configuredTimeOffsetFromLive = CMTime(
                seconds: catchupConfig.targetLatency,
                preferredTimescale: 1
            )
        } else {
            player.automaticallyWaitsToMinimizeStalling = true
        }
        // ────────────────────────────────────────────────────────────────────

        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        player.rate = lock.withLock { _rate }
        player.play()

        if isLiveStream {
            startStallWatchdog()
            startLiveCatchupLoop()
        }

        let streamKind = self.isLiveStream ? "LIVE" : "VOD"
        logger.info("AVPlayerEngine playing [\(streamKind)]: \(url.lastPathComponent)")
    }

    public func pause() {
        player.pause()
        lock.withLock { _state = .paused }
        notifyStateChange(.paused)
    }

    public func resume() {
        player.rate = lock.withLock { _rate }
        player.play()
        lock.withLock { _state = .playing }
        notifyStateChange(.playing)
    }

    public func stop() {
        stallWatchdogTask?.cancel()
        liveCatchupTask?.cancel()
        stallWatchdogTask = nil
        liveCatchupTask = nil

        // KVO observer 잔존 방지 — replaceCurrentItem(nil) 전에 제거
        removeItemObservers()

        player.pause()
        player.replaceCurrentItem(with: nil)
        lock.withLock {
            _state = .idle
            _currentURL = nil
        }
        notifyStateChange(.idle)
    }

    public func seek(to position: TimeInterval) {
        let cmTime = CMTime(seconds: position, preferredTimescale: 600)
        let prev = lock.withLock { _state }

        lock.withLock { _state = .buffering(progress: 0) }
        notifyStateChange(.buffering(progress: 0))

        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            let restored: PlayerState.Phase = (prev == .paused) ? .paused : .playing
            self.lock.withLock { self._state = restored }
            self.notifyStateChange(restored)
            if prev != .paused { self.player.play() }
        }
    }

    public func setRate(_ newRate: Float) {
        lock.withLock { _rate = newRate }
        if player.timeControlStatus == .playing {
            player.rate = newRate
        }
    }

    public func setVolume(_ newVolume: Float) {
        let v = max(0, min(1, newVolume))
        player.volume = v
        lock.withLock { _volume = v }
    }

    // MARK: - Recording (PlayerEngineProtocol)

    /// 현재 녹화 중인지 여부
    public var isRecording: Bool {
        lock.withLock { _isRecording }
    }

    /// 스트림 녹화 시작 — HLS 세그먼트 다운로드 방식
    /// 현재 재생 중인 HLS 스트림의 세그먼트를 직접 다운로드·저장한다.
    public func startRecording(to url: URL) async throws {
        guard !lock.withLock({ _isRecording }) else {
            throw PlayerError.recordingFailed("이미 녹화 중입니다")
        }
        guard let streamURL = lock.withLock({ _currentURL }) else {
            throw PlayerError.recordingFailed("재생 중인 스트림이 없습니다")
        }

        try await recordingService.startRecording(playlistURL: streamURL, to: url)

        lock.withLock {
            _isRecording = true
            _recordingURL = url
        }
        logger.info("AVPlayer 녹화 시작: \(url.lastPathComponent, privacy: .public)")
    }

    /// 녹화 중지
    public func stopRecording() async {
        guard lock.withLock({ _isRecording }) else { return }

        await recordingService.stopRecording()

        lock.withLock {
            _isRecording = false
            _recordingURL = nil
        }
        logger.info("AVPlayer 녹화 중지")
    }

    // MARK: - AVPlayer-Specific Accessors

    public var currentPhase: PlayerState.Phase {
        lock.withLock { _state }
    }

    // MARK: - Stall Watchdog

    /// 스마트 스톨 워치독:
    /// 1) 12초 무진행: 재연결 요청
    /// 2) 버퍼 고갈(isPlaybackLikelyToKeepUp=false): 연속 7회 → 재연결 요청
    /// 3) 장시간 재생 안정성: 워치독이 재연결 후에도 영구 종료되지 않고 계속 감시
    /// 4) 연속 재연결 실패 보호: 5분 내 3회 이상 재연결 시 에러 상태 전환
    private var recentReconnectTimestamps: [Date] = []
    private let maxReconnectsInWindow = 3
    private let reconnectWindowSeconds: TimeInterval = 300 // 5분

    private func startStallWatchdog() {
        let kStallTimeout: TimeInterval = 12.0
        let kCheckInterval: UInt64 = 3_000_000_000 // 3초

        stallWatchdogTask?.cancel()
        lastProgressTime = Date()
        recentReconnectTimestamps.removeAll()

        stallWatchdogTask = Task { [weak self] in
            var bufferStallCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: kCheckInterval)
                guard let self, !Task.isCancelled else { return }

                let phase = self.lock.withLock { self._state }

                // idle/ended/error 상태에서는 감시 일시 중지 (루프는 유지)
                if phase == .idle || phase == .ended {
                    bufferStallCount = 0
                    continue
                }
                if case .error = phase {
                    bufferStallCount = 0
                    continue
                }

                guard phase == .playing || phase == .buffering(progress: 0) else {
                    bufferStallCount = 0
                    continue
                }

                let elapsed = Date().timeIntervalSince(self.lastProgressTime)

                // 버퍼 부족 + 장시간 스톨 → 재연결
                let keepUp = player.currentItem?.isPlaybackLikelyToKeepUp ?? true
                if !keepUp { bufferStallCount += 1 } else { bufferStallCount = 0 }

                if elapsed >= kStallTimeout || bufferStallCount >= 7 {
                    self.logger.warning(
                        "AVPlayerEngine: stall watchdog — elapsed=\(Int(elapsed))s bufferStalls=\(bufferStallCount)"
                    )

                    // 연속 재연결 실패 보호: 5분 내 maxReconnectsInWindow회 초과 시 에러 전환
                    let now = Date()
                    self.recentReconnectTimestamps.append(now)
                    self.recentReconnectTimestamps.removeAll {
                        now.timeIntervalSince($0) > self.reconnectWindowSeconds
                    }

                    if self.recentReconnectTimestamps.count > self.maxReconnectsInWindow {
                        self.logger.error(
                            "AVPlayerEngine: \(self.maxReconnectsInWindow)+ reconnects in \(Int(self.reconnectWindowSeconds))s — giving up"
                        )
                        self.handleError(.connectionLost)
                        return // 워치독 종료 (복구 불가 상태)
                    }

                    // 재연결 요청 후 카운터 리셋, 루프 계속
                    bufferStallCount = 0
                    self.lastProgressTime = Date()
                    self.handleError(.connectionLost)
                    // 재연결 완료 대기 (15초) — play()가 다시 호출될 때까지 대기
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    continue
                }
            }
        }
    }

    // MARK: - Live Catchup Loop

    /// 1초마다 지연 측정 → 스무딩된 속도 조정
    /// - 급격한 속도 변화를 방지하기 위해 최근 4개 측정값의 EMA 사용
    /// - latency > maxLatency: 라이브 엣지로 즉시 점프 후 offset 재설정
    private func startLiveCatchupLoop() {
        let kCheckInterval: UInt64 = 1_000_000_000 // 1초

        liveCatchupTask?.cancel()
        liveCatchupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: kCheckInterval)
                guard let self, !Task.isCancelled else { return }
                await MainActor.run { self.adjustPlaybackRateForLatency() }
            }
        }
    }

    @MainActor
    private func adjustPlaybackRateForLatency() {
        guard let item = player.currentItem,
              let seekRange = item.seekableTimeRanges.last?.timeRangeValue,
              player.timeControlStatus == .playing else { return }

        let liveEdge  = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
        let currentPos = CMTimeGetSeconds(player.currentTime())
        guard liveEdge.isFinite, currentPos.isFinite, liveEdge > 0 else { return }

        let latency = max(0, liveEdge - currentPos)
        measuredLatency = latency
        onLatencyChange?(latency)

        let cfg = catchupConfig

        // ── 지연 과다: 라이브 엣지 바로 앞으로 점프 ──────────────────────
        if latency > cfg.maxLatency {
            let target = max(0, liveEdge - cfg.targetLatency)
            logger.info("AVPlayerEngine: latency \(String(format: "%.1f", latency))s > max → snap to live edge")
            seek(to: target)
            rateHistory.removeAll()
            return
        }

        // ── 지연 정상 범위: 스무딩된 속도 계산 ───────────────────────────
        let targetRate: Float
        if latency > cfg.targetLatency {
            // 0~1로 정규화한 ratio → 로그 곡선으로 완만하게 가속
            let ratio = min((latency - cfg.targetLatency) / (cfg.maxLatency - cfg.targetLatency), 1.0)
            let curved = Float(1.0 - cos(ratio * .pi / 2))    // 코사인 이징
            targetRate = 1.0 + curved * (cfg.maxCatchupRate - 1.0)
        } else if latency < cfg.targetLatency * 0.6 {
            targetRate = 1.0   // 지연이 목표보다 훨씬 낮으면 정상 속도 복구
        } else {
            return // 목표 범위 내 → 아무것도 하지 않음
        }

        // EMA 스무딩 (α=0.4): 빠른 반응이면서 급격한 변화는 완충
        let alpha: Float = 0.4
        let last = rateHistory.last ?? player.rate
        let smoothed = alpha * targetRate + (1 - alpha) * last

        rateHistory.append(smoothed)
        if rateHistory.count > 4 { rateHistory.removeFirst() }

        // 0.03 미만 변화는 무시해서 불필요한 API 호출 제거
        if abs(player.rate - smoothed) > 0.03 {
            player.rate = smoothed
        }
    }

    // MARK: - Network Monitor

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previousType = self.currentNetworkType
            
            if path.usesInterfaceType(.wiredEthernet) {
                self.currentNetworkType = .wiredEthernet
            } else if path.usesInterfaceType(.wifi) {
                self.currentNetworkType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.currentNetworkType = .cellular
            } else {
                self.currentNetworkType = .other
            }
            
            // 네트워크 인터페이스 변경 시 자동 대응
            if previousType != self.currentNetworkType {
                self.logger.info("AVPlayerEngine: 네트워크 전환 \(String(describing: previousType)) → \(String(describing: self.currentNetworkType))")
                
                // 연결 상실 시 즉시 재연결 요청
                if path.status != .satisfied {
                    self.logger.warning("AVPlayerEngine: 네트워크 연결 해제 감지 — 재연결 대기")
                    return
                }
                
                // 라이브 스트림에서만 캐치업 설정 재조정
                let isLive = self.isLiveStream
                if isLive {
                    self.adjustCatchupConfigForNetwork()
                    
                    // 현재 재생 중인 아이템의 버퍼 설정 즉시 업데이트
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let item = self.player.currentItem else { return }
                        item.preferredForwardBufferDuration = self.catchupConfig.preferredForwardBuffer
                        self.logger.info("AVPlayerEngine: 버퍼 설정 업데이트 — target=\(self.catchupConfig.targetLatency)s max=\(self.catchupConfig.maxLatency)s buffer=\(self.catchupConfig.preferredForwardBuffer)s")
                    }
                }
                
                // 스톨 워치독 타임스탬프 갱신 — 전환 순간의 일시 정지를 스톨로 오인 방지
                self.lastProgressTime = Date()
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    /// 네트워크 인터페이스에 따라 목표 지연 시간 조정
    private func adjustCatchupConfigForNetwork() {
        switch currentNetworkType {
        case .wiredEthernet:
            catchupConfig.targetLatency = 2.0
            catchupConfig.maxLatency = 6.0
        case .wifi:
            catchupConfig.targetLatency = 3.0
            catchupConfig.maxLatency = 8.0
        case .cellular:
            catchupConfig.targetLatency = 6.0
            catchupConfig.maxLatency = 15.0
        default:
            catchupConfig.targetLatency = 4.0
            catchupConfig.maxLatency = 10.0
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: PlayerError) {
        lock.withLock { _state = .error(error) }
        notifyStateChange(.error(error))

        if error == .connectionLost || error == .networkTimeout {
            onReconnectRequested?()
        }
    }

    /// AVFoundation 에러를 PlayerError로 분류
    private func classifyError(_ error: Error) -> PlayerError {
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

    // MARK: - KVO Setup

    private func setupObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            let phase: PlayerState.Phase
            switch player.timeControlStatus {
            case .playing:
                // 재생 중 타임스탬프 갱신 (스톨 워치독용)
                self.lastProgressTime = Date()
                phase = .playing
            case .paused:
                let cur = self.lock.withLock { self._state }
                if cur == .loading || cur == .idle { return }
                phase = .paused
            case .waitingToPlayAtSpecifiedRate:
                phase = .buffering(progress: 0)
            @unknown default:
                return
            }
            self.lock.withLock { self._state = phase }
            self.notifyStateChange(phase)
        }

        // 1초 간격: 0.5s에서 완화 → 4세션 기준 @Observable 업데이트 8→4회/초 감소
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let cur = CMTimeGetSeconds(time)
            let dur = self.duration
            if cur.isFinite {
                self.lastProgressTime = Date()
                self.onTimeChange?(cur, dur)
            }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        removeItemObservers()

        // ── 아이템 상태 KVO ───────────────────────────────────────────
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.lock.withLock { self._state = .playing }
                self.notifyStateChange(.playing)
                self.logger.info("AVPlayerEngine: readyToPlay")

            case .failed:
                // ErrorLog에서 세부 원인 추출 코드 포함
                if let errLog = item.errorLog()?.events.last {
                    self.logger.error(
                        "AVPlayerEngine: item failed uri=\(errLog.uri ?? "-") statusCode=\(errLog.errorStatusCode)"
                    )
                }
                let err = item.error.map { self.classifyError($0) } ?? .engineInitFailed
                self.lock.withLock { self._state = .error(err) }
                self.notifyStateChange(.error(err))
                self.logger.error("AVPlayerEngine: item failed — \(item.error?.localizedDescription ?? "?")")

            case .unknown:
                break
            @unknown default:
                break
            }
        }

        // ── 버퍼 fullness KVO — 재생 가능성 변화 확인 ────────────────
        bufferKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.isPlaybackLikelyToKeepUp {
                // 버퍼 회복 → 일시정지 상태에서 자동 재개
                let phase = self.lock.withLock { self._state }
                if case .buffering = phase {
                    self.lock.withLock { self._state = .playing }
                    self.notifyStateChange(.playing)
                    DispatchQueue.main.async { [weak self] in
                        self?.player.play()
                    }
                }
            }
        }
        bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackBufferFull else { return }
            // 버퍼 완전 충전 → 스톨 타임스템프 갱신 (워치독 리셋)
            self.lastProgressTime = Date()
        }

        // ── Notification: 스톨 / 종료 / AccessLog ──────────────────────
        stallObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logger.warning("AVPlayerEngine: playback stalled")
            self.lock.withLock { self._state = .buffering(progress: 0) }
            self.notifyStateChange(.buffering(progress: 0))
            // 스톨 복구: 2초 후 자동 play() 재시도
            // AVPlayer는 버퍼가 충분히 쌓이면 자동 재개하지 않는 경우가 있음
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false
                if keepUp && self.player.timeControlStatus != .playing {
                    self.logger.info("AVPlayerEngine: stall recovery — buffer ready, resuming play")
                    self.player.play()
                    self.lastProgressTime = Date()
                }
            }
        }

        bufferObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self._state = .ended }
            self.notifyStateChange(.ended)
        }

        // AccessLog: 드롭 프레임, 비트레이트, 스트리밍 정보 모니터링
        // + 주기적 AccessLog 정리 — 장시간 재생 시 이벤트 무한 축적 방지
        accessLogObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  let log = self.player.currentItem?.accessLog(),
                  let entry = log.events.last else { return }

            if entry.indicatedBitrate > 0 {
                self.indicatedBitrate = entry.indicatedBitrate
            }
            let newDropped = entry.numberOfDroppedVideoFrames
            if newDropped > self.droppedFrames {
                let diff = newDropped - self.droppedFrames
                self.droppedFrames = newDropped
                if diff > 5 {
                    self.logger.warning(
                        "AVPlayerEngine: \(diff) frames dropped (total=\(newDropped)) bitrate=\(Int(entry.indicatedBitrate / 1000))kbps"
                    )
                }
            }
            
            // AccessLog 이벤트 수가 과다하면 경고 (AVPlayerItem은 자체 정리 불가)
            // 10분 이상 재생 시 수백 개의 이벤트가 쌓일 수 있음
            let eventCount = log.events.count
            if eventCount > 500 && eventCount % 100 == 0 {
                self.logger.warning(
                    "AVPlayerEngine: AccessLog events accumulating: \(eventCount) entries (memory concern for long playback)"
                )
            }
        }
    }

    private func removeItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        bufferKeepUpObservation?.invalidate()
        bufferKeepUpObservation = nil
        bufferFullObservation?.invalidate()
        bufferFullObservation = nil
        for obs in [stallObservation, bufferObservation, accessLogObservation, liveOffsetObservation].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
        stallObservation = nil
        bufferObservation = nil
        accessLogObservation = nil
        liveOffsetObservation = nil
    }

    private func removeObservers() {
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        removeItemObservers()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Helpers

    private func notifyStateChange(_ phase: PlayerState.Phase) {
        if Thread.isMainThread {
            onStateChange?(phase)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(phase)
            }
        }
    }
}

