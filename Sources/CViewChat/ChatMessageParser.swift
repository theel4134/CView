// MARK: - ChatMessageParser.swift
// CViewChat - Chzzk chat protocol message parser
// 원본의 ChzzkChatService 내부 파싱 로직 분리

import Foundation
import CViewCore

// MARK: - Chzzk Chat Protocol Constants

/// Chzzk WebSocket chat protocol command types
public enum ChzzkChatCommand: Int, Sendable, CaseIterable {
    case ping = 0
    case pong = 10000
    case connect = 100
    case connected = 10100
    case requestRecentChat = 5101
    case recentChat = 15101
    case sendChat = 3101
    case chatMessage = 93101
    case donation = 93102
    case kick = 94005
    case blind = 94008
    case notice = 94010
    case penalty = 94015
    case sendChatResponse = 13101
    case sendEmote = 3103
    case emoteMessage = 93103
    case systemMessage = 93006
    
    public var description: String {
        switch self {
        case .ping: "Ping"
        case .pong: "Pong"
        case .connect: "Connect"
        case .connected: "Connected"
        case .requestRecentChat: "RequestRecentChat"
        case .recentChat: "RecentChat"
        case .sendChat: "SendChat"
        case .chatMessage: "ChatMessage"
        case .donation: "Donation"
        case .kick: "Kick"
        case .blind: "Blind"
        case .notice: "Notice"
        case .penalty: "Penalty"
        case .sendChatResponse: "SendChatResponse"
        case .sendEmote: "SendEmote"
        case .emoteMessage: "EmoteMessage"
        case .systemMessage: "SystemMessage"
        }
    }
}

// MARK: - Raw Protocol Models

/// Raw chat protocol envelope (Chzzk WebSocket format)
public struct ChatProtocolMessage: Codable, Sendable {
    public let cmd: Int
    public let tid: Int?
    public let svcid: String?
    public let cid: String?
    public let bdy: AnyCodable?
    public let retCode: Int?
    public let retMsg: String?
    
    public init(
        cmd: Int,
        tid: Int? = nil,
        svcid: String? = nil,
        cid: String? = nil,
        bdy: AnyCodable? = nil,
        retCode: Int? = nil,
        retMsg: String? = nil
    ) {
        self.cmd = cmd
        self.tid = tid
        self.svcid = svcid
        self.cid = cid
        self.bdy = bdy
        self.retCode = retCode
        self.retMsg = retMsg
    }
}

/// Type-erased JSON value for protocol flexibility
public enum AnyCodable: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(dict)
        } else {
            self = .null
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    
    // Convenience accessors
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    
    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    
    public var dictValue: [String: AnyCodable]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
    
    public var arrayValue: [AnyCodable]? {
        if case .array(let v) = self { return v }
        return nil
    }
    
    /// Convert Any (from JSONSerialization) to AnyCodable
    public static func from(_ value: Any) -> AnyCodable {
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            // CFBoolean check to distinguish Bool from Int/Double
            if number === kCFBooleanTrue {
                return .bool(true)
            } else if number === kCFBooleanFalse {
                return .bool(false)
            } else {
                let objCType = String(cString: number.objCType)
                if objCType == "d" || objCType == "f" {
                    return .double(number.doubleValue)
                }
                return .int(number.intValue)
            }
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { from($0) })
        default:
            return .null
        }
    }
}

// MARK: - Chat Message Parser

/// Parses raw Chzzk WebSocket messages into domain models.
/// Stateless, pure function design – no side effects.
public struct ChatMessageParser: Sendable {
    
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()
    
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    
    public init() {}
    
    // MARK: - Parsing
    
    /// Parse raw WebSocket text into a ChatProtocolMessage (JSONSerialization 기반 — v1 방식)
    public func parseRaw(_ text: String) throws -> ChatProtocolMessage {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = json["cmd"] as? Int else {
            throw AppError.chat(.invalidMessage)
        }
        
        let bdy: AnyCodable?
        if let bdyValue = json["bdy"] {
            bdy = AnyCodable.from(bdyValue)
        } else {
            bdy = nil
        }
        
        return ChatProtocolMessage(
            cmd: cmd,
            tid: json["tid"] as? Int,
            svcid: json["svcid"] as? String,
            cid: json["cid"] as? String,
            bdy: bdy,
            retCode: json["retCode"] as? Int,
            retMsg: json["retMsg"] as? String
        )
    }
    
