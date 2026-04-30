// MARK: - CViewCore/Models/ClipModels.swift
// 클립 재생을 위한 도메인 모델

import Foundation

/// 클립 재생 설정
public struct ClipPlaybackConfig: Sendable {
    public let clipUID: String
    public let title: String
    public let streamURL: URL
    public let duration: TimeInterval
    public let channelName: String
    public let thumbnailURL: URL?
    
    public init(
        clipUID: String,
        title: String,
        streamURL: URL,
        duration: TimeInterval,
        channelName: String = "",
        thumbnailURL: URL? = nil
    ) {
        self.clipUID = clipUID
        self.title = title
        self.streamURL = streamURL
        self.duration = duration
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
    }
}

/// POST /service/v1/clips/{uid}/inkey 응답 내용
public struct ClipInkeyContent: Sendable, Codable {
    public let inKey: String

    enum CodingKeys: String, CodingKey {
        case inKey = "inKey"
    }
}

/// Naver rmcnmv VOD play v2.0 응답 (HLS URL 추출용)
/// 실제 응답은 errorCode가 없을 때 videos.list 또는 상위 배열에 m3u8 URL이 있음
public struct NaverVodPlayResponse: Sendable, Codable {
    public let errorCode: String?
    public let videos: NaverVodVideos?

    public struct NaverVodVideos: Sendable, Codable {
        public let list: [NaverVodVideo]?
    }

    public struct NaverVodVideo: Sendable, Codable {
        public let encodedType: String?
        public let masterPlaylistUrl: String?
        public let source: String?
    }

    /// 첫 번째 HLS m3u8 URL 반환 (masterPlaylistUrl 또는 source)
    public var bestHLSURL: String? {
        guard errorCode == nil else { return nil }
        let list = videos?.list ?? []
        // ADHLS 타입 우선
        if let adhls = list.first(where: { $0.encodedType == "ADHLS" || $0.encodedType == "ABR_HLS" }) {
            return adhls.masterPlaylistUrl ?? adhls.source
        }
        return list.first?.masterPlaylistUrl ?? list.first?.source
    }
}

/// 클립 상세 정보의 선택적 필드를 담는 구조체
/// (API 응답: /service/v1/clips/{uid}/detail → content.optionalProperty)
public struct ClipOptionalProperty: Sendable, Codable {
    public let ownerChannel: ChannelInfo?
    public let makerChannel: ChannelInfo?
    public let commentCount: Int?
    public let hasDeletePermission: Bool?
    public let privateUserBlock: Bool?
    public let penalty: Bool?
}

/// 클립 상세 정보 (API 응답: /service/v1/clips/{uid}/detail)
public struct ClipDetail: Sendable, Codable {
    public let clipUID: String
    public let clipTitle: String
    public let clipURL: URL?
    public let thumbnailImageURL: URL?
    public let duration: Int
    /// 조회수 (clipDetail API에서는 반환되지 않으므로 optional)
    public let readCount: Int?
    public let createdDate: Date?
    /// 선택적 필드 (채널 정보는 여기서 가져와야 함)
    public let optionalProperty: ClipOptionalProperty?
    /// 클립 재생 URL — videoPlayUrl 우선, videoUrl 폴백
    public let videoPlayUrl: String?
    /// 클립 비디오 URL (구버전/폴백)
    public let videoUrl: String?
    /// VOD 상태 ("ABR_HLS" 등 — WebView fallback 필요 여부 판단)
    public let vodStatus: String?
    /// VOD ID (ABR_HLS 타입에서 embed 재생에 필요)
    public let videoId: String?

    /// 채널 정보 (optionalProperty.ownerChannel 우선, makerChannel 폴백)
    public var channel: ChannelInfo? {
        optionalProperty?.ownerChannel ?? optionalProperty?.makerChannel
    }

    /// 최적 재생 URL 반환 (videoPlayUrl → videoUrl 우선순위)
    public var bestPlaybackURL: URL? {
        if let s = videoPlayUrl, !s.isEmpty, let u = URL(string: s) { return u }
        if let s = videoUrl,     !s.isEmpty, let u = URL(string: s) { return u }
        return nil
    }

    public init(
        clipUID: String,
        clipTitle: String,
        clipURL: URL? = nil,
        thumbnailImageURL: URL? = nil,
        duration: Int = 0,
        readCount: Int? = nil,
        createdDate: Date? = nil,
        optionalProperty: ClipOptionalProperty? = nil,
        videoPlayUrl: String? = nil,
        videoUrl: String? = nil,
        vodStatus: String? = nil,
        videoId: String? = nil
    ) {
        self.clipUID = clipUID
        self.clipTitle = clipTitle
        self.clipURL = clipURL
        self.thumbnailImageURL = thumbnailImageURL
        self.duration = duration
        self.readCount = readCount
        self.createdDate = createdDate
        self.optionalProperty = optionalProperty
        self.videoPlayUrl = videoPlayUrl
        self.videoUrl = videoUrl
        self.vodStatus = vodStatus
        self.videoId = videoId
    }

    enum CodingKeys: String, CodingKey {
        case clipUID = "clipUID"   // API 응답 키: "clipUID" (대문자 UID)
        case clipTitle
        case clipURL = "clipUrl"
        case thumbnailImageURL = "thumbnailImageUrl"
        case duration, readCount, createdDate, optionalProperty
        case videoPlayUrl
        case videoUrl
        case vodStatus
        case videoId
    }
}
