// MARK: - VLCPlayerEngine.swift
// CViewPlayer — VLC 플레이어 엔진 (고도화)
//
// [핵심 원칙]
// • drawable은 play() 전에 반드시 설정 (VLCVideoView.makeNSView에서 동기 바인딩)
// • HLS-CMAF(fMP4) 스트림에 wallclock timestamp 옵션 사용 금지
//   → ISO BMFF PTS/DTS 교체 시 A/V 동기화 실패 → 버퍼링 무한루프
// • setVolume: 0.0~1.0 → VLC 0~100 (100=정상; 구버그: *200 → 200% 과증폭)

import Foundation
import CViewCore
@preconcurrency import VLCKitSPM

// MARK: - Streaming Profile

/// VLC 스트리밍 설정 프로파일
public enum VLCStreamingProfile: Sendable {
    /// 일반 재생 — 높은 안정성, 넉넉한 버퍼
    case normal
    /// 저지연 라이브 — 최소 버퍼, 빠른 동기화
    case lowLatency
    /// 멀티라이브 탭 (백그라운드) — 낮은 CPU/GPU 우선순위
    case multiLiveBackground

    var networkCaching: Int {
        switch self {
        case .normal:             return 1500
        case .lowLatency:         return 400
        case .multiLiveBackground: return 800
        }
    }
    var liveCaching: Int {
        switch self {
        case .normal:             return 1000
        case .lowLatency:         return 200
        case .multiLiveBackground: return 500
        }
    }
}

// MARK: - VLC Player Engine

/// Thread-safe VLC player engine conforming to PlayerEngineProtocol.
/// Uses @preconcurrency import for VLCKit interop.
public final class VLCPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {
    
    // MARK: - Properties

    /// 이 엔진 전용 VLCVideoView.
    /// VLCMediaPlayer는 init 시 이 뷰에 바인딩되며, play() 직전 MainActor에서 재확인함.
    /// SwiftUI NSViewRepresentable은 이 뷰를 container에 서브뷰로 삽입한다.
    public let playerView: VLCKitSPM.VLCVideoView

    /// PlayerEngineProtocol conformance — NSView 통합용
    public var videoView: NSView { playerView }

    private let player: VLCMediaPlayer
    private let logger = AppLogger.player
    
    // State (protected by lock for thread safety from VLC callbacks)
    private let lock = NSLock()
    private var _state: PlayerState.Phase = .idle
    private var _rate: Float = 1.0
    private var _currentURL: URL?
    private var _volume: Int = 100

    // ── 자동 재시도 (네트워크 순단 등 일시적 VLC ERROR 복구) ─────────────
    private var remainingRetries: Int = 3
    private let maxRetries:       Int = 3

    // ── 스톨 감지 워치독 ────────────────────────────────────────────────────
    // PLAYING 상태에서 재생 위치가 일정 시간 이상 변하지 않으면 강제 재시작
    // CDN 세그먼트 무응답(HTTP 403/404) 시 VLC가 ERROR 없이 무음 정지하는 상황 대응
    private var lastPositionMillis: Int32 = 0
    private var lastPositionDate: Date = Date()
    private var stallWatchdogTask: Task<Void, Never>?
    private let stallThresholdSecs: TimeInterval = 45  // 45초 무변화 → 스톨 판정

    // ── VLC 메트릭 타이머 ────────────────────────────────────────────────────
    /// 2초 주기로 VLC 재생 메트릭을 수집하여 MetricsForwarder로 전달합니다.
    public var onVLCMetrics: (@Sendable (VLCLiveMetrics) -> Void)?
    private var statsTimerTask: Task<Void, Never>?
    // 누적 통계 델타 계산용 이전 값 (lock으로 보호)
    private var _prevReadBytes: Int32 = 0
    private var _prevDisplayedPictures: Int32 = 0
    private var _prevDecodedVideo: Int32 = 0
    private var _prevLostPictures: Int32 = 0
    private var _prevLostAudioBuffers: Int32 = 0
    private var _prevStatsDate: Date = Date()

