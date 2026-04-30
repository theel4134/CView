// MARK: - AppState+Widget.swift
// 위젯 스냅샷 작성기 보유 + 현재 AppState 로부터 WidgetSnapshot 캡처
//
// [Phase 1: Widget 통합 2026-04-24]

import Foundation
import CViewCore

extension AppState {

    // MARK: - Widget Snapshot Writer

    // associated property 우회: AppState 가 final class 이므로 ObjectIdentifier 기반 storage 사용
    private static var writerStorage: [ObjectIdentifier: WidgetSnapshotWriter] = [:]
    private static var maintenanceTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]
    private static let widgetLock = NSLock()

    /// 위젯 스냅샷 작성 액터 (싱글턴 per AppState 인스턴스).
    var widgetSnapshotWriter: WidgetSnapshotWriter {
        let key = ObjectIdentifier(self)
        AppState.widgetLock.lock()
        defer { AppState.widgetLock.unlock() }
        if let existing = AppState.writerStorage[key] { return existing }
        let writer = WidgetSnapshotWriter()
        AppState.writerStorage[key] = writer
        return writer
    }

    fileprivate var widgetMaintenanceTask: Task<Void, Never>? {
        get {
            let key = ObjectIdentifier(self)
            AppState.widgetLock.lock()
            defer { AppState.widgetLock.unlock() }
            return AppState.maintenanceTaskStorage[key]
        }
        set {
            let key = ObjectIdentifier(self)
            AppState.widgetLock.lock()
            defer { AppState.widgetLock.unlock() }
            AppState.maintenanceTaskStorage[key] = newValue
        }
    }

    // MARK: - Snapshot Capture

    /// 현재 AppState 로부터 위젯에 표시할 스냅샷을 합성.
    func captureWidgetSnapshot() -> WidgetSnapshot {
        let following = (homeViewModel?.followingChannels ?? [])
            .prefix(20)  // 위젯에 의미 있는 개수만
            .map { WidgetLiveItem(from: $0) }

        let nowWatching: WidgetLiveItem? = {
            guard let pvm = playerViewModel,
                  let cid = pvm.currentChannelId,
                  !cid.isEmpty
            else { return nil }
            // 팔로잉 목록에서 같은 채널을 찾아 메타데이터 보완
            if let match = homeViewModel?.followingChannels.first(where: { $0.channelId == cid }) {
                return WidgetLiveItem(from: match)
            }
            // 팔로잉이 아닌 채널이면 라이브 목록에서 검색
            if let match = homeViewModel?.liveChannels.first(where: { $0.channelId == cid }) {
                return WidgetLiveItem(from: match)
            }
            return nil
        }()

        return WidgetSnapshot(
            generatedAt: Date(),
            isLoggedIn: isLoggedIn,
            followingLives: Array(following),
            nowWatching: nowWatching
        )
    }

    /// 스냅샷을 캡처하고 작성기에 디바운스 스케줄.
    func scheduleWidgetSnapshotUpdate() {
        let snapshot = captureWidgetSnapshot()
        let writer = widgetSnapshotWriter
        Task {
            await writer.schedule(snapshot: snapshot)
        }
    }

    // MARK: - Maintenance Timer

    /// 5분 backstop 타이머를 시작 (initialize 직후 1회 호출).
    /// 명시적 이벤트(시청 시작/종료, 팔로잉 갱신) 외에도 안정적으로 갱신 보장.
    func startWidgetSnapshotMaintenance() {
        // 즉시 1회 캡처
        scheduleWidgetSnapshotUpdate()

        // 기존 타이머가 있으면 취소
        widgetMaintenanceTask?.cancel()
        widgetMaintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))  // 5분
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.scheduleWidgetSnapshotUpdate()
                }
            }
        }
    }
}

