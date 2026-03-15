// MARK: - HLSPrefetchService.swift
// CViewPlayer - HLS 매니페스트 프리페치 서비스
// 채널 카드 호버 시 liveDetail API + HLS 매니페스트를 미리 캐시하여 재생 시작 시간 단축

import Foundation
import CViewCore
import CViewNetworking

// MARK: - Prefetch Result

/// 프리페치된 스트림 정보 — 재생 시작 시 API 호출을 건너뛰기 위해 사용
public struct PrefetchedStream: Sendable {
    public let channelId: String
    public let streamURL: URL
    public let channelName: String
    public let liveTitle: String
    public let liveInfo: LiveInfo
    public let masterPlaylist: MasterPlaylist?
    public let timestamp: Date
}

// MARK: - HLS Prefetch Service

/// 채널 호버 시 liveDetail + HLS 매니페스트를 미리 가져와 캐시하는 actor.
/// 캐시는 최대 10개 항목, TTL 30초로 제한하여 메모리와 네트워크 부하를 최소화.
public actor HLSPrefetchService {

    // MARK: - Configuration

    private let maxEntries: Int = 10
    private let ttlSeconds: TimeInterval = 30

    // MARK: - Dependencies

    private let apiClient: ChzzkAPIClient
    private let hlsParser = HLSManifestParser()
    private let logger = AppLogger.player
    // 전용 HLS 세션 — ephemeral(쿠키 격리) + 캐시 비활성화
    private nonisolated let hlsSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    // MARK: - State

    private var cache: [String: PrefetchedStream] = [:]
    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Init

    public init(apiClient: ChzzkAPIClient) {
        self.apiClient = apiClient
    }
    
    deinit {
        hlsSession.invalidateAndCancel()
    }

    // MARK: - Public API

    /// 채널의 HLS 스트림 정보를 백그라운드에서 프리페치한다.
    /// 이미 유효한 캐시가 있거나 진행 중인 요청이 있으면 중복 요청하지 않는다.
    public func prefetch(channelId: String) {
        // 유효한 캐시가 이미 있으면 스킵
        if let existing = cache[channelId], !isExpired(existing) {
            return
        }

        // 이미 진행 중이면 스킵
        if inFlightTasks[channelId] != nil {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performPrefetch(channelId: channelId)
        }
        inFlightTasks[channelId] = task
    }

    /// 캐시된 프리페치 결과를 반환하고 캐시에서 제거한다 (1회성 소비).
    /// 만료된 항목은 nil을 반환한다.
    public func consumePrefetchedStream(channelId: String) -> PrefetchedStream? {
        guard let entry = cache[channelId], !isExpired(entry) else {
            cache.removeValue(forKey: channelId)
            return nil
        }
        cache.removeValue(forKey: channelId)
        inFlightTasks.removeValue(forKey: channelId)
        return entry
    }

    /// 캐시된 프리페치 결과를 반환한다 (제거하지 않음).
    public func peekPrefetchedStream(channelId: String) -> PrefetchedStream? {
        guard let entry = cache[channelId], !isExpired(entry) else {
            return nil
        }
        return entry
    }

    /// 모든 캐시를 비운다.
    public func clearCache() {
        for (_, task) in inFlightTasks {
            task.cancel()
        }
        inFlightTasks.removeAll()
        cache.removeAll()
    }

    // MARK: - Private

    private func performPrefetch(channelId: String) async {
        defer { inFlightTasks.removeValue(forKey: channelId) }

        do {
            // 1. liveDetail API 호출 — 스트림 URL 확보
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)

            guard let playbackJSON = liveInfo.livePlaybackJSON,
                  let jsonData = playbackJSON.data(using: .utf8) else {
                logger.debug("Prefetch: playbackJSON 없음 — \(channelId, privacy: .public)")
                return
            }

            let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
            let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                ?? playback.media.first

            guard let mediaPath = media?.path,
                  let streamURL = URL(string: mediaPath) else {
                logger.debug("Prefetch: HLS URL 없음 — \(channelId, privacy: .public)")
                return
            }

            // 2. HLS 매니페스트 프리페치 (선택적 — 실패해도 streamURL은 캐시)
            let masterPlaylist = await fetchMasterPlaylist(from: streamURL)

            // 3. 캐시에 저장
            let channelName = liveInfo.channel?.channelName ?? ""
            let liveTitle = liveInfo.liveTitle

            let entry = PrefetchedStream(
                channelId: channelId,
                streamURL: streamURL,
                channelName: channelName,
                liveTitle: liveTitle,
                liveInfo: liveInfo,
                masterPlaylist: masterPlaylist,
                timestamp: Date()
            )

            evictIfNeeded()
            cache[channelId] = entry

            logger.info("Prefetch 완료: \(channelId, privacy: .public) (manifest: \(masterPlaylist != nil))")

        } catch is CancellationError {
            // Task 취소 — 정상
        } catch {
            logger.debug("Prefetch 실패: \(channelId, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// HLS 마스터 매니페스트를 가져와 파싱한다. 실패하면 nil.
    private func fetchMasterPlaylist(from url: URL) async -> MasterPlaylist? {
        do {
            var request = URLRequest(url: url)
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            // 프리페치는 경량이어야 하므로 타임아웃 짧게 설정
            request.timeoutInterval = 5

            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""

            if content.contains("#EXT-X-STREAM-INF") {
                return try hlsParser.parseMasterPlaylist(content: content, baseURL: url)
            }
        } catch {
            // 매니페스트 프리페치 실패는 무시 — streamURL만으로도 충분
        }
        return nil
    }

    /// 캐시가 maxEntries를 초과하면 가장 오래된 항목 제거
    private func evictIfNeeded() {
        guard cache.count >= maxEntries else { return }

        // 만료된 항목 먼저 제거
        let now = Date()
        let expired = cache.filter { now.timeIntervalSince($0.value.timestamp) > ttlSeconds }
        for key in expired.keys {
            cache.removeValue(forKey: key)
        }

        // 그래도 꽉 차면 가장 오래된 항목 제거
        while cache.count >= maxEntries {
            if let oldest = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) {
                cache.removeValue(forKey: oldest.key)
            } else {
                break
            }
        }
    }

    /// 캐시 항목이 만료됐는지 확인
    private func isExpired(_ entry: PrefetchedStream) -> Bool {
        Date().timeIntervalSince(entry.timestamp) > ttlSeconds
    }
}
