// MARK: - MetricsWebSocketClient.swift
// 메트릭 서버 WebSocket 클라이언트 — 실시간 메트릭 스트림

import Foundation
import CViewCore

/// 메트릭 서버 WebSocket 클라이언트
/// - wss://cv.dododo.app 연결
/// - 자동 재연결 (최대 5회, 지수 백오프)
/// - AsyncStream<MetricsWebSocketMessage>로 메시지 전달
public actor MetricsWebSocketClient {
    
    // MARK: - State
    
    public enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }
    
    private let serverURL: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var state: ConnectionState = .disconnected
    private var continuation: AsyncStream<MetricsWebSocketMessage>.Continuation?
    private var reconnectTask: Task<Void, Never>?
    private let maxReconnectAttempts = 5
    private var isManuallyDisconnected = false
    
    // MARK: - Init
    
    public init(serverURL: URL = URL(string: "wss://cv.dododo.app")!) {
        self.serverURL = serverURL
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// 연결 상태
    public var connectionState: ConnectionState { state }
    
    /// WebSocket 메시지 스트림 연결
    public func connect() -> AsyncStream<MetricsWebSocketMessage> {
        isManuallyDisconnected = false
        
        let stream = AsyncStream<MetricsWebSocketMessage> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect() }
            }
        }
        
        Task { await startConnection() }
        
        return stream
    }
    
    /// 연결 해제
    public func disconnect() {
        isManuallyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .disconnected
        continuation?.finish()
        continuation = nil
    }
    
    // MARK: - Connection Management
    
    private func startConnection() async {
        guard !isManuallyDisconnected else { return }
        
        state = .connecting
        let task = session.webSocketTask(with: serverURL)
        webSocketTask = task
        task.resume()
        
        state = .connected
        await receiveMessages()
    }
    
    private func receiveMessages() async {
        guard let task = webSocketTask else { return }
        
        while !isManuallyDisconnected {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let wsMessage = try? JSONDecoder().decode(MetricsWebSocketMessage.self, from: data) {
                        continuation?.yield(wsMessage)
                    }
                case .data(let data):
                    if let wsMessage = try? JSONDecoder().decode(MetricsWebSocketMessage.self, from: data) {
                        continuation?.yield(wsMessage)
                    }
                @unknown default:
                    break
                }
            } catch {
                // 연결 끊김 → 재연결 시도
                if !isManuallyDisconnected {
                    await scheduleReconnect()
                }
                return
            }
        }
    }
    
    private func scheduleReconnect() async {
        guard !isManuallyDisconnected else { return }
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        for attempt in 1...maxReconnectAttempts {
            guard !isManuallyDisconnected else { return }
            
            state = .reconnecting(attempt: attempt)
            let delay = min(Double(attempt * attempt), 30.0) // 1, 4, 9, 16, 25초
            try? await Task.sleep(for: .seconds(delay))
            
            guard !isManuallyDisconnected else { return }
            
            // 재연결 시도
            let task = session.webSocketTask(with: serverURL)
            webSocketTask = task
            task.resume()
            
            // 연결 확인: 첫 메시지 수신 시도
            do {
                let message = try await task.receive()
                state = .connected
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let wsMessage = try? JSONDecoder().decode(MetricsWebSocketMessage.self, from: data) {
                        continuation?.yield(wsMessage)
                    }
                case .data(let data):
                    if let wsMessage = try? JSONDecoder().decode(MetricsWebSocketMessage.self, from: data) {
                        continuation?.yield(wsMessage)
                    }
                @unknown default:
                    break
                }
                // 재연결 성공 → 메시지 수신 루프 재개
                await receiveMessages()
                return
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil
                continue
            }
        }
        
        // 재연결 실패
        state = .disconnected
    }
}
