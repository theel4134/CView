// MARK: - CViewCoreTests.swift
// CViewCore module tests

import Testing
import Foundation
@testable import CViewCore

// MARK: - EWMA Calculator Tests

@Suite("EWMA Calculator")
struct EWMACalculatorTests {
    
    @Test("Initial state is zero")
    func initialState() {
        let ewma = EWMACalculator(alpha: 0.5)
        #expect(ewma.current == 0)
    }
    
    @Test("Single sample returns that value")
    func singleSample() {
        var ewma = EWMACalculator(alpha: 0.5)
        let result = ewma.update(100.0)
        #expect(result == 100.0)
    }
    
    @Test("EWMA converges to stable value")
    func convergence() {
        var ewma = EWMACalculator(alpha: 0.5)
        
        var value = 0.0
        for _ in 0..<100 {
            value = ewma.update(50.0)
        }
        
        #expect(abs(value - 50.0) < 1.0)
    }
    
    @Test("Higher alpha responds faster to changes")
    func alphaResponse() {
        var fastEWMA = EWMACalculator(alpha: 0.9)
        var slowEWMA = EWMACalculator(alpha: 0.1)
        
        // Establish baseline
        for _ in 0..<10 {
            _ = fastEWMA.update(100.0)
            _ = slowEWMA.update(100.0)
        }
        
        // Apply sudden change
        let fastResponse = fastEWMA.update(200.0)
        let slowResponse = slowEWMA.update(200.0)
        
        // Fast EWMA should be closer to 200
        #expect(fastResponse > slowResponse)
    }
    
    @Test("Reset clears all state")
    func reset() {
        var ewma = EWMACalculator(alpha: 0.5)
        _ = ewma.update(100.0)
        ewma.reset()
        #expect(ewma.current == 0)
    }
}

// MARK: - PID Controller Tests

@Suite("PID Controller")
struct PIDControllerTests {
    
    @Test("Zero error produces zero output")
    func zeroError() {
        var pid = PIDController()
        let output = pid.update(error: 0, deltaTime: 0.1)
        #expect(output == 0)
    }
    
    @Test("Positive error produces positive output")
    func positiveError() {
        var pid = PIDController()
        let output = pid.update(error: 5.0, deltaTime: 0.1)
        #expect(output > 0)
    }
    
    @Test("Negative error produces negative output")
    func negativeError() {
        var pid = PIDController()
        let output = pid.update(error: -5.0, deltaTime: 0.1)
        #expect(output < 0)
    }
    
    @Test("Proportional component scales with Kp")
    func proportional() {
        var pid = PIDController(kp: 2.0, ki: 0, kd: 0)
        let output = pid.update(error: 3.0, deltaTime: 0.1)
        #expect(abs(output - 6.0) < 0.001)
    }
    
    @Test("Integral accumulates over time")
    func integral() {
        var pid = PIDController(kp: 0, ki: 1.0, kd: 0)
        
        _ = pid.update(error: 1.0, deltaTime: 1.0) // integral = 1.0
        let output = pid.update(error: 1.0, deltaTime: 1.0) // integral = 2.0
        
        #expect(output > 1.0)
    }
    
    @Test("Derivative responds to error change")
    func derivative() {
        var pid = PIDController(kp: 0, ki: 0, kd: 1.0)
        
        _ = pid.update(error: 0.0, deltaTime: 1.0)
        let output = pid.update(error: 5.0, deltaTime: 1.0)
        
        #expect(output > 0)
    }
    
    @Test("Reset clears accumulated state")
    func reset() {
        var pid = PIDController()
        _ = pid.update(error: 5.0, deltaTime: 0.1)
        _ = pid.update(error: 5.0, deltaTime: 0.1)
        
        pid.reset()
        
        let output = pid.update(error: 0.0, deltaTime: 0.1)
        #expect(output == 0)
    }
}

// MARK: - ServiceContainer Tests

@Suite("ServiceContainer")
struct ServiceContainerTests {
    
    @Test("Register and resolve service")
    func registerResolve() async throws {
        let container = ServiceContainer.shared
        await container.reset()
        
        let testValue = "test-service"
        await container.register(String.self, instance: testValue)
        
        let resolved: String? = await container.resolve(String.self)
        #expect(resolved == testValue)
    }
    
    @Test("Resolve unregistered returns nil")
    func resolveUnregistered() async {
        let container = ServiceContainer.shared
        await container.reset()
        let resolved: Int? = await container.resolve(Int.self)
        #expect(resolved == nil)
    }
    
    @Test("Override existing registration")
    func override() async {
        let container = ServiceContainer.shared
        await container.reset()
        
        await container.register(String.self, instance: "first")
        await container.register(String.self, instance: "second")
        
        let resolved: String? = await container.resolve(String.self)
        #expect(resolved == "second")
    }
}

// MARK: - AppError Tests

@Suite("AppError")
struct AppErrorTests {
    
    @Test("Network error descriptions are in Korean")
    func networkErrors() {
        let error = AppError.network(.timeout)
        #expect(!error.localizedDescription.isEmpty)
    }
    
    @Test("API errors include status code")
    func apiError() {
        let error = AppError.api(.httpError(statusCode: 404))
        let desc = error.localizedDescription
        #expect(desc.contains("404"))
    }
    
    @Test("Network invalidURL error includes URL string")
    func invalidURLError() {
        let error = AppError.network(.invalidURL("test"))
        let desc = error.localizedDescription
        #expect(desc.contains("test"))
    }
}

// MARK: - AsyncTimerSequence Tests

@Suite("AsyncTimerSequence")
struct AsyncTimerTests {
    
    @Test("Timer fires at least once within interval")
    func timerFires() async throws {
        let timer = AsyncTimerSequence(interval: 0.1)
        var count = 0
        
        for await _ in timer {
            count += 1
            if count >= 3 { break }
        }
        
        #expect(count == 3)
    }
}
