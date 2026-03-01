// MARK: - CViewPersistence/SettingsStore.swift
// 설정 저장소 — SwiftData + @Observable

import Foundation
import SwiftData
import CViewCore

/// 설정 저장소 — 카테고리별 분리된 설정 관리
@Observable
@MainActor
public final class SettingsStore {
    public var player: PlayerSettings
    public var chat: ChatSettings
    public var general: GeneralSettings
    public var appearance: AppearanceSettings
    public var network: NetworkSettings
    public var metrics: MetricsSettings
    public var keyboard: KeyboardShortcutSettings
    public var channelNotifications: ChannelNotificationSettings

    private var dataStore: DataStore?

    public init(dataStore: DataStore? = nil) {
        self.dataStore = dataStore
        self.player = .default
        self.chat = .default
        self.general = .default
        self.appearance = .default
        self.network = .default
        self.metrics = .default
        self.keyboard = .default
        self.channelNotifications = .default
    }

    /// DataStore 연결 후 설정 로드 (객체 교체 없이 in-place 업데이트)
    public func configure(dataStore: DataStore) async {
        self.dataStore = dataStore
        await load()
    }

    /// 저장된 설정 로드 (병렬 로드로 actor hop 최소화)
    public func load() async {
        guard let store = dataStore else { return }

        // 모든 설정 로드를 동시에 시작 — DataStore actor hop 5회→1회 수준으로 단축
        async let p = try? store.loadSetting(key: "player", as: PlayerSettings.self)
        async let c = try? store.loadSetting(key: "chat", as: ChatSettings.self)
        async let g = try? store.loadSetting(key: "general", as: GeneralSettings.self)
        async let a = try? store.loadSetting(key: "appearance", as: AppearanceSettings.self)
        async let n = try? store.loadSetting(key: "network", as: NetworkSettings.self)
        async let m = try? store.loadSetting(key: "metrics", as: MetricsSettings.self)
        async let k = try? store.loadSetting(key: "keyboard", as: KeyboardShortcutSettings.self)
        async let cn = try? store.loadSetting(key: "channelNotifications", as: ChannelNotificationSettings.self)

        // Equality 체크 — 동일 값 할당으로 인한 @Observable 재평가 방지
        if let val = await p, val != self.player { self.player = val }
        if let val = await c, val != self.chat { self.chat = val }
        if let val = await g, val != self.general { self.general = val }
        if let val = await a, val != self.appearance { self.appearance = val }
        if let val = await n, val != self.network { self.network = val }
        if let val = await m, val != self.metrics { self.metrics = val }
        if let val = await k, val != self.keyboard { self.keyboard = val }
        if let val = await cn, val != self.channelNotifications { self.channelNotifications = val }

        Log.persistence.info("Settings loaded")
    }

    /// 설정 저장 — 8개 설정을 병렬로 저장하여 총 대기 시간 단축
    public func save() async {
        guard let store = dataStore else { return }

        do {
            // @MainActor 프로퍼티를 로컬 변수로 사전 캡처하여 TaskGroup 내 actor 격리 위반 방지
            let playerVal = self.player
            let chatVal = self.chat
            let generalVal = self.general
            let appearanceVal = self.appearance
            let networkVal = self.network
            let metricsVal = self.metrics
            let keyboardVal = self.keyboard
            let channelNotificationsVal = self.channelNotifications

            // TaskGroup으로 병렬 저장 — 각 항목의 I/O 대기가 겹침
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await store.saveSetting(key: "player", value: playerVal) }
                group.addTask { try await store.saveSetting(key: "chat", value: chatVal) }
                group.addTask { try await store.saveSetting(key: "general", value: generalVal) }
                group.addTask { try await store.saveSetting(key: "appearance", value: appearanceVal) }
                group.addTask { try await store.saveSetting(key: "network", value: networkVal) }
                group.addTask { try await store.saveSetting(key: "metrics", value: metricsVal) }
                group.addTask { try await store.saveSetting(key: "keyboard", value: keyboardVal) }
                group.addTask { try await store.saveSetting(key: "channelNotifications", value: channelNotificationsVal) }
                try await group.waitForAll()
            }
            Log.persistence.info("Settings saved")
        } catch {
            Log.persistence.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    /// 모든 설정 초기화
    public func resetAll() async {
        player = .default
        chat = .default
        general = .default
        appearance = .default
        network = .default
        metrics = .default
        keyboard = .default
        channelNotifications = .default
        await save()
    }

    // MARK: - Channel Notification Helpers

    /// 채널별 알림 설정 조회 — 없으면 기본값(all-true) 반환
    public func channelNotificationSetting(for channelId: String, channelName: String = "") -> ChannelNotificationSetting {
        channelNotifications.setting(for: channelId, channelName: channelName)
    }

    /// 채널별 알림 설정 업데이트 및 저장
    public func updateChannelNotification(_ setting: ChannelNotificationSetting) async {
        channelNotifications.update(setting)
        await save()
    }

    /// 채널별 알림 설정을 Sendable 스냅샷으로 반환 (cross-actor 전달용)
    public func channelNotificationsSnapshot() -> ChannelNotificationSettings {
        channelNotifications
    }
}
