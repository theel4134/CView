// MARK: - DeepLinkRouter.swift
// 위젯/외부 URL Scheme 호출을 메인 앱 라우팅으로 변환
//
// [Phase 1: Widget 통합 2026-04-24]
// 지원 URL Scheme:
//   cview://live?channelId=XYZ        → 라이브 화면 + 자동 재생
//   cview://channel?channelId=XYZ     → 채널 상세
//   cview://following                 → 팔로잉(라이브) 메뉴
//   cview://multilive                 → 멀티라이브
//   cview://home                      → 홈

import Foundation
import SwiftUI

// MARK: - DeepLink

/// URL Scheme 으로 들어온 명령을 표현하는 enum.
public enum DeepLink: Equatable, Sendable {
    case live(channelId: String)
    case channel(channelId: String)
    case following
    case multiLive
    case home

    /// `cview://...` URL 을 파싱.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "cview" else { return nil }

        // host 가 명령, 쿼리에서 파라미터 추출
        let host = (url.host ?? "").lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let channelId = queryItems.first(where: { $0.name.lowercased() == "channelid" })?.value

        switch host {
        case "live":
            guard let id = channelId, !id.isEmpty else { return nil }
            self = .live(channelId: id)
        case "channel":
            guard let id = channelId, !id.isEmpty else { return nil }
            self = .channel(channelId: id)
        case "following":
            self = .following
        case "multilive":
            self = .multiLive
        case "home", "":
            self = .home
        default:
            return nil
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
        switch link {
        case .live(let channelId):
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
        }
    }
}
