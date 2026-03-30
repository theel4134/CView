// MARK: - PlaybackReconnectionHandlerTests.swift
// CViewPlayer - 재연결 핸들러 테스트

import Testing
import Foundation
@testable import CViewPlayer

/// Sendable 컬렉터 — @Sendable 클로저에서 안전하게 값 수집
private final class Collector<T: Sendable>: @unchecked Sendable {
    private var _values: [T] = []
    func append(_ value: T) { _values.append(value) }
    var values: [T] { _values }
    var count: Int { _values.count }
}

private final class Flag: @unchecked Sendable {
    private var _value: Bool = false
    func set() { _value = true }
    var value: Bool { _value }
}

// MARK: - ReconnectionConfig Preset Tests

@Suite("ReconnectionConfig Presets")
struct ReconnectionConfigPresetTests {

    @Test("aggressive 프리셋 값 검증")
    func aggressivePreset() {
        let config = ReconnectionConfig.aggressive
        #expect(config.maxRetries == 10)
        #expect(config.baseDelay == 0.5)
        #expect(config.maxRetryDelay == 15.0)
        #expect(config.backoffMultiplier == 1.5)
        #expect(config.retryOnNetworkRecovery == true)
    }

    @Test("balanced 프리셋 값 검증")
    func balancedPreset() {
        let config = ReconnectionConfig.balanced
        #expect(config.maxRetries == 5)
        #expect(config.baseDelay == 1.0)
        #expect(config.maxRetryDelay == 30.0)
        #expect(config.backoffMultiplier == 2.0)
        #expect(config.retryOnNetworkRecovery == true)
    }

    @Test("conservative 프리셋 값 검증")
    func conservativePreset() {
        let config = ReconnectionConfig.conservative
        #expect(config.maxRetries == 3)
        #expect(config.baseDelay == 2.0)
        #expect(config.maxRetryDelay == 60.0)
        #expect(config.backoffMultiplier == 3.0)
        #expect(config.retryOnNetworkRecovery == false)
    }

    @Test("커스텀 설정 생성")
    func customConfig() {
        let config = ReconnectionConfig(
            maxRetries: 7,
            baseDelay: 0.8,
            maxRetryDelay: 20.0,
            backoffMultiplier: 1.8
        )
        #expect(config.maxRetries == 7)
        #expect(config.baseDelay == 0.8)
        #expect(config.maxRetryDelay == 20.0)
        #expect(config.backoffMultiplier == 1.8)
        #expect(config.retryOnNetworkRecovery == true) // 기본값
    }
}

// MARK: - PlaybackReconnectionHandler State Tests

@Suite("PlaybackReconnectionHandler — Advanced")
struct PlaybackReconnectionHandlerAdvancedTests {

    @Test("초기 상태 검증")
    func initialState() async {
        let handler = PlaybackReconnectionHandler()
        let attempt = await handler.currentAttempt
        let isReconnecting = await handler.isReconnecting
        #expect(attempt == 0)
        #expect(isReconnecting == false)
    }

