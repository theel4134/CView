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
            
            // 5.0s: PID 제어 주기를 낮춰 CPU 절약 + 버퍼 안정화. 
            // VLC 내부 버퍼가 안정될 충분한 시간 확보.
            // [Fix P-7] PowerAware: Battery 모드에서 7.5초로 연장 (1.5×) — PID 보정은
            // 추세성이라 정밀도 영향 미미, idle wake-up 33% 감소.
            let interval = PowerAwareInterval.scaled(5.0 as TimeInterval)
            let timer = AsyncTimerSequence(interval: interval)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                
                if let latency = await latencyProvider() {
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
