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
    var liveCaching: Int {
        switch self {
        case .ultraLow: return 300
        case .lowLatency: return 500   // network-caching과 동일
        case .multiLive: return 1000   // network-caching과 동일
        }
    }
    var manifestRefreshInterval: Int {
        switch self {
        case .ultraLow: return 8    // LL-HLS 부분 세그먼트(~200ms) 대응: 빠른 매니페스트 리프레시
        case .lowLatency: return 10
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

    private let player: VLCMediaPlayer
    private(set) public var playerView: VLCLayerHostView

    // 상태 (Mutex 격리)
    private struct VLCEngineState: Sendable {
        var currentPhase: PlayerState.Phase = .idle
        var isRecording: Bool = false
        var isMuted: Bool = false
        var volume: Float = 1.0
    }
    private let _state = Mutex(VLCEngineState())
    private var statsTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?

    // 이전 통계 (delta 계산용)
    private var _prevStats: VLCMedia.Stats?
    private var _lastMetricsTime: Date = Date()

    // 재생 정체 감지 (0-프레임 연속 횟수)
    private var _zeroFrameCount: Int = 0
    // 2회 연속 0프레임: lowLatency=4초, multiLive=8초 내 정체 감지 (3→2회)
    private let _zeroFrameStallThreshold: Int = 2

    // 버퍼링 필터용: 마지막 buffering 이벤트 시점의 decodedVideo 누적값
    // 누적값이 아닌 delta로 비교하여 장시간 재생 후에도 정확한 감지
    private var _lastBufferingDecodedCount: Int32 = 0

    // C1 fix: 버퍼링 필터 시간 기반 override
    // .buffering이 delta>0으로 연속 필터링될 때 최초 필터 시각을 기록.
    // 이 시점 이후 5초 이상 지나면 필터링을 중단하고 .buffering을 강제 전파.
    private var _bufferingFilterStartTime: Date?

    // collectMetrics() player.videoSize 캐싱 (MainActor 동기 호출 최소화)
    // 해상도는 재생 시작 이후 거의 변하지 않으므로 이전 값과 비교 후 변경 시에만 갱신
    private var _cachedVideoSize: CGSize = .zero
    private var _cachedResolutionString: String? = nil

    // mediaPlayerTimeChanged 스로틀링 — 초당 10~30회 콜백을 1초 간격으로 제한
    private var _lastTimeChangeNotify: UInt64 = 0
    private let _timeChangeThrottleNs: UInt64 = 1_000_000_000  // 1초

    // Fix 12: VLC 4.0 fMP4 디먹서 폴백 버그 대응 — 초기 재생 실패 시 자동 재시도
    // VLC adaptive 모듈이 init segment 파싱 후 첫 미디어 세그먼트 CDN 연결 지연으로
    // MP4 디먹서를 TS로 잘못 전환 → fMP4 파싱 불가 → stopping 전이.
    // 3초 후 디코딩 프레임이 0이고 player가 실패 상태이면 자동 재시도.
    private var _startPlayRetryTask: Task<Void, Never>?

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

    /// [P0: 채널 전환 최적화] 미디어 URL만 교체하여 vout 재생성 없이 빠른 채널 전환.
    /// 기존 VLC 엔진/drawable을 유지하면서 미디어만 스왑하므로:
    /// - FIQCA 큐 재생성 없음 (기존 vout 유지)
    /// - 전환 시간 1~3초 → 0.3~0.5초로 단축
    /// - 프레임 드롭 최소화 (초기화 비용 제거)
    @MainActor
    public func switchMedia(to url: URL) async {
        guard !Task.isCancelled else { return }
        let profile = streamingProfile

        // 현재 재생 중이면 stop → 짧은 대기 → 새 미디어 설정
        player.stop()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms — 최소 flush
        guard !Task.isCancelled else { return }

        // drawable 유지 (vout 재생성 방지)
        // player.drawable이 이미 설정되어 있으므로 재설정 불필요

        guard let media = VLCMedia(url: url) else {
            _setPhase(.error(.streamNotFound))
            return
        }

        // 프로파일 옵션 적용 (기존 _startPlay와 동일)
        media.addOption(":network-caching=\(profile.networkCaching)")
        media.addOption(":live-caching=\(profile.liveCaching)")
        media.addOption(":file-caching=0")
        media.addOption(":disc-caching=0")
        media.addOption(":cr-average=\(profile.crAverage)")
        media.addOption(":avcodec-threads=\(profile.decoderThreads)")
        media.addOption(":avcodec-fast=1")
        media.addOption(":http-reconnect")
        let maxW = profile.adaptiveMaxWidth(isSelected: isSelectedSession)
        let maxH = profile.adaptiveMaxHeight(isSelected: isSelectedSession)
        media.addOption(":adaptive-maxwidth=\(maxW)")
        media.addOption(":adaptive-maxheight=\(maxH)")
        media.addOption(":adaptive-logic=highest")
        // [Fix 16g] adaptive 자체 HTTP로 세그먼트 다운로드
        // (adaptive-use-access 제거: 마스터/chunklist URL 무관하게 demux 프로빙 루프 유발)
        // chunklist 내 세그먼트 URL이 프록시 절대경로로 변환되어 있으므로
        // adaptive 자체 HTTP도 프록시를 경유하여 Content-Type 교정 적용
        media.addOption(":deinterlace=0")
        media.addOption(":postproc-q=0")
        media.addOption(":clock-jitter=\(profile.clockJitter)")
        // [Fix 16h-opt2] clock-synchro=0: 라이브 HLS는 시스템 클럭 동기화 비활성 필수
        // clock-synchro=1 시 454회 마스터 클럭 리셋 + 11K late pictures 발생 확인
        media.addOption(":clock-synchro=0")
        // [Fix 15] switchMedia도 Fix 13과 동일한 코덱 옵션 사용
        media.addOption(":codec=videotoolbox,avcodec")
        media.addOption(":avcodec-hw=videotoolbox")
        // [Fix 16] Content-Type 문제는 LocalStreamProxy M3U8 캐싱으로 해결
        media.addOption(":http-referrer=\(CommonHeaders.chzzkReferer)")
        media.addOption(":http-user-agent=\(CommonHeaders.safariUserAgent)")
        // [Fix 16h] http-continuous 제거: VLC가 M3U8/세그먼트 응답을 무한 스트림으로 취급 →
        // Content-Length 이후에도 데이터 대기 → prefetch가 재요청 폭풍(331K req, 410K conn fail)
        // [Fix 17b] http-forward-cookies 제거: 로컬 프록시(localhost)로 연결하므로 쿠키 전달 불필요
        if profile.dropLateFrames { media.addOption(":drop-late-frames=1") }
        if profile.skipFrames { media.addOption(":skip-frames=1") }
        // [Fix 16h-opt3] avcodec-hurry-up + prefetch: switchMedia에도 동일 적용
        media.addOption(":avcodec-hurry-up=1")
        if profile == .multiLive {
            media.addOption(":prefetch-buffer-size=786432")   // 768KB
        } else {
            media.addOption(":prefetch-buffer-size=393216")   // 384KB (256→384KB: 지터 흡수 강화)
        }
        if profile == .multiLive {
            // [Fix 18] no-audio-time-stretch 제거: scaletempo 필터가 필요하여 A/V 싱크 유지
            media.addOption(":avcodec-skip-idct=4")
        }

        player.media = media
        player.play()
    }

    @MainActor
    private func _startPlay(url: URL, profile: VLCStreamingProfile, retryAttempt: Int = 0) async {
        guard !Task.isCancelled else { return }

        // 기존 재생 중이면 안전하게 정리
        // VLCKit 4.0: player.media = nil 호출 시 VLC 내부에서
        // freed libvlc_media_t*를 retain 시도 → 크래시 발생.
        // player.stop()만 호출하고, 새 media 설정이 자동으로 교체 처리.
        if player.isPlaying || player.media != nil {
            Log.player.debug("[DIAG] _startPlay: stopping existing playback — isPlaying=\(self.player.isPlaying) hasMedia=\(self.player.media != nil)")
            player.stop()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms — VLC flush 대기
            guard !Task.isCancelled else { return }
        }

        // drawable 설정
        player.drawable = playerView

        // 뷰가 윈도우에 붙을 때까지 대기 (최대 5초, 100회 × 0.05초)
        // [Opt: Single VLC] 폴링 간격 0.1초 → 0.05초: window 감지 최대 50ms 빨라짐
        // SwiftUI가 NSViewRepresentable을 window hierarchy에 마운트할 시간 확보
        if playerView.window == nil {
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05초
                guard !Task.isCancelled else { return }
                if playerView.window != nil {
                    break
                }
            }
            if playerView.window == nil {
                // window가 nil이어도 VLC play()를 호출하여 버퍼링 시작
                // layout() 시점에 drawable이 재바인딩되므로 나중에 화면 출력 가능
                Log.player.warning("VLCPlayerEngine: 5초 대기 후에도 playerView.window == nil — play() 계속 진행")
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
        media.addOption(":cr-average=\(profile.crAverage)")
        // avcodec-threads: VideoToolbox 전용 경로에서는 내부적으로 무시되지만
        // avcodec 폴백 시 소프트웨어 스레드 수를 제한하여 CPU 스파이크 방지
        media.addOption(":avcodec-threads=\(profile.decoderThreads)")
        media.addOption(":avcodec-fast=1")
        // HTTP 재연결: 네트워크 일시 끊김 시 VLC 내부에서 자동 재연결
        media.addOption(":http-reconnect")
        // adaptive 모듈: HLS 라이브 스트림 해상도 캡 (매니페스트 파싱 비용 최소화)
        // 멀티라이브 그리드 셀(511×290, Retina 2x→1022×580)에는 720p(1280×720)로 충분
        // 선택된(포그라운드) 세션만 1080p, 비선택 세션은 720p로 GPU 디코딩 부하 50% 감소
        let maxW = profile.adaptiveMaxWidth(isSelected: isSelectedSession)
        let maxH = profile.adaptiveMaxHeight(isSelected: isSelectedSession)
        media.addOption(":adaptive-maxwidth=\(maxW)")
        media.addOption(":adaptive-maxheight=\(maxH)")
        // adaptive-logic=highest: 앱 레벨에서 이미 chunklist URL로 품질 고정.
        // VLCKit 4.0에서 'none'은 유효하지 않은 값으로 HLS demux 초기화 실패를 유발함.
        media.addOption(":adaptive-logic=highest")
        // [Fix 16g] adaptive 자체 HTTP로 세그먼트 다운로드
        // (adaptive-use-access 제거: demux 프로빙 루프 유발 확인)
        // chunklist 내 세그먼트 URL이 프록시 절대경로이므로 자체 HTTP도 프록시 경유
        // GPU 부하 최적화: 불필요한 후처리 비활성화
        media.addOption(":deinterlace=0")
        media.addOption(":postproc-q=0")
        // 저지연 HW 가속 재생 — profile별 clock-jitter 적용
        media.addOption(":clock-jitter=\(profile.clockJitter)")
        // [Fix 16h-opt2] clock-synchro=0: 라이브 HLS는 PCR 기반 클럭만 사용
        // 시스템 클럭 강제 동기화(=1)는 PTS 불일치로 클럭 리셋 폭풍 유발
        media.addOption(":clock-synchro=0")
        // [Fix 13] videotoolbox + avcodec
        media.addOption(":codec=videotoolbox,avcodec")
        media.addOption(":avcodec-hw=videotoolbox")
        // [Fix 16] Content-Type 문제는 LocalStreamProxy에서 해결
        media.addOption(":http-referrer=\(CommonHeaders.chzzkReferer)")
        media.addOption(":http-user-agent=\(CommonHeaders.safariUserAgent)")
        // [Fix 16h] http-continuous 제거: VLC HTTP 모듈이 Content-Length 존중하도록
        // M3U8는 유한 응답이므로 continuous 모드 불필요, 세그먼트도 Content-Length로 완결
        // [Fix 17b] http-forward-cookies 제거: 로컬 프록시(localhost)로 연결하므로 쿠키 전달 불필요
        if profile.dropLateFrames {
            // 저지연/멀티라이브: 늦은 프레임을 디코더 단에서 조기 드롭하여
            // GPU VideoToolbox 세션 유휴 대기 시간 최소화
            media.addOption(":drop-late-frames=1")
        }
        if profile.skipFrames {
            // [외부 리서치] skip-frames: 디코더가 참조 프레임이 아닌 B/P 프레임을
            // 건너뛰어 디코딩 파이프라인 지연 감소 (drop-late-frames와 함께 사용)
            media.addOption(":skip-frames=1")
        }
        // [Fix 16h-opt3] avcodec-hurry-up: 모든 프로파일에서 활성화
        // 늦은 프레임을 빠르게 처리하여 디코딩 큐 적체 방지 → 리버퍼링 감소
        media.addOption(":avcodec-hurry-up=1")
        // [Fix 16h-opt3] prefetch-buffer-size: 모든 프로파일에서 활성화
        // 네트워크 지터 흡수용 프리페치 — 세그먼트 다운로드 지연 시 버퍼링 방지
        if profile == .multiLive {
            media.addOption(":prefetch-buffer-size=786432")   // 768KB
        } else {
            media.addOption(":prefetch-buffer-size=393216")   // 384KB (256→384KB: 지터 흡수 강화)
        }
        if profile == .multiLive {
            // [Fix 18] no-audio-time-stretch 제거: VLC scaletempo 필터로 A/V 싱크 유지
            // 비참조 프레임 IDCT 스킵 — 디코딩 파이프라인 부하 감소
            media.addOption(":avcodec-skip-idct=4")  // nonref(4)
        }

        player.media = media
        player.play()
        Log.player.debug("[DIAG] player.play() called — state=\(self.player.state.rawValue) media=\(url.lastPathComponent, privacy: .public) retry=\(retryAttempt)")
        startStatsTimer()
        Log.player.debug("[DIAG] _startPlay: profile=\(String(describing: profile)) isSelected=\(self.isSelectedSession) window=\(self.playerView.window != nil ? "attached" : "NIL") playerState=\(self.player.state.rawValue) url=\(url.lastPathComponent, privacy: .public)")
        
        // [Fix 14] VLC 4.0 초기 재생 모니터링 — 버퍼링 보호 + 최소 재시도
        //
        // Fix 12/13 교훈:
        //  - 버퍼링 중(state=3, videoSize>0) 재시작 → VLC 버퍼 진행 파괴 → 영원히 미시작
        //  - 동일 player로 반복 재시도 → fMP4→TS 폴백 반복 → transport_error 폭주
        //  - 3회 재시도 × 12초 = 36초간 VLC 내부 상태 계속 악화
        //
        // Fix 14 전략:
        //  - 버퍼링(state=3/2) + videoSize>0 → 재시작 금지, 최대 30초 추가 대기
        //  - stopped/stopping/error → 1회만 재시도 (stop 완료 1.5초 대기 후)
        //  - playing + videoSize=0 (15초+) → 1회만 재시도
        //  - 모든 재시도 소진 후 → _setPhase(.error) → 상위 레이어가 재연결
        _startPlayRetryTask?.cancel()
        if retryAttempt < 1 {
            let capturedUrl = url
            let capturedProfile = profile
            let attempt = retryAttempt
            let pid = String(url.lastPathComponent.prefix(8))
            _startPlayRetryTask = Task { @MainActor [weak self] in
                // Phase 1: 5초 안정화 대기 — VLC가 opening→buffering→playing 전이 완료
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                
                let initState = self.player.state
                let initSize = self.player.videoSize
                let initDecoded = self.player.media?.statistics.decodedVideo ?? 0
                Log.player.debug("[FIX14] [\(pid, privacy: .public)] initial: state=\(initState.rawValue)(0=stop,1=stopping,2=open,3=buf,4=err,5=play,6=pause) vSz=\(Int(initSize.width))x\(Int(initSize.height)) decoded=\(initDecoded)")
                
                // 즉시 성공
                if initState == .playing && initSize.width > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 5초 내 재생 확인")
                    return
                }
                
                // [Fix 17b] buffering이지만 이미 디코딩 중 → 정상
                if initState == .buffering && initSize.width > 0 && initDecoded > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 5초 내 buffering이지만 디코딩 활성 (decoded=\(initDecoded)) — 정상")
                    return
                }
                
                // 명확한 실패: stopped/stopping/error → 1회 재시도
                if initState == .stopped || initState == .stopping || initState == .error {
                    Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 즉시 실패 (state=\(initState.rawValue)) — retry")
                    // stop() 완료까지 최대 1.5초 대기
                    self.player.stop()
                    for _ in 0..<15 {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }
                        if self.player.state == .stopped { break }
                    }
                    await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                    return
                }
                
                // Phase 2: 버퍼링/opening/playing(noVideo) → 장기 폴링 (최대 30초 추가)
                // VLC가 videoSize를 파악했다면 스트림은 유효 — 재시작하면 진행 파괴됨
                // [Fix 17b] 디코딩 프레임 기반 성공 판정: VLC가 buffering 상태이더라도
                // 실제로 프레임을 디코딩하고 있으면 스트림은 정상 작동 중
                Log.player.info("[FIX14] [\(pid, privacy: .public)] 장기 대기 시작 (최대 30초)")
                var lastPolledDecoded: Int32 = self.player.media?.statistics.decodedVideo ?? 0
                for pollIdx in 0..<10 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    
                    let state = self.player.state
                    let size = self.player.videoSize
                    let decoded = self.player.media?.statistics.decodedVideo ?? 0
                    let decodedDelta = decoded - lastPolledDecoded
                    lastPolledDecoded = decoded
                    Log.player.debug("[FIX14] [\(pid, privacy: .public)] poll=\(pollIdx)/10: state=\(state.rawValue) vSz=\(Int(size.width))x\(Int(size.height)) decoded=\(decoded) Δ=\(decodedDelta)")
                    
                    // 성공: playing + videoSize 확인
                    if state == .playing && size.width > 0 {
                        Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 폴링 중 재생 확인")
                        return
                    }
                    
                    // [Fix 17b] 성공: buffering이지만 프레임이 실제 디코딩 중
                    // VLC가 4스트림 동시 버퍼링 시 buffering 상태를 벗어나지 못하지만
                    // 실제로 프레임을 디코딩/표시하고 있으면 정상 재생으로 판단
                    if state == .buffering && size.width > 0 && decodedDelta > 0 {
                        Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ buffering이지만 프레임 디코딩 중 (Δ=\(decodedDelta)) — 정상")
                        return
                    }
                    
                    // 버퍼링→실패 전환 감지: stopped/stopping/error
                    if state == .stopped || state == .stopping || state == .error {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 폴링 중 실패 (state=\(state.rawValue)) — retry")
                        self.player.stop()
                        for _ in 0..<15 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            guard !Task.isCancelled else { return }
                            if self.player.state == .stopped { break }
                        }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                    
                    // playing + videoSize=0: 15초(pollIdx>=3) 이상이면 비디오 디코더 실패
                    if state == .playing && size.width == 0 && pollIdx >= 3 {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ playing+noVideo 15s+ — retry")
                        self.player.stop()
                        for _ in 0..<15 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            guard !Task.isCancelled else { return }
                            if self.player.state == .stopped { break }
                        }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                    
                    // paused 10초+(pollIdx>=3) → 비정상
                    if state == .paused && pollIdx >= 3 {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ paused 15s+ — retry")
                        self.player.stop()
                        for _ in 0..<15 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            guard !Task.isCancelled else { return }
                            if self.player.state == .stopped { break }
                        }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                    
                    // buffering/opening → 계속 대기 (VLC 버퍼링 보호)
                }
                
                // 35초(5+30) 경과 — 최종 확인
                guard !Task.isCancelled else { return }
                let finalState = self.player.state
                let finalSize = self.player.videoSize
                let finalDecoded = self.player.media?.statistics.decodedVideo ?? 0
                if finalState == .playing && finalSize.width > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 35초 후 재생 확인")
                    return
                }
                // [Fix 17b] buffering이지만 디코딩 중이면 성공
                if finalState == .buffering && finalSize.width > 0 && finalDecoded > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 35초 후 buffering이지만 디코딩 활성 (decoded=\(finalDecoded)) — 정상")
                    return
                }
                // 완전 실패 — 에러 시그널로 상위 레이어(StreamCoordinator watchdog)에 위임
                Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 35초 타임아웃 — 에러 전환 (state=\(finalState.rawValue) decoded=\(finalDecoded))")
                self._setPhase(.error(.networkTimeout))
            }
        }

        // [VLC vout 안정화]
        // 초기 재생 시 VLC가 자체적으로 vout(samplebufferdisplay)을 생성하도록 대기한다.
        // 이전의 progressive recovery(500ms/2s refreshDrawable + 4s forceVoutRecovery)는
        // 오히려 vout 초기화를 방해하여 decoded>0 + displayed=0 상태를 유발하거나,
        // forceVoutRecovery의 트랙 deselect가 VLC를 paused 상태로 만들어 재생 실패를 초래.
        // 그리드 레이아웃 변경(세션 추가/제거) 시에만 attachVideoView/MultiLiveManager에서
        // forceVoutRecovery를 호출하여 필요한 경우에만 vout을 재생성한다.
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

    // MARK: - drawable 재바인딩



    /// VLC drawable을 nil → playerView 순서로 강제 리셋하여 vout 재생성을 트리거한다.
    /// MainActor(메인 스레드)에서 호출 시 **동기** 실행되므로
    /// 이후 setVideoTrackEnabled(true) 호출 전에 drawable이 확실히 설정된다.
    /// 비메인 스레드에서 호출 시 DispatchQueue.main.async로 실행.
    public func refreshDrawable() {
        if Thread.isMainThread {
            player.drawable = nil
            player.drawable = playerView
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.player.drawable = nil
                self.player.drawable = playerView
            }
        }
    }

    /// VLC vout 파이프라인 강제 재생성.
    /// refreshDrawable()만으로 부족할 때 — 비디오 트랙을 순환(deselect → select)하여
    /// samplebufferdisplay 모듈을 완전히 파괴 후 재생성한다.
    /// 멀티라이브 그리드 레이아웃 변경 시 필수.
    public func forceVoutRecovery() {
        let doRecovery = { [weak self] in
            guard let self else { return }
            guard self.playerView.window != nil else { return }
            let state = self.player.state
            guard state != .stopped && state != .stopping else { return }
            let wasPlaying = state == .playing || state == .buffering || state == .opening

            // 1단계: drawable 재바인딩
            self.player.drawable = nil
            self.player.drawable = self.playerView

            // 2단계: 비디오 트랙 순환으로 vout 완전 재생성
            guard !self.player.videoTracks.isEmpty else { return }
            self.player.deselectAllVideoTracks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.player.videoTracks.isEmpty else { return }
                let state = self.player.state
                guard state != .stopped && state != .stopping else { return }
                self.player.selectTrack(at: 0, type: .video)
                // VLC가 트랙 deselect 시 paused 상태로 전환될 수 있으므로
                // 이전에 재생 중이었으면 명시적으로 resume
                if wasPlaying && (state == .paused || !self.player.isPlaying) {
                    self.player.play()
                }
            }
        }
        if Thread.isMainThread {
            doRecovery()
        } else {
            DispatchQueue.main.async { doRecovery() }
        }
    }

    // MARK: - 재사용 지원

    /// 에러 상태 여부 (PlayerEngineProtocol)
    public var isInErrorState: Bool {
        if case .error = _state.withLock({ $0.currentPhase }) { return true }
        return false
    }

    public func resetRetries() {}

    /// 풀 반납 전 엔진 초기화
    public func resetForReuse() {
        playTask?.cancel()
        _startPlayRetryTask?.cancel()
        _startPlayRetryTask = nil
        statsTask?.cancel()
        statsTask = nil
        // VLCKit 4.0 크래시 방지: player.media = nil 호출 금지.
        // VLC 내부 on_current_media_changed 콜백에서 freed libvlc_media_t*를
        // libvlc_media_retain()으로 접근 → Assertion failed 크래시.
        // stop()만 호출하고 media 정리는 VLCMediaPlayer dealloc에 위임.
        let p = player
        let pv = playerView
        let doStop = { [weak self] in
            self?._prevStats = nil
            self?._lastBufferingDecodedCount = 0
            self?._bufferingFilterStartTime = nil
            self?._zeroFrameCount = 0
            p.delegate = nil  // 콜백 차단
            p.stop()
            // [P1: FIQCA 큐 정리] drawable을 nil로 설정하여 VLC samplebufferdisplay vout이
            // 연결된 FIQCA 큐와 Metal 렌더링 서피스를 해제하도록 유도.
            // 이전 코드는 drawable = nil만 했으나, VLC가 내부적으로 vout을 정리할 시간이 필요.
            p.drawable = nil
            // playerView의 sublayer도 정리하여 이전 vout의 CALayer 잔여 방지
            pv.layer?.sublayers?.forEach { sub in
                if sub !== pv.layer { sub.removeFromSuperlayer() }
            }
            self?._setPhase(.idle)
            // delegate 즉시 복원 — 이전 0.3s asyncAfter 갭에서 VLC 상태 이벤트 유실 + 풀 race condition 수정
            p.delegate = self
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
        onPlaybackStalled = nil
        streamingProfile = .multiLive
        isSelectedSession = true  // 재사용 시 기본값 복원
    }

    /// 비디오 트랙 활성화/비활성화
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

    /// 백그라운드 모드 시 통계 수집 주기 조절 + 오디오 디코딩 비활성화
    public func setTimeUpdateMode(background: Bool) {
        if background {
            statsTask?.cancel()
            statsTask = nil
            // 비선택(배경) 세션: 오디오 트랙 비활성화 — 오디오 디코더 CPU 절약
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.deselectAllAudioTracks()
            }
        } else {
            startStatsTimer()
            // [Fix 18] 포그라운드 복귀: 오디오 트랙 재활성화 + A/V 동기화 리셋
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.player.audioTracks.isEmpty {
                    self.player.selectTrack(at: 0, type: .audio)
                    // 오디오 딜레이를 0으로 리셋하여 A/V 싱크 정렬
                    self.player.currentAudioPlaybackDelay = 0
                }
            }
        }
    }

    // MARK: - 녹화

    public var isRecording: Bool { _state.withLock { $0.isRecording } }

    public func startRecording(to url: URL) async throws {
        guard !_state.withLock({ $0.isRecording }) else { return }
        player.startRecording(atPath: url.path)
        _state.withLock { $0.isRecording = true }
    }

    public func stopRecording() async {
        guard _state.withLock({ $0.isRecording }) else { return }
        player.stopRecording()
        _state.withLock { $0.isRecording = false }
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

    @MainActor
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
        _state.withLock { $0.currentPhase = phase }
        onStateChange?(phase)
    }

    private func startStatsTimer() {
        statsTask?.cancel()
        // 멀티라이브: 4초 주기 (4세션 × MainActor 접근 최소화)
        // 싱글/저지연: 2초 주기 (실시간 메트릭 중요)
        let interval: UInt64 = streamingProfile == .multiLive ? 4_000_000_000 : 2_000_000_000
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
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

        // 초회 수집 시 prev == nil → 누적값이 delta가 되는 문제 방지
        // 첫 호출은 baseline만 저장하고 delta 계산 스킵
        guard let prev else { return }

        let droppedDelta = Int(stats.lostPictures) - Int(prev.lostPictures)
        let decodedDelta = Int(stats.decodedVideo) - Int(prev.decodedVideo)
        let audioLostDelta = Int(stats.lostAudioBuffers) - Int(prev.lostAudioBuffers)
        let lateDelta = Int(stats.latePictures) - Int(prev.latePictures)
        let demuxCorruptDelta = Int(stats.demuxCorrupted) - Int(prev.demuxCorrupted)
        let demuxDiscDelta = Int(stats.demuxDiscontinuity) - Int(prev.demuxDiscontinuity)

        let rawInputKbps = Double(stats.inputBitrate) * 8.0
        let inputKbps = rawInputKbps.isFinite && rawInputKbps >= 0 ? rawInputKbps : 0.0
        let rawDemuxKbps = Double(stats.demuxBitrate) * 8.0
        let demuxKbps = rawDemuxKbps.isFinite && rawDemuxKbps >= 0 ? rawDemuxKbps : 0.0
        // Float 곱셈이 Infinity로 오버플로우될 수 있으므로 Double로 변환 후 범위 검증
        let rawNetBytes = Double(stats.inputBitrate) * 1024.0
        let netBytesPerSec = rawNetBytes.isFinite && rawNetBytes >= 0 && rawNetBytes < 1e15 ? Int(rawNetBytes) : 0
        let fps = elapsed > 0 ? Double(max(0, decodedDelta)) / elapsed : 0.0

        let size = player.videoSize
        // 해상도 캐싱: 값이 변경된 경우에만 문자열 재생성 (매 2초 불필요한 String 할당 방지)
        if size != _cachedVideoSize {
            _cachedVideoSize = size
            let w = size.width, h = size.height
            _cachedResolutionString = w > 0 && w.isFinite && h.isFinite ? "\(Int(w))x\(Int(h))" : nil
        }
        let resolution = _cachedResolutionString

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

        // 재생 정체 감지: playing 상태에서 디코딩 프레임이 0이면 카운터 증가
        // buffering 상태에서는 리셋하여 실제 재생 중단만 카운팅
        let currentPhase = _state.withLock { $0.currentPhase }
        if case .playing = currentPhase {
            if decodedDelta <= 0 {
                _zeroFrameCount += 1
                if _zeroFrameCount >= _zeroFrameStallThreshold {
                    _zeroFrameCount = 0
                    onPlaybackStalled?()
                }
            } else {
                _zeroFrameCount = 0
            }
        } else {
            // idle/buffering/paused/error 상태에서는 카운터 리셋
            _zeroFrameCount = 0
        }
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
        Log.player.debug("[DIAG] VLC stateChanged: \(newState.rawValue) (0=stopped,1=stopping,2=opening,3=buffering,4=error,5=playing,6=paused)")
        let phase: PlayerState.Phase
        switch newState {
        case .opening:
            phase = .loading
        case .buffering:
            // 프레임 기반 필터링: 이미 재생 중이었고 프레임이 디코딩되고 있으면
            // .buffering 상태를 상위에 전파하지 않는다 (VLC 내부 버퍼 리필일 뿐)
            // [수정] 누적값이 아닌 delta 비교 — 장시간 재생 후에도 정확 감지
            // [C1 fix] 시간 기반 override: delta>0 필터가 5초 이상 지속되면
            // 실제 버퍼링으로 간주하고 강제 전파 (CDN 403 시 VLC가 간헐적으로
            // 1-2프레임 디코딩하면서 무한 필터링 되는 것을 방지)
            if case .playing = _state.withLock({ $0.currentPhase }) {
                let decoded = player.media?.statistics.decodedVideo ?? 0
                let delta = decoded - _lastBufferingDecodedCount
                _lastBufferingDecodedCount = decoded
                if delta > 0 {
                    // 이전 체크 이후 새 프레임이 디코딩됨
                    let now = Date()
                    if let filterStart = _bufferingFilterStartTime {
                        if now.timeIntervalSince(filterStart) >= 3.0 {
                            // [Fix 16h-opt3] 5→3초: 실제 버퍼링 감지 2초 빨라짐
                            _bufferingFilterStartTime = nil
                        } else {
                            return  // 아직 5초 미만, 필터 유지
                        }
                    } else {
                        _bufferingFilterStartTime = now
                        return  // 최초 필터링, 타이머 시작
                    }
                } else {
                    // delta == 0: 프레임 디코딩 없음 → 필터 타이머 리셋 (진짜 버퍼링)
                    _bufferingFilterStartTime = nil
                }
            }
            phase = .buffering(progress: 0)
        case .playing:
            _bufferingFilterStartTime = nil  // C1: .playing 전이 시 필터 타이머 리셋
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
    /// [스로틀링] VLC는 초당 10~30회 호출 → 멀티라이브 4세션 = 초당 40~120회
    /// 1초 미만 간격의 콜백은 무시하여 CPU 부하 대폭 감소
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - _lastTimeChangeNotify >= _timeChangeThrottleNs else { return }
        _lastTimeChangeNotify = now
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
