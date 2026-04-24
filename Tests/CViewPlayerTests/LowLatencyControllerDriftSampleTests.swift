// MARK: - LowLatencyControllerDriftSampleTests.swift
// processDriftSample(_:) — PDT 기반 정밀 동기화 핵심 분기 테스트
//
// docs/chzzk-browser-sync-latency-research-swift6-2026-04-25.md §5.3 ~ §5.4
// 권장 hysteresis + phase 전이 + snap 동작을 보장하기 위한 회귀 방지 테스트.
//
// 테스트 대상:
// - 밴드 1 (≤200ms)        → tracking lock, rate=1.0
// - 밴드 2 (200~500ms)      → micro-rate, sign 일치
// - 밴드 3 (500~1500ms)     → normal-rate, tracking 보존
// - 밴드 4 (1500~2500ms)    → wide-rate, acquiring 강등
// - 밴드 5 (>2500ms)        → snap → onWebSyncSnap(smoothed) 또는
//                              onSeekRequired(targetLatency) fallback
// - stale / no_pdt          → hold, rate=1.0
// - snap cooldown 8s        → 두번째 snap 차단

import Foundation
import Testing
@testable import CViewPlayer

// MARK: - 캡처 헬퍼

/// 콜백 인자 캡처용 스레드 안전 박스. `SendableBox` (Double?) 와 동일 패턴.
private final class RateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func push(_ v: Double) { lock.withLock { values.append(v) } }
    var last: Double? { lock.withLock { values.last } }
    var count: Int { lock.withLock { values.count } }
}

private final class SnapBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func push(_ v: Double) { lock.withLock { values.append(v) } }
    var last: Double? { lock.withLock { values.last } }
    var count: Int { lock.withLock { values.count } }
}

private final class SeekBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    func push(_ v: TimeInterval) { lock.withLock { values.append(v) } }
    var last: TimeInterval? { lock.withLock { values.last } }
    var count: Int { lock.withLock { values.count } }
}

// MARK: - Drift Sample Tests

@Suite("LowLatencyController — Drift Sample (PDT)")
struct LLCDriftSampleTests {

    // MARK: 밴드 1: ≤200ms — lock

    @Test("밴드 1: |drift|≤200ms 3회 연속 → tracking, rate=1.0")
    func band1_lockToTracking() async {
        let controller = LowLatencyController()
        let rates = RateBox()
        await controller.setOnRateChange { rates.push($0) }

        for _ in 0..<3 {
            await controller.processDriftSample(
                .init(driftMs: 100, isFresh: true, hasPdt: true)
            )
        }

        let phase = await controller.webPhase
        let rate = await controller.currentRate
        #expect(phase == .tracking)
        #expect(rate == 1.0)
        // 한 번도 1.0에서 벗어나지 않았으므로 rate change 콜백은 0회
        #expect(rates.count == 0)
    }

    // MARK: 밴드 2: 200~500ms — micro-rate

    @Test("밴드 2: drift=350ms (양수) → micro-rate 1.0~1.015 사이")
    func band2_microRatePositive() async {
        let controller = LowLatencyController()
        let rates = RateBox()
        await controller.setOnRateChange { rates.push($0) }

        await controller.processDriftSample(
            .init(driftMs: 350, isFresh: true, hasPdt: true)
        )

        let rate = await controller.currentRate
        #expect(rate > 1.0)
        #expect(rate < 1.016)
        // 부호: drift > 0 → 가속 (앱이 웹보다 뒤짐)
        #expect(rates.last != nil)
        #expect(rates.last! > 1.0)
    }

    @Test("밴드 2: drift=-350ms (음수) → 감속")
    func band2_microRateNegative() async {
        let controller = LowLatencyController()

        await controller.processDriftSample(
            .init(driftMs: -350, isFresh: true, hasPdt: true)
        )

        let rate = await controller.currentRate
        #expect(rate < 1.0)
        #expect(rate > 0.985)
    }

    // MARK: 밴드 3: 500~1500ms — normal-rate

    @Test("밴드 3: drift=1000ms → normal-rate ≈ 1.022 (±0.005), 부호=가속")
    func band3_normalRate() async {
        let controller = LowLatencyController()

        await controller.processDriftSample(
            .init(driftMs: 1000, isFresh: true, hasPdt: true)
        )

        let rate = await controller.currentRate
        // 공식: 1.0 + (0.015 + 0.015 * 0.5) = 1.0225 — 단, 버퍼 댐핑 미적용시
        #expect(rate > 1.015)
        #expect(rate < 1.030)
    }

    // MARK: 밴드 4: 1500~2500ms — acquiring + wide-rate

    @Test("밴드 4: drift=2000ms → acquiring + wide-rate, _consecutiveExcellent 리셋")
    func band4_wideRateAcquiring() async {
        let controller = LowLatencyController()

        await controller.processDriftSample(
            .init(driftMs: 2000, isFresh: true, hasPdt: true)
        )

        let phase = await controller.webPhase
        let rate = await controller.currentRate
        #expect(phase == .acquiring)
        #expect(rate > 1.030)
        #expect(rate < 1.061)
    }

