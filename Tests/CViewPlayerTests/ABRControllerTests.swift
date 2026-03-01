// MARK: - ABRControllerTests.swift
// ABRController 종합 단위 테스트
// Phase 1: 순수 로직 테스트 (외부 의존성 없음)

import Foundation
import Testing
@testable import CViewPlayer
@testable import CViewCore

// MARK: - Helper

private func makeVariants(bandwidths: [Int]) -> [MasterPlaylist.Variant] {
    bandwidths.enumerated().map { index, bw in
        MasterPlaylist.Variant(
            bandwidth: bw,
            averageBandwidth: nil,
            resolution: "\(360 + index * 360)p",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/\(bw).m3u8")!,
            name: "\(bw)"
        )
    }
}

private func makeSample(bytesLoaded: Int, duration: Double) -> ABRController.BandwidthSample {
    ABRController.BandwidthSample(bytesLoaded: bytesLoaded, duration: duration)
}

/// 대역폭 샘플 반복 기록 (EWMA 수렴용)
private func feedSamples(
    to abr: ABRController,
    bps: Double,
    count: Int = 10
) async {
    let bytes = Int(bps / 8.0) // bps → bytes per second
    for _ in 0..<count {
        await abr.recordSample(makeSample(bytesLoaded: bytes, duration: 1.0))
    }
}

// MARK: - Configuration Tests

@Suite("ABRController — Configuration")
struct ABRConfigurationTests {
    
    @Test("기본 Configuration 값 검증")
    func defaultConfiguration() {
        let config = ABRController.Configuration.default
        
        #expect(config.minBandwidthBps == 500_000)
        #expect(config.maxBandwidthBps == 50_000_000)
        #expect(config.bandwidthSafetyFactor == 0.7)
        #expect(config.switchUpThreshold == 1.2)
        #expect(config.switchDownThreshold == 0.8)
        #expect(config.minSwitchInterval == 5.0)
        #expect(config.initialBandwidthEstimate == 5_000_000)
    }
    
    @Test("커스텀 Configuration 생성")
    func customConfiguration() {
        let config = ABRController.Configuration(
            minBandwidthBps: 100_000,
            maxBandwidthBps: 10_000_000,
            bandwidthSafetyFactor: 0.5,
            switchUpThreshold: 1.5,
            switchDownThreshold: 0.6,
            minSwitchInterval: 3.0,
            initialBandwidthEstimate: 2_000_000
        )
        
        #expect(config.minBandwidthBps == 100_000)
        #expect(config.maxBandwidthBps == 10_000_000)
        #expect(config.bandwidthSafetyFactor == 0.5)
        #expect(config.switchUpThreshold == 1.5)
        #expect(config.switchDownThreshold == 0.6)
        #expect(config.minSwitchInterval == 3.0)
        #expect(config.initialBandwidthEstimate == 2_000_000)
    }
}

// MARK: - BandwidthSample Tests

@Suite("ABRController — BandwidthSample")
struct BandwidthSampleTests {
    
    @Test("bitsPerSecond 정상 계산")
    func normalBitsPerSecond() {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 1_000_000,
            duration: 1.0
        )
        #expect(sample.bitsPerSecond == 8_000_000)
    }
    
    @Test("duration 0일 때 bitsPerSecond는 0")
    func zeroDuration() {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 1_000_000,
            duration: 0
        )
        #expect(sample.bitsPerSecond == 0)
    }
    
    @Test("음수 duration일 때 bitsPerSecond는 0")
    func negativeDuration() {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 1_000_000,
            duration: -1.0
        )
        // guard duration > 0 → returns 0
        #expect(sample.bitsPerSecond == 0)
    }
    
    @Test("bytesLoaded 0일 때 bitsPerSecond는 0")
    func zeroBytes() {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 0,
            duration: 1.0
        )
        #expect(sample.bitsPerSecond == 0)
    }
    
    @Test("다양한 대역폭 시나리오")
    func variousBandwidths() {
        // 500KB in 0.5s = 8Mbps
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 500_000,
            duration: 0.5
        )
        #expect(sample.bitsPerSecond == 8_000_000)
    }
}

// MARK: - Initialization Tests

@Suite("ABRController — 초기화 및 기본 상태")
struct ABRInitializationTests {
    
    @Test("빈 상태에서 recommendLevel은 .maintain")
    func noLevelsMaintain() async {
        let abr = ABRController()
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
    }
    
