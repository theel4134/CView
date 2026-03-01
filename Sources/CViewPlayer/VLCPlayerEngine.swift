// MARK: - VLCPlayerEngine.swift
// CViewPlayer — 재작성된 VLC 플레이어 엔진
//
// [설계 원칙]
// • 내부 복구/워치독/재시도 로직 없음 — 깔끔한 VLC API 래퍼
// • play() → VLC에 위임, 상태 콜백으로 외부 통보
// • stop() → 안전한 순서: stop() → drawable=nil → media=nil (defer async)
// • streamingProfile 로 미디어 옵션 설정
// • 모든 VLC 고급 API (EQ, 비디오조정, 자막, 오디오 등) 보존

import Foundation
import AppKit
import QuartzCore
import CViewCore
@preconcurrency import VLCKitSPM

// MARK: - VLC 비디오 컨테이너 뷰

/// VLC 렌더링 서피스를 호스팅하는 컨테이너 NSView.
/// player.drawable = 이 뷰로 설정하면 VLC가 내부적으로 서브뷰를 추가해 렌더링.
public final class VLCLayerHostView: NSView {
    weak var boundPlayer: VLCMediaPlayer?

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        canDrawSubviewsIntoLayer = false
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        layer.drawsAsynchronously = true
        layer.actions = [
            "onOrderIn": NSNull(), "onOrderOut": NSNull(),
            "sublayers": NSNull(), "contents": NSNull(),
            "bounds": NSNull(), "position": NSNull(), "transform": NSNull()
        ]
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        boundPlayer?.drawable = self  // 리사이즈 시 drawable 재바인딩
    }
}

// MARK: - 화질 적응 액션

/// 1080p+ABR 하이브리드 화질 전환 요청 타입.
public enum QualityAdaptationAction: Sendable {
    case downgrade(reason: String)
    case upgrade(reason: String)
}

// MARK: - 스트리밍 프로파일

/// VLC 스트리밍 시나리오별 캐싱 프로파일.
public enum VLCStreamingProfile: Sendable {
    case lowLatency           // 단일 라이브 (저지연 우선)
    case multiLiveForeground  // 멀티라이브 포그라운드 (균형)
    case multiLiveBackground  // 멀티라이브 백그라운드 (절전)

    var networkCaching: Int {
        switch self {
        case .lowLatency: return 1200
        case .multiLiveForeground: return 1800
        case .multiLiveBackground: return 2500
        }
    }
    var liveCaching: Int {
        switch self {
        case .lowLatency: return 1200
        case .multiLiveForeground: return 1800
        case .multiLiveBackground: return 2500
        }
    }
    var manifestRefreshInterval: Int {
        switch self {
        case .lowLatency: return 15
        case .multiLiveForeground: return 20
        case .multiLiveBackground: return 30
        }
    }
}

// MARK: - VLC 플레이어 엔진

/// VLCKit 4.0 기반 스트림 플레이어 엔진.
/// 내부 복구 로직 없는 깔끔한 VLC API 래퍼.
@preconcurrency
public final class VLCPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {

    // MARK: - Public Properties

    /// 현재 스트리밍 프로파일 (play() 이전에 설정하면 다음 재생에 반영)
    public var streamingProfile: VLCStreamingProfile = .lowLatency

    /// 내부 VLCMediaPlayer 인스턴스 (PiP 등 직접 접근이 필요한 경우 사용)
    public var mediaPlayer: VLCMediaPlayer { player }

    /// 상태 변경 콜백 (PlayerState.Phase)
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?

    /// 재생 시간 콜백 (currentTime, duration) — 초 단위
    public var onTimeChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?

    /// VLC 실시간 메트릭 콜백 (2초 주기)
    public var onVLCMetrics: (@Sendable (VLCLiveMetrics) -> Void)?

    /// 트랙 이벤트 콜백 (PlayerEngineProtocol 요구사항)
    public var onTrackEvent: (@Sendable (TrackEvent) -> Void)?

