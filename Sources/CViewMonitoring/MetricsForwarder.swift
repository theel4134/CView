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
        /// 서버에서 수신한 최신 동기화 추천
        public let lastRecommendation: CViewSyncRecommendation?
        /// 서버에서 수신한 최신 동기화 데이터
        public let lastSyncData: CViewSyncData?
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
    
    /// CView 클라이언트 고유 ID (서버 연결 시 부여 또는 로컬 생성)
    private var clientId: String
    
    /// 서버에서 수신한 최신 동기화 추천 (양방향 통신)
    private var lastRecommendation: CViewSyncRecommendation?
    /// 서버에서 수신한 최신 동기화 데이터
    private var lastSyncData: CViewSyncData?

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
        self.clientId = UUID().uuidString
    }

    // MARK: - Settings Control

    /// 메트릭 전송 활성화/비활성화
    public func setEnabled(_ enabled: Bool) async {
        let wasEnabled = isEnabled
        isEnabled = enabled

        // 활성화 → 현재 채널이 있으면 즉시 전송 시작
        if enabled && !wasEnabled, let channelId = activeChannelId, let channelName = activeChannelName {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
            let connectPayload = CViewConnectPayload(
                clientId: clientId,
                appVersion: appVersion,
                channelId: channelId,
                channelName: channelName
            )
            if let response = try? await apiClient.cviewConnect(connectPayload) {
                if let serverId = response.clientId {
                    clientId = serverId
                }
                lastSyncData = response.syncData
            } else {
                // 폴백
                let payload = ChannelActivatePayload(channelId: channelId, channelName: channelName, source: "VLC")
                try? await apiClient.activateChannel(payload)
            }
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
                let disconnectPayload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
                try? await apiClient.cviewDisconnect(disconnectPayload)
            }
            lastRecommendation = nil
            lastSyncData = nil
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

        // CView 통합 연결 API 사용 — 채널 등록 + 초기 동기화 데이터 수신
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let payload = CViewConnectPayload(
            clientId: clientId,
            appVersion: appVersion,
            channelId: channelId,
            channelName: channelName
        )
        do {
            let response = try await apiClient.cviewConnect(payload)
            // 서버가 clientId를 할당했으면 갱신
            if let serverId = response.clientId {
                clientId = serverId
            }
            // 초기 동기화 데이터 저장
            lastSyncData = response.syncData
        } catch {
            // 서버 연결 실패 시 레거시 API 폴백
            let legacyPayload = ChannelActivatePayload(
                channelId: channelId,
                channelName: channelName,
                streamUrl: streamUrl,
                source: "VLC"
            )
            try? await apiClient.activateChannel(legacyPayload)
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
            lastRecommendation = nil
            lastSyncData = nil
            return
        }

        // CView 통합 연결 해제 API 사용
        let payload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
        do {
            try await apiClient.cviewDisconnect(payload)
        } catch {
            // 폴백: 레거시 API
            try? await apiClient.deactivateChannel(channelId: channelId)
        }

        activeChannelId = nil
        activeChannelName = nil
        lastRecommendation = nil
        lastSyncData = nil
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
            isForwarding: forwardingTask != nil,
            lastRecommendation: lastRecommendation,
            lastSyncData: lastSyncData
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

        // VLC 통계가 있으면 CView 하트비트에 포함
        let vlcPayload = vlc.map { CViewVLCMetrics(from: $0) }

        let payload = CViewHeartbeatPayload(
            clientId: clientId,
            channelId: channelId,
            channelName: channelName,
            latency: metrics?.latencyMs ?? 0,
            resolution: vlc?.resolution,
            bitrate: vlc.map { Int($0.demuxBitrateKbps) },
            fps: vlc.map { $0.fps } ?? metrics?.fps,
            bufferHealth: vlc.map { $0.bufferHealth * 100 } ?? metrics?.bufferHealthPercent,
            playbackRate: vlc.map { Double($0.playbackRate) },
            droppedFrames: vlc.map { $0.droppedFramesDelta } ?? metrics?.droppedFrames,
            healthScore: vlc.map { $0.healthScore },
            vlcMetrics: vlcPayload
        )

        do {
            let response = try await apiClient.cviewHeartbeat(payload)
            totalSent += 1
            lastSentAt = Date()
            
            // 양방향: 서버 응답에서 동기화 데이터 저장
            lastSyncData = response.syncData
            lastRecommendation = response.recommendation
        } catch {
            // CView API 실패 시 레거시 폴백
            let legacyPayload = AppLatencyPayload(
                channelId: channelId,
                channelName: channelName,
                latency: metrics?.latencyMs ?? 0,
                bitrate: vlc.map { Int($0.demuxBitrateKbps) },
                resolution: vlc?.resolution,
                frameRate: vlc.map { $0.fps } ?? metrics?.fps,
                droppedFrames: vlc.map { $0.droppedFramesDelta } ?? metrics?.droppedFrames,
                bufferHealth: vlc.map { $0.bufferHealth * 100 } ?? metrics?.bufferHealthPercent,
                playbackRate: vlc.map { Double($0.playbackRate) },
                engine: "VLC",
                healthScore: vlc.map { $0.healthScore },
                latencySource: "native"
            )
            do {
                _ = try await apiClient.sendAppLatency(legacyPayload)
                totalSent += 1
                lastSentAt = Date()
            } catch {
                totalErrors += 1
                lastErrorAt = Date()
                lastErrorMessage = error.localizedDescription
            }
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
    
    // MARK: - Sync Data Access
    
    /// 가장 최근 서버 동기화 추천 (외부에서 조회용)
    public var currentRecommendation: CViewSyncRecommendation? { lastRecommendation }
    
    /// 가장 최근 서버 동기화 데이터 (외부에서 조회용)
    public var currentSyncData: CViewSyncData? { lastSyncData }
}