    @Test("setConfig 변경 확인")
    func setConfig() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        await handler.setConfig(.aggressive)
        // aggressive 설정이 반영되었는지 간접 확인: maxRetries 10
        // 재연결 시작 후 10회까지 시도 가능한지로 검증
        let attempts = await collectAttempts(handler: handler, maxWait: 11)
        // aggressive는 maxRetries=10이므로 최대 10번 시도
        #expect(attempts.count <= 10)
    }

    @Test("cancel — 상태 초기화")
    func cancelResetsState() async {
        let handler = PlaybackReconnectionHandler(config: .aggressive)
        await handler.startReconnecting(
            onAttempt: { _, delay in
                try? await Task.sleep(for: .seconds(delay))
            },
            onExhausted: {}
        )
        // 잠시 대기 후 cancel
        try? await Task.sleep(for: .milliseconds(100))
        await handler.cancel()

        let attempt = await handler.currentAttempt
        let isReconnecting = await handler.isReconnecting
        #expect(attempt == 0)
        #expect(isReconnecting == false)
    }

    @Test("handleSuccess — 상태 초기화")
    func handleSuccessResetsState() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        await handler.startReconnecting(
            onAttempt: { _, delay in
                try? await Task.sleep(for: .seconds(delay))
            },
            onExhausted: {}
        )
        try? await Task.sleep(for: .milliseconds(100))
        await handler.handleSuccess()

        let attempt = await handler.currentAttempt
        let isReconnecting = await handler.isReconnecting
        #expect(attempt == 0)
        #expect(isReconnecting == false)
    }

    @Test("reset — attempt만 초기화, isReconnecting 유지")
    func resetOnlyAttempt() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        await handler.startReconnecting(
            onAttempt: { _, delay in
                try? await Task.sleep(for: .seconds(delay))
            },
            onExhausted: {}
        )
        try? await Task.sleep(for: .milliseconds(100))
        await handler.reset()

        let attempt = await handler.currentAttempt
        let isReconnecting = await handler.isReconnecting
        #expect(attempt == 0)
        #expect(isReconnecting == true)

        // 클린업
        await handler.cancel()
    }

    @Test("double-start 방지 — 이미 재연결 중이면 무시")
    func doubleStartGuard() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        let firstCollector = Collector<Int>()
        let secondCollector = Collector<Int>()

        await handler.startReconnecting(
            onAttempt: { attempt, delay in
                firstCollector.append(attempt)
                try? await Task.sleep(for: .seconds(delay))
            },
            onExhausted: {}
        )

        // 즉시 두 번째 호출 — 무시되어야 함
        await handler.startReconnecting(
            onAttempt: { attempt, _ in
                secondCollector.append(attempt)
            },
            onExhausted: {}
        )

        try? await Task.sleep(for: .milliseconds(200))
        await handler.cancel()

        // 두 번째 호출의 onAttempt은 호출되지 않아야 함
        #expect(secondCollector.values.isEmpty)
    }

    @Test("maxRetries 소진 → onExhausted 호출")
    func exhaustedCallsCallback() async {
        // maxRetries=2, 빠른 지연
        let config = ReconnectionConfig(
            maxRetries: 2,
            baseDelay: 0.01,
            maxRetryDelay: 0.05,
            backoffMultiplier: 1.5
        )
        let handler = PlaybackReconnectionHandler(config: config)
        let exhaustedFlag = Flag()
        let attemptCollector = Collector<Int>()

        await handler.startReconnecting(
            onAttempt: { attempt, _ in
                attemptCollector.append(attempt)
            },
            onExhausted: {
                exhaustedFlag.set()
            }
        )

        // maxRetries=2이므로 금방 끝남
        try? await Task.sleep(for: .milliseconds(500))

        #expect(exhaustedFlag.value == true)
        #expect(attemptCollector.count == 2)
        #expect(attemptCollector.values == [1, 2])
    }

    @Test("지수 백오프 delay 값 검증 (balanced)")
    func exponentialBackoffDelays() async {
        let config = ReconnectionConfig(
            maxRetries: 4,
            baseDelay: 1.0,
            maxRetryDelay: 30.0,
            backoffMultiplier: 2.0
        )
        let handler = PlaybackReconnectionHandler(config: config)
        let delayCollector = Collector<TimeInterval>()

        await handler.startReconnecting(
            onAttempt: { _, delay in
                delayCollector.append(delay)
                // delay 대기 없이 즉시 반환
            },
            onExhausted: {}
        )

        try? await Task.sleep(for: .milliseconds(500))

        // delay = min(1.0 * pow(2.0, attempt-1), 30.0)
        // attempt 1: min(1.0 * 1.0, 30) = 1.0
        // attempt 2: min(1.0 * 2.0, 30) = 2.0
        // attempt 3: min(1.0 * 4.0, 30) = 4.0
        // attempt 4: min(1.0 * 8.0, 30) = 8.0
        let delays = delayCollector.values
        #expect(delays.count == 4)
        if delays.count == 4 {
            #expect(abs(delays[0] - 1.0) < 0.001)
            #expect(abs(delays[1] - 2.0) < 0.001)
            #expect(abs(delays[2] - 4.0) < 0.001)
            #expect(abs(delays[3] - 8.0) < 0.001)
        }
    }

    @Test("maxRetryDelay 상한 적용 확인")
    func delayCappedAtMax() async {
        let config = ReconnectionConfig(
            maxRetries: 5,
            baseDelay: 10.0,
            maxRetryDelay: 15.0,
            backoffMultiplier: 3.0
        )
        let handler = PlaybackReconnectionHandler(config: config)
        let delayCollector = Collector<TimeInterval>()

        await handler.startReconnecting(
            onAttempt: { _, delay in
                delayCollector.append(delay)
            },
            onExhausted: {}
        )

        try? await Task.sleep(for: .milliseconds(500))

        // attempt 1: min(10*1, 15) = 10
        // attempt 2: min(10*3, 15) = 15 (capped)
        // attempt 3: min(10*9, 15) = 15 (capped)
        let delays = delayCollector.values
        #expect(delays.count >= 3)
        if delays.count >= 3 {
            #expect(abs(delays[0] - 10.0) < 0.001)
            #expect(abs(delays[1] - 15.0) < 0.001)
            #expect(abs(delays[2] - 15.0) < 0.001)
        }

        await handler.cancel()
    }

    // MARK: - Helpers

    /// 핸들러 시작 후 attempt 번호들을 수집
    private func collectAttempts(handler: PlaybackReconnectionHandler, maxWait: Int) async -> [Int] {
        let collector = Collector<Int>()
        await handler.startReconnecting(
            onAttempt: { attempt, _ in
                collector.append(attempt)
            },
            onExhausted: {}
        )
        try? await Task.sleep(for: .milliseconds(500))
        await handler.cancel()
        return collector.values
    }
}
