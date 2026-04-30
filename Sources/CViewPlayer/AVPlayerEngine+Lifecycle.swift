// MARK: - AVPlayerEngine+Lifecycle.swift
// CViewPlayer - Observer/Task 라이프사이클 중앙 관리 (누수 방지)
//
// 설계 목표
//   - 모든 KVO/Notification/PeriodicTimeObserver를 한 인스턴스에 축적
//   - 모든 Task를 한 인스턴스에 축적
//   - deinit/stop()/resetForReuse()에서 단 한 번 호출로 완전 해제 보증
//
// 구현 주의
//   - NSKeyValueObservation/NSObjectProtocol/timeObserver(Any)는 Sendable이 아니므로
//     Swift 6의 Mutex<T>(sending inout T) 요구사항을 만족시킬 수 없다.
//     따라서 NSLock 기반의 @unchecked Sendable 클래스로 직접 구현한다.

import Foundation
import AVFoundation

// MARK: - Observer Bag

/// AVPlayer 관련 모든 옵저버 (KVO / Notification / PeriodicTimeObserver) 중앙 관리.
///
/// 사용법:
/// ```
/// observers.addKVO(item.observe(\.status) { ... })
/// observers.addNotification(NotificationCenter.default.addObserver(...))
/// observers.addTimeObserver(player.addPeriodicTimeObserver(...), on: player)
/// observers.removeItemScoped()  // PlayerItem 교체 시
/// observers.removeAll()         // 엔진 정리 시
/// ```
internal final class AVPlayerObserverBag: @unchecked Sendable {

    private let lock = NSLock()
    private var kvo: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    /// (player, opaqueObserverToken) — removeTimeObserver는 원본 player 참조 필요
    private var timeObservers: [(AVPlayer, Any)] = []

    // MARK: Add

    func addKVO(_ observation: NSKeyValueObservation) {
        lock.lock(); defer { lock.unlock() }
        kvo.append(observation)
    }

    func addNotification(_ token: NSObjectProtocol) {
        lock.lock(); defer { lock.unlock() }
        notifications.append(token)
    }

    func addTimeObserver(_ token: Any, on player: AVPlayer) {
        lock.lock(); defer { lock.unlock() }
        timeObservers.append((player, token))
    }

    // MARK: Remove

    /// 아이템 단위 옵저버만 제거 (PlayerItem 교체 시 사용).
    /// KVO와 Notification은 대부분 item-scoped이므로 전부 해제.
    /// PeriodicTimeObserver는 player-scoped이므로 유지.
    func removeItemScoped() {
        lock.lock()
        let oldKVO = kvo
        let oldNotes = notifications
        kvo.removeAll(keepingCapacity: true)
        notifications.removeAll(keepingCapacity: true)
        lock.unlock()

        for obs in oldKVO { obs.invalidate() }
        for token in oldNotes { NotificationCenter.default.removeObserver(token) }
    }

    /// 모든 옵저버 해제 — 엔진 정리 시 호출.
    func removeAll() {
        lock.lock()
        let oldKVO = kvo
        let oldNotes = notifications
        let oldTime = timeObservers
        kvo.removeAll(keepingCapacity: true)
        notifications.removeAll(keepingCapacity: true)
        timeObservers.removeAll(keepingCapacity: true)
        lock.unlock()

        for obs in oldKVO { obs.invalidate() }
        for token in oldNotes { NotificationCenter.default.removeObserver(token) }
        for (player, token) in oldTime { player.removeTimeObserver(token) }
    }

    deinit { removeAll() }
}

// MARK: - Task Bag

/// AVPlayer 관련 장기 실행 Task 중앙 관리.
/// 동일 이름 Task는 교체(자동 취소)되고, `cancelAll()`로 일괄 정리.
internal final class AVPlayerTaskBag: @unchecked Sendable {

    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    /// 이름으로 Task를 등록 또는 교체. 기존 동일 이름 Task는 취소됨.
    func set(_ name: String, _ task: Task<Void, Never>) {
        lock.lock()
        let old = tasks[name]
        tasks[name] = task
        lock.unlock()
        old?.cancel()
    }

    func cancel(_ name: String) {
        lock.lock()
        let old = tasks.removeValue(forKey: name)
        lock.unlock()
        old?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let all = Array(tasks.values)
        tasks.removeAll(keepingCapacity: true)
        lock.unlock()
        for t in all { t.cancel() }
    }

    deinit { cancelAll() }
}

// MARK: - Task Bag Keys

extension AVPlayerTaskBag {
    /// 스톨 워치독 (라이브 전용)
    static let kStallWatchdog = "stall.watchdog"
    /// 라이브 캐치업 루프
    static let kLiveCatchup = "live.catchup"
    /// 주기 메트릭 수집
    static let kMetricsCollector = "metrics.collector"
    /// stall notification 직후의 빠른 복구 시도
    static let kStallRecovery = "stall.recovery"
    /// [HQ 복귀] 레이턴시 캐치업 등으로 AVFoundation 내부 ABR이 720p 이하로 고정된 경우
    /// ceiling(preferredPeakBitRate)을 잠시 해제해 재평가를 유도하는 복귀 워치독
    static let kHQRecovery = "hq.recovery"
}
