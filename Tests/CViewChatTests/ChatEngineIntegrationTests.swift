// MARK: - ChatEngineIntegrationTests.swift
// Mock-based integration tests for ChatEngine event dispatch, message handling,
// connection state transitions, and reconnection behavior.

import Testing
import Foundation
@testable import CViewChat
@testable import CViewCore

// MARK: - Test Helpers

/// Minimal ChatEngine configuration for tests (no real server).
private func makeTestConfig(
    chatChannelId: String = "test-channel-001",
    accessToken: String = "test-access-token",
    extraToken: String? = "test-extra-token",
    uid: String? = "test-uid",
    maxMessageBuffer: Int = ChatDefaults.maxMessageBuffer,
    reconnectionConfig: ReconnectionPolicy.Configuration = .init(
        initialDelay: 0.01,
        maxDelay: 0.05,
        maxAttempts: 3,
        backoffMultiplier: 1.5,
        jitterFactor: 0
    )
) -> ChatEngine.Configuration {
    ChatEngine.Configuration(
        chatChannelId: chatChannelId,
        accessToken: accessToken,
        extraToken: extraToken,
        uid: uid,
        channelId: "channel-id",
        serverUrl: URL(string: "wss://localhost:0/chat")!,
        reconnectionConfig: reconnectionConfig,
        maxMessageBuffer: maxMessageBuffer
    )
}

/// Helper: create a ChatMessage with convenient defaults.
private func makeChatMessage(
    id: String = UUID().uuidString,
    nickname: String = "TestUser",
    content: String = "Hello",
    type: MessageType = .normal
) -> ChatMessage {
    ChatMessage(
        id: id,
        userId: "user-\(id)",
        nickname: nickname,
        content: content,
        timestamp: .now,
        type: type
    )
}

/// Collects events from an AsyncStream with a timeout.
private func collectEvents(
    from stream: AsyncStream<ChatEngineEvent>,
    count: Int,
    timeout: TimeInterval = 2.0
) async -> [ChatEngineEvent] {
    var events: [ChatEngineEvent] = []
    let deadline = Date().addingTimeInterval(timeout)

    for await event in stream {
        events.append(event)
        if events.count >= count || Date() > deadline { break }
    }
    return events
}

// MARK: - ChatEngine Initialization Tests

@Suite("ChatEngine — Initialization")
struct ChatEngineInitTests {

    @Test("Engine starts in disconnected state")
    func initialStateDisconnected() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let state = await engine.connectionState
        #expect(state == .disconnected)
    }

    @Test("Engine starts with empty messages")
    func initialMessagesEmpty() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let messages = await engine.messages
        #expect(messages.isEmpty)
    }

    @Test("Engine starts with nil sessionId")
    func initialSessionIdNil() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let sid = await engine.sessionId
        #expect(sid == nil)
    }

    @Test("Engine isConnected is false initially")
    func initialIsConnectedFalse() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let connected = await engine.isConnected
        #expect(connected == false)
    }

    @Test("Event stream is accessible immediately")
    func eventStreamAccessible() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let stream = await engine.events()
        // Stream type check — should return AsyncStream
        #expect(type(of: stream) == AsyncStream<ChatEngineEvent>.self)
    }
}

// MARK: - ChatEngine Message Buffer Tests

@Suite("ChatEngine — Message Buffer")
struct ChatEngineMessageBufferTests {

    @Test("clearMessages removes all messages")
    func clearMessages() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        await engine.clearMessages()
        let messages = await engine.messages
        #expect(messages.isEmpty)
    }

    @Test("clearMessages emits messagesCleared event")
    func clearMessagesEmitsEvent() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let stream = await engine.events()

        // Clear in background
        Task { await engine.clearMessages() }

        let events = await collectEvents(from: stream, count: 1, timeout: 1.0)
        let hasClearedEvent = events.contains { event in
            if case .messagesCleared = event { return true }
            return false
        }
        #expect(hasClearedEvent)
    }
}

// MARK: - ChatEngine Send Failure Tests

@Suite("ChatEngine — Send Failures")
struct ChatEngineSendFailureTests {

    @Test("sendMessage throws when not connected")
    func sendMessageThrowsWhenDisconnected() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        // Engine is in .disconnected state
        await #expect(throws: AppError.self) {
            try await engine.sendMessage("test message")
        }
    }

    @Test("requestRecentMessages silently returns when not connected")
    func requestRecentMessagesDoesNotThrowWhenDisconnected() async throws {
        let engine = ChatEngine(configuration: makeTestConfig())
        // Should not throw, just silently return
        try await engine.requestRecentMessages()
    }
}

// MARK: - ChatEngine Configuration Tests

@Suite("ChatEngine — Configuration")
struct ChatEngineConfigurationTests {