    /// Parse a protocol message into domain ChatEvent
    public func parse(_ text: String) throws -> ChatEvent {
        let raw = try parseRaw(text)
        return try parseToDomainEvent(raw)
    }
    
    /// Convert raw protocol message to domain event
    public func parseToDomainEvent(_ raw: ChatProtocolMessage) throws -> ChatEvent {
        guard let command = ChzzkChatCommand(rawValue: raw.cmd) else {
            return .unknown(cmd: raw.cmd)
        }
        
        switch command {
        case .connected:
            return .connected(sessionId: extractSessionId(from: raw))
            
        case .chatMessage:
            let messages = try parseChatMessages(from: raw)
            return .messages(messages)
            
        case .donation:
            let donations = try parseDonations(from: raw)
            return .donations(donations)
            
        case .recentChat:
            let messages = try parseChatMessages(from: raw)
            return .recentMessages(messages)
            
        case .notice:
            let notice = try parseNotice(from: raw)
            return .notice(notice)
            
        case .blind:
            let blindInfo = parseBlind(from: raw)
            return .blind(messageId: blindInfo.0, userId: blindInfo.1)
            
        case .kick:
            return .kick
            
        case .penalty:
            let penalty = parsePenalty(from: raw)
            return .penalty(userId: penalty.0, duration: penalty.1)
            
        case .ping:
            return .ping
            
        case .pong:
            return .pong
            
        case .sendChatResponse:
            // 13101: 메시지 전송 확인 응답 (retCode 0 = 성공)
            let retCode = raw.retCode ?? 0
            if retCode != 0 {
                Log.chat.warning("SendChat response error: retCode=\(retCode), msg=\(raw.retMsg ?? "unknown", privacy: .public)")
            }
            return .sendConfirmed(retCode: retCode)
            
        case .emoteMessage:
            let messages = try parseChatMessages(from: raw)
            return .messages(messages)
            
        case .systemMessage:
            return .system(extractSystemMessage(from: raw))
            
        default:
            return .unknown(cmd: raw.cmd)
        }
    }
    
    // MARK: - Message Construction
    
