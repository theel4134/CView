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
    
    // MARK: - Sync Control
    
    /// Start sync monitoring loop
    public func startSync(latencyProvider: @escaping @Sendable () async -> TimeInterval?) {
        stopSync()
        _state = .synced
        
        syncTask = Task { [weak self] in
            guard let self else { return }
            
            // 2.0s: 라이브 스트림 레이턴시 동기화 목적에 충분한 간격.
            // 0.5s(기존)는 세션당 2회/초 Swift concurrency Task를 생성해 CPU 낭비.
            let timer = AsyncTimerSequence(interval: 2.0 as TimeInterval)
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
        pidController.reset()
    }
    
    /// Process a single latency measurement
    public func processLatency(_ currentLatency: TimeInterval) {
        let smoothedLatency = latencyEWMA.update(currentLatency)
        
        _latencyHistory.append(smoothedLatency)
        if _latencyHistory.count > 100 {
            _latencyHistory.removeFirst()
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
        let pidOutput = pidController.update(error: error, deltaTime: 2.0)
        
        // Determine rate adjustment
        let newRate: Double
        
        if abs(error) < config.slowDownThreshold {
            // Within acceptable range
            newRate = 1.0
            _state = .synced
        } else if error > config.catchUpThreshold {
            // Too far behind - speed up
            let adjustment = min(pidOutput * 0.1, config.maxPlaybackRate - 1.0)
            newRate = min(1.0 + max(0, adjustment), config.maxPlaybackRate)
            _state = .catchingUp
        } else if error < -config.slowDownThreshold {
            // Too far ahead - slow down
            let adjustment = max(pidOutput * 0.1, config.minPlaybackRate - 1.0)
            newRate = max(1.0 + min(0, adjustment), config.minPlaybackRate)
            _state = .slowingDown
        } else {
            // Mild adjustment zone
            let rateAdjustment = pidOutput * 0.05
            newRate = max(config.minPlaybackRate, min(config.maxPlaybackRate, 1.0 + rateAdjustment))
            _state = error > 0 ? .catchingUp : .slowingDown
        }
        
        // Apply rate if changed significantly
        if abs(newRate - _currentRate) > 0.005 {
            _currentRate = newRate
            onRateChange?(newRate)
            
            if newRate != 1.0 {
                let targetLatency = self.config.targetLatency
                logger.debug("Rate: \(String(format: "%.3f", newRate)), Latency: \(String(format: "%.1f", smoothedLatency))s, Target: \(String(format: "%.1f", targetLatency))s")
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
    }
}
