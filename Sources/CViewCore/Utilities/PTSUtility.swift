// MARK: - PTSUtility.swift
// CViewCore — MPEG-2 PTS (Presentation Time Stamp) 유틸리티
//
// flashls PTS.as 및 Level.updateFragment() 참조:
// - 33비트 PTS 래핑 정규화 (약 26.5시간 주기)
// - 세그먼트 간 PTS 연속성 보장
// - 타임스탬프 드리프트 보정

import Foundation

/// MPEG-2 PTS 유틸리티
/// PTS는 33비트(90kHz 클럭)로, ms 변환 후 약 26.5시간(95,443,717ms)에서 래핑됩니다.
public enum PTSUtility {

    // MARK: - Constants

    /// 33비트 PTS의 밀리초 값 전체 범위 (2^33 / 90)
    /// flashls: 95,443,717ms ≈ 26.5시간
    public static let ptsWrapMs: Double = 95_443_717.0

    /// PTS 래핑 판정 임계값 (전체 범위의 절반)
    /// flashls: 47,721,858ms ≈ 13.3시간
    public static let ptsWrapThresholdMs: Double = 47_721_858.0

    // MARK: - Normalization

    /// PTS 정규화: 두 값의 차이가 래핑 임계값을 초과하면 보정
    ///
    /// flashls PTS.normalize(reference, value):
    /// |value - reference| > 47,721,858ms 이면 ±95,443,717을 가산하여
    /// reference에 가장 가까운 값으로 정규화합니다.
    ///
    /// - Parameters:
    ///   - reference: 기준 PTS (ms)
    ///   - value: 정규화할 PTS (ms)
    /// - Returns: reference에 가장 가까운 정규화된 PTS (ms)
    public static func normalize(reference: Double, value: Double) -> Double {
        var result = value
        while abs(result - reference) > ptsWrapThresholdMs {
            if result > reference {
                result -= ptsWrapMs
            } else {
                result += ptsWrapMs
            }
        }
        return result
    }

    // MARK: - Duration Calculation

    /// 두 PTS 값 사이의 duration 계산 (래핑 안전)
    ///
    /// - Parameters:
    ///   - startPts: 시작 PTS (ms)
    ///   - endPts: 끝 PTS (ms)
    /// - Returns: duration (초)
    public static func duration(from startPts: Double, to endPts: Double) -> TimeInterval {
        let normalized = normalize(reference: startPts, value: endPts)
        return (normalized - startPts) / 1000.0
    }

    // MARK: - 90kHz ↔ ms Conversion

    /// 90kHz 타임스탬프 → 밀리초 변환
    /// flashls: Math.round(_pts / 90)
    public static func toMilliseconds(_ pts90kHz: Int64) -> Double {
        return Double(pts90kHz) / 90.0
    }

    /// 밀리초 → 90kHz 타임스탬프 변환
    public static func to90kHz(_ ms: Double) -> Int64 {
        return Int64(ms * 90.0)
    }

    // MARK: - Segment PTS Propagation

    /// 세그먼트 배열에서 PTS 양방향 전파 (flashls Level.updateFragment 포팅)
    ///
    /// 하나의 세그먼트에서 실측한 PTS 값을 인접 세그먼트들에 전파하여
    /// manifest의 #EXTINF duration과 실제 PTS 간의 드리프트를 자동 보정합니다.
    ///
    /// - Parameters:
    ///   - segments: 세그먼트 배열 (mutable: ptsStart가 업데이트됨)
    ///   - anchorIndex: 실측 PTS가 있는 기준 세그먼트 인덱스
    ///   - anchorPtsMs: 기준 세그먼트의 실측 시작 PTS (ms)
    ///   - anchorEndPtsMs: 기준 세그먼트의 실측 끝 PTS (ms)
    /// - Returns: 각 세그먼트의 보정된 시작 시간 (초) 배열
    public static func propagatePTS(
        segmentDurations: [TimeInterval],
        anchorIndex: Int,
        anchorPtsMs: Double,
        anchorEndPtsMs: Double
    ) -> [TimeInterval] {
        guard !segmentDurations.isEmpty,
              anchorIndex >= 0,
              anchorIndex < segmentDurations.count else {
            return segmentDurations.isEmpty ? [] : cumulativeStartTimes(segmentDurations)
        }

        var ptsStarts = [Double](repeating: 0, count: segmentDurations.count)
        ptsStarts[anchorIndex] = anchorPtsMs

        // 역방향 전파: anchorIndex → 0
        for i in stride(from: anchorIndex - 1, through: 0, by: -1) {
            ptsStarts[i] = ptsStarts[i + 1] - segmentDurations[i + 1] * 1000.0
        }

        // 순방향 전파: anchorIndex → end
        for i in (anchorIndex + 1)..<segmentDurations.count {
            ptsStarts[i] = ptsStarts[i - 1] + segmentDurations[i - 1] * 1000.0
        }

        // ms → 초 변환하여 start_time 계산
        let baseMs = ptsStarts[0]
        return ptsStarts.map { ($0 - baseMs) / 1000.0 }
    }

    // MARK: - Helpers

    /// duration 배열의 누적 합으로 시작 시간 배열 생성
    private static func cumulativeStartTimes(_ durations: [TimeInterval]) -> [TimeInterval] {
        var result = [TimeInterval](repeating: 0, count: durations.count)
        for i in 1..<durations.count {
            result[i] = result[i - 1] + durations[i - 1]
        }
        return result
    }
}
