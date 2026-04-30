// MARK: - ReconnectionPolicy.swift
// CViewChat - Smart reconnection with exponential backoff + jitter
// 원본: 단순 reconnect → 개선: exponential backoff + jitter + circuit breaker

import Foundation
import CViewCore

// MARK: - Reconnection Policy

/// Configurable reconnection strategy with exponential backoff and jitter.
/// Prevents thundering herd on server recovery.
public actor ReconnectionPolicy {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let initialDelay: TimeInterval
        public let maxDelay: TimeInterval
        public let maxAttempts: Int
        public let backoffMultiplier: Double
        public let jitterFactor: Double
        public let resetThreshold: TimeInterval
        
        public static let `default` = Configuration(
            initialDelay: 1.0,
            maxDelay: ReconnectDefaults.defaultMaxDelay,
            maxAttempts: ReconnectDefaults.defaultMaxAttempts,
            backoffMultiplier: 2.0,
            jitterFactor: ReconnectDefaults.defaultJitter,
            resetThreshold: ReconnectDefaults.resetThreshold
        )
        
        public static let aggressive = Configuration(
            initialDelay: 0.5,
            maxDelay: ReconnectDefaults.aggressiveMaxDelay,
            maxAttempts: ReconnectDefaults.aggressiveMaxAttempts,
            backoffMultiplier: 1.5,
            jitterFactor: 0.15,
            resetThreshold: 30.0
        )
        
        public init(
            initialDelay: TimeInterval = 1.0,
            maxDelay: TimeInterval = ReconnectDefaults.defaultMaxDelay,
            maxAttempts: Int = ReconnectDefaults.defaultMaxAttempts,
            backoffMultiplier: Double = 2.0,
            jitterFactor: Double = ReconnectDefaults.defaultJitter,
            resetThreshold: TimeInterval = ReconnectDefaults.resetThreshold
        ) {
            self.initialDelay = initialDelay
            self.maxDelay = maxDelay
            self.maxAttempts = maxAttempts
            self.backoffMultiplier = backoffMultiplier
            self.jitterFactor = jitterFactor
            self.resetThreshold = resetThreshold
        }
    }
    
    // MARK: - State
    
    public enum State: Sendable, Equatable {
        case idle
        case waiting(attempt: Int, delay: TimeInterval)
        case connecting(attempt: Int)
        case connected
        case exhausted
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let logger = AppLogger.chat
    
    private var currentAttempt: Int = 0
    private var lastSuccessfulConnection: Date?
    private var _state: State = .idle
    private var reconnectTask: Task<Void, Never>?
    
    public var state: State { _state }
    public var attemptsRemaining: Int { config.maxAttempts - currentAttempt }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Public API
    
    /// Calculate next reconnection delay and update state
    public func nextDelay() -> TimeInterval? {
        // If connected long enough, reset attempts
        if let lastSuccess = lastSuccessfulConnection,
           Date().timeIntervalSince(lastSuccess) > config.resetThreshold {
            reset()
        }
        
        currentAttempt += 1
        
        guard currentAttempt <= config.maxAttempts else {
            _state = .exhausted
            let maxAttempts = self.config.maxAttempts
            logger.error("Reconnection exhausted after \(maxAttempts) attempts")
            return nil
        }
        
        let baseDelay = config.initialDelay * pow(config.backoffMultiplier, Double(currentAttempt - 1))
        let clampedDelay = min(baseDelay, config.maxDelay)
        
        // Add jitter: delay ± (jitterFactor * delay)
        let jitter = clampedDelay * config.jitterFactor
        let finalDelay = clampedDelay + Double.random(in: -jitter...jitter)
        let safeDelay = max(0.1, finalDelay)
        
        _state = .waiting(attempt: currentAttempt, delay: safeDelay)
        let attempt = self.currentAttempt
        let maxAttempts = self.config.maxAttempts
        logger.info("Reconnect attempt \(attempt)/\(maxAttempts), delay: \(String(format: "%.1f", safeDelay))s")
        
        return safeDelay
    }
    
    /// Mark connection as successful, reset counters
    public func markConnected() {
        currentAttempt = 0
        lastSuccessfulConnection = Date()
        _state = .connected
        logger.info("Connection established, reconnection state reset")
    }
    
    /// Reset the reconnection state
    public func reset() {
        currentAttempt = 0
        lastSuccessfulConnection = nil  // nextDelay()에서 무한 reset 루프 방지
        _state = .idle
        reconnectTask?.cancel()
        reconnectTask = nil
    }
    
    /// Check if reconnection should be attempted
    public var shouldReconnect: Bool {
        currentAttempt < config.maxAttempts
    }
    
    /// Execute reconnection with automatic delay and retry
    public func executeReconnection(
        action: @Sendable @escaping () async throws -> Void
    ) async throws {
        while shouldReconnect {
            guard let delay = nextDelay() else {
                throw AppError.chat(.connectionFailed("재연결 지연 계산 실패"))
            }
            
            _state = .waiting(attempt: currentAttempt, delay: delay)
            
            try await Task.sleep(for: .seconds(delay))
            
            guard !Task.isCancelled else { return }
            
            _state = .connecting(attempt: currentAttempt)
            
            do {
                try await action()
                markConnected()
                return
            } catch {
                let attempt = self.currentAttempt
                logger.warning("Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
                continue
            }
        }
        
        _state = .exhausted
        throw AppError.chat(.connectionFailed("최대 재연결 시도 횟수 초과"))
    }
    
    /// Cancel any pending reconnection
    public func cancel() {
        reconnectTask?.cancel()
        reconnectTask = nil
        _state = .idle
    }
}

// MARK: - Convenience Extensions

extension ReconnectionPolicy {
    /// Quick check for connection viability
    public var isExhausted: Bool {
        if case .exhausted = _state { return true }
        return false
    }
    
    /// Formatted status for UI display
    public var statusDescription: String {
        switch _state {
        case .idle: return "대기 중"
        case .waiting(let attempt, let delay):
            return "재연결 대기 (\(attempt)/\(config.maxAttempts)) - \(String(format: "%.0f", delay))초"
        case .connecting(let attempt):
            return "재연결 중 (\(attempt)/\(config.maxAttempts))"
        case .connected: return "연결됨"
        case .exhausted: return "재연결 실패"
        }
    }
}
