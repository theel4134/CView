// MARK: - CViewMonitoringTests/MetricsForwarderTests.swift
// MetricsForwarder 페이로드/안전성 회귀 테스트
//
// 범위 (P1-7, [Fix 32]):
//   - safeForJSON: NaN/Infinity 방어 (Double / Optional<Double>)
//   - CViewHeartbeatPayload Codable 회귀 (모든 옵션 필드 포함)
//   - 페이로드 JSON 인코딩이 NaN/Infinity 입력에도 실패하지 않음을 보장

import Testing
import Foundation
@testable import CViewCore
@testable import CViewMonitoring
@testable import CViewNetworking

// MARK: - safeForJSON

@Suite("safeForJSON — NaN/Infinity 방어")
struct SafeForJSONTests {

    @Test("Double: 유한값은 그대로")
    func finiteDoublePreserved() {
        #expect(0.0.safeForJSON == 0.0)
        #expect(123.456.safeForJSON == 123.456)
        #expect((-99.9).safeForJSON == -99.9)
        #expect(Double.greatestFiniteMagnitude.safeForJSON == .greatestFiniteMagnitude)
    }

    @Test("Double: NaN → 0")
    func nanReplacedWithZero() {
        let nan: Double = .nan
        #expect(nan.safeForJSON == 0.0)
    }

    @Test("Double: +Inf / -Inf → 0")
    func infinityReplacedWithZero() {
        #expect(Double.infinity.safeForJSON == 0.0)
        #expect((-Double.infinity).safeForJSON == 0.0)
    }

    @Test("Optional<Double>: nil → nil")
    func optionalNilStaysNil() {
        let v: Double? = nil
        #expect(v.safeForJSON == nil)
    }

    @Test("Optional<Double>: 유한값은 그대로")
    func optionalFinitePreserved() {
        let v: Double? = 42.5
        #expect(v.safeForJSON == 42.5)
    }

    @Test("Optional<Double>: NaN → nil")
    func optionalNaNBecomesNil() {
        let v: Double? = .nan
        #expect(v.safeForJSON == nil)
    }

    @Test("Optional<Double>: Inf → nil")
    func optionalInfBecomesNil() {
        let v: Double? = .infinity
        #expect(v.safeForJSON == nil)
    }
}

// MARK: - CViewHeartbeatPayload Codable

@Suite("CViewHeartbeatPayload — Codable 회귀")
struct CViewHeartbeatPayloadCodableTests {

    /// JSONEncoder는 기본적으로 NaN/Infinity 인코딩 시 예외를 던진다.
    /// 모든 수치는 사전에 safeForJSON으로 정제되어야 한다.
    @Test("VLC 페이로드 — 정상 인코딩")
    func encodeVLCHeartbeat() throws {
        let payload = CViewHeartbeatPayload(
            clientId: "client-1",
            channelId: "ch-A",
            channelName: "테스트 채널",
            latency: 250.0,
            resolution: "1920x1080",
            bitrate: 5_000,
            fps: 60.0,
            bufferHealth: 95.0,
            playbackRate: 1.0,
            droppedFrames: 0,
            healthScore: 0.95,
            engine: "VLC",
            targetLatency: 2_000,
            connectionState: "connected",
            connectionQuality: "excellent",
            isBuffering: false,
            currentTime: 12345.6,
            pdtTimestamp: 1_700_000_000_000,
            pdtLatency: 250.0,
            latencyUnit: "ms",
            latencySource: "pdt+buffer"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CViewHeartbeatPayload.self, from: data)
        #expect(decoded.clientId == payload.clientId)
        #expect(decoded.channelId == payload.channelId)
        #expect(decoded.channelName == payload.channelName)
        #expect(decoded.latency == payload.latency)
        #expect(decoded.engine == "VLC")
        #expect(decoded.latencySource == "pdt+buffer")
    }

    @Test("HLS.js 페이로드 — vlcMetrics nil")
    func encodeHLSJSHeartbeat() throws {
        let payload = CViewHeartbeatPayload(
            clientId: "c",
            channelId: "ch",
            channelName: "n",
            latency: 1500,
            resolution: "1280x720",
            bitrate: 2500,
            fps: 30,
            bufferHealth: 80,
            playbackRate: 1.0,
            droppedFrames: 2,
            healthScore: 0.8,
            engine: "HLS.js",
            vlcMetrics: nil,
            targetLatency: nil,
            isBuffering: false,
            latencyUnit: "ms"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CViewHeartbeatPayload.self, from: data)
        #expect(decoded.engine == "HLS.js")
        #expect(decoded.vlcMetrics == nil)
    }