    /// Build a connect command message
    public func buildConnectMessage(
        chatChannelId: String,
        accessToken: String,
        uid: String? = nil
    ) -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVerStr = "macOS/\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        let body: [String: Any] = [
            "ver": "3",
            "cmd": ChzzkChatCommand.connect.rawValue,
            "svcid": "game",
            "cid": chatChannelId,
            "bdy": [
                "uid": uid ?? "",
                "devType": 2001,
                "accTkn": accessToken,
                "auth": uid != nil ? "SEND" : "READ",
                "libVer": "4.9.3",
                "osVer": osVerStr,
                "devName": "CView_v2/1.0.0",
                "locale": "ko",
                "timezone": "Asia/Seoul"
            ] as [String: Any],
            "tid": 1
        ]
        
        return jsonString(from: body)
    }
    
    /// Build a send chat message (치지직 웹 채팅 HAR 분석 기반 포맷)
    public func buildSendMessage(
        chatChannelId: String,
        channelId: String? = nil,
        sessionId: String? = nil,
        extraToken: String? = nil,
        message: String,
        tid: Int = 3,
        emojis: [String: String]? = nil
    ) -> String {
        let msgTime = Int(Date().timeIntervalSince1970 * 1000)
        
        var msgExtras: [String: Any] = [
            "chatType": "STREAMING",
            "osType": "PC",
            "streamingChannelId": channelId ?? chatChannelId,
            "emojis": emojis ?? [:] as [String: String]
        ]
        
        if let extraToken, !extraToken.isEmpty {
            msgExtras["extraToken"] = extraToken
        }
        
        let body: [String: Any] = [
            "ver": "3",
            "cmd": ChzzkChatCommand.sendChat.rawValue,
            "svcid": "game",
            "cid": chatChannelId,
            "sid": sessionId ?? "",
            "retry": false,
            "tid": String(tid),
            "bdy": [
                "msg": message,
                "msgTypeCode": 1,
                "extras": jsonString(from: msgExtras),
                "msgTime": msgTime,
                "ctime": msgTime
            ] as [String: Any]
        ]
        
        return jsonString(from: body)
    }
    
    /// Build a recent chat request
    public func buildRecentChatRequest(chatChannelId: String, count: Int = 50) -> String {
        let body: [String: Any] = [
            "ver": "3",
            "cmd": ChzzkChatCommand.requestRecentChat.rawValue,
            "svcid": "game",
            "cid": chatChannelId,
            "tid": 2,
            "bdy": [
                "recentMessageCount": count
            ]
        ]
        
        return jsonString(from: body)
    }
    
    /// Build a pong response
    public func buildPong() -> String {
        return "{\"ver\":\"3\",\"cmd\":\(ChzzkChatCommand.pong.rawValue)}"
    }
    
    // MARK: - Private Parsing Helpers
    
    private func parseChatMessages(from raw: ChatProtocolMessage) throws -> [ChatMessage] {
        guard let body = raw.bdy else { return [] }
        
        let messageArray: [AnyCodable]
        if let array = body.arrayValue {
            messageArray = array
        } else if let dict = body.dictValue,
                  let msgs = dict["messageList"]?.arrayValue {
            messageArray = msgs
        } else {
            return []
        }
        
        return messageArray.compactMap { item -> ChatMessage? in
            guard let dict = item.dictValue else { return nil }
            return parseSingleMessage(dict)
        }
    }
    
    private func parseSingleMessage(_ dict: [String: AnyCodable]) -> ChatMessage? {
        let msg = dict["msg"]?.stringValue ?? ""
        let uid = dict["uid"]?.stringValue ?? ""
        let msgTime = dict["msgTime"]?.intValue ?? 0
        // 고유 ID 생성: uid + msgTime 조합 (msgStatusType은 항상 "NORMAL"이므로 사용 불가)
        let msgId = uid.isEmpty ? UUID().uuidString : "\(uid)_\(msgTime)"
        
        // Parse profile from extras
        let parsedProfile = parseProfile(dict["profile"])
        let parsedExtras = parseExtras(dict["extras"])
        
        let messageType: MessageType
        if parsedExtras.isDonation {
            messageType = .donation
        } else if parsedExtras.isSubscription {
            messageType = .subscription
        } else if parsedExtras.isSystemMessage {
            messageType = .systemMessage
        } else {
            messageType = .normal
        }
        
        let chatProfile = ChatProfile(
            nickname: parsedProfile.nickname,
            profileImageURL: parsedProfile.profileImageUrl.flatMap { URL(string: $0) },
            userRoleCode: parsedProfile.isStreamer ? "streamer" : (parsedProfile.isManager ? "manager" : nil),
            badge: parsedProfile.badges.first,
            title: nil
        )
        
        let chatExtras = ChatExtras(
            emojis: parsedExtras.emojis.isEmpty ? nil : parsedExtras.emojis,
            donation: parsedExtras.donation
        )
        
        return ChatMessage(
            id: msgId,
            userId: uid,
            nickname: parsedProfile.nickname,
            content: msg,
            timestamp: Date(timeIntervalSince1970: Double(msgTime) / 1000.0),
            type: messageType,
            profile: chatProfile,
            extras: chatExtras
        )
    }
    
    private struct ParsedProfile {
        var nickname: String = "Unknown"
        var profileImageUrl: String? = nil
        var badges: [ChatBadge] = []
        var isStreamer: Bool = false
        var isManager: Bool = false
        var isVerified: Bool = false
    }
    
    private func parseProfile(_ value: AnyCodable?) -> ParsedProfile {
        var result = ParsedProfile()
        
        // Profile can be a JSON string or a dict
        guard let value else { return result }
        
        let dict: [String: AnyCodable]?
        if let jsonStr = value.stringValue,
           let data = jsonStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Convert to AnyCodable dict (simplified)
            dict = nil // Fallback
            result.nickname = parsed["nickname"] as? String ?? "Unknown"
            result.profileImageUrl = parsed["profileImageUrl"] as? String
            if let userRole = parsed["userRoleCode"] as? String {
                result.isStreamer = userRole == "streamer"
                result.isManager = userRole == "streaming_chat_manager" || userRole == "manager"
            }
            return result
        } else {
            dict = value.dictValue
        }
        
        guard let profileDict = dict else { return result }
        
        result.nickname = profileDict["nickname"]?.stringValue ?? "Unknown"
        result.profileImageUrl = profileDict["profileImageUrl"]?.stringValue
        
        if let role = profileDict["userRoleCode"]?.stringValue {
            result.isStreamer = role == "streamer"
            result.isManager = role.contains("manager")
        }
        
        if let badgeArray = profileDict["badge"]?.dictValue {
            for (key, val) in badgeArray {
                if let url = val.stringValue {
                    result.badges.append(ChatBadge(imageURL: URL(string: url)))
                }
            }
        }
        
        return result
    }
    
    private struct ParsedExtras {
        var emojis: [String: String] = [:]
        var donation: DonationInfo? = nil
        var isDonation: Bool = false
        var isSubscription: Bool = false
        var isSystemMessage: Bool = false
    }
    
    private func parseExtras(_ value: AnyCodable?) -> ParsedExtras {
        var result = ParsedExtras()
        
        guard let value else { return result }
        
        // Extras can be a JSON string
        let dict: [String: Any]
        if let jsonStr = value.stringValue,
           let data = jsonStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = parsed
        } else {
            return result
        }
        
        // Emojis — Chzzk extras: {"emojis": {"emoticonId": "https://..."}}
        // JSONSerialization은 Swift [String: String] 캐스팅이 실패할 수 있으므로 보수적으로 처리
        if let emojisRaw = dict["emojis"] {
            if let directDict = emojisRaw as? [String: String] {
                result.emojis = directDict
            } else if let anyDict = emojisRaw as? [String: Any] {
                // NSString → String 브리징 등 타입 불일치 보정
                result.emojis = anyDict.reduce(into: [String: String]()) { acc, kv in
                    if let strVal = kv.value as? String { acc[kv.key] = strVal }
                    else if let urlVal = kv.value as? URL { acc[kv.key] = urlVal.absoluteString }
                    else { acc[kv.key] = "\(kv.value)" } // 최후 fallback
                }
            }
            if !result.emojis.isEmpty {
                Log.chat.debug("parseExtras: 메시지당 이모티콘 \(result.emojis.count)개 수신")
            }
        }
        
        // Donation
        if let payAmount = dict["payAmount"] as? Int, payAmount > 0 {
            result.isDonation = true
            result.donation = DonationInfo(
                amount: payAmount,
                currency: "KRW",
                type: dict["donationType"] as? String ?? "CHAT"
            )
        }
        
        // Chat type
        if let chatType = dict["chatType"] as? String {
            result.isSubscription = chatType == "SUBSCRIPTION"
            result.isSystemMessage = chatType == "SYSTEM"
        }
        
        return result
    }
    
    private func parseDonations(from raw: ChatProtocolMessage) throws -> [ChatMessage] {
        // Donations use same format as chat messages
        return try parseChatMessages(from: raw)
    }
    
    private func parseNotice(from raw: ChatProtocolMessage) throws -> ChatMessage {
        guard let bdy = raw.bdy,
              let dict = bdy.dictValue else {
            throw AppError.chat(.invalidMessage)
        }
        
        let msg = dict["msg"]?.stringValue ?? ""
        return ChatMessage(
            id: UUID().uuidString,
            nickname: "공지",
            content: msg,
            timestamp: Date(),
            type: .notice
        )
    }
    
    private func parseBlind(from raw: ChatProtocolMessage) -> (String, String) {
        guard let bdy = raw.bdy,
              let dict = bdy.dictValue else {
            return ("", "")
        }
        
        let messageId = dict["messageId"]?.stringValue ?? ""
        let userId = dict["userId"]?.stringValue ?? ""
        return (messageId, userId)
    }
    
    private func parsePenalty(from raw: ChatProtocolMessage) -> (String, Int) {
        guard let bdy = raw.bdy,
              let dict = bdy.dictValue else {
            return ("", 0)
        }
        
        let userId = dict["targetUserId"]?.stringValue ?? ""
        let duration = dict["duration"]?.intValue ?? 0
        return (userId, duration)
    }
    
    private func extractSessionId(from raw: ChatProtocolMessage) -> String {
        guard let bdy = raw.bdy,
              let dict = bdy.dictValue else { return "" }
        return dict["sid"]?.stringValue ?? ""
    }
    
    private func extractSystemMessage(from raw: ChatProtocolMessage) -> String {
        guard let bdy = raw.bdy,
              let dict = bdy.dictValue else { return "" }
        return dict["msg"]?.stringValue ?? ""
    }
    
    // MARK: - JSON Helpers
    
    private func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - Chat Event (Domain Event)

public enum ChatEvent: Sendable {
    case connected(sessionId: String)
    case messages([ChatMessage])
    case recentMessages([ChatMessage])
    case donations([ChatMessage])
    case notice(ChatMessage)
    case blind(messageId: String, userId: String)
    case kick
    case penalty(userId: String, duration: Int)
    case ping
    case pong
    case sendConfirmed(retCode: Int)
    case system(String)
    case unknown(cmd: Int)
}