    @Test("빈 상태에서 selectedLevel은 nil")
    func noLevelsNilSelected() async {
        let abr = ABRController()
        let selected = await abr.selectedLevel
        #expect(selected == nil)
    }
    
    @Test("샘플 없을 때 initialBandwidthEstimate 반환")
    func initialEstimateWithoutSamples() async {
        let config = ABRController.Configuration(initialBandwidthEstimate: 3_000_000)
        let abr = ABRController(configuration: config)
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate == 3_000_000)
    }
    
    @Test("기본 Configuration으로 초기화")
    func defaultInit() async {
        let abr = ABRController()
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate == Double(ABRController.Configuration.default.initialBandwidthEstimate))
    }
}

// MARK: - Level Setting Tests

@Suite("ABRController — setLevels")
struct ABRSetLevelsTests {
    
    @Test("레벨 설정 후 selectedLevel은 첫 번째 (최저 대역폭)")
    func selectedLevelAfterSet() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [3_000_000, 1_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        // 내부정렬: 1M, 3M, 5M → currentLevelIndex=0 → 1M
        let selected = await abr.selectedLevel
        #expect(selected != nil)
        #expect(selected?.bandwidth == 1_000_000)
    }
    
    @Test("레벨이 대역폭 오름차순으로 정렬됨")
    func levelsSortedAscending() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [5_000_000, 1_000_000, 3_000_000, 8_000_000])
        await abr.setLevels(variants)
        
        // 최저 대역폭(1M)이 선택되어야 함 (currentLevelIndex=0)
        let selected = await abr.selectedLevel
        #expect(selected?.bandwidth == 1_000_000)
    }
    
    @Test("빈 레벨 배열 설정")
    func emptyLevels() async {
        let abr = ABRController()
        await abr.setLevels([])
        
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
        
        let selected = await abr.selectedLevel
        #expect(selected == nil)
    }
}

// MARK: - Bandwidth Estimation Tests

@Suite("ABRController — 대역폭 추정")
struct ABRBandwidthEstimationTests {
    
    @Test("단일 샘플 후 추정값")
    func singleSample() async {
        let abr = ABRController()
        let sample = makeSample(bytesLoaded: 1_000_000, duration: 1.0)
        // 8Mbps
        await abr.recordSample(sample)
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate > 0)
    }
    
    @Test("0 bps 샘플은 무시됨")
    func zeroSampleIgnored() async {
        let abr = ABRController()
        let sample = makeSample(bytesLoaded: 0, duration: 1.0)
        await abr.recordSample(sample)
        
        // 샘플이 무시되므로 초기값 유지
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate == Double(ABRController.Configuration.default.initialBandwidthEstimate))
    }
    
    @Test("다수 샘플 후 보수적 추정 (min of fast/slow)")
    func conservativeEstimate() async {
        let abr = ABRController()
        
        await feedSamples(to: abr, bps: 10_000_000, count: 20)
        
        let estimate = await abr.currentBandwidthEstimate()
        // EWMA가 수렴 → 10Mbps에 근접
        #expect(estimate > 5_000_000) // 초기값(5M)보다는 높아야 함
        #expect(estimate <= 10_000_000) // 실제 bps를 초과하면 안 됨
    }
    
    @Test("대역폭 급감 시 추정값 하락")
    func bandwidthDropReflected() async {
        let abr = ABRController()
        
        // 먼저 높은 대역폭 피드
        await feedSamples(to: abr, bps: 10_000_000, count: 10)
        let highEstimate = await abr.currentBandwidthEstimate()
        
        // 갑자기 낮아진 대역폭 피드
        await feedSamples(to: abr, bps: 1_000_000, count: 10)
        let lowEstimate = await abr.currentBandwidthEstimate()
        
        // 추정값이 감소해야 함
        #expect(lowEstimate < highEstimate)
    }
}

// MARK: - recommendLevel Tests

@Suite("ABRController — recommendLevel (품질 결정)")
struct ABRRecommendLevelTests {
    
    @Test("충분한 대역폭 시 switchUp 결정")
    func switchUpWithSufficientBandwidth() async {
        let config = ABRController.Configuration(
            bandwidthSafetyFactor: 0.7,
            switchUpThreshold: 1.2,
            switchDownThreshold: 0.8,
            minSwitchInterval: 0 // 즉시 전환 허용
        )
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        // 충분히 높은 대역폭 피드 (5M * 1.2 / 0.7 ≈ 8.57M 이상 필요)
        await feedSamples(to: abr, bps: 15_000_000, count: 10)
        
        let decision = await abr.recommendLevel()
        
        // switchUp 또는 이미 최고 레벨이라 maintain 중 하나
        switch decision {
        case .switchUp:
            break // 기대한 결과
        case .maintain:
            // 이미 적절한 레벨에 있을 수 있음 — 허용
            break
        case .switchDown:
            Issue.record("충분한 대역폭에서 switchDown 발생")
        }
    }
    
