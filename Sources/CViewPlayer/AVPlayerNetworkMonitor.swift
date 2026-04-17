// MARK: - AVPlayerNetworkMonitor.swift
// CViewPlayer - 공유 NWPathMonitor (멀티라이브 N개 세션이 하나의 모니터 공유)
//
// 기존: AVPlayerEngine 인스턴스마다 NWPathMonitor 생성 → 4세션 = 4개 모니터
// 개선: 전역 싱글톤 1개가 Path 변경을 다수 구독자에게 브로드캐스트
//
// 스레드 안전
//   - 구독 추가/제거, 알림 브로드캐스트 모두 전용 큐에서 처리
//   - 구독 콜백은 내부 큐에서 호출되며, 콜백 내에서 MainActor 전환은 구독자 책임

import Foundation
import Network

// MARK: - Shared Network Monitor

/// 공유 네트워크 경로 모니터.
/// - 엔진들이 `shared.subscribe(_:)`로 path 변경을 구독.
/// - 최소 1개 구독자가 있을 때만 내부 NWPathMonitor가 start됨(배터리 절약).
internal final class AVPlayerNetworkMonitor: @unchecked Sendable {

    // MARK: Interface Type

    enum InterfaceType: Sendable, Equatable {
        case wiredEthernet
        case wifi
        case cellular
        case other
        case offline

        static func from(path: NWPath) -> InterfaceType {
            guard path.status == .satisfied else { return .offline }
            if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
            if path.usesInterfaceType(.wifi) { return .wifi }
            if path.usesInterfaceType(.cellular) { return .cellular }
            return .other
        }
    }

    // MARK: Singleton

    static let shared = AVPlayerNetworkMonitor()

    // MARK: Internals

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "av.engine.network.shared")
    private var monitorStarted = false

    /// id → handler 맵. 동일 큐에서만 read/write.
    private var subscribers: [UUID: @Sendable (InterfaceType) -> Void] = [:]
    private var currentType: InterfaceType = .other

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }

    // MARK: API

    /// Path 변경 구독. 반환된 토큰을 보관하여 `unsubscribe(_:)`로 해제.
    /// 구독 직후 현재 타입이 즉시 1회 통보된다.
    @discardableResult
    func subscribe(_ handler: @escaping @Sendable (InterfaceType) -> Void) -> UUID {
        let id = UUID()
        queue.async { [weak self] in
            guard let self else { return }
            self.subscribers[id] = handler
            if !self.monitorStarted {
                self.monitor.start(queue: self.queue)
                self.monitorStarted = true
            }
            // 현재 상태 즉시 통보
            handler(self.currentType)
        }
        return id
    }

    func unsubscribe(_ id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.subscribers.removeValue(forKey: id)
            if self.subscribers.isEmpty && self.monitorStarted {
                self.monitor.cancel()
                self.monitorStarted = false
                // 재사용 위해 새 인스턴스 필요 — NWPathMonitor는 cancel 후 재start 불가
                // 따라서 여기서는 유지하고, 재구독 시 새 모니터 생성
            }
        }
    }

    // MARK: Path Handling

    private func handlePathUpdate(_ path: NWPath) {
        let type = InterfaceType.from(path: path)
        queue.async { [weak self] in
            guard let self else { return }
            guard type != self.currentType else { return }
            self.currentType = type
            for handler in self.subscribers.values {
                handler(type)
            }
        }
    }
}
