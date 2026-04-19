// MARK: - PlayerConstants.swift
// CViewPlayer 모듈 매직 넘버 상수화

import Foundation
import CoreMedia

// MARK: - ABR Controller

public enum ABRDefaults {
    /// 최소 대역폭 (500kbps)
    public static let minBandwidthBps: Double = 500_000
    /// 최대 대역폭 (50Mbps)
    public static let maxBandwidthBps: Double = 50_000_000
    /// 초기 대역폭 추정치 (5Mbps)
    public static let initialBandwidthEstimate: Double = 5_000_000
    /// 대역폭 안전 계수 (실제 대역폭의 85% 사용)
    /// [Quality] 0.7→0.85: 더 많은 대역폭 활용으로 높은 비트레이트 선택
    public static let bandwidthSafetyFactor: Double = 0.85
    /// 품질 상향 전환 임계값
    /// [Quality] 1.2→1.1: 10% 초과 시 업그레이드 → 더 적극적 최고 화질 전환
    public static let switchUpThreshold: Double = 1.1
    /// 품질 하향 전환 임계값
    /// [Fix 19] 0.8→0.7: 30% 안전 마진 확보 → 대역폭 변동 시 품질 진동 방지
    public static let switchDownThreshold: Double = 0.7
    /// 최소 품질 전환 간격 (초)
    /// [Fix 19] 5→8초: 대역폭 추정 안정화 시간 확보 → 잦은 화질 전환 방지
    public static let minSwitchInterval: TimeInterval = 8.0

    // MARK: Buffer-Aware ABR (flashls AutoLevelManager 참조)

    /// 동적 switchUp 상대 비트레이트 차이 최대값 (flashls: 0.5)
    public static let maxSwitchUpRatio: Double = 0.5
    /// 동적 switchDown 최소 보장 비율 (flashls: 2 × minGap)
    public static let minSwitchDownRatio: Double = 0.1
    /// 긴급 강등 시 최소 버퍼 비율 — bufferRatio < 이 값이면 즉시 강등
    /// flashls: 2 × bitrate[j] / lastBandwidth
    public static let emergencyBufferRatio: Double = 2.0
    /// 버퍼 인지형 ABR 사용 시 최소 필요 샘플 수
    public static let bufferAwareMinSamples: Int = 3

    // MARK: Dynamic Buffer Management (flashls AutoBufferManager 참조)

    /// 대역폭 히스토리 링 버퍼 최대 크기
    public static let bandwidthHistoryMaxSize: Int = 30
}

// MARK: - VLC Player Engine

public enum VLCDefaults {
    /// Normal 프로필 네트워크 캐싱 (ms)
    public static let normalNetworkCaching = 1500
    /// 저지연 프로필 네트워크 캐싱 (ms)
    public static let lowLatencyNetworkCaching = 400

    /// 스톨 감지 임계값 (초)
    public static let stallThresholdSecs: TimeInterval = 45
    /// 스톨 워치독 첫 체크 대기 (초)
    public static let watchdogInitialDelaySecs: UInt64 = 60
    /// 스톨 워치독 체크 주기 (초)
    public static let watchdogCheckIntervalSecs: UInt64 = 20
    /// VLC 진단 딜레이 (초)
    public static let diagnosticDelaySecs: UInt64 = 15
}

// MARK: - AVPlayer Engine

public enum AVPlayerDefaults {
    /// 스톨 무진행 타임아웃 (초)
    public static let stallTimeoutSecs: TimeInterval = 12.0
    /// 스톨 워치독 체크 간격 (나노초)
    public static let stallCheckIntervalNs: UInt64 = 3_000_000_000
    /// 재생 속도 변화 무시 임계값
    public static let rateChangeMinDelta: Float = 0.03
    /// CMTime preferredTimescale
    public static let preferredTimescale: CMTimeScale = 600
}

// MARK: - Low Latency Controller

public enum LatencyDefaults {
    /// 레이턴시 히스토리 최대 크기
    public static let historyMaxCount = 100
    /// 미세 조정 영역 PID 스케일링
    public static let mildAdjustmentFactor: Double = 0.05
    /// 속도 변경 최소 유의 변화량
    public static let rateSignificanceThreshold: Double = 0.005
    /// 비현실적 레이턴시 상한 (초)
    public static let maxRealisticLatencySecs: Double = 60
}

// MARK: - Local Stream Proxy

