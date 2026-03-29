// MARK: - PlayerViewModel.swift
// CViewApp — 재작성된 Player ViewModel
// @Observable ViewModel + StreamCoordinator 아키텍처

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Player ViewModel

@Observable
@MainActor
public final class PlayerViewModel {

    // MARK: - Constants

    static let maxLatencyHistory = 60

    // MARK: - 재생 상태

    public var streamPhase: StreamCoordinator.StreamPhase = .idle
    public var currentQuality: StreamQualityInfo?
    public var availableQualities: [StreamQualityInfo] = []
    public var latencyInfo: LatencyInfo?
    public var latencyHistory: [LatencyDataPoint] = []
    public var bufferHealth: BufferHealth?
    public var playbackRate: Double = 1.0
    public var volume: Float = 1.0
    public var isMuted = false
    public var isFullscreen = false
    public var isAudioOnly = false
    public var showControls = true
    public var errorMessage: String?
    public var isLiveStream: Bool = true

    // MARK: - 네트워크 메트릭

    public var latestMetrics: VLCLiveMetrics?
    public var showNetworkMetrics: Bool = false

    // MARK: - 녹화 상태

    public var isRecording: Bool = false
    public var recordingDuration: TimeInterval = 0
    public var recordingURL: URL?
    var recordingTimerTask: Task<Void, Never>?

    // MARK: - 스트림 메타정보

    public var channelName: String = ""
    public var liveTitle: String = ""
    public var thumbnailURL: URL?
    public var viewerCount: Int = 0
    public var uptime: TimeInterval = 0
    public private(set) var currentChannelId: String?

    // MARK: - 의존성

    var streamCoordinator: StreamCoordinator?
    public private(set) var playerEngine: (any PlayerEngineProtocol)?
    private var isPreallocated: Bool
    public var isMultiLive: Bool = false
    var eventTask: Task<Void, Never>?
    private var controlHideTask: Task<Void, Never>?
    var uptimeTask: Task<Void, Never>?
    /// VLC 버퍼링 디바운스: 재생 중 순간적인 버퍼링 상태 변경은 무시하고
    /// 일정 시간 이상 지속될 때만 UI에 반영
    var _bufferingDebounceTask: Task<Void, Never>?
    /// 안티플리커: 마지막으로 .playing 전환된 시각 (쿨다운 기준)
    /// playing 진입 후 일정 시간 동안은 버퍼링 전환을 억제하여 깜빡임 방지
    var _lastPlayingTime: Date?
    /// [Freeze Fix] drawable 재바인딩 Task 추적
    var _refreshDrawableTask: Task<Void, Never>?
    let logger = AppLogger.player

    public var onPlaybackStateChanged: (() -> Void)?
    
    /// 방송 종료 여부 확인 콜백 — 재연결 시 API 호출로 라이브 상태 확인
    public var onCheckStreamEnded: (@Sendable () async -> Bool)?

    // MARK: - 엔진 선택

    public var preferredEngineType: PlayerEngineType = .avPlayer
    public private(set) var currentEngineType: PlayerEngineType = .avPlayer

    // MARK: - VLC 고급 설정 (Observable 상태)

    public var isEqualizerEnabled: Bool = false
    public var equalizerPresetName: String = ""
    public var equalizerPreAmp: Float = 0
    public var equalizerBands: [Float] = []

    public var isVideoAdjustEnabled: Bool = false
    public var videoBrightness: Float = 1.0
    public var videoContrast: Float = 1.0
    public var videoSaturation: Float = 1.0
    public var videoHue: Float = 0
    public var videoGamma: Float = 1.0

    public var aspectRatio: String? = nil
    public var audioStereoMode: UInt = 0
    public var audioMixMode: UInt32 = 0
    public var audioDelay: Int = 0

    public var subtitleTracks: [(Int, String)] = []
    public var selectedSubtitleTrack: Int = -1
    public var subtitleDelay: Int = 0
    public var subtitleFontScale: Float = 100

    // MARK: - Init

    public init(engineType: PlayerEngineType = .avPlayer, isPreallocated: Bool = false) {
        self.preferredEngineType = engineType
        self.currentEngineType = engineType
        self.isPreallocated = isPreallocated
    }

