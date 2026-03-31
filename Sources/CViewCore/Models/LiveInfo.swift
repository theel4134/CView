// MARK: - CViewCore/Models/LiveInfo.swift
// 라이브 방송 정보 도메인 모델

import Foundation

/// 라이브 방송 상세 정보
public struct LiveInfo: Sendable, Codable, Identifiable, Hashable {
    public let liveId: Int
    public let liveTitle: String
    public let status: LiveStatus
    public let concurrentUserCount: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // live-status 폴링 API는 liveId가 없을 수 있으므로 기본값 적용
        liveId = (try? container.decode(Int.self, forKey: .liveId)) ?? 0
        liveTitle = (try? container.decode(String.self, forKey: .liveTitle)) ?? ""
        status = (try? container.decode(LiveStatus.self, forKey: .status)) ?? .open
        concurrentUserCount = (try? container.decode(Int.self, forKey: .concurrentUserCount)) ?? 0
        categoryType = try? container.decode(String.self, forKey: .categoryType)
        liveCategory = try? container.decode(String.self, forKey: .liveCategory)
        liveCategoryValue = try? container.decode(String.self, forKey: .liveCategoryValue)
        chatChannelId = try? container.decode(String.self, forKey: .chatChannelId)
        // {type} 플레이스홀더를 String으로 먼저 디코딩해 치환 (URL 파싱 시 %7Btype%7D로 인코딩되는 문제 방지)
        if let raw = try? container.decode(String.self, forKey: .liveImageURL) {
            let resolved = raw.replacingOccurrences(of: "{type}", with: "720")
            liveImageURL = URL(string: resolved)
        } else {
            liveImageURL = nil
        }
        defaultThumbnailImageURL = try? container.decode(URL.self, forKey: .defaultThumbnailImageURL)
        openDate = try? container.decode(Date.self, forKey: .openDate)
        adult = (try? container.decode(Bool.self, forKey: .adult)) ?? false
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        livePlaybackJSON = try? container.decode(String.self, forKey: .livePlaybackJSON)
        channel = try? container.decode(ChannelInfo.self, forKey: .channel)
    }
    public let categoryType: String?
    public let liveCategory: String?
    public let liveCategoryValue: String?
    public let chatChannelId: String?
    public let liveImageURL: URL?
    public let defaultThumbnailImageURL: URL?
    public let openDate: Date?
    public let adult: Bool
    public let tags: [String]
    public let livePlaybackJSON: String?
    public let channel: ChannelInfo?

    public var id: Int { liveId }

    /// {type} 치환이 완료된 라이브 썸네일 URL (디코딩 시 이미 해결됨)
    public var resolvedLiveImageURL: URL? { liveImageURL }

    public init(
        liveId: Int,
        liveTitle: String,
        status: LiveStatus = .open,
        concurrentUserCount: Int = 0,
        categoryType: String? = nil,
        liveCategory: String? = nil,
        liveCategoryValue: String? = nil,
        chatChannelId: String? = nil,
        liveImageURL: URL? = nil,
        defaultThumbnailImageURL: URL? = nil,
        openDate: Date? = nil,
        adult: Bool = false,
        tags: [String] = [],
        livePlaybackJSON: String? = nil,
        channel: ChannelInfo? = nil
    ) {
        self.liveId = liveId
        self.liveTitle = liveTitle
        self.status = status
        self.concurrentUserCount = concurrentUserCount
        self.categoryType = categoryType
        self.liveCategory = liveCategory
        self.liveCategoryValue = liveCategoryValue
        self.chatChannelId = chatChannelId
        self.liveImageURL = liveImageURL
        self.defaultThumbnailImageURL = defaultThumbnailImageURL
        self.openDate = openDate
        self.adult = adult
        self.tags = tags
        self.livePlaybackJSON = livePlaybackJSON
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case liveId
        case liveTitle
        case status
        case concurrentUserCount
        case categoryType
        case liveCategory
        case liveCategoryValue
        case chatChannelId
        case liveImageURL = "liveImageUrl"
        case defaultThumbnailImageURL = "defaultThumbnailImageUrl"
        case openDate
        case adult
        case tags
        case livePlaybackJSON = "livePlaybackJson"
        case channel
    }
}

/// 라이브 방송 상태
public enum LiveStatus: String, Sendable, Codable, Hashable {
    case open = "OPEN"
    case close = "CLOSE"
}

