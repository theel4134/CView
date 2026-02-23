// MARK: - CViewChatTests.swift
// CViewChat module tests

import Testing
import Foundation
@testable import CViewChat
@testable import CViewCore

// MARK: - Chat Message Parser Tests

@Suite("ChatMessageParser")
struct ChatMessageParserTests {
    
    let parser = ChatMessageParser()
    
    @Test("Parse connect message")
    func parseConnect() throws {
        let json = """
        {"cmd":10100,"bdy":{"sid":"session-123"},"retCode":0}
        """
        
        let event = try parser.parse(json)
        
        if case .connected(let sessionId) = event {
            #expect(sessionId == "session-123")
        } else {
            Issue.record("Expected connected event")
        }
    }
    
    @Test("Parse ping message")
    func parsePing() throws {
        let json = """
        {"cmd":0}
        """
        
        let event = try parser.parse(json)
        
        if case .ping = event {
            // Expected
        } else {
            Issue.record("Expected ping event")
        }
    }
    
    @Test("Build connect message contains required fields")
    func buildConnect() {
        let msg = parser.buildConnectMessage(
            chatChannelId: "channel-123",
            accessToken: "token-abc",
            uid: "user-456"
        )
        
        #expect(msg.contains("channel-123"))
        #expect(msg.contains("token-abc"))
        #expect(msg.contains("100")) // connect command
    }
    
    @Test("Build pong message")
    func buildPong() {
        let pong = parser.buildPong()
        #expect(pong.contains("10000"))
    }
    
    @Test("Build send message contains text")
    func buildSend() {
        let msg = parser.buildSendMessage(
            chatChannelId: "ch-1",
            message: "Hello World"
        )
        
        #expect(msg.contains("Hello World"))
        #expect(msg.contains("3101")) // sendChat command
    }
    
    @Test("Parse unknown command returns unknown event")
    func unknownCommand() throws {
        let json = """
        {"cmd":99999}
        """
        
        let event = try parser.parse(json)
        
        if case .unknown(let cmd) = event {
            #expect(cmd == 99999)
        } else {
            Issue.record("Expected unknown event")
        }
    }
    
    @Test("Invalid JSON throws error")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try parser.parse("not valid json")
        }
    }
}

// MARK: - Chat Command Code Tests

@Suite("ChzzkChatCommand")
struct ChzzkChatCommandTests {
    
    @Test("Ping command is 0")
    func pingCommand() {
        #expect(ChzzkChatCommand.ping.rawValue == 0)
    }
    
    @Test("Connect command is 100")
    func connectCommand() {
        #expect(ChzzkChatCommand.connect.rawValue == 100)
    }
    
    @Test("SendChat command is 3101")
    func sendChatCommand() {
        #expect(ChzzkChatCommand.sendChat.rawValue == 3101)
    }
    
    @Test("Connected command is 10100")
    func connectedCommand() {
        #expect(ChzzkChatCommand.connected.rawValue == 10100)
    }
    
    @Test("ChatMessage command is 93101")
    func chatMessageCommand() {
        #expect(ChzzkChatCommand.chatMessage.rawValue == 93101)
    }
    
    @Test("All cases are iterable")
    func allCases() {
        #expect(ChzzkChatCommand.allCases.isEmpty == false)
    }
}

// MARK: - Reconnection Policy Tests

@Suite("ReconnectionPolicy")
struct ReconnectionPolicyTests {
    
    @Test("First delay equals initial delay approximately")
    func firstDelay() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            jitterFactor: 0 // No jitter for predictable test
        )
        let policy = ReconnectionPolicy(configuration: config)
        
        let delay = await policy.nextDelay()
        #expect(delay != nil)
        #expect(abs(delay! - 1.0) < 0.01)
    }
    
    @Test("Delay increases with attempts")
    func exponentialBackoff() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 1.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)
        
        let firstDelay = await policy.nextDelay()!
        let secondDelay = await policy.nextDelay()!
        
        #expect(secondDelay > firstDelay)
    }
    
    @Test("Delay capped at max")
    func maxDelayCap() async {
        let config = ReconnectionPolicy.Configuration(
            initialDelay: 10.0,
            maxDelay: 15.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)
        
        // First: 10, Second: 15 (capped), Third: 15 (capped)
        _ = await policy.nextDelay()
        let second = await policy.nextDelay()!
        
        #expect(second <= 15.0)
    }
    
    @Test("Returns nil after max attempts")
    func maxAttempts() async {
        let config = ReconnectionPolicy.Configuration(
            maxAttempts: 2,
            jitterFactor: 0
        )
        let policy = ReconnectionPolicy(configuration: config)
        
        _ = await policy.nextDelay()  // 1
        _ = await policy.nextDelay()  // 2
        let third = await policy.nextDelay()  // nil
        
        #expect(third == nil)
    }
    
    @Test("Mark connected resets state")
    func markConnected() async {
        let policy = ReconnectionPolicy(configuration: .default)
        
        _ = await policy.nextDelay()
        _ = await policy.nextDelay()
        
        await policy.markConnected()
        
        #expect(await policy.shouldReconnect == true)
        #expect(await policy.state == .connected)
    }
}

// MARK: - Chat Message Tests

@Suite("ChatMessage")
struct ChatMessageTests {
    
    @Test("Message stores properties correctly")
    func messageProperties() {
        let now = Date()
        let message = ChatMessage(
            id: "msg-1",
            userId: "user-1",
            nickname: "TestUser",
            content: "Hello, world!",
            timestamp: now,
            type: .normal,
            profile: nil,
            extras: nil
        )
        
        #expect(message.id == "msg-1")
        #expect(message.userId == "user-1")
        #expect(message.nickname == "TestUser")
        #expect(message.content == "Hello, world!")
        #expect(message.timestamp == now)
    }
    
    @Test("Message with donation extras")
    func messageWithExtras() {
        let extras = ChatExtras(donation: DonationInfo(amount: 1000))
        let message = ChatMessage(
            id: "msg-2",
            userId: "user-2",
            nickname: "Donor",
            content: "donation message",
            timestamp: Date(),
            type: .donation,
            profile: nil,
            extras: extras
        )
        
        #expect(message.content == "donation message")
        #expect(message.extras?.donation?.amount == 1000)
    }
}

// MARK: - AnyCodable Tests

@Suite("AnyCodable")
struct AnyCodableTests {
    
    @Test("Decode string")
    func decodeString() throws {
        let json = "\"hello\"".data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodable.self, from: json)
        #expect(value.stringValue == "hello")
    }
    
    @Test("Decode integer")
    func decodeInt() throws {
        let json = "42".data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodable.self, from: json)
        #expect(value.intValue == 42)
    }
    
    @Test("Decode null")
    func decodeNull() throws {
        let json = "null".data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodable.self, from: json)
        if case .null = value {
            // Expected
        } else {
            Issue.record("Expected null")
        }
    }
}
