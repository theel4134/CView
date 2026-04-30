// MARK: - HomeThumbnailPrefetcher.swift
// 홈 화면에 표시될 모든 썸네일/채널 이미지의 사전 캐싱(워밍).
//
// 배경:
// ──────────────────────────────────────────────────────────────────────────
// 홈은 Hero / 추천(Discover) / 팔로잉 라이브 / 인기 채널 / 이어보기 / 즐겨찾기
// 등 다수의 카드를 동시에 노출하며 각 카드는 LiveThumbnailView (라이브 썸네일,
// 90s TTL) + CachedAsyncImage (채널 아바타, 장기 캐시) 를 사용한다.
//
// 기존엔 카드의 `.task` 에서 처음 보였을 때 비로소 네트워크 fetch 가 시작되어:
//   • 첫 진입 / 새로고침 직후 카드들이 동시에 4-게이트(ImageCacheService) 에 적체
//   • 스크롤로 화면에 들어오는 카드도 동일한 1회성 latency 부담
//
// 본 서비스는 데이터(채널 목록) 가 갱신된 직후 백그라운드에서 다음 절차로
// 캐시를 미리 채운다:
//   1. 메모리/디스크 캐시에 이미 있으면 즉시 종료(no-op).
//   2. 없다면 ImageCacheService 의 4-동시 게이트 위에서 다운로드 → 디스크/메모리
//      캐시에 저장.
//   3. NSImage 디코딩까지 미리 수행해 렌더 패스에서 Data→NSImage 비용 제거.
//
// 따라서 카드가 화면에 등장하는 순간 .task 는 디코딩 캐시 히트로 즉시 반환하고
// 사용자는 깜빡임 없이 썸네일을 본다.
//
// 비용:
// ──────────────────────────────────────────────────────────────────────────
// • 동시 다운로드는 ImageCacheService 가 4 로 제한 → 네트워크 폭주 없음.
// • Task 우선순위 .utility — UI/플레이어와 경합 회피.
// • 라이브 썸네일은 90s TTL, 채널 아바타는 장기 캐시 — 재호출은 거의 항상
//   캐시 히트 (negligible cost).
//
// 호출 시점:
//   • HomeView_v2.onAppear (첫 진입 + 캐시 복원 직후)
//   • viewModel.refresh() 완료 직후
//   • recomputeCachesIfNeeded() 가 cachedRecommendations 갱신한 직후

import Foundation
import CViewCore
import CViewNetworking
import CViewPersistence

/// 홈 카드에 표시될 이미지/썸네일 사전 워밍 유틸.
@MainActor
enum HomeThumbnailPrefetcher {

    /// 한 번의 prefetch 호출에서 처리할 최대 채널 수.
    /// 너무 크면 의미 없는 트래픽 + 로컬 디스크 부담 → "사용자가 곧 볼" 범위로 제한.
    private static let maxChannels = 60

    /// [Perf 2026-04-24] 가장 최근 prefetch 작업 핸들. 새 호출이 오면 이전을 취소해
    /// 짧은 시간 내 중복 호출(예: refresh 직후 recompute 가 또 호출) 의 부하를 막는다.
    private static var currentTask: Task<Void, Never>?

    /// [Perf 2026-04-24] 외부에서 강제 취소 (홈을 벗어날 때).
    static func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// 라이브 채널 묶음에 대해 라이브 썸네일 + 채널 아바타를 비동기 워밍.
    ///
    /// - Parameters:
    ///   - channels: 워밍할 라이브 채널 (Hero/Recommended/Top/Following 등 합집합 권장)
    ///   - includeLiveThumbnail: 라이브 썸네일까지 워밍할지 (false 면 아바타만)
    ///
    /// 반환 즉시 끝나는 게 아니라, 내부에서 detached Task 를 띄우고 곧장 반환한다.
    /// 호출자는 await 하지 않으며 화면 렌더링을 가로막지 않는다.
    static func prefetchLive(
        channels: [LiveChannelItem],
        includeLiveThumbnail: Bool = true
    ) {
        guard !channels.isEmpty else { return }

        // channelId 중복 제거 — Hero/Recommended/Top 이 동일 채널을 공유할 수 있음
        var seen = Set<String>()
        let unique = channels.filter { seen.insert($0.channelId).inserted }
        let slice = Array(unique.prefix(maxChannels))

        let avatarURLs: [URL] = slice.compactMap { ch in
            guard let s = ch.channelImageUrl, let u = URL(string: s) else { return nil }
            return u
        }
        let liveThumbItems: [(channelId: String, fallback: URL?)] = includeLiveThumbnail
            ? slice.map { ch in
                let fb = ch.thumbnailUrl.flatMap { URL(string: $0) }
                return (ch.channelId, fb)
            }
            : []

        // [Perf 2026-04-24] 이전 prefetch 취소 + 160ms 디바운스. 짧은 시간 안에
        // 여러 번(refresh + recompute + onAppear) 호출되어도 최종 1회만 실행.
        currentTask?.cancel()
        currentTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await runPrefetch(avatarURLs: avatarURLs, liveThumbs: liveThumbItems)
        }
    }

    /// 영속(즐겨찾기/이어보기) 항목의 채널 아바타를 워밍.
    /// 이 항목들은 라이브 여부와 무관 — 채널 이미지만 사전 로딩.
    static func prefetchPersisted(items: [ChannelListData]) {
        guard !items.isEmpty else { return }

        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.channelId).inserted }
        let urls: [URL] = unique
            .prefix(maxChannels)
            .compactMap { it -> URL? in
                guard let s = it.imageURL, let u = URL(string: s) else { return nil }
                return u
            }

        guard !urls.isEmpty else { return }
        // [Perf 2026-04-24] persisted prefetch 는 더 가볍지만 동일 디바운스 적용.
        // (currentTask 와는 별개의 Task — 라이브 prefetch 와는 종류가 다르므로 cancel 하지 않음.)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await runPrefetch(avatarURLs: urls, liveThumbs: [])
        }
    }

    // MARK: - Internal

    private static func runPrefetch(
        avatarURLs: [URL],
        liveThumbs: [(channelId: String, fallback: URL?)]
    ) async {
        // ImageCacheService 의 4-동시 게이트가 실제 동시성을 제한하므로
        // TaskGroup 으로 한꺼번에 던져도 안전. nsImage(for:) 는 디코딩까지 캐시에 적재.
        await withTaskGroup(of: Void.self) { group in
            for url in avatarURLs {
                group.addTask(priority: .utility) {
                    _ = await ImageCacheService.shared.nsImage(for: url)
                }
            }
            for item in liveThumbs {
                group.addTask(priority: .utility) {
                    _ = await LiveThumbnailService.shared.thumbnailImage(
                        channelId: item.channelId,
                        fallbackUrl: item.fallback
                    )
                }
            }
        }
    }
}
