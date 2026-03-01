// MARK: - ChatMessageParserTests.swift
// Comprehensive unit tests for ChatMessageParser

import Testing
import Foundation
@testable import CViewChat
@testable import CViewCore

/// Escape a JSON string so it can be safely embedded inside another JSON string value.
/// e.g. `{"key":"value"}` → `{\"key\":\"value\"}`
private func jsonEscape(_ str: String) -> String {
    str.replacingOccurrences(of: "\\", with: "\\\\")
       .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - Parse Raw Protocol Messages

@Suite("ChatMessageParser — Raw Parsing")
struct ChatMessageParserRawTests {

    let parser = ChatMessageParser()

    @Test("parseRaw extracts cmd field")
    func parseRawCmd() throws {
        let json = """
        {"cmd":93101}
        """
        let raw = try parser.parseRaw(json)
        #expect(raw.cmd == 93101)
    }

    @Test("parseRaw extracts all top-level fields")
    func parseRawAllFields() throws {
        let json = """
        {"cmd":100,"tid":1,"svcid":"game","cid":"ch1","retCode":0,"retMsg":"OK"}
        """
        let raw = try parser.parseRaw(json)
        #expect(raw.cmd == 100)
        #expect(raw.tid == 1)
        #expect(raw.svcid == "game")
        #expect(raw.cid == "ch1")
        #expect(raw.retCode == 0)
        #expect(raw.retMsg == "OK")
    }

    @Test("parseRaw with body as dictionary")
    func parseRawBodyDict() throws {
        let json = """
        {"cmd":10100,"bdy":{"sid":"abc"}}
        """
        let raw = try parser.parseRaw(json)
        #expect(raw.bdy?.dictValue?["sid"]?.stringValue == "abc")
    }

    @Test("parseRaw with body as array")
    func parseRawBodyArray() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"hello","uid":"u1","msgTime":1000}]}
        """
        let raw = try parser.parseRaw(json)
        #expect(raw.bdy?.arrayValue?.count == 1)
    }

    @Test("parseRaw with no body returns nil bdy")
    func parseRawNoBody() throws {
        let json = """
        {"cmd":0}
        """
        let raw = try parser.parseRaw(json)
        #expect(raw.bdy == nil)
    }

    @Test("parseRaw throws on empty string")
    func parseRawEmpty() {
        #expect(throws: (any Error).self) {
            _ = try parser.parseRaw("")
        }
    }

    @Test("parseRaw throws on non-JSON string")
    func parseRawNonJSON() {
        #expect(throws: (any Error).self) {
            _ = try parser.parseRaw("this is not json")
        }
    }

    @Test("parseRaw throws on JSON without cmd field")
    func parseRawMissingCmd() {
        #expect(throws: (any Error).self) {
            _ = try parser.parseRaw("{\"bdy\":{}}")
        }
    }

    @Test("parseRaw throws on JSON array (not object)")
    func parseRawArrayRoot() {
        #expect(throws: (any Error).self) {
            _ = try parser.parseRaw("[1,2,3]")
        }
    }

    @Test("parseRaw with unicode content")
    func parseRawUnicode() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"안녕하세요 🎉","uid":"u1","msgTime":1000}]}
        """
        let raw = try parser.parseRaw(json)
        let firstMsg = raw.bdy?.arrayValue?.first?.dictValue?["msg"]?.stringValue
        #expect(firstMsg == "안녕하세요 🎉")
    }
}

// MARK: - Parse Domain Events — Chat Messages

@Suite("ChatMessageParser — Chat Messages")
struct ChatMessageParserChatTests {

    let parser = ChatMessageParser()

