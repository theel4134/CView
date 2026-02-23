// MARK: - CViewCore/Models/SearchModels.swift
// 검색 도메인 모델

import Foundation

/// 검색 결과 타입
public enum SearchType: String, Sendable, Codable, CaseIterable {
    case channel
    case live
    case video
    case clip
}

/// 검색 결과 컨테이너
public struct SearchResult<T: Sendable & Codable>: Sendable, Codable {
    public let size: Int
    public let page: SearchPage?
    public let totalCount: Int?
    public let data: [T]

    public init(size: Int = 0, page: SearchPage? = nil, totalCount: Int? = nil, data: [T] = []) {
        self.size = size
        self.page = page
        self.totalCount = totalCount
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case size, page, totalCount, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? container.decode(Int.self, forKey: .size)) ?? 0
        totalCount = try? container.decode(Int.self, forKey: .totalCount)
        data = (try? container.decode([T].self, forKey: .data)) ?? []
        // page는 Int, Object, null 모두 가능 — 유연하게 처리
        page = try? container.decode(SearchPage.self, forKey: .page)
    }
}

/// 검색 페이지 정보 (API에서 Object로 반환)
public struct SearchPage: Sendable, Codable {
    public let next: SearchPageOffset?

    public init(next: SearchPageOffset? = nil) {
        self.next = next
    }
}

/// 검색 페이지 오프셋
public struct SearchPageOffset: Sendable, Codable {
    public let offset: Int

    public init(offset: Int) {
        self.offset = offset
    }
}

/// 채널 검색 결과 아이템 래퍼 (API에서 {"channel": {...}} 형태로 반환)
public struct ChannelSearchItem: Sendable, Codable {
    public let channel: ChannelInfo
    public let openLive: Bool?

    public init(channel: ChannelInfo, openLive: Bool? = nil) {
        self.channel = channel
        self.openLive = openLive
    }
}

/// 라이브 검색 결과 아이템 래퍼 (API에서 {"live": {...}, "channel": {...}} 형태로 반환)
public struct LiveSearchItem: Sendable, Codable {
    public let live: LiveInfo
    public let channel: ChannelInfo?

    private enum CodingKeys: String, CodingKey {
        case live, channel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseLive = try container.decode(LiveInfo.self, forKey: .live)
        let ch = try? container.decode(ChannelInfo.self, forKey: .channel)
        // channel을 live에 주입
        live = LiveInfo(
            liveId: baseLive.liveId,
            liveTitle: baseLive.liveTitle,
            status: baseLive.status,
            concurrentUserCount: baseLive.concurrentUserCount,
            categoryType: baseLive.categoryType,
            liveCategory: baseLive.liveCategory,
            liveCategoryValue: baseLive.liveCategoryValue,
            chatChannelId: baseLive.chatChannelId,
            liveImageURL: baseLive.liveImageURL,
            defaultThumbnailImageURL: baseLive.defaultThumbnailImageURL,
            openDate: baseLive.openDate,
            adult: baseLive.adult,
            tags: baseLive.tags,
            livePlaybackJSON: baseLive.livePlaybackJSON,
            channel: ch ?? baseLive.channel
        )
        channel = ch
    }
}

/// 비디오 검색 결과 아이템 래퍼 (API에서 {"video": {...}, "channel": {...}} 형태로 반환)
public struct VideoSearchItem: Sendable, Codable {
    public let video: VODInfo
    public let channel: ChannelInfo?

    private enum CodingKeys: String, CodingKey {
        case video, channel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseVideo = try container.decode(VODInfo.self, forKey: .video)
        let ch = try? container.decode(ChannelInfo.self, forKey: .channel)
        // channel을 video에 주입
        video = VODInfo(
            videoNo: baseVideo.videoNo,
            videoId: baseVideo.videoId,
            videoTitle: baseVideo.videoTitle,
            videoImageURL: baseVideo.videoImageURL,
            duration: baseVideo.duration,
            publishDate: baseVideo.publishDate,
            readCount: baseVideo.readCount,
            channel: ch ?? baseVideo.channel
        )
        channel = ch
    }
}

