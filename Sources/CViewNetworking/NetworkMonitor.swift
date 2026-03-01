// MARK: - CViewNetworking/NetworkMonitor.swift
// 네트워크 상태 모니터링 — NWPathMonitor 기반

import Foundation
import Network
import CViewCore

/// 네트워크 상태 모니터
public actor NetworkMonitor {
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cview.network-monitor", qos: .utility)
    private var isMonitoring = false

    public private(set) var isConnected = true
    public private(set) var connectionType: ConnectionType = .unknown

    public enum ConnectionType: Sendable {
        case wifi, cellular, wired, unknown
    }

    private init() {}

    /// 현재 활성 stream continuation — 다중 start() 시 이전 stream 종료 보장
    private var activeContinuation: AsyncStream<Bool>.Continuation?

    /// 모니터링 시작
    public func start() -> AsyncStream<Bool> {
        // 이전 stream이 있으면 종료하여 고아 stream 방지
        activeContinuation?.finish()
        activeContinuation = nil

        return AsyncStream { continuation in
            self.activeContinuation = continuation
            monitor.pathUpdateHandler = { [weak self] path in
                Task {
                    await self?.handlePathUpdate(path)
                    let connected = path.status == .satisfied
                    continuation.yield(connected)
                }
            }
            if !isMonitoring {
                monitor.start(queue: queue)
                isMonitoring = true
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    private func clearContinuation() {
        activeContinuation = nil
    }

    private func handlePathUpdate(_ path: NWPath) {
        isConnected = path.status == .satisfied

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wired
        } else {
            connectionType = .unknown
        }

        Log.network.info("Network: \(self.isConnected ? "connected" : "disconnected") via \(String(describing: self.connectionType))")
    }

    private func stopIfNeeded() {
        // 참조 카운트 기반 정리는 향후 구현
    }
}
