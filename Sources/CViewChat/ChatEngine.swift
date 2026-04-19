// MARK: - ChatEngine.swift
// CViewChat - Unified chat engine orchestrating WebSocket, parsing, and reconnection
// 원본: ChzzkChatService (5,326L God Object) → 500L 미만으로 분리된 구성 요소의 오케스트레이터

import Foundation
import CViewCore

// MARK: - Chat Engine

/// Orchestrates chat WebSocket connection, message parsing, and reconnection.
/// Uses composition over inheritance – delegates to focused components.
public actor ChatEngine {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let chatChannelId: String
        public let accessToken: String
        public let extraToken: String?
        public let uid: String?
        public let channelId: String?
        public let serverUrl: URL
        public let reconnectionConfig: ReconnectionPolicy.Configuration
        public let maxMessageBuffer: Int
        
        public init(
            chatChannelId: String,
            accessToken: String,
            extraToken: String? = nil,
            uid: String? = nil,
            channelId: String? = nil,
            serverUrl: URL? = nil,
            reconnectionConfig: ReconnectionPolicy.Configuration = .default,
            maxMessageBuffer: Int = ChatDefaults.maxMessageBuffer
        ) {
            self.chatChannelId = chatChannelId
            self.accessToken = accessToken
            self.extraToken = extraToken
            self.uid = uid
            self.channelId = channelId
            self.serverUrl = serverUrl ?? Self.computeServerURL(chatChannelId: chatChannelId)
            self.reconnectionConfig = reconnectionConfig
            self.maxMessageBuffer = maxMessageBuffer
        }
        
        /// chatChannelId의 UTF-8 바이트 합산으로 서버 번호(1~9) 결정
        private static func computeServerURL(chatChannelId: String) -> URL {
            let sum = chatChannelId.utf8.reduce(0) { $0 + Int($1) }
            let serverId = (sum % 9) + 1
            // serverId는 1~9 범위이므로 URL 생성 실패 불가, guard로 방어
            guard let url = URL(string: "wss://kr-ss\(serverId).chat.naver.com/chat") else {
                return URL(string: "wss://kr-ss1.chat.naver.com/chat")!
            }
            return url
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let parser = ChatMessageParser()
    private let logger = AppLogger.chat
    
    private var webSocket: WebSocketService?
    private var reconnection: ReconnectionPolicy
    
    private var messageListenTask: Task<Void, Never>?
    private var stateListenTask: Task<Void, Never>?
    
    // State
    private var _connectionState: ChatConnectionState = .disconnected
    private var _messages: [ChatMessage] = []
    private var _sessionId: String?
    private var isManualDisconnect = false
    private var _nextTid: Int = 3
    
    // Streams
    private var eventContinuation: AsyncStream<ChatEngineEvent>.Continuation?
    private var _eventStream: AsyncStream<ChatEngineEvent>
    
    // MARK: - Public Accessors
    
    public var connectionState: ChatConnectionState { _connectionState }
    public var messages: [ChatMessage] { _messages }
    public var sessionId: String? { _sessionId }
    public var isConnected: Bool { _connectionState.isConnected }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration) {
        self.config = configuration
        self.reconnection = ReconnectionPolicy(configuration: configuration.reconnectionConfig)
        // AsyncStream을 init에서 즉시 생성하여 이벤트 드롭 방지
        var cont: AsyncStream<ChatEngineEvent>.Continuation?
        self._eventStream = AsyncStream<ChatEngineEvent> { continuation in
            cont = continuation
        }
        self.eventContinuation = cont
    }
    
    deinit {
        messageListenTask?.cancel()
        stateListenTask?.cancel()
        reconnectionTask?.cancel()
        eventContinuation?.finish()
    }
    
    // MARK: - Public API
    
    /// Connect to chat server
    public func connect() async {
        isManualDisconnect = false
        await reconnection.reset()
        
        updateConnectionState(.connecting)
        
        do {
            try await establishConnection()
        } catch {
            logger.error("Initial connection failed: \(error.localizedDescription, privacy: .public)")
            await startReconnection()
        }
    }
    
    /// Disconnect from chat server
    public func disconnect() async {
        isManualDisconnect = true
        
        messageListenTask?.cancel()
        messageListenTask = nil
        stateListenTask?.cancel()
        stateListenTask = nil
        // [Fix 25D] reconnectionTask 명시적 취소 — disconnect 후에도 재연결 시도 방지
        reconnectionTask?.cancel()
        reconnectionTask = nil
        
        await webSocket?.disconnect()
        await reconnection.cancel()
        
        updateConnectionState(.disconnected)
        logger.info("Chat disconnected (manual)")
    }
    
    /// Send a chat message
    public func sendMessage(_ text: String, emojis: [String: String]? = nil) async throws {
        guard isConnected else {
            throw AppError.chat(.notConnected)
        }
        
        let tid = _nextTid
        _nextTid = (_nextTid == Int.max) ? 3 : _nextTid + 1
        
        let message = parser.buildSendMessage(
            chatChannelId: config.chatChannelId,
            channelId: config.channelId,
            sessionId: _sessionId,
            extraToken: config.extraToken,
            message: text,
            tid: tid,
            emojis: emojis
        )
        
        logger.info("Chat send payload: [\(message.count) chars]")
        try await webSocket?.send(message)
        logger.debug("Chat message sent: \(text.prefix(50), privacy: .private)")
    }
    
    /// Request recent chat messages
    public func requestRecentMessages() async throws {
        guard isConnected else { return }
        
        let request = parser.buildRecentChatRequest(chatChannelId: config.chatChannelId)
        try await webSocket?.send(request)
    }
    
    /// Get the event stream for UI binding
    public func events() -> AsyncStream<ChatEngineEvent> {
        return _eventStream
    }

    /// [M-3] 백그라운드 모드 전파 — WebSocket ping 주기/QoS 감쇄.
    /// MultiChatSessionManager가 비활성 세션을 백그라운드로 전환할 때 호출.
    public func setBackgroundMode(_ enabled: Bool) async {
        await webSocket?.setBackgroundMode(enabled)
    }
    
    /// Clear message buffer
    public func clearMessages() {
        _messages.removeAll()
        emitEvent(.messagesCleared)
    }
    
    // MARK: - Connection Management
    
    private func establishConnection() async throws {
        logger.info("Chat connecting to: \(LogMask.url(self.config.serverUrl), privacy: .private) (chatChannelId: \(self.config.chatChannelId, privacy: .public))")
        
        // NID_AUT, NID_SES 쿠키를 URLRequest Cookie 헤더로 전달 (v1 동일)
        // uid 유무와 관계없이 항상 쿠키 주입 — 서버가 쿠키로 인증 수행
        var httpHeaders: [String: String] = [:]
        let cookieNames: Set<String> = ["NID_AUT", "NID_SES"]
        if let allCookies = HTTPCookieStorage.shared.cookies {
            let authCookies = allCookies.filter {
                cookieNames.contains($0.name) &&
                $0.domain.contains("naver.com") &&
                !$0.value.isEmpty
            }
            if !authCookies.isEmpty {
                let cookieHeader = authCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                httpHeaders["Cookie"] = cookieHeader
                logger.info("WS cookie header: \(authCookies.count) cookies attached")
            } else {
                logger.warning("No NID_AUT/NID_SES cookies found in HTTPCookieStorage")
            }
        } else {
            logger.warning("HTTPCookieStorage.shared.cookies is nil")
        }
        
        let wsConfig = WebSocketService.Configuration(
            url: config.serverUrl,
            pingInterval: ChatDefaults.pingInterval,
            httpHeaders: httpHeaders
        )
        
        // 기존 WebSocket 정리 — URLSession 메모리 누수 방지 (장시간 재생 시 세션 축적 방지)
        if let oldWs = self.webSocket {
            await oldWs.disconnect()
            self.webSocket = nil
        }
        
        let ws = WebSocketService(configuration: wsConfig)
        self.webSocket = ws
        
        try await ws.connect()
        
        // Send connect command
        let connectMsg = parser.buildConnectMessage(
            chatChannelId: config.chatChannelId,
            accessToken: config.accessToken,
            uid: config.uid
        )
        logger.info("Connect msg (uid: \(self.config.uid != nil ? "✓" : "✗", privacy: .public), auth: \(self.config.uid != nil ? "SEND" : "READ", privacy: .public))")
        try await ws.send(connectMsg)
        
        // Start listening
        startMessageListening(ws)
        startStateListening(ws)
    }
    
    private func startMessageListening(_ ws: WebSocketService) {
        messageListenTask?.cancel()
        messageListenTask = Task { [weak self] in
            guard let self else { return }
            
            let stream = await ws.messages()
            for await message in stream {
                guard !Task.isCancelled else { break }
                
                if let text = message.textValue {
                    // 파싱을 actor 직렬 큐에서 분리 — 멀티코어 활용
                    // ChatMessageParser는 stateless Sendable struct이므로 안전
                    let parseResult = Self.parseOffActor(text: text, parser: self.parser)
                    await self.handleParsedResult(parseResult, rawLength: text.count)
                }
            }
            
            // Stream ended = disconnected
            if !Task.isCancelled {
                await self.handleWebSocketClosed()
            }
        }
    }
    
    private func startStateListening(_ ws: WebSocketService) {
        stateListenTask?.cancel()
        stateListenTask = Task { [weak self] in
            guard let self else { return }
            
            let stream = await ws.stateChanges()
            for await newState in stream {
                guard !Task.isCancelled else { break }
                
                switch newState {
                case .connected:
                    break // Wait for protocol-level connected
                case .failed(let reason):
                    await self.logger.error("WS state failed: \(reason, privacy: .private)")
                case .disconnected:
                    break
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Message Handling
    
    /// 파싱 결과를 나타내는 enum — actor 바깥에서 생성 후 actor로 전달
    private enum ParseResult: Sendable {
        case success(ChatEvent)
        case failure(String, String) // (errorDescription, rawPreview)
    }
    
    /// nonisolated 파싱 — actor 직렬 큐를 차단하지 않고 멀티코어에서 실행
    /// ChatMessageParser는 stateless Sendable struct이므로 안전
    private nonisolated static func parseOffActor(text: String, parser: ChatMessageParser) -> ParseResult {
        do {
            let event = try parser.parse(text)
            return .success(event)
        } catch {
            let preview = String(text.prefix(200))
            return .failure(error.localizedDescription, preview)
        }
    }
    
    /// 파싱된 결과를 actor 격리 내에서 처리
    private func handleParsedResult(_ result: ParseResult, rawLength: Int) {
        switch result {
        case .success(let event):
            handleParsedEvent(event)
        case .failure(let errorDesc, let preview):
            logger.warning("Failed to parse message: \(errorDesc, privacy: .public) | raw: \(preview, privacy: .public)")
        }
    }
    
    private func handleParsedEvent(_ event: ChatEvent) {
        switch event {
        case .connected(let sessionId):
            _sessionId = sessionId
            updateConnectionState(.connected(serverIndex: 0))
            logger.info("Chat CONNECTED (sid: \(LogMask.token(sessionId), privacy: .private))")
            Task {
                do {
                    try await requestRecentMessages()
                } catch {
                    logger.warning("Recent messages fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            emitEvent(.connected)
            
        case .messages(let msgs):
            appendMessages(msgs)
            emitEvent(.newMessages(msgs))
            
        case .recentMessages(let msgs):
            logger.info("Chat recent messages: \(msgs.count) msgs")
            appendMessages(msgs)
            emitEvent(.recentMessages(msgs))
            
        case .donations(let msgs):
            appendMessages(msgs)
            emitEvent(.donations(msgs))
            
        case .notice(let msg):
            appendMessages([msg])
            emitEvent(.notice(msg))
            
        case .blind(let messageId, _):
            removeMessage(id: messageId)
            emitEvent(.messageBlinded(messageId))
            
        case .kick:
            emitEvent(.kicked)
            
        case .penalty(let userId, let duration):
            emitEvent(.userPenalized(userId: userId, duration: duration))
            
        case .ping:
            Task {
                let pong = parser.buildPong()
                do {
                    try await webSocket?.send(pong)
                } catch {
                    logger.warning("Pong send failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            
        case .pong:
            break
            
        case .sendConfirmed(let retCode):
            if retCode == 0 {
                logger.info("Chat send confirmed ✅")
            } else {
                logger.warning("Chat send failed: retCode=\(retCode, privacy: .public)")
            }
            
        case .system(let msg):
            emitEvent(.systemMessage(msg))
            
        case .unknown(let cmd):
            logger.debug("Unknown chat command: \(cmd)")
        }
    }
    
    // MARK: - Buffer Management
    
    private func appendMessages(_ newMessages: [ChatMessage]) {
        _messages.append(contentsOf: newMessages)
        
        // Trim buffer if needed
        if _messages.count > config.maxMessageBuffer {
            let excess = _messages.count - config.maxMessageBuffer
            _messages.removeFirst(excess)
        }
    }
    
    private func removeMessage(id: String) {
        _messages.removeAll { $0.id == id }
    }
    
    // MARK: - Reconnection
    
    private var reconnectionTask: Task<Void, Never>?

    private func handleWebSocketClosed() {
        guard !isManualDisconnect else { return }
        
        updateConnectionState(.reconnecting(attempt: 0))
        
        // 기존 재연결 Task가 있으면 취소 후 새로 시작 — 중복 재연결 방지
        reconnectionTask?.cancel()
        reconnectionTask = Task {
            await startReconnection()
        }
    }
    
    private func startReconnection() async {
        guard !isManualDisconnect else { return }
        
        updateConnectionState(.reconnecting(attempt: 1))
        emitEvent(.reconnecting)
        
        do {
            try await reconnection.executeReconnection { [weak self] in
                guard let self else {
                    throw AppError.chat(.connectionFailed("ChatEngine이 해제되어 재연결 불가"))
                }
                try await self.establishConnection()
            }
        } catch {
            updateConnectionState(.failed(reason: "재연결 실패: 최대 시도 횟수 초과"))
            emitEvent(.disconnected(reason: "재연결 실패: 최대 시도 횟수 초과"))
            logger.error("Reconnection failed permanently")
        }
    }
    
    // MARK: - State Management
    
    private func updateConnectionState(_ state: ChatConnectionState) {
        _connectionState = state
        emitEvent(.stateChanged(state))
    }
    
    private func emitEvent(_ event: ChatEngineEvent) {
        if eventContinuation == nil {
            logger.warning("eventContinuation is nil, event dropped: \(String(describing: event).prefix(50), privacy: .public)")
        }
        eventContinuation?.yield(event)
    }
}

// MARK: - Chat Engine Events

public enum ChatEngineEvent: Sendable {
    case connected
    case disconnected(reason: String)
    case reconnecting
    case stateChanged(ChatConnectionState)
    case newMessages([ChatMessage])
    case recentMessages([ChatMessage])
    case donations([ChatMessage])
    case notice(ChatMessage)
    case messageBlinded(String)
    case kicked
    case userPenalized(userId: String, duration: Int)
    case systemMessage(String)
    case messagesCleared
}
