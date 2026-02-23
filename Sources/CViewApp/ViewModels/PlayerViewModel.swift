// MARK: - PlayerViewModel.swift
// CViewApp - Player ViewModel
// 원본: 뷰 내 직접 플레이어 제어 → 개선: @Observable ViewModel + StreamCoordinator

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Player ViewModel

@Observable
@MainActor
public final class PlayerViewModel {
    
    // MARK: - State
    
    public var streamPhase: StreamCoordinator.StreamPhase = .idle
    public var currentQuality: StreamQualityInfo?
    public var availableQualities: [StreamQualityInfo] = []
    public var latencyInfo: LatencyInfo?
    public var bufferHealth: BufferHealth?
    public var playbackRate: Double = 1.0
    public var volume: Float = 1.0
    public var isMuted = false
    public var isFullscreen = false
    public var isAudioOnly = false
    public var showControls = true
    public var errorMessage: String?
    
    // Stream info
    public var channelName: String = ""
    public var liveTitle: String = ""
    public var viewerCount: Int = 0
    public var uptime: TimeInterval = 0
    /// 현재 재생 중인 채널 ID (새 창 중복 스트림 방지용)
    public private(set) var currentChannelId: String?
    
    // MARK: - Dependencies
    
    private var streamCoordinator: StreamCoordinator?
    private var playerEngine: (any PlayerEngineProtocol)?
    /// true = 멀티라이브에서 VLCPlayerEngine을 주입받은 경우 → startStream() 시 엔진 재사용
    /// false = 싱글라이브 → startStream() 시 preferredEngineType 기준으로 항상 신규 생성
    private let isPreallocated: Bool
    private var eventTask: Task<Void, Never>?
    private var controlHideTask: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    private let logger = AppLogger.player

    // MARK: - Engine Selection

    /// 다음 채널 시청 시 사용할 엔진 타입 (설정에서 읽어서 설정)
    public var preferredEngineType: PlayerEngineType = .vlc
    /// 현재 실행 중인 엔진 타입
    public private(set) var currentEngineType: PlayerEngineType = .vlc
    
    // MARK: - Initialization
    
    public init(engineType: PlayerEngineType = .vlc) {
        // 설정 로드(initializeDataStore) 전 기본값.vlc 으로 미리 엔진을 생성하면
        // 이후 설정이 .avPlayer로 바뀌어도 VLC가 남아있는 타이밍 버그가 발생한다.
        // → 엔진은 startStream() 직전 preferredEngineType 기준으로 지연 생성한다.
        self.preferredEngineType = engineType
        self.currentEngineType = engineType
        self.isPreallocated = false
        // playerEngine = nil (지연 생성)
    }

    /// 멀티라이브 전용: VLCPlayerEngine을 미리 생성해 주입.
    /// VLCVideoView가 뷰 마운트 즉시 drawable을 설정할 수 있으므로
    /// play() 호출 전 drawable이 보장됨.
    public init(preallocatedEngine: VLCPlayerEngine) {
        preallocatedEngine.streamingProfile = .lowLatency
        self.preferredEngineType = .vlc
        self.currentEngineType = .vlc
        self.isPreallocated = true
        self.playerEngine = preallocatedEngine
    }

    /// 엔진 팩토리 — 타입에 따라 적절한 엔진 생성
    private static func makeEngine(type: PlayerEngineType) -> any PlayerEngineProtocol {
        switch type {
        case .vlc:
            let vlcEngine = VLCPlayerEngine()
            vlcEngine.streamingProfile = .lowLatency
            return vlcEngine
        case .avPlayer:
            let avEngine = AVPlayerEngine()
            avEngine.catchupConfig = .lowLatency
            return avEngine
        }
    }
    
    // MARK: - VLC Metrics Callback

