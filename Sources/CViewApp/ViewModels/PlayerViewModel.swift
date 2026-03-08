// MARK: - PlayerViewModel.swift
// CViewApp — 재작성된 Player ViewModel
// @Observable ViewModel + StreamCoordinator 아키텍처

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer
import UniformTypeIdentifiers

// MARK: - Player ViewModel

@Observable
@MainActor
public final class PlayerViewModel {

    // MARK: - Constants

    private static let maxLatencyHistory = 60

    // MARK: - 재생 상태

    public var streamPhase: StreamCoordinator.StreamPhase = .idle
    public var currentQuality: StreamQualityInfo?
    public var availableQualities: [StreamQualityInfo] = []
    public var latencyInfo: LatencyInfo?
    public private(set) var latencyHistory: [LatencyDataPoint] = []
    public var bufferHealth: BufferHealth?
    public var playbackRate: Double = 1.0
    public var volume: Float = 1.0
    public var isMuted = false
    public var isFullscreen = false
    public var isAudioOnly = false
    public var showControls = true
    public var errorMessage: String?
    public var isLiveStream: Bool = true

    // MARK: - 녹화 상태

    public var isRecording: Bool = false
    public var recordingDuration: TimeInterval = 0
    public private(set) var recordingURL: URL?
    private var recordingTimerTask: Task<Void, Never>?

    // MARK: - 스트림 메타정보

    public var channelName: String = ""
    public var liveTitle: String = ""
    public var thumbnailURL: URL?
    public var viewerCount: Int = 0
    public var uptime: TimeInterval = 0
    public private(set) var currentChannelId: String?

    // MARK: - 의존성

    private var streamCoordinator: StreamCoordinator?
    public private(set) var playerEngine: (any PlayerEngineProtocol)?
    private let isPreallocated: Bool
    private var eventTask: Task<Void, Never>?
    private var controlHideTask: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    /// VLC 버퍼링 디바운스: 재생 중 순간적인 버퍼링 상태 변경은 무시하고
    /// 일정 시간 이상 지속될 때만 UI에 반영
    private var _bufferingDebounceTask: Task<Void, Never>?
    /// 안티플리커: 마지막으로 .playing 전환된 시각 (쿨다운 기준)
    /// playing 진입 후 일정 시간 동안은 버퍼링 전환을 억제하여 깜빡임 방지
    private var _lastPlayingTime: Date?
    private let logger = AppLogger.player

    public var onPlaybackStateChanged: (() -> Void)?

    // MARK: - 엔진 선택

    public var preferredEngineType: PlayerEngineType = .vlc
    public private(set) var currentEngineType: PlayerEngineType = .vlc

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

    public init(engineType: PlayerEngineType = .vlc) {
        self.preferredEngineType = engineType
        self.currentEngineType = engineType
        self.isPreallocated = false
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

    // MARK: - 설정 적용

    public func applySettings(volume: Float, lowLatency: Bool, catchupRate: Double) {
        self.volume = volume
        playerEngine?.setVolume(isMuted ? 0 : volume)
        if lowLatency {
            (playerEngine as? VLCPlayerEngine)?.streamingProfile = .lowLatency
        }
    }

    // MARK: - Background Mode (멀티라이브 CPU 절약)
    
    /// 멀티라이브 비활성 세션의 CPU 사용 감소
    /// AVPlayerEngine: catchupLoop + stallWatchdog 건너뜀
    /// VLCPlayerEngine: statsTimer 건너뜀
    public func setBackgroundMode(_ enabled: Bool) {
        if let avEngine = playerEngine as? AVPlayerEngine {
            avEngine.isBackgroundMode = enabled
        } else if let vlcEngine = playerEngine as? VLCPlayerEngine {
            vlcEngine.setTimeUpdateMode(background: enabled)
        }
    }

    // MARK: - 스트림 제어

    public func startStream(
        channelId: String,
        streamUrl: URL,
        channelName: String = "",
        liveTitle: String = "",
        thumbnailURL: URL? = nil
    ) async {
        self.channelName = channelName
        self.liveTitle = liveTitle
        self.thumbnailURL = thumbnailURL
        self.currentChannelId = channelId

        let config = StreamCoordinator.Configuration(channelId: channelId, enableLowLatency: true, enableABR: true)
        let coordinator = StreamCoordinator(configuration: config)
        streamCoordinator = coordinator

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
        NSApp.mainWindow?.toggleFullScreen(nil)
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

    // MARK: - 스크린샷

    public func takeScreenshot() {
        guard let engine = playerEngine as? VLCPlayerEngine else { return }
        guard let tempURL = engine.captureSnapshot() else { return }
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let dir = picturesDir?.appendingPathComponent("CView Screenshots")
        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "CView_\(channelName)_\(Int(Date().timeIntervalSince1970)).png"
            let dest = dir.appendingPathComponent(name)
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                try? FileManager.default.copyItem(at: tempURL, to: dest)
                await MainActor.run { Log.player.info("스크린샷 저장: \(dest.path)") }
            }
        }
    }

