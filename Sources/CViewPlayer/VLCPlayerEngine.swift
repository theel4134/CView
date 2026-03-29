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
}

// MARK: - 화질 적응 액션

/// 1080p+ABR 하이브리드 화질 전환 요청 타입.
public enum QualityAdaptationAction: Sendable {
    case downgrade(reason: String)
    case upgrade(reason: String)
}

// MARK: - 스트리밍 프로파일

/// VLC 스트리밍 시나리오별 캐싱 프로파일.
/// - ultraLow: 최저 지연 (네트워크 안정적인 유선/고속WiFi 전용)
/// - lowLatency: 저지연 기본값 (대부분의 라이브 시청)
/// - multiLive: 멀티라이브 (GPU/메모리 절약 우선)
public enum VLCStreamingProfile: Sendable {
    case ultraLow             // 라이브 (최저 지연, 유선/고속WiFi 전용)
    case lowLatency           // 라이브 (저지연 기본)
    case multiLive            // 멀티라이브 (GPU/메모리 절약 우선)

    // [Fix 17b] 버퍼링 최소화 — 초기 재생 지연 단축 + 네트워크 지터 흡수 균형
    // lowLatency 600→500ms: 2초 세그먼트 25% 커버리지, prefetch 병용으로 보완
    // multiLive 2000→1000ms: 4스트림 동시 재생 시 VLC가 2초 버퍼를 유지하지 못해
    //   buffering 상태에서 빠져나오지 못하는 문제 해결. 1초 버퍼로 더 빠른 playing 전이.
    var networkCaching: Int {
        switch self {
        case .ultraLow: return 300
        case .lowLatency: return 500   // 600→500ms: prefetch-buffer-size 병용
        case .multiLive: return 1000   // 2000→1000ms: 4스트림 동시 버퍼 경합 방지
        }
    }
    public var liveCaching: Int {
        switch self {
        case .ultraLow: return 300
        case .lowLatency: return 500   // network-caching과 동일
        case .multiLive: return 1000   // network-caching과 동일
        }
    }
    var manifestRefreshInterval: Int {
        switch self {
        case .ultraLow: return 8    // LL-HLS 부분 세그먼트(~200ms) 대응: 빠른 매니페스트 리프레시
        case .lowLatency: return 4  // 10→4s: 2×TARGETDURATION(2s) — 새 세그먼트 조기 발견으로 레이턴시 단축
        case .multiLive: return 20  // 멀티라이브: 비활성 세션 네트워크 부하 절감
        }
    }
    /// clock-jitter 허용 범위 (µs) — 프레임 타이밍 편차 허용량
    /// [Fix 18] multiLive 30ms→10ms: A/V 싱크 허용 오차 축소로 오디오-비디오 동기화 강화
    var clockJitter: Int {
        switch self {
        case .ultraLow: return 0
        case .lowLatency: return 5000
        case .multiLive: return 10000 // 10ms — 영상/소리 싱크 정밀도 향상
        }
    }
    /// cr-average 클럭 복구 평균 (ms) — 낮을수록 더 빠른 타이밍 조정
    /// [Fix 18] multiLive 50→30ms: 클럭 복구 가속 → A/V 싱크 보정 속도 향상
    var crAverage: Int {
        switch self {
        case .ultraLow: return 20
        case .lowLatency: return 30
        case .multiLive: return 30  // 50→30ms: A/V 싱크 보정 가속
        }
    }
    /// 디코딩 스레드 수 — multiLive는 세션이 여러 개이므로 낮게 제한
    var decoderThreads: Int {
        switch self {
        case .ultraLow:   return min(ProcessInfo.processInfo.processorCount, 4)
        case .lowLatency: return min(ProcessInfo.processInfo.processorCount, 4)
        case .multiLive:  return 1  // 다중 세션 GPU/CPU 경합 방지, VideoToolbox 주체
        }
    }
    /// HLS adaptive 최대 해상도 — 멀티라이브 그리드 셀에서는 720p로 제한
    /// isSelected: 현재 선택된(포그라운드) 세션 여부
    func adaptiveMaxWidth(isSelected: Bool) -> Int {
        switch self {
        case .ultraLow, .lowLatency: return 1920
        case .multiLive: return isSelected ? 1920 : 1280
        }
    }
    func adaptiveMaxHeight(isSelected: Bool) -> Int {
        switch self {
        case .ultraLow, .lowLatency: return 1080
        case .multiLive: return isSelected ? 1080 : 720
        }
    }
    /// 늦은 프레임 드롭 여부
    /// [Fix 16h-opt3] 모든 프로파일에서 활성화: 늦은 프레임이 큐에 쌓이면
    /// VLC가 뒤처진 프레임을 모두 디코딩하려다 지연 축적 → 결국 리버퍼링 유발
    /// 라이브 스트리밍에서는 늦은 프레임 드롭이 버퍼링 최소화의 핵심
    var dropLateFrames: Bool { true }
    /// skip-frames 활성화 여부 — 디코더 단에서 참조되지 않는 프레임 건너뛰기
    /// [Fix 16h-opt3] 모든 프로파일에서 활성화: 디코딩 파이프라인 부하 감소 → 리버퍼링 감소
    var skipFrames: Bool { true }
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

    // 버퍼링 필터용: 마지막 buffering 이벤트 시점의 decodedVideo 누적값
    // 누적값이 아닌 delta로 비교하여 장시간 재생 후에도 정확한 감지
    var _lastBufferingDecodedCount: Int32 = 0

    // C1 fix: 버퍼링 필터 시간 기반 override
    // .buffering이 delta>0으로 연속 필터링될 때 최초 필터 시각을 기록.
    // 이 시점 이후 5초 이상 지나면 필터링을 중단하고 .buffering을 강제 전파.
    var _bufferingFilterStartTime: Date?

    // _setPhase 중복 호출 방지: 동일 phase 연속 콜백 억제
    // VLC가 같은 상태를 수십 ms 간격으로 반복 보고해도 onStateChange 1회만 호출
    var _lastEmittedPhase: PlayerState.Phase?

    // collectMetrics() player.videoSize 캐싱 (MainActor 동기 호출 최소화)
    var _cachedVideoSize: CGSize = .zero
    var _cachedResolutionString: String? = nil

    // mediaPlayerTimeChanged 스로틀링 — 초당 10~30회 콜백을 1초 간격으로 제한
    var _lastTimeChangeNotify: UInt64 = 0
    let _timeChangeThrottleNs: UInt64 = 2_000_000_000  // 2초 (CPU 최적화: 1→2초)

    // Fix 12: VLC 4.0 fMP4 디먹서 폴백 버그 대응
    var _startPlayRetryTask: Task<Void, Never>?

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
        _prevStats = nil
        _lastBufferingDecodedCount = 0
        _bufferingFilterStartTime = nil
        _state.withLock { $0.currentPhase = .idle }
        if Thread.isMainThread {
            p.stop()
            p.drawable = nil
            _setPhase(.idle)
        } else {
            // p는 강한 참조로 캡처되어 VLC stop()은 항상 실행됨
            // _setPhase는 콜백 전파용이므로 self가 해제되어도 VLC 리소스 정리는 보장
            DispatchQueue.main.async { [weak self] in
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
