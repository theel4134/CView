// MARK: - CViewAction.swift
// 모든 액션 진입점(Command Palette, Deep Link, Widget, App Intent)이 공유하는
// 단일 액션 모델. 라우팅 의존성을 분리해 unit-test가 가능하도록 순수 enum으로 둔다.
//
// [Plan 2026-04-30 ACT-1]

import Foundation

public enum LiveOpenMode: String, Sendable, Hashable, Codable {
    /// 단일 시청 (워치 모드 — 기존 `applyHubModePreset(.watch)`)
    case watch
    /// 멀티라이브 추가 (이미 시청 중이면 그대로, 아니면 추가 후 멀티 모드)
    case multi
    /// 채팅만 (chatOnly route)
    case chatOnly
}

// MARK: - CViewAction

/// Command Palette / DeepLink / Widget / AppIntent가 공유하는 단일 액션 enum.
///
/// 모든 진입점은 이 enum을 만들어 `CViewActionRegistry.dispatch(_:)`에 넘긴다.
/// Registry는 `AppRouter` + `AppState`를 주입받아 실제 사이드 이펙트를 수행한다.
enum CViewAction: Sendable, Hashable, Codable {
    /// 라이브 시청 화면으로 이동 (mode에 따라 watch/multi/chatOnly)
    case openLive(channelId: String, mode: LiveOpenMode)
    /// 채널 상세 시트 표시
    case openChannel(channelId: String)
    /// 멀티라이브 세션 추가 (라이브 메뉴 멀티 모드 전환)
    case addToMultiLive(channelId: String)
    /// 멀티채팅 세션 추가
    case addToMultiChat(channelId: String)
    /// 라이브 허브 모드 전환 (explore/watch/multi)
    case switchLiveMode(FollowingHubMode)
    /// 검색 화면 진입 (선택적 query)
    case openSearch(query: String?)
    /// 클립 재생
    case openClip(clipUID: String)
    /// 메트릭 대시보드 (선택적 탭)
    case openMetrics(tab: MetricsDashboardTab?)
    /// 홈 화면
    case openHome

    // MARK: Stable IDs (logging/dedupe)

    var id: String {
        switch self {
        case .openLive(let id, let mode): "openLive:\(id):\(mode.rawValue)"
        case .openChannel(let id):        "openChannel:\(id)"
        case .addToMultiLive(let id):     "addToMultiLive:\(id)"
        case .addToMultiChat(let id):     "addToMultiChat:\(id)"
        case .switchLiveMode(let m):      "switchLiveMode:\(m.rawValue)"
        case .openSearch(let q):          "openSearch:\(q ?? "")"
        case .openClip(let uid):          "openClip:\(uid)"
        case .openMetrics(let tab):       "openMetrics:\(tab?.rawValue ?? "")"
        case .openHome:                   "openHome"
        }
    }

    /// 사람이 읽을 수 있는 라벨 (로그/Command Palette 부제용)
    var displayLabel: String {
        switch self {
        case .openLive(_, let mode):
            switch mode {
            case .watch:    "라이브 시청"
            case .multi:    "멀티라이브 추가"
            case .chatOnly: "채팅만 열기"
            }
        case .openChannel:    "채널 상세"
        case .addToMultiLive: "멀티라이브에 추가"
        case .addToMultiChat: "멀티채팅에 추가"
        case .switchLiveMode(let m):
            switch m {
            case .explore: "탐색 모드"
            case .watch:   "시청 모드"
            case .multi:   "멀티 모드"
            }
        case .openSearch:  "검색 열기"
        case .openClip:    "클립 재생"
        case .openMetrics: "메트릭 열기"
        case .openHome:    "홈으로"
        }
    }

    // MARK: Validation

    /// 입력값을 검증해 정상화된 Action을 돌려주거나, 실패 시 nil.
    /// (channelId 빈 문자열, query 공백 only 등)
    var validated: CViewAction? {
        switch self {
        case .openLive(let id, let mode):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .openLive(channelId: trimmed, mode: mode)
        case .openChannel(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .openChannel(channelId: trimmed)
        case .addToMultiLive(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .addToMultiLive(channelId: trimmed)
        case .addToMultiChat(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .addToMultiChat(channelId: trimmed)
        case .openClip(let uid):
            let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .openClip(clipUID: trimmed)
        case .openSearch(let q):
            let trimmed = q?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .openSearch(query: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        case .switchLiveMode, .openMetrics, .openHome:
            return self
        }
    }
}
