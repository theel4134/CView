// MARK: - WidgetSnapshotWriter.swift
// 메인 앱이 위젯 표시용 스냅샷을 주기적/이벤트 기반으로 기록하는 액터
//
// [Phase 1: Widget 통합 2026-04-24]
// 호출 트리거:
//   1. 앱 launch 직후 (initialize 완료 시점)
//   2. 팔로잉 라이브 목록 갱신 완료 시 (HomeViewModel.loadFollowingChannels 직후)
//   3. 라이브 시청 시작/종료 시 (PlayerViewModel)
//   4. 5분 간격 backstop 타이머 (AppLifecycle)
//
// 작성 후 WidgetCenter.reloadAllTimelines() 호출로 위젯 즉시 갱신.

import Foundation
import WidgetKit
import CViewCore

/// 위젯에 노출할 `WidgetSnapshot` 을 App Group container 에 기록하는 액터.
///
/// 다음을 보장:
/// - 동시 호출 시 직렬화 (actor)
/// - 짧은 시간 내 중복 호출 합치기 (200ms 디바운스)
/// - 직전과 동일한 데이터면 디스크 쓰기/timeline reload 생략
public actor WidgetSnapshotWriter {

    // MARK: - State

    private var lastWrittenSnapshot: WidgetSnapshot?
    private var debounceTask: Task<Void, Never>?

    public init() {}

    // MARK: - Public API

    /// 새 스냅샷을 기록 요청. 200ms 디바운스 적용.
    /// - Parameter snapshot: 작성할 스냅샷 (메인 앱 측에서 즉시 캡처)
    public func schedule(snapshot: WidgetSnapshot) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.write(snapshot: snapshot)
        }
    }

    /// 디바운스 없이 즉시 기록 (테스트/명시적 강제 갱신용).
    public func writeNow(snapshot: WidgetSnapshot) async {
        debounceTask?.cancel()
        await write(snapshot: snapshot)
    }

    // MARK: - Internals

    private func write(snapshot: WidgetSnapshot) async {
        // 변경 없음 → 디스크/타임라인 reload 생략
        if let last = lastWrittenSnapshot, isEffectivelyEqual(last, snapshot) {
            return
        }

        do {
            try snapshot.persist()
            lastWrittenSnapshot = snapshot
            await reloadTimelines()
        } catch {
            // 스냅샷 쓰기 실패는 무시 (다음 trigger에서 재시도)
        }
    }

    /// `generatedAt` 을 제외한 의미 있는 필드들이 동일한지 비교.
    private func isEffectivelyEqual(_ lhs: WidgetSnapshot, _ rhs: WidgetSnapshot) -> Bool {
        return lhs.isLoggedIn == rhs.isLoggedIn
            && lhs.followingLives == rhs.followingLives
            && lhs.nowWatching == rhs.nowWatching
    }

    @MainActor
    private func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - LiveChannelItem → WidgetLiveItem 변환

extension WidgetLiveItem {
    /// `LiveChannelItem` 에서 위젯용 축약 모델 생성.
    public init(from item: LiveChannelItem) {
        self.init(
            channelId: item.channelId,
            channelName: item.channelName,
            channelImageURL: item.channelImageUrl.flatMap(URL.init(string:)),
            liveTitle: item.liveTitle,
            viewerCount: item.viewerCount,
            categoryName: item.categoryName,
            thumbnailURL: item.thumbnailUrl.flatMap(URL.init(string:))
        )
    }
}
