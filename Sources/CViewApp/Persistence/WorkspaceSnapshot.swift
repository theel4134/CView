// MARK: - WorkspaceSnapshot.swift
// 앱 종료/백그라운드 진입 시점에 워크스페이스 상태를 캡처해
// 다음 실행에서 복원하기 위한 스냅샷.
//
// v1 캡처 항목:
//   - selectedSidebarItem (sidebar)
//   - followingHubMode    (라이브 메뉴 모드)
//   - multiLive channelIds
//   - multiChat channelIds
//   - pendingSearchQuery
//   - pendingMetricsTab
//
// 저장 위치: UserDefaults("WorkspaceSnapshot.v1")
// 저장 시점: willResignActive / willTerminate
// 복원 시점: AppLifecycle.handleAppBecameActive 첫 1회 (cold-start 직후)
//
// [Plan 2026-04-30 SES-1]

import Foundation

// MARK: - Snapshot Model

struct WorkspaceSnapshot: Codable, Sendable, Equatable {
    var version: Int = 1
    var sidebar: String?              // AppRouter.SidebarItem.rawValue
    var hubMode: String?              // FollowingHubMode.rawValue
    var multiLiveChannelIds: [String] = []
    var multiChatChannelIds: [String] = []
    var pendingSearchQuery: String?
    var pendingMetricsTab: String?    // MetricsDashboardTab.rawValue
    var smartQueueChannelIds: [String] = []
    var savedAt: Date = .init()
}

// MARK: - Store (actor — atomic write)

actor WorkspaceStateStore {
    static let shared = WorkspaceStateStore()

    private let defaultsKey = "WorkspaceSnapshot.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: WorkspaceSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            // 조용히 무시 — 다음 호출에서 재시도
        }
    }

    func load() -> WorkspaceSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: defaultsKey)
    }
}
