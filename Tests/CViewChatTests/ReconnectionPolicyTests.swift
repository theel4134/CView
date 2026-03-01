// MARK: - ReconnectionPolicyTests.swift
// Comprehensive unit tests for ReconnectionPolicy

import Testing
import Foundation
@testable import CViewChat
@testable import CViewCore

// MARK: - Exponential Backoff Calculation

@Suite("ReconnectionPolicy — Backoff Calculation")
struct ReconnectionPolicyBackoffTests {

    @Test("First delay equals initialDelay when jitter is 0")
    func firstDelayNoJitter() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        let delay = await policy.nextDelay()
        #expect(delay != nil)
        #expect(abs(delay! - 2.0) < 0.01)
    }

    @Test("Second delay is initialDelay * multiplier")
    func secondDelay() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 120.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay() // 1.0
        let second = await policy.nextDelay()
        #expect(second != nil)
        #expect(abs(second! - 2.0) < 0.01) // 1.0 * 2^1
    }

    @Test("Third delay is initialDelay * multiplier^2")
    func thirdDelay() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 120.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay() // 1
        _ = await policy.nextDelay() // 2
        let third = await policy.nextDelay()
        #expect(third != nil)
        #expect(abs(third! - 4.0) < 0.01) // 1.0 * 2^2
    }

    @Test("Backoff sequence: 1, 2, 4, 8, 16 with multiplier=2")
    func backoffSequence() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 5,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        let expected: [Double] = [1.0, 2.0, 4.0, 8.0, 16.0]

        for exp in expected {
            let delay = await policy.nextDelay()
            #expect(delay != nil)
            #expect(abs(delay! - exp) < 0.01, "Expected \(exp), got \(delay!)")
        }
    }

    @Test("Backoff with multiplier 1.5")
    func backoffMultiplier1_5() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 4,
            backoffMultiplier: 1.5,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        let d1 = await policy.nextDelay()!
        let d2 = await policy.nextDelay()!
        let d3 = await policy.nextDelay()!

        #expect(abs(d1 - 1.0) < 0.01)
        #expect(abs(d2 - 1.5) < 0.01)
        #expect(abs(d3 - 2.25) < 0.01) // 1.0 * 1.5^2
    }
}

// MARK: - Max Delay Cap

@Suite("ReconnectionPolicy — Max Delay Cap")
struct ReconnectionPolicyMaxDelayTests {

    @Test("Delay is capped at maxDelay")
    func capAtMax() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 10.0,
            maxDelay: 15.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay() // 10.0
        let d2 = await policy.nextDelay()! // min(20, 15) = 15
        let d3 = await policy.nextDelay()! // min(40, 15) = 15
        #expect(abs(d2 - 15.0) < 0.01)
        #expect(abs(d3 - 15.0) < 0.01)
    }

    @Test("All delays never exceed maxDelay (many attempts)")
    func neverExceedMax() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 10.0,
            maxAttempts: 20,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        for _ in 0..<20 {
            if let delay = await policy.nextDelay() {
                #expect(delay <= 10.0, "Delay \(delay) exceeds maxDelay 10.0")
            }
        }
    }
}

// MARK: - Jitter Bounds

@Suite("ReconnectionPolicy — Jitter")
struct ReconnectionPolicyJitterTests {

    @Test("Jitter stays within ±jitterFactor * baseDelay")
    func jitterBounds() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 10.0,
            maxDelay: 100.0,
            maxAttempts: 50,
            backoffMultiplier: 1.0, // No growth, always 10
            jitterFactor: 0.25
        )

        // Run multiple attempts and check bounds
        for _ in 0..<10 {
            let policy = ReconnectionPolicy(configuration: config)
            let delay = await policy.nextDelay()!
            // Base = 10, jitter = ±2.5, so range [7.5, 12.5], but clamped ≥ 0.1
            #expect(delay >= 0.1, "Delay should be at least 0.1")
            #expect(delay <= 12.5, "Delay \(delay) exceeds upper jitter bound")
        }
    }

    @Test("Zero jitter gives exact base delay")
    func zeroJitter() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 5.0,
            maxDelay: 100.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        let delay = await policy.nextDelay()!
        #expect(abs(delay - 5.0) < 0.01)
    }

    @Test("Delay is always at least 0.1 even with large negative jitter")
    func minimumDelay() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxDelay: 100.0,
            maxAttempts: 50,
            backoffMultiplier: 1.0,
            jitterFactor: 0.99 // Jitter can reduce to near 0
        )
        for _ in 0..<20 {
            let policy = ReconnectionPolicy(configuration: config)
            let delay = await policy.nextDelay()!
            #expect(delay >= 0.1, "Delay should be at least 0.1, got \(delay)")
        }
    }
}

// MARK: - Max Attempts

@Suite("ReconnectionPolicy — Max Attempts")
struct ReconnectionPolicyMaxAttemptsTests {

    @Test("Returns nil after maxAttempts exhausted")
    func returnsNilAfterMax() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        #expect(await policy.nextDelay() != nil) // 1
        #expect(await policy.nextDelay() != nil) // 2
        #expect(await policy.nextDelay() != nil) // 3
        #expect(await policy.nextDelay() == nil) // nil
    }

    @Test("State is exhausted after max attempts")
    func stateExhausted() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 1,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay() // 1
        _ = await policy.nextDelay() // nil
        #expect(await policy.state == .exhausted)
    }

    @Test("shouldReconnect is false after exhaustion")
    func shouldReconnectFalse() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 1,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        #expect(await policy.shouldReconnect == false)
    }

    @Test("isExhausted is true after exhaustion")
    func isExhaustedTrue() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 1,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        #expect(await policy.isExhausted == true)
    }

    @Test("attemptsRemaining decreases correctly")
    func attemptsRemaining() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        #expect(await policy.attemptsRemaining == 5)
        _ = await policy.nextDelay()
        #expect(await policy.attemptsRemaining == 4)
        _ = await policy.nextDelay()
        #expect(await policy.attemptsRemaining == 3)
    }

    @Test("maxAttempts of 0 returns nil immediately")
    func zeroMaxAttempts() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        #expect(await policy.nextDelay() == nil)
    }
}

