// MARK: - CViewCore/Utilities/PIDController.swift
// PID 제어기 — 정밀 동기화 엔진 (기존 검증 알고리즘 보존)

import Foundation

/// PID 제어기 — 비례(P), 적분(I), 미분(D) 제어
/// 플레이어-웹 동기화에 사용
public struct PIDController: Sendable {
    public var kp: Double  // 비례 게인
    public var ki: Double  // 적분 게인
    public var kd: Double  // 미분 게인

    private(set) public var integral: Double = 0
    private(set) public var previousError: Double = 0
    private(set) public var lastOutput: Double = 0

    /// 적분항 윈드업 방지 범위
    public var integralClamp: ClosedRange<Double> = -10...10

    /// 출력 제한 범위
    public var outputClamp: ClosedRange<Double>?

    public init(kp: Double = 0.8, ki: Double = 0.1, kd: Double = 0.05) {
        self.kp = kp
        self.ki = ki
        self.kd = kd
    }

    /// 에러 값과 시간 간격으로 제어 출력 계산
    public mutating func update(error: Double, deltaTime: Double) -> Double {
        guard deltaTime > 0 else { return lastOutput }

        // 비례항
        let proportional = kp * error

        // 적분항 (윈드업 방지)
        integral += error * deltaTime
        integral = integral.clamped(to: integralClamp)
        let integralTerm = ki * integral

        // 미분항
        let derivative = (error - previousError) / deltaTime
        let derivativeTerm = kd * derivative

        previousError = error

        var output = proportional + integralTerm + derivativeTerm

        // 출력 클램핑
        if let clamp = outputClamp {
            output = output.clamped(to: clamp)
        }

        lastOutput = output
        return output
    }

    /// 상태 리셋
    public mutating func reset() {
        integral = 0
        previousError = 0
        lastOutput = 0
    }

    // MARK: - 프리셋

    /// 정밀 동기화 프리셋 (±0.05초 정밀도)
    public static let ultraPrecise = PIDController(kp: 1.0, ki: 0.15, kd: 0.08)

    /// 표준 동기화 프리셋 (±0.3초 정밀도)
    public static let standard = PIDController(kp: 0.8, ki: 0.1, kd: 0.05)

    /// 완화된 동기화 프리셋 (±0.5초 정밀도)
    public static let relaxed = PIDController(kp: 0.5, ki: 0.05, kd: 0.02)
}

// MARK: - Comparable clamped extension

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
