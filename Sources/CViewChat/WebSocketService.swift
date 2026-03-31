// MARK: - WebSocketService.swift
// CViewChat - Actor-based WebSocket connection manager
// Original: ChzzkChatService.swift (5,326 lines) → Split into focused actors

import Foundation
import Synchronization
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
            pingInterval: TimeInterval = WSDefaults.pingInterval,
            maxMessageSize: Int = WSDefaults.maxMessageSize,
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
    private let _messageStream: AsyncStream<WebSocketMessage>
    
    // State stream
    private var stateContinuation: AsyncStream<State>.Continuation?
    private let _stateStream: AsyncStream<State>
    
    // MARK: - Initialization
    
    public init(configuration: Configuration) {
        self.configuration = configuration
        // stream을 즉시 생성하여 connect() 전 구독 여부와 무관하게 메시지 수신 보장
        let (msgStream, msgCont) = AsyncStream<WebSocketMessage>.makeStream()
        self._messageStream = msgStream
        self.messageContinuation = msgCont
        let (stateStream, stateCont) = AsyncStream<State>.makeStream()
        self._stateStream = stateStream
        self.stateContinuation = stateCont
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
        sessionConfig.timeoutIntervalForRequest = WSDefaults.requestTimeout
        sessionConfig.timeoutIntervalForResource = WSDefaults.resourceTimeout
        sessionConfig.httpShouldSetCookies = true
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpAdditionalHeaders = [
            "Connection": "keep-alive",
            "Keep-Alive": WSDefaults.keepAliveHeader
        ]
        
        let delegate = WebSocketDelegate { [weak self] closeCode, _ in
            Task { [weak self] in
                await self?.handleServerClose(closeCode: closeCode)
            }
        }
        session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        
        var request = URLRequest(url: configuration.url)
        request.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        request.setValue(CommonHeaders.chromeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("permessage-deflate; client_max_window_bits", forHTTPHeaderField: "Sec-WebSocket-Extensions")
        request.setValue(WSDefaults.protocolVersion, forHTTPHeaderField: "Sec-WebSocket-Version")
        if let host = configuration.url.host {
            request.setValue(host, forHTTPHeaderField: "Host")
        }
        
        // 쿠키 및 추가 헤더 (NID_AUT, NID_SES 등)
        for (key, value) in configuration.httpHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        guard let session else {
            updateState(.failed("Session creation failed"))
            return
        }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = configuration.maxMessageSize
        webSocket = task
        task.resume()
        
        updateState(.connected)
        startReceiving()
        startPingTimer()
        
        logger.info("WebSocket connected to \(LogMask.url(self.configuration.url), privacy: .private)")
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
        logger.debug("Sent: [\(text.count) chars]")
    }
    
    /// Send binary data
    public func sendData(_ data: Data) async throws {
        guard _state == .connected, let ws = webSocket else {
            throw AppError.chat(.notConnected)
        }
        
        try await ws.send(.data(data))
    }
    
    /// Get the message stream (init에서 즉시 생성됨)
    public func messages() -> AsyncStream<WebSocketMessage> {
        _messageStream
    }
    
    /// Get the state change stream (init에서 즉시 생성됨)
    public func stateChanges() -> AsyncStream<State> {
        _stateStream
    }
    
    // MARK: - Private Methods
    
    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    guard let ws = self.webSocket else { break }
                    let message = try await ws.receive()
                    
                    let wsMessage: WebSocketMessage
                    switch message {
                    case .string(let text):
                        wsMessage = .text(text)
                    case .data(let data):
                        wsMessage = .data(data)
                    @unknown default:
                        continue
                    }
                    
                    self.messageContinuation?.yield(wsMessage)
                    
                } catch {
                    if !Task.isCancelled {
                        self.logger.warning("WS receive error: \(error.localizedDescription, privacy: .public)")
                        self.handleDisconnection(error: error)
                    }
                    break
                }
            }
            self.logger.info("WS receive loop ended")
        }
    }
    
    private func startPingTimer() {
        pingTask?.cancel()
        let pingInterval = configuration.pingInterval
        pingTask = Task {
            let timer = AsyncTimerSequence(interval: pingInterval)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                do {
                    try await self.sendPing()
                } catch {
                    // Ping 실패 시 1회 재시도 후 연결 해제 (일시적 네트워크 지터 대응)
                    self.logger.warning("Ping failed, retrying once...")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초 대기
                    do {
                        try await self.sendPing()
                        self.logger.info("Ping retry succeeded")
                        continue
                    } catch {
                        self.handleDisconnection(error: error)
                        break
                    }
                }
            }
        }
    }
    
    private func sendPing() async throws {
        guard let ws = webSocket else { return }
        
        // URLSessionWebSocketTask.sendPing의 completionHandler가 호출되지 않거나
        // 2회 호출되는 edge case 방지를 위해 UnsafeContinuation + Mutex guard 사용.
        let resumed = Mutex(false)
        let timeoutTaskHolder = Mutex<Task<Void, Never>?>(nil)
        
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
            let resumeOnce: @Sendable (Error?) -> Void = { error in
                let alreadyResumed = resumed.withLock { val -> Bool in
                    if val { return true }
                    val = true
                    return false
                }
                guard !alreadyResumed else { return }
                timeoutTaskHolder.withLock { $0?.cancel() }
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            
            ws.sendPing { error in
                resumeOnce(error)
            }
            
            // 10초 타임아웃: completionHandler가 호출되지 않는 경우 대비
            let task = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                resumeOnce(URLError(.timedOut))
            }
            timeoutTaskHolder.withLock { $0 = task }
        }
    }
    
    private func updateState(_ newState: State) {
        _state = newState
        stateContinuation?.yield(newState)
    }
    
    private func handleDisconnection(error: Error) {
        // 이미 연결 해제 상태면 중복 처리 방지
        guard _state == .connected || _state == .connecting else { return }
        
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        
        updateState(.failed(error.localizedDescription))
        logger.warning("WebSocket disconnected due to error: \(error.localizedDescription, privacy: .public)")
    }
    
    /// 서버가 close frame을 보냈을 때 delegate에서 호출
    private func handleServerClose(closeCode: URLSessionWebSocketTask.CloseCode) {
        guard _state == .connected || _state == .connecting else { return }
        logger.info("WS server close frame received: \(closeCode.rawValue)")
        handleDisconnection(error: URLError(.networkConnectionLost))
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
    private let onClose: @Sendable (URLSessionWebSocketTask.CloseCode, Data?) -> Void
    
    init(onClose: @escaping @Sendable (URLSessionWebSocketTask.CloseCode, Data?) -> Void = { _, _ in }) {
        self.onClose = onClose
    }
    
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
        onClose(closeCode, reason)
    }
}