// MARK: - Reset & State Management

@Suite("ReconnectionPolicy — Reset & State")
struct ReconnectionPolicyResetTests {

    @Test("Reset sets state to idle")
    func resetToIdle() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        await policy.reset()
        #expect(await policy.state == .idle)
    }

    @Test("Reset restores attemptsRemaining")
    func resetRestoresAttempts() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        await policy.reset()
        #expect(await policy.attemptsRemaining == 5)
    }

    @Test("Reset allows re-use after exhaustion")
    func resetAfterExhaustion() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 1,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay() // exhausted
        #expect(await policy.isExhausted == true)

        await policy.reset()
        #expect(await policy.isExhausted == false)
        #expect(await policy.shouldReconnect == true)
        let delay = await policy.nextDelay()
        #expect(delay != nil)
    }

    @Test("markConnected sets state to connected")
    func markConnectedState() async {
        let policy = ReconnectionPolicy(configuration: .default)
        _ = await policy.nextDelay()
        await policy.markConnected()
        #expect(await policy.state == .connected)
    }

    @Test("markConnected resets attempt counter")
    func markConnectedResetsAttempts() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 10,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        await policy.markConnected()
        #expect(await policy.attemptsRemaining == 10)
    }

    @Test("After markConnected, nextDelay restarts from initialDelay")
    func markConnectedResetsDelay() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 10,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay() // 1
        _ = await policy.nextDelay() // 2
        _ = await policy.nextDelay() // 4
        await policy.markConnected()
        let nextAfterReset = await policy.nextDelay()
        #expect(nextAfterReset != nil)
        #expect(abs(nextAfterReset! - 1.0) < 0.01)
    }

    @Test("Cancel sets state to idle")
    func cancelToIdle() async {
        let policy = ReconnectionPolicy(configuration: .default)
        _ = await policy.nextDelay()
        await policy.cancel()
        #expect(await policy.state == .idle)
    }

    @Test("Initial state is idle")
    func initialState() async {
        let policy = ReconnectionPolicy(configuration: .default)
        #expect(await policy.state == .idle)
    }

    @Test("State is waiting after nextDelay")
    func waitingState() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        let state = await policy.state
        if case .waiting(let attempt, _) = state {
            #expect(attempt == 1)
        } else {
            Issue.record("Expected .waiting state, got \(state)")
        }
    }
}

// MARK: - Configuration Presets

@Suite("ReconnectionPolicy — Configuration Presets")
struct ReconnectionPolicyConfigTests {

    @Test("Default configuration values")
    func defaultConfig() {
        let config = ReconnectionPolicy.Configuration.default
        #expect(config.initialDelay == 1.0)
        #expect(config.maxDelay == ReconnectDefaults.defaultMaxDelay)
        #expect(config.maxAttempts == ReconnectDefaults.defaultMaxAttempts)
        #expect(config.backoffMultiplier == 2.0)
        #expect(config.jitterFactor == ReconnectDefaults.defaultJitter)
    }

    @Test("Aggressive configuration values")
    func aggressiveConfig() {
        let config = ReconnectionPolicy.Configuration.aggressive
        #expect(config.initialDelay == 0.5)
        #expect(config.maxDelay == ReconnectDefaults.aggressiveMaxDelay)
        #expect(config.maxAttempts == ReconnectDefaults.aggressiveMaxAttempts)
        #expect(config.backoffMultiplier == 1.5)
    }

    @Test("Custom configuration preserves values")
    func customConfig() {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 3.0,
            maxDelay: 45.0,
            maxAttempts: 7,
            backoffMultiplier: 3.0,
            jitterFactor: 0.1,
            resetThreshold: 120.0
        )
        #expect(config.initialDelay == 3.0)
        #expect(config.maxDelay == 45.0)
        #expect(config.maxAttempts == 7)
        #expect(config.backoffMultiplier == 3.0)
        #expect(config.jitterFactor == 0.1)
        #expect(config.resetThreshold == 120.0)
    }
}

// MARK: - Status Description

@Suite("ReconnectionPolicy — Status Description")
struct ReconnectionPolicyStatusTests {

    @Test("Idle status description")
    func idleStatus() async {
        let policy = ReconnectionPolicy(configuration: .default)
        let desc = await policy.statusDescription
        #expect(desc == "대기 중")
    }

    @Test("Connected status description")
    func connectedStatus() async {
        let policy = ReconnectionPolicy(configuration: .default)
        await policy.markConnected()
        let desc = await policy.statusDescription
        #expect(desc == "연결됨")
    }

    @Test("Exhausted status description")
    func exhaustedStatus() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.1,
            maxAttempts: 1,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        let desc = await policy.statusDescription
        #expect(desc == "재연결 실패")
    }

    @Test("Waiting status description includes attempt info")
    func waitingStatus() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 5.0,
            maxAttempts: 10,
            jitterFactor: 0.0
        )
        let policy = ReconnectionPolicy(configuration: config)
        _ = await policy.nextDelay()
        let desc = await policy.statusDescription
        #expect(desc.contains("1/10"))
        #expect(desc.contains("5"))
    }
}
