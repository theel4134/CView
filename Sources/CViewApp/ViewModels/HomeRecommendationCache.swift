// MARK: - HomeRecommendationCache.swift
// CViewApp - 홈 추천 결과(ScoredChannel) 영속 캐시 (콜드스타트 가속)
//
// 배경 (docs/home-frame-drop-analysis-2026-04-24.md / 2026-04-25 후속):
// ──────────────────────────────────────────────────────────────────────────
// HomeView_v2 의 Hero / Discover 그리드는 `cachedRecommendations` (ScoredChannel
// 배열) 을 입력으로 한다. 이 배열은 매 부트마다 `recomputeCachesIfNeeded()` 가
// 라이브 채널 목록 + 팔로잉 + 즐겨찾기 + 최근 시청 + 멀티라이브 세션을 입력으로
// 점수 함수를 돌려서 만든다.
//
// 문제: 콜드스타트 직후 viewModel 의 채널 배열은 `cache.liveChannels` JSON blob
// 으로 즉시 복원되지만, 추천 점수 계산은 reloadStore()(즐겨찾기/최근 SwiftData
// fetch) 가 끝나야 입력이 모이고 점수가 계산된다. 그 사이 Hero/Discover 가
// placeholder 상태로 노출돼 "켜자마자 홈이 비어 보이는" 인상을 준다.
//
// 해결: 점수 계산 결과 자체를 동일한 PersistedSetting JSON blob 패턴으로 별도
// 키 `cache.scoredRecommendations` 에 저장해두고, 부트 직후 `bootTask` 의 380ms
// 지연 전에 즉시 hydrate 한다 → 첫 프레임에 Hero/Discover 가 곧장 그려진다.
//
// 정책:
//   • Stale-while-revalidate: 신선도 무관 즉시 표시. recomputeCachesIfNeeded()
//     가 새 결과를 만들면 자연스럽게 덮어쓴다.
//   • Hard TTL 24h: 너무 오래된 캐시(예: 한 달 전 라이브) 는 노이즈로 차단.
//   • 라이브가 종료된 채널이 첫 프레임에 잠깐 보일 수 있으나, 380ms+API 후의
//     recompute 가 정정한다(목표 = 즉시성 우선).

import Foundation
import CViewCore
import CViewPersistence

/// `HomeRecommendationEngine.ScoredChannel` 의 직렬화용 DTO.
///
/// `ScoredChannel` 자체는 SwiftUI Identifiable 이지만 Codable 이 아니라서
/// 디스크 저장에는 plain struct 가 필요하다. `LiveChannelItem` 은 이미 Codable
/// 을 채택하고 있다(기존 `cache.liveChannels` 가 동일 패턴 사용).
public struct CachedScoredChannel: Codable, Sendable {
    public let channel: LiveChannelItem
    public let score: Double
    public let reasons: [String]
    public let cachedAt: Date

    public init(channel: LiveChannelItem, score: Double, reasons: [String], cachedAt: Date) {
        self.channel = channel
        self.score = score
        self.reasons = reasons
        self.cachedAt = cachedAt
    }
}

/// 추천 결과를 PersistedSetting JSON blob 으로 저장/복원하는 헬퍼.
@MainActor
public enum HomeRecommendationCache {

    /// PersistedSetting 키 — 다른 cache.* 키들과 동일 네임스페이스 규칙.
    public static let key = "cache.scoredRecommendations"

    /// Hard TTL — 24h 초과 캐시는 무시. 신선도 보장이 아니라 노이즈 방지용.
    public static let ttl: TimeInterval = 86_400

    /// 추천 결과를 디스크에 저장 (fire-and-forget 권장).
    ///
    /// 빈 배열이면 저장하지 않는다(불필요한 디스크 쓰기 방지). 직렬화 실패는
    /// 로그 한 줄로 무시 — 캐시 저장 실패가 사용자 경험을 바꿀 이유가 없다.
    public static func save(
        _ items: [HomeRecommendationEngine.ScoredChannel],
        store: DataStore
    ) async {
        guard !items.isEmpty else { return }
        let now = Date()
        let dtos = items.map {
            CachedScoredChannel(
                channel: $0.channel,
                score: $0.score,
                reasons: $0.reasons,
                cachedAt: now
            )
        }
        do {
            try await store.saveSetting(key: key, value: dtos)
        } catch {
            // 캐시 저장 실패는 silently ignore — 다음 recompute 사이클에서 재시도.
            print("[HomeRecommendationCache] save 실패: \(error)")
        }
    }

    /// 디스크에서 복원. 24h 초과 캐시는 nil 반환.
    ///
    /// 복원된 결과는 `ScoredChannel` 로 그대로 매핑되어 `cachedRecommendations`
    /// 에 즉시 주입할 수 있다. 첫 항목이 Hero, 나머지가 Discover 그리드를 채움.
    public static func load(store: DataStore) async -> [HomeRecommendationEngine.ScoredChannel]? {
        do {
            guard let dtos = try await store.loadSetting(key: key, as: [CachedScoredChannel].self) else {
                return nil
            }
            guard !dtos.isEmpty else { return nil }
            // hard TTL — 첫 항목의 cachedAt 만 체크 (모두 동일 시점에 저장됨).
            if let first = dtos.first, Date().timeIntervalSince(first.cachedAt) > ttl {
                return nil
            }
            return dtos.map {
                HomeRecommendationEngine.ScoredChannel(
                    channel: $0.channel,
                    score: $0.score,
                    reasons: $0.reasons
                )
            }
        } catch {
            // 디코딩 실패(스키마 변경 등) 는 silently ignore — 캐시 무시하고
            // 새로 계산된 결과를 다음 recompute 가 채움.
            print("[HomeRecommendationCache] load 실패: \(error)")
            return nil
        }
    }
}