    @Test("AVPlayer 페이로드 — fps nil 허용")
    func encodeAVPlayerHeartbeatFPSNil() throws {
        let payload = CViewHeartbeatPayload(
            clientId: "c",
            channelId: "ch",
            channelName: "n",
            latency: 800,
            bitrate: 4000,
            fps: nil,
            bufferHealth: 90,
            playbackRate: 1.0,
            droppedFrames: 0,
            healthScore: 0.92,
            engine: "AVPlayer",
            isBuffering: false
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CViewHeartbeatPayload.self, from: data)
        #expect(decoded.engine == "AVPlayer")
        #expect(decoded.fps == nil)
    }

    /// safeForJSON 적용 후라면 NaN/Inf가 아닌 0 또는 nil이 들어가야 한다.
    /// 이 테스트는 실수로 raw NaN을 넣었을 때 인코딩이 실패함을 확인하여
    /// safeForJSON 누락 회귀를 잡아낸다.
    @Test("RAW NaN 입력 시 인코딩 실패 — safeForJSON 누락 감지용 가드")
    func rawNaNFailsEncoding() {
        let payload = CViewHeartbeatPayload(
            clientId: "c",
            channelId: "ch",
            channelName: "n",
            latency: .nan,
            engine: "VLC"
        )
        // 기본 JSONEncoder는 NaN을 거부함
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder().encode(payload)
        }
    }

    /// safeForJSON으로 정제된 값은 항상 인코딩 성공해야 함
    @Test("safeForJSON 적용 후 인코딩 — 항상 성공")
    func sanitizedPayloadEncodesAlways() throws {
        let nan: Double = .nan
        let inf: Double = .infinity
        let payload = CViewHeartbeatPayload(
            clientId: "c",
            channelId: "ch",
            channelName: "n",
            latency: nan.safeForJSON,           // → 0
            fps: (nan as Double?).safeForJSON,  // → nil
            bufferHealth: (inf as Double?).safeForJSON,
            playbackRate: 1.0,
            engine: "VLC"
        )
        let data = try JSONEncoder().encode(payload)
        #expect(!data.isEmpty)
    }
}

// MARK: - MetricsForwarder Snapshot 초기 상태

@Suite("MetricsForwarder — 실제 actor 초기 상태")
struct MetricsForwarderActorInitTests {

    /// 초기화 직후 snapshot 기본값 확인.
    /// MetricsAPIClient는 actor이므로 초기화에 IO 없음.
    @Test("초기 상태: 비활성, 카운터 0, 채널 nil")
    func initialSnapshotDefaults() async {
        let api = MetricsAPIClient(baseURL: URL(string: "https://example.invalid")!)
        let monitor = PerformanceMonitor()
        let fwd = MetricsForwarder(
            apiClient: api,
            monitor: monitor,
            isEnabled: false,
            forwardInterval: 15,
            pingInterval: 30
        )
        let snap = await fwd.snapshot
        #expect(snap.isEnabled == false)
        #expect(snap.channelId == nil)
        #expect(snap.channelName == nil)
        #expect(snap.totalSent == 0)
        #expect(snap.totalErrors == 0)
        #expect(snap.totalPings == 0)
        #expect(snap.lastSentAt == nil)
        #expect(snap.lastErrorAt == nil)
        #expect(snap.lastErrorMessage == nil)
        #expect(snap.forwardInterval == 15)
        #expect(snap.pingInterval == 30)
        #expect(snap.isForwarding == false)
        #expect(snap.lastRecommendation == nil)
        #expect(snap.lastSyncData == nil)
    }

    @Test("updateIntervals: 비활성 상태에서 단순 갱신만")
    func updateIntervalsWhenDisabled() async {
        let api = MetricsAPIClient(baseURL: URL(string: "https://example.invalid")!)
        let monitor = PerformanceMonitor()
        let fwd = MetricsForwarder(
            apiClient: api,
            monitor: monitor,
            isEnabled: false
        )
        await fwd.updateIntervals(forward: 10, ping: 20)
        let snap = await fwd.snapshot
        #expect(snap.forwardInterval == 10)
        #expect(snap.pingInterval == 20)
        #expect(snap.isForwarding == false)
    }

    @Test("currentChannelId: 활성화 전에는 nil")
    func currentChannelIdNilBeforeActivation() async {
        let api = MetricsAPIClient(baseURL: URL(string: "https://example.invalid")!)
        let monitor = PerformanceMonitor()
        let fwd = MetricsForwarder(apiClient: api, monitor: monitor)
        let cid = await fwd.currentChannelId
        #expect(cid == nil)
    }
}
