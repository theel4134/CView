// MARK: - VODStreamResolver.swift
// CViewPlayer - VOD 스트림 URL 해석기

import Foundation
import CViewCore
import CViewNetworking

/// VOD/Clip 스트림 URL을 해석하는 유틸리티
public actor VODStreamResolver {
    
    private let apiClient: ChzzkAPIClient
    private let logger = AppLogger.player
    
    public init(apiClient: ChzzkAPIClient) {
        self.apiClient = apiClient
    }
    
    /// VOD 상세 정보에서 스트림 정보 해석
    public func resolveVOD(videoNo: Int) async throws -> VODStreamInfo {
        let detail = try await apiClient.vodDetail(videoNo: videoNo)
        return try resolveFromDetail(detail)
    }
    
    /// VODDetail에서 스트림 URL 추출
    private func resolveFromDetail(_ detail: VODDetail) throws -> VODStreamInfo {
        // 1. Try liveRewindPlaybackJson first (contains HLS manifests)
        if let playbackJson = detail.liveRewindPlaybackJson {
            do {
                let streamInfo = try parsePlaybackJson(playbackJson, detail: detail)
                logger.info("VOD resolved from playbackJson: \(detail.videoTitle)")
                return streamInfo
            } catch {
                logger.warning("VOD playbackJson 파싱 실패 (vodUrl 폴백): \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // 2. Try direct vodUrl
        if let vodUrlStr = detail.vodUrl, let vodURL = URL(string: vodUrlStr) {
            var finalURL = vodURL
            // Append inKey if available
            if let inKey = detail.inKey {
                var components = URLComponents(url: vodURL, resolvingAgainstBaseURL: false)
                var queryItems = components?.queryItems ?? []
                queryItems.append(URLQueryItem(name: "inKey", value: inKey))
                components?.queryItems = queryItems
                if let urlWithKey = components?.url {
                    finalURL = urlWithKey
                }
            }
            
            logger.info("VOD resolved from vodUrl: \(detail.videoTitle)")
            return VODStreamInfo(
                videoNo: detail.videoNo,
                title: detail.videoTitle,
                streamURL: finalURL,
                duration: TimeInterval(detail.duration),
                channelName: detail.channel?.channelName ?? ""
            )
        }
        
        throw VODResolveError.noPlayableURL
    }
    
    /// liveRewindPlaybackJson 파싱 (치지직 API 응답 형식)
    private func parsePlaybackJson(_ jsonString: String, detail: VODDetail) throws -> VODStreamInfo {
        guard let data = jsonString.data(using: .utf8) else {
            throw VODResolveError.invalidPlaybackJson
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VODResolveError.invalidPlaybackJson
        }
        
        // Extract media from playback JSON
        // Structure: { "media": [{ "mediaId": "...", "protocol": "HLS", "path": "...", "encodingTrack": [...] }] }
        guard let mediaArray = json["media"] as? [[String: Any]],
              let firstMedia = mediaArray.first,
              let mediaPath = firstMedia["path"] as? String,
              let mediaURL = URL(string: mediaPath) else {
            throw VODResolveError.noPlayableURL
        }
        
        // Parse available qualities from encodingTrack
        var qualities: [VODQuality] = []
        if let tracks = firstMedia["encodingTrack"] as? [[String: Any]] {
            for track in tracks {
                let trackId = track["encodingTrackId"] as? String ?? UUID().uuidString
                let name = track["encodingTrackName"] as? String ?? "Unknown"
                let width = track["videoWidth"] as? Int ?? 0
                let height = track["videoHeight"] as? Int ?? 0
                let bitrate = track["videoBitRate"] as? Int ?? track["audioBitRate"] as? Int ?? 0
                let resolution = "\(width)x\(height)"
                
                // Path might be specific per quality or the same base URL
                let trackPath = track["path"] as? String
                let qualityURL: URL
                if let trackPath, let url = URL(string: trackPath) {
                    qualityURL = url
                } else {
                    qualityURL = mediaURL
                }
                
                qualities.append(VODQuality(
                    id: trackId,
                    name: name,
                    resolution: resolution,
                    bandwidth: bitrate,
                    url: qualityURL
                ))
            }
        }
        
        // Sort qualities by bandwidth (highest first)
        qualities.sort { $0.bandwidth > $1.bandwidth }
        
        // Build final URL with inKey
        var finalURL = mediaURL
        if let inKey = detail.inKey {
            var components = URLComponents(url: mediaURL, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "inKey", value: inKey))
            components?.queryItems = queryItems
            if let urlWithKey = components?.url {
                finalURL = urlWithKey
            }
        }
        
        return VODStreamInfo(
            videoNo: detail.videoNo,
            title: detail.videoTitle,
            streamURL: finalURL,
            duration: TimeInterval(detail.duration),
            qualities: qualities,
            channelName: detail.channel?.channelName ?? ""
        )
    }
    
    /// 클립 URL 해석 (클립은 일반적으로 직접 MP4/HLS URL)
    public func resolveClip(clipInfo: ClipInfo) -> ClipPlaybackConfig? {
        guard let clipURL = clipInfo.clipURL else {
            logger.warning("Clip has no URL: \(clipInfo.clipTitle)")
            return nil
        }
        
        return ClipPlaybackConfig(
            clipUID: clipInfo.clipUID,
            title: clipInfo.clipTitle,
            streamURL: clipURL,
            duration: TimeInterval(clipInfo.duration),
            channelName: clipInfo.channel?.channelName ?? "",
            thumbnailURL: clipInfo.thumbnailImageURL
        )
    }
}

/// VOD 해석 에러
public enum VODResolveError: Error, LocalizedError, Sendable {
    case noPlayableURL
    case invalidPlaybackJson
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noPlayableURL: "재생 가능한 URL을 찾을 수 없습니다"
        case .invalidPlaybackJson: "재생 정보를 파싱할 수 없습니다"
        case .networkError(let msg): "네트워크 오류: \(msg)"
        }
    }
}