    /// 외부에서 미리 생성된 엔진 주입 (멀티라이브 엔진 풀용)
    public func injectEngine(_ engine: any PlayerEngineProtocol) {
        self.playerEngine = engine
        self.isPreallocated = true
        if let vlc = engine as? VLCPlayerEngine {
            self.currentEngineType = .vlc
            vlc.streamingProfile = .multiLive
        } else {
            self.currentEngineType = .avPlayer
        }
    }

    /// 주입된 엔진 분리 (풀 반환용) — 엔진 참조만 해제, stop은 호출하지 않음
    public func detachEngine() -> (any PlayerEngineProtocol)? {
        let engine = playerEngine
        playerEngine = nil
        isPreallocated = false
        return engine
    }

    /// 엔진 팩토리
    private static func makeEngine(type: PlayerEngineType) -> any PlayerEngineProtocol {
        switch type {
        case .vlc:
            let e = VLCPlayerEngine()
            e.streamingProfile = .lowLatency
            return e
        case .avPlayer:
            let e = AVPlayerEngine()
            e.catchupConfig = .lowLatency
            return e
        }
    }

    // MARK: - VLC 메트릭 콜백

    public func setVLCMetricsCallback(_ callback: (@Sendable (VLCLiveMetrics) -> Void)?) {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        if let callback = callback {
            let coordinator = self.streamCoordinator
            vlc.onVLCMetrics = { [weak coordinator] metrics in
                callback(metrics)
                if metrics.networkBytesPerSec > 0 {
                    let bytes = Int(metrics.networkBytesPerSec * 2)
                    Task { await coordinator?.recordBandwidthSample(bytesLoaded: bytes, duration: 2.0) }
                }
            }
        } else {
            vlc.onVLCMetrics = nil
        }
    }

    // MARK: - AVPlayer 메트릭 콜백

    public func setAVPlayerMetricsCallback(_ callback: (@Sendable (AVPlayerLiveMetrics) -> Void)?) {
        guard let avEngine = playerEngine as? AVPlayerEngine else { return }
        if let callback = callback {
            avEngine.onAVMetrics = { metrics in
                callback(metrics)
            }
        } else {
            avEngine.onAVMetrics = nil
        }
    }

    /// 싱글 플레이어 네트워크 탭용 자체 메트릭 수집 활성화
    public func enableSelfMetrics(_ enabled: Bool) {
        showNetworkMetrics = enabled
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        if enabled {
            let coordinator = self.streamCoordinator
            vlc.onVLCMetrics = { [weak self, weak coordinator] metrics in
                Task { @MainActor in
                    self?.latestMetrics = metrics
                }
                if metrics.networkBytesPerSec > 0 {
                    let bytes = Int(metrics.networkBytesPerSec * 2)
                    Task { await coordinator?.recordBandwidthSample(bytesLoaded: bytes, duration: 2.0) }
                }
            }
        } else {
            vlc.onVLCMetrics = nil
            latestMetrics = nil
        }
    }

    // MARK: - 설정 적용

    /// 서버 동기화 추천에 따른 재생 속도 적용
    /// MetricsForwarder 콜백에서 호출 (백그라운드 스레드 → Main Actor)
    public func applySyncSpeed(_ speed: Float) {
        Task { @MainActor [weak self] in
            guard let self, let engine = self.playerEngine else { return }
            // 동기화 속도는 0.95~1.05 범위 내에서만 적용 (안전 범위)
            let clamped = max(0.95, min(1.05, speed))
            engine.setRate(clamped)
        }
    }

    public func applySettings(volume: Float, lowLatency: Bool, catchupRate: Double) {
        self.volume = volume
        playerEngine?.setVolume(isMuted ? 0 : volume)
        // multiLive 프로파일은 MultiLiveManager가 injectEngine()으로 설정하므로
        // lowLatency 설정이 활성화되어도 multiLive를 덮어쓰지 않는다.
        // multiLive 세션에서 lowLatency로 변경하면 재연결 시 잘못된 VLC 옵션이 적용됨.
        if lowLatency {
            if let vlc = playerEngine as? VLCPlayerEngine,
               vlc.streamingProfile != .multiLive {
                vlc.streamingProfile = .lowLatency
            }
        }
    }