    /// 1080p+ABR 화질 적응 요청 콜백 (StreamCoordinator에서 구독)
    public var onQualityAdaptationRequest: (@Sendable (QualityAdaptationAction) -> Void)?

    /// 복구 시 신선한 variant URL 제공 콜백
    public var onRecoveryURLRefresh: (@Sendable () async -> URL?)?

    // MARK: - PlayerEngineProtocol

    public var isPlaying: Bool { player.isPlaying }

    public var currentTime: TimeInterval {
        TimeInterval(player.time.intValue) / 1000.0
    }

    public var duration: TimeInterval {
        TimeInterval(player.media?.length.intValue ?? 0) / 1000.0
    }

    public var rate: Float { player.rate }

    public var videoView: NSView { playerView }

    // MARK: - VLC 내부

    private let player: VLCMediaPlayer
    private(set) public var playerView: VLCLayerHostView

    // 상태
    private let stateLock = NSLock()
    private var _currentPhase: PlayerState.Phase = .idle
    private var _isMuted: Bool = false
    private var _volume: Float = 1.0
    private var statsTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?

    // 이전 통계 (delta 계산용)
    private var _prevStats: VLCMedia.Stats?
    private var _lastMetricsTime: Date = Date()

    // 녹화 상태
    private var _isRecording: Bool = false

    // 복구 URL (매니페스트 갱신 시 StreamCoordinator가 동기화)
    private var _recoveryURL: URL?

    // MARK: - Init / Deinit

    public override init() {
        player = VLCMediaPlayer()
        playerView = VLCLayerHostView()
        super.init()
        playerView.boundPlayer = player
        player.delegate = self
    }

    deinit {
        statsTask?.cancel()
        playTask?.cancel()
        // VLCKit 4.0 크래시 방지:
        // player.media = nil 명시 호출 시 VLC 내부 on_current_media_changed
        // 이벤트에서 이미 해제된 libvlc_media_t*를 retain 시도 → 크래시.
        //
        // 해결: delegate만 해제하여 콜백 차단하고, stop()만 호출.
        // media 정리는 VLCMediaPlayer 자체 dealloc에 위임.
        // playerView를 async 블록으로 캡처하여 player보다 먼저 해제 방지.
        let p = player
        let pv = playerView
        p.delegate = nil
        if Thread.isMainThread {
            p.stop()
            p.drawable = nil
            // playerView가 player보다 먼저 해제되지 않도록 다음 run loop까지 유지
            DispatchQueue.main.async {
                _ = pv
            }
        } else {
            DispatchQueue.main.async {
                p.stop()
                p.drawable = nil
                _ = pv
            }
        }
    }

    // MARK: - 재생 제어

    /// PlayerEngineProtocol 요구사항 — 기본 프로파일로 재생
    public func play(url: URL) async throws {
        await _startPlay(url: url, profile: streamingProfile)
    }

