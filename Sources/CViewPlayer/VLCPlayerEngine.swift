// MARK: - VLCPlayerEngine.swift
// CViewPlayer — 재작성된 VLC 플레이어 엔진
//
// [설계 원칙]
// • 내부 복구/워치독/재시도 로직 없음 — 깔끔한 VLC API 래퍼
// • play() → VLC에 위임, 상태 콜백으로 외부 통보
// • stop() → 안전한 순서: stop() → drawable=nil (media=nil은 VLCKit 4.0 크래시 방지로 호출 금지)
// • streamingProfile 로 미디어 옵션 설정
// • 모든 VLC 고급 API (EQ, 비디오조정, 자막, 오디오 등) 보존

import Foundation
import AppKit
import QuartzCore
import Synchronization
import CViewCore
@preconcurrency import VLCKitSPM

// MARK: - VLC 비디오 컨테이너 뷰

/// VLC 렌더링 서피스를 호스팅하는 컨테이너 NSView.
/// player.drawable = 이 뷰로 설정하면 VLC가 내부적으로 서브뷰를 추가해 렌더링.
public final class VLCLayerHostView: NSView {
    weak var boundPlayer: VLCMediaPlayer?
    weak var boundEngine: VLCPlayerEngine?

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        canDrawSubviewsIntoLayer = false
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        // VLC가 자체 Metal 렌더링 레이어를 서브레이어로 추가·관리하므로
        // 컨테이너 레이어 비동기 드로잉을 끄면 GPU 이중 합성 패스가 제거됨
        layer.drawsAsynchronously = false
        layer.allowsGroupOpacity = false
        layer.actions = [
            "onOrderIn": NSNull(), "onOrderOut": NSNull(),
            "sublayers": NSNull(), "contents": NSNull(),
            "bounds": NSNull(), "position": NSNull(), "transform": NSNull()
        ]
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        // drawable 재할당을 layout() 에서 수행하지 않음:
        // player.drawable = view 는 VLC 렌더 파이프라인 재초기화를 트리거하는 무거운 작업.
        // 잦은 layout() 호출(리사이즈, SwiftUI 재계산 등)마다 재초기화되면 GPU 스파이크 발생.
        // play() 직전 _startPlay() 에서 한 번만 설정하고, refreshDrawable() 로 명시적 복구.
    }

    /// 선명한 화면(픽셀 샤프 스케일링) 토글.
    /// VLC 가 생성하는 서브레이어(Metal/CAMetalLayer) 들에 대해 magnificationFilter 를
    /// nearest 로 전환한다. (CA 합성 경로에서만 유효; 일부 Metal 직통 출력에서는 효과 제한)
    public func setSharpScaling(_ enabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let mag: CALayerContentsFilter = enabled ? .nearest : .linear
        let min: CALayerContentsFilter = enabled ? .nearest : .trilinear
        layer?.magnificationFilter = mag
        layer?.minificationFilter = min
        // VLC 가 렌더 타겟으로 추가한 서브레이어 전체에 적용
        layer?.sublayers?.forEach { sub in
            sub.magnificationFilter = mag
            sub.minificationFilter = min
        }
    }

    /// 현재 적용된 GPU 렌더 계층 (기본 active = 풀 품질)
    private var _gpuRenderTier: SessionTier = .active

    /// 멀티라이브 GPU 렌더 계층에 따라 Metal drawable 해상도(contentsScale)와
    /// 레이어 가시성을 조정한다.
    ///
    /// VLC 가 생성하는 CAMetalLayer 서브레이어의 `contentsScale` 을 조정하면
    /// Metal drawable 크기 = `bounds × contentsScale` 이 줄어들어, GPU가 렌더링하는
    /// 픽셀 수가 비례하여 감소한다. (예: 2.0 → 1.5 = 43% 픽셀 감소)
    ///
    /// - `.active`   : 풀 백킹 스케일 (Retina 원본 선명도)
    /// - `.visible`  : 백킹 × 0.75 (약 44% 픽셀 감소, 비선택 패널 스케일링 자연스러움 유지)
    /// - `.hidden`   : 레이어 자체 숨김 (GPU 합성 패스 완전 생략)
    ///
    /// 디코딩 품질/해상도와는 독립적 — quality-lock 모드(1080p 유지)에서도 안전하게 동작.
    public func setGPURenderTier(_ tier: SessionTier) {
        _gpuRenderTier = tier
        applyGPURenderTier()
    }

    /// 현재 저장된 tier 를 실제 레이어에 반영. 서브레이어가 뒤늦게 추가되어도
    /// (VLC 가 play 시점에 Metal layer 를 붙임) `layout()` 등에서 재호출 가능.
    fileprivate func applyGPURenderTier() {
        guard let layer else { return }
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        // [Phase E] Low Power Mode 활성 시 비선택(.visible) 세션을 0.75 → 0.625 로 추가 다운.
        // 약 60% 픽셀 감소 → GPU/배터리 절감 ↑. 선택(.active) 세션은 화질 유지.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let visibleFactor: CGFloat = lowPower ? 0.625 : 0.75
        let targetScale: CGFloat
        let shouldHide: Bool
        switch _gpuRenderTier {
        case .active:
            targetScale = backing
            shouldHide = false
        case .visible:
            // 0.75× → 44% 픽셀 감소. 그리드 셀은 원본보다 작게 표시되므로
            // 시각적 열화는 미미하되 GPU 합성/샘플링 비용이 크게 감소한다.
            // Low Power Mode: 0.625× → 약 60% 픽셀 감소.
            targetScale = max(1.0, backing * visibleFactor)
            shouldHide = false
        case .hidden:
            // 비디오 트랙은 VLC 가 이미 중단 (setVideoTrackEnabled(false)),
            // 레이어 숨김으로 CA 합성 패스까지 완전 제거
            targetScale = backing
            shouldHide = true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.isHidden = shouldHide
        layer.contentsScale = targetScale
        layer.sublayers?.forEach { sub in
            sub.contentsScale = targetScale
        }
        CATransaction.commit()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // 스크린 전환 시 tier 재적용 (백킹 스케일 변경 반영)
        applyGPURenderTier()
    }
}