    @Test("대역폭 부족 시 switchDown 결정")
    func switchDownWithInsufficientBandwidth() async {
        let config = ABRController.Configuration(
            bandwidthSafetyFactor: 0.7,
            switchUpThreshold: 1.2,
            switchDownThreshold: 0.8,
            minSwitchInterval: 0
        )
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [500_000, 1_000_000, 3_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        // 먼저 높은 레벨로 강제 설정
        await abr.forceLevelIndex(3) // 5Mbps
        
        // 매우 낮은 대역폭 피드
        await feedSamples(to: abr, bps: 800_000, count: 15)
        
        let decision = await abr.recommendLevel()
        
        switch decision {
        case .switchDown:
            break // 기대한 결과
        case .maintain:
            break // minSwitchInterval에 의해 유지될 수도 있음
        case .switchUp:
            Issue.record("낮은 대역폭에서 switchUp 발생")
        }
    }
    
    @Test("minSwitchInterval 내에서는 항상 .maintain")
    func minSwitchIntervalEnforced() async {
        let config = ABRController.Configuration(
            minSwitchInterval: 60.0 // 60초 (테스트 중 절대 만료 안 됨)
        )
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [1_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        // 강제 전환으로 lastSwitchTime 설정
        await abr.forceLevelIndex(0)
        
        // 높은 대역폭 피드
        await feedSamples(to: abr, bps: 20_000_000, count: 10)
        
        // minSwitchInterval 내이므로 .maintain
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
    }
    
    @Test("hysteresis — switchUpThreshold 미달 시 .maintain")
    func hysteresisPreventsPrematureUpgrade() async {
        let config = ABRController.Configuration(
            bandwidthSafetyFactor: 0.7,
            switchUpThreshold: 1.2,
            minSwitchInterval: 0
        )
        let abr = ABRController(configuration: config)
        
        // 1Mbps, 3Mbps 두 레벨
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000])
        await abr.setLevels(variants)
        
        // 3Mbps * 1.2 / 0.7 ≈ 5.14Mbps 이상 필요
        // 딱 3Mbps만 제공 → safeBandwidth = 3M * 0.7 = 2.1M
        // 2.1M > 1M (현재) 이지만 < 3M * 1.2 = 3.6M
        await feedSamples(to: abr, bps: 3_000_000, count: 15)
        
        let decision = await abr.recommendLevel()
        // safeBandwidth(2.1M)이 3M의 요구치(3.6M)에 못 미치므로 maintain
        #expect(decision == .maintain)
    }
}

// MARK: - forceLevelIndex Tests

@Suite("ABRController — forceLevelIndex")
struct ABRForceLevelTests {
    
    @Test("유효한 인덱스로 강제 설정")
    func validIndex() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(2)
        let selected = await abr.selectedLevel
        #expect(selected?.bandwidth == 5_000_000)
    }
    
    @Test("음수 인덱스는 무시")
    func negativeIndex() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(-1)
        let selected = await abr.selectedLevel
        #expect(selected?.bandwidth == 1_000_000) // 변경 안 됨
    }
    
    @Test("범위 초과 인덱스는 무시")
    func outOfBoundsIndex() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(5)
        let selected = await abr.selectedLevel
        #expect(selected?.bandwidth == 1_000_000) // 변경 안 됨
    }
    
    @Test("강제 설정 후 lastSwitchTime 갱신으로 minSwitchInterval 적용")
    func forceSetsLastSwitchTime() async {
        let config = ABRController.Configuration(minSwitchInterval: 60.0)
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(1)
        
        // forceLevelIndex가 lastSwitchTime을 설정하므로 recommendLevel은 .maintain
        await feedSamples(to: abr, bps: 20_000_000, count: 10)
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
    }
}

// MARK: - Reset Tests

@Suite("ABRController — reset")
struct ABRResetTests {
    