    /// 프로파일 지정 재생
    public func play(url: URL, profile: VLCStreamingProfile) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self else { return }
            await self._startPlay(url: url, profile: profile)
        }
    }

    @MainActor
    private func _startPlay(url: URL, profile: VLCStreamingProfile) async {
        guard !Task.isCancelled else { return }

        // 기존 재생 중이면 안전하게 정리
        // VLCKit 4.0: player.media = nil 호출 시 VLC 내부에서
        // freed libvlc_media_t*를 retain 시도 → 크래시 발생.
        // player.stop()만 호출하고, 새 media 설정이 자동으로 교체 처리.
        if player.isPlaying || player.media != nil {
            player.stop()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms — VLC flush 대기
            guard !Task.isCancelled else { return }
        }

        // drawable 설정
        player.drawable = playerView

        // 뷰가 윈도우에 붙을 때까지 대기 (최대 5초, 50회 × 0.1초)
        // SwiftUI가 NSViewRepresentable을 window hierarchy에 마운트할 시간 확보
        // 기존 2초(20회)는 멀티라이브에서 여러 세션이 동시에 시작될 때 부족했음
        if playerView.window == nil {
            for i in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초
                guard !Task.isCancelled else { return }
                if playerView.window != nil {
                    break
                }
            }
            if playerView.window == nil {
                // window가 nil이어도 VLC play()를 호출하여 버퍼링 시작
                // layout() 시점에 drawable이 재바인딩되므로 나중에 화면 출력 가능
            }
        }

        guard !Task.isCancelled else { return }

        // 미디어 생성 (VLCKit 4.0: VLCMedia(url:) 옵셔널 반환)
        guard let media = VLCMedia(url: url) else {
            _setPhase(.error(.streamNotFound))
            return
        }
        // VLCKit 4.0: 콜론 접두사 문자열 옵션
        media.addOption(":network-caching=\(profile.networkCaching)")
        media.addOption(":live-caching=\(profile.liveCaching)")
        media.addOption(":file-caching=0")
        media.addOption(":disc-caching=0")
        media.addOption(":cr-average=40")
        media.addOption(":avcodec-threads=2")
        media.addOption(":avcodec-fast=1")
        // adaptive 모듈 최적화: VLC 내부 버퍼링 안정성 개선
        media.addOption(":adaptive-maxwidth=1920")
        media.addOption(":adaptive-maxheight=1080")
        switch profile {
        case .lowLatency:
            media.addOption(":clock-jitter=20000")
            media.addOption(":codec=videotoolbox,avcodec,all")
            media.addOption(":avcodec-hw=any")
            media.addOption(":videotoolbox-zero-copy=1")
        case .multiLiveForeground:
            media.addOption(":clock-jitter=30000")
            media.addOption(":codec=videotoolbox,avcodec,all")
            media.addOption(":avcodec-hw=any")
            media.addOption(":videotoolbox-zero-copy=0")
        case .multiLiveBackground:
            media.addOption(":clock-jitter=40000")
            media.addOption(":codec=avcodec,all")
            media.addOption(":avcodec-hw=none")
        }

        player.media = media
        player.play()
        startStatsTimer()
    }

    public func pause() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            player.pause()
            _setPhase(.paused)
        }
    }

    public func resume() {
        Task { @MainActor [weak self] in
            self?.player.play()
        }
    }

    public func stop() {
        playTask?.cancel()
        statsTask?.cancel()
        statsTask = nil
        _prevStats = nil
        // VLCKit 4.0 크래시 방지:
        // player.media = nil 을 명시적으로 호출하면 VLC 내부에서
        // vlc_player_SetCurrentMedia → on_current_media_changed →
        // HandleMediaPlayerMediaChanged → libvlc_media_retain() 순서로
        // 이미 해제된 libvlc_media_t* 접근 → Assertion failed 크래시.
        //
        // 해결: player.media = nil 을 호출하지 않는다.
        // - 새 URL 재생 시 _startPlay()에서 새 media를 설정하면 자동 교체됨
        // - 엔진 해제 시 VLCMediaPlayer 자체 dealloc이 안전하게 처리
        // - stop()만으로 VLC 내부 디먹서/디코더/렌더러가 모두 정지됨
        let p = player
        if Thread.isMainThread {
            p.stop()
            p.drawable = nil
        } else {
            DispatchQueue.main.async {
                p.stop()
                p.drawable = nil
            }
        }
        _setPhase(.idle)
    }

    /// 특정 시간으로 탐색 (TimeInterval 초 단위)
    public func seek(to position: TimeInterval) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let dur = duration
            guard dur > 0 else { return }
            player.position = Double(position / dur)
        }
    }

    public func setRate(_ rate: Float) {
        Task { @MainActor [weak self] in
            self?.player.rate = rate
        }
    }

    public func setVolume(_ volume: Float) {
        _volume = volume
        Task { @MainActor [weak self] in
            guard let self else { return }
            player.audio?.volume = Int32(volume * 200)
        }
    }

    public func setMuted(_ muted: Bool) {
        _isMuted = muted
        Task { @MainActor [weak self] in
            guard let self else { return }
            player.audio?.volume = muted ? 0 : Int32(_volume * 200)
        }
    }

    // MARK: - drawable 재바인딩

    /// StreamCoordinator가 복구 URL을 신선한 것으로 동기화할 때 사용ꁜ (URL은 다음 play() 호출 시 적용됨)
    public func updateCurrentURL(_ url: URL) {
        stateLock.withLock { _recoveryURL = url }
    }

    public func refreshDrawable() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            player.drawable = playerView
        }
    }

    // MARK: - 재사용 지원

    /// 에러 상태 여부 (PlayerEngineProtocol)
    public var isInErrorState: Bool {
        if case .error = _currentPhase { return true }
        return false
    }

    public func resetRetries() {}

    /// 풀 반납 전 엔진 초기화
    public func resetForReuse() {
        playTask?.cancel()
        statsTask?.cancel()
        statsTask = nil
        _prevStats = nil
        // VLCKit 4.0 크래시 방지: player.media = nil 호출 금지.
        // VLC 내부 on_current_media_changed 콜백에서 freed libvlc_media_t*를
        // libvlc_media_retain()으로 접근 → Assertion failed 크래시.
        // stop()만 호출하고 media 정리는 VLCMediaPlayer dealloc에 위임.
        let p = player
        let doStop = { [weak self] in
            p.delegate = nil  // 콜백 차단
            p.stop()
            p.drawable = nil
            self?._setPhase(.idle)
            // delegate만 복원 (media = nil 호출하지 않음)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                p.delegate = self  // 재사용을 위해 delegate 복원
            }
        }
        if Thread.isMainThread {
            doStop()
        } else {
            DispatchQueue.main.async { doStop() }
        }
        onStateChange = nil
        onTimeChange = nil
        onVLCMetrics = nil
        onTrackEvent = nil
        onQualityAdaptationRequest = nil
        onRecoveryURLRefresh = nil
        streamingProfile = .lowLatency
    }

    /// 비디오 트랙 활성화/비활성화 (멀티라이브 백그라운드 절전용)
    public func setVideoTrackEnabled(_ enabled: Bool) {
        if enabled {
            if !player.videoTracks.isEmpty {
                player.selectTrack(at: 0, type: .video)
            } else {
                // 스트림이 아직 로딩 중이면 videoTracks가 비어있을 수 있음
                // 0.5초 후 재시도하여 트랙 복원 보장
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !self.player.videoTracks.isEmpty {
                        self.player.selectTrack(at: 0, type: .video)
                    }
                }
            }
        } else {
            player.deselectAllVideoTracks()
        }
    }

    /// 백그라운드 모드 시 통계 수집 주기 조절
    public func setTimeUpdateMode(background: Bool) {
        if background {
            statsTask?.cancel()
            statsTask = nil
        } else {
            startStatsTimer()
        }
    }

    // MARK: - 녹화

    public var isRecording: Bool { stateLock.withLock { _isRecording } }

    public func startRecording(to url: URL) async throws {
        guard !stateLock.withLock({ _isRecording }) else { return }
        player.startRecording(atPath: url.path)
        stateLock.withLock { _isRecording = true }
    }

    public func stopRecording() async {
        guard stateLock.withLock({ _isRecording }) else { return }
        player.stopRecording()
        stateLock.withLock { _isRecording = false }
    }

    /// 스냅샷 저장 후 URL 반환
    public func captureSnapshot() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let name = "snapshot_\(Int(Date().timeIntervalSince1970)).png"
        let url = dir.appendingPathComponent(name)
        player.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 버퍼 상태

    public func bufferHealth() -> BufferHealth {
        guard let stats = player.media?.statistics else {
            return BufferHealth(currentLevel: 0, targetLevel: 1.0, isHealthy: true)
        }
        let displayed = max(Int(stats.displayedPictures), 0)
        let decoded   = max(Int(stats.decodedVideo), 1)
        let lost      = max(Int(stats.lostPictures), 0)
        let ratio     = Float(displayed) / Float(decoded)
        let isBuffering = player.state == .buffering
        let isHealthy   = displayed > 0 && lost == 0 && !isBuffering
        return BufferHealth(currentLevel: Double(ratio), targetLevel: 1.0, isHealthy: isHealthy)
    }

    // MARK: - 오디오 트랙

    public func audioTracks() -> [(Int, String)] {
        return player.audioTracks.enumerated().map { (i, t) in (i, t.trackName) }
    }

    public func setAudioTrack(_ index: Int) {
        player.selectTrack(at: index, type: .audio)
    }

    // MARK: - 이퀄라이저

    public func equalizerPresets() -> [String] {
        return VLCAudioEqualizer.presets.map { $0.name }
    }

    public func setEqualizerPreset(_ index: Int) {
        let presets = VLCAudioEqualizer.presets
        guard index >= 0 && index < presets.count else { return }
        player.equalizer = VLCAudioEqualizer(preset: presets[index])
    }

    public func setEqualizerPresetByName(_ name: String) {
        let presets = VLCAudioEqualizer.presets
        guard let index = presets.firstIndex(where: { $0.name == name }) else { return }
        setEqualizerPreset(index)
    }

    public func setEqualizerPreAmp(_ value: Float) {
        guard let eq = player.equalizer else { return }
        eq.preAmplification = value
        player.equalizer = eq
    }

    public func setEqualizerBand(index: Int, value: Float) {
        guard let eq = player.equalizer else { return }
        let bands = eq.bands
        guard index >= 0 && index < bands.count else { return }
        bands[index].amplification = value
        player.equalizer = eq
    }

    public func equalizerBandCount() -> Int {
        return player.equalizer?.bands.count ?? VLCAudioEqualizer().bands.count
    }

    public func equalizerBandValues() -> [Float] {
        guard let eq = player.equalizer else { return [] }
        return eq.bands.map { $0.amplification }
    }

    public func equalizerBandFrequencies() -> [Float] {
        let eq = player.equalizer ?? VLCAudioEqualizer()
        return eq.bands.map { $0.frequency }
    }

    public func equalizerPreAmpValue() -> Float {
        return player.equalizer?.preAmplification ?? 0
    }

    public func resetEqualizer() {
        player.equalizer = nil
    }

    // MARK: - 비디오 조정 필터

    public func setVideoAdjustEnabled(_ enabled: Bool) {
        player.adjustFilter.isEnabled = enabled
    }

    public func setVideoBrightness(_ value: Float) {
        player.adjustFilter.brightness.value = NSNumber(value: value)
    }

    public func setVideoContrast(_ value: Float) {
        player.adjustFilter.contrast.value = NSNumber(value: value)
    }

    public func setVideoSaturation(_ value: Float) {
        player.adjustFilter.saturation.value = NSNumber(value: value)
    }

    public func setVideoHue(_ value: Float) {
        player.adjustFilter.hue.value = NSNumber(value: value)
    }

    public func setVideoGamma(_ value: Float) {
        player.adjustFilter.gamma.value = NSNumber(value: value)
    }

    public func resetVideoAdjust() {
        player.adjustFilter.resetParametersIfNeeded()
        player.adjustFilter.isEnabled = false
    }

    // MARK: - 화면비율 / 크롭 / 스케일

    public func setAspectRatio(_ ratio: String?) {
        player.videoAspectRatio = ratio
    }

    public func setCropRatio(numerator: UInt32, denominator: UInt32) {
        player.setCropRatioWithNumerator(UInt32(numerator), denominator: UInt32(denominator))
    }

    public func setScaleFactor(_ scale: Float) {
        player.scaleFactor = scale
    }

    // MARK: - 자막 트랙

    public func textTracks() -> [(Int, String)] {
        return player.textTracks.enumerated().map { (i, t) in (i, t.trackName) }
    }

    public func selectTextTrack(_ index: Int) {
        let tracks = player.textTracks
        guard index >= 0 && index < tracks.count else { return }
        tracks[index].isSelectedExclusively = true
    }

    public func deselectAllTextTracks() {
        player.deselectAllTextTracks()
    }

    public func addSubtitleFile(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    public func setSubtitleDelay(_ delay: Int) {
        player.currentVideoSubTitleDelay = delay
    }

    public func setSubtitleFontScale(_ scale: Float) {
        player.currentSubTitleFontScale = scale
    }

    // MARK: - 오디오 스테레오 / 믹스 모드

    public func setAudioStereoMode(_ mode: UInt) {
        guard let stereoMode = VLCMediaPlayer.AudioStereoMode(rawValue: mode) else { return }
        player.audioStereoMode = stereoMode
    }

    public func currentAudioStereoMode() -> UInt {
        return player.audioStereoMode.rawValue
    }

    public func setAudioMixMode(_ mode: UInt32) {
        guard let mixMode = VLCMediaPlayer.AudioMixMode(rawValue: mode) else { return }
        player.audioMixMode = mixMode
    }

    public func currentAudioMixMode() -> UInt32 {
        player.audioMixMode.rawValue
    }

    /// 오디오 지연 설정 (마이크로초)
    public func setAudioDelay(_ delay: Int) {
        Task { @MainActor [weak self] in
            self?.player.currentAudioPlaybackDelay = delay
        }
    }

    public func currentAudioDelay() -> Int {
        player.currentAudioPlaybackDelay
    }

    // MARK: - 고급 설정 일괄 적용 (PlayerSettings)

    public func applyAdvancedSettings(_ settings: PlayerSettings) {
        // 이퀄라이저
        if let preset = settings.equalizerPreset {
            setEqualizerPresetByName(preset)
            setEqualizerPreAmp(settings.equalizerPreAmp)
            for (i, val) in settings.equalizerBands.enumerated() {
                setEqualizerBand(index: i, value: val)
            }
        } else {
            resetEqualizer()
        }
        // 비디오 조정
        setVideoAdjustEnabled(settings.videoAdjustEnabled)
        if settings.videoAdjustEnabled {
            setVideoBrightness(settings.videoBrightness)
            setVideoContrast(settings.videoContrast)
            setVideoSaturation(settings.videoSaturation)
            setVideoHue(settings.videoHue)
            setVideoGamma(settings.videoGamma)
        }
        // 화면 비율
        setAspectRatio(settings.aspectRatio)
        // 오디오 고급
        setAudioStereoMode(UInt(settings.audioStereoMode))
        setAudioMixMode(settings.audioMixMode)
        setAudioDelay(Int(settings.audioDelay))
    }

    // MARK: - Private Helpers

    private func _setPhase(_ phase: PlayerState.Phase) {
        stateLock.withLock { _currentPhase = phase }
        onStateChange?(phase)
    }

    private func startStatsTimer() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초
                guard !Task.isCancelled, let self else { break }
                await self.collectMetrics()
            }
        }
    }

    @MainActor
    private func collectMetrics() {
        guard let stats = player.media?.statistics else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(_lastMetricsTime)
        _lastMetricsTime = now

        let prev = _prevStats
        _prevStats = stats

        let droppedDelta = Int(stats.lostPictures) - Int(prev?.lostPictures ?? 0)
        let decodedDelta = Int(stats.decodedVideo) - Int(prev?.decodedVideo ?? 0)
        let audioLostDelta = Int(stats.lostAudioBuffers) - Int(prev?.lostAudioBuffers ?? 0)
        let lateDelta = Int(stats.latePictures) - Int(prev?.latePictures ?? 0)
        let demuxCorruptDelta = Int(stats.demuxCorrupted) - Int(prev?.demuxCorrupted ?? 0)
        let demuxDiscDelta = Int(stats.demuxDiscontinuity) - Int(prev?.demuxDiscontinuity ?? 0)

        let inputKbps = Double(stats.inputBitrate) * 8.0
        let demuxKbps = Double(stats.demuxBitrate) * 8.0
        let netBytesPerSec = Int(stats.inputBitrate * 1024)
        let fps = elapsed > 0 ? Double(max(0, decodedDelta)) / elapsed : 0.0

        let size = player.videoSize
        let resolution = size.width > 0 ? "\(Int(size.width))x\(Int(size.height))" : nil

        let metrics = VLCLiveMetrics(
            fps: fps,
            droppedFramesDelta: max(0, droppedDelta),
            decodedFramesDelta: max(0, decodedDelta),
            networkBytesPerSec: max(0, netBytesPerSec),
            inputBitrateKbps: inputKbps,
            demuxBitrateKbps: demuxKbps,
            resolution: resolution,
            videoWidth: Double(size.width),
            videoHeight: Double(size.height),
            playbackRate: player.rate,
            bufferHealth: bufferHealth().currentLevel,
            lostAudioBuffersDelta: max(0, audioLostDelta),
            latePicturesDelta: max(0, lateDelta),
            demuxCorruptedDelta: max(0, demuxCorruptDelta),
            demuxDiscontinuityDelta: max(0, demuxDiscDelta)
        )
        onVLCMetrics?(metrics)
    }
}

