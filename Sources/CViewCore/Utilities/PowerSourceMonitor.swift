// MARK: - PowerSourceMonitor.swift
// CViewCore — 전원 연결(AC) / 배터리 상태 감지 + 변경 알림
//
// 목적: 전원 연결 시 P-core(고성능 코어) 우선, 배터리 시 E-core(효율 코어) 우선으로
//      백그라운드/주기적 Task의 QoS를 동적 조절하여 배터리 수명 보호 + AC에서는 응답성 극대화.
//
// macOS QoS → 코어 어피니티 (Apple Silicon):
//   .userInteractive / .userInitiated → P-core 강하게 선호 (스로틀 거의 없음)
//   .default                          → P-core 우선 (시스템 부하 따라 가변)
//   .utility                          → E-core 우선 (Sustained 워크로드)
//   .background                       → E-core 강하게 선호 + thermal/power 스로틀
//
// 전원 상태는 IOKit `IOPSGetProvidingPowerSourceType` + RunLoop 노티피케이션으로 감시.
// `isLowPowerModeEnabled` 도 함께 고려하여 절전 모드에서는 AC라도 효율 우선.

import Foundation
import IOKit.ps

// MARK: - Power Source

public enum CViewPowerSource: String, Sendable {
    case ac      // 전원 연결됨 (어댑터 또는 외부 전원)
    case battery // 배터리 사용 중
    case unknown // 판별 불가 (초기화 직후 등)
}

// MARK: - Notifications

public extension Notification.Name {
    /// 전원 상태(AC↔Battery) 또는 LowPowerMode 변경 시 발화
    static let cviewPowerSourceChanged = Notification.Name("cviewPowerSourceChanged")
}

// MARK: - Monitor

/// 시스템 전원 소스(AC/Battery)를 감시하고 변경을 알리는 싱글톤.
/// 메인 RunLoop 에 IOPSNotification 콜백을 부착하여 실시간 갱신.
public final class PowerSourceMonitor: @unchecked Sendable {

    public static let shared = PowerSourceMonitor()

    private let lock = NSLock()
    private var _current: CViewPowerSource = .unknown
    private var runLoopSource: CFRunLoopSource?

    /// 현재 전원 소스 — 항상 즉시 반환(IOKit 호출 X, 캐시된 값)
    public var current: CViewPowerSource {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    /// 고성능 모드 선호 여부 — AC 연결 + LowPowerMode 비활성 시에만 true
    /// 이 값이 true 면 P-core 우선 QoS 사용, false 면 E-core 우선.
    public var prefersHighPerformance: Bool {
        let src = current
        guard src == .ac else { return false }
        return !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private init() {
        refresh()
        startMonitoring()

        // LowPowerMode 변경도 동일 노티에 통합 (AC 상태에서 절전 토글 시 QoS 변경 트리거)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            NotificationCenter.default.post(name: .cviewPowerSourceChanged, object: nil)
        }
    }

    // MARK: - Refresh

    private func refresh() {
        let typeRef = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue()
        let typeStr = typeRef as String?

        let new: CViewPowerSource
        switch typeStr {
        case kIOPMACPowerKey:
            new = .ac
        case kIOPMBatteryPowerKey, kIOPMUPSPowerKey:
            new = .battery
        default:
            new = .unknown
        }

        lock.lock()
        let changed = _current != new
        _current = new
        lock.unlock()

        if changed {
            NotificationCenter.default.post(name: .cviewPowerSourceChanged, object: nil)
        }
    }

    // MARK: - IOKit RunLoop Source

    private func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let unmanagedSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let mon = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            mon.refresh()
        }, context)

        guard let source = unmanagedSource?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }
}

// MARK: - Power-Aware Task Priority

/// 의미 기반 Task 우선순위 — 전원 상태에 따라 P-core / E-core 힌트를 동적 결정.
///
/// 사용 예:
/// ```swift
/// Task.detached(priority: PowerAwareTaskPriority.userVisible) { ... }
/// Task.detached(priority: PowerAwareTaskPriority.periodic)    { ... }
/// Task.detached(priority: PowerAwareTaskPriority.prefetch)    { ... }
/// ```
public enum PowerAwareTaskPriority {

    /// 사용자에게 곧 보일 결과 (메시지 변환, 즉시 디코딩, DB 초기화 등)
    /// - AC: `.userInitiated` → P-core 우선, 빠른 응답
    /// - Battery: `.utility` → E-core 우선, 배터리 보호
    public static var userVisible: TaskPriority {
        PowerSourceMonitor.shared.prefersHighPerformance ? .userInitiated : .utility
    }

    /// 주기적 모니터링 / 폴링 (PerformanceMonitor, ABR, manifest refresh 등)
    /// - AC: `.utility` → E-core 위주지만 적당히 응답
    /// - Battery: `.background` → E-core + 스로틀, 최대 절전
    public static var periodic: TaskPriority {
        PowerSourceMonitor.shared.prefersHighPerformance ? .utility : .background
    }

    /// 백그라운드 프리페치 (이미지·이모티콘 다운로드)
    /// - 항상 `.background` — 사용자 인지 불필요, 배터리 보호 우선
    public static var prefetch: TaskPriority { .background }

    /// 사용자 즉시 인터랙션 결과 (재생 시작, 채널 전환 등)
    /// - AC: `.userInteractive` → P-core 강제 선호
    /// - Battery: `.userInitiated` → P-core 선호하되 약간 양보
    /// 주의: 너무 자주 사용하면 배터리 절약 효과가 사라짐. 진짜 즉시 응답이 필요한 곳만.
    public static var userInteractive: TaskPriority {
        PowerSourceMonitor.shared.prefersHighPerformance ? .high : .userInitiated
    }
}

// MARK: - Power-Aware Interval Helpers

/// 전원 상태에 따라 주기·임계값을 동적으로 조절하는 헬퍼.
public enum PowerAwareInterval {

    /// 주기를 전원 상태에 따라 스케일링.
    /// - AC: `acSeconds`
    /// - Battery: `acSeconds × batteryMultiplier` (기본 1.5배 — 50% 더 느린 폴링)
    public static func scaled(_ acSeconds: TimeInterval, batteryMultiplier: Double = 1.5) -> TimeInterval {
        PowerSourceMonitor.shared.prefersHighPerformance
            ? acSeconds
            : acSeconds * batteryMultiplier
    }
}
