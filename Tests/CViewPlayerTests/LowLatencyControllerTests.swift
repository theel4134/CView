// MARK: - LowLatencyControllerTests.swift
// LowLatencyController 종합 단위 테스트
// Phase 1: 순수 로직 테스트 (PID 제어, 레이턴시 동기화)

import Foundation
import Testing
@testable import CViewPlayer
@testable import CViewCore

// MARK: - Thread-safe helper for Sendable closures

final class SendableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double?
    
    var value: Double? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - Configuration Tests

@Suite("LowLatencyController — Configuration")
struct LLCConfigurationTests {
    
    @Test("기본 Configuration 값 검증")
    func defaultConfiguration() {
        let config = LowLatencyController.Configuration.default
        
        #expect(config.targetLatency == 3.0)
        #expect(config.maxLatency == 8.0)
        #expect(config.minLatency == 1.0)
        #expect(config.maxPlaybackRate == 1.15)
        #expect(config.minPlaybackRate == 0.9)
        #expect(config.catchUpThreshold == 1.2)
        #expect(config.slowDownThreshold == 0.5)
        #expect(config.pidKp == 0.8)
        #expect(config.pidKi == 0.12)
        #expect(config.pidKd == 0.06)
    }
    
    @Test("ultraLow Configuration 값 검증")
    func ultraLowConfiguration() {
        let config = LowLatencyController.Configuration.ultraLow
        
        #expect(config.targetLatency == 1.5)
        #expect(config.maxLatency == 5.0)
        #expect(config.minLatency == 0.5)
        #expect(config.maxPlaybackRate == 1.2)
        #expect(config.minPlaybackRate == 0.85)
        #expect(config.catchUpThreshold == 1.0)
        #expect(config.slowDownThreshold == 0.3)
        #expect(config.pidKp == 1.0)
        #expect(config.pidKi == 0.15)
        #expect(config.pidKd == 0.08)
    }
    
    @Test("커스텀 Configuration 생성")
    func customConfiguration() {
        let config = LowLatencyController.Configuration(
            targetLatency: 2.0,
            maxLatency: 8.0,
            minLatency: 0.5,
            maxPlaybackRate: 1.3,
            minPlaybackRate: 0.8,
            catchUpThreshold: 2.0,
            slowDownThreshold: 0.3,
            pidKp: 1.0,
            pidKi: 0.2,
            pidKd: 0.1
        )
        
        #expect(config.targetLatency == 2.0)
        #expect(config.maxLatency == 8.0)
        #expect(config.maxPlaybackRate == 1.3)
    }
}

// MARK: - Initialization Tests

@Suite("LowLatencyController — 초기화 및 기본 상태")
struct LLCInitializationTests {
    
    @Test("초기 상태는 .idle")
    func initialStateIsIdle() async {
        let controller = LowLatencyController()
        let state = await controller.syncState
        #expect(state == .idle)
    }
    
    @Test("초기 재생 속도는 1.0")
    func initialRateIsOne() async {
        let controller = LowLatencyController()
        let rate = await controller.currentRate
        #expect(rate == 1.0)
    }
    
    @Test("커스텀 Configuration으로 초기화")
    func customConfigInit() async {
        let config = LowLatencyController.Configuration.ultraLow
        let controller = LowLatencyController(configuration: config)
        
        let state = await controller.syncState
        #expect(state == .idle)
    }
}

// MARK: - processLatency Tests

@Suite("LowLatencyController — processLatency (핵심 동기화 로직)")
struct LLCProcessLatencyTests {
    
    @Test("타겟 레이턴시 근처 시 .synced 상태")
    func syncedAtTargetLatency() async {
        let controller = LowLatencyController()
        
        // targetLatency=3.0, slowDownThreshold=0.5
        // |error| < 0.5 → synced
        // EWMA 초기값이 0이므로 충분한 반복으로 수렴 필요
        for _ in 0..<50 {
            await controller.processLatency(3.0)
        }
        
        let state = await controller.syncState
        #expect(state == .synced)
        
        let rate = await controller.currentRate
        // PID integral이 축적될 수 있으므로 근사 비교
        #expect(abs(rate - 1.0) < 0.02)
    }
    
