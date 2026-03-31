// MARK: - CViewNetworking/LiveThumbnailService.swift
// 라이브 채널 썸네일 전용 서비스 — 단기 TTL 캐시 + 메트릭 서버 통합

import Foundation
import AppKit   // NSImage
import CViewCore

/// 라이브 채널 썸네일 데이터를 제공하는 서비스
///
/// 우선순위:
/// 1. `cv.dododo.app` 메트릭 서버 → `/api/channel/{id}/web-player-info` 썸네일 URL
/// 2. Chzzk CDN 직접 URL (fallback)
///
/// 라이브 썸네일은 ~45초 단기 TTL로 캐시되어 주기적으로 갱신됩니다.
public actor LiveThumbnailService {
    public static let shared = LiveThumbnailService()

    /// 라이브 썸네일 캐시 유지 시간 (초)
    public static let liveThumbnailTTL: TimeInterval = 90

    private let imageCache = ImageCacheService.shared
    private let metricsBaseURL = URL(string: MetricsSettings.defaultServerURL)!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// 라이브 채널 썸네일 Data 반환 (45초 TTL 캐싱)
    /// - Parameters:
    ///   - channelId: 채널 ID (예: "woowakgood")
    ///   - fallbackUrl: Chzzk API의 resolvedLiveImageURL ({type} 치환 완료)
    public func thumbnailData(channelId: String, fallbackUrl: URL?) async -> Data? {
        // 1. 메트릭 서버에서 썸네일 시도
        if let data = await fetchFromMetrics(channelId: channelId) {
            return data
        }

        // 2. Chzzk CDN 직접 URL fallback (45초 TTL)
        guard let url = fallbackUrl else { return nil }
        return await imageCache.imageData(for: url, maxAge: Self.liveThumbnailTTL)
    }

    /// 디코딩된 NSImage 반환 — 렌더 패스에서 Data→NSImage 변환 제거
    public func thumbnailImage(channelId: String, fallbackUrl: URL?) async -> NSImage? {
        // 1. 메트릭 서버 경로
        if let data = await fetchFromMetrics(channelId: channelId) {
            return await Task.detached(priority: .userInitiated) {
                NSImage(data: data)
            }.value
        }
        // 2. CDN fallback — ImageCacheService nsImage 재사용 (디코딩 캐시 포함)
        guard let url = fallbackUrl else { return nil }
        return await imageCache.nsImage(for: url, maxAge: Self.liveThumbnailTTL)
    }

    // MARK: - Private

    private func fetchFromMetrics(channelId: String) async -> Data? {
        guard !channelId.isEmpty else { return nil }

        let endpoint = metricsBaseURL
            .appending(path: "api/channel/\(channelId)/web-player-info")

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            // 메트릭 서버 응답에서 썸네일 URL 추출 (여러 키 이름 시도)
            let thumbStr = json["thumbnailUrl"] as? String
                ?? json["liveImageUrl"] as? String
                ?? json["thumbnail"] as? String

            guard let thumbStr,
                  let thumbURL = URL(string: thumbStr.replacingOccurrences(of: "{type}", with: "720")) else { return nil }

            return await imageCache.imageData(for: thumbURL, maxAge: Self.liveThumbnailTTL)
        } catch {
            return nil
        }
    }
}
