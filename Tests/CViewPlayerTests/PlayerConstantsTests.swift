// MARK: - PlayerConstantsTests.swift
// CViewPlayer - 상수값 회귀 테스트

import Testing
@testable import CViewPlayer

// MARK: - ABRDefaults

@Suite("ABRDefaults")
struct ABRDefaultsTests {

    @Test("대역폭 범위 및 초기값")
    func bandwidthValues() {
        #expect(ABRDefaults.minBandwidthBps == 500_000)
        #expect(ABRDefaults.maxBandwidthBps == 50_000_000)
        #expect(ABRDefaults.initialBandwidthEstimate == 5_000_000)
    }

    @Test("안전 계수 및 전환 임계값")
    func switchThresholds() {
        #expect(ABRDefaults.bandwidthSafetyFactor == 0.7)
        #expect(ABRDefaults.switchUpThreshold == 1.2)
        #expect(ABRDefaults.switchDownThreshold == 0.8)
    }

    @Test("최소 전환 간격")
    func minSwitchInterval() {
        #expect(ABRDefaults.minSwitchInterval == 5.0)
    }
}

// MARK: - VLCDefaults

@Suite("VLCDefaults")
struct VLCDefaultsTests {

    @Test("네트워크 캐싱 값")
    func networkCaching() {
        #expect(VLCDefaults.normalNetworkCaching == 1500)
        #expect(VLCDefaults.lowLatencyNetworkCaching == 400)
    }

    @Test("스톨 및 워치독 설정")
    func stallAndWatchdog() {
        #expect(VLCDefaults.stallThresholdSecs == 45)
        #expect(VLCDefaults.watchdogInitialDelaySecs == 60)
        #expect(VLCDefaults.watchdogCheckIntervalSecs == 20)
        #expect(VLCDefaults.diagnosticDelaySecs == 15)
    }
}

// MARK: - AVPlayerDefaults

@Suite("AVPlayerDefaults")
struct AVPlayerDefaultsTests {

    @Test("stall 관련 설정")
    func stallSettings() {
        #expect(AVPlayerDefaults.stallTimeoutSecs == 12.0)
        #expect(AVPlayerDefaults.stallCheckIntervalNs == 3_000_000_000) // 3초 nanoseconds
    }

    @Test("rate 변화 감지 임계값")
    func rateSettings() {
        #expect(AVPlayerDefaults.rateChangeMinDelta == 0.03)
    }

    @Test("timescale")
    func timescale() {
        #expect(Int(AVPlayerDefaults.preferredTimescale) == 600)
    }
}

// MARK: - LatencyDefaults

@Suite("LatencyDefaults")
struct LatencyDefaultsTests {

    @Test("전체 값 검증")
    func allValues() {
        #expect(LatencyDefaults.historyMaxCount == 100)
        #expect(LatencyDefaults.mildAdjustmentFactor == 0.05)
        #expect(LatencyDefaults.rateSignificanceThreshold == 0.005)
        #expect(LatencyDefaults.maxRealisticLatencySecs == 60.0)
    }
}

// MARK: - ProxyDefaults

@Suite("ProxyDefaults")
struct ProxyDefaultsTests {

    @Test("타임아웃 설정")
    func timeouts() {
        #expect(ProxyDefaults.keepAliveTimeout == 15)
        #expect(ProxyDefaults.requestTimeout == 15)
    }

    @Test("연결 수 제한")
    func connectionLimits() {
        #expect(ProxyDefaults.maxConnectionsPerHost == 24)
        #expect(ProxyDefaults.maxActiveConnections == 80)
    }
}

// MARK: - MultiPaneDefaults

@Suite("MultiPaneDefaults")
struct MultiPaneDefaultsTests {

    @Test("멀티팬 설정값")
    func values() {
        #expect(MultiPaneDefaults.minHeight == 360)
        #expect(MultiPaneDefaults.maxBitrate == 8_000_000)
    }
}

// MARK: - PollingDefaults

@Suite("PollingDefaults")
struct PollingDefaultsTests {

    @Test("폴링 간격 값")
    func intervals() {
        #expect(PollingDefaults.liveStatusIntervalSecs == 30)
        #expect(PollingDefaults.backgroundPollIntervalSecs == 120)
    }
}

// MARK: - StreamDefaults

@Suite("StreamDefaults")
struct StreamDefaultsTests {

    @Test("CDN 토큰 갱신 간격")
    func cdnTokenRefresh() {
        #expect(StreamDefaults.cdnTokenRefreshIntervalSecs == 55 * 60) // 3300초
    }

    @Test("품질 복구 지연 및 워밍업")
    func qualityAndWarmup() {
        #expect(StreamDefaults.qualityRecoveryDelaySecs == 10)
        #expect(StreamDefaults.cdnWarmupTimeoutSecs == 3)
        #expect(StreamDefaults.defaultManifestRefreshIntervalSecs == 20)
    }

    @Test("최대 연속 엔진 오류")
    func maxErrors() {
        #expect(StreamDefaults.maxConsecutiveEngineErrors == 2)
    }
}

// MARK: - UIDefaults

@Suite("UIDefaults")
struct UIDefaultsTests {

    @Test("채팅 창 너비")
    func chatPaneWidth() {
        #expect(UIDefaults.chatPaneWidth == 340)
    }

    @Test("볼륨 스텝")
    func volumeStep() {
        #expect(UIDefaults.volumeStep == 0.05)
    }

    @Test("재생 속도 옵션")
    func playbackRateOptions() {
        #expect(UIDefaults.playbackRateOptions == [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
    }
}