    /// VLCPlayerEngine.onVLCMetrics 콜백을 설정합니다.
    /// LiveStreamView에서 MetricsForwarder와 연결하는 데 사용합니다.
    /// - Parameter callback: nil을 전달하면 콜백을 해제합니다.
    public func setVLCMetricsCallback(_ callback: (@Sendable (VLCLiveMetrics) -> Void)?) {
        (playerEngine as? VLCPlayerEngine)?.onVLCMetrics = callback
    }

    /// Apply settings from SettingsStore
    public func applySettings(volume: Float, lowLatency: Bool, catchupRate: Double) {
        self.volume = volume
        playerEngine?.setVolume(isMuted ? 0 : volume)
        if lowLatency {
            (playerEngine as? VLCPlayerEngine)?.streamingProfile = .lowLatency
        }
    }

    /// 멀티라이브 모드에서 동시 재생 세션 수에 비례해 AVPlayer 해상도·비트레이트를 제한한다.
    /// GPU 병렬 디코딩 부하를 세션 수에 반비례해 분산함으로써 전체 GPU 사용률을 낮춘다.
    /// - VLC 엔진은 별도 API가 없으므로 AVPlayer 전용으로 동작한다.
    /// - paneCount == 0 또는 1이면 제한을 완전히 해제한다.
    public func applyMultiLiveConstraints(paneCount: Int) {
        guard let avEngine = playerEngine as? AVPlayerEngine,
              let item = avEngine.player.currentItem else { return }

        if paneCount <= 1 {
            // 단독 재생: 제한 해제
            item.preferredMaximumResolution = .zero   // .zero == 무제한
            item.preferredPeakBitRate       = 0       // 0 == 무제한
            return
        }

        // 화면 물리 픽셀 기준으로 pane 크기를 산정
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenH = screen?.frame.height ?? 1080
        let scale   = screen?.backingScaleFactor ?? 2.0

        // pane 수별 목표 해상도 (4:3 분할 기준)
        let targetHeightPt: CGFloat
        switch paneCount {
        case 2:     targetHeightPt = screenH / 2.0   // 하프 → ~540 ~ 720pt
        case 3, 4:  targetHeightPt = screenH / 2.5   // 쿼터 → ~432pt
        default:    targetHeightPt = 360             // 5개 이상(예비)
        }
        let heightPx = targetHeightPt * scale
        let widthPx  = heightPx * 16.0 / 9.0
        item.preferredMaximumResolution = CGSize(width: widthPx, height: heightPx)

        // pane 수에 반비례한 비트레이트 상한 (4K 기준 20Mbps → n분할)
        let maxBitrate = 8_000_000.0 / Double(paneCount)  // 8Mbps ÷ n
        item.preferredPeakBitRate = maxBitrate
    }

    // MARK: - Stream Control
    
