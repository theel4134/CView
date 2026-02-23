// MARK: - CViewCore/Utilities/EWMACalculator.swift
// 지수 가중 이동 평균 계산기 — HLS.js 알고리즘 포팅

import Foundation

/// EWMA (Exponential Weighted Moving Average) 계산기
/// HLS.js의 검증된 알고리즘을 Swift로 포팅
public struct EWMACalculator: Sendable {
    private let alpha: Double
    private var estimate: Double?
    private var totalWeight: Double = 0

    /// alpha: 평활화 계수 (0~1, 높을수록 최근 값에 민감)
    public init(alpha: Double) {
        precondition(alpha > 0 && alpha <= 1, "Alpha must be in (0, 1]")
        self.alpha = alpha
    }

    /// 새 샘플로 EWMA 업데이트 후 현재 추정값 반환
    public mutating func update(_ value: Double) -> Double {
        if let current = estimate {
            let weight = pow(1 - alpha, totalWeight)
            let newEstimate = value * alpha + current * (1 - alpha)
            totalWeight += 1
            let adjustedEstimate = newEstimate / (1 - weight)
            estimate = newEstimate
            return adjustedEstimate
        } else {
            estimate = value
            totalWeight = 1
            return value
        }
    }

    /// 현재 추정값
    public var current: Double {
        estimate ?? 0
    }

    /// 리셋
    public mutating func reset() {
        estimate = nil
        totalWeight = 0
    }
}

/// 이중 EWMA — 빠른/느린 평활화 동시 계산
public struct DualEWMA: Sendable {
    public var fast: EWMACalculator
    public var slow: EWMACalculator

    public init(fastAlpha: Double = 0.3, slowAlpha: Double = 0.1) {
        self.fast = EWMACalculator(alpha: fastAlpha)
        self.slow = EWMACalculator(alpha: slowAlpha)
    }

    /// 양쪽 모두 업데이트
    public mutating func update(_ value: Double) -> (fast: Double, slow: Double) {
        let fastResult = fast.update(value)
        let slowResult = slow.update(value)
        return (fastResult, slowResult)
    }

    public mutating func reset() {
        fast.reset()
        slow.reset()
    }
}
