// MARK: - CViewMonitoringTests/PerformanceMonitorTests.swift
// PerformanceMonitor actor 테스트 — Metrics 구조체, 상태 제어, 통계

import Testing
import Foundation
@testable import CViewMonitoring
@testable import CViewNetworking
@testable import CViewCore

// MARK: - Metrics 구조체

@Suite("PerformanceMonitor.Metrics — 초기화")
struct PerformanceMetricsInitTests {

    @Test("기본값 초기화")
    func defaultValues() {
        let m = PerformanceMonitor.Metrics()
        #expect(m.fps == 0)
        #expect(m.droppedFrames == 0)
        #expect(m.memoryUsageMB == 0)
        #expect(m.cpuUsage == 0)
        #expect(m.networkBytesReceived == 0)
        #expect(m.bufferHealthPercent == 0)
        #expect(m.latencyMs == 0)
        #expect(m.gpuUsagePercent == 0)
        #expect(m.gpuRendererPercent == 0)
        #expect(m.gpuMemoryUsedMB == 0)
        #expect(m.resolution == nil)
        #expect(m.inputBitrateKbps == 0)
        #expect(m.networkSpeedBytesPerSec == 0)
    }

    @Test("커스텀 값 초기화")
    func customValues() {
        let now = Date()
        let m = PerformanceMonitor.Metrics(
            fps: 60.0,
            droppedFrames: 5,
            memoryUsageMB: 512.3,
            cpuUsage: 25.5,
            networkBytesReceived: 1_000_000,
            bufferHealthPercent: 95.0,
            latencyMs: 150.5,
            gpuUsagePercent: 40.0,
            gpuRendererPercent: 35.0,
            gpuMemoryUsedMB: 256.0,
            resolution: "1920x1080",
            inputBitrateKbps: 5000.0,
            networkSpeedBytesPerSec: 500_000,
            timestamp: now
        )
        #expect(m.fps == 60.0)
        #expect(m.droppedFrames == 5)
        #expect(m.memoryUsageMB == 512.3)
        #expect(m.cpuUsage == 25.5)
        #expect(m.networkBytesReceived == 1_000_000)
        #expect(m.bufferHealthPercent == 95.0)
        #expect(m.latencyMs == 150.5)
        #expect(m.gpuUsagePercent == 40.0)
        #expect(m.gpuRendererPercent == 35.0)
        #expect(m.gpuMemoryUsedMB == 256.0)
        #expect(m.resolution == "1920x1080")
        #expect(m.inputBitrateKbps == 5000.0)
        #expect(m.networkSpeedBytesPerSec == 500_000)
        #expect(m.timestamp == now)
    }
}

// MARK: - PerformanceMonitor 제어

@Suite("PerformanceMonitor — 시작/중지")
struct PerformanceMonitorControlTests {

    @Test("초기 상태 — currentMetrics nil")
    func initialStateIsNil() async {
        let monitor = PerformanceMonitor()
        let metrics = await monitor.currentMetrics
        #expect(metrics == nil)
    }

    @Test("start 후 stop — 크래시 없이 동작")
    func startAndStopSafely() async {
        let monitor = PerformanceMonitor()
        await monitor.start()
        await monitor.stop()
        // 크래시 없이 정상 종료되면 통과
    }

    @Test("중복 start 안전")
    func doubleStartSafe() async {
        let monitor = PerformanceMonitor()
        await monitor.start()
        await monitor.start()
        await monitor.stop()
    }

    @Test("maxHistorySize 커스텀")
    func customMaxHistorySize() async {
        let monitor = PerformanceMonitor(maxHistorySize: 10)
        // 초기화만 확인
        let metrics = await monitor.currentMetrics
        #expect(metrics == nil)
    }
}

// MARK: - 외부 업데이트

@Suite("PerformanceMonitor — 외부 메트릭 업데이트")
struct PerformanceMonitorUpdateTests {

    @Test("개별 메트릭 업데이트 — 크래시 없이 동작")
    func individualUpdates() async {
        let monitor = PerformanceMonitor()
        await monitor.updateFPS(60.0)
        await monitor.updateDroppedFrames(3)
        await monitor.updateNetworkBytes(1_000)
        await monitor.updateBufferHealth(95.0)
        await monitor.updateLatency(100.0)
        await monitor.updateResolution("1280x720")
        await monitor.updateInputBitrate(3000.0)
        await monitor.updateNetworkSpeed(250_000)
    }

    @Test("VLC 메트릭 일괄 업데이트")
    func batchUpdate() async {
        let monitor = PerformanceMonitor()
        await monitor.updateVLCMetricsBatch(
            fps: 30.0,
            droppedFrames: 2,
            networkBytes: 500_000,
            bufferHealth: 80.0,
            resolution: "1920x1080",
            inputBitrateKbps: 6000.0,
            networkSpeedBytesPerSec: 750_000
        )
    }
}

// MARK: - 통계 함수

@Suite("PerformanceMonitor — 통계")
struct PerformanceMonitorStatsTests {

    @Test("빈 상태에서 averageFPS — 0 반환")
    func averageFPSEmpty() async {
        let monitor = PerformanceMonitor()
        let avg = await monitor.averageFPS(seconds: 10)
        #expect(avg == 0)
    }

