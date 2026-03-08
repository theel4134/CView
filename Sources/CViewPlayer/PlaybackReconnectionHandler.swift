// MARK: - PlaybackReconnectionHandler.swift
// CViewPlayer - 라이브 스트림 재연결 핸들러
// Reference: chzzkView-v1/StreamReconnectionManager.swift, EnhancedErrorRecoverySystem.swift

import Foundation
import CViewCore

// MARK: - Reconnection Configuration

/// 재연결 전략 설정
public struct ReconnectionConfig: Sendable {
    /// 최대 재시도 횟수
    public var maxRetries: Int
    /// 첫 번째 재시도 기본 지연 시간 (초)
    public var baseDelay: TimeInterval
    /// 최대 지연 시간 상한 (초)
    public var maxRetryDelay: TimeInterval
    /// 지수 백오프 승수
    public var backoffMultiplier: Double
    /// 네트워크 복구 감지 시 즉시 재시도 여부
    public var retryOnNetworkRecovery: Bool

    /// 프리셋: 공격적 — 빠른 재연결, 높은 재시도 횟수
    public static let aggressive = ReconnectionConfig(
        maxRetries: 10,
        baseDelay: 0.5,
        maxRetryDelay: 15.0,
        backoffMultiplier: 1.5,
        retryOnNetworkRecovery: true
    )

    /// 프리셋: 균형 — 기본 전략
    public static let balanced = ReconnectionConfig(
        maxRetries: 5,
        baseDelay: 1.0,
        maxRetryDelay: 30.0,
        backoffMultiplier: 2.0,
        retryOnNetworkRecovery: true
    )

    /// 프리셋: 보수적 — 느리지만 안정적
    public static let conservative = ReconnectionConfig(
        maxRetries: 3,
        baseDelay: 2.0,
        maxRetryDelay: 60.0,
        backoffMultiplier: 3.0,
        retryOnNetworkRecovery: false
    )

    public init(
        maxRetries: Int,
        baseDelay: TimeInterval,
        maxRetryDelay: TimeInterval,
        backoffMultiplier: Double,
        retryOnNetworkRecovery: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxRetryDelay = maxRetryDelay
        self.backoffMultiplier = backoffMultiplier
        self.retryOnNetworkRecovery = retryOnNetworkRecovery
    }
}

// MARK: - Reconnection Handler

/// 라이브 스트림 자동 재연결 핸들러
/// - 지수 백오프: `delay = min(baseDelay * pow(backoffMultiplier, attempt), maxRetryDelay)`
/// - 최대 재시도 횟수 초과 시 `onExhausted` 콜백 호출
/// - `reset()` 호출 시 재시도 카운터 초기화
public actor PlaybackReconnectionHandler {

    // MARK: - State

    private(set) var attempt: Int = 0
    private(set) var isReconnecting: Bool = false
    private var config: ReconnectionConfig
    private var reconnectTask: Task<Void, Never>?
    private let logger = AppLogger.player

    // MARK: - Init

    public init(config: ReconnectionConfig = .balanced) {
        self.config = config
    }

    // MARK: - Public API

    /// 재연결 설정 변경
    public func setConfig(_ newConfig: ReconnectionConfig) {
        config = newConfig
    }

    /// 현재 재시도 횟수
    public var currentAttempt: Int { attempt }

    /// 재연결 시작
    /// - Parameters:
    ///   - onAttempt: 각 재시도 직전 호출. 재시도 번호(1-based), 지연 시간(초) 전달
    ///   - onExhausted: 최대 재시도 횟수 초과 시 호출
    public func startReconnecting(
        onAttempt: @escaping @Sendable (Int, TimeInterval) async -> Void,
        onExhausted: @escaping @Sendable () async -> Void
    ) {
        guard !isReconnecting else { return }
        isReconnecting = true
        attempt = 0

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            while await self.shouldContinue() {
                let currentAttempt = await self.incrementAttempt()
                let maxRetries = await self.maxRetries
                guard currentAttempt <= maxRetries else {
                    await self.markFinished()
                    await onExhausted()
                    return
                }

                let delay = await self.calculateDelay(for: currentAttempt)
                await self.log(attempt: currentAttempt, delay: delay)

                // onAttempt 클로저가 delay 대기 + 실제 재시도를 모두 처리
                // (이전에는 onAttempt 내부 sleep + 여기서 추가 sleep으로 이중 대기 발생)
                await onAttempt(currentAttempt, delay)

                guard !Task.isCancelled else {
                    await self.markFinished()
                    return
                }
            }

            await self.markFinished()
        }
    }

    /// 재연결 중단 및 상태 초기화
    public func cancel() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        attempt = 0
    }

    /// 재시도 카운터만 초기화 (재연결 중단하지 않음)
    public func reset() {
        attempt = 0
    }

    /// 재연결 성공 처리 — 상태 초기화
    public func handleSuccess() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        attempt = 0
        logger.info("PlaybackReconnectionHandler: 재연결 성공")
    }

    // MARK: - Private Helpers

    private func shouldContinue() -> Bool {
        !Task.isCancelled && isReconnecting
    }

    private func incrementAttempt() -> Int {
        attempt += 1
        return attempt
    }

    private var maxRetries: Int { config.maxRetries }

    private func calculateDelay(for attempt: Int) -> TimeInterval {
        // 지수 백오프: delay = min(baseDelay * pow(backoffMultiplier, attempt - 1), maxRetryDelay)
        let raw = config.baseDelay * pow(config.backoffMultiplier, Double(attempt - 1))
        return min(raw, config.maxRetryDelay)
    }

    private func markFinished() {
        isReconnecting = false
    }

    private func log(attempt: Int, delay: TimeInterval) {
        logger.info("PlaybackReconnectionHandler: 재시도 \(attempt)/\(self.config.maxRetries) — \(String(format: "%.1f", delay))초 후")
    }
}
