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

    private var dataStore: DataStore?

    public init(dataStore: DataStore? = nil) {
        self.dataStore = dataStore
        self.player = .default
        self.chat = .default
        self.general = .default
        self.appearance = .default
        self.network = .default
        self.metrics = .default
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

        // Equality 체크 — 동일 값 할당으로 인한 @Observable 재평가 방지
        if let val = await p, val != self.player { self.player = val }
        if let val = await c, val != self.chat { self.chat = val }
        if let val = await g, val != self.general { self.general = val }
        if let val = await a, val != self.appearance { self.appearance = val }
        if let val = await n, val != self.network { self.network = val }
        if let val = await m, val != self.metrics { self.metrics = val }

        Log.persistence.info("Settings loaded")
    }

    /// 설정 저장
    public func save() async {
        guard let store = dataStore else { return }

        do {
            try await store.saveSetting(key: "player", value: player)
            try await store.saveSetting(key: "chat", value: chat)
            try await store.saveSetting(key: "general", value: general)
            try await store.saveSetting(key: "appearance", value: appearance)
            try await store.saveSetting(key: "network", value: network)
            try await store.saveSetting(key: "metrics", value: metrics)
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
        await save()
    }
}
