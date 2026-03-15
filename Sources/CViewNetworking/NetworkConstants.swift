// MARK: - NetworkConstants.swift
// CViewNetworking 모듈 매직 넘버 상수화

import Foundation

// MARK: - API Client

public enum APIDefaults {
    /// API 요청 타임아웃 (초)
    public static let requestTimeout: TimeInterval = 15
    /// API 리소스 타임아웃 (초)
    public static let resourceTimeout: TimeInterval = 30
    /// 캐시 정리 주기 (초, 5분)
    public static let cachePurgeInterval: TimeInterval = 300
    /// 기본 캐시 TTL (초, 5분)
    public static let defaultCacheTTL: TimeInterval = 300
    /// 전체 라이브 수집 최대 페이지
    public static let allLivesMaxPages = 200
    /// 429 Rate Limit 최대 재대기 (초)
    public static let maxRateLimitRetrySecs: TimeInterval = 30
    /// Clip Inkey 요청 타임아웃 (초)
    public static let clipInkeyTimeout: TimeInterval = 10
    /// VOD 스트림 정보 요청 타임아웃 (초)
    public static let vodStreamInfoTimeout: TimeInterval = 10
}

// MARK: - Image Cache

public enum ImageCacheDefaults {
    /// 디스크 캐시 최대 크기 (200MB)
    public static let diskCacheMaxSize = 200 * 1024 * 1024
    /// 디스크 캐시 최대 수명 (7일)
    public static let diskCacheMaxAge: TimeInterval = 7 * 24 * 3600
    /// 메모리 캐시 최대 항목 수
    public static let memoryCacheCountLimit = 200
    /// 메모리 캐시 최대 크기 (50MB)
    public static let memoryCacheSizeLimit = 50 * 1024 * 1024
    /// 디코딩 캐시 최대 항목 수
    public static let decodedCacheCountLimit = 150
    /// 디코딩 캐시 최대 크기 (80MB)
    public static let decodedCacheSizeLimit = 80 * 1024 * 1024
    /// 이미지 요청 타임아웃 (초)
    public static let requestTimeout: TimeInterval = 12
}

// MARK: - Response Cache

public enum ResponseCacheDefaults {
    /// 응답 캐시 최대 항목 수
    public static let maxEntries = 100
    /// 기본 캐시 TTL (초)
    public static let defaultTTL: TimeInterval = 300
}

// MARK: - Metrics Networking

public enum MetricsNetDefaults {
    /// 메트릭 요청 타임아웃 (초)
    public static let requestTimeout: TimeInterval = 10
    /// 메트릭 리소스 타임아웃 (초)
    public static let resourceTimeout: TimeInterval = 20
    /// 최대 WS 재연결 횟수
    public static let maxReconnectAttempts = 5
    /// 재연결 최대 백오프 딜레이 (초)
    public static let maxBackoffDelay: TimeInterval = 30.0
}

// MARK: - Cache TTL

public enum CacheTTLDefaults {
    /// 채널 정보 캐시 TTL (초)
    public static let channelInfo: TimeInterval = 300
    /// 기본 API 캐시 TTL (초)
    public static let defaultAPI: TimeInterval = 60
    /// stats/activeApp 캐시 TTL (초)
    public static let metricsStats: TimeInterval = 10
    /// 채널 메트릭 캐시 TTL (초)
    public static let metricsChannel: TimeInterval = 5
    /// 라이브 썸네일 캐시 TTL (초)
    public static let liveThumbnail: TimeInterval = 45
}
