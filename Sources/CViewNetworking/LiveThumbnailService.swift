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

    /// 메트릭 서버에서 가져온 썸네일 URL 캐시
    /// - 값: (resolvedURL, 캐시 만료 시점)
    /// - URL이 없으면 nil — nil도 short TTL로 캐시(negative cache)
    /// - 대량 채널(200+)에 대해 매 45초마다 HTTP 요청이 반복되는 것을 방지
    private struct CachedThumbURL {
        let url: URL?
        let expiry: Date
    }
    private var metricsURLCache: [String: CachedThumbURL] = [:]
    private static let metricsURLTTL: TimeInterval = 45        // 라이브 썸네일 주기와 동일
    private static let metricsURLNegativeTTL: TimeInterval = 30 // 실패/없음은 더 짧게

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
            return await Task.detached(priority: .utility) {
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

        // 1. 캐시된 썸네일 URL 확인 — negative cache 포함
        let now = Date()
        if let cached = metricsURLCache[channelId], cached.expiry > now {
            guard let thumbURL = cached.url else { return nil }
            return await imageCache.imageData(for: thumbURL, maxAge: Self.liveThumbnailTTL)
        }

        let endpoint = metricsBaseURL
            .appending(path: "api/channel/\(channelId)/web-player-info")

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                metricsURLCache[channelId] = CachedThumbURL(url: nil, expiry: now.addingTimeInterval(Self.metricsURLNegativeTTL))
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                metricsURLCache[channelId] = CachedThumbURL(url: nil, expiry: now.addingTimeInterval(Self.metricsURLNegativeTTL))
                return nil
            }

            // 메트릭 서버 응답에서 썸네일 URL 추출 (여러 키 이름 시도)
            let thumbStr = json["thumbnailUrl"] as? String
                ?? json["liveImageUrl"] as? String
                ?? json["thumbnail"] as? String

            guard let thumbStr,
                  let thumbURL = URL(string: thumbStr.replacingOccurrences(of: "{type}", with: "720")) else {
                metricsURLCache[channelId] = CachedThumbURL(url: nil, expiry: now.addingTimeInterval(Self.metricsURLNegativeTTL))
                return nil
            }

            // URL 해석 성공 — 긍정 캐시
            metricsURLCache[channelId] = CachedThumbURL(url: thumbURL, expiry: now.addingTimeInterval(Self.metricsURLTTL))
            return await imageCache.imageData(for: thumbURL, maxAge: Self.liveThumbnailTTL)
        } catch {
            // 네트워크 실패도 짧게 negative cache (재시도 폭주 방지)
            metricsURLCache[channelId] = CachedThumbURL(url: nil, expiry: now.addingTimeInterval(Self.metricsURLNegativeTTL))
            return nil
        }
    }
}