    @Test("빈 상태에서 peakMemoryMB — 0 반환")
    func peakMemoryMBEmpty() async {
        let monitor = PerformanceMonitor()
        let peak = await monitor.peakMemoryMB()
        #expect(peak == 0)
    }
}

// MARK: - MetricsForwarder.Snapshot

@Suite("MetricsForwarder.Snapshot — 속성")
struct MetricsForwarderSnapshotTests {

    @Test("Snapshot 초기화 — 모든 필드 확인")
    func snapshotAllFields() {
        let now = Date()
        let syncData = CViewSyncData(
            webPosition: nil,
            appPosition: nil,
            webLatency: 150.0,
            appLatency: 140.0,
            latencyDelta: 10.0,
            timestamp: 1700000000
        )
        let recommendation = CViewSyncRecommendation(
            action: "speed_up",
            suggestedSpeed: 1.05,
            reason: "latency too high",
            delta: 50.0,
            avgDelta: 45.0,
            weightedDelta: 48.0,
            confidence: 0.8,
            tier: "adjust",
            trend: "worsening",
            samples: nil
        )

        let snapshot = MetricsForwarder.Snapshot(
            isEnabled: true,
            channelId: "ch1",
            channelName: "테스트채널",
            totalSent: 100,
            totalErrors: 2,
            totalPings: 50,
            lastSentAt: now,
            lastErrorAt: nil,
            lastErrorMessage: nil,
            forwardInterval: 8.0,
            pingInterval: 30.0,
            isForwarding: true,
            lastRecommendation: recommendation,
            lastSyncData: syncData
        )

        #expect(snapshot.isEnabled == true)
        #expect(snapshot.channelId == "ch1")
        #expect(snapshot.channelName == "테스트채널")
        #expect(snapshot.totalSent == 100)
        #expect(snapshot.totalErrors == 2)
        #expect(snapshot.totalPings == 50)
        #expect(snapshot.lastSentAt == now)
        #expect(snapshot.lastErrorAt == nil)
        #expect(snapshot.lastErrorMessage == nil)
        #expect(snapshot.forwardInterval == 8.0)
        #expect(snapshot.pingInterval == 30.0)
        #expect(snapshot.isForwarding == true)
        #expect(snapshot.lastRecommendation?.action == "speed_up")
        #expect(snapshot.lastSyncData?.webLatency == 150.0)
    }

    @Test("Snapshot — 비활성 상태")
    func snapshotDisabled() {
        let snapshot = MetricsForwarder.Snapshot(
            isEnabled: false,
            channelId: nil,
            channelName: nil,
            totalSent: 0,
            totalErrors: 0,
            totalPings: 0,
            lastSentAt: nil,
            lastErrorAt: nil,
            lastErrorMessage: nil,
            forwardInterval: 8.0,
            pingInterval: 30.0,
            isForwarding: false,
            lastRecommendation: nil,
            lastSyncData: nil
        )

        #expect(snapshot.isEnabled == false)
        #expect(snapshot.channelId == nil)
        #expect(snapshot.isForwarding == false)
    }
}

// MARK: - MetricsForwarder 초기 상태

@Suite("MetricsForwarder — 초기 상태")
struct MetricsForwarderInitTests {

    @Test("초기 snapshot — 비활성, 채널 없음")
    func initialSnapshot() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor,
            isEnabled: false
        )

        let snapshot = await forwarder.snapshot
        #expect(snapshot.isEnabled == false)
        #expect(snapshot.channelId == nil)
        #expect(snapshot.channelName == nil)
        #expect(snapshot.totalSent == 0)
        #expect(snapshot.totalErrors == 0)
        #expect(snapshot.totalPings == 0)
        #expect(snapshot.isForwarding == false)
        #expect(snapshot.lastRecommendation == nil)
        #expect(snapshot.lastSyncData == nil)
    }

    @Test("초기 currentRecommendation — nil")
    func initialRecommendation() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor
        )

        let rec = await forwarder.currentRecommendation
        #expect(rec == nil)
    }

    @Test("초기 currentSyncData — nil")
    func initialSyncData() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor
        )

        let data = await forwarder.currentSyncData
        #expect(data == nil)
    }

    @Test("초기 currentChannelId — nil")
    func initialChannelId() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor
        )

        let chId = await forwarder.currentChannelId
        #expect(chId == nil)
    }

    @Test("enabled 초기값 확인")
    func initialEnabled() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor,
            isEnabled: true
        )

        let enabled = await forwarder.enabled
        #expect(enabled == true)
    }

    @Test("커스텀 interval 확인")
    func customIntervals() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor,
            forwardInterval: 5.0,
            pingInterval: 15.0
        )

        let snapshot = await forwarder.snapshot
        #expect(snapshot.forwardInterval == 5.0)
        #expect(snapshot.pingInterval == 15.0)
    }

    @Test("shutdown 안전 호출")
    func shutdownSafely() async {
        let apiClient = MetricsAPIClient(baseURL: URL(string: "https://localhost:9999")!)
        let monitor = PerformanceMonitor()
        let forwarder = MetricsForwarder(
            apiClient: apiClient,
            monitor: monitor
        )

        await forwarder.shutdown()
        let snapshot = await forwarder.snapshot
        #expect(snapshot.channelId == nil)
    }
}