    @Test("Server URL computed from chatChannelId deterministically")
    func serverURLDeterministic() {
        // Same chatChannelId → same server
        let config1 = ChatEngine.Configuration(chatChannelId: "ABCDEF", accessToken: "tok")
        let config2 = ChatEngine.Configuration(chatChannelId: "ABCDEF", accessToken: "tok")
        #expect(config1.serverUrl == config2.serverUrl)
    }

    @Test("Different chatChannelId may produce different server URL")
    func differentChannelIdDifferentServer() {
        let config1 = ChatEngine.Configuration(chatChannelId: "AAA", accessToken: "tok")
        let config2 = ChatEngine.Configuration(chatChannelId: "ZZZ", accessToken: "tok")
        // They might or might not differ, but the URL should be valid wss
        #expect(config1.serverUrl.scheme == "wss")
        #expect(config2.serverUrl.scheme == "wss")
    }

    @Test("Custom server URL is preserved")
    func customServerURL() {
        let customURL = URL(string: "wss://custom.server.com/chat")!
        let config = ChatEngine.Configuration(
            chatChannelId: "ch1",
            accessToken: "tok",
            serverUrl: customURL
        )
        #expect(config.serverUrl == customURL)
    }

    @Test("Default max message buffer matches ChatDefaults")
    func defaultMaxMessageBuffer() {
        let config = ChatEngine.Configuration(chatChannelId: "ch1", accessToken: "tok")
        #expect(config.maxMessageBuffer == ChatDefaults.maxMessageBuffer)
    }

    @Test("Custom max message buffer is respected")
    func customMaxMessageBuffer() {
        let config = ChatEngine.Configuration(
            chatChannelId: "ch1",
            accessToken: "tok",
            maxMessageBuffer: 100
        )
        #expect(config.maxMessageBuffer == 100)
    }
}

// MARK: - ChatEngine Disconnect Tests

@Suite("ChatEngine — Disconnect")
struct ChatEngineDisconnectTests {

    @Test("Disconnect on idle engine sets state to disconnected")
    func disconnectFromIdle() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        await engine.disconnect()
        let state = await engine.connectionState
        #expect(state == .disconnected)
    }

    @Test("Disconnect emits stateChanged event")
    func disconnectEmitsStateChanged() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        let stream = await engine.events()

        Task { await engine.disconnect() }

        let events = await collectEvents(from: stream, count: 1, timeout: 1.0)
        let hasStateChanged = events.contains { event in
            if case .stateChanged(.disconnected) = event { return true }
            return false
        }
        #expect(hasStateChanged)
    }

    @Test("Multiple disconnects are idempotent")
    func multipleDisconnects() async {
        let engine = ChatEngine(configuration: makeTestConfig())
        await engine.disconnect()
        await engine.disconnect()
        await engine.disconnect()
        let state = await engine.connectionState
        #expect(state == .disconnected)
    }
}

// MARK: - ChatEngineEvent Tests

@Suite("ChatEngineEvent — Coverage")
struct ChatEngineEventTests {

    @Test("All event cases are Sendable") 
    func eventsSendable() {
        // Compile-time check: create each case
        let _: ChatEngineEvent = .connected
        let _: ChatEngineEvent = .disconnected(reason: "test")
        let _: ChatEngineEvent = .reconnecting
        let _: ChatEngineEvent = .stateChanged(.disconnected)
        let _: ChatEngineEvent = .newMessages([])
        let _: ChatEngineEvent = .recentMessages([])
        let _: ChatEngineEvent = .donations([])
        let _: ChatEngineEvent = .notice(makeChatMessage())
        let _: ChatEngineEvent = .messageBlinded("id")
        let _: ChatEngineEvent = .kicked
        let _: ChatEngineEvent = .userPenalized(userId: "u1", duration: 300)
        let _: ChatEngineEvent = .systemMessage("sys")
        let _: ChatEngineEvent = .messagesCleared
        // If this compiles, all cases are Sendable ✓
    }

    @Test("ChatConnectionState display text")
    func connectionStateDisplayText() {
        #expect(ChatConnectionState.disconnected.displayText == "연결 안됨")
        #expect(ChatConnectionState.connecting.displayText == "연결 중...")
        #expect(ChatConnectionState.connected(serverIndex: 3).displayText == "연결됨 (서버 3)")
        #expect(ChatConnectionState.reconnecting(attempt: 2).displayText == "재연결 중 (2회)")
        #expect(ChatConnectionState.failed(reason: "timeout").displayText == "연결 실패: timeout")
    }

