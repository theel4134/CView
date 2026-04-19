// MARK: - CViewNetworking/ResponseCache.swift
// Actor 기반 응답 캐시

import Foundation
import CViewCore

/// 응답 캐시 (actor 기반, thread-safe)
public actor ResponseCache {
    private var storage: [String: CacheEntry] = [:]
    private let maxEntries: Int

    public init(maxEntries: Int = ResponseCacheDefaults.maxEntries) {
        self.maxEntries = maxEntries
    }

    struct CacheEntry {
        let data: any Sendable
        /// 최초 저장 시각 — TTL 계산용 (불변)
        let timestamp: Date
        /// 마지막 접근 시각 — LRU 퇴출용 (set/get 시 갱신)
        var lastAccess: Date
    }

    /// 캐시에서 가져오기 (TTL 확인)
    /// [Opt-N-2] 접근 시 lastAccess 갱신 — true LRU (hot entry가 FIFO로 퇴출되던 문제 해결)
    public func get<T: Sendable>(key: String, ttl: TimeInterval) -> T? {
        guard var entry = storage[key],
              Date.now.timeIntervalSince(entry.timestamp) < ttl,
              let value = entry.data as? T else {
            return nil
        }
        entry.lastAccess = .now
        storage[key] = entry
        return value
    }

    /// 캐시에 저장
    public func set<T: Sendable>(key: String, value: T) {
        // 용량 초과 시 오래된 항목 제거
        if storage.count >= maxEntries {
            evictOldest()
        }
        let now = Date.now
        storage[key] = CacheEntry(data: value, timestamp: now, lastAccess: now)
    }

    /// 특정 키 삭제
    public func remove(key: String) {
        storage.removeValue(forKey: key)
    }

    /// 전체 초기화
    public func clear() {
        storage.removeAll()
    }

    /// 만료된 항목 정리
    public func purgeExpired(defaultTTL: TimeInterval = ResponseCacheDefaults.defaultTTL) {
        let now = Date.now
        storage = storage.filter { now.timeIntervalSince($0.value.timestamp) < defaultTTL }
    }

    /// 가장 오래 미접근된 25% 항목 제거 (true LRU)
    /// [Opt-N-2] lastAccess 기준으로 정렬 → 자주 읽히는 엔트리 보존
    private func evictOldest() {
        let sorted = storage.sorted { $0.value.lastAccess < $1.value.lastAccess }
        let toRemove = max(1, sorted.count / 4)
        for entry in sorted.prefix(toRemove) {
            storage.removeValue(forKey: entry.key)
        }
    }
}
