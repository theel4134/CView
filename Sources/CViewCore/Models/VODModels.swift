// MARK: - CViewCore/Models/VODModels.swift
// VOD 재생을 위한 도메인 모델

import Foundation

/// VOD 재생 상세 정보 (API 응답)
public struct VODDetail: Sendable, Codable {
    public let videoNo: Int
    public let videoId: String?
    public let videoTitle: String
    public let videoImageURL: URL?
    public let duration: Int
    public let publishDate: Date?
    public let readCount: Int
    public let channel: ChannelInfo?
    public let vodStatus: String?
    public let thumbnailImageURL: URL?
    
    /// 재생 정보 JSON 문자열 (livePlaybackJSON과 유사한 구조)
    public let liveRewindPlaybackJson: String?
    /// 직접 VOD URL
    public let vodUrl: String?
    /// inKey (재생 인증용)
    public let inKey: String?
    
    public init(
        videoNo: Int,
        videoId: String? = nil,
        videoTitle: String,
        videoImageURL: URL? = nil,
        duration: Int = 0,
        publishDate: Date? = nil,
        readCount: Int = 0,
        channel: ChannelInfo? = nil,
        vodStatus: String? = nil,
        thumbnailImageURL: URL? = nil,
        liveRewindPlaybackJson: String? = nil,
        vodUrl: String? = nil,
        inKey: String? = nil
    ) {
        self.videoNo = videoNo
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.videoImageURL = videoImageURL
        self.duration = duration
        self.publishDate = publishDate
        self.readCount = readCount
        self.channel = channel
        self.vodStatus = vodStatus
        self.thumbnailImageURL = thumbnailImageURL
        self.liveRewindPlaybackJson = liveRewindPlaybackJson
        self.vodUrl = vodUrl
        self.inKey = inKey
    }
    
    enum CodingKeys: String, CodingKey {
        case videoNo, videoId, videoTitle
        case videoImageURL = "videoImageUrl"
        case duration, publishDate, readCount, channel
        case vodStatus
        case thumbnailImageURL = "thumbnailImageUrl"
        case liveRewindPlaybackJson
        case vodUrl
        case inKey
    }
}

/// VOD 스트림 정보 (해상된 재생 URL)
public struct VODStreamInfo: Sendable {
    public let videoNo: Int
    public let title: String
    public let streamURL: URL
    public let duration: TimeInterval
    public let qualities: [VODQuality]
    public let channelName: String
    
    public init(
        videoNo: Int,
        title: String,
        streamURL: URL,
        duration: TimeInterval,
        qualities: [VODQuality] = [],
        channelName: String = ""
    ) {
        self.videoNo = videoNo
        self.title = title
        self.streamURL = streamURL
        self.duration = duration
        self.qualities = qualities
        self.channelName = channelName
    }
}

/// VOD 화질 정보
public struct VODQuality: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let resolution: String
    public let bandwidth: Int
    public let url: URL
    
    public init(id: String, name: String, resolution: String, bandwidth: Int, url: URL) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.bandwidth = bandwidth
        self.url = url
    }
}

/// VOD 재생 상태
public enum VODPlaybackState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case buffering
    case ended
    case error(String)
}

/// 재생 속도 프리셋
public enum PlaybackSpeed: Float, Sendable, CaseIterable, Identifiable {
    case x025 = 0.25
    case x050 = 0.5
    case x075 = 0.75
    case x100 = 1.0
    case x125 = 1.25
    case x150 = 1.5
    case x175 = 1.75
    case x200 = 2.0
    
    public var id: Float { rawValue }
    
    public var displayName: String {
        if rawValue == 1.0 { return "1x (기본)" }
        if rawValue == Float(Int(rawValue)) {
            return "\(Int(rawValue))x"
        }
        return String(format: "%.2gx", rawValue)
    }
}
