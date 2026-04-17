// MARK: - MetricsWebSocketClient.swift
// 메트릭 서버 WebSocket 클라이언트 — 실시간 메트릭 스트림

import Foundation
import CViewCore

/// 메트릭 서버 WebSocket 클라이언트
/// - wss://cv.dododo.app/ws 연결
/// - 자동 재연결 (지수 백오프, 무한 재시도)
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
    private var session: URLSession
    private var state: ConnectionState = .disconnected
    private var continuation: AsyncStream<MetricsWebSocketMessage>.Continuation?
    private var reconnectTask: Task<Void, Never>?
    private var isManuallyDisconnected = false
    
    // MARK: - Init
    
    public init(serverURL: URL = URL(string: MetricsSettings.defaultWebSocketURL)!) {
        self.serverURL = serverURL
        self.session = Self.makeSession()
    }
    
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// 연결 상태
    public var connectionState: ConnectionState { state }
    
    /// WebSocket 메시지 스트림 연결
    public func connect() -> AsyncStream<MetricsWebSocketMessage> {
        isManuallyDisconnected = false
        
        // 이전 stream이 있으면 종료하여 소비자 hang 방지
        continuation?.finish()
        continuation = nil
        
        // 이전 disconnect로 invalidate된 session 재생성
        session = Self.makeSession()
        
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
        // URLSession invalidate — delegate retain cycle 방지
        session.invalidateAndCancel()
    }
    
    // MARK: - Channel Subscription
    
    /// 채널 구독 — 해당 채널의 메트릭만 수신
    public func subscribe(channelId: String) async {
        await sendJSON(["type": "subscribe", "channelId": channelId])
    }
    
    /// 채널 구독 해제
    public func unsubscribe(channelId: String) async {
        await sendJSON(["type": "unsubscribe", "channelId": channelId])
    }
    
    /// 전체 구독 해제 (모든 채널 수신 모드로 복귀)
    public func unsubscribeAll() async {
        await sendJSON(["type": "subscribe", "channelId": ""])
    }
    
    /// 서버 상태 요청
    public func requestStatus() async {
        await sendJSON(["type": "status"])
    }
    
    /// JSON 메시지 전송
    private func sendJSON(_ dict: [String: String]) async {
        guard let task = webSocketTask, !isManuallyDisconnected else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            guard let text = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(text))
        } catch {
            Log.network.debug("WebSocket JSON 전송 실패: \(error.localizedDescription, privacy: .public)")
        }
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
            } catch is CancellationError {
                return
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
        
        var attempt = 0
        let maxAttempts = MetricsNetDefaults.maxReconnectAttempts
        while !isManuallyDisconnected && attempt < maxAttempts {
            attempt += 1
            state = .reconnecting(attempt: attempt)
            // 지수 백오프: 2, 4, 8, 16, 30, 30... 초
            let delay = min(pow(2.0, Double(attempt)), MetricsNetDefaults.maxBackoffDelay)
            Log.network.info("WebSocket 재연결 시도 \(attempt)/\(maxAttempts) — \(String(format: "%.0f", delay))초 후")
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return  // Task cancelled
            }
            
            guard !isManuallyDisconnected, !Task.isCancelled else { return }
            
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
        
        state = .disconnected
    }
}
