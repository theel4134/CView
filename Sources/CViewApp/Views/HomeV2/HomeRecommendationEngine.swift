// MARK: - HomeRecommendationEngine.swift
// CViewApp - Rule-based recommendation scoring for HomeView_v2
//
// 개편 문서 (docs/home-screen-redesign-analysis-2026-04-24.md, P1-1) 의 점수 공식:
//   score = followingLive*100
//         + favoriteLive*80
//         + recentlyWatchedLive*60
//         + sameCategoryAsRecent*25
//         + viewerRankNormalized*15
//         - alreadyWatching*100

import Foundation
import CViewCore

@MainActor
public enum HomeRecommendationEngine {

    /// 단일 추천 결과 — 점수 + 하이라이트할 사유 라벨
    public struct ScoredChannel: Identifiable {
        public let channel: LiveChannelItem
        public let score: Double
        public let reasons: [String]
        public var id: String { channel.channelId }
    }

    public struct Inputs {
        public let candidates: [LiveChannelItem]
        public let followingChannelIds: Set<String>
        public let favoriteChannelIds: Set<String>
        public let recentChannelIds: Set<String>
        public let recentCategories: Set<String>
        public let alreadyWatchingChannelIds: Set<String>

        public init(
            candidates: [LiveChannelItem],
            followingChannelIds: Set<String>,
            favoriteChannelIds: Set<String>,
            recentChannelIds: Set<String>,
            recentCategories: Set<String>,
            alreadyWatchingChannelIds: Set<String>
        ) {
            self.candidates = candidates
            self.followingChannelIds = followingChannelIds
            self.favoriteChannelIds = favoriteChannelIds
            self.recentChannelIds = recentChannelIds
            self.recentCategories = recentCategories
            self.alreadyWatchingChannelIds = alreadyWatchingChannelIds
        }
    }

    /// 채점 후 score 내림차순으로 정렬해 반환. 점수 0 이하는 제외.
    public static func score(_ inputs: Inputs, limit: Int = 12) -> [ScoredChannel] {
        guard !inputs.candidates.isEmpty else { return [] }

        // 시청자 수 정규화 (max viewer 기준)
        let maxViewer = max(1, inputs.candidates.map(\.viewerCount).max() ?? 1)

        let results = inputs.candidates.map { ch -> ScoredChannel in
            var score: Double = 0
            var reasons: [String] = []

            if inputs.followingChannelIds.contains(ch.channelId) {
                score += 100
                reasons.append("팔로잉")
            }
            if inputs.favoriteChannelIds.contains(ch.channelId) {
                score += 80
                reasons.append("즐겨찾기")
            }
            if inputs.recentChannelIds.contains(ch.channelId) {
                score += 60
                reasons.append("최근 시청")
            }
            if let cat = ch.categoryName,
               !cat.isEmpty,
               inputs.recentCategories.contains(cat) {
                score += 25
                reasons.append("관심 카테고리")
            }
            // 시청자 수 정규화 (0.0 ~ 1.0) * 15
            let viewerNorm = Double(ch.viewerCount) / Double(maxViewer)
            score += viewerNorm * 15.0

            if inputs.alreadyWatchingChannelIds.contains(ch.channelId) {
                score -= 100
            }

            return ScoredChannel(channel: ch, score: score, reasons: reasons)
        }

        return results
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
