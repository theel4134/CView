// MARK: - WebSocketService.swift
// CViewChat - Actor-based WebSocket connection manager
// Original: ChzzkChatService.swift (5,326 lines) → Split into focused actors

import Foundation
import CViewCore

// MARK: - WebSocket Connection Actor

/// Actor-based WebSocket connection manager.
/// 원본의 ChzzkChatService에서 WebSocket 연결 부분만 분리.
/// - Thread-safe by design (actor isolation)
/// - AsyncStream-based message delivery
/// - Automatic ping/pong handling
public actor WebSocketService {
    
    // MARK: - Types
    
    public enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(String)
        
        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.disconnecting, .disconnecting):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }
    
    public struct Configuration: Sendable {
        public let url: URL
        public let pingInterval: TimeInterval
        public let maxMessageSize: Int
        public let httpHeaders: [String: String]
        
        public init(
            url: URL,
            pingInterval: TimeInterval = 20,
            maxMessageSize: Int = 1_048_576,
            httpHeaders: [String: String] = [:]
        ) {
            self.url = url
            self.pingInterval = pingInterval
            self.maxMessageSize = maxMessageSize
            self.httpHeaders = httpHeaders
        }
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let logger = AppLogger.chat
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    
    private var _state: State = .disconnected
    public var state: State { _state }
    
    // Message stream
    private var messageContinuation: AsyncStream<WebSocketMessage>.Continuation?
    private var _messageStream: AsyncStream<WebSocketMessage>?
    
    // State stream
    private var stateContinuation: AsyncStream<State>.Continuation?
    private var _stateStream: AsyncStream<State>?
    
    // MARK: - Initialization
    
    public init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    deinit {
        pingTask?.cancel()
        receiveTask?.cancel()
        messageContinuation?.finish()
        stateContinuation?.finish()
    }
    
    // MARK: - Public API
    
    /// Connect to WebSocket server
    public func connect() async throws {
        switch _state {
        case .disconnected, .failed:
            break  // 연결 허용
        case .connecting, .connected, .disconnecting:
            logger.warning("WebSocket already \(String(describing: self._state))")
            return
        }
        
        updateState(.connecting)
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.timeoutIntervalForRequest = 90
        sessionConfig.timeoutIntervalForResource = 900
        sessionConfig.httpShouldSetCookies = true
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpAdditionalHeaders = [
            "Connection": "keep-alive",
            "Keep-Alive": "timeout=120, max=200"
        ]
        
        let delegate = WebSocketDelegate()
        session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        
        var request = URLRequest(url: configuration.url)
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("permessage-deflate; client_max_window_bits", forHTTPHeaderField: "Sec-WebSocket-Extensions")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        if let host = configuration.url.host {
            request.setValue(host, forHTTPHeaderField: "Host")
        }
        
        // 쿠키 및 추가 헤더 (NID_AUT, NID_SES 등)
        for (key, value) in configuration.httpHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let task = session!.webSocketTask(with: request)
        task.maximumMessageSize = configuration.maxMessageSize
        webSocket = task
        task.resume()
        
        updateState(.connected)
        startReceiving()
        startPingTimer()
        
        logger.info("WebSocket connected to \(self.configuration.url.absoluteString)")
    }
    
    /// Disconnect from WebSocket server
    public func disconnect() async {
        guard _state == .connected || _state == .connecting else { return }
        
        updateState(.disconnecting)
        
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        
        updateState(.disconnected)
        logger.info("WebSocket disconnected")
    }
    
    /// Send a text message
    public func send(_ text: String) async throws {
        guard _state == .connected, let ws = webSocket else {
            throw AppError.chat(.notConnected)
        }
        
        try await ws.send(.string(text))
        logger.debug("Sent: \(text.prefix(100))")
    }
    
    /// Send binary data
    public func sendData(_ data: Data) async throws {
        guard _state == .connected, let ws = webSocket else {
            throw AppError.chat(.notConnected)
        }
        
        try await ws.send(.data(data))
    }
    
    /// Get the message stream
    public func messages() -> AsyncStream<WebSocketMessage> {
        if let existing = _messageStream {
            return existing
        }
        
        let stream = AsyncStream<WebSocketMessage> { continuation in
            self.messageContinuation = continuation
        }
        _messageStream = stream
        return stream
    }
    
    /// Get the state change stream
    public func stateChanges() -> AsyncStream<State> {
        if let existing = _stateStream {
            return existing
        }
        
        let stream = AsyncStream<State> { continuation in
            self.stateContinuation = continuation
        }
        _stateStream = stream
        return stream
    }
    
    // MARK: - Private Methods
    
    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                do {
                    guard let ws = await self.webSocket else { break }
                    let message = try await ws.receive()
                    
                    let wsMessage: WebSocketMessage
                    switch message {
                    case .string(let text):
                        wsMessage = .text(text)
                        await self.logger.debug("WS recv: \(text.prefix(80), privacy: .public)")
                    case .data(let data):
                        wsMessage = .data(data)
                        await self.logger.debug("WS recv data: \(data.count) bytes")
                    @unknown default:
                        continue
                    }
                    
                    await self.messageContinuation?.yield(wsMessage)
                    
                } catch {
                    if !Task.isCancelled {
                        await self.logger.warning("WS receive error: \(error.localizedDescription, privacy: .public)")
                        await self.handleDisconnection(error: error)
                    }
                    break
                }
            }
            await self.logger.info("WS receive loop ended")
        }
    }
    
    private func startPingTimer() {
        pingTask?.cancel()
        let pingInterval = configuration.pingInterval
        pingTask = Task { [weak self] in
            guard let self else { return }
            
            let timer = AsyncTimerSequence(interval: pingInterval)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                do {
                    try await sendPing()
                } catch {
                    await handleDisconnection(error: error)
                    break
                }
            }
        }
    }
    
    private func sendPing() async throws {
        guard let ws = webSocket else { return }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ws.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func handleDisconnection(error: Error) {
        logger.error("WebSocket disconnection: \(error.localizedDescription)")
        updateState(.failed(error.localizedDescription))
        
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket = nil
    }
    
    private func updateState(_ newState: State) {
        _state = newState
        stateContinuation?.yield(newState)
    }
}

// MARK: - WebSocket Message Type

public enum WebSocketMessage: Sendable {
    case text(String)
    case data(Data)
    
    public var textValue: String? {
        if case .text(let text) = self { return text }
        return nil
    }
    
    public var dataValue: Data? {
        if case .data(let data) = self { return data }
        return nil
    }
}

// MARK: - WebSocket Delegate

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // Connection opened
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        // Connection closed
    }
}
