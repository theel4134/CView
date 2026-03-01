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
        let timestamp: Date
    }

    /// 캐시에서 가져오기 (TTL 확인)
    public func get<T: Sendable>(key: String, ttl: TimeInterval) -> T? {
        guard let entry = storage[key],
              Date.now.timeIntervalSince(entry.timestamp) < ttl,
              let value = entry.data as? T else {
            return nil
        }
        return value
    }

    /// 캐시에 저장
    public func set<T: Sendable>(key: String, value: T) {
        // 용량 초과 시 오래된 항목 제거
        if storage.count >= maxEntries {
            evictOldest()
        }
        storage[key] = CacheEntry(data: value, timestamp: .now)
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

    /// 가장 오래된 25% 항목 제거
    private func evictOldest() {
        let sorted = storage.sorted { $0.value.timestamp < $1.value.timestamp }
        let toRemove = max(1, sorted.count / 4)
        for entry in sorted.prefix(toRemove) {
            storage.removeValue(forKey: entry.key)
        }
    }
}