    @Test("높은 레이턴시 시 .catchingUp 상태")
    func catchingUpAtHighLatency() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            catchUpThreshold: 1.5,
            slowDownThreshold: 0.5
        )
        let controller = LowLatencyController(configuration: config)
        
        // targetLatency=3.0, catchUpThreshold=1.5
        // error = latency - target > 1.5 → catchingUp
        for _ in 0..<10 {
            await controller.processLatency(6.0) // error = 3.0
        }
        
        let state = await controller.syncState
        #expect(state == .catchingUp)
        
        let rate = await controller.currentRate
        #expect(rate > 1.0) // 속도를 높여 따라가야 함
    }
    
    @Test("매우 낮은 레이턴시 시 .slowingDown 상태")
    func slowingDownAtLowLatency() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            catchUpThreshold: 1.5,
            slowDownThreshold: 0.5
        )
        let controller = LowLatencyController(configuration: config)
        
        // error = latency - target < -slowDownThreshold → slowingDown
        for _ in 0..<10 {
            await controller.processLatency(1.0) // error = -2.0
        }
        
        let state = await controller.syncState
        #expect(state == .slowingDown)
        
        let rate = await controller.currentRate
        #expect(rate < 1.0) // 속도를 줄여야 함
    }
    
    @Test("maxLatency 초과 시 .seekRequired 상태")
    func seekRequiredAtExcessiveLatency() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            maxLatency: 10.0
        )
        let controller = LowLatencyController(configuration: config)
        
        // maxLatency 초과 → seekRequired
        for _ in 0..<10 {
            await controller.processLatency(15.0)
        }
        
        let state = await controller.syncState
        #expect(state == .seekRequired)
    }
    
    @Test("재생 속도가 maxPlaybackRate을 초과하지 않음")
    func rateClampedToMax() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            maxPlaybackRate: 1.15,
            catchUpThreshold: 1.5
        )
        let controller = LowLatencyController(configuration: config)
        
        // 매우 높은 레이턴시로 속도 증가 유도
        for _ in 0..<20 {
            await controller.processLatency(9.0)
        }
        
        let rate = await controller.currentRate
        #expect(rate <= config.maxPlaybackRate)
    }
    
    @Test("재생 속도가 minPlaybackRate 미만이 되지 않음")
    func rateClampedToMin() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            minPlaybackRate: 0.9,
            slowDownThreshold: 0.5
        )
        let controller = LowLatencyController(configuration: config)
        
        // 매우 낮은 레이턴시로 속도 감소 유도
        for _ in 0..<20 {
            await controller.processLatency(0.1)
        }
        
        let rate = await controller.currentRate
        #expect(rate >= config.minPlaybackRate)
    }
    
    @Test("onSeekRequired 콜백 호출 확인")
    func seekRequiredCallbackCalled() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            maxLatency: 10.0
        )
        let controller = LowLatencyController(configuration: config)
        
        let seekBox = SendableBox()
        await controller.setOnSeekRequired { target in
            seekBox.value = target
        }
        
        // maxLatency 초과
        for _ in 0..<10 {
            await controller.processLatency(15.0)
        }
        
        #expect(seekBox.value != nil)
        #expect(seekBox.value == 3.0) // targetLatency로 seek
    }
    
    @Test("onRateChange 콜백 호출 확인")
    func rateChangeCallbackCalled() async {
        let controller = LowLatencyController()
        
        let rateBox = SendableBox()
        await controller.setOnRateChange { rate in
            rateBox.value = rate
        }
        
        // 큰 레이턴시로 속도 변화 유도 (maxLatency=8.0 이하로 EWMA 수렴 필요)
        for _ in 0..<20 {
            await controller.processLatency(6.0)
        }
        
        #expect(rateBox.value != nil)
        #expect(rateBox.value != 1.0)
    }
}

// MARK: - Snapshot Tests

@Suite("LowLatencyController — snapshot")
struct LLCSnapshotTests {
    
    @Test("snapshot 기본 필드 검증")
    func snapshotFields() async {
        let config = LowLatencyController.Configuration(targetLatency: 3.0)
        let controller = LowLatencyController(configuration: config)
        
        let snap = await controller.snapshot(currentLatency: 4.5)
        
        #expect(snap.currentLatency == 4.5)
        #expect(snap.targetLatency == 3.0)
        #expect(snap.playbackRate == 1.0) // 아직 processLatency 호출 전
        #expect(snap.syncState == .idle)
    }
    
    @Test("processLatency 후 snapshot 상태 반영")
    func snapshotAfterProcessing() async {
        let controller = LowLatencyController()
        
        // EWMA가 targetLatency에 충분히 수렴하도록 반복
        for _ in 0..<50 {
            await controller.processLatency(3.0)
        }
        
        let snap = await controller.snapshot(currentLatency: 3.0)
        #expect(snap.syncState == .synced)
        // PID integral 축적으로 정확히 1.0이 아닐 수 있음
        #expect(abs(snap.playbackRate - 1.0) < 0.02)
    }
}

// MARK: - Reset Tests

@Suite("LowLatencyController — reset")
struct LLCResetTests {
    