    /// PlayerSettings의 레이턴시 필드 → LowLatencyController.Configuration 변환 후 StreamCoordinator에 적용
    public func applyLatencySettings(_ ps: PlayerSettings) {
        guard let coordinator = streamCoordinator else { return }
        let config = Self.lowLatencyConfig(from: ps)
        Task { await coordinator.updateLowLatencyConfig(config) }
    }
    
    /// PlayerSettings → LowLatencyController.Configuration 변환
    static func lowLatencyConfig(from ps: PlayerSettings) -> LowLatencyController.Configuration {
        let preset = PlayerSettings.LatencyPreset(rawValue: ps.latencyPreset)
        switch preset {
        case .webSync:   return .webSync
        case .standard:  return .default
        case .ultraLow:  return .ultraLow
        case .custom, .none:
            return LowLatencyController.Configuration(
                targetLatency: ps.latencyTarget,
                maxLatency: ps.latencyMax,
                minLatency: ps.latencyMin,
                maxPlaybackRate: ps.latencyMaxRate,
                minPlaybackRate: ps.latencyMinRate,
                catchUpThreshold: ps.latencyCatchUpThreshold,
                slowDownThreshold: ps.latencySlowDownThreshold,
                pidKp: ps.latencyPidKp,
                pidKi: ps.latencyPidKi,
                pidKd: ps.latencyPidKd
            )
        }
    }

    // MARK: - Background Mode (멀티라이브 CPU 절약)
    
    /// 멀티라이브 비활성 세션의 CPU 사용 감소
    /// AVPlayerEngine: catchupLoop + stallWatchdog 건너뜀
    /// 멀티라이브 제약 조건 적용 (패인 수에 따라 CPU 최적화)
    public func applyMultiLiveConstraints(paneCount: Int) {
        // 패인이 2개 이상이면 배경 모드 최적화 적용
        if paneCount > 1 {
            if let vlcEngine = playerEngine as? VLCPlayerEngine {
                vlcEngine.setTimeUpdateMode(background: false)
            }
        }
    }

    /// VLC 백그라운드 모드: statsTimer 주기 조절 (비디오 트랙은 유지)
    ///
    /// [VLC macOS 안정성] deselectAllVideoTracks() → selectTrack() 방식은
    /// VLC vout 모듈을 파괴 후 재생성하는데, macOS layer-backed 뷰에서
    /// 다중 인스턴스 vout 재생성 시 데드락이 발생하는 알려진 VLC 버그가 있다.
    /// (VLC #19596: Multiple instances of macOS vouts hang using layer backing)
    /// (VLC #28793: Video and UI deadlock when disabling and reenabling video track)
    /// 따라서 비디오 트랙을 토글하지 않고 vout을 항상 살려두며,
    /// SwiftUI opacity:0 로 화면 숨기기만 한다. (최대 4세션 → CPU 부하 수용 가능)
    public func setBackgroundMode(_ enabled: Bool) {
        if let avEngine = playerEngine as? AVPlayerEngine {
            avEngine.isBackgroundMode = enabled
        } else if let vlcEngine = playerEngine as? VLCPlayerEngine {
            vlcEngine.setTimeUpdateMode(background: enabled)
        }
    }

    // MARK: - 백그라운드 복귀 재생 복구

