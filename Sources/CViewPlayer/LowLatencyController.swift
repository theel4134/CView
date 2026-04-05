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
        
        /// 웹(hls.js) 동기화 프리셋 — 앱↔웹 동일 재생 위치 목표
        /// hls.js 기본값: liveSyncDurationCount=3 × TARGETDURATION(2s) = 6.0s 지연
        /// 앱은 VLC 내부 버퍼(~1s) + CDN→프록시 파이프라인을 고려하여 6.0s 타겟
        /// PID 게인을 적극적으로 설정: 빠른 수렴 후 정밀 유지
        /// catchUpThreshold=0.5: ±0.5초 초과 시 즉시 속도 조정 시작
        /// slowDownThreshold=0.3: ±0.3초 이내면 동기화 완료로 판단
        public static let webSync = Configuration(
            targetLatency: 6.0,
            maxLatency: 10.0,
            minLatency: 3.0,
            maxPlaybackRate: 1.15,
            minPlaybackRate: 0.90,
            catchUpThreshold: 0.5,
            slowDownThreshold: 0.3,
            pidKp: 1.2,
            pidKi: 0.15,
            pidKd: 0.08
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
    
    private let config: Configuration
    private let logger = AppLogger.sync
    
    private var pidController: PIDController
    private var latencyEWMA: EWMACalculator
    
    private var _state: SyncState = .idle
    private var _currentRate: Double = 1.0
    private var _latencyHistory: [TimeInterval] = []
    private var syncTask: Task<Void, Never>?
    
    // M1 fix: 버퍼링 중 rate 조정 일시 중지
    private var _isPausedForBuffering: Bool = false
    
    // 초기 재생 시 seek 여부 — 첫 측정에서 타겟 대비 크게 벗어나면 seek으로 즉시 이동
    private var _initialSeekDone: Bool = false
    
    // Callbacks
    private var onRateChange: (@Sendable (Double) -> Void)?
    private var onSeekRequired: (@Sendable (TimeInterval) -> Void)?
    
    // MARK: - Public Accessors
    
    public var syncState: SyncState { _state }
    public var currentRate: Double { _currentRate }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.config = configuration
        self.pidController = PIDController(kp: configuration.pidKp, ki: configuration.pidKi, kd: configuration.pidKd)
        self.latencyEWMA = EWMACalculator(alpha: 0.3)
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
    
    // MARK: - Buffering Pause (M1 fix)
    
    /// 버퍼링 시작 시 호출 — rate를 1.0으로 리셋하고 조정 일시 중지
    public func pauseForBuffering() {
        guard !_isPausedForBuffering else { return }
        _isPausedForBuffering = true
        if _currentRate != 1.0 {
            _currentRate = 1.0
            onRateChange?(1.0)
            logger.info("LowLatency: 버퍼링 감지 — rate 1.0으로 리셋, 조정 일시 중지")
        }
    }
    
    /// 버퍼링 종료(재생 재개) 시 호출 — rate 조정 재개
    public func resumeFromBuffering() {
        guard _isPausedForBuffering else { return }
        _isPausedForBuffering = false
        logger.info("LowLatency: 재생 재개 — rate 조정 재개")
    }
    
    // MARK: - Sync Control
    
    /// Start sync monitoring loop
    public func startSync(latencyProvider: @escaping @Sendable () async -> TimeInterval?) {
        stopSync()
        _state = .synced
        _initialSeekDone = false
        
        syncTask = Task { [weak self] in
            guard let self else { return }
            
            // 3.0s: PID 제어 주기를 낮춰 CPU 절약. 3초 간격에서도 실시간 지연 보정 충분.
            let timer = AsyncTimerSequence(interval: 3.0 as TimeInterval)
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
        latencyEWMA = EWMACalculator(alpha: 0.3)
        _latencyHistory.removeAll()
    }
    
    /// Process a single latency measurement
    public func processLatency(_ currentLatency: TimeInterval) {
        // M1 fix: 버퍼링 중에는 rate 조정 스킵 (rate는 이미 1.0으로 리셋됨)
        guard !_isPausedForBuffering else { return }
        
        let smoothedLatency = latencyEWMA.update(currentLatency)
        
        _latencyHistory.append(smoothedLatency)
        if _latencyHistory.count > 100 {
            _latencyHistory.removeFirst()
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
                pidController.reset()
                logger.info("Initial seek: latency \(String(format: "%.1f", smoothedLatency))s → target \(String(format: "%.1f", self.config.targetLatency))s")
                return
            }
        }
        
        // Check if seek is required (latency too high)
        if smoothedLatency > config.maxLatency {
            _state = .seekRequired
            onSeekRequired?(config.targetLatency)
            pidController.reset()
            logger.warning("Latency \(String(format: "%.1f", smoothedLatency))s exceeds max, seek required")
            return
        }
        
        // Calculate PID output
        let error = smoothedLatency - config.targetLatency
        let pidOutput = pidController.update(error: error, deltaTime: 1.0)
        
        // Determine rate adjustment — 직접 PID 출력을 rate로 변환
        let newRate: Double
        
        if abs(error) < config.slowDownThreshold {
            // 데드존 안 — 동기화 완료 상태
            newRate = 1.0
            _state = .synced
        } else if error > 0 {
            // 뒤쳐짐 — 속도 올림
            // PID 출력을 직접 rate 오프셋으로 사용 (0.1 승수 제거)
            // 클램핑으로 max rate 초과 방지
            let rateOffset = min(pidOutput * 0.3, config.maxPlaybackRate - 1.0)
            newRate = min(1.0 + max(0.01, rateOffset), config.maxPlaybackRate)
            _state = .catchingUp
        } else {
            // 앞서감 — 속도 내림
            let rateOffset = max(pidOutput * 0.3, config.minPlaybackRate - 1.0)
            newRate = max(1.0 + min(-0.01, rateOffset), config.minPlaybackRate)
            _state = .slowingDown
        }
        
        // Apply rate if changed significantly
        if abs(newRate - _currentRate) > 0.003 {
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
        latencyEWMA = EWMACalculator(alpha: 0.3)
        _latencyHistory.removeAll()
        _currentRate = 1.0
        _state = .idle
        _initialSeekDone = false
    }
}