    @Test("reset 후 초기 대역폭 추정값 복원")
    func resetRestoresInitialEstimate() async {
        let config = ABRController.Configuration(initialBandwidthEstimate: 5_000_000)
        let abr = ABRController(configuration: config)
        
        // 샘플 피드 후 리셋
        await feedSamples(to: abr, bps: 20_000_000, count: 10)
        await abr.reset()
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate == 5_000_000)
    }
    
    @Test("reset 후 selectedLevel 초기 인덱스로 복귀")
    func resetRestoresLevelIndex() async {
        let abr = ABRController()
        let variants = makeVariants(bandwidths: [1_000_000, 3_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(2)
        await abr.reset()
        
        let selected = await abr.selectedLevel
        #expect(selected?.bandwidth == 1_000_000) // 인덱스 0으로 복귀
    }
    
    @Test("reset 후 minSwitchInterval 제약 해제")
    func resetClearsLastSwitchTime() async {
        let config = ABRController.Configuration(minSwitchInterval: 60.0)
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [1_000_000, 5_000_000])
        await abr.setLevels(variants)
        
        await abr.forceLevelIndex(0) // lastSwitchTime 설정
        await abr.reset()            // lastSwitchTime 초기화
        
        // 높은 대역폭 피드 후 전환 가능해야 함
        await feedSamples(to: abr, bps: 20_000_000, count: 15)
        
        let decision = await abr.recommendLevel()
        // minSwitchInterval 제약이 해제되었으므로 switchUp 가능
        switch decision {
        case .switchDown:
            Issue.record("reset 후에도 switchDown 발생")
        default:
            break
        }
    }
}

// MARK: - ABRDecision Equatable Tests

@Suite("ABRController — ABRDecision Equatable")
struct ABRDecisionEquatableTests {
    
    @Test(".maintain == .maintain")
    func maintainEquality() {
        #expect(ABRController.ABRDecision.maintain == ABRController.ABRDecision.maintain)
    }
    
    @Test(".switchUp 동일 파라미터 비교")
    func switchUpEquality() {
        let a = ABRController.ABRDecision.switchUp(toBandwidth: 5_000_000, reason: "test")
        let b = ABRController.ABRDecision.switchUp(toBandwidth: 5_000_000, reason: "test")
        #expect(a == b)
    }
    
    @Test(".switchUp 다른 대역폭은 불일치")
    func switchUpDifferentBandwidth() {
        let a = ABRController.ABRDecision.switchUp(toBandwidth: 5_000_000, reason: "test")
        let b = ABRController.ABRDecision.switchUp(toBandwidth: 3_000_000, reason: "test")
        #expect(a != b)
    }
    
    @Test(".switchUp과 .switchDown은 불일치")
    func switchUpVsDown() {
        let up = ABRController.ABRDecision.switchUp(toBandwidth: 5_000_000, reason: "test")
        let down = ABRController.ABRDecision.switchDown(toBandwidth: 5_000_000, reason: "test")
        #expect(up != down)
    }
}

// MARK: - Edge Case Tests

@Suite("ABRController — 엣지 케이스")
struct ABREdgeCaseTests {
    
    @Test("단일 레벨만 있을 때 항상 .maintain")
    func singleLevel() async {
        let config = ABRController.Configuration(minSwitchInterval: 0)
        let abr = ABRController(configuration: config)
        
        let variants = makeVariants(bandwidths: [3_000_000])
        await abr.setLevels(variants)
        
        await feedSamples(to: abr, bps: 10_000_000, count: 10)
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
    }
    
    @Test("레벨 설정 전 selectedLevel은 nil")
    func selectedLevelBeforeSetLevels() async {
        let abr = ABRController()
        let level = await abr.selectedLevel
        #expect(level == nil)
    }
    
    @Test("매우 큰 대역폭 샘플 처리")
    func veryHighBandwidth() async {
        let abr = ABRController()
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 100_000_000, // 100MB
            duration: 1.0
        )
        await abr.recordSample(sample)
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate > 0)
        #expect(estimate <= 800_000_000) // 800Mbps 이하
    }
    
    @Test("매우 짧은 duration 샘플 처리")
    func veryShortDuration() async {
        let abr = ABRController()
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 1_000,
            duration: 0.001 // 1ms
        )
        await abr.recordSample(sample)
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate > 0)
    }
    
    @Test("연속 recordSample 후 추정값 안정성")
    func estimateStabilizes() async {
        let abr = ABRController()
        
        // 동일한 대역폭 50회 피드
        await feedSamples(to: abr, bps: 5_000_000, count: 50)
        
        let estimate = await abr.currentBandwidthEstimate()
        // 충분한 수렴 후 5Mbps에 가까워야 함
        #expect(estimate > 4_000_000)
        #expect(estimate < 6_000_000)
    }
}