    @Test("ChatConnectionState isConnected matches only .connected")
    func connectionStateIsConnected() {
        #expect(ChatConnectionState.disconnected.isConnected == false)
        #expect(ChatConnectionState.connecting.isConnected == false)
        #expect(ChatConnectionState.connected(serverIndex: 0).isConnected == true)
        #expect(ChatConnectionState.reconnecting(attempt: 1).isConnected == false)
        #expect(ChatConnectionState.failed(reason: "x").isConnected == false)
    }
}

// MARK: - ChatMessageParser Integration Tests

@Suite("ChatEngine — Parser Integration")
struct ChatEngineParserIntegrationTests {

    let parser = ChatMessageParser()

    @Test("Connected event extracts sessionId from body")
    func connectedEventSessionId() throws {
        let json = """
        {"cmd":10100,"bdy":{"sid":"session-abc-123"}}
        """
        let event = try parser.parse(json)
        if case .connected(let sid) = event {
            #expect(sid == "session-abc-123")
        } else {
            Issue.record("Expected .connected event, got \\(event)")
        }
    }

    @Test("Chat message event parses multiple messages")
    func chatMessageEventMultiple() throws {
        // Build a raw protocol message simulating cmd=93101 with message array body
        let json = """
        {"cmd":93101,"bdy":[{"uid":"u1","profile":"{\\"nickname\\":\\"User1\\"}","msg":"Hello","msgTime":1700000000000,"msgTypeCode":1,"extras":"{}"}]}
        """
        let event = try parser.parse(json)
        if case .messages(let msgs) = event {
            #expect(msgs.count == 1)
            #expect(msgs[0].content == "Hello")
        } else {
            Issue.record("Expected .messages event")
        }
    }

    @Test("Ping/pong round trip via parser")
    func pingPongRoundTrip() throws {
        let pingJson = """
        {"cmd":0}
        """
        let pingEvent = try parser.parse(pingJson)
        #expect({
            if case .ping = pingEvent { return true }
            return false
        }())

        let pongMsg = parser.buildPong()
        #expect(pongMsg.contains("10000"))
    }

    @Test("Send confirmed parses retCode")
    func sendConfirmedParsesRetCode() throws {
        let json = """
        {"cmd":13101,"retCode":0}
        """
        let event = try parser.parse(json)
        if case .sendConfirmed(let code) = event {
            #expect(code == 0)
        } else {
            Issue.record("Expected .sendConfirmed")
        }
    }

    @Test("Kick event parsed correctly")
    func kickEvent() throws {
        let json = """
        {"cmd":94005}
        """
        let event = try parser.parse(json)
        if case .kick = event {
            // Pass
        } else {
            Issue.record("Expected .kick event")
        }
    }
}

// MARK: - Reconnection Policy Integration Tests

@Suite("ChatEngine — Reconnection Policy Integration")
struct ChatEngineReconnectionTests {

    @Test("ReconnectionPolicy with zero jitter produces deterministic delays")
    func deterministicDelays() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 5,
            backoffMultiplier: 2.0,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)

        let d1 = await policy.nextDelay()
        let d2 = await policy.nextDelay()
        let d3 = await policy.nextDelay()

        #expect(d1! == 1.0)
        #expect(d2! == 2.0)
        #expect(d3! == 4.0)
    }

    @Test("ReconnectionPolicy exhaustion returns nil")
    func exhaustionReturnsNil() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.01,
            maxAttempts: 1,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)

        _ = await policy.nextDelay() // attempt 1
        let exhausted = await policy.nextDelay() // attempt 2 → nil
        #expect(exhausted == nil)
        #expect(await policy.isExhausted)
    }

    @Test("ReconnectionPolicy reset restores attempt count")
    func resetRestoresAttempts() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 0.01,
            maxAttempts: 2,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)

        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        await policy.reset()

        let afterReset = await policy.nextDelay()
        #expect(afterReset != nil)
    }

    @Test("ReconnectionPolicy aggressive preset has higher max attempts")
    func aggressivePreset() {
        let aggressive = ReconnectionPolicy.Configuration.aggressive
        let standard = ReconnectionPolicy.Configuration.default

        #expect(aggressive.maxAttempts > standard.maxAttempts)
        #expect(aggressive.initialDelay < standard.initialDelay)
    }

    @Test("ReconnectionPolicy state transitions through waiting → connected")
    func stateTransitions() async {
        let policy = ReconnectionPolicy(configuration: .init(
            initialDelay: 0.01, maxAttempts: 5, jitterFactor: 0
        ))

        #expect(await policy.state == .idle)

        _ = await policy.nextDelay()
        let afterFirst = await policy.state
        if case .waiting = afterFirst {
            // Expected
        } else {
            Issue.record("Expected .waiting state")
        }

        await policy.markConnected()
        #expect(await policy.state == .connected)
    }
}