    /// 앱이 백그라운드에서 포그라운드로 복귀 시 재생 상태를 확인하고 복구합니다.
    /// - VLC: drawable 재설정 + 재생 정체 시 재연결
    /// - AVPlayer: 재생 정체 시 재연결
    public func recoverFromBackground() {
        guard streamPhase == .playing || streamPhase == .buffering else { return }
        guard let engine = playerEngine else { return }

        // VLC: drawable 재바인딩 (NSView 계층 변경 대응)
        // 비디오 트랙은 항상 활성 상태이므로 vout은 살아있다.
        // 탭 전환 시 NSView가 다른 PlayerContainerView로 이동할 수 있으므로
        // drawable만 재바인딩하여 렌더링 서피스를 갱신한다.
        if let vlcEngine = engine as? VLCPlayerEngine {
            Task { @MainActor [weak vlcEngine] in
                guard let vlcEngine else { return }
                vlcEngine.refreshDrawable()
                vlcEngine.setTimeUpdateMode(background: false)
            }
        }

        // AVPlayer: 백그라운드에서 macOS가 자동 일시정지한 경우 재개
        if let avEngine = engine as? AVPlayerEngine {
            avEngine.isBackgroundMode = false
            if !avEngine.isPlaying && !avEngine.isInErrorState {
                avEngine.resume()
            }
        }

        // StreamCoordinator를 통한 재생 복구 (엔진 상태 체크 + 매니페스트 갱신)
        if let coordinator = streamCoordinator {
            Task { await coordinator.recoverFromBackground() }
        }
    }

    // MARK: - 스트림 제어