// MARK: - VLCMediaPlayerDelegate (VLCKit 4.0)

extension VLCPlayerEngine: VLCMediaPlayerDelegate {

    /// 재생 상태 변경 — VLCKit 4.0: State를 직접 파라미터로 받음 (Notification 아님)
    ///
    /// [프레임 기반 버퍼링 필터링]
    /// VLC는 라이브 HLS 중 네트워크 버퍼를 채울 때 수시로 .buffering 상태를 보고하지만,
    /// 이 시점에도 프레임이 실제로 디코딩/표시되고 있을 수 있다.
    /// VLC가 .buffering을 보고해도 최근 프레임이 디코딩되었다면 상위 레이어에 전파하지 않는다.
    /// 이로써 "영상은 잘 나오는데 버퍼링 스피너가 계속 뜨는" 문제를 엔진 레벨에서 차단.
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        let phase: PlayerState.Phase
        switch newState {
        case .opening:
            phase = .loading
        case .buffering:
            // 프레임 기반 필터링: 이미 재생 중이었고 프레임이 디코딩되고 있으면
            // .buffering 상태를 상위에 전파하지 않는다 (VLC 내부 버퍼 리필일 뿐)
            if case .playing = stateLock.withLock({ _currentPhase }) {
                let decoded = player.media?.statistics.decodedVideo ?? 0
                if decoded > 0 {
                    // 프레임이 디코딩되고 있으므로 실제 재생 중단이 아님 — 무시
                    return
                }
            }
            phase = .buffering(progress: 0)
        case .playing:
            phase = .playing
        case .paused:
            phase = .paused
        case .stopped, .stopping:
            phase = .idle
        case .error:
            phase = .error(.decodingFailed("VLC 재생 오류"))
        @unknown default:
            phase = .loading
        }
        _setPhase(phase)
    }

    /// 재생 위치 변경 — VLCKit 4.0: Notification 파라미터
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let t = TimeInterval(player.time.intValue) / 1000.0
        let d = TimeInterval(player.media?.length.intValue ?? 0) / 1000.0
        onTimeChange?(t, d)
    }

    /// 미디어 길이 확정 — VLCKit 4.0: Int64 직접 파라미터
    public func mediaPlayerLengthChanged(_ length: Int64) {
        let t = TimeInterval(player.time.intValue) / 1000.0
        let d = TimeInterval(length) / 1000.0
        onTimeChange?(t, d)
    }

    // MARK: - 트랙 Delegate

    public func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .added))
    }

    public func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .removed))
    }

    public func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .updated))
    }

    public func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: selectedId, trackType: type, kind: .selected(unselectedId: unselectedId)))
    }

    private func playerTrackType(_ vlcType: VLCMedia.TrackType) -> PlayerTrackType {
        switch vlcType {
        case .audio: return .audio
        case .video: return .video
        case .text: return .text
        @unknown default: return .unknown
        }
    }
}