/// 스트림 품질
public enum StreamQuality: String, Sendable, Codable, Hashable, CaseIterable {
    case auto = "auto"
    case source = "1080p"
    case high = "720p"
    case medium = "480p"
    case low = "360p"

    public var displayName: String {
        switch self {
        case .auto: "자동"
        case .source: "원본 (1080p)"
        case .high: "고화질 (720p)"
        case .medium: "중화질 (480p)"
        case .low: "저화질 (360p)"
        }
    }
}

/// 라이브 재생 정보 (JSON 파싱)
public struct LivePlayback: Sendable, Codable, Hashable {
    public let media: [MediaInfo]
    public let live: LivePlaybackDetail?

    public init(media: [MediaInfo] = [], live: LivePlaybackDetail? = nil) {
        self.media = media
        self.live = live
    }
}

/// 미디어 정보 (HLS 스트림)
public struct MediaInfo: Sendable, Codable, Hashable {
    public let mediaId: String
    public let mediaProtocol: String?
    public let path: String
    public let encodingTrack: [EncodingTrack]?

    public init(mediaId: String, mediaProtocol: String? = nil, path: String, encodingTrack: [EncodingTrack]? = nil) {
        self.mediaId = mediaId
        self.mediaProtocol = mediaProtocol
        self.path = path
        self.encodingTrack = encodingTrack
    }

    enum CodingKeys: String, CodingKey {
        case mediaId
        case mediaProtocol = "protocol"
        case path
        case encodingTrack
    }
}

/// 인코딩 트랙 정보
public struct EncodingTrack: Sendable, Codable, Hashable {
    public let encodingTrackId: String
    public let videoProfile: String?
    public let audioProfile: String?
    public let videoCodec: String?
    public let videoBitRate: Int?
    public let audioBitRate: Int?
    public let videoFrameRate: Double?
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let audioChannel: Int?

    public init(
        encodingTrackId: String, videoProfile: String? = nil,
        audioProfile: String? = nil, videoCodec: String? = nil,
        videoBitRate: Int? = nil, audioBitRate: Int? = nil,
        videoFrameRate: Double? = nil, videoWidth: Int? = nil,
        videoHeight: Int? = nil, audioChannel: Int? = nil
    ) {
        self.encodingTrackId = encodingTrackId
        self.videoProfile = videoProfile
        self.audioProfile = audioProfile
        self.videoCodec = videoCodec
        self.videoBitRate = videoBitRate
        self.audioBitRate = audioBitRate
        self.videoFrameRate = videoFrameRate
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.audioChannel = audioChannel
    }

    // API가 videoFrameRate를 String("60.0")으로 반환하므로 커스텀 디코더 필요
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        encodingTrackId = (try? container.decode(String.self, forKey: .encodingTrackId)) ?? ""
        videoProfile = try? container.decode(String.self, forKey: .videoProfile)
        audioProfile = try? container.decode(String.self, forKey: .audioProfile)
        videoCodec = try? container.decode(String.self, forKey: .videoCodec)
        videoBitRate = try? container.decode(Int.self, forKey: .videoBitRate)
        audioBitRate = try? container.decode(Int.self, forKey: .audioBitRate)
        videoWidth = try? container.decode(Int.self, forKey: .videoWidth)
        videoHeight = try? container.decode(Int.self, forKey: .videoHeight)
        audioChannel = try? container.decode(Int.self, forKey: .audioChannel)

        // videoFrameRate: Double 또는 String("60.0") 모두 처리
        if let doubleVal = try? container.decode(Double.self, forKey: .videoFrameRate) {
            videoFrameRate = doubleVal
        } else if let strVal = try? container.decode(String.self, forKey: .videoFrameRate) {
            if let parsed = Double(strVal) {
                videoFrameRate = parsed
            } else {
                Log.general.debug("EncodingTrack: invalid videoFrameRate string '\(strVal)'")
                videoFrameRate = nil
            }
        } else {
            videoFrameRate = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case encodingTrackId, videoProfile, audioProfile, videoCodec
        case videoBitRate, audioBitRate, videoFrameRate
        case videoWidth, videoHeight, audioChannel
    }
}

/// 라이브 재생 상세
public struct LivePlaybackDetail: Sendable, Codable, Hashable {
    public let start: String?
    public let open: String?
    public let timeMachine: Bool?
    public let status: String?

    public init(start: String? = nil, open: String? = nil, timeMachine: Bool? = nil, status: String? = nil) {
        self.start = start
        self.open = open
        self.timeMachine = timeMachine
        self.status = status
    }
}
