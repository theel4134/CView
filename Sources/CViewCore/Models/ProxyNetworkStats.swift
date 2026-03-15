// MARK: - ProxyNetworkStats.swift
// 로컬 프록시 네트워크 통계 스냅샷 (CViewCore — 모듈 간 공유 타입)

import Foundation

/// LocalStreamProxy가 수집한 네트워크 통계 스냅샷.
/// 프록시 계층의 요청/응답 성능을 실시간 모니터링하기 위한 구조체.
public struct ProxyNetworkStats: Sendable {

    // MARK: - 요청 통계

    /// 총 처리 요청 수 (누적)
    public let totalRequests: Int

    /// M3U8 요청 중 캐시 히트 수
    public let cacheHits: Int

    /// M3U8 요청 중 캐시 미스 수 (실제 CDN 요청 발생)
    public let cacheMisses: Int

    /// 에러 응답 수 (HTTP 4xx/5xx)
    public let errorCount: Int

    // MARK: - 데이터 전송

    /// 총 CDN 수신 바이트 (누적)
    public let totalBytesReceived: Int64

    /// 총 VLC 전달 바이트 (누적, 캐시 히트 포함)
    public let totalBytesServed: Int64

    // MARK: - 연결 상태

    /// 현재 활성 연결 수
    public let activeConnections: Int

    /// 연속 403 에러 수
    public let consecutive403Count: Int

    // MARK: - 응답 시간

    /// 최근 CDN 평균 응답 시간 (초) — 슬라이딩 윈도우
    public let avgResponseTime: Double

    /// 최근 CDN 최대 응답 시간 (초)
    public let maxResponseTime: Double

    // MARK: - 스냅샷 시각

    public let timestamp: Date

    // MARK: - 계산 프로퍼티

    /// 캐시 히트율 0.0~1.0
    public var cacheHitRatio: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Double(cacheHits) / Double(total)
    }

    /// CDN 수신 속도 (Mbps) — 최근 구간 기준
    public var receivedMbps: Double {
        0  // 외부에서 계산하여 주입
    }

    /// 에러율 0.0~1.0
    public var errorRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(errorCount) / Double(totalRequests)
    }

    // MARK: - Init

    public init(
        totalRequests: Int = 0,
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        errorCount: Int = 0,
        totalBytesReceived: Int64 = 0,
        totalBytesServed: Int64 = 0,
        activeConnections: Int = 0,
        consecutive403Count: Int = 0,
        avgResponseTime: Double = 0,
        maxResponseTime: Double = 0,
        timestamp: Date = Date()
    ) {
        self.totalRequests = totalRequests
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.errorCount = errorCount
        self.totalBytesReceived = totalBytesReceived
        self.totalBytesServed = totalBytesServed
        self.activeConnections = activeConnections
        self.consecutive403Count = consecutive403Count
        self.avgResponseTime = avgResponseTime
        self.maxResponseTime = maxResponseTime
        self.timestamp = timestamp
    }
}
