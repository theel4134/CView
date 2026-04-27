// MARK: - CViewPersistence/SettingsStore.swift
// 설정 저장소 — SwiftData + @Observable

import Foundation
import SwiftData
import CViewCore

// MARK: - Live Settings Change Notifications

extension Notification.Name {
    /// 스트림 보정 모드(`StreamProxyMode`)가 변경되었음을 활성 스트림에 통지
    /// userInfo: ["mode": StreamProxyMode]
    public static let cviewStreamProxyModeChanged = Notification.Name("com.cview.streamProxyModeChanged")
}

/// 설정 저장소 — 카테고리별 분리된 설정 관리
@Observable
@MainActor
public final class SettingsStore {
    public var player: PlayerSettings {
        didSet {
            // 스트림 보정 모드 실시간 반영 — 변경 시 활성 스트림에 재시작 알림
            if oldValue.streamProxyMode != player.streamProxyMode {
                NotificationCenter.default.post(
                    name: .cviewStreamProxyModeChanged,
                    object: nil,
                    userInfo: ["mode": player.streamProxyMode]
                )
            }
        }
    }
    public var chat: ChatSettings
    public var general: GeneralSettings
    public var appearance: AppearanceSettings
    public var network: NetworkSettings
    public var metrics: MetricsSettings
    public var keyboard: KeyboardShortcutSettings
    public var channelNotifications: ChannelNotificationSettings
    public var multiLive: MultiLiveSettings
    public var multiChat: MultiChatSettings

    private var dataStore: DataStore?
    private var _saveDebounceTask: Task<Void, Never>?

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
        self.multiLive = .default
        self.multiChat = .default
    }

    /// DataStore 연결 후 설정 로드 (객체 교체 없이 in-place 업데이트)
    public func configure(dataStore: DataStore) async {
        self.dataStore = dataStore
        await load()
    }

    /// 저장된 설정 로드 (병렬 로드로 actor hop 최소화)
    public func load() async {
        guard let store = dataStore else { return }

        // 앱 종료 시 설정된 멀티채팅 초기화 플래그 확인
        let shouldClearMultiChat = UserDefaults.standard.bool(forKey: "multiChatShouldClear")
        if shouldClearMultiChat {
            UserDefaults.standard.removeObject(forKey: "multiChatShouldClear")
        }

        // 모든 설정 로드를 동시에 시작 — DataStore actor hop 5회→1회 수준으로 단축
        async let p = loadSettingLogged(from: store, key: "player", as: PlayerSettings.self)
        async let c = loadSettingLogged(from: store, key: "chat", as: ChatSettings.self)
        async let g = loadSettingLogged(from: store, key: "general", as: GeneralSettings.self)
        async let a = loadSettingLogged(from: store, key: "appearance", as: AppearanceSettings.self)
        async let n = loadSettingLogged(from: store, key: "network", as: NetworkSettings.self)
        async let m = loadSettingLogged(from: store, key: "metrics", as: MetricsSettings.self)
        async let k = loadSettingLogged(from: store, key: "keyboard", as: KeyboardShortcutSettings.self)
        async let cn = loadSettingLogged(from: store, key: "channelNotifications", as: ChannelNotificationSettings.self)
        async let ml = loadSettingLogged(from: store, key: "multiLive", as: MultiLiveSettings.self)
        async let mc = loadSettingLogged(from: store, key: "multiChat", as: MultiChatSettings.self)

        // Equality 체크 — 동일 값 할당으로 인한 @Observable 재평가 방지
        if let val = await p, val != self.player { self.player = val }
        if let val = await c, val != self.chat { self.chat = val }
        if let val = await g, val != self.general { self.general = val }
        if let val = await a, val != self.appearance { self.appearance = val }
        if let val = await n, val != self.network { self.network = val }
        if let val = await m, val != self.metrics { self.metrics = val }
        if let val = await k, val != self.keyboard { self.keyboard = val }
        if let val = await cn, val != self.channelNotifications { self.channelNotifications = val }
        if let val = await ml, val != self.multiLive { self.multiLive = val }
        if shouldClearMultiChat {
            // 종료 시 플래그가 설정되었으므로 저장된 멀티채팅 세션 무시 + DB에서도 초기화
            self.multiChat = .default
            try? await store.saveSetting(key: "multiChat", value: MultiChatSettings.default)
        } else if let val = await mc, val != self.multiChat {
            self.multiChat = val
        }

        Log.persistence.info("Settings loaded")
    }

    /// 설정 로드 + 에러 로깅 래퍼 (async let 병렬 로드 유지)
    private func loadSettingLogged<T: Codable & Equatable & Sendable>(
        from store: DataStore, key: String, as type: T.Type
    ) async -> T? {
        do {
            return try await store.loadSetting(key: key, as: type)
        } catch {
            Log.persistence.warning("Setting '\(key)' load failed: \(error.localizedDescription)")
            return nil
        }
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
            let metricsVal = self.metrics.normalized()
            let keyboardVal = self.keyboard
            let channelNotificationsVal = self.channelNotifications
            let multiLiveVal = self.multiLive
            let multiChatVal = self.multiChat

            // DataStore는 actor이므로 순차 실행됨 — TaskGroup 오버헤드 없이 직접 호출
            try await store.saveSetting(key: "player", value: playerVal)
            try await store.saveSetting(key: "chat", value: chatVal)
            try await store.saveSetting(key: "general", value: generalVal)
            try await store.saveSetting(key: "appearance", value: appearanceVal)
            try await store.saveSetting(key: "network", value: networkVal)
            try await store.saveSetting(key: "metrics", value: metricsVal)
            try await store.saveSetting(key: "keyboard", value: keyboardVal)
            try await store.saveSetting(key: "channelNotifications", value: channelNotificationsVal)
            try await store.saveSetting(key: "multiLive", value: multiLiveVal)
            try await store.saveSetting(key: "multiChat", value: multiChatVal)
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
        multiLive = .default
        multiChat = .default
        await save()
    }

    // MARK: - Channel Notification Helpers

    /// 채널별 알림 설정 조회 — 없으면 기본값(all-true) 반환
    public func channelNotificationSetting(for channelId: String, channelName: String = "") -> ChannelNotificationSetting {
        channelNotifications.setting(for: channelId, channelName: channelName)
    }

    /// 채널별 알림 설정 업데이트 및 저장 (0.5초 디바운스)
    public func updateChannelNotification(_ setting: ChannelNotificationSetting) {
        channelNotifications.update(setting)
        scheduleDebouncedSave()
    }

    /// 0.5초 디바운스 — 연속 변경 시 마지막 1회만 저장
    public func scheduleDebouncedSave() {
        _saveDebounceTask?.cancel()
        _saveDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// 채널별 알림 설정을 Sendable 스냅샷으로 반환 (cross-actor 전달용)
    public func channelNotificationsSnapshot() -> ChannelNotificationSettings {
        channelNotifications
    }
}
