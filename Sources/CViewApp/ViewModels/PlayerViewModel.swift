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

    // MARK: - 스크린샷 설정

    public var screenshotSavePath: String = "~/Pictures/CView Screenshots"
    public var screenshotSaveFormat: ScreenshotFormat = .png

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

    /// [No-Proxy] VLC 가 chzzk CDN 응답을 처리하지 못해 35초 타임아웃이 발생했을 때 호출.
    /// 단일 라이브에서는 PlayerViewModel 가 내부적으로 AVPlayer 로 재시작하지만,
    /// 멀티라이브(엔진 풀 사용 — `isPreallocated == true`) 에서는 외부 컨테이너가
    /// 엔진을 교체해야 하므로 본 콜백으로 통보만 한다.
    public var onEngineFallbackRequested: (@Sendable (_ reason: String) -> Void)?

    // [Persistence 2026-04-18] 볼륨/음소거 변경 알림 — AppDependencies 에서
    // SettingsStore.player.volumeLevel / startMuted 영구 저장에 연결.
    /// 사용자 볼륨 조절 시 호출 (0.0 ~ 1.0)
    public var onVolumeChanged: ((Float) -> Void)?
    /// 음소거 토글 시 호출
    public var onMuteChanged: ((Bool) -> Void)?

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
        } else if let hlsjs = engine as? HLSJSPlayerEngine {
            self.currentEngineType = .hlsjs
            hlsjs.streamingProfile = .multiLive
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
        case .hlsjs:
            let e = HLSJSPlayerEngine()
            e.streamingProfile = .lowLatency
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
                    let bh = metrics.bufferHealth
                    Task { await coordinator?.recordBandwidthSample(bytesLoaded: bytes, duration: 2.0, bufferHealth: bh) }
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
            avEngine.emitCurrentMetricsSnapshot()
        } else {
            avEngine.onAVMetrics = nil
        }
    }

    // MARK: - HLS.js 메트릭 콜백

    public func setHLSJSMetricsCallback(_ callback: (@Sendable (HLSJSLiveMetrics) -> Void)?) {
        guard let hlsjs = playerEngine as? HLSJSPlayerEngine else { return }
        if let callback = callback {
            hlsjs.onHLSJSMetrics = { metrics in
                callback(metrics)
            }
        } else {
            hlsjs.onHLSJSMetrics = nil
        }
    }

    /// 현재 엔진의 목표 레이턴시를 밀리초 단위로 반환.
    /// 서버 하트비트의 targetLatency 필드와 동기화 제어에 사용한다.
    public func currentTargetLatencyMs() -> Double? {
        if let vlc = playerEngine as? VLCPlayerEngine {
            return Double(vlc.streamingProfile.liveCaching)
        }
        if let av = playerEngine as? AVPlayerEngine {
            return av.catchupConfig.targetLatency * 1000.0
        }
        if let hlsjs = playerEngine as? HLSJSPlayerEngine {
            switch hlsjs.streamingProfile {
            case .ultraLow:
                return 1_000
            case .lowLatency:
                return 2_000
            case .multiLive:
                return 3_000
            }
        }
        return nil
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
                    let bh = metrics.bufferHealth
                    Task { await coordinator?.recordBandwidthSample(bytesLoaded: bytes, duration: 2.0, bufferHealth: bh) }
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
    /// 
    /// 속도 범위는 MetricsForwarder의 validateAndComputeSyncSpeed()에서 이미 계산되어
    /// 델타 크기에 비례한 값이 넘어옴 (최대 ±0.05). 안전 하한/상한만 적용.
    /// 버퍼 상태에 따라 가속을 제한하여 버퍼링을 방지합니다.
    public func applySyncSpeed(_ speed: Float) {
        Task { @MainActor [weak self] in
            guard let self, let engine = self.playerEngine else { return }

            // 버퍼 상태 기반 가속 제한 — 버퍼가 낮으면 가속을 억제
            let bh = self.latestMetrics?.bufferHealth ?? 1.0
            let maxAllowed: Float
            if bh < 0.3 {
                // 버퍼 위험 — 가속 금지, 감속만 허용
                maxAllowed = 1.0
            } else if bh < 0.6 {
                // 버퍼 주의 — 미세 가속만 허용 (최대 1.02)
                maxAllowed = 1.02
            } else {
                // 버퍼 정상 — 완화된 범위 허용 (최대 1.08)
                maxAllowed = 1.08
            }

            let clamped = max(0.93, min(maxAllowed, speed))
            engine.setRate(clamped)
        }
    }

    public func applySettings(volume: Float, lowLatency: Bool, catchupRate: Double) {
        self.volume = volume
        playerEngine?.setVolume(isMuted ? 0 : volume)
        // multiLive 프로파일은 MultiLiveManager가 injectEngine()으로 설정하므로
        // lowLatency 설정이 활성화되어도 multiLive를 덮어쓰지 않는다.
        // multiLive 세션에서 lowLatency로 변경하면 재연결 시 잘못된 VLC 옵션이 적용됨.
        // [Quality 2026-04-18] multiLiveHQ 도 보호 대상에 포함 — isMultiLiveFamily 사용.
        if lowLatency {
            if let vlc = playerEngine as? VLCPlayerEngine,
               !vlc.streamingProfile.isMultiLiveFamily {
                vlc.streamingProfile = .lowLatency
            }
        }
    }

    /// [Quality Lock] 최고 화질 유지 설정 — 런타임 변경 시 모든 엔진에 즉시 반영
    /// VLC: forceHighestQuality / maxAdaptiveHeight 0
    /// AVPlayer: isQualityLocked + lockedPeakBitRate=8Mbps + lockedMaximumResolution=1920×1080
    /// (잠금 해제 시 AVPlayer 는 시스템 자동 ABR 로 복귀)
    public func applyForceHighestQuality(_ enabled: Bool) {
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.forceHighestQuality = enabled
            if enabled {
                vlc.maxAdaptiveHeight = 0
            }
        }
        if let av = playerEngine as? AVPlayerEngine {
            if enabled {
                // 잠금 활성 — 1080p60 / 8Mbps 명시 설정 (디폴트 동일)
                av.lockedPeakBitRate = 8_000_000
                av.lockedMaximumResolution = CGSize(width: 1920, height: 1080)
            }
            av.isQualityLocked = enabled
        }
    }

    /// [백그라운드 화질 유지] macOS 앱 백그라운드/포그라운드/occlusion 전환 시 화질 ceiling을 즉시 재확인.
    ///
    /// 배경
    /// - 앱이 백그라운드일 때 macOS가 렌더링/디코딩을 스로틀링하면 AVPlayer/VLC 내부 ABR이
    ///   "소비 속도가 느림"으로 해석해 720p 이하 variant 로 다운시프트 후 고정될 수 있다.
    /// - `isQualityLocked=true` 라도 AVPlayer 내부 ABR 은 ceiling 밑에서 자유롭게 움직이므로,
    ///   한 번 저화질에 갇히면 `startHQRecoveryWatchdog` 의 18s/60s 쿨다운 없이 즉시 복구하려면
    ///   외부에서 명시적으로 nudge 를 보내야 한다.
    ///
    /// 동작
    /// - AVPlayer: `nudgeQualityCeiling` 호출 → 250ms 동안 ceiling 해제 후 복원,
    ///   AVFoundation 내부 ABR 이 즉시 상위 variant 재평가.
    /// - VLC: 미디어 옵션은 재생 시점 고정이므로 런타임 변경 불가. `forceHighestQuality` 플래그만
    ///   재확인해 `StreamCoordinator+QualityABR` 의 downgrade 거부 로직이 유지되도록 한다.
    public func reassertHighestQuality(reason: String) {
        guard let engine = playerEngine else { return }
        if let av = engine as? AVPlayerEngine {
            av.nudgeQualityCeiling(reason: reason)
        }
        if let vlc = engine as? VLCPlayerEngine {
            // 플래그 상태만 재확인 — false 로 떨어졌다면 그대로 둔다(사용자 설정 존중).
            if vlc.forceHighestQuality {
                vlc.maxAdaptiveHeight = 0
            }
        }
    }

    // MARK: - Phase D — 윈도우 가림 시 GPU 합성 정지/복원

    /// 메인 윈도우가 완전히 가려졌을 때 비디오 레이어를 `.hidden` 으로 강등.
    /// 디코딩/오디오는 영향 없음 — Metal 합성 패스만 정지.
    public func engine_setGPURenderTier_hidden() {
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.setGPURenderTier(.hidden)
        }
        if let av = playerEngine as? AVPlayerEngine {
            av.setGPURenderTier(.hidden)
        }
    }

    /// 윈도우 노출 복귀 시 비디오 레이어를 `.active` 로 복원.
    public func engine_setGPURenderTier_active() {
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.setGPURenderTier(.active)
        }
        if let av = playerEngine as? AVPlayerEngine {
            av.setGPURenderTier(.active)
        }
    }

    /// 선명한 화면(픽셀 샤프 스케일링) 설정 — VLC/AV 양쪽 엔진에 즉시 반영
    public func applySharpPixelScaling(_ enabled: Bool) {
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.sharpPixelScaling = enabled
        }
        if let av = playerEngine as? AVPlayerEngine {
            av.setSharpPixelScaling(enabled)
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

        // VLC: drawable 재바인딩이 필요한 경우는 PlayerContainerView.attachVideoView()에서 처리.
        // vout은 항상 살아있으므로 (비디오 트랙 토글 없음) 여기서 drawable 리셋을 하면
        // 불필요한 검은 프레임(플리커)이 발생한다. statsTimer 업데이트 모드만 복원.
        if let vlcEngine = engine as? VLCPlayerEngine {
            vlcEngine.setTimeUpdateMode(background: false)
        }

        // AVPlayer: 백그라운드에서 macOS가 자동 일시정지한 경우 재개
        if let avEngine = engine as? AVPlayerEngine {
            avEngine.isBackgroundMode = false
            if !avEngine.isPlaying && !avEngine.isInErrorState {
                avEngine.resume()
            }
        }

        // HLS.js: 라이브 엣지로 seek (백그라운드 동안 쌓인 버퍼 스킵)
        if let hlsEngine = engine as? HLSJSPlayerEngine {
            hlsEngine.seekToLiveEdge()
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
        // [Quality Lock] 레이턴시 동기화(lowLatencyMode/catchupRate>1.0) 활성 시
        // forceHighestQuality 가 꺼져 있어도 1080p60/8Mbps 화질 잠금을 자동 강제.
        // — sync 가속 중 ABR 강등으로 화질이 떨어지는 회귀 차단.
        // [P0-2 2026-04-24] 멀티라이브에서는 sync 활성만으로 forceMax 자동 잠금하지 않는다.
        //   이유: 모든 세션을 1080p로 묶으면 대역폭 코디네이터/비선택 절약 정책이 무력화되어
        //   디코딩/프록시/GPU 병목으로 잦은 버퍼링이 발생함. 사용자가 명시적으로
        //   forceHighestQuality 를 켠 경우에만 잠금. 단일 라이브는 기존 거동 유지.
        let userForceMax = playerSettings?.forceHighestQuality ?? true
        let syncActive = (playerSettings?.lowLatencyMode ?? true) || ((playerSettings?.catchupRate ?? 1.0) > 1.0)
        let requestedForceMax = isMultiLive ? userForceMax : (userForceMax || syncActive)
        // [Quality 2026-04-18] 멀티라이브 + AVPlayer 조합도 forceMax 허용.
        //   이전에는 1080p variant URL 고정이 ABR 우회로 첫 프레임 정지 회귀를 유발한다는
        //   우려로 차단했으나, AVPlayerEngine 의 isQualityLocked(8Mbps/1080p ceiling) +
        //   HQ recovery watchdog 가 회복 경로를 보장하므로 차단을 해제하여 비선택→선택
        //   전환 시에도 1080p 변종이 즉시 선택되도록 한다.
        let forceMax = requestedForceMax
        let proxyMode = playerSettings?.streamProxyMode ?? .localProxy
        // [Code Review 2026-04-24] 장문 한 줄 → 파라미터별 줄바꿈으로 가독성 개선
        let config = StreamCoordinator.Configuration(
            channelId: channelId,
            enableLowLatency: !isMultiLive,
            enableABR: true,
            lowLatencyConfig: lowLatencyConfig,
            abrConfig: isMultiLive ? .multiLive : .default,
            forceHighestQuality: forceMax,
            streamProxyMode: proxyMode
        )
        // [Fix 26B] 이전 coordinator를 ARC deinit에 의존하지 않고 명시적 정리
        // — LocalStreamProxy NWConnection CLOSE_WAIT 방지
        if let old = streamCoordinator {
            await old.stopStream()
        }
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
        // [Quality Lock] 모든 엔진에 최고 화질 유지 플래그 전파 (1080p60 / 8Mbps)
        if let vlc = engine as? VLCPlayerEngine {
            vlc.forceHighestQuality = forceMax
        }
        if let av = engine as? AVPlayerEngine {
            if forceMax {
                av.lockedPeakBitRate = 8_000_000
                av.lockedMaximumResolution = CGSize(width: 1920, height: 1080)
            }
            av.isQualityLocked = forceMax
        }
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
            // [No-Proxy] FIX14 35초 타임아웃 → AVPlayer 폴백 요청
            vlc.onEngineFallbackRequested = { [weak self] reason in
                Task { @MainActor [weak self] in
                    await self?._handleVLCFallback(reason: reason)
                }
            }
        }

        // HLS.js onStateChange 콜백 연결
        if let hlsjs = engine as? HLSJSPlayerEngine {
            hlsjs.onStateChange = { [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch phase {
                    case .playing:
                        self._bufferingDebounceTask?.cancel()
                        self._bufferingDebounceTask = nil
                        self._lastPlayingTime = Date()
                        self.streamPhase = .playing
                        self.errorMessage = nil
                        self.onPlaybackStateChanged?()
                    case .error:
                        self.streamPhase = .error("HLS.js 재생 오류")
                        self.errorMessage = "HLS.js 재생 오류"
                    default:
                        break
                    }
                }
            }
            hlsjs.onPlaybackStalled = { [weak coordinator] in
                guard let coordinator else { return }
                Task { await coordinator.triggerReconnect(reason: "HLS.js playback stall") }
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
                vlc.onEngineFallbackRequested = nil
            }
            if let hlsjs = engine as? HLSJSPlayerEngine {
                hlsjs.onStateChange = nil
                hlsjs.onHLSJSMetrics = nil
                hlsjs.onPlaybackStalled = nil
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
        // [Fix 25C] 녹화 타이머 방어적 정리 — isRecording 상태 불일치 시에도 누수 방지
        recordingTimerTask?.cancel(); recordingTimerTask = nil

        // VLC 콜백 정리 — 엔진 재사용(풀 반납) 시 이전 세션의 dangling callback 방지
        if let vlc = playerEngine as? VLCPlayerEngine {
            vlc.onStateChange = nil
            vlc.onVLCMetrics = nil
            vlc.onPlaybackStalled = nil
            vlc.onEngineFallbackRequested = nil
        }
        // HLS.js 콜백 정리
        if let hlsjs = playerEngine as? HLSJSPlayerEngine {
            hlsjs.onStateChange = nil
            hlsjs.onHLSJSMetrics = nil
            hlsjs.onPlaybackStalled = nil
        }
        
        uptimeTask?.cancel(); uptimeTask = nil
        eventTask?.cancel(); eventTask = nil
        controlHideTask?.cancel(); controlHideTask = nil
        _bufferingDebounceTask?.cancel(); _bufferingDebounceTask = nil
        _refreshDrawableTask?.cancel(); _refreshDrawableTask = nil
        _lastPlayingTime = nil  // [플리커 방지] 다음 재생 시 초기 drawable refresh 보장

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
        onVolumeChanged?(newVolume)
    }

    public func toggleMute() {
        isMuted.toggle()
        playerEngine?.setVolume(isMuted ? 0 : volume)
        onMuteChanged?(isMuted)
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
