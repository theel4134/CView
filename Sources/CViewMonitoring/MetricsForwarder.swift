// MARK: - MetricsForwarder.swift
// 앱 성능 메트릭을 cv.dododo.app 서버로 전송

import Foundation
import CViewCore
import CViewNetworking

/// 앱 내부 메트릭을 메트릭 서버로 전달하는 Actor
/// - 채널 활성화/비활성화 관리
/// - 주기적 레이턴시 전송
/// - Keep-alive 핑
/// - 설정에서 활성화/비활성화 제어 가능
public actor MetricsForwarder {

    // MARK: - Snapshot (뷰에서 폴링용)

    /// 포워더 상태 스냅샷 — 설정 패널에 메트릭 전송 현황 표시용
    public struct Snapshot: Sendable {
        public let isEnabled: Bool
        public let channelId: String?
        public let channelName: String?
        public let totalSent: Int
        public let totalErrors: Int
        public let totalPings: Int
        public let lastSentAt: Date?
        public let lastErrorAt: Date?
        public let lastErrorMessage: String?
        public let forwardInterval: TimeInterval
        public let pingInterval: TimeInterval
        public let isForwarding: Bool
    }

    // MARK: - State

    private let apiClient: MetricsAPIClient
    public let monitor: PerformanceMonitor
    private var activeChannelId: String?
    private var activeChannelName: String?

    private var forwardingTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    /// VLCPlayerEngine에서 주기적으로 전달받는 최신 VLC 통계 (nil = 아직 수신 전)
    private var latestVLCMetrics: VLCLiveMetrics?

    /// 메트릭 전송 활성화 여부 (설정과 연동)
    private var isEnabled: Bool
    private var forwardInterval: TimeInterval
    private var pingInterval: TimeInterval

    // MARK: - Stats Tracking

    private var totalSent: Int = 0
    private var totalErrors: Int = 0
    private var totalPings: Int = 0
    private var lastSentAt: Date?
    private var lastErrorAt: Date?
    private var lastErrorMessage: String?

    // MARK: - Init

    public init(
        apiClient: MetricsAPIClient,
        monitor: PerformanceMonitor,
        isEnabled: Bool = false,
        forwardInterval: TimeInterval = 5.0,
        pingInterval: TimeInterval = 30.0
    ) {
        self.apiClient = apiClient
        self.monitor = monitor
        self.isEnabled = isEnabled
        self.forwardInterval = forwardInterval
        self.pingInterval = pingInterval
    }

    // MARK: - Settings Control

    /// 메트릭 전송 활성화/비활성화
    public func setEnabled(_ enabled: Bool) async {
        let wasEnabled = isEnabled
        isEnabled = enabled

        // 활성화 → 현재 채널이 있으면 즉시 전송 시작
        if enabled && !wasEnabled, let channelId = activeChannelId, let channelName = activeChannelName {
            let payload = ChannelActivatePayload(channelId: channelId, channelName: channelName, source: "VLC")
            try? await apiClient.activateChannel(payload)
            await monitor.start()
            startForwarding()
            startPing()
        }

        // 비활성화 → 포워딩·핑 중단, 서버에 비활성화 알림
        if !enabled && wasEnabled {
            stopForwarding()
            stopPing()
            await monitor.stop()
            if let channelId = activeChannelId {
                try? await apiClient.deactivateChannel(channelId: channelId)
            }
        }
    }

    /// 전송 주기 업데이트
    public func updateIntervals(forward: TimeInterval, ping: TimeInterval) {
        let changed = (forward != forwardInterval || ping != pingInterval)
        forwardInterval = forward
        pingInterval = ping

        // 현재 실행 중이면 재시작
        if changed && isEnabled && activeChannelId != nil {
            startForwarding()
            startPing()
        }
    }

    /// 현재 활성화 여부
    public var enabled: Bool { isEnabled }
    
    // MARK: - Channel Lifecycle

    /// 채널 시청 시작 시 호출
    public func activateChannel(channelId: String, channelName: String, streamUrl: String? = nil) async {
        // 기존 채널이 있으면 먼저 비활성화
        if activeChannelId != nil {
            await deactivateCurrentChannel()
        }

        activeChannelId = channelId
        activeChannelName = channelName

        guard isEnabled else { return }

        // 서버에 채널 활성화 알림
        let payload = ChannelActivatePayload(
            channelId: channelId,
            channelName: channelName,
            streamUrl: streamUrl,
            source: "VLC"
        )
        do {
            _ = try await apiClient.activateChannel(payload)
        } catch {
            // 서버 연결 실패 시 로컬 동작에 영향 없음
        }

        await monitor.start()
        startForwarding()
        startPing()
    }

    /// 채널 시청 종료 시 호출
    public func deactivateCurrentChannel() async {
        stopForwarding()
        stopPing()
        await monitor.stop()

        guard let channelId = activeChannelId, isEnabled else {
            activeChannelId = nil
            activeChannelName = nil
            return
        }

        do {
            try await apiClient.deactivateChannel(channelId: channelId)
        } catch {
            // 네트워크 실패 무시
        }

        activeChannelId = nil
        activeChannelName = nil
    }

    /// 현재 활성 채널 ID
    public var currentChannelId: String? { activeChannelId }

    /// 뷰 표시용 상태 스냅샷
    public var snapshot: Snapshot {
        Snapshot(
            isEnabled: isEnabled,
            channelId: activeChannelId,
            channelName: activeChannelName,
            totalSent: totalSent,
            totalErrors: totalErrors,
            totalPings: totalPings,
            lastSentAt: lastSentAt,
            lastErrorAt: lastErrorAt,
            lastErrorMessage: lastErrorMessage,
            forwardInterval: forwardInterval,
            pingInterval: pingInterval,
            isForwarding: forwardingTask != nil
        )
    }

    // MARK: - VLC Metrics

    /// VLCPlayerEngine.onVLCMetrics 콜백에서 호출합니다.
    /// PerformanceMonitor를 업데이트하고 최신 VLC 통계를 캐싱합니다.
    /// [최적화] 7개 개별 actor hop → 1회 일괄 호출로 통합하여 Swift concurrency 오버헤드 제거
    public func updateVLCMetrics(_ metrics: VLCLiveMetrics) async {
        latestVLCMetrics = metrics
        await monitor.updateVLCMetricsBatch(
            fps: metrics.fps,
            droppedFrames: metrics.droppedFramesDelta,
            networkBytes: metrics.networkBytesPerSec,
            bufferHealth: metrics.bufferHealth * 100,  // 0-1 → 0-100%
            resolution: metrics.resolution,
            inputBitrateKbps: metrics.inputBitrateKbps,
            networkSpeedBytesPerSec: metrics.networkBytesPerSec
        )
    }

    // MARK: - Metrics Forwarding

    private func startForwarding() {
        forwardingTask?.cancel()
        forwardingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.forwardInterval))
                guard !Task.isCancelled else { break }
                await self.forwardCurrentMetrics()
            }
        }
    }
    
    private func stopForwarding() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }
    
    private func forwardCurrentMetrics() async {
        guard isEnabled,
              let channelId = activeChannelId,
              let channelName = activeChannelName else { return }

        let metrics = await monitor.currentMetrics
        let vlc = latestVLCMetrics

        // VLC 통계가 있으면 우선 사용, 없으면 PerformanceMonitor 폴백
        let payload = AppLatencyPayload(
            channelId: channelId,
            channelName: channelName,
            latency: metrics?.latencyMs ?? 0,
            bitrate: vlc.map { Int($0.demuxBitrateKbps) },
            resolution: vlc?.resolution,
            frameRate: vlc.map { $0.fps } ?? metrics?.fps,
            droppedFrames: vlc.map { $0.droppedFramesDelta } ?? metrics?.droppedFrames,
            bufferHealth: vlc.map { $0.bufferHealth * 100 } ?? metrics?.bufferHealthPercent,  // 0-1 → 0-100%
            playbackRate: vlc.map { Double($0.playbackRate) },
            engine: "VLC",
            healthScore: vlc.map { $0.healthScore },
            latencySource: "native"
        )

        do {
            _ = try await apiClient.sendAppLatency(payload)
            totalSent += 1
            lastSentAt = Date()
        } catch {
            totalErrors += 1
            lastErrorAt = Date()
            lastErrorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Keep-alive Ping
    
    private func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.pingInterval))
                guard !Task.isCancelled else { break }
                await self.sendPing()
            }
        }
    }
    
    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
    }
    
    private func sendPing() async {
        guard isEnabled, let channelId = activeChannelId else { return }
        do {
            try await apiClient.pingChannel(channelId: channelId)
            totalPings += 1
        } catch {
            // 핑 실패 무시
        }
    }
    
    // MARK: - Cleanup
    
    /// 앱 종료 시 호출
    public func shutdown() async {
        await deactivateCurrentChannel()
    }
}