    @Test("Parse single chat message with profile as dict")
    func parseSingleChatWithProfile() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"Hello!","uid":"user1","msgTime":1700000000000,"profile":{"nickname":"TestUser","profileImageUrl":"https://img.example.com/pic.jpg","userRoleCode":"common"},"extras":"{}"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event, got \(event)")
            return
        }
        #expect(messages.count == 1)
        #expect(messages[0].content == "Hello!")
        #expect(messages[0].nickname == "TestUser")
        #expect(messages[0].userId == "user1")
    }

    @Test("Parse multiple chat messages in single batch")
    func parseMultipleMessages() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"msg1","uid":"u1","msgTime":1000},{"msg":"msg2","uid":"u2","msgTime":2000},{"msg":"msg3","uid":"u3","msgTime":3000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages.count == 3)
        #expect(messages[0].content == "msg1")
        #expect(messages[1].content == "msg2")
        #expect(messages[2].content == "msg3")
    }

    @Test("Parse chat message with empty msg field")
    func parseEmptyMessage() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"","uid":"u1","msgTime":1000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages.count == 1)
        #expect(messages[0].content == "")
    }

    @Test("Parse chat message with missing msg field defaults to empty")
    func parseMissingMsg() throws {
        let json = """
        {"cmd":93101,"bdy":[{"uid":"u1","msgTime":1000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].content == "")
    }

    @Test("Parse chat message with missing uid defaults to empty")
    func parseMissingUid() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"hi","msgTime":1000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        // uid defaults to "" so id is generated from UUID
        #expect(messages[0].content == "hi")
    }

    @Test("Parse chat message with empty body array returns empty messages")
    func parseEmptyBodyArray() throws {
        let json = """
        {"cmd":93101,"bdy":[]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages.isEmpty)
    }

    @Test("Parse chat message timestamp conversion")
    func parseTimestamp() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"test","uid":"u1","msgTime":1700000000000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        let expectedDate = Date(timeIntervalSince1970: 1700000000.0)
        #expect(abs(messages[0].timestamp.timeIntervalSince(expectedDate)) < 1.0)
    }

    @Test("Parse chat message with no body returns empty messages")
    func parseNoBody() throws {
        let json = """
        {"cmd":93101}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages.isEmpty)
    }
}

// MARK: - Parse Domain Events — Donations

@Suite("ChatMessageParser — Donations")
struct ChatMessageParserDonationTests {

    let parser = ChatMessageParser()

    @Test("Parse donation message with amount")
    func parseDonation() throws {
        let extrasJson = #"{"payAmount":1000,"donationType":"CHAT","chatType":"STREAMING"}"#
        let json = """
        {"cmd":93102,"bdy":[{"msg":"donation msg","uid":"donor1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .donations(let messages) = event else {
            Issue.record("Expected .donations event, got \(event)")
            return
        }
        #expect(messages.count == 1)
        #expect(messages[0].content == "donation msg")
        #expect(messages[0].type == .donation)
        #expect(messages[0].extras?.donation?.amount == 1000)
        #expect(messages[0].extras?.donation?.currency == "KRW")
    }

    @Test("Parse donation with zero amount treated as normal")
    func parseDonationZeroAmount() throws {
        let extrasJson = #"{"payAmount":0,"chatType":"STREAMING"}"#
        let json = """
        {"cmd":93102,"bdy":[{"msg":"not a real donation","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .donations(let messages) = event else {
            Issue.record("Expected .donations event")
            return
        }
        #expect(messages.count == 1)
        // payAmount 0 should not flag as donation
        #expect(messages[0].type == .normal)
    }
}

// MARK: - Parse Domain Events — Profile & Badges

@Suite("ChatMessageParser — Profiles & Badges")
struct ChatMessageParserProfileTests {

    let parser = ChatMessageParser()

    @Test("Parse profile from JSON string in extras")
    func parseProfileJsonString() throws {
        let profileJson = #"{"nickname":"StreamerNick","profileImageUrl":"https://img.example.com/avatar.jpg","userRoleCode":"streamer"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"hi","uid":"u1","msgTime":1000,"profile":"\(jsonEscape(profileJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].nickname == "StreamerNick")
        #expect(messages[0].profile?.userRoleCode == "streamer")
    }

    @Test("Parse profile with manager role")
    func parseManagerProfile() throws {
        let profileJson = #"{"nickname":"ManagerNick","userRoleCode":"streaming_chat_manager"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"hi","uid":"u1","msgTime":1000,"profile":"\(jsonEscape(profileJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].nickname == "ManagerNick")
        #expect(messages[0].profile?.userRoleCode == "manager")
    }

    @Test("Parse profile with no profile data defaults to Unknown")
    func parseNoProfile() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"anonymous","uid":"u1","msgTime":1000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].nickname == "Unknown")
    }

    @Test("Parse profile with badge dict")
    func parseBadge() throws {
        let json = """
        {"cmd":93101,"bdy":[{"msg":"badged","uid":"u1","msgTime":1000,"profile":{"nickname":"BadgeUser","badge":{"subscriber":"https://badge.example.com/sub.png"}}}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].profile?.badge != nil)
        #expect(messages[0].profile?.badge?.imageURL?.absoluteString == "https://badge.example.com/sub.png")
    }
}

// MARK: - Parse Domain Events — Emoji Parsing

@Suite("ChatMessageParser — Emojis")
struct ChatMessageParserEmojiTests {

    let parser = ChatMessageParser()

    @Test("Parse extras with emoji map")
    func parseEmojis() throws {
        let extrasJson = #"{"emojis":{"happy_emote":"https://emoji.example.com/happy.png","sad_emote":"https://emoji.example.com/sad.png"},"chatType":"STREAMING"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"{:happy_emote:} {:sad_emote:}","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].extras?.emojis?.count == 2)
        #expect(messages[0].extras?.emojis?["happy_emote"] == "https://emoji.example.com/happy.png")
    }

    @Test("Parse extras with empty emojis map results in nil")
    func parseEmptyEmojis() throws {
        let extrasJson = #"{"emojis":{},"chatType":"STREAMING"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"no emojis","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        // Empty emoji dict should become nil
        #expect(messages[0].extras?.emojis == nil)
    }

    @Test("Parse extras with no emojis key")
    func parseNoEmojis() throws {
        let extrasJson = #"{"chatType":"STREAMING"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"text","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].extras?.emojis == nil)
    }
}

// MARK: - Parse Domain Events — Other Event Types

@Suite("ChatMessageParser — Event Types")
struct ChatMessageParserEventTypeTests {

    let parser = ChatMessageParser()

    @Test("Parse connected event extracts session ID")
    func parseConnected() throws {
        let json = """
        {"cmd":10100,"bdy":{"sid":"sess-xyz-789"}}
        """
        let event = try parser.parse(json)
        guard case .connected(let sid) = event else {
            Issue.record("Expected .connected event")
            return
        }
        #expect(sid == "sess-xyz-789")
    }

    @Test("Parse connected with no sid defaults to empty")
    func parseConnectedNoSid() throws {
        let json = """
        {"cmd":10100,"bdy":{}}
        """
        let event = try parser.parse(json)
        guard case .connected(let sid) = event else {
            Issue.record("Expected .connected event")
            return
        }
        #expect(sid == "")
    }

    @Test("Parse recent chat message returns recentMessages")
    func parseRecentChat() throws {
        let json = """
        {"cmd":15101,"bdy":{"messageList":[{"msg":"recent1","uid":"u1","msgTime":1000},{"msg":"recent2","uid":"u2","msgTime":2000}]}}
        """
        let event = try parser.parse(json)
        guard case .recentMessages(let messages) = event else {
            Issue.record("Expected .recentMessages event, got \(event)")
            return
        }
        #expect(messages.count == 2)
    }

    @Test("Parse notice event")
    func parseNotice() throws {
        let json = """
        {"cmd":94010,"bdy":{"msg":"This is a notice"}}
        """
        let event = try parser.parse(json)
        guard case .notice(let message) = event else {
            Issue.record("Expected .notice event, got \(event)")
            return
        }
        #expect(message.content == "This is a notice")
        #expect(message.type == .notice)
    }

    @Test("Parse blind event extracts messageId and userId")
    func parseBlind() throws {
        let json = """
        {"cmd":94008,"bdy":{"messageId":"msg-123","userId":"user-456"}}
        """
        let event = try parser.parse(json)
        guard case .blind(let msgId, let userId) = event else {
            Issue.record("Expected .blind event, got \(event)")
            return
        }
        #expect(msgId == "msg-123")
        #expect(userId == "user-456")
    }

    @Test("Parse kick event")
    func parseKick() throws {
        let json = """
        {"cmd":94005}
        """
        let event = try parser.parse(json)
        guard case .kick = event else {
            Issue.record("Expected .kick event, got \(event)")
            return
        }
    }

    @Test("Parse penalty event extracts userId and duration")
    func parsePenalty() throws {
        let json = """
        {"cmd":94015,"bdy":{"targetUserId":"bad-user","duration":300}}
        """
        let event = try parser.parse(json)
        guard case .penalty(let userId, let duration) = event else {
            Issue.record("Expected .penalty event, got \(event)")
            return
        }
        #expect(userId == "bad-user")
        #expect(duration == 300)
    }

    @Test("Parse pong event")
    func parsePong() throws {
        let json = """
        {"cmd":10000}
        """
        let event = try parser.parse(json)
        guard case .pong = event else {
            Issue.record("Expected .pong event, got \(event)")
            return
        }
    }

    @Test("Parse sendChatResponse success")
    func parseSendConfirmed() throws {
        let json = """
        {"cmd":13101,"retCode":0,"retMsg":"OK"}
        """
        let event = try parser.parse(json)
        guard case .sendConfirmed(let retCode) = event else {
            Issue.record("Expected .sendConfirmed event")
            return
        }
        #expect(retCode == 0)
    }

    @Test("Parse sendChatResponse error code")
    func parseSendError() throws {
        let json = """
        {"cmd":13101,"retCode":-1,"retMsg":"error"}
        """
        let event = try parser.parse(json)
        guard case .sendConfirmed(let retCode) = event else {
            Issue.record("Expected .sendConfirmed event")
            return
        }
        #expect(retCode == -1)
    }

    @Test("Parse system message event")
    func parseSystemMessage() throws {
        let json = """
        {"cmd":93006,"bdy":{"msg":"System: maintenance in 5 min"}}
        """
        let event = try parser.parse(json)
        guard case .system(let message) = event else {
            Issue.record("Expected .system event, got \(event)")
            return
        }
        #expect(message == "System: maintenance in 5 min")
    }

    @Test("Parse emote message returns messages event")
    func parseEmoteMessage() throws {
        let json = """
        {"cmd":93103,"bdy":[{"msg":"emote","uid":"u1","msgTime":1000}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event for emote, got \(event)")
            return
        }
        #expect(messages.count == 1)
    }

    @Test("Parse unknown command returns unknown event with cmd")
    func parseUnknown() throws {
        let json = """
        {"cmd":12345}
        """
        let event = try parser.parse(json)
        guard case .unknown(let cmd) = event else {
            Issue.record("Expected .unknown event")
            return
        }
        #expect(cmd == 12345)
    }
}

// MARK: - Subscription / System Message Types via Extras

@Suite("ChatMessageParser — Subscription & System Extras")
struct ChatMessageParserExtrasTypeTests {

    let parser = ChatMessageParser()

    @Test("Parse subscription message type from extras chatType")
    func parseSubscription() throws {
        let extrasJson = #"{"chatType":"SUBSCRIPTION"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"subscribed!","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].type == .subscription)
    }

    @Test("Parse system message type from extras chatType")
    func parseSystemType() throws {
        let extrasJson = #"{"chatType":"SYSTEM"}"#
        let json = """
        {"cmd":93101,"bdy":[{"msg":"system notice","uid":"u1","msgTime":1000,"extras":"\(jsonEscape(extrasJson))"}]}
        """
        let event = try parser.parse(json)
        guard case .messages(let messages) = event else {
            Issue.record("Expected .messages event")
            return
        }
        #expect(messages[0].type == .systemMessage)
    }
}

// MARK: - Build Message Tests

@Suite("ChatMessageParser — Build Messages")
struct ChatMessageParserBuildTests {

    let parser = ChatMessageParser()

    @Test("buildConnectMessage contains all required fields")
    func buildConnect() {
        let msg = parser.buildConnectMessage(chatChannelId: "ch-abc", accessToken: "tok-123", uid: "uid-456")
        #expect(msg.contains("ch-abc"))
        #expect(msg.contains("tok-123"))
        #expect(msg.contains("uid-456"))
        #expect(msg.contains("\"cmd\":100"))
        #expect(msg.contains("\"svcid\":\"game\""))
        #expect(msg.contains("SEND")) // auth: SEND when uid provided
    }

    @Test("buildConnectMessage with nil uid uses READ auth")
    func buildConnectAnonymous() {
        let msg = parser.buildConnectMessage(chatChannelId: "ch-abc", accessToken: "tok")
        #expect(msg.contains("READ"))
    }

    @Test("buildSendMessage includes message text and command")
    func buildSend() {
        let msg = parser.buildSendMessage(chatChannelId: "ch-1", message: "Hello World!")
        #expect(msg.contains("Hello World!"))
        #expect(msg.contains("3101"))
    }

    @Test("buildSendMessage with emojis includes emojis")
    func buildSendWithEmojis() {
        let emojis = ["smile": "https://emoji.com/smile.png"]
        let msg = parser.buildSendMessage(chatChannelId: "ch-1", message: ":smile:", emojis: emojis)
        #expect(msg.contains("smile"))
        #expect(msg.contains("emoji.com") && msg.contains("smile.png"))
    }

    @Test("buildRecentChatRequest contains correct command")
    func buildRecentChat() {
        let msg = parser.buildRecentChatRequest(chatChannelId: "ch-1")
        #expect(msg.contains("5101"))
        #expect(msg.contains("ch-1"))
    }

    @Test("buildPong returns valid JSON with pong command")
    func buildPong() {
        let pong = parser.buildPong()
        #expect(pong.contains("10000"))
        #expect(pong.contains("\"ver\":\"3\""))
    }
}

// MARK: - AnyCodable Extended Tests

@Suite("AnyCodable — Extended")
struct AnyCodableExtendedTests {

    @Test("from() converts dictionary")
    func fromDict() {
        let dict: [String: Any] = ["key": "value", "num": 42]
        let result = AnyCodable.from(dict)
        #expect(result.dictValue?["key"]?.stringValue == "value")
        #expect(result.dictValue?["num"]?.intValue == 42)
    }

    @Test("from() converts nested array")
    func fromArray() {
        let array: [Any] = ["a", "b", 3]
        let result = AnyCodable.from(array)
        #expect(result.arrayValue?.count == 3)
        #expect(result.arrayValue?[0].stringValue == "a")
        #expect(result.arrayValue?[2].intValue == 3)
    }

    @Test("from() converts NSNull to .null")
    func fromNSNull() {
        let result = AnyCodable.from(NSNull())
        if case .null = result {
            // expected
        } else {
            Issue.record("Expected .null")
        }
    }

    @Test("from() converts boolean correctly")
    func fromBool() {
        let trueResult = AnyCodable.from(true as NSNumber)
        let falseResult = AnyCodable.from(false as NSNumber)
        if case .bool(let v) = trueResult { #expect(v == true) }
        else { Issue.record("Expected .bool(true)") }
        if case .bool(let v) = falseResult { #expect(v == false) }
        else { Issue.record("Expected .bool(false)") }
    }

    @Test("Decode and encode round-trip for dictionary")
    func roundTrip() throws {
        let json = """
        {"name":"test","count":5,"active":true,"tags":["a","b"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: json)
        let encoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        #expect(reDecoded.dictValue?["name"]?.stringValue == "test")
    }

    @Test("Decode double value")
    func decodeDouble() throws {
        let json = "3.14".data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodable.self, from: json)
        // Note: JSONDecoder may decode as Int if it's a whole number, or Double
        if case .double(let d) = value {
            #expect(abs(d - 3.14) < 0.001)
        } else if case .int = value {
            Issue.record("3.14 should decode as double, not int")
        }
    }

    @Test("Decode array value")
    func decodeArray() throws {
        let json = "[1,2,3]".data(using: .utf8)!
        let value = try JSONDecoder().decode(AnyCodable.self, from: json)
        #expect(value.arrayValue?.count == 3)
    }
}

// MARK: - ChzzkChatCommand Extended Tests

@Suite("ChzzkChatCommand — Extended")
struct ChzzkChatCommandExtendedTests {

    @Test("All raw values are unique")
    func uniqueRawValues() {
        let values = ChzzkChatCommand.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count)
    }

    @Test("Donation command is 93102")
    func donationCommand() {
        #expect(ChzzkChatCommand.donation.rawValue == 93102)
    }

    @Test("Notice command is 94010")
    func noticeCommand() {
        #expect(ChzzkChatCommand.notice.rawValue == 94010)
    }

    @Test("SystemMessage command is 93006")
    func systemMessageCommand() {
        #expect(ChzzkChatCommand.systemMessage.rawValue == 93006)
    }

    @Test("Description returns non-empty string for all cases")
    func descriptions() {
        for cmd in ChzzkChatCommand.allCases {
            #expect(!cmd.description.isEmpty)
        }
    }

    @Test("Init from unknown raw value returns nil")
    func unknownRawValue() {
        #expect(ChzzkChatCommand(rawValue: 99999) == nil)
    }
}