    // MARK: - 이퀄라이저

    public func getEqualizerPresets() -> [String] {
        (playerEngine as? VLCPlayerEngine)?.equalizerPresets() ?? []
    }

    public func getEqualizerFrequencies() -> [Float] {
        (playerEngine as? VLCPlayerEngine)?.equalizerBandFrequencies() ?? []
    }

    public func applyEqualizerPreset(_ name: String) {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        vlc.setEqualizerPresetByName(name)
        equalizerPresetName = name
        isEqualizerEnabled = true
        equalizerPreAmp = vlc.equalizerPreAmpValue()
        equalizerBands = vlc.equalizerBandValues()
    }

    public func setEqualizerPreAmp(_ value: Float) {
        (playerEngine as? VLCPlayerEngine)?.setEqualizerPreAmp(value)
        equalizerPreAmp = value
    }

    public func setEqualizerBand(index: Int, value: Float) {
        (playerEngine as? VLCPlayerEngine)?.setEqualizerBand(index: index, value: value)
        if index < equalizerBands.count { equalizerBands[index] = value }
    }

    public func disableEqualizer() {
        (playerEngine as? VLCPlayerEngine)?.resetEqualizer()
        isEqualizerEnabled = false
        equalizerPresetName = ""
        equalizerPreAmp = 0
        equalizerBands = []
    }

    // MARK: - 비디오 조정

    public func setVideoAdjust(enabled: Bool) {
        (playerEngine as? VLCPlayerEngine)?.setVideoAdjustEnabled(enabled)
        isVideoAdjustEnabled = enabled
    }

    public func setVideoBrightness(_ v: Float)  { (playerEngine as? VLCPlayerEngine)?.setVideoBrightness(v); videoBrightness = v }
    public func setVideoContrast(_ v: Float)    { (playerEngine as? VLCPlayerEngine)?.setVideoContrast(v); videoContrast = v }
    public func setVideoSaturation(_ v: Float)  { (playerEngine as? VLCPlayerEngine)?.setVideoSaturation(v); videoSaturation = v }
    public func setVideoHue(_ v: Float)         { (playerEngine as? VLCPlayerEngine)?.setVideoHue(v); videoHue = v }
    public func setVideoGamma(_ v: Float)       { (playerEngine as? VLCPlayerEngine)?.setVideoGamma(v); videoGamma = v }

    public func resetVideoAdjust() {
        (playerEngine as? VLCPlayerEngine)?.resetVideoAdjust()
        isVideoAdjustEnabled = false
        videoBrightness = 1.0; videoContrast = 1.0; videoSaturation = 1.0
        videoHue = 0; videoGamma = 1.0
    }

    // MARK: - 화면 비율

    public func setAspectRatio(_ ratio: String?) {
        (playerEngine as? VLCPlayerEngine)?.setAspectRatio(ratio)
        aspectRatio = ratio
    }

    // MARK: - 오디오 고급

    public func setAudioStereoMode(_ mode: UInt) {
        (playerEngine as? VLCPlayerEngine)?.setAudioStereoMode(mode)
        audioStereoMode = mode
    }

    public func setAudioDelay(_ delay: Int) {
        (playerEngine as? VLCPlayerEngine)?.setAudioDelay(delay)
        audioDelay = delay
    }

    public func setAudioMixMode(_ mode: UInt32) {
        (playerEngine as? VLCPlayerEngine)?.setAudioMixMode(mode)
        audioMixMode = mode
    }

    // MARK: - 자막

    public func refreshSubtitleTracks() {
        subtitleTracks = (playerEngine as? VLCPlayerEngine)?.textTracks() ?? []
    }

    public func selectSubtitleTrack(_ index: Int) {
        if index < 0 {
            (playerEngine as? VLCPlayerEngine)?.deselectAllTextTracks()
            selectedSubtitleTrack = -1
        } else {
            (playerEngine as? VLCPlayerEngine)?.selectTextTrack(index)
            selectedSubtitleTrack = index
        }
    }

