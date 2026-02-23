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
            maxMessageBuffer: Int = 500
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
            return URL(string: "wss://kr-ss\(serverId).chat.naver.com/chat")!
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
        
        logger.info("Chat send payload: \(message.prefix(500), privacy: .public)")
        try await webSocket?.send(message)
        logger.debug("Chat message sent: \(text.prefix(50))")
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
    
    /// Clear message buffer
    public func clearMessages() {
        _messages.removeAll()
        emitEvent(.messagesCleared)
    }
    
    // MARK: - Connection Management
    
    private func establishConnection() async throws {
        logger.info("Chat connecting to: \(self.config.serverUrl.absoluteString, privacy: .public) (chatChannelId: \(self.config.chatChannelId, privacy: .public))")
        
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
                logger.info("WS cookie header: \(authCookies.map(\.name).joined(separator: ", "), privacy: .public)")
            } else {
                logger.warning("No NID_AUT/NID_SES cookies found in HTTPCookieStorage")
            }
        } else {
            logger.warning("HTTPCookieStorage.shared.cookies is nil")
        }
        
        let wsConfig = WebSocketService.Configuration(
            url: config.serverUrl,
            pingInterval: 20,
            httpHeaders: httpHeaders
        )
        
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
                    await self.handleIncomingMessage(text)
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
                    await self.logger.error("WS state failed: \(reason, privacy: .public)")
                case .disconnected:
                    break
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func handleIncomingMessage(_ text: String) {
        // Pre-parse raw logging
        let cmdPreview: String
        if let range = text.range(of: "\"cmd\":"), let endRange = text[range.upperBound...].range(of: ",") ?? text[range.upperBound...].range(of: "}") {
            cmdPreview = String(text[range.lowerBound..<endRange.lowerBound])
        } else {
            cmdPreview = "?"
        }
        let preview = String(text.prefix(300))
        logger.debug("Chat raw (\(cmdPreview, privacy: .public)): \(preview, privacy: .public)")
        
        do {
            let event = try parser.parse(text)
            
            switch event {
            case .connected(let sessionId):
                _sessionId = sessionId
                updateConnectionState(.connected(serverIndex: 0))
                logger.info("Chat CONNECTED (sid: \(sessionId.prefix(20), privacy: .public))")
                Task { try? await requestRecentMessages() }
                emitEvent(.connected)
                
            case .messages(let msgs):
                logger.debug("Chat messages received: \(msgs.count) msgs")
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
                    try? await webSocket?.send(pong)
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
            
        } catch {
            // 파싱 실패 시 원본 메시지 일부를 표시하여 디버깅 가능하게
            let preview = String(text.prefix(200))
            logger.warning("Failed to parse message: \(error.localizedDescription, privacy: .public) | raw: \(preview, privacy: .public)")
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
    
    private func handleWebSocketClosed() {
        guard !isManualDisconnect else { return }
        
        updateConnectionState(.reconnecting(attempt: 0))
        
        Task {
            await startReconnection()
        }
    }
    
    private func startReconnection() async {
        guard !isManualDisconnect else { return }
        
        updateConnectionState(.reconnecting(attempt: 1))
        emitEvent(.reconnecting)
        
        do {
            try await reconnection.executeReconnection { [weak self] in
                guard let self else { return }
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