    /// Start playing a stream
    public func startStream(
        channelId: String,
        streamUrl: URL,
        channelName: String = "",
        liveTitle: String = ""
    ) async {
        self.channelName = channelName
        self.liveTitle = liveTitle
        self.currentChannelId = channelId
        
        let config = StreamCoordinator.Configuration(
            channelId: channelId,
            enableLowLatency: true,
            enableABR: true
        )
        
        let coordinator = StreamCoordinator(configuration: config)
        streamCoordinator = coordinator

        // 멀티라이브(isPreallocated): VLC 주입 엔진 재사용 — 이미 뷰에 바인딩됨
        // 싱글라이브: preferredEngineType 기준으로 항상 신규 생성
        //   (init()은 settings 로드 전이므로 미리 만든 엔진을 절대 재사용하지 않는다)
        let engine: any PlayerEngineProtocol
        if isPreallocated, let existing = playerEngine {
            engine = existing
        } else {
            // 기존 엔진 폐기 후 최신 preferredEngineType으로 신규 생성
            playerEngine = nil
            let newEngine = PlayerViewModel.makeEngine(type: preferredEngineType)
            currentEngineType = preferredEngineType
            playerEngine = newEngine
            engine = newEngine
            let engineName = preferredEngineType.rawValue
            logger.info("PlayerViewModel: 엔진 생성 → \(engineName)")
        }
        engine.setVolume(isMuted ? 0 : volume)
        await coordinator.setPlayerEngine(engine)
        
        // Listen to events
        startEventListening(coordinator)
        
        // playerView가 window hierarchy에 연결될 때까지 대기 (최대 500ms)
        // window 밖에서 play()가 호출되면 vout 초기화 실패 → 블랙스크린
        await waitForViewMounted(engine)
        
        do {
            try await coordinator.startStream(url: streamUrl)
            startUptimeTimer()
        } catch {
            errorMessage = "스트림 시작 실패: \(error.localizedDescription)"
            logger.error("스트림 시작 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Stop the stream
    public func stopStream() async {
        uptimeTask?.cancel()
        uptimeTask = nil
        eventTask?.cancel()
        eventTask = nil
        
        await streamCoordinator?.stopStream()
        streamCoordinator = nil
        playerEngine = nil
        
        uptime = 0
        streamPhase = .idle
    }
    
    /// Toggle play/pause
    public func togglePlayPause() async {
        guard let coordinator = streamCoordinator else { return }
        
        if streamPhase == .playing {
            await coordinator.pause()
        } else if streamPhase == .paused {
            await coordinator.resume()
        }
    }
    
    /// Set volume
    public func setVolume(_ newVolume: Float) {
        volume = newVolume
        playerEngine?.setVolume(isMuted ? 0 : newVolume)
    }
    
    /// Toggle mute
    public func toggleMute() {
        isMuted.toggle()
        playerEngine?.setVolume(isMuted ? 0 : volume)
    }
    
    /// Switch quality
    public func switchQuality(_ quality: StreamQualityInfo) async {
        guard let coordinator = streamCoordinator else { return }
        errorMessage = nil
        logger.info("Quality switch requested: \(quality.name)")
        
        do {
            try await coordinator.switchQualityByBandwidth(quality.bandwidth)
            currentQuality = quality
        } catch {
            errorMessage = "품질 전환 실패: \(error.localizedDescription)"
            logger.error("Quality switch failed: \(error)")
        }
    }
    
    /// Toggle fullscreen
    public func toggleFullscreen() {
        isFullscreen.toggle()
        NSApp.mainWindow?.toggleFullScreen(nil)
    }
    
    /// 배경/포그라운드 모드 전환 (멀티라이브 탭 전환 시 사용, VLC 전용)
    public func setBackgroundMode(_ isBackground: Bool) {
        if let vlcEngine = playerEngine as? VLCPlayerEngine {
            let profile: VLCStreamingProfile = isBackground ? .multiLiveBackground : .lowLatency
            vlcEngine.streamingProfile = profile
        }
        // AVPlayer: 백그라운드 탭의 레이어 숨기기 → GPU 합성 패스 완전 제거
        // 디코딩·오디오 버퍼링은 유지되므로 포그라운드 전환 시 즉시 재개됨
        (playerEngine as? AVPlayerEngine)?.setVideoLayerVisible(!isBackground)
        if isBackground {
            playerEngine?.setVolume(0)
        } else {
            playerEngine?.setVolume(isMuted ? 0 : volume)
        }
    }

    /// Toggle audio-only mode (hide video, save bandwidth)
    public func toggleAudioOnly() {
        isAudioOnly.toggle()
        // VLC: 비디오 트랙 비활성화 (디코딩 절약)
        (playerEngine as? VLCPlayerEngine)?.setVideoTrackEnabled(!isAudioOnly)
        // AVPlayer: 레이어 숨기기 (GPU 합성 제거; 디코딩은 유지)
        (playerEngine as? AVPlayerEngine)?.setVideoLayerVisible(!isAudioOnly)
    }
    
    /// Set playback rate
    public func setPlaybackRate(_ rate: Double) async {
        playbackRate = rate
        playerEngine?.setRate(Float(rate))
    }
    
    /// Show controls temporarily
    public func showControlsTemporarily() {
        showControls = true
        controlHideTask?.cancel()
        controlHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.showControls = false
            }
        }
    }
    
    /// 비디오 렌더링 뷰 — PlayerVideoView 통합용 (VLC / AVPlayer 모두 지원)
    public var currentVideoView: NSView? {
        playerEngine?.videoView
    }

    /// VLC 미디어 플레이어 — 멀티라이브 VLCVideoView 바인딩 전용
    public var mediaPlayer: VLCPlayerEngine? {
        playerEngine as? VLCPlayerEngine
    }
    
    /// Take a screenshot of the current video frame (VLC 전용)
    public func takeScreenshot() {
        guard let engine = playerEngine as? VLCPlayerEngine else { return }
        
        if let tempURL = engine.captureSnapshot() {
            // 데스크톱 또는 사진 폴더에 복사
            let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            let screenshotsDir = picturesDir?.appendingPathComponent("CView Screenshots")
            
            if let dir = screenshotsDir {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let filename = "CView_\(channelName)_\(Int(Date().timeIntervalSince1970)).png"
                let destURL = dir.appendingPathComponent(filename)
                
                // VLC 비동기 저장 대기 후 복사
                Task.detached {
                    try? await Task.sleep(for: .milliseconds(500))
                    try? FileManager.default.copyItem(at: tempURL, to: destURL)
                    await MainActor.run {
                        Log.player.info("스크린샷 저장: \(destURL.path)")
                    }
                }
            }
        }
    }
    
    // MARK: - Formatted Properties
    
    public var formattedUptime: String {
        let h = Int(uptime) / 3600
        let m = (Int(uptime) % 3600) / 60
        let s = Int(uptime) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    public var formattedLatency: String {
        guard let info = latencyInfo else { return "-" }
        return String(format: "%.1f초", info.current)
    }
    
    public var formattedPlaybackRate: String {
        if abs(playbackRate - 1.0) < 0.01 {
            return "1.0x"
        }
        return String(format: "%.2fx", playbackRate)
    }
    
    // MARK: - Private

    /// playerView가 실제 window에 연결될 때까지 폴링 대기.
    /// stopStream → startStream 패턴에서 새 VLC엔진의 NSView가
    /// SwiftUI container에 실제 삽입되기 전 play()가 호출되는 것을 방지한다.
    /// 어떠한 경우도 작동하도록 500ms 타임아웃 후 진행.
    private func waitForViewMounted(_ engine: any PlayerEngineProtocol) async {
        for _ in 0..<50 {  // 50 × 10ms = 최대 500ms
            let isMounted = await MainActor.run { engine.videoView.window != nil }
            if isMounted { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        logger.warning("waitForViewMounted: 500ms 타임아웃 — window 미연결 상태로 play() 진행")
    }

    private func startUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if let coordinator = self.streamCoordinator {
                    let t = await coordinator.uptime
                    self.uptime = t
                }
            }
        }
    }

    private func startEventListening(_ coordinator: StreamCoordinator) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            
            let events = await coordinator.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handleStreamEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .phaseChanged(let phase):
            streamPhase = phase
            if case .error(let msg) = phase {
                errorMessage = msg
            }
            
        case .qualitySelected(let quality):
            currentQuality = quality
            // 품질이 선택되면 → 사용 가능한 품질 목록도 업데이트
            Task {
                if let coordinator = streamCoordinator {
                    let qualities = await coordinator.availableQualities
                    self.availableQualities = qualities
                }
            }
            
        case .qualityChanged(let quality):
            currentQuality = quality
            
        case .abrDecision(let decision):
            switch decision {
            case .switchUp(_, let reason):
                logger.info("ABR switch up: \(reason)")
            case .switchDown(_, let reason):
                logger.info("ABR switch down: \(reason)")
            case .maintain:
                break
            }
            
        case .latencyUpdate(let info):
            latencyInfo = info
            
        case .bufferUpdate(let health):
            bufferHealth = health
            
        case .error(let msg):
            errorMessage = msg
            
        case .stopped:
            streamPhase = .idle
        }
    }
}