    public func addSubtitleFile(url: URL) {
        (playerEngine as? VLCPlayerEngine)?.addSubtitleFile(url: url)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            refreshSubtitleTracks()
        }
    }

    public func setSubtitleDelay(_ delay: Int) {
        (playerEngine as? VLCPlayerEngine)?.setSubtitleDelay(delay)
        subtitleDelay = delay
    }

    public func setSubtitleFontScale(_ scale: Float) {
        (playerEngine as? VLCPlayerEngine)?.setSubtitleFontScale(scale)
        subtitleFontScale = scale
    }

    /// 고급 설정 일괄 적용
    public func applyAdvancedSettings(from settings: PlayerSettings) {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        vlc.applyAdvancedSettings(settings)
        if let preset = settings.equalizerPreset {
            isEqualizerEnabled = true
            equalizerPresetName = preset
            equalizerPreAmp = vlc.equalizerPreAmpValue()
            equalizerBands = vlc.equalizerBandValues()
        }
        if settings.videoAdjustEnabled {
            isVideoAdjustEnabled = true
            videoBrightness = settings.videoBrightness; videoContrast = settings.videoContrast
            videoSaturation = settings.videoSaturation; videoHue = settings.videoHue
            videoGamma = settings.videoGamma
        }
        aspectRatio = settings.aspectRatio
        audioStereoMode = UInt(settings.audioStereoMode)
        audioMixMode = settings.audioMixMode
        audioDelay = Int(settings.audioDelay)
    }

    // MARK: - 녹화

    public func startRecording(to customURL: URL? = nil) async {
        guard let engine = playerEngine, !isRecording else { return }
        let url = customURL ?? StreamRecordingService.defaultRecordingURL(channelName: channelName)
        recordingURL = url
        do {
            try await engine.startRecording(to: url)
            isRecording = true
            recordingDuration = 0
            startRecordingTimer()
            logger.info("녹화 시작: \(url.lastPathComponent, privacy: .public)")
        } catch {
            errorMessage = "녹화 시작 실패: \(error.localizedDescription)"
        }
    }

    public func stopRecording() async {
        guard let engine = playerEngine, isRecording else { return }
        await engine.stopRecording()
        isRecording = false
        recordingTimerTask?.cancel(); recordingTimerTask = nil
        if let url = recordingURL {
            logger.info("녹화 저장 완료: \(url.path, privacy: .public)")
        }
    }

    public func toggleRecording() async {
        if isRecording { await stopRecording() } else { await startRecording() }
    }

    public func startRecordingWithSavePanel() async {
        let panel = NSSavePanel()
        panel.title = "녹화 파일 저장"
        panel.nameFieldStringValue = StreamRecordingService.defaultRecordingURL(channelName: channelName).lastPathComponent
        panel.allowedContentTypes = [.mpeg2TransportStream]
        panel.canCreateDirectories = true
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        if let dir = moviesDir?.appendingPathComponent("CView") {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            panel.directoryURL = dir
        }
        let response = await panel.beginSheetModal(for: NSApp.mainWindow ?? NSApp.keyWindow ?? NSWindow())
        guard response == .OK, let url = panel.url else { return }
        await startRecording(to: url)
    }

    public var formattedRecordingDuration: String { Self.formatTimeInterval(recordingDuration) }

    private func startRecordingTimer() {
        recordingTimerTask?.cancel()
        let start = Date()
        recordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

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

    // MARK: - Private

    private func startUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                if let coord = self.streamCoordinator {
                    self.uptime = await coord.uptime
                }
            }
        }
    }

    private func startEventListening(_ coordinator: StreamCoordinator) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            let events = await coordinator.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                await self?.handleStreamEvent(event)
            }
        }
    }

    @MainActor
    private func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .phaseChanged(let phase):
            // [버퍼링 디바운스 통합] StreamCoordinator에서 오는 .buffering phase도
            // VLC 디바운스와 동일하게 처리해야 한다.
            // 그렇지 않으면 VLC 디바운스를 우회하여 즉시 streamPhase = .buffering이 되어
            // 정상 재생 중에도 버퍼링 스피너가 계속 표시된다.
            if phase == .buffering && streamPhase == .playing {
                // 이미 재생 중이면 디바운스 적용 (VLC _handleVLCPhase와 동일 로직)
                // 안티플리커: 재생 시작 후 5초 이내면 버퍼링 전환 억제
                if let lastPlaying = _lastPlayingTime,
                   Date().timeIntervalSince(lastPlaying) < 5.0 {
                    // 쿨다운 중 — 무시
                } else if _bufferingDebounceTask == nil {
                    _bufferingDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3초
                        guard !Task.isCancelled, let self else { return }
                        self.streamPhase = .buffering
                        self._bufferingDebounceTask = nil
                    }
                }
            } else if phase == .playing {
                // playing 전환 시 디바운스 취소 + 즉시 반영
                _bufferingDebounceTask?.cancel()
                _bufferingDebounceTask = nil
                _lastPlayingTime = Date()
                streamPhase = phase
            } else {
                streamPhase = phase
            }
            if case .error(let msg) = phase { errorMessage = msg }
            onPlaybackStateChanged?()

        case .qualitySelected(let q):
            currentQuality = q
            Task {
                if let coord = streamCoordinator {
                    self.availableQualities = await coord.availableQualities
                }
            }

        case .qualityChanged(let q):
            currentQuality = q

        case .abrDecision:
            break

        case .latencyUpdate(let info):
            latencyInfo = info
            if latencyHistory.isEmpty || latencyHistory.count % 10 == 0 {
                let point = LatencyDataPoint(timestamp: Date(), latency: info.current)
                latencyHistory.append(point)
                if latencyHistory.count > Self.maxLatencyHistory { latencyHistory.removeFirst() }
            }

        case .bufferUpdate(let health):
            bufferHealth = health

        case .error(let msg):
            errorMessage = msg

        case .stopped:
            streamPhase = .idle
        }
    }

    /// VLC 상태 변경 처리
    @MainActor
    private func _handleVLCPhase(_ phase: PlayerState.Phase, coordinator: StreamCoordinator?) {
        switch phase {
        case .error:
            logger.warning("VLC → ERROR: StreamCoordinator 재연결 트리거")
            if let coord = coordinator {
                Task { await coord.triggerReconnect(reason: "VLC error state") }
            }
        case .ended:
            logger.warning("VLC → ENDED: 라이브 스트림 재연결")
            if let coord = coordinator {
                Task { await coord.triggerReconnect(reason: "VLC ended (live stream)") }
            }
        case .playing:
            // 버퍼링 디바운스 취소 — VLC가 playing으로 돌아오면 즉시 반영
            _bufferingDebounceTask?.cancel()
            _bufferingDebounceTask = nil
            _lastPlayingTime = Date()
            streamPhase = .playing
            errorMessage = nil
            onPlaybackStateChanged?()
            // 재생 시작 시 고급 설정 적용 (설정이 기본값이 아닐 경우만)
            _applyVLCAdvancedSettingsIfNeeded()
        case .buffering:
            // [VLC 버퍼링 디바운스] VLC는 라이브 HLS 중 네트워크 버퍼를 채울 때
            // 수시로 .buffering 상태를 보고한다 (수백ms 이내 .playing으로 복귀).
            // 이 순간적인 버퍼링마다 UI 스피너를 표시하면 영상이 정상 재생되는데도
            // 스피너가 계속 깜빡이거나 고착되어 보인다.
            //
            // 해결 1: 이미 재생 중(.playing)이었으면 3초 디바운스 적용.
            //         3초 이상 버퍼링이 지속될 때만 streamPhase를 .buffering으로 전환.
            // 해결 2: 안티플리커 쿨다운 — 재생 시작 후 5초 이내 버퍼링은 무시.
            //         VLC가 재생 초반에 버퍼를 정리하는 과정에서 발생하는 순간 버퍼링 방지.
            if streamPhase == .playing {
                // 안티플리커: 재생 시작 후 5초 이내면 버퍼링 전환 억제
                if let lastPlaying = _lastPlayingTime,
                   Date().timeIntervalSince(lastPlaying) < 5.0 {
                    break
                }
                if _bufferingDebounceTask == nil {
                    _bufferingDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3초
                        guard !Task.isCancelled, let self else { return }
                        self.streamPhase = .buffering
                        self._bufferingDebounceTask = nil
                    }
                }
            } else {
                // 아직 재생 전이면 (connecting, idle 등) 즉시 반영
                if streamPhase != .buffering { streamPhase = .buffering }
            }
        case .paused:
            streamPhase = .paused
        case .loading:
            streamPhase = .connecting
        case .idle:
            break
        }
    }

    /// 재생 시작 시 VLC 고급 설정 적용 (기본값이 아닌 항목만)
    private func _applyVLCAdvancedSettingsIfNeeded() {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        let hasEq = isEqualizerEnabled && !equalizerPresetName.isEmpty
        let hasVideoAdj = isVideoAdjustEnabled
        let hasAspect = aspectRatio != nil
        let hasAudio = audioStereoMode != 0 || audioMixMode != 0 || audioDelay != 0
        guard hasEq || hasVideoAdj || hasAspect || hasAudio else { return }

        if hasEq {
            vlc.setEqualizerPresetByName(equalizerPresetName)
            vlc.setEqualizerPreAmp(equalizerPreAmp)
            for (i, val) in equalizerBands.enumerated() { vlc.setEqualizerBand(index: i, value: val) }
        }
        if hasVideoAdj {
            vlc.setVideoAdjustEnabled(true)
            vlc.setVideoBrightness(videoBrightness); vlc.setVideoContrast(videoContrast)
            vlc.setVideoSaturation(videoSaturation); vlc.setVideoHue(videoHue); vlc.setVideoGamma(videoGamma)
        }
        if hasAspect { vlc.setAspectRatio(aspectRatio) }
        if audioStereoMode != 0 { vlc.setAudioStereoMode(audioStereoMode) }
        if audioMixMode != 0 { vlc.setAudioMixMode(audioMixMode) }
        if audioDelay != 0 { vlc.setAudioDelay(audioDelay) }
    }
}