    /// 현재 스트리밍 프로파일 (play 호출 전 설정)
    public var streamingProfile: VLCStreamingProfile = .lowLatency

    /// 하드웨어 디코딩 활성화 여부 (기본값: true = VideoToolbox 우선)
    public var hardwareDecodingEnabled: Bool = true

    /// State change callback (for ViewModel binding)
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?
    /// Time change callback
    public var onTimeChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?
    
    // MARK: - PlayerEngineProtocol Properties
    
    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _state == .playing
    }
    
    public var currentTime: TimeInterval {
        Double(player.time.intValue) / 1000.0
    }
    
    public var duration: TimeInterval {
        guard let media = player.media else { return 0 }
        let length = media.length.intValue
        return length > 0 ? Double(length) / 1000.0 : 0
    }
    
    public var rate: Float {
        lock.lock()
        defer { lock.unlock() }
        return _rate
    }
    
    /// 정규화 볼륨 (0.0~1.0)
    public var volume: Float {
        Float(_volume) / 100.0
    }
    
    // MARK: - VLC-specific Properties
    
    /// The underlying VLCMediaPlayer for view binding
    public var mediaPlayer: VLCMediaPlayer { player }
    
    // MARK: - Initialization

    public override init() {
        let view = VLCKitSPM.VLCVideoView()
        self.playerView = view
        // [macOS 전용] initWithVideoView: 를 사용하여 생성 시점에 vout 연결.
        // VLCMediaPlayer()로 생성 후 setVideoView()를 호출하는 것보다
        // initWithVideoView:가 내부적으로 더 완전한 vout 초기화를 수행한다.
        // 각 VLCMediaPlayer 인스턴스는 독립적인 재생 상태(미디어·위치·볼륨)를 가지므로
        // 멀티라이브 탭 간에 플레이어 레벨 격리가 보장된다.
        self.player = VLCKitSPM.VLCMediaPlayer(videoView: view)
        super.init()
        player.delegate = self

        // [DEBUG 전용] VLC 내부 상세 로그 → /tmp/vlc_internal.log
        // VLC가 OPENING 후 PLAYING으로 전환되지 않는 원인 진단용
        #if DEBUG
        VLCKitSPM.VLCLibrary.shared().debugLoggingLevel = 4   // 0=info … 4=debug
        VLCKitSPM.VLCLibrary.shared().setDebugLoggingToFile("/tmp/vlc_internal.log")
        #endif
    }
    
    deinit {
        player.stop()
    }
    
    // MARK: - PlayerEngineProtocol Methods
    
    public func play(url: URL) async throws {
        lock.withLock {
            _currentURL = url
            _state = .buffering(progress: 0)
            remainingRetries = maxRetries   // 새 play() 호출 시 재시도 카운터 리셋
        }

        let media = VLCMedia(url: url)
        configureMediaOptions(media)

        let profileDesc = String(describing: streamingProfile)
        logger.info("VLC play(): \(url.lastPathComponent, privacy: .public) profile=\(profileDesc, privacy: .public)")

        // [메인 스레드 필수] VLC macOS vout 모듈은 NSView/CALayer를 초기화하므로
        // 반드시 메인 스레드에서 실행해야 함.
        // StreamCoordinator(actor)에서 호출되면 백그라운드 스레드 → vout 초기화 실패 → 검은 화면.
        //
        // setVideoView: generic `drawable` setter 대신 macOS 전용 API 사용.
        //   - 엔진 재생성(stopStream → startStream) 시 SwiftUI updateNSView 타이밍과 무관하게 안전.
        //   - playerView는 이 엔진 전용 뷰이므로 항상 올바른 target.
        await MainActor.run { [player, media, playerView] in
            player.setVideoView(playerView)  // ✅ 매번 재확인 — stop/start 후 새 엔진도 안전
            player.media = media
            player.play()

            // 진단: playerView가 window hierarchy에 있는지 확인
            let inWindow = playerView.window != nil
            let bounds = playerView.bounds
            self.logger.info("VLC play() dispatched — playerView.inWindow=\(inWindow, privacy: .public) bounds=\(bounds.width, privacy: .public)x\(bounds.height, privacy: .public)")
        }

        // 스톨 워치독 + 메트릭 타이머 시작
        startStallWatchdog()
        startStatsTimer()

        #if DEBUG
        // 15초 후 진단: VLC 상태 + view 상태 재확인 (DEBUG 전용)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            await MainActor.run {
                let inWindow = self.playerView.window != nil
                let hasVideo = self.playerView.hasVideo
                let bounds = self.playerView.bounds
                let vlcState = self.player.state.rawValue
                let videoSize = self.player.videoSize
                let hasOut = self.player.hasVideoOut
                self.logger.info("── 15s 진단 ── state=\(vlcState, privacy: .public) hasVideoOut=\(hasOut, privacy: .public) hasVideo=\(hasVideo, privacy: .public) inWindow=\(inWindow, privacy: .public) bounds=\(bounds.width, privacy: .public)x\(bounds.height, privacy: .public) videoSize=\(videoSize.width, privacy: .public)x\(videoSize.height, privacy: .public)")
            }
        }
        #endif
    }
    
    public func pause() {
        let p = player
        if Thread.isMainThread { p.pause() }
        else { DispatchQueue.main.async { p.pause() } }
        lock.lock()
        _state = .paused
        lock.unlock()
    }
    
    public func resume() {
        let p = player
        let v = playerView
        // [안정화] pause → window 상태 변경(최소화·화면보호기 등) 후 resume 시
        // vout CALayer 컨텍스트가 무효화될 수 있으므로 setVideoView를 재호출해 재바인딩
        if Thread.isMainThread {
            p.setVideoView(v)
            p.play()
        } else {
            DispatchQueue.main.async {
                p.setVideoView(v)
                p.play()
            }
        }
        lock.lock()
        _state = .playing
        lock.unlock()
    }
    
    public func stop() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        statsTimerTask?.cancel()
        statsTimerTask = nil
        onVLCMetrics = nil   // 순환 참조 방지 및 콜백 해제
        let p = player
        if Thread.isMainThread { p.stop() }
        else { DispatchQueue.main.async { p.stop() } }
        lock.lock()
        _state = .idle
        _currentURL = nil
        lock.unlock()
    }

    /// 재시도 카운터를 초기화합니다.
    /// MultiLiveSession에서 스트림 URL을 새로 취득한 후 호출해 복구 기회를 되살립니다.
    public func resetRetries() {
        lock.withLock { remainingRetries = maxRetries }
    }
    
    public func seek(to time: TimeInterval) {
        let msTime = Int32(time * 1000)
        player.time = VLCTime(int: msTime)
    }
    
    public func setRate(_ newRate: Float) {
        player.rate = newRate
        lock.lock()
        _rate = newRate
        lock.unlock()
        logger.debug("Rate set to \(newRate)")
    }
    
    /// 볼륨 설정 (0.0~1.0)
    /// VLC 볼륨 스케일: 0-200 (100=정상 볼륨, 200=200% 과증폭)
    /// 앱 1.0 → VLC 100 (정상); 구버그: *200 → 200% 과증폭이었음
    public func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        let vlcVol = Int32(clamped * 100)   // ✅ 수정: *200 → *100
        player.audio?.volume = vlcVol
        lock.withLock { _volume = Int(clamped * 100) }
    }
    
    // MARK: - VLC-specific Methods
    
    /// Get buffer health from actual VLC media statistics
    public func bufferHealth() -> BufferHealth {
        // VLC statistics는 메인스레드 또는 lock 외부에서 안전 접근 가능
        guard let stats = player.media?.statistics else {
            return BufferHealth(currentLevel: 0, targetLevel: 1.0, isHealthy: true)
        }
        let displayed = max(Int(stats.displayedPictures), 0)
        let decoded   = max(Int(stats.decodedVideo),      1)
        let lost      = max(Int(stats.lostPictures),      0)
        let ratio     = Float(displayed) / Float(decoded)      // 0.0~1.0
        // 버퍼링 중이거나 프레임 손실 발생 시 비건강 상태로 판정
        let isBuffering = player.state == .buffering
        let isHealthy   = displayed > 0 && lost == 0 && !isBuffering
        return BufferHealth(currentLevel: Double(ratio), targetLevel: 1.0, isHealthy: isHealthy)
    }
    
    /// Set hardware decoding preference — 다음 play() 호출부터 적용
    public func setHardwareDecoding(_ enabled: Bool) {
        hardwareDecodingEnabled = enabled
        logger.info("Hardware decoding preference set: \(enabled) (applies on next play)")
    }
    
    /// Enable or disable video track (for audio-only mode)
    public func setVideoTrackEnabled(_ enabled: Bool) {
        if enabled {
            player.currentVideoTrackIndex = 0
        } else {
            player.currentVideoTrackIndex = -1
        }
        logger.info("Video track enabled: \(enabled)")
    }
    
    /// Available audio tracks
    public func audioTracks() -> [(Int, String)] {
        var tracks: [(Int, String)] = []
        let count = player.numberOfAudioTracks
        
        if count > 0 {
            if let names = player.audioTrackNames as? [String],
               let indices = player.audioTrackIndexes as? [NSNumber] {
                for (i, name) in names.enumerated() {
                    if i < indices.count {
                        tracks.append((indices[i].intValue, name))
                    }
                }
            }
        }
        
        return tracks
    }
    
    /// Set audio track by index
    public func setAudioTrack(_ index: Int) {
        player.currentAudioTrackIndex = Int32(index)
    }
    
    /// Capture current video frame as a snapshot
    /// Returns the file URL of the saved screenshot, or nil on failure
    public func captureSnapshot() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let filename = "CView_screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let filePath = dir.appendingPathComponent(filename)
        
        player.saveVideoSnapshot(at: filePath.path, withWidth: 0, andHeight: 0)
        
        // VLC saves asynchronously; return the expected path
        return filePath
    }
    
    // MARK: - Configuration
    
    private func configureDefaultOptions() {
        // 자막 트랙 초기 비활성화 (미디어 옵션의 :sub-track=-1 보완)
        player.currentVideoTrackIndex = 0
    }
    
    private func configureMediaOptions(_ media: VLCMedia) {
        // ── 네트워크 / 라이브 캐싱 (프로파일별) ──────────────────────────────
        let profile = streamingProfile
        media.addOption(":network-caching=\(profile.networkCaching)")
        media.addOption(":live-caching=\(profile.liveCaching)")
        media.addOption(":file-caching=0")
        media.addOption(":disc-caching=0")

        // ── 클럭 / 타임스탬프 동기화 ─────────────────────────────────────────
        // [IMPORTANT] HLS-CMAF(fMP4) 스트림에는 avformat-use-wallclock-as-timestamps,
        // clock-jitter=0, clock-synchro=0 을 사용하면 안 됨.
        // fMP4 세그먼트는 ISO BMFF 박스에 정확한 PTS/DTS가 내장되어 있어
        // wall-clock 타임스탬프로 교체하면 A/V 동기화가 깨져 버퍼링에서 탈출 불가.

        // ── VideoToolbox GPU 하드웨어 디코딩 ─────────────────────────────────
        // VideoToolbox → avcodec→ all 순서로 HW 우선 시도, SW fallback 유지
        if hardwareDecodingEnabled {
            media.addOption(":codec=videotoolbox,avcodec,all")
            media.addOption(":avcodec-hw=any")
            // zero-copy 비활성: CVPixelBuffer를 CPU 복사 경로로 처리하여 안정성 확보
            // (HW 디코딩은 여전히 VideoToolbox GPU에서 수행됨)
            media.addOption(":videotoolbox-zero-copy=0")
            // HW 전용 강제 모드 OFF → 하드웨어 실패 시 SW로 자동 전환 (안정성 보장)
            media.addOption(":videotoolbox-hw-decoder-only=0")
        } else {
            media.addOption(":codec=avcodec,all")
            media.addOption(":avcodec-hw=none")
        }

        // ── avcodec/ffmpeg 디코더 퍼포먼스 튜닝 ──────────────────────────────
        // CPU 스레드: 멀티라이브 백그라운드에서는 2로 제한
        // (4개 동시 VLC 인스턴스 시 스레드 경쟁 완화; Intel Mac HW 디코더 세션 한계 방지)
        // 포그라운드는 0(자동)으로 논리 코어 수 최대 활용
        let threads = (profile == .multiLiveBackground) ? 2 : 0
        media.addOption(":avcodec-threads=\(threads)")
        // 표준 비준수 속도 최적화 허용
        // (일부 마이너 화질 트레이드오프, 라이브 스트림에서는 무방)
        media.addOption(":avcodec-fast=1")
        // Non-reference 프레임의 디블로킹 루프 필터 스킵 → GPU 연산량 감소
        // (nonref: B/P 비참조 프레임 스킵; 화질 영향 미미, 지연 개선)
        media.addOption(":avcodec-skiploopfilter=nonref")
        // Non-reference IDCT 스킵 → SW 디코딩 시 부하 감소
        media.addOption(":avcodec-skip-idct=nonref")
        // 프레임 스킵 기준 — 0: 스킵 없음 (HW decode 시 충분), 비참조는 이미 위에서 제어
        media.addOption(":avcodec-skip-frame=0")

        // ── 라이브 스트림 프레임 드롭 전략 ───────────────────────────────────
        // 디코더 큐가 밀릴 때 늦은 프레임 폐기 → 버퍼 적체 방지, 재생 연속성 유지
        media.addOption(":drop-late-frames=1")
        // 버퍼 부족 / 리소스 과부하 시 비핵심 프레임 스킵
        media.addOption(":skip-frames=1")

        // ── 디인터레이스 (라이브 Progressive → 불필요, CPU 절약) ─────────────
        media.addOption(":deinterlace=-1")    // -1: 자동(Progressive 감지 시 생략)
        media.addOption(":deinterlace-mode=discard")

        // ── 오디오/비디오 출력 모듈 ───────────────────────────────────────────
        // ✅ vout은 play() 직전 player.setVideoView(playerView)로 명시 설정됨.
        //    media.addOption(":vout=macosx") 제거 — media-level 옵션은 instance-level 모듈 선택과 다름.
        //    VLC가 setVideoView로 받은 VLCVideoView 기반으로 자동으로 macosx vout을 선택함.
        // macOS Core Audio 아웃풋 (auhal)
        media.addOption(":aout=auhal")
        // 오디오 타임스트레치 비활성 — CPU 부하 유발, 라이브 스트리밍에서는 불필요
        media.addOption(":no-audio-time-stretch")
        // 오디오 시각화 비활성 (불필요 OpenGL 렌더링 제거)
        media.addOption(":audio-visual=none")

        // ── 자막 완전 비활성화 ─────────────────────────────────────────────────
        media.addOption(":sub-track=-1")
        media.addOption(":no-sub-autodetect-file")
        media.addOption(":sub-source=none")

        // ── 기타 CPU 절약 ─────────────────────────────────────────────────────
        // 재생 통계 수집 비활성 (디버그 빌드에서도 불필요한 오버헤드 제거)
        media.addOption(":no-stats")
        // SPU(서브 픽처 유닛) 렌더링 비활성
        media.addOption(":no-spu")

        // ── HTTP 헤더 (Chzzk CDN 필수) ────────────────────────────────────────
        media.addOption(":http-user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
        media.addOption(":http-referrer=https://chzzk.naver.com/")
        // [주의] :http-continuous=1 제거 — HLS 세그먼트 기반 스트림에서 demux 간섭 가능
        // (non-segmented Icecast/Shoutcast 전용 옵션이며 HLS에서는 불필요)

        logger.debug("VLC media configured: profile=\(String(describing: profile)), hw=\(self.hardwareDecodingEnabled)")
    }
    
    // MARK: - Stall Watchdog

    /// PLAYING 상태에서 재생 위치가 stallThresholdSecs 이상 변하지 않으면 VLC를 강제 재시작합니다.
    /// CDN 세그먼트 무응답(토큰 만료, 일시 장애)으로 VLC가 무음 정지하는 상황을 대응합니다.
    private func startStallWatchdog() {
        stallWatchdogTask?.cancel()
        lock.withLock {
            lastPositionMillis = 0
            lastPositionDate   = Date()
        }

        stallWatchdogTask = Task { [weak self] in
            // 첫 체크는 시작 후 60초 뒤 — 초기 버퍼링/OPENING 단계에서 오작동 방지
            try? await Task.sleep(for: .seconds(60))

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled else { break }

                let phase: PlayerState.Phase
                let lastDate: Date
                let urlToRetry: URL?
                (phase, lastDate, urlToRetry) = self.lock.withLock {
                    (self._state, self.lastPositionDate, self._currentURL)
                }

                // PLAYING 상태일 때만 검사
                guard case .playing = phase else { continue }

                let stalledFor = -lastDate.timeIntervalSinceNow
                guard stalledFor >= self.stallThresholdSecs else { continue }

                self.logger.warning("⚠️ 스톨 감지: \(Int(stalledFor))초 간 재생 위치 변화 없음 → 복구 시도")

                var retries: Int = 0
                self.lock.withLock {
                    retries = self.remainingRetries
                    if retries > 0 {
                        self.remainingRetries -= 1
                        self._state = .buffering(progress: 0)
                    }
                }

                if retries > 0, let url = urlToRetry {
                    self.onStateChange?(.buffering(progress: 0))
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.player.stop()
                        let media = VLCMedia(url: url)
                        self.configureMediaOptions(media)
                        self.player.setVideoView(self.playerView)
                        self.player.media = media
                        self.player.play()
                        self.logger.info("스톨 복구 재시작: \(url.lastPathComponent, privacy: .public)")
                    }
                    // 재시작 직후 측정값 리셋 (spurious 재발 방지)
                    self.lock.withLock {
                        self.lastPositionDate   = Date()
                        self.lastPositionMillis = 0
                    }
                } else {
                    // 재시도 소진 → 상위 레이어(MultiLiveSession)에 알려 URL 재취득 요청
                    self.logger.error("스톨 복구 재시도 소진 — MultiLiveSession에서 URL 재취득 필요")
                    let errPhase = PlayerState.Phase.error(.engineInitFailed)
                    self.lock.withLock { self._state = errPhase }
                    self.onStateChange?(errPhase)
                    break
                }
            }
        }
    }

    // MARK: - VLC Stats Timer

    /// 2초 주기로 VLC media.statistics를 읽어 VLCLiveMetrics를 생성하고 onVLCMetrics 콜백을 호출합니다.
    private func startStatsTimer() {
        statsTimerTask?.cancel()
        lock.withLock {
            _prevReadBytes = 0
            _prevDisplayedPictures = 0
            _prevDecodedVideo = 0
            _prevLostPictures = 0
            _prevLostAudioBuffers = 0
            _prevStatsDate = Date()
        }
        statsTimerTask = Task { [weak self] in
            // 초기 3초 대기 — 버퍼링 안정화 후 수집 시작
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { break }
                self.captureVLCMetrics()
            }
        }
    }

    /// VLC 통계 스냅샷을 읽어 VLCLiveMetrics를 생성하고 콜백을 호출합니다.
    /// 누적 카운터 차분으로 초당 FPS, 드롭 프레임, 네트워크 throughput을 계산합니다.
    private func captureVLCMetrics() {
        // VLC statistics는 reader 스레드에서 안전 접근 가능
        let stats    = player.media?.statistics
        let videoSize = player.videoSize
        let rate     = player.rate

        // 이전 값 읽기
        let prevSnapshot: (read: Int32, displayed: Int32, decoded: Int32, lost: Int32, audio: Int32, date: Date)
        prevSnapshot = lock.withLock {
            (_prevReadBytes, _prevDisplayedPictures, _prevDecodedVideo,
             _prevLostPictures, _prevLostAudioBuffers, _prevStatsDate)
        }

        let now     = Date()
        let elapsed = max(now.timeIntervalSince(prevSnapshot.date), 0.001)

        // 현재 누적값 (stats 없으면 이전 값 유지 → 델타 0)
        let curRead      = stats.map { Int32($0.readBytes)          } ?? prevSnapshot.read
        let curDisplayed = stats.map { Int32($0.displayedPictures)  } ?? prevSnapshot.displayed
        let curDecoded   = stats.map { Int32($0.decodedVideo)       } ?? prevSnapshot.decoded
        let curLost      = stats.map { Int32($0.lostPictures)       } ?? prevSnapshot.lost
        let curAudio     = stats.map { Int32($0.lostAudioBuffers)   } ?? prevSnapshot.audio

        // 델타 (음수 방지 — VLC 내부 리셋 시 누적값이 낮아질 수 있음)
        let deltaRead    = Int(max(0, curRead      - prevSnapshot.read))
        let deltaDecoded = Int(max(0, curDecoded   - prevSnapshot.decoded))
        let deltaLost    = Int(max(0, curLost      - prevSnapshot.lost))
        let deltaAudio   = Int(max(0, curAudio     - prevSnapshot.audio))

        // 이전 값 업데이트
        lock.withLock {
            _prevReadBytes         = curRead
            _prevDisplayedPictures = curDisplayed
            _prevDecodedVideo      = curDecoded
            _prevLostPictures      = curLost
            _prevLostAudioBuffers  = curAudio
            _prevStatsDate         = now
        }

        // FPS = 구간 디코딩 프레임 / 경과 시간
        let fps = Double(deltaDecoded) / elapsed

        // 네트워크 throughput (bytes/sec)
        let bytesPerSec = Int(Double(deltaRead) / elapsed)

        // 비트레이트: VLC inputBitrate/demuxBitrate 단위는 KB/s → kbps = * 8
        let inputKbps = Double(stats?.inputBitrate ?? 0) * 8.0
        let demuxKbps = Double(stats?.demuxBitrate ?? 0) * 8.0

        // 해상도 문자열
        let width  = Double(videoSize.width)
        let height = Double(videoSize.height)
        let resStr: String? = (width > 0 && height > 0) ? "\(Int(width))x\(Int(height))" : nil

        // 버퍼 건강도
        let buf = bufferHealth()

        let metrics = VLCLiveMetrics(
            fps:                   fps,
            droppedFramesDelta:    deltaLost,
            decodedFramesDelta:    deltaDecoded,
            networkBytesPerSec:    bytesPerSec,
            inputBitrateKbps:      inputKbps,
            demuxBitrateKbps:      demuxKbps,
            resolution:            resStr,
            videoWidth:            width,
            videoHeight:           height,
            playbackRate:          rate,
            bufferHealth:          buf.currentLevel,
            lostAudioBuffersDelta: deltaAudio,
            timestamp:             now
        )

        onVLCMetrics?(metrics)
    }

    /// 저지연 설정 전환 - 다음 play() 호출부터 적용
    public func applyLowLatencyConfig() {
        streamingProfile = .lowLatency
        // 현재 재생 중인 경우 즉시 반영 (캐싱값 실시간 적용 시도)
        if let media = player.media {
            media.addOption(":network-caching=\(VLCStreamingProfile.lowLatency.networkCaching)")
            media.addOption(":live-caching=\(VLCStreamingProfile.lowLatency.liveCaching)")
        }
        logger.info("Applied low-latency VLC profile (network=\(VLCStreamingProfile.lowLatency.networkCaching)ms)")
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlayerEngine: VLCMediaPlayerDelegate {

    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        let vlcState = player.state

        let phase: PlayerState.Phase
        switch vlcState {
        case .playing:
            phase = .playing
            logger.info("VLC → PLAYING ✅ videoSize=\(self.player.videoSize.width, privacy: .public)x\(self.player.videoSize.height, privacy: .public) hasVideoOut=\(self.player.hasVideoOut, privacy: .public) viewHasVideo=\(self.playerView.hasVideo, privacy: .public)")

        case .paused:
            phase = .paused
            logger.info("VLC → PAUSED")

        case .buffering:
            // playing 중 버퍼링 이벤트는 상태 역전 방지를 위해 무시
            lock.lock()
            let current = _state
            lock.unlock()
            if case .playing = current { return }
            phase = .buffering(progress: 0)
            if case .buffering = current { } else {
                logger.info("VLC → BUFFERING")
            }

        case .ended:
            phase = .ended
            logger.warning("VLC → ENDED")

        case .error:
            // ── 자동 재시도 로직 ─────────────────────────────────────────────
            // 네트워크 순단, CDN 일시 오류 등 복구 가능한 에러에 대응
            let retries: Int
            let urlToRetry: URL?
            lock.lock()
            retries    = remainingRetries
            urlToRetry = _currentURL
            if retries > 0 {
                remainingRetries -= 1
                _state = .buffering(progress: 0)
            }
            lock.unlock()

            if retries > 0 {
                let attempt = self.maxRetries - retries + 1
                logger.warning("VLC → ERROR ❌ — 자동 재시도 \(attempt)/\(self.maxRetries) (2초 후)")
                onStateChange?(.buffering(progress: 0))
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, let url = urlToRetry else { return }
                    let media = VLCMedia(url: url)
                    self.configureMediaOptions(media)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.player.setVideoView(self.playerView)
                        self.player.media = media
                        self.player.play()
                        self.logger.info("VLC 재시도 play(): \(url.lastPathComponent, privacy: .public)")
                    }
                }
                return
            }
            phase = .error(.engineInitFailed)
            logger.error("VLC → ERROR ❌ (재시도 \(self.maxRetries)회 소진)")

        case .stopped:
            phase = .idle
            logger.info("VLC → STOPPED")

        case .opening:
            phase = .buffering(progress: 0)
            logger.info("VLC → OPENING")

        case .esAdded:
            // ES_ADDED = 트랙 감지. PLAYING 전 발생. 내부 상태 미변경.
            logger.info("VLC → ES_ADDED (tracks detected — PLAYING approaching)")
            return

        @unknown default:
            phase = .idle
            logger.warning("VLC → UNKNOWN(\(vlcState.rawValue, privacy: .public))")
        }

        lock.withLock { _state = phase }
        onStateChange?(phase)
    }

    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // 재생 위치 갱신 추적 — 스톨 워치독에서 사용
        let ms = player.time.intValue
        lock.lock()
        if ms != lastPositionMillis {
            lastPositionMillis = ms
            lastPositionDate   = Date()
        }
        lock.unlock()
        onTimeChange?(currentTime, duration)
    }
}

// MARK: - VLC Length Change (non-protocol)

extension VLCPlayerEngine {
    // @nonobjc 제거 → ObjC 런타임에서 VLC가 직접 호출 가능 → duration 0 표시 버그 수정
    public func mediaPlayerLengthChanged(_ aNotification: Notification) {
        onTimeChange?(currentTime, duration)
    }
}

// MARK: - VLC error state helper

extension PlayerState.Phase {
    fileprivate static let error = PlayerState.Phase.error(.engineInitFailed)
}
