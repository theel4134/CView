// MARK: - ProxyNetworkStatsTests.swift
// CViewCore 프록시 네트워크 통계 테스트

import Testing
import Foundation
@testable import CViewCore

@Suite("ProxyNetworkStats")
struct ProxyNetworkStatsTests {

    @Test("기본 init — 모두 0")
    func defaultInit() {
        let stats = ProxyNetworkStats()
        #expect(stats.totalRequests == 0)
        #expect(stats.cacheHits == 0)
        #expect(stats.cacheMisses == 0)
        #expect(stats.errorCount == 0)
        #expect(stats.totalBytesReceived == 0)
        #expect(stats.totalBytesServed == 0)
        #expect(stats.activeConnections == 0)
        #expect(stats.consecutive403Count == 0)
        #expect(stats.avgResponseTime == 0)
        #expect(stats.maxResponseTime == 0)
    }

    @Test("cacheHitRatio — 정상 계산")
    func cacheHitRatio() {
        let stats = ProxyNetworkStats(cacheHits: 7, cacheMisses: 3)
        #expect(stats.cacheHitRatio == 0.7)
    }

    @Test("cacheHitRatio — 모두 0이면 0")
    func cacheHitRatioZero() {
        let stats = ProxyNetworkStats()
        #expect(stats.cacheHitRatio == 0)
    }

    @Test("cacheHitRatio — 100% 히트")
    func cacheHitRatioFull() {
        let stats = ProxyNetworkStats(cacheHits: 10, cacheMisses: 0)
        #expect(stats.cacheHitRatio == 1.0)
    }

    @Test("errorRate — 정상 계산")
    func errorRate() {
        let stats = ProxyNetworkStats(totalRequests: 100, errorCount: 5)
        #expect(stats.errorRate == 0.05)
    }

    @Test("errorRate — 요청 0이면 0")
    func errorRateZero() {
        let stats = ProxyNetworkStats()
        #expect(stats.errorRate == 0)
    }

    @Test("receivedMbps — 항상 0")
    func receivedMbps() {
        let stats = ProxyNetworkStats(totalBytesReceived: 1_000_000)
        #expect(stats.receivedMbps == 0)
    }
}
