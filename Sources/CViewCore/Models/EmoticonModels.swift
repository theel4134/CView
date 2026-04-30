// MARK: - EmoticonModels.swift
// CViewCore - 치지직 이모티콘 도메인 모델

import Foundation

// MARK: - Emoticon Pack

/// 이모티콘 팩 정보
public struct EmoticonPack: Sendable, Codable, Identifiable, Hashable {
    public let emoticonPackId: String
    public let emoticonPackName: String
    public let emoticonPackImageURL: URL?
    public let emoticonPackType: String?
    public let emoticons: [EmoticonItem]?
    
    public var id: String { emoticonPackId }
    
    public init(
        emoticonPackId: String,
        emoticonPackName: String,
        emoticonPackImageURL: URL? = nil,
        emoticonPackType: String? = nil,
        emoticons: [EmoticonItem]? = nil
    ) {
        self.emoticonPackId = emoticonPackId
        self.emoticonPackName = emoticonPackName
        self.emoticonPackImageURL = emoticonPackImageURL
        self.emoticonPackType = emoticonPackType
        self.emoticons = emoticons
    }
    
    enum CodingKeys: String, CodingKey {
        case emoticonPackId
        case emoticonPackName
        case emoticonPackImageURL = "emoticonPackImageUrl"
        case emoticonPackType
        case emoticons
    }
}

// MARK: - Emoticon Item

/// 개별 이모티콘
public struct EmoticonItem: Sendable, Codable, Identifiable, Hashable {
    public let emoticonId: String
    public let emoticonName: String?
    public let imageURL: URL?
    public let darkModeImageURL: URL?
    public let width: Int?
    public let height: Int?
    public let packId: String?
    
    public var id: String { emoticonId }
    
    /// 이모티콘을 채팅에서 사용할 때 패턴 (예: {:emoticonId:})
    public var chatPattern: String { "{:\(emoticonId):}" }
    
    public init(
        emoticonId: String,
        emoticonName: String? = nil,
        imageURL: URL? = nil,
        darkModeImageURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        packId: String? = nil
    ) {
        self.emoticonId = emoticonId
        self.emoticonName = emoticonName
        self.imageURL = imageURL
        self.darkModeImageURL = darkModeImageURL
        self.width = width
        self.height = height
        self.packId = packId
    }
    
    enum CodingKeys: String, CodingKey {
        case emoticonId
        case emoticonName
        case imageURL = "imageUrl"
        case darkModeImageURL = "darkModeImageUrl"
        case width, height
        case packId
    }
}

// MARK: - Emoticon Deploy

/// 채널의 이모티콘 배포 정보 (API 응답)
public struct EmoticonDeploy: Sendable, Codable {
    public let emoticonPacks: [EmoticonPack]?
    public let subscriptionEmoticonPacks: [EmoticonPack]?
    
    public init(
        emoticonPacks: [EmoticonPack]? = nil,
        subscriptionEmoticonPacks: [EmoticonPack]? = nil
    ) {
        self.emoticonPacks = emoticonPacks
        self.subscriptionEmoticonPacks = subscriptionEmoticonPacks
    }
    
    /// 모든 팩 (일반 + 구독)
    public var allPacks: [EmoticonPack] {
        (emoticonPacks ?? []) + (subscriptionEmoticonPacks ?? [])
    }
    
    /// 모든 이모티콘 평탄화
    public var allEmoticons: [EmoticonItem] {
        allPacks.flatMap { $0.emoticons ?? [] }
    }
}

// MARK: - Parsed Emoticon Segment

/// 채팅 메시지에서 파싱된 세그먼트 (텍스트 또는 이모티콘)
public enum ChatContentSegment: Sendable, Identifiable, Hashable {
    case text(String)
    case emoticon(id: String, url: URL)
    
    public var id: String {
        switch self {
        case .text(let t): "text-\(t.hashValue)"
        case .emoticon(let id, _): "emo-\(id)"
        }
    }
}

// MARK: - Emoticon Parser

/// 채팅 메시지 내 이모티콘 패턴을 파싱
public struct EmoticonParser: Sendable {
    
    public init() {}
    
    /// 메시지 content와 emojis 딕셔너리를 받아 세그먼트로 파싱
    /// emojis: ["emoticonId": "imageUrl"] 형태
    public func parse(content: String, emojis: [String: String]?) -> [ChatContentSegment] {
        guard let emojis, !emojis.isEmpty else {
            return [.text(content)]
        }
        
        var segments: [ChatContentSegment] = []
        var remaining = content
        
        while !remaining.isEmpty {
            // {emoticonId} 패턴 찾기
            guard let openBrace = remaining.firstIndex(of: "{"),
                  let closeBrace = remaining[remaining.index(after: openBrace)...].firstIndex(of: "}") else {
                // 더 이상 패턴이 없음
                if !remaining.isEmpty {
                    segments.append(.text(remaining))
                }
                break
            }
            
            // { 이전 텍스트
            let beforeText = String(remaining[remaining.startIndex..<openBrace])
            if !beforeText.isEmpty {
                segments.append(.text(beforeText))
            }
            
            // {와 } 사이의 ID
            let idStart = remaining.index(after: openBrace)
            let rawId = String(remaining[idStart..<closeBrace])
            // Chzzk 형식: {:d_54:} → rawId = ":d_54:", 콜론 제거 후 실제 ID
            let emoticonId = rawId.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            
            // 이모티콘 URL 찾기 (원본 ID 또는 콜론 제거 ID 둘 다 시도)
            let urlStr = emojis[emoticonId] ?? emojis[rawId]
            if let urlStr, let url = URL(string: urlStr) {
                segments.append(.emoticon(id: emoticonId, url: url))
            } else {
                // 매칭 안되면 원본 텍스트 유지
                segments.append(.text("{\(rawId)}"))
            }
            
            remaining = String(remaining[remaining.index(after: closeBrace)...])
        }
        
        return segments
    }
}