// MARK: - 화질 적응 액션

/// 1080p+ABR 하이브리드 화질 전환 요청 타입.
public enum QualityAdaptationAction: Sendable {
    case downgrade(reason: String)
    case upgrade(reason: String)
}

// MARK: - 세션 계층 (멀티라이브 3-Tier)

/// 멀티라이브 리소스 배분을 위한 세션 계층.
/// - active: 선택된 포그라운드 세션 (1080p, 최고 품질)
/// - visible: 그리드에 보이지만 비선택 (480p, 성능 우선)
/// - hidden: 화면에 보이지 않음 (비디오 비활성화, 오디오만 또는 완전 중단)
public enum SessionTier: Int, Sendable, Comparable {
    case active = 0    // Tier 1: 선택 세션
    case visible = 1   // Tier 2: 가시 비선택
    case hidden = 2    // Tier 3: 비가시

    public static func < (lhs: SessionTier, rhs: SessionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 스트리밍 프로파일

/// VLC 스트리밍 시나리오별 캐싱 프로파일.
/// - ultraLow: 최저 지연 (네트워크 안정적인 유선/고속WiFi 전용)
/// - lowLatency: 저지연 기본값 (대부분의 라이브 시청)
/// - multiLive: 멀티라이브 (GPU/메모리 절약 우선)
public enum VLCStreamingProfile: Sendable {
    case ultraLow             // 라이브 (최저 지연, 유선/고속WiFi 전용)
    case lowLatency           // 라이브 (저지연 기본)
    case multiLive            // 멀티라이브 비선택 세션 (GPU/메모리 절약 우선)
    case multiLiveHQ          // 멀티라이브 선택 세션 (1080p60 / 8Mbps 유지)

    // [Fix 19] 네트워크 지터 흡수 + 초기 재생 지연 균형
    // lowLatency 500ms: 2초 세그먼트 25% 커버리지, prefetch 병용
    // multiLive 1000→1500ms: 1초 세그먼트 커버 + 0.5초 지터 마진
    //   (2000ms는 4스트림에서 VLC 버퍼 경합 유발, 1000ms는 지터 흡수 부족)
    var networkCaching: Int {
        switch self {
        case .ultraLow: return 300
        case .lowLatency: return 500
        case .multiLive: return 1500     // 1000→1500ms: 지터 흡수 마진 확보
        case .multiLiveHQ: return 800    // 선택 HQ: 지터 흡수는 유지하되 저지연 쪽으로 이동
        }
    }
    public var liveCaching: Int {
        switch self {
        case .ultraLow: return 300
        case .lowLatency: return 500
        case .multiLive: return 1500     // network-caching과 동일
        case .multiLiveHQ: return 800
        }
    }
    var manifestRefreshInterval: Int {
        switch self {
        case .ultraLow: return 8    // LL-HLS 부분 세그먼트(~200ms) 대응: 빠른 매니페스트 리프레시
        case .lowLatency: return 4  // 10→4s: 2×TARGETDURATION(2s) — 새 세그먼트 조기 발견으로 레이턴시 단축
        case .multiLive: return 20  // 멀티라이브 비선택: 네트워크 부하 절감
        case .multiLiveHQ: return 5 // 선택 HQ: variant 조기 갱신으로 1080p 유지 안정화
        }
    }
    /// clock-jitter 허용 범위 (µs) — 프레임 타이밍 편차 허용량
    /// [Fix 18] multiLive 30ms→10ms: A/V 싱크 허용 오차 축소로 오디오-비디오 동기화 강화
    var clockJitter: Int {
        switch self {
        case .ultraLow: return 0
        case .lowLatency: return 5000
        case .multiLive: return 10000 // 10ms — 영상/소리 싱크 정밀도 향상
        case .multiLiveHQ: return 5000 // 선택 HQ: 저지연 프로파일과 동일한 싱크 정밀도
        }
    }
    /// cr-average 클럭 복구 평균 (ms) — 낮을수록 더 빠른 타이밍 조정
    /// [Fix 18] multiLive 50→30ms: 클럭 복구 가속 → A/V 싱크 보정 속도 향상
    var crAverage: Int {
        switch self {
        case .ultraLow: return 20
        case .lowLatency: return 30
        case .multiLive: return 30  // 50→30ms: A/V 싱크 보정 가속
        case .multiLiveHQ: return 30
        }
    }
    /// 디코딩 스레드 수 — multiLive는 세션이 여러 개이므로 낮게 제한
    var decoderThreads: Int {
        switch self {
        case .ultraLow:   return min(ProcessInfo.processInfo.processorCount, 4)
        case .lowLatency: return min(ProcessInfo.processInfo.processorCount, 4)
        case .multiLive:  return 1  // 다중 세션 GPU/CPU 경합 방지, VideoToolbox 주체
        case .multiLiveHQ: return min(ProcessInfo.processInfo.processorCount, 3) // 선택 세션은 P-core 적극 활용
        }
    }
    /// HLS adaptive 최대 해상도 — 멀티라이브 그리드 셀에서는 해상도 제한
    /// isSelected: 현재 선택된(포그라운드) 세션 여부
    /// [Quality 2026-04-18] 비선택 480p → 720p 완화 — 사용자 선택 시점 즉시 가시 화질 보장
    ///   (이전: 480p 고정 → 선택 후 switchMedia 전까지 480p 유지되는 회귀 발견)
    /// [Quality] 싱글 스트림: 0 = 무제한 (소스 원본 해상도 사용)
    func adaptiveMaxWidth(isSelected: Bool) -> Int {
        switch self {
        case .ultraLow, .lowLatency: return 0  // 무제한 — 소스 원본 해상도
        case .multiLive: return isSelected ? 1920 : 1280
        case .multiLiveHQ: return 0            // 선택 HQ: 무제한 (1080p 유지)
        }
    }
    func adaptiveMaxHeight(isSelected: Bool) -> Int {
        switch self {
        case .ultraLow, .lowLatency: return 0  // 무제한 — 소스 원본 해상도
        case .multiLive: return isSelected ? 1080 : 720
        case .multiLiveHQ: return 0            // 선택 HQ: 무제한 (1080p 유지)
        }
    }
    /// 늦은 프레임 드롭 여부
    /// [Fix 16h-opt3] 모든 프로파일에서 활성화: 늦은 프레임이 큐에 쌓이면
    /// VLC가 뒤처진 프레임을 모두 디코딩하려다 지연 축적 → 결국 리버퍼링 유발
    /// 라이브 스트리밍에서는 늦은 프레임 드롭이 버퍼링 최소화의 핵심
    var dropLateFrames: Bool { true }
    /// skip-frames 활성화 여부 — 디코더 단에서 참조되지 않는 프레임 건너뛰기
    /// [Quality] 싱글 스트림에서는 비활성: 프레임 스킵 없이 원본 품질 유지
    /// multiLive에서만 활성: 디코딩 파이프라인 부하 감소
    var skipFrames: Bool {
        switch self {
        case .ultraLow, .lowLatency: return false
        case .multiLive: return true
        case .multiLiveHQ: return false        // 선택 HQ: 프레임 스킵 금지
        }
    }
    /// avcodec-fast 모드 — 빠른 디코딩 경로 (일부 디블로킹 생략 가능)
    /// [Quality] 싱글 스트림에서는 비활성: 디블로킹 필터 완전 적용으로 블록 아티팩트 방지
    var avcodecFast: Bool {
        switch self {
        case .ultraLow, .lowLatency: return false
        case .multiLive: return true
        case .multiLiveHQ: return false        // 선택 HQ: 디블로킹 완전 적용
        }
    }
    /// 루프필터 스킵 레벨 (0=없음, 1=Non-ref, 4=전체)
    /// [Quality] 싱글 스트림: 0 = 스킵 없음 (원본 품질), multiLive: 4 = 전체 스킵 (GPU 절감)
    var skipLoopFilter: Int {
        switch self {
        case .ultraLow, .lowLatency: return 0
        case .multiLive: return 4
        case .multiLiveHQ: return 0            // 선택 HQ: 루프 필터 유지
        }
    }
    /// avcodec-hurry-up 모드 — 디코더 품질 단계 건너뛰기
    /// [Quality] 싱글 스트림에서는 비활성: 디코더 전체 품질 단계 적용
    var hurryUp: Bool {
        switch self {
        case .ultraLow, .lowLatency: return false
        case .multiLive: return true
        case .multiLiveHQ: return false        // 선택 HQ: 품질 단계 전체 적용
        }
    }

    /// 멀티라이브 계열 프로파일 여부 (`multiLive` / `multiLiveHQ`)
    public var isMultiLiveFamily: Bool {
        switch self {
        case .multiLive, .multiLiveHQ: return true
        default: return false
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

    /// 멀티라이브에서 현재 선택된(포그라운드) 세션인지 여부
    /// adaptive 해상도 결정에 사용 — 그리드 셀은 720p, 선택 세션은 1080p
    public var isSelectedSession: Bool = true

    /// 현재 세션 계층 (멀티라이브 3-Tier 리소스 관리)
    /// .active = 선택 세션 (1080p), .visible = 보이지만 비선택 (480p), .hidden = 비가시
    public var sessionTier: SessionTier = .active

    /// 대역폭 코디네이터가 설정하는 최대 적응 해상도 높이 (0 = 제한 없음)
    /// 화면 캡핑(flashls capLevelToStage) 적용 시 사용
    public var maxAdaptiveHeight: Int = 0

    /// 항상 최고 화질(1080p60) 유지 — true면 ABR 하향/해상도 캡핑/프레임 스킵 비활성화
    public var forceHighestQuality: Bool = true

    /// 스트림 프록시 / 인터셉트 모드. StreamCoordinator 가 재생 시작 직전 주입.
    /// - .directVLCAdaptive : `:demux=adaptive,hls` 강제 + Content-Type 무시
    /// - 그 외              : 기본 자동 데모서 선택
    public var streamProxyMode: StreamProxyMode = .localProxy

    /// 선명한 화면(픽셀 샤프 스케일링) 여부 — play() 이후 drawable 재생성 시에도 자동 재적용
    public var sharpPixelScaling: Bool = false {
        didSet {
            guard oldValue != sharpPixelScaling else { return }
            playerView.setSharpScaling(sharpPixelScaling)
        }
    }

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



    /// 재생 정체 감지 콜백 — 디코딩 프레임 0이 연속 발생할 때 호출
    public var onPlaybackStalled: (@Sendable () -> Void)?

    /// [No-Proxy] VLC 가 chzzk CDN fMP4 응답을 처리하지 못해 FIX14 35초 타임아웃이
    /// 발생했을 때 호출. 상위(PlayerViewModel/MultiLiveManager) 가 이 콜백을 받으면
    /// AVPlayer 엔진으로 자동 전환한다. nil 이면 기존처럼 .error(.networkTimeout) 으로 진입.
    public var onEngineFallbackRequested: (@Sendable (String) -> Void)?

    // MARK: - PlayerEngineProtocol

    public var isPlaying: Bool { player.isPlaying }

    public var currentTime: TimeInterval {
        TimeInterval(player.time.intValue) / 1000.0
    }

    /// VLC 통계의 누적 디코딩 프레임 수 — Watchdog 보조 stall 감지용
    public var decodedVideoFrames: Int32 {
        player.media?.statistics.decodedVideo ?? 0
    }

    public var duration: TimeInterval {
        TimeInterval(player.media?.length.intValue ?? 0) / 1000.0
    }

    public var rate: Float { player.rate }

    public var videoView: NSView { playerView }

    // MARK: - VLC 내부

    let player: VLCMediaPlayer
    private(set) public var playerView: VLCLayerHostView

    // 상태 (Mutex 격리)
    struct VLCEngineState: Sendable {
        var currentPhase: PlayerState.Phase = .idle
        var isRecording: Bool = false
        var isMuted: Bool = false
        var volume: Float = 1.0
    }
    let _state = Mutex(VLCEngineState())
    var statsTask: Task<Void, Never>?
    var playTask: Task<Void, Never>?

    // 이전 통계 (delta 계산용)
    var _prevStats: VLCMedia.Stats?
    var _lastMetricsTime: Date = Date()

    // 재생 정체 감지 (0-프레임 연속 횟수)
    var _zeroFrameCount: Int = 0
    // 2회 연속 0프레임: lowLatency=4초, multiLive=8초 내 정체 감지 (3→2회)
    let _zeroFrameStallThreshold: Int = 2

    // [Fix 20 Phase3] 버퍼 건강도: I/O 비율 + 프레임 전달률 EWMA 추적
    var _ioHealthEWMA: Double = 1.0      // input/demux 바이트 비율 (1.0 = 정상)
    var _frameDeliveryEWMA: Double = 1.0 // 프레임 전달 성공률 (1.0 = 모든 프레임 표시)

    // [Fix 27] 버퍼링 필터 상태 — VLC delegate 스레드 + Main 스레드 동시 접근 보호
    struct _BufferingFilterState: Sendable {
        var lastDecodedCount: Int32 = 0
        var filterStartTime: Date?
    }
    let _bufferingFilter = Mutex(_BufferingFilterState())

    // _setPhase 중복 호출 방지: 동일 phase 연속 콜백 억제
    // VLC가 같은 상태를 수십 ms 간격으로 반복 보고해도 onStateChange 1회만 호출
    var _lastEmittedPhase: PlayerState.Phase?

    // collectMetrics() player.videoSize 캐싱 (MainActor 동기 호출 최소화)
    var _cachedVideoSize: CGSize = .zero
    var _cachedResolutionString: String? = nil

    // [Opt-B3] 통계 기반 화질 적응 — 연속 품질 저하/안정 카운터
    var _qualityDegradeCount: Int = 0   // 연속 프레임 드롭 감지 횟수
    var _qualityStableCount: Int = 0    // 연속 안정 감지 횟수

    // mediaPlayerTimeChanged 스로틀링 — 초당 10~30회 콜백을 1초 간격으로 제한
    var _lastTimeChangeNotify: UInt64 = 0
    let _timeChangeThrottleNs: UInt64 = 2_000_000_000  // 2초 (CPU 최적화: 1→2초)

    // Fix 12: VLC 4.0 fMP4 디먹서 폴백 버그 대응
    var _startPlayRetryTask: Task<Void, Never>?

    // [플리커 방지] drawable refresh 쿨다운 시각
    var _lastDrawableRefreshTime: Date?

    // MARK: - Init / Deinit

    public override init() {
        player = VLCMediaPlayer()
        playerView = VLCLayerHostView()
        super.init()
        playerView.boundPlayer = player
        playerView.boundEngine = self
        player.delegate = self
    }

    deinit {
        statsTask?.cancel()
        playTask?.cancel()
        _startPlayRetryTask?.cancel()
        // VLCKit 4.0 크래시 방지:
        // player.media = nil 명시 호출 시 VLC 내부 on_current_media_changed
        // 이벤트에서 이미 해제된 libvlc_media_t*를 retain 시도 → 크래시.
        //
        // 해결: delegate만 해제하여 콜백 차단하고, stop()만 호출.
        // media 정리는 VLCMediaPlayer 자체 dealloc에 위임.
        // 항상 DispatchQueue.main.async로 통일 — deinit에서 Thread.isMainThread
        // 분기는 actor 정리 경로에서 예측 불가하므로 제거.
        let p = player
        let pv = playerView
        p.delegate = nil
        DispatchQueue.main.async {
            p.stop()
            p.drawable = nil
            // playerView가 player보다 먼저 해제되지 않도록 다음 run loop까지 유지
            withExtendedLifetime(pv) {}
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

    public func pause() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Log.player.debug("[DIAG] pause() called externally — state=\(self.player.state.rawValue)")
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
        Log.player.debug("[DIAG] stop() called externally — state=\(self.player.state.rawValue) isPlaying=\(self.player.isPlaying)")
        playTask?.cancel()
        _startPlayRetryTask?.cancel()
        _startPlayRetryTask = nil
        statsTask?.cancel()
        statsTask = nil
        let p = player
        // 상태 초기화 (Mutex로 보호 — 어느 스레드에서도 안전)
        _state.withLock { $0.currentPhase = .idle }
        if Thread.isMainThread {
            // [장시간 안정성] 메트릭 관련 변수는 collectMetrics()와 동일한
            // MainActor 컨텍스트에서 정리하여 데이터 레이스 방지
            _prevStats = nil
            _bufferingFilter.withLock { $0 = _BufferingFilterState() }
            _zeroFrameCount = 0
            _ioHealthEWMA = 1.0
            _frameDeliveryEWMA = 1.0
            _qualityDegradeCount = 0
            _qualityStableCount = 0
            p.stop()
            p.drawable = nil
            _setPhase(.idle)
        } else {
            // p는 강한 참조로 캡처되어 VLC stop()은 항상 실행됨
            // _setPhase는 콜백 전파용이므로 self가 해제되어도 VLC 리소스 정리는 보장
            DispatchQueue.main.async { [weak self] in
                // [장시간 안정성] 메트릭 관련 변수 정리도 MainActor에서 수행
                self?._prevStats = nil
                self?._bufferingFilter.withLock { $0 = _BufferingFilterState() }
                self?._zeroFrameCount = 0
                self?._ioHealthEWMA = 1.0
                self?._frameDeliveryEWMA = 1.0
                self?._qualityDegradeCount = 0
                self?._qualityStableCount = 0
                p.stop()
                p.drawable = nil
                self?._setPhase(.idle)
            }
        }
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
        _state.withLock { $0.volume = volume }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let muted = _state.withLock { $0.isMuted }
            // VLCKit 4.0: volume 범위 0-100 (이전 *200은 과증폭 유발)
            player.audio?.volume = muted ? 0 : Int32(volume * 100)
        }
    }

    public func setMuted(_ muted: Bool) {
        let vol = _state.withLock { s -> Float in
            s.isMuted = muted
            return s.volume
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            player.audio?.volume = muted ? 0 : Int32(vol * 100)
        }
    }

}