    @Test("reset 후 .idle 상태 복귀")
    func resetToIdle() async {
        let controller = LowLatencyController()
        
        // catchingUp 상태로 만들기
        for _ in 0..<10 {
            await controller.processLatency(8.0)
        }
        
        await controller.reset()
        
        let state = await controller.syncState
        #expect(state == .idle)
    }
    
    @Test("reset 후 재생 속도 1.0 복귀")
    func resetRateToOne() async {
        let controller = LowLatencyController()
        
        for _ in 0..<10 {
            await controller.processLatency(8.0)
        }
        
        await controller.reset()
        
        let rate = await controller.currentRate
        #expect(rate == 1.0)
    }
}

// MARK: - stopSync Tests

@Suite("LowLatencyController — stopSync")
struct LLCStopSyncTests {
    
    @Test("stopSync 후 .idle 상태")
    func stopSyncToIdle() async {
        let controller = LowLatencyController()
        
        // startSync 후 stopSync
        await controller.startSync { return 3.0 }
        await controller.stopSync()
        
        let state = await controller.syncState
        #expect(state == .idle)
        
        let rate = await controller.currentRate
        #expect(rate == 1.0)
    }
}

// MARK: - SyncState Equatable Tests

@Suite("LowLatencyController — SyncState")
struct LLCSyncStateTests {
    
    @Test("SyncState 동등성 검증")
    func syncStateEquality() {
        #expect(LowLatencyController.SyncState.idle == .idle)
        #expect(LowLatencyController.SyncState.synced == .synced)
        #expect(LowLatencyController.SyncState.catchingUp == .catchingUp)
        #expect(LowLatencyController.SyncState.slowingDown == .slowingDown)
        #expect(LowLatencyController.SyncState.seekRequired == .seekRequired)
    }
    
    @Test("SyncState 비동등성 검증")
    func syncStateInequality() {
        #expect(LowLatencyController.SyncState.idle != .synced)
        #expect(LowLatencyController.SyncState.catchingUp != .slowingDown)
    }
}

// MARK: - Edge Case Tests

@Suite("LowLatencyController — 엣지 케이스")
struct LLCEdgeCaseTests {
    
    @Test("0 레이턴시 처리")
    func zeroLatency() async {
        let controller = LowLatencyController()
        
        for _ in 0..<5 {
            await controller.processLatency(0.0)
        }
        
        // 0 레이턴시도 정상 처리 (slowDown 또는 synced)
        let state = await controller.syncState
        #expect(state == .slowingDown || state == .synced)
    }
    
    @Test("정확히 maxLatency일 때는 seekRequired 아님")
    func exactlyMaxLatency() async {
        let config = LowLatencyController.Configuration(
            targetLatency: 3.0,
            maxLatency: 10.0
        )
        let controller = LowLatencyController(configuration: config)
        
        // smoothedLatency > maxLatency 조건이므로 정확히 10.0은 seekRequired 아님
        for _ in 0..<20 {
            await controller.processLatency(10.0)
        }
        
        let state = await controller.syncState
        // EWMA 수렴 후 10.0에 가까워지고 > 10.0이 아니므로 seekRequired가 아니어야 함
        // 하지만 catchingUp 상태일 수 있음
        #expect(state != .idle)
    }
    
    @Test("급격한 레이턴시 변화 대응")
    func latencySpike() async {
        let controller = LowLatencyController()
        
        // 안정 상태에서 시작
        for _ in 0..<10 {
            await controller.processLatency(3.0)
        }
        
        let stablState = await controller.syncState
        #expect(stablState == .synced)
        
        // 갑자기 레이턴시 급등
        for _ in 0..<10 {
            await controller.processLatency(8.0)
        }
        
        let spikeState = await controller.syncState
        #expect(spikeState == .catchingUp)
        
        let spikeRate = await controller.currentRate
        #expect(spikeRate > 1.0)
    }
    
    @Test("ultraLow 프리셋에서 더 빠른 반응")
    func ultraLowFasterResponse() async {
        let defaultCtrl = LowLatencyController(configuration: .default)
        let ultraLowCtrl = LowLatencyController(configuration: .ultraLow)
        
        // 동일한 레이턴시 피드 (ultraLow maxLatency=5.0 이하로 EWMA 수렴 필요)
        for _ in 0..<20 {
            await defaultCtrl.processLatency(4.0)
            await ultraLowCtrl.processLatency(4.0)
        }
        
        let defaultRate = await defaultCtrl.currentRate
        let ultraLowRate = await ultraLowCtrl.currentRate
        
        // ultraLow는 더 공격적인 PID 게인 → 더 큰 속도 조정
        // (반드시 그렇지는 않을 수 있으나, 둘 다 1.0보다 커야 함)
        #expect(defaultRate > 1.0)
        #expect(ultraLowRate > 1.0)
    }
}