    // MARK: 밴드 5: >2500ms — snap

    @Test("밴드 5: drift=3000ms → onWebSyncSnap(smoothed) 호출, phase=.reacquire")
    func band5_snapPrefersWebSyncCallback() async {
        let controller = LowLatencyController()
        let snap = SnapBox()
        let seek = SeekBox()
        await controller.setOnWebSyncSnap({ v in snap.push(v) })
        await controller.setOnSeekRequired { seek.push($0) }

        await controller.processDriftSample(
            .init(driftMs: 3000, isFresh: true, hasPdt: true)
        )

        // 첫 샘플이라 EWMA 없이 raw=3000 그대로
        #expect(snap.count == 1)
        #expect(snap.last == 3000)
        // onWebSyncSnap 등록되었으므로 onSeekRequired 는 호출되지 않음
        #expect(seek.count == 0)

        let phase = await controller.webPhase
        #expect(phase == .reacquire(reason: "snap"))
    }

    @Test("밴드 5 fallback: onWebSyncSnap 미등록 → onSeekRequired(targetLatency) 호출")
    func band5_snapFallbackToSeekRequired() async {
        let controller = LowLatencyController()
        let snap = SnapBox()
        let seek = SeekBox()
        // onWebSyncSnap 미등록 — onSeekRequired 만 등록
        await controller.setOnSeekRequired { seek.push($0) }

        await controller.processDriftSample(
            .init(driftMs: 3000, isFresh: true, hasPdt: true)
        )

        #expect(snap.count == 0)
        #expect(seek.count == 1)
        // fallback 은 targetLatency (default = 3.0s) 로 호출
        #expect(seek.last == 3.0)
    }

    @Test("snap cooldown: 8s 이내 두번째 snap 차단 → wide-rate(acquiring)")
    func snap_cooldownBlocksSecondSnap() async {
        let controller = LowLatencyController()
        let snap = SnapBox()
        await controller.setOnWebSyncSnap({ v in snap.push(v) })

        // 1차 snap
        await controller.processDriftSample(
            .init(driftMs: 3000, isFresh: true, hasPdt: true)
        )
        #expect(snap.count == 1)

        // enterPostSeekGrace() 가 _isPausedForBuffering=true 로 만들어
        // 다음 processDriftSample 가 early-return 되므로, 쿨다운 분기에
        // 도달하기 위해 명시적으로 재개시킨다.
        await controller.resumeFromBuffering()

        // 2차 snap 시도 — 8s 쿨다운 내라 분기에서 차단되고 acquiring 으로
        await controller.processDriftSample(
            .init(driftMs: 3500, isFresh: true, hasPdt: true)
        )
        // 콜백은 더 이상 호출되지 않아야 함
        #expect(snap.count == 1)
        let phase = await controller.webPhase
        #expect(phase == .acquiring)
    }

    // MARK: stale / no_pdt — hold

    @Test("stale 샘플 → phase=.hold(stale), rate=1.0")
    func stale_holdsAtRateOne() async {
        let controller = LowLatencyController()
        let rates = RateBox()
        await controller.setOnRateChange { rates.push($0) }

        // 먼저 정상 샘플로 rate 를 1.0이 아닌 값으로 만든다
        await controller.processDriftSample(
            .init(driftMs: 1000, isFresh: true, hasPdt: true)
        )
        let rateAfterFresh = await controller.currentRate
        #expect(rateAfterFresh > 1.0)

        // stale 주입
        await controller.processDriftSample(
            .init(driftMs: 1500, isFresh: false, hasPdt: true)
        )
        let phase = await controller.webPhase
        let rate = await controller.currentRate
        #expect(phase == .hold(reason: "stale"))
        #expect(rate == 1.0)
    }

    @Test("hasPdt=false → phase=.hold(no_pdt), rate=1.0")
    func noPdt_holdsAtRateOne() async {
        let controller = LowLatencyController()

        await controller.processDriftSample(
            .init(driftMs: 1000, isFresh: true, hasPdt: false)
        )

        let phase = await controller.webPhase
        let rate = await controller.currentRate
        #expect(phase == .hold(reason: "no_pdt"))
        #expect(rate == 1.0)
    }

    // MARK: EWMA 평활

    @Test("EWMA 평활: alternating drift → smoothedDriftMs 가 raw 보다 완만")
    func ewma_smoothing() async {
        let controller = LowLatencyController()

        // acquiring 기본 alpha=0.5
        await controller.processDriftSample(
            .init(driftMs: 1000, isFresh: true, hasPdt: true)
        )
        let s1 = await controller.smoothedDriftMs
        #expect(s1 == 1000)

        await controller.processDriftSample(
            .init(driftMs: 0, isFresh: true, hasPdt: true)
        )
        let s2 = await controller.smoothedDriftMs
        // 0.5 * 0 + 0.5 * 1000 = 500
        #expect(s2 == 500)

        await controller.processDriftSample(
            .init(driftMs: 1000, isFresh: true, hasPdt: true)
        )
        let s3 = await controller.smoothedDriftMs
        // 0.5 * 1000 + 0.5 * 500 = 750
        #expect(s3 == 750)
    }
}
