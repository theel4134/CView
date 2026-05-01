// MARK: - DeepLinkRouter.swift
// 위젯/외부 URL Scheme 호출을 메인 앱 라우팅으로 변환
//
// [Phase 1: Widget 통합 2026-04-24]
// [Phase 2: ACT-2 확장 2026-04-30]
// 지원 URL Scheme:
//   cview://live?channelId=XYZ[&mode=watch|multi|chatonly]  → 라이브 (mode 프리셋)
//   cview://channel?channelId=XYZ                            → 채널 상세
//   cview://following[?mode=explore|watch|multi]             → 팔로잉(라이브) 메뉴
//   cview://multilive                                        → 멀티라이브 (= following?mode=multi)
//   cview://home                                             → 홈
//   cview://search[?q=keyword]                               → 검색
//   cview://clip?id=UID                                      → 클립 재생
//   cview://metrics[?tab=overview|channels|monitoring]       → 메트릭 대시보드

import Foundation
import SwiftUI

// MARK: - DeepLink

/// URL Scheme 으로 들어온 명령을 표현하는 enum.
enum DeepLink: Equatable, Sendable {
    case live(channelId: String, mode: LiveOpenMode)
    case channel(channelId: String)
    case following(mode: FollowingHubMode?)
    case multiLive
    case home
    case search(query: String?)
    case clip(uid: String)
    case metrics(tab: MetricsDashboardTab?)

    /// `cview://...` URL 을 파싱.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "cview" else { return nil }

        let host = (url.host ?? "").lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value
        }
        let channelId = q("channelId")

        switch host {
        case "live":
            guard let id = channelId, !id.isEmpty else { return nil }
            let modeRaw = q("mode")?.lowercased()
            let mode: LiveOpenMode = {
                switch modeRaw {
                case "multi":    return .multi
                case "chatonly", "chat-only", "chat": return .chatOnly
                default:         return .watch
                }
            }()
            self = .live(channelId: id, mode: mode)

        case "channel":
            guard let id = channelId, !id.isEmpty else { return nil }
            self = .channel(channelId: id)

        case "following":
            let mode = q("mode").flatMap { FollowingHubMode(rawValue: $0.lowercased()) }
            self = .following(mode: mode)

        case "multilive":
            self = .multiLive

        case "home", "":
            self = .home

        case "search":
            let raw = q("q") ?? q("query")
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .search(query: (trimmed?.isEmpty ?? true) ? nil : trimmed)

        case "clip":
            let uid = (q("id") ?? q("uid") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { return nil }
            self = .clip(uid: uid)

        case "metrics":
            let tab = q("tab").flatMap { MetricsDashboardTab(rawValue: $0.lowercased()) }
            self = .metrics(tab: tab)

        default:
            return nil
        }
    }

    /// `CViewAction` 으로 변환 (없으면 nil — 직접 라우팅 필요).
    var asAction: CViewAction? {
        switch self {
        case .live(let id, let mode):       return .openLive(channelId: id, mode: mode)
        case .channel(let id):              return .openChannel(channelId: id)
        case .following(let mode):
            if let m = mode { return .switchLiveMode(m) }
            return nil
        case .multiLive:                    return .switchLiveMode(.multi)
        case .home:                         return .openHome
        case .search(let query):            return .openSearch(query: query)
        case .clip(let uid):                return .openClip(clipUID: uid)
        case .metrics(let tab):             return .openMetrics(tab: tab)
        }
    }
}

// MARK: - DeepLinkRouter

/// 외부에서 들어온 `DeepLink` 를 `AppRouter` + `AppState` 에 적용.
///
/// 사용:
/// - `.onOpenURL { url in router.handle(url: url, ...) }`  (warm start)
/// - `AppLifecycle` cold-start hook 에서도 동일 호출
@MainActor
enum DeepLinkRouter {

    /// URL 을 받아 라우팅 적용. 알 수 없는 스킴/형식은 조용히 무시.
    static func handle(
        url: URL,
        router: AppRouter,
        appState: AppState
    ) {
        guard let link = DeepLink(url: url) else { return }
        apply(link, router: router, appState: appState)
    }

    /// 파싱된 `DeepLink` 를 직접 적용 (테스트 친화적).
    static func apply(
        _ link: DeepLink,
        router: AppRouter,
        appState: AppState
    ) {
        // 1) Action 으로 변환 가능한 케이스는 Registry 위임 (단일 진입점)
        if let action = link.asAction,
           let registry = appState.actionRegistry,
           registry.dispatch(action) {
            return
        }

        // 2) Registry 미바인딩/실패 시 fallback (기존 동작 유지)
        switch link {
        case .live(let channelId, _):
            router.selectedSidebarItem = .following
            router.navigate(to: .live(channelId: channelId))

        case .channel(let channelId):
            router.navigate(to: .channelDetail(channelId: channelId))

        case .following:
            router.selectedSidebarItem = .following

        case .multiLive:
            router.selectedSidebarItem = .following
            router.navigate(to: .multiLive)

        case .home:
            router.selectedSidebarItem = .home
            router.path = NavigationPath()

        case .search(let query):
            router.selectedSidebarItem = .search
            if let q = query { router.pendingSearchQuery = q }

        case .clip(let uid):
            router.navigate(to: .clip(clipUID: uid))

        case .metrics(let tab):
            router.selectedSidebarItem = .metrics
            appState.pendingMetricsTab = tab
        }
    }
}
