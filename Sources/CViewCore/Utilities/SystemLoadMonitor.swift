// MARK: - CViewCore/Utilities/SystemLoadMonitor.swift
// CPU/열 부하에 따라 동적 throttle 정책을 제공하는 경량 유틸.
//
// 목적:
//   - macOS thermalState (nominal/fair/serious/critical) + lowPowerMode를 단일 진입점에서 평가
//   - 디코더 스레드 수, 채팅 배치 flush 간격 등을 동적으로 조정할 때 사용
//   - ProcessInfo.processInfo.thermalStateDidChangeNotification은 시스템에서 자동 발생 → 비용 0
//
// 사용 예:
//   let mode = SystemLoadMonitor.shared.currentMode
//   let threads = mode.adjustedDecoderThreads(base: 6)
//   let flushNs = mode.adjustedChatFlushIntervalNs(base: 33_000_000)

import Foundation

/// 시스템 부하 모드 — thermalState + lowPowerMode를 단일 enum으로 추상화.
public enum SystemLoadMode: Int, Sendable, Comparable {
    case normal = 0       // nominal/fair, 정상 동작
    case warm = 1         // serious, 부하 감소 권고
    case hot = 2          // critical, 강한 throttle 필요

    public static func < (lhs: SystemLoadMode, rhs: SystemLoadMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 디코더 스레드 수 가이드 — base 값을 부하에 따라 줄임.
    /// 예: base=6 → normal=6, warm=4, hot=2
    public func adjustedDecoderThreads(base: Int) -> Int {
        switch self {
        case .normal: return base
        case .warm:   return max(2, base * 2 / 3)
        case .hot:    return max(1, base / 3)
        }
    }

    /// 채팅 배치 flush 간격 — 부하가 높을수록 간격 증가로 SwiftUI 업데이트 빈도 감소.
    /// 예: base=33ms → normal=33, warm=66, hot=120
    public func adjustedChatFlushIntervalNs(base: UInt64) -> UInt64 {
        switch self {
        case .normal: return base
        case .warm:   return base * 2
        case .hot:    return base * 4
        }
    }
}

/// 시스템 부하 상태 모니터 — process-wide 싱글톤.
/// thermalState는 OS 알림을 통해 자동 갱신되므로 폴링 비용 없음.
public final class SystemLoadMonitor: @unchecked Sendable {

    public static let shared = SystemLoadMonitor()

    private init() {
        // 변경 시 캐시 무효화만 수행 — 실제 평가는 currentMode 프로퍼티 호출 시점.
        // (옵저버 보관 불필요: process 종료까지 유지)
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in /* no-op: lazy 평가 */ }
    }

    /// 현재 시스템 부하 모드 — thermalState 우선, lowPowerMode 보강.
    public var currentMode: SystemLoadMode {
        let state = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        switch state {
        case .critical:
            return .hot
        case .serious:
            return .hot
        case .fair:
            return lowPower ? .warm : .normal
        case .nominal:
            return lowPower ? .warm : .normal
        @unknown default:
            return .normal
        }
    }

    /// 활성 코어 수 — Apple Silicon에서는 P+E 코어 합산.
    /// VLC `:avcodec-threads=` 등에 사용. 통상 4~12 범위.
    public var activeProcessorCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }
}