    public func startStream(
        channelId: String,
        streamUrl: URL,
        channelName: String = "",
        liveTitle: String = "",
        thumbnailURL: URL? = nil,
        prefetchedManifest: MasterPlaylist? = nil,
        playerSettings: PlayerSettings? = nil
    ) async {
        self.channelName = channelName
        self.liveTitle = liveTitle
        self.thumbnailURL = thumbnailURL
        self.currentChannelId = channelId

        let lowLatencyConfig: LowLatencyController.Configuration = playerSettings.map { Self.lowLatencyConfig(from: $0) } ?? .webSync
        let config = StreamCoordinator.Configuration(channelId: channelId, enableLowLatency: !isMultiLive, enableABR: true, lowLatencyConfig: lowLatencyConfig, abrConfig: isMultiLive ? .multiLive : .default)
        let coordinator = StreamCoordinator(configuration: config)
        streamCoordinator = coordinator
        
        // 방송 종료 확인 콜백 연결
        if let checkEnded = onCheckStreamEnded {
            await coordinator.setCheckStreamEndedCallback(checkEnded)
        }
        
        // [Opt: Single VLC] 프리페치 매니페스트가 있으면 coordinator에 주입
        // startStream()에서 resolveHighestQualityVariant() 네트워크 요청 건너뜀 (~200-400ms)
        if let manifest = prefetchedManifest {
            await coordinator.setPrefetchedManifest(manifest)
        }

        let engine: any PlayerEngineProtocol
        if isPreallocated, let existing = playerEngine {
            engine = existing
        } else {
            playerEngine = nil
            let newEngine = PlayerViewModel.makeEngine(type: preferredEngineType)
            currentEngineType = preferredEngineType
            playerEngine = newEngine
            engine = newEngine
            logger.info("PlayerViewModel: 엔진 생성 → \(self.preferredEngineType.rawValue)")
        }
        engine.setVolume(isMuted ? 0 : volume)
        await coordinator.setPlayerEngine(engine)

        // VLC onStateChange 콜백 연결
        if let vlc = engine as? VLCPlayerEngine {
            vlc.onStateChange = { [weak self, weak coordinator] phase in
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?._handleVLCPhase(phase, coordinator: coordinator)
                    }
                } else {
                    Task { @MainActor [weak self, weak coordinator] in
                        self?._handleVLCPhase(phase, coordinator: coordinator)
                    }
                }
            }
            // 재생 정체 감지 → StreamCoordinator 재연결 트리거
            vlc.onPlaybackStalled = { [weak coordinator] in
                guard let coordinator else { return }
                Task { await coordinator.triggerReconnect(reason: "VLC decoded frames stall") }
            }
        }

        startEventListening(coordinator)

        do {
            try await coordinator.startStream(url: streamUrl)
            startUptimeTimer()
        } catch {
            // 스트림 시작 실패 시 VLC 콜백 정리 — zombie callback 방지
            if let vlc = engine as? VLCPlayerEngine {
                vlc.onStateChange = nil
                vlc.onVLCMetrics = nil
                vlc.onPlaybackStalled = nil
            }
            // eventTask 정리 — coordinator 이벤트 리스닝 중단
            eventTask?.cancel()
            eventTask = nil
            errorMessage = "스트림 시작 실패: \(error.localizedDescription)"
            logger.error("스트림 시작 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func stopStream() async {
        if isRecording { await stopRecording() }

        // VLC 콜백 정리 — 엔진 재사용(풀 반납) 시 이전 세션의 dangling callback 방지
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.onStateChange = nil
            vlc.onVLCMetrics = nil
            vlc.onPlaybackStalled = nil
        }
        
        uptimeTask?.cancel(); uptimeTask = nil
        eventTask?.cancel(); eventTask = nil
        controlHideTask?.cancel(); controlHideTask = nil
        _bufferingDebounceTask?.cancel(); _bufferingDebounceTask = nil
        _refreshDrawableTask?.cancel(); _refreshDrawableTask = nil

        await streamCoordinator?.stopStream()
        streamCoordinator = nil

        if isPreallocated {
            playerEngine?.stop()
        } else {
            let old = playerEngine
            old?.stop()
            playerEngine = nil
            withExtendedLifetime(old) {}
        }

        uptime = 0
        streamPhase = .idle
        latencyHistory = []
        onPlaybackStateChanged?()
    }

    public func togglePlayPause() async {
        guard let coordinator = streamCoordinator else { return }
        if streamPhase == .playing {
            await coordinator.pause()
        } else if streamPhase == .paused {
            await coordinator.resume()
        }
    }

    public func setVolume(_ newVolume: Float) {
        volume = newVolume
        playerEngine?.setVolume(isMuted ? 0 : newVolume)
    }

    public func toggleMute() {
        isMuted.toggle()
        playerEngine?.setVolume(isMuted ? 0 : volume)
    }

    /// StreamCoordinator 내부 per-instance 프록시의 네트워크 통계 반환
    public func proxyNetworkStats() -> ProxyNetworkStats? {
        streamCoordinator?.proxyNetworkStats()
    }

    public func switchQuality(_ quality: StreamQualityInfo) async {
        guard let coordinator = streamCoordinator else { return }
        errorMessage = nil
        do {
            try await coordinator.switchQualityByBandwidth(quality.bandwidth)
            currentQuality = quality
        } catch {
            errorMessage = "품질 전환 실패: \(error.localizedDescription)"
        }
    }

    public func toggleFullscreen() {
        isFullscreen.toggle()
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    public func toggleAudioOnly() {
        isAudioOnly.toggle()
        (playerEngine as? VLCPlayerEngine)?.setVideoTrackEnabled(!isAudioOnly)
        (playerEngine as? AVPlayerEngine)?.setVideoLayerVisible(!isAudioOnly)
    }

    public func setPlaybackRate(_ rate: Double) async {
        playbackRate = rate
        playerEngine?.setRate(Float(rate))
    }

    public func showControlsTemporarily() {
        showControls = true
        controlHideTask?.cancel()
        controlHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.showControls = false }
        }
    }

    public var currentVideoView: NSView? { playerEngine?.videoView }

    public var mediaPlayer: VLCPlayerEngine? { playerEngine as? VLCPlayerEngine }

    // MARK: - 포맷 헬퍼

    public var formattedUptime: String {
        let h = Int(uptime) / 3600, m = (Int(uptime) % 3600) / 60, s = Int(uptime) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    public var formattedLatency: String {
        guard let info = latencyInfo else { return "-" }
        return String(format: "%.1f초", info.current)
    }

    public var formattedPlaybackRate: String {
        abs(playbackRate - 1.0) < 0.01 ? "1.0x" : String(format: "%.2fx", playbackRate)
    }

    public var currentTime: TimeInterval { playerEngine?.currentTime ?? 0 }
    public var duration: TimeInterval    { playerEngine?.duration ?? 0 }

    public func seek(to position: TimeInterval) { playerEngine?.seek(to: position) }

    public var formattedCurrentTime: String { Self.formatTimeInterval(currentTime) }
    public var formattedDuration: String    { Self.formatTimeInterval(duration) }

    public static func formatTimeInterval(_ t: TimeInterval) -> String {
        guard t.isFinite && t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public func refreshDrawable() {
        (playerEngine as? VLCPlayerEngine)?.refreshDrawable()
    }
}
