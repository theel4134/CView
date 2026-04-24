// MARK: - LowLatencyController.swift
// CViewPlayer - Low-Latency HLS (LL-HLS) Controller
// 원본: CatchUpController + syncTimerFired 로직 → 개선: PID + EWMA 통합 actor

import Foundation
import CViewCore

// MARK: - Low Latency Controller

/// Controls low-latency HLS playback using PID controller for catch-up/slow-down.
/// Integrates EWMA for stable latency estimation and PID for smooth rate adjustment.
public actor LowLatencyController {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let targetLatency: TimeInterval
        public let maxLatency: TimeInterval
        public let minLatency: TimeInterval
        public let maxPlaybackRate: Double
        public let minPlaybackRate: Double
        public let catchUpThreshold: TimeInterval
        public let slowDownThreshold: TimeInterval
        public let pidKp: Double
        public let pidKi: Double
        public let pidKd: Double
        
        public static let `default` = Configuration(
            targetLatency: 3.0,
            maxLatency: 8.0,
            minLatency: 1.0,
            maxPlaybackRate: 1.15,
            minPlaybackRate: 0.90,
            catchUpThreshold: 1.2,
            slowDownThreshold: 0.5,
            pidKp: 0.8,
            pidKi: 0.12,
            pidKd: 0.06
        )
        
        public static let ultraLow = Configuration(
            targetLatency: 1.5,
            maxLatency: 5.0,
            minLatency: 0.5,
            maxPlaybackRate: 1.20,
            minPlaybackRate: 0.85,
            catchUpThreshold: 1.0,
            slowDownThreshold: 0.3,
            pidKp: 1.0,
            pidKi: 0.15,
            pidKd: 0.08
        )
        
        /// 웹(hls.js) 동기화 프리셋 — 앱↔웹 동일 재생 위치 목표 (완화형)
        /// hls.js 기본값: liveSyncDurationCount=3 × TARGETDURATION(2s) = 6.0s 지연
        /// 앱은 VLC 내부 버퍼(~1s) + CDN→프록시 파이프라인을 고려하여 6.0s 타겟
        /// PID 게인을 보수적으로 설정: 부드러운 수렴 (버퍼링 최소화 우선)
        /// catchUpThreshold=1.0: ±1.0초 초과 시 속도 조정 시작 (여유 확보)
        /// slowDownThreshold=0.8: ±0.8초 이내면 동기화 완료로 판단 (넓은 데드존)
        public static let webSync = Configuration(
            targetLatency: 6.0,
            maxLatency: 12.0,
            minLatency: 3.0,
            maxPlaybackRate: 1.08,
            minPlaybackRate: 0.93,
            catchUpThreshold: 1.0,
            slowDownThreshold: 0.8,
            pidKp: 0.5,
            pidKi: 0.05,
            pidKd: 0.03
        )
        
        public init(
            targetLatency: TimeInterval = 3.0,
            maxLatency: TimeInterval = 10.0,
            minLatency: TimeInterval = 1.0,
            maxPlaybackRate: Double = 1.15,
            minPlaybackRate: Double = 0.9,
            catchUpThreshold: TimeInterval = 1.5,
            slowDownThreshold: TimeInterval = 0.5,
            pidKp: Double = 0.8,
            pidKi: Double = 0.1,
            pidKd: Double = 0.05
        ) {
            self.targetLatency = targetLatency
            self.maxLatency = maxLatency
            self.minLatency = minLatency
            self.maxPlaybackRate = maxPlaybackRate
            self.minPlaybackRate = minPlaybackRate
            self.catchUpThreshold = catchUpThreshold
            self.slowDownThreshold = slowDownThreshold
            self.pidKp = pidKp
            self.pidKi = pidKi
            self.pidKd = pidKd
        }
    }
    
    // MARK: - State
    
    public enum SyncState: Sendable, Equatable {
        case idle
        case synced
        case catchingUp
        case slowingDown
        case seekRequired
    }
    
    public struct LatencySnapshot: Sendable {
        public let currentLatency: TimeInterval
        public let targetLatency: TimeInterval
        public let ewmaLatency: TimeInterval
        public let playbackRate: Double
        public let syncState: SyncState
        public let pidOutput: Double
        public let timestamp: Date
    }

    // MARK: - Web Sync Phase (P1 / 2026-04-25)

    /// 웹↔앱 정밀 동기화 권장 상태(docs §5 원안). 기존 `SyncState` 는
    /// rate 방향(catch/slow) 관점에서 유지하고, `WebSyncPhase` 는
    /// PDT drift 매개 제어 주기·정책(hysteresis) 의 관점으로 별도 운용.
    ///
    /// 전이:
    /// - `idle` → `acquiring` (첫 샘플 수신)
    /// - `acquiring` (|drift| ≤ 500ms 일정 회수) → `tracking`
    /// - `tracking` (|drift| > 1500ms) → `acquiring`
    /// - `tracking|acquiring` (|drift| > 2500ms) → `snap` → seek → `reacquire`
    /// - 샘플 stale → `hold` (rate=1.0, seek 금지)
    public enum WebSyncPhase: Sendable, Equatable {
        case idle
        case acquiring
        case snap
        case tracking
        case hold(reason: String)
        case reacquire(reason: String)
    }

    /// PDT 정밀 샘플 — 서버 출력(웹 vs 앱 driftMs)을 설명하는 값타입.
    /// `WebLatencyClient` 가 수집한 `PDTComparisonSnapshot` 을 제어 루프에
    /// 주입하기 위한 축소 표현.
    public struct DriftSample: Sendable, Equatable {
        public let driftMs: Double
        public let isFresh: Bool
        public let hasPdt: Bool
        public init(driftMs: Double, isFresh: Bool, hasPdt: Bool) {
            self.driftMs = driftMs
            self.isFresh = isFresh
            self.hasPdt = hasPdt
        }
    }

    // MARK: - Properties
    
    // [Fix 보정모드] 런타임 설정 변경 지원 — 콜백/sync 루프 유지한 채 config만 교체
    private var config: Configuration
    private let logger = AppLogger.sync
    
    private var pidController: PIDController
    private var latencyEWMA: EWMACalculator
    
    private var _state: SyncState = .idle
    private var _currentRate: Double = 1.0
    private var _latencyHistory: [TimeInterval] = []
    private var syncTask: Task<Void, Never>?

    // [P0 / 2026-04-25] PID dt 실측 — 기존 deltaTime=1.0 고정값은
    // 실제 제어 주기(≈5s, PowerAware 7.5s)와 5–7.5배 차이나 PID
    // 적분·미분 항이 완전히 잘못 계산되었다. ContinuousClock 기반으로
    // 다음 샘플까지 경과 시간을 실측하고, 긴 pause 등으로 인한
    // 스파이크를 제거하기 위해 [0.5..15]s 범위로 클램프한다.
    private var _lastProcessInstant: ContinuousClock.Instant?
    private let _pidClock = ContinuousClock()

    // [P1 / 2026-04-25] 웹 동기화 phase 상태 — docs §5.2 권장 상태기.
    // PDT drift 주입(`processDriftSample`)이 있을 때만 사용. 주입 없으면
    // 기존 경로(`processLatency`) 만 동작하고 phase 는 `.idle` 으로 유지.
    private var _webPhase: WebSyncPhase = .idle
    private var _ewmaDriftMs: Double?
    private var _consecutiveExcellent: Int = 0
    private var _lastSeekAt: Date = .distantPast
    private let _seekCooldown: TimeInterval = 8.0  // seek 후 8초간 추가 seek 금지

    /// phase 별 sync 주기 — docs §6.1의 1s/2s/5–10s 권장을 power-aware 로 확장.
    /// 기존 5s 고정값보다 acquiring 에서 빠르게 잡고, hold 에서 아끼는 구조.
    private var currentSyncInterval: TimeInterval {
        let base: TimeInterval
        switch _webPhase {
        case .acquiring, .snap: base = 1.5
        case .tracking:         base = 3.0
        case .reacquire:        base = 2.0
        case .hold:             base = 7.0
        case .idle:             base = 5.0
        }
        return PowerAwareInterval.scaled(base)
    }

    // PDT drift 제공자 — sync loop 가 매 tick 호출.
    // nil 반환 또는 provider 미설정 시 기존 latencyProvider 경로로 fallback.
    private var driftSampleProvider: (@Sendable () async -> DriftSample?)?
    
    // M1 fix: 버퍼링 중 rate 조정 일시 중지
    private var _isPausedForBuffering: Bool = false
    
    // [Fix 20] 버퍼링 해제 후 쿨다운 — 즉시 재가속 방지
    private var _cooldownUntil: Date = .distantPast
    private let _cooldownDuration: TimeInterval = 12.0  // 12초 쿨다운
    private let _cooldownMaxRate: Double = 1.03  // 쿨다운 중 최대 가속
    
    // [Fix 20] 가속↔버퍼링 진동 감지기
    private var _recentBufferingTimestamps: [Date] = []
    private var _oscillationMaxRate: Double?  // nil = 정상, 값 있으면 제한
    private var _oscillationResetTime: Date = .distantPast
    
    // 버퍼 건강도 콜백 — 가속 댐핑에 사용 (0.0~1.0, 기본 1.0)
    private var bufferHealthProvider: (@Sendable () -> Double)?
    
    // 초기 재생 시 seek 여부 — 첫 측정에서 타겟 대비 크게 벗어나면 seek으로 즉시 이동
    private var _initialSeekDone: Bool = false
    
    // [Fix 20] PID 비활성 상태 공개 — MetricsForwarder 속도 제어 여부 판단용
    public var isPIDActive: Bool {
        _state == .catchingUp || _state == .slowingDown
    }
    
    // [Fix 20-F] 멀티라이브 가속 예산 — 외부에서 설정하는 가속 상한 오버라이드
    // nil = config.maxPlaybackRate 사용 (기본), 값 있으면 해당 값으로 제한
    private var _maxRateOverride: Double?
    public func setMaxRateOverride(_ maxRate: Double?) {
        _maxRateOverride = maxRate
    }
    
    /// 현재 실효 최대 가속률 (config, 쿨다운, 진동, 외부 오버라이드 중 최소값)
    private var effectiveMaxRate: Double {
        var rate = config.maxPlaybackRate
        if let override = _maxRateOverride {
            rate = min(rate, override)
        }
        if Date() < _cooldownUntil {
            rate = min(rate, _cooldownMaxRate)
        }
        if let oscMax = _oscillationMaxRate {
            rate = min(rate, oscMax)
        }
        return rate
    }
    
    // Callbacks
    private var onRateChange: (@Sendable (Double) -> Void)?
    private var onSeekRequired: (@Sendable (TimeInterval) -> Void)?
    /// 매 측정 후 (raw, ewma, target) 알림 — StreamCoordinator → PlayerViewModel.latencyInfo 갱신용
    private var onLatencyMeasured: (@Sendable (TimeInterval, TimeInterval, TimeInterval) -> Void)?
    
    // MARK: - Public Accessors
    
    public var syncState: SyncState { _state }
    public var currentRate: Double { _currentRate }

    // MARK: - Web Sync Public Accessors (P1)

    public var webPhase: WebSyncPhase { _webPhase }
    public var smoothedDriftMs: Double? { _ewmaDriftMs }

    /// PDT drift 제공자 설정. nil 로 설정하면 기존 latency-only 경로로 되돌린다.
    public func setDriftSampleProvider(_ provider: (@Sendable () async -> DriftSample?)?) {
        self.driftSampleProvider = provider
        if provider == nil {
            _webPhase = .idle
            _ewmaDriftMs = nil
            _consecutiveExcellent = 0
        }
    }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.config = configuration
        self.pidController = PIDController(kp: configuration.pidKp, ki: configuration.pidKi, kd: configuration.pidKd)
        self.latencyEWMA = EWMACalculator(alpha: 0.15)
    }

    // MARK: - Runtime Configuration Update

    /// [Fix 보정모드] 런타임 중 설정만 교체 — 콜백/sync 루프/쿨다운 상태 모두 유지
    /// 사용자가 프리셋/슬라이더를 조정해도 보정 기능이 중단되지 않도록 함.
    public func updateConfiguration(_ newConfig: Configuration) {
        self.config = newConfig
        // PID 게인이 바뀌었으니 컨트롤러 재생성 (적분 누적은 리셋 — 새 게인에서 이전 적분값은 무의미)
        self.pidController = PIDController(kp: newConfig.pidKp, ki: newConfig.pidKi, kd: newConfig.pidKd)
        // EWMA는 그대로 유지 — 레이턴시 추정은 연속성 보존
        logger.info("LowLatency: configuration updated in-place (target=\(newConfig.targetLatency)s, kp=\(newConfig.pidKp))")
    }
    
    // MARK: - Setup
    
    /// Set callback for rate changes
    public func setOnRateChange(_ handler: @escaping @Sendable (Double) -> Void) {
        self.onRateChange = handler
    }
    
    /// Set callback for seek requirements
    public func setOnSeekRequired(_ handler: @escaping @Sendable (TimeInterval) -> Void) {
        self.onSeekRequired = handler
    }

    /// Set callback for latency measurements (current, ewma, target — all in seconds)
    public func setOnLatencyMeasured(_ handler: @escaping @Sendable (TimeInterval, TimeInterval, TimeInterval) -> Void) {
        self.onLatencyMeasured = handler
    }

    /// 버퍼 건강도 제공자 설정 (0.0~1.0) — 가속 시 댐핑에 사용
    public func setBufferHealthProvider(_ provider: @escaping @Sendable () -> Double) {
        self.bufferHealthProvider = provider
    }
    
    // MARK: - Buffering Pause (M1 fix + Fix 20 쿨다운/진동 감지)
    
    /// 버퍼링 시작 시 호출 — rate를 1.0으로 리셋, PID I항 리셋, 조정 일시 중지
    public func pauseForBuffering() {
        guard !_isPausedForBuffering else { return }
        _isPausedForBuffering = true
        
        // [Fix 20-A] PID 적분(I)항 리셋 — 축적된 오차가 재가속을 유발하지 않도록
        pidController.reset()
        
        if _currentRate != 1.0 {
            _currentRate = 1.0
            onRateChange?(1.0)
            logger.info("LowLatency: 버퍼링 감지 — rate 1.0으로 리셋 + PID 리셋, 조정 일시 중지")
        }
        
        // [Fix 20-C] 진동 감지: 최근 버퍼링 시각 기록
        let now = Date()
        _recentBufferingTimestamps.append(now)
        // 60초보다 오래된 기록 제거
        _recentBufferingTimestamps.removeAll { now.timeIntervalSince($0) > 60 }
        
        if _recentBufferingTimestamps.count >= 3 {
            // 60초 내 3회 이상 버퍼링 → 가속 상한을 1.03으로 제한
            _oscillationMaxRate = _cooldownMaxRate
            _oscillationResetTime = now.addingTimeInterval(120)  // 120초 후 자동 복원
            let count = _recentBufferingTimestamps.count
            logger.warning("LowLatency: 진동 감지 — 60초 내 \(count)회 버퍼링, 가속 상한 1.03 적용 (120초간)")
        }
    }
    
    /// 버퍼링 종료(재생 재개) 시 호출 — rate 조정 재개 (쿨다운 적용)
    public func resumeFromBuffering() {
        guard _isPausedForBuffering else { return }
        _isPausedForBuffering = false
        
        // [Fix 20-B] 쿨다운 기간 시작 — 버퍼 안정화용
        let duration = _cooldownDuration
        let maxRate = _cooldownMaxRate
        _cooldownUntil = Date().addingTimeInterval(duration)
        logger.info("LowLatency: 재생 재개 — \(Int(duration))초 쿨다운 (최대 가속 \(maxRate))")
    }
    
    // MARK: - Post-Seek Grace
    
    /// [Fix 20-E] Seek 실행 후 버퍼 재구축 보호
    /// PID 리셋 + 자동 버퍼링 일시정지 + 쿨다운 적용
    /// VLC가 .playing 상태로 돌아오면 StreamCoordinator가 resumeFromBuffering() 호출
    private func enterPostSeekGrace() {
        pidController.reset()
        latencyEWMA = EWMACalculator(alpha: 0.15)
        _latencyHistory.removeAll()
        _isPausedForBuffering = true
        _currentRate = 1.0
        // [P0 / 2026-04-25] grace 진입 — 다음 processLatency 의 dt 계산이
        // pause 구간을 포함해 증폭하지 않도록 clock 참조점을 초기화.
        _lastProcessInstant = nil
        onRateChange?(1.0)
        // seek 후에도 쿨다운 적용 — 재개 시 즉시 가속 방지
        let duration = _cooldownDuration
        _cooldownUntil = Date().addingTimeInterval(duration)
        logger.info("LowLatency: Seek 후 preload grace — PID/EWMA 리셋, 버퍼 재구축 대기")
    }
    
    // MARK: - Sync Control
    
    /// Start sync monitoring loop
    public func startSync(latencyProvider: @escaping @Sendable () async -> TimeInterval?) {
        stopSync()
        _state = .synced
        _initialSeekDone = false
        
        syncTask = Task { [weak self] in
            guard let self else { return }
            
            // [P1 / 2026-04-25] phase 별 동적 sync 주기 — AsyncTimerSequence 의 고정
            // 주기 한계를 벗어나기 위해 매 tick `currentSyncInterval` 을 다시 읽고
            // Task.sleep 으로 재무장한다. PDT drift 주입이 있을 때 acquiring(1.5s)
            // /tracking(3s)/hold(7s) 로 자동 변동, 미주입 시 기존 5s 동작 유지.
            while !Task.isCancelled {
                let intervalSec = await self.currentSyncInterval
                let nanos = UInt64(max(0.5, intervalSec) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { break }

                // 1순위: PDT drift 샘플 주입(WebLatencyClient). nil → 기존 경로.
                if let provider = await self.driftSampleProvider,
                   let sample = await provider() {
                    await self.processDriftSample(sample)
                } else if let latency = await latencyProvider() {
                    await self.processLatency(latency)
                }
            }
        }
    }
    
    /// Stop sync monitoring
    public func stopSync() {
        syncTask?.cancel()
        syncTask = nil
        _state = .idle
        _currentRate = 1.0
        _initialSeekDone = false
        pidController.reset()
        // 재연결 시 이전 세션의 stale EWMA/히스토리가 PID를 오염하지 않도록 리셋
        latencyEWMA = EWMACalculator(alpha: 0.15)
        _latencyHistory.removeAll()
        // [P0 / 2026-04-25] dt 초기화 — 재시작 시 첫 샘플은 deltaTime=0으로 계산되어 PID kick 방지.
        _lastProcessInstant = nil
        // [P1 / 2026-04-25] phase 상태 리셋
        _webPhase = .idle
        _ewmaDriftMs = nil
        _consecutiveExcellent = 0
    }
    
    /// Process a single latency measurement
    public func processLatency(_ currentLatency: TimeInterval) {
        // M1 fix: 버퍼링 중에는 rate 조정 스킵 (rate는 이미 1.0으로 리셋됨)
        guard !_isPausedForBuffering else { return }
        
        let smoothedLatency = latencyEWMA.update(currentLatency)

        // 측정 콜백 — StreamCoordinator → PlayerViewModel.latencyInfo 갱신
        onLatencyMeasured?(currentLatency, smoothedLatency, config.targetLatency)
        
        _latencyHistory.append(smoothedLatency)
        if _latencyHistory.count > 100 {
            _latencyHistory.removeFirst()
        }
        
        // [Fix 20-C] 진동 제한 자동 해제 (120초 경과)
        if let _ = _oscillationMaxRate, Date() > _oscillationResetTime {
            _oscillationMaxRate = nil
            _recentBufferingTimestamps.removeAll()
            logger.info("LowLatency: 진동 제한 해제 — 가속 범위 정상 복원")
        }
        
        // 초기 재생 시 타겟 대비 크게 벗어나면 seek으로 즉시 점프 (PID 수렴 대기 대신)
        // 첫 측정에서만 1회 적용 — 이후는 PID로 미세 조정
        if !_initialSeekDone {
            _initialSeekDone = true
            let initialError = smoothedLatency - config.targetLatency
            if initialError > 2.0 {
                // 타겟보다 2초 이상 뒤쳐진 상태 → seek으로 즉시 이동
                _state = .seekRequired
                onSeekRequired?(config.targetLatency)
                // [Fix 20-E] Seek 후 preload grace — 버퍼 재구축 보호
                enterPostSeekGrace()
                logger.info("Initial seek: latency \(String(format: "%.1f", smoothedLatency))s → target \(String(format: "%.1f", self.config.targetLatency))s")
                return
            }
        }
        
        // [Fix 20-D] 점진적 수렴: maxLatency 초과가 아닌 중간 범위(8~12s)는 가속으로 접근
        // seek은 maxLatency 초과 시에만 실행 (기존과 동일)
        if smoothedLatency > config.maxLatency {
            _state = .seekRequired
            onSeekRequired?(config.targetLatency)
            // [Fix 20-E] Seek 후 preload grace — 버퍼 재구축 보호
            enterPostSeekGrace()
            logger.warning("Latency \(String(format: "%.1f", smoothedLatency))s exceeds max, seek required")
            return
        }
        
        // Calculate PID output
        let error = smoothedLatency - config.targetLatency

        // [P0 / 2026-04-25] 실측 dt — 고정값 1.0 대체. 첨 샘플은 fallback
        // 5.0s(PowerAwareInterval.scaled 평균 주기)를 쓰고, 너무 짧거나(burst)
        // 너무 긴 경우(pause/sleep) PID 적분·미분 증폭을 막도록 클램프.
        let now = _pidClock.now
        let measuredDt: TimeInterval
        if let last = _lastProcessInstant {
            let components = last.duration(to: now).components
            measuredDt = TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
        } else {
            measuredDt = 5.0
        }
        _lastProcessInstant = now
        let dt = max(0.5, min(15.0, measuredDt))
        let pidOutput = pidController.update(error: error, deltaTime: dt)
        
        // Determine rate adjustment — 직접 PID 출력을 rate로 변환
        var newRate: Double
        
        // [Fix 보정모드] 비대칭 데드존 — catchUpThreshold/slowDownThreshold를 각각 독립 사용
        // error > 0: 뒤처짐 → catchUpThreshold 초과해야 가속 시작
        // error < 0: 앞서감 → slowDownThreshold 초과해야 감속 시작
        // 그 사이(데드존)는 synced 유지 — 미세 떨림으로 인한 불필요한 rate 변동 억제
        if error > config.catchUpThreshold {
            // 뒤쳐짐 — 속도 올림
            // 버퍼 건강도에 따라 가속 댐핑 — 낮은 버퍼에서 과도한 가속 방지
            let bh = bufferHealthProvider?() ?? 1.0
            let damping: Double
            if bh < 0.3 {
                damping = 0.0  // 버퍼 위험 — 가속 중단
            } else if bh < 0.6 {
                damping = 0.5  // 버퍼 주의 — 가속 절반
            } else {
                damping = 1.0  // 버퍼 정상 — 전체 가속
            }
            let rateOffset = min(pidOutput * 0.3 * damping, config.maxPlaybackRate - 1.0)
            newRate = min(1.0 + max(0.01 * damping, rateOffset), config.maxPlaybackRate)
            _state = .catchingUp
        } else if error < -config.slowDownThreshold {
            // 앞서감 — 속도 내림
            let rateOffset = max(pidOutput * 0.3, config.minPlaybackRate - 1.0)
            newRate = max(1.0 + min(-0.01, rateOffset), config.minPlaybackRate)
            _state = .slowingDown
        } else {
            // 데드존 안 — 동기화 완료 상태
            newRate = 1.0
            _state = .synced
        }
        
        // [Fix 20-F] 통합 가속 상한 (쿨다운 + 진동 + 멀티라이브 예산)
        if newRate > 1.0 {
            newRate = min(newRate, effectiveMaxRate)
        }
        
        // Apply rate if changed significantly (0.005 임계값: 미세한 떨림 무시)
        if abs(newRate - _currentRate) > 0.005 {
            _currentRate = newRate
            onRateChange?(newRate)
            
            if newRate != 1.0 {
                let targetLatency = self.config.targetLatency
                logger.debug("Rate: \(String(format: "%.3f", newRate)), Latency: \(String(format: "%.1f", smoothedLatency))s, Target: \(String(format: "%.1f", targetLatency))s, Error: \(String(format: "%.2f", error))s")
            }
        }
    }

    // MARK: - Drift Sample Path (P1 / 2026-04-25)

    /// PDT 기반 web↔app drift 샘플 처리 (정밀 모드).
    /// docs §5.3 ~ §5.4 권장 hysteresis + phase 전이 적용.
    ///
    /// 밴드(절대 drift, ms 단위):
    /// - ≤ 200ms              → tracking lock, rate=1.0
    /// - 200 < d ≤ 500ms      → tracking, micro-rate (0.985..1.015)
    /// - 500 < d ≤ 1500ms     → tracking, normal-rate (0.97..1.03)
    /// - 1500 < d ≤ 2500ms    → acquiring, wide-rate (0.97..1.06)
    /// - > 2500ms             → snap → seek (쿨다운 8s)
    ///
    /// stale 샘플(`isFresh=false`) → hold, rate=1.0 (seek 금지).
    public func processDriftSample(_ sample: DriftSample) {
        guard !_isPausedForBuffering else { return }

        // Stale guard — PDT 데이터 신선하지 않으면 1.0 으로 hold.
        guard sample.isFresh && sample.hasPdt else {
            if _webPhase != .idle, case .hold = _webPhase {} else {
                _webPhase = .hold(reason: sample.isFresh ? "no_pdt" : "stale")
                logger.info("WebSync phase=hold (\(sample.isFresh ? "no_pdt" : "stale"))")
            }
            if abs(_currentRate - 1.0) > 0.005 {
                _currentRate = 1.0
                onRateChange?(1.0)
            }
            _consecutiveExcellent = 0
            return
        }

        // EWMA 평활 (phase 별 alpha)
        let alpha = driftSmoothingAlpha
        let smoothed: Double
        if let prev = _ewmaDriftMs {
            smoothed = alpha * sample.driftMs + (1 - alpha) * prev
        } else {
            smoothed = sample.driftMs
        }
        _ewmaDriftMs = smoothed

        let absDrift = abs(smoothed)

        // [Fix 20-C] 진동 제한 자동 해제 (120초 경과)
        if let _ = _oscillationMaxRate, Date() > _oscillationResetTime {
            _oscillationMaxRate = nil
            _recentBufferingTimestamps.removeAll()
            logger.info("LowLatency: 진동 제한 해제 — 가속 범위 정상 복원")
        }

        // 밴드 5: snap → seek (대드리프트). _seekCooldown 동안은 acquiring 으로만.
        if absDrift > 2500 {
            let now = Date()
            if now.timeIntervalSince(_lastSeekAt) > _seekCooldown {
                _lastSeekAt = now
                let prevPhase = _webPhase
                _webPhase = .snap
                _state = .seekRequired
                onSeekRequired?(config.targetLatency)
                enterPostSeekGrace()
                _webPhase = .reacquire(reason: "snap")
                _consecutiveExcellent = 0
                if abs(_currentRate - 1.0) > 0.005 {
                    _currentRate = 1.0
                    onRateChange?(1.0)
                }
                logger.warning("WebSync snap: drift=\(Int(smoothed))ms → seek (prev=\(String(describing: prevPhase)))")
                return
            } else {
                // 쿨다운 중 — wide-rate 로 따라잡기
                _webPhase = .acquiring
            }
        } else if absDrift > 1500 {
            _webPhase = .acquiring
            _consecutiveExcellent = 0
        } else if absDrift <= 200 {
            _consecutiveExcellent += 1
            // tracking 진입: acquiring 에서 연속 3회 excellent 시
            switch _webPhase {
            case .tracking, .hold: _webPhase = .tracking
            default:
                if _consecutiveExcellent >= 3 { _webPhase = .tracking }
                else { _webPhase = .acquiring }
            }
        } else {
            // 200 < d ≤ 1500
            switch _webPhase {
            case .tracking: break  // 유지
            default: _webPhase = .acquiring
            }
            _consecutiveExcellent = 0
        }

        // 측정 콜백 — 외부 모니터링용 (drift 를 latency 단위로 변환: target + drift)
        let virtualLatency = config.targetLatency + smoothed / 1000.0
        onLatencyMeasured?(virtualLatency, virtualLatency, config.targetLatency)

        // Rate 계산 — 밴드별 hysteresis. drift > 0: 앱이 웹보다 뒤쳐짐 → 가속.
        var newRate: Double = 1.0
        let sign: Double = smoothed >= 0 ? 1.0 : -1.0

        if absDrift <= 200 {
            newRate = 1.0
            _state = .synced
        } else if absDrift <= 500 {
            // micro-rate: 0.985 .. 1.015 (선형 매핑 200→0.0, 500→1.0)
            let t = (absDrift - 200) / 300.0  // 0..1
            let delta = 0.015 * t
            newRate = 1.0 + sign * delta
            _state = sign > 0 ? .catchingUp : .slowingDown
        } else if absDrift <= 1500 {
            // normal-rate: 1.015 .. 1.03 (500→0.015, 1500→0.03)
            let t = (absDrift - 500) / 1000.0
            let delta = 0.015 + 0.015 * t
            newRate = 1.0 + sign * delta
            _state = sign > 0 ? .catchingUp : .slowingDown
        } else {
            // wide-rate (acquiring): 1.03 .. 1.06 (1500→0.03, 2500→0.06)
            let t = (absDrift - 1500) / 1000.0
            let delta = 0.03 + 0.03 * t
            newRate = 1.0 + sign * delta
            _state = sign > 0 ? .catchingUp : .slowingDown
        }

        // 버퍼 댐핑 — 가속 방향에서만 적용 (감속은 그대로 허용)
        if newRate > 1.0 {
            let bh = bufferHealthProvider?() ?? 1.0
            let damping: Double
            if bh < 0.3 { damping = 0.0 }
            else if bh < 0.6 { damping = 0.5 }
            else { damping = 1.0 }
            let delta = (newRate - 1.0) * damping
            newRate = 1.0 + delta
            // 통합 가속 상한
            newRate = min(newRate, effectiveMaxRate)
        } else if newRate < 1.0 {
            newRate = max(newRate, config.minPlaybackRate)
        }

        if abs(newRate - _currentRate) > 0.005 {
            _currentRate = newRate
            onRateChange?(newRate)
            logger.debug("WebSync drift=\(Int(smoothed))ms phase=\(String(describing: self._webPhase)) rate=\(String(format: "%.3f", newRate))")
        }
    }

    /// phase 별 EWMA alpha — acquiring 빠른 추종, tracking 안정.
    private var driftSmoothingAlpha: Double {
        switch _webPhase {
        case .acquiring, .snap, .reacquire: return 0.5
        case .tracking, .hold: return 0.2
        case .idle: return 0.3
        }
    }

    /// Get current latency snapshot for monitoring
    public func snapshot(currentLatency: TimeInterval) -> LatencySnapshot {
        return LatencySnapshot(
            currentLatency: currentLatency,
            targetLatency: config.targetLatency,
            ewmaLatency: latencyEWMA.current,
            playbackRate: _currentRate,
            syncState: _state,
            pidOutput: pidController.lastOutput,
            timestamp: Date()
        )
    }
    
    /// Reset all state
    public func reset() {
        pidController.reset()
        latencyEWMA = EWMACalculator(alpha: 0.15)
        _latencyHistory.removeAll()
        _currentRate = 1.0
        _state = .idle
        _initialSeekDone = false
    }
}
