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

    /// AVPlayerEngine에서 주기적으로 전달받는 최신 AVPlayer 통계 (nil = 아직 수신 전)
    private var latestAVPlayerMetrics: AVPlayerLiveMetrics?

    /// 서버 동기화 추천에 따른 재생 속도 변경 콜백
    /// MetricsForwarder → 외부 PlayerEngine 연결용
    private var onSyncSpeedChange: (@Sendable (Float) -> Void)?

    /// 플레이어 목표 지연시간 (ms) — VLC liveCaching 또는 AVPlayer targetLatency
    private var targetLatencyMs: Double?

    /// 현재 VLC 재생 위치 조회 콜백 (seconds)
    private var currentTimeCallback: (@Sendable () async -> Double)?

    /// PDT 기반 레이턴시 조회 콜백 (seconds, nil = PDT 미지원)
    private var pdtLatencyCallback: (@Sendable () async -> Double?)?

    /// 동기화 상태 조회 Task (ping 주기와 동일)
    private var syncStatusTask: Task<Void, Never>?

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
        forwardInterval: TimeInterval = 8.0,
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
            do {
                let response = try await apiClient.cviewConnect(connectPayload)
                if let serverId = response.clientId {
                    clientId = serverId
                }
                lastSyncData = response.syncData
            } catch {
                // CView API 미지원 서버 — /api/metrics 폴백
                Log.network.warning("cviewConnect failed, falling back to legacy: \(error.localizedDescription)")
                let payload = AppLatencyPayload(
                    channelId: channelId,
                    channelName: channelName,
                    latency: 0,
                    engine: "VLC",
                    latencySource: "native"
                )
                do {
                    try await apiClient.sendMetrics(payload)
                } catch {
                    Log.network.debug("Legacy metrics fallback failed: \(error.localizedDescription)")
                }
            }
            await monitor.start()
            startForwarding()
            startPing()
            startSyncStatusPolling()
        }

        // 비활성화 → 포워딩·핑 중단, 서버에 비활성화 알림
        if !enabled && wasEnabled {
            stopForwarding()
            stopPing()
            stopSyncStatusPolling()
            await monitor.stop()
            if let channelId = activeChannelId {
                let disconnectPayload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
                do {
                    try await apiClient.cviewDisconnect(disconnectPayload)
                } catch {
                    Log.network.debug("cviewDisconnect (toggle) failed: \(error.localizedDescription)")
                }
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
            // CView API 미지원 서버 — /api/metrics 폴백으로 첫 메트릭 전송
            let legacyPayload = AppLatencyPayload(
                channelId: channelId,
                channelName: channelName,
                latency: 0,
                engine: "VLC",
                latencySource: "native"
            )
            do {
                try await apiClient.sendMetrics(legacyPayload)
            } catch {
                Log.network.debug("Legacy metrics fallback failed: \(error.localizedDescription)")
            }
        }

        await monitor.start()
        startForwarding()
        startPing()
        startSyncStatusPolling()
    }

    /// 채널 시청 종료 시 호출
    public func deactivateCurrentChannel() async {
        stopForwarding()
        stopPing()
        stopSyncStatusPolling()
        await monitor.stop()

        // 엔진별 메트릭 캐시 클리어
        latestVLCMetrics = nil
        latestAVPlayerMetrics = nil

        guard let channelId = activeChannelId, isEnabled else {
            activeChannelId = nil
            activeChannelName = nil
            lastRecommendation = nil
            lastSyncData = nil
            return
        }

        // CView 통합 연결 해제 API 사용 (서버 미지원 시 무시)
        let payload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
        do {
            try await apiClient.cviewDisconnect(payload)
        } catch {
            Log.network.debug("cviewDisconnect (deactivate) failed: \(error.localizedDescription)")
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

    /// AVPlayerEngine.onAVMetrics 콜백에서 호출합니다.
    /// PerformanceMonitor를 업데이트하고 최신 AVPlayer 통계를 캐싱합니다.
    public func updateAVPlayerMetrics(_ metrics: AVPlayerLiveMetrics) async {
        latestAVPlayerMetrics = metrics
        await monitor.updateVLCMetricsBatch(
            fps: 0,  // AVPlayer에서는 FPS 직접 수집 불가
            droppedFrames: metrics.droppedFramesDelta,
            networkBytes: 0,
            bufferHealth: metrics.bufferHealth * 100,  // 0-1 → 0-100%
            resolution: metrics.resolution,
            inputBitrateKbps: metrics.bitrateKbps,
            networkSpeedBytesPerSec: 0
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
        let avp = latestAVPlayerMetrics

        // 엔진 판별: VLC 메트릭이 있으면 VLC, AVPlayer 메트릭이 있으면 AVPlayer
        let isAVPlayerEngine = vlc == nil && avp != nil
        let engineName = isAVPlayerEngine ? "AVPlayer" : "VLC"

        // VLC 통계가 있으면 CView 하트비트에 포함
        let vlcPayload = vlc.map { CViewVLCMetrics(from: $0) }

        // 재생 위치 수집 (seconds)
        let playbackTime = await currentTimeCallback?()
        // PDT 레이턴시 수집 (seconds → ms)
        let pdtLat = await pdtLatencyCallback?()
        let pdtLatMs = pdtLat.map { $0 * 1000.0 }
        let pdtTimestampMs = pdtLat.map { _ in Date().timeIntervalSince1970 * 1000.0 }

        // NaN/Infinity 방어: finite 값만 전송, 비유한 값은 기본값으로 대체
        let payload: CViewHeartbeatPayload
        if isAVPlayerEngine, let avp {
            // AVPlayer 엔진 — AVPlayerLiveMetrics 기반 하트비트
            payload = CViewHeartbeatPayload(
                clientId: clientId,
                channelId: channelId,
                channelName: channelName,
                latency: (avp.measuredLatency * 1000.0).safeForJSON, // sec → ms
                resolution: avp.resolution,
                bitrate: Int(avp.bitrateKbps.safeForJSON),
                fps: nil, // AVPlayer에서는 FPS 직접 수집 불가
                bufferHealth: (avp.bufferHealth * 100).safeForJSON,
                playbackRate: Double(avp.playbackRate).safeForJSON,
                droppedFrames: avp.droppedFramesDelta,
                healthScore: avp.healthScore.safeForJSON,
                engine: engineName,
                vlcMetrics: nil,
                targetLatency: targetLatencyMs,
                connectionState: avp.bufferHealth > 0.5 ? "connected" : "degraded",
                connectionQuality: avp.bufferHealth > 0.7 ? "excellent" : avp.bufferHealth > 0.3 ? "good" : "poor",
                isBuffering: avp.bufferHealth < 0.3,
                latePictures: nil,
                currentTime: playbackTime?.safeForJSON,
                pdtTimestamp: pdtTimestampMs?.safeForJSON,
                pdtLatency: pdtLatMs?.safeForJSON,
                latencyUnit: "ms"
            )
        } else {
            // VLC 엔진 — 기존 VLC 기반 하트비트
            payload = CViewHeartbeatPayload(
                clientId: clientId,
                channelId: channelId,
                channelName: channelName,
                latency: (metrics?.latencyMs ?? 0).safeForJSON,
                resolution: vlc?.resolution,
                bitrate: vlc.map { Int($0.demuxBitrateKbps.safeForJSON) },
                fps: (vlc.map { $0.fps } ?? metrics?.fps)?.safeForJSON,
                bufferHealth: (vlc.map { $0.bufferHealth * 100 } ?? metrics?.bufferHealthPercent)?.safeForJSON,
                playbackRate: vlc.map { Double($0.playbackRate).safeForJSON },
                droppedFrames: vlc.map { $0.droppedFramesDelta } ?? metrics?.droppedFrames,
                healthScore: vlc.map { $0.healthScore.safeForJSON },
                engine: engineName,
                vlcMetrics: vlcPayload,
                targetLatency: targetLatencyMs,
                connectionState: deriveConnectionState(vlc: vlc, metrics: metrics),
                connectionQuality: deriveConnectionQuality(vlc: vlc, metrics: metrics),
                isBuffering: vlc.map { $0.bufferHealth < 0.3 },
                latePictures: vlc.map { $0.latePicturesDelta },
                currentTime: playbackTime?.safeForJSON,
                pdtTimestamp: pdtTimestampMs?.safeForJSON,
                pdtLatency: pdtLatMs?.safeForJSON,
                latencyUnit: "ms"
            )
        }

        do {
            let response = try await apiClient.cviewHeartbeat(payload)
            totalSent += 1
            lastSentAt = Date()
            // 전송 성공 → 이전 에러 상태 클리어
            lastErrorAt = nil
            lastErrorMessage = nil
            
            // 양방향: 서버 응답에서 동기화 데이터 저장
            lastSyncData = response.syncData
            lastRecommendation = response.recommendation
            
            // PDT 또는 position 데이터가 있으면 hybrid-heartbeat도 전송
            if pdtLatMs != nil || playbackTime != nil {
                let hybridPayload = HybridHeartbeatPayload(
                    channelId: channelId,
                    clientId: clientId,
                    clientType: isAVPlayerEngine ? "avplayer" : "vlc",
                    engine: engineName,
                    vlcPosition: playbackTime?.safeForJSON,
                    pdtTimestamp: pdtTimestampMs?.safeForJSON,
                    latencyMs: pdtLatMs?.safeForJSON ?? (metrics?.latencyMs ?? 0).safeForJSON
                )
                do {
                    _ = try await apiClient.hybridHeartbeat(hybridPayload)
                } catch {
                    Log.network.debug("Hybrid heartbeat failed: \(error.localizedDescription)")
                }
            }
            
            // 서버 동기화 추천 → 재생 속도 적용 (confidence 30% 이상, hold 아닌 경우)
            if let rec = response.recommendation,
               let speed = rec.suggestedSpeed,
               let confidence = rec.confidence, confidence >= 0.3,
               let action = rec.action, action != "hold" && action != "waiting",
               abs(speed - 1.0) > 0.001 {
                onSyncSpeedChange?(Float(speed))
            } else if let action = response.recommendation?.action, action == "hold" {
                // hold → 정상 속도 복원
                onSyncSpeedChange?(1.0)
            }
        } catch is DecodingError {
            // HTTP 200 성공했으나 서버 응답 형식 불일치 — 전송은 완료된 상태
            totalSent += 1
            lastSentAt = Date()
            lastErrorAt = nil
            lastErrorMessage = nil
        } catch {
            // HTTP 오류 또는 네트워크 오류 — /api/metrics 폴백
            let legacyPayload: AppLatencyPayload
            if isAVPlayerEngine, let avp {
                legacyPayload = AppLatencyPayload(
                    channelId: channelId,
                    channelName: channelName,
                    latency: (avp.measuredLatency * 1000.0).safeForJSON,
                    bitrate: Int(avp.bitrateKbps.safeForJSON),
                    resolution: avp.resolution,
                    frameRate: nil,
                    droppedFrames: avp.droppedFramesDelta,
                    bufferHealth: (avp.bufferHealth * 100).safeForJSON,
                    playbackRate: Double(avp.playbackRate).safeForJSON,
                    engine: engineName,
                    healthScore: avp.healthScore.safeForJSON,
                    latencySource: "native",
                    latencyUnit: "ms"
                )
            } else {
                legacyPayload = AppLatencyPayload(
                    channelId: channelId,
                    channelName: channelName,
                    latency: (metrics?.latencyMs ?? 0).safeForJSON,
                    bitrate: vlc.map { Int($0.demuxBitrateKbps.safeForJSON) },
                    resolution: vlc?.resolution,
                    frameRate: (vlc.map { $0.fps } ?? metrics?.fps)?.safeForJSON,
                    droppedFrames: vlc.map { $0.droppedFramesDelta } ?? metrics?.droppedFrames,
                    bufferHealth: (vlc.map { $0.bufferHealth * 100 } ?? metrics?.bufferHealthPercent)?.safeForJSON,
                    playbackRate: vlc.map { Double($0.playbackRate).safeForJSON },
                    engine: engineName,
                    healthScore: vlc.map { $0.healthScore.safeForJSON },
                    latencySource: "native",
                    latencyUnit: "ms"
                )
            }
            do {
                try await apiClient.sendMetrics(legacyPayload)
                totalSent += 1
                lastSentAt = Date()
                lastErrorAt = nil
                lastErrorMessage = nil
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
        guard isEnabled,
              let channelId = activeChannelId,
              let channelName = activeChannelName else { return }
        do {
            // /api/metrics 로 간단 핑 전송 (서버 호환)
            let payload = AppLatencyPayload(
                channelId: channelId,
                channelName: channelName,
                latency: 0,
                engine: "VLC",
                latencySource: "ping"
            )
            try await apiClient.sendMetrics(payload)
            totalPings += 1
        } catch {
            // 핑 실패 무시
        }
    }
    
    // MARK: - Cleanup
    
    /// 앱 종료 시 호출
    public func shutdown() async {
        await deactivateCurrentChannel()
        forwardingTask?.cancel()
        forwardingTask = nil
        pingTask?.cancel()
        pingTask = nil
        syncStatusTask?.cancel()
        syncStatusTask = nil
    }

    // MARK: - Sync Status Polling

    private func startSyncStatusPolling() {
        syncStatusTask?.cancel()
        syncStatusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.pingInterval))
                guard !Task.isCancelled else { break }
                await self.fetchSyncStatus()
            }
        }
    }

    private func stopSyncStatusPolling() {
        syncStatusTask?.cancel()
        syncStatusTask = nil
    }

    private func fetchSyncStatus() async {
        guard isEnabled, let channelId = activeChannelId else { return }
        do {
            let response = try await apiClient.cviewSyncStatus(channelId: channelId)
            lastSyncData = response.syncData
            if let rec = response.recommendation {
                lastRecommendation = rec
            }
        } catch {
            Log.network.debug("Sync status fetch failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Sync Data Access
    
    /// 가장 최근 서버 동기화 추천 (외부에서 조회용)
    public var currentRecommendation: CViewSyncRecommendation? { lastRecommendation }
    
    /// 가장 최근 서버 동기화 데이터 (외부에서 조회용)
    public var currentSyncData: CViewSyncData? { lastSyncData }
    
    /// 서버 동기화 추천에 따른 재생 속도 변경 콜백 등록
    /// - Parameter handler: 서버 추천 속도(Float)를 받아 PlayerEngine.setRate()를 호출
    public func setSyncSpeedCallback(_ handler: @escaping @Sendable (Float) -> Void) {
        onSyncSpeedChange = handler
    }

    /// 플레이어 목표 지연시간 설정 (ms) — VLC liveCaching 또는 AVPlayer targetLatency 기반
    public func setTargetLatency(_ ms: Double) {
        targetLatencyMs = ms
    }

    /// VLC 재생 위치 콜백 등록 (currentTime in seconds)
    public func setCurrentTimeCallback(_ callback: @escaping @Sendable () async -> Double) {
        currentTimeCallback = callback
    }

    /// PDT 레이턴시 콜백 등록 (seconds, nil = 미지원)
    public func setPDTLatencyCallback(_ callback: @escaping @Sendable () async -> Double?) {
        pdtLatencyCallback = callback
    }
    
    // MARK: - Connection State Derivation
    
    /// VLC 메트릭 + 시스템 메트릭에서 연결 상태 추론
    private func deriveConnectionState(vlc: VLCLiveMetrics?, metrics: PerformanceMonitor.Metrics?) -> String {
        guard let vlc else { return "unknown" }
        if vlc.bufferHealth < 0.1 { return "poor" }
        if vlc.demuxCorruptedDelta > 0 || vlc.demuxDiscontinuityDelta > 0 { return "degraded" }
        return "connected"
    }
    
    /// VLC 메트릭 + 시스템 메트릭에서 연결 품질 추론
    private func deriveConnectionQuality(vlc: VLCLiveMetrics?, metrics: PerformanceMonitor.Metrics?) -> String {
        guard let vlc else { return "unknown" }
        let health = vlc.healthScore
        if health >= 0.9 { return "excellent" }
        if health >= 0.7 { return "good" }
        if health >= 0.5 { return "fair" }
        return "poor"
    }
}