public enum ProxyDefaults {
    /// Keep-Alive 타임아웃 (초)
    /// 15초: 멀티라이브 4세션 시 stale 연결 빠른 회수 (30→15s)
    public static let keepAliveTimeout: TimeInterval = 15.0
    /// 프록시 요청 타임아웃 (초)
    public static let requestTimeout: TimeInterval = 15
    /// 프록시 리소스 타임아웃 (초)
    public static let resourceTimeout: TimeInterval = 30
    /// 호스트당 최대 연결 수
    /// 24: VLC HLS 모듈의 동시 세그먼트/매니페스트 요청 수용 (18→24)
    public static let maxConnectionsPerHost = 24
    /// 소켓 최대 수신 크기 (바이트)
    public static let maxReceiveLength = 65536
    /// 업스트림 요청 타임아웃 (초)
    public static let upstreamRequestTimeout: TimeInterval = 15
    /// 최대 동시 활성 연결 수
    /// 80: 멀티라이브 4세션 × ~12-15 연결/세션 = ~60 여유분 포함 (50→80)
    public static let maxActiveConnections = 80
    /// HLS 매니페스트(M3U8) 요청용 Accept-Encoding 헤더
    /// 매니페스트는 텍스트이므로 gzip으로 70-85% 압축 — 멀티라이브 4세션 × 초당 1회 폴링 시 대역폭 크게 절감.
    /// 세그먼트(TS/fMP4)는 이미 압축된 바이너리이므로 적용 대상 아님 (CPU만 소모).
    public static let manifestAcceptEncoding = "gzip, deflate"
}

// MARK: - Multi-Pane Quality

public enum MultiPaneDefaults {
    /// 5개 이상 pane 시 기본 높이 (pt)
    public static let minHeight: CGFloat = 360
    /// 멀티 pane 최대 비트레이트 기준 (8Mbps)
    public static let maxBitrate: Double = 8_000_000
}

// MARK: - Polling Intervals

public enum PollingDefaults {
    /// 라이브 상태 폴링 주기 (초)
    public static let liveStatusIntervalSecs: TimeInterval = 30
    /// 앱 배경 상태 폴링 주기 (초)
    public static let backgroundPollIntervalSecs: TimeInterval = 120
}

// MARK: - Stream Defaults

public enum StreamDefaults {
    /// CDN 토큰 예방적 갱신 주기 (초, 55분)
    public static let cdnTokenRefreshIntervalSecs: TimeInterval = 55 * 60
    /// 품질 복구 대기 시간 (초)
    public static let qualityRecoveryDelaySecs: TimeInterval = 10
    /// CDN 워밍 타임아웃 (초)
    public static let cdnWarmupTimeoutSecs: TimeInterval = 3
    /// 기본 매니페스트 갱신 주기 (초)
    public static let defaultManifestRefreshIntervalSecs: TimeInterval = 20
    /// VLC 연속 에러 재시도 임계값
    public static let maxConsecutiveEngineErrors: Int = 2
}

// MARK: - Multi-Live Bandwidth Coordinator (flashls 참조)

public enum MultiLiveBWDefaults {
    /// 대역폭 안전 계수 (총 대역폭의 75% 사용)
    public static let safetyFactor: Double = 0.75
    /// 스트림당 최소 보장 대역폭 (300kbps)
    public static let minPerStreamBitrate: Double = 300_000
    /// 집계 대역폭 히스토리 크기 (flashls: 30 samples)
    public static let historySize: Int = 30
    /// 버퍼 저수위 임계값 (초) — buffering 진입
    public static let lowBufferThreshold: TimeInterval = 3.0
    /// 버퍼 고수위 임계값 (초) — playing 복귀 (히스테리시스)
    public static let highBufferThreshold: TimeInterval = 6.0
    /// 선택 세션 대역폭 가중치 (1.5 = 50% 더 할당)
    public static let selectedSessionWeight: Double = 1.5
    /// 긴급 강등 평균 버퍼 임계값 (초)
    /// — 정말 위급 상황(버퍼 1초 미만)만 강등 → 일시적 지터로 인한 불필요한 화질 저하 차단
    public static let emergencyBufferThreshold: TimeInterval = 1.0
    /// 코디네이터 업데이트 주기 (초)
    /// [CPU 최적화] 5s → 8s — 멀티라이브 4채널 환경에서 BW 재배분 빈도를 줄여 메인 액터 부하 감소.
    /// 화질 강등은 emergencyBufferThreshold(1초) 트리거가 별도로 보호하므로 응답성 유지.
    public static let updateIntervalSecs: TimeInterval = 8.0
}

// MARK: - UI Defaults

public enum UIDefaults {
    /// 채팅 패널 너비
    public static let chatPaneWidth: CGFloat = 300
    /// 볼륨 증감 스텝
    public static let volumeStep: Float = 0.05
    /// 재생 속도 옵션
    public static let playbackRateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
}