/// VOD 정보
public struct VODInfo: Sendable, Codable, Identifiable, Hashable {
    public let videoNo: Int
    public let videoId: String?
    public let videoTitle: String
    public let videoImageURL: URL?
    public let duration: Int
    public let publishDate: Date?
    public let readCount: Int
    public let channel: ChannelInfo?

    public var id: Int { videoNo }

    public var formattedDuration: String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    public init(
        videoNo: Int,
        videoId: String? = nil,
        videoTitle: String,
        videoImageURL: URL? = nil,
        duration: Int = 0,
        publishDate: Date? = nil,
        readCount: Int = 0,
        channel: ChannelInfo? = nil
    ) {
        self.videoNo = videoNo
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.videoImageURL = videoImageURL
        self.duration = duration
        self.publishDate = publishDate
        self.readCount = readCount
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case videoNo
        case videoId
        case videoTitle
        case videoImageURL = "videoImageUrl"
        case duration
        case publishDate
        case readCount
        case channel
    }
}

/// 클립 정보
public struct ClipInfo: Sendable, Codable, Identifiable, Hashable {
    public let clipUID: String
    public let clipTitle: String
    public let thumbnailImageURL: URL?
    public let clipURL: URL?
    public let duration: Int
    public let readCount: Int
    public let createdDate: Date?
    public let channel: ChannelInfo?

    public var id: String { clipUID }

    public init(
        clipUID: String,
        clipTitle: String,
        thumbnailImageURL: URL? = nil,
        clipURL: URL? = nil,
        duration: Int = 0,
        readCount: Int = 0,
        createdDate: Date? = nil,
        channel: ChannelInfo? = nil
    ) {
        self.clipUID = clipUID
        self.clipTitle = clipTitle
        self.thumbnailImageURL = thumbnailImageURL
        self.clipURL = clipURL
        self.duration = duration
        self.readCount = readCount
        self.createdDate = createdDate
        self.channel = channel
    }

    // API 응답 키 매핑:
    //   clip list: clipUID(대문자), ownerChannel
    //   clip detail: clipUid(소문자), channel
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // clipUID: list API는 "clipUID"(대문자), detail API는 "clipUid"(소문자) → 둘 다 시도
        if let uid = try? container.decode(String.self, forKey: .clipUID), !uid.isEmpty {
            clipUID = uid
        } else if let uid = try? container.decode(String.self, forKey: .clipUIDLower), !uid.isEmpty {
            clipUID = uid
        } else {
            clipUID = ""
        }
        clipTitle = (try? container.decode(String.self, forKey: .clipTitle)) ?? ""
        thumbnailImageURL = try? container.decode(URL.self, forKey: .thumbnailImageURL)
        clipURL = try? container.decode(URL.self, forKey: .clipURL)
        duration = (try? container.decode(Int.self, forKey: .duration)) ?? 0
        readCount = (try? container.decode(Int.self, forKey: .readCount)) ?? 0
        createdDate = try? container.decode(Date.self, forKey: .createdDate)
        // channel: list API는 "ownerChannel", detail API는 "channel" → 둘 다 시도
        if let ch = try? container.decode(ChannelInfo.self, forKey: .ownerChannel) {
            channel = ch
        } else {
            channel = try? container.decode(ChannelInfo.self, forKey: .channel)
        }
    }

    enum CodingKeys: String, CodingKey {
        case clipUID = "clipUID"        // clip list API (대문자 D)
        case clipUIDLower = "clipUid"   // clip detail API (소문자 d)
        case clipTitle
        case thumbnailImageURL = "thumbnailImageUrl"
        case clipURL = "clipUrl"
        case duration
        case readCount
        case createdDate
        case ownerChannel               // clip list API
        case channel                    // clip detail API
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clipUID, forKey: .clipUID)
        try container.encode(clipTitle, forKey: .clipTitle)
        try container.encodeIfPresent(thumbnailImageURL, forKey: .thumbnailImageURL)
        try container.encodeIfPresent(clipURL, forKey: .clipURL)
        try container.encode(duration, forKey: .duration)
        try container.encode(readCount, forKey: .readCount)
        try container.encodeIfPresent(createdDate, forKey: .createdDate)
        try container.encodeIfPresent(channel, forKey: .channel)
    }
}
