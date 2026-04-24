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
        /// 적응형 동기화 현재 폴링 간격 (초)
        public let adaptiveSyncInterval: TimeInterval
        /// 클라이언트 측 직접 계산 델타 (ms, 양수=앱 뒤처짐)
        public let lastClientDelta: Double
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

    /// HLSJSPlayerEngine에서 주기적으로 전달받는 최신 HLS.js 통계 (nil = 아직 수신 전)
    private var latestHLSJSMetrics: HLSJSLiveMetrics?

    // MARK: - Multi-Live Channel State

    /// 멀티라이브 부가 채널의 메트릭 상태 (주 채널은 기존 activeChannelId로 관리)
    private struct MultiLiveChannelState {
        let channelId: String
        let channelName: String
        var vlcMetrics: VLCLiveMetrics?
        var avPlayerMetrics: AVPlayerLiveMetrics?
        var hlsjsMetrics: HLSJSLiveMetrics?
        var currentTimeCallback: (@Sendable () async -> Double)?
        var pdtLatencyCallback: (@Sendable () async -> Double?)?
        /// 레이턴시(ms) 직접 조회 콜백 — PDT 미지원 VLC 세션에서 latencyInfo.current 사용
        var latencyMsCallback: (@Sendable () async -> Double)?
        var targetLatencyMs: Double?
    }

    /// 멀티라이브 부가 채널 목록 (선택된 주 채널 제외)
    private var multiLiveChannels: [String: MultiLiveChannelState] = [:]

    /// 서버 동기화 추천에 따른 재생 속도 변경 콜백
    /// MetricsForwarder → 외부 PlayerEngine 연결용
    private var onSyncSpeedChange: (@Sendable (Float) -> Void)?

    /// [P0 / 2026-04-25] 서버 추천 → playbackRate 직접 적용 여부.
    ///
    /// docs/chzzk-browser-sync-latency-research-swift6-2026-04-25.md §3.5/§9 P0:
    /// 정밀 동기화 모드에서는 rate 소유권을 단일 컨트롤러(LowLatencyController /
    /// 후속 WebSyncController)로 일원화한다. MetricsForwarder 는 관측·전송만
    /// 담당하고 rate 보정은 비활성화하는 것이 기본 정책이다.
    ///
    /// 기본값 false — 정책 단일화. true 로 설정 시 기존(arbitrateServerSpeed) 동작.
    public var rateControlEnabled: Bool = false
    
    /// [Fix 20] PID 활성 상태 확인 콜백 — PID가 능동 제어 중이면 서버 추천 무시
    private var isPIDActiveCallback: (@Sendable () async -> Bool)?
    
    /// [Fix 20 Phase3] PID 현재 재생 배율 콜백 — Rate Arbiter 중재에 사용
    private var pidCurrentRateCallback: (@Sendable () async -> Double)?

    /// 플레이어 목표 지연시간 (ms) — VLC liveCaching 또는 AVPlayer targetLatency
    private var targetLatencyMs: Double?

    /// 현재 VLC 재생 위치 조회 콜백 (seconds)
    private var currentTimeCallback: (@Sendable () async -> Double)?

    /// PDT 기반 레이턴시 조회 콜백 (seconds, nil = PDT 미지원)
    private var pdtLatencyCallback: (@Sendable () async -> Double?)?

    /// 레이턴시(ms) 직접 조회 콜백 — PDT/AVPlayer 미지원 VLC 세션용 (latencyInfo.current 기반)
    private var latencyMsCallback: (@Sendable () async -> Double)?

    /// 동기화 상태 조회 Task (ping 주기와 동일)
    private var syncStatusTask: Task<Void, Never>?

    /// 메트릭 전송 활성화 여부 (설정과 연동)
    private var isEnabled: Bool
    private var forwardInterval: TimeInterval
    private var pingInterval: TimeInterval

    // MARK: - Adaptive Sync

    /// 현재 적응형 동기화 폴링 간격 (델타 크기에 따라 3~30초 동적 조절)
    private var adaptiveSyncInterval: TimeInterval = 30.0
    /// 연속 hold 카운트 (서버가 동기화 양호를 N회 연속 반환 시 폴링 간격 확대)
    private var consecutiveHoldCount: Int = 0
    /// 마지막 클라이언트 측 보정 델타 (ms)
    private var lastClientDelta: Double = 0
    
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
        forwardInterval: TimeInterval = 15.0,
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
            // 멀티라이브 부가 채널도 해제
            for channelId in multiLiveChannels.keys {
                let payload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
                try? await apiClient.cviewDisconnect(payload)
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
        if changed && isEnabled && (activeChannelId != nil || !multiLiveChannels.isEmpty) {
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
        // 멀티라이브 부가 채널이 남아있으면 포워딩 유지
        if multiLiveChannels.isEmpty {
            stopForwarding()
            stopPing()
            stopSyncStatusPolling()
            await monitor.stop()
        } else {
            // 주 채널만 해제 — 동기화 폴링만 중단
            stopSyncStatusPolling()
        }

        // 엔진별 메트릭 캐시 클리어
        latestVLCMetrics = nil
        latestAVPlayerMetrics = nil
        latestHLSJSMetrics = nil
        currentTimeCallback = nil
        pdtLatencyCallback = nil
        latencyMsCallback = nil

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
            lastSyncData: lastSyncData,
            adaptiveSyncInterval: adaptiveSyncInterval,
            lastClientDelta: lastClientDelta
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

    /// HLSJSPlayerEngine.onHLSJSMetrics 콜백에서 호출합니다.
    /// PerformanceMonitor를 업데이트하고 최신 HLS.js 통계를 캐싱합니다.
    public func updateHLSJSMetrics(_ metrics: HLSJSLiveMetrics) async {
        latestHLSJSMetrics = metrics
        await monitor.updateVLCMetricsBatch(
            fps: metrics.fps,
            droppedFrames: metrics.droppedFramesDelta,
            networkBytes: 0,
            bufferHealth: metrics.bufferHealth * 100,  // 0-1 → 0-100%
            resolution: metrics.resolution,
            inputBitrateKbps: metrics.bitrateKbps,
            networkSpeedBytesPerSec: 0
        )
    }

    // MARK: - Multi-Live Channel Management

    /// 멀티라이브 채널 등록 — 메트릭 전송 대상으로 추가
    /// 주 채널과 동일하면 스킵 (activateChannel로 이미 관리됨)
    public func registerMultiLiveChannel(channelId: String, channelName: String) async {
        if channelId == activeChannelId { return }
        guard multiLiveChannels[channelId] == nil else { return }

        multiLiveChannels[channelId] = MultiLiveChannelState(
            channelId: channelId,
            channelName: channelName
        )

        guard isEnabled else { return }

        // 서버에 채널 연결 알림
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let payload = CViewConnectPayload(
            clientId: clientId,
            appVersion: appVersion,
            channelId: channelId,
            channelName: channelName
        )
        do {
            _ = try await apiClient.cviewConnect(payload)
        } catch {
            Log.network.debug("Multi-live channel connect failed: \(error.localizedDescription)")
        }
    }

    /// 멀티라이브 채널 해제 — 메트릭 전송 중단
    public func unregisterMultiLiveChannel(channelId: String) async {
        guard multiLiveChannels.removeValue(forKey: channelId) != nil else { return }
        guard isEnabled else { return }

        let payload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
        do {
            try await apiClient.cviewDisconnect(payload)
        } catch {
            Log.network.debug("Multi-live channel disconnect failed: \(error.localizedDescription)")
        }
    }

    /// 멀티라이브 주 채널 전환 — 기존 주 채널은 부가 채널로 이동, 새 채널이 주 채널로 승격
    public func switchPrimaryChannel(channelId: String, channelName: String) async {
        // 이미 동일 채널이면 무시
        guard channelId != activeChannelId else { return }

        // 현재 주 채널을 부가 채널로 이동 (메트릭 캐시 유지)
        if let oldId = activeChannelId, let oldName = activeChannelName {
            multiLiveChannels[oldId] = MultiLiveChannelState(
                channelId: oldId,
                channelName: oldName,
                vlcMetrics: latestVLCMetrics,
                avPlayerMetrics: latestAVPlayerMetrics,
                hlsjsMetrics: latestHLSJSMetrics,
                currentTimeCallback: currentTimeCallback,
                pdtLatencyCallback: pdtLatencyCallback,
                latencyMsCallback: latencyMsCallback,
                targetLatencyMs: targetLatencyMs
            )
        }

        // 새 채널을 부가 목록에서 제거 (중복 전송 방지) + 메트릭 캐시 복원
        let restoredState = multiLiveChannels.removeValue(forKey: channelId)

        // 주 채널 업데이트
        activeChannelId = channelId
        activeChannelName = channelName
        latestVLCMetrics = restoredState?.vlcMetrics
        latestAVPlayerMetrics = restoredState?.avPlayerMetrics
        latestHLSJSMetrics = restoredState?.hlsjsMetrics
        currentTimeCallback = restoredState?.currentTimeCallback
        pdtLatencyCallback = restoredState?.pdtLatencyCallback
        latencyMsCallback = restoredState?.latencyMsCallback
        targetLatencyMs = restoredState?.targetLatencyMs

        // 포워딩이 아직 안 돌고 있으면 시작
        if isEnabled && forwardingTask == nil {
            await monitor.start()
            startForwarding()
            startPing()
            startSyncStatusPolling()
        }
    }

    /// 멀티라이브 채널별 VLC 메트릭 업데이트
    public func updateVLCMetrics(_ metrics: VLCLiveMetrics, forChannel channelId: String) async {
        if channelId == activeChannelId {
            await updateVLCMetrics(metrics)
        } else if multiLiveChannels[channelId] != nil {
            multiLiveChannels[channelId]?.vlcMetrics = metrics
        }
    }

    /// 멀티라이브 채널별 AVPlayer 메트릭 업데이트
    public func updateAVPlayerMetrics(_ metrics: AVPlayerLiveMetrics, forChannel channelId: String) async {
        if channelId == activeChannelId {
            await updateAVPlayerMetrics(metrics)
        } else if multiLiveChannels[channelId] != nil {
            multiLiveChannels[channelId]?.avPlayerMetrics = metrics
        }
    }

    /// 멀티라이브 채널별 HLS.js 메트릭 업데이트
    public func updateHLSJSMetrics(_ metrics: HLSJSLiveMetrics, forChannel channelId: String) async {
        if channelId == activeChannelId {
            await updateHLSJSMetrics(metrics)
        } else if multiLiveChannels[channelId] != nil {
            multiLiveChannels[channelId]?.hlsjsMetrics = metrics
        }
    }

    /// 멀티라이브 채널별 재생 위치 콜백 등록
    public func setCurrentTimeCallback(_ callback: @escaping @Sendable () async -> Double, forChannel channelId: String) {
        if channelId == activeChannelId {
            currentTimeCallback = callback
        } else {
            multiLiveChannels[channelId]?.currentTimeCallback = callback
        }
    }

    /// 멀티라이브 채널별 PDT 레이턴시 콜백 등록
    public func setPDTLatencyCallback(_ callback: @escaping @Sendable () async -> Double?, forChannel channelId: String) {
        if channelId == activeChannelId {
            pdtLatencyCallback = callback
        } else {
            multiLiveChannels[channelId]?.pdtLatencyCallback = callback
        }
    }

    /// 멀티라이브 채널별 목표 레이턴시 설정
    public func setTargetLatency(_ ms: Double, forChannel channelId: String) {
        if channelId == activeChannelId {
            targetLatencyMs = ms
        } else {
            multiLiveChannels[channelId]?.targetLatencyMs = ms
        }
    }

    /// 멀티라이브 채널별 레이턴시(ms) 직접 조회 콜백 등록 — latencyInfo 기반
    public func setLatencyMsCallback(_ callback: @escaping @Sendable () async -> Double, forChannel channelId: String) {
        if channelId == activeChannelId {
            latencyMsCallback = callback
        } else {
            multiLiveChannels[channelId]?.latencyMsCallback = callback
        }
    }

    /// 레이턴시(ms) 직접 조회 콜백 등록 (싱글라이브 호환)
    public func setLatencyMsCallback(_ callback: @escaping @Sendable () async -> Double) {
        latencyMsCallback = callback
    }

    // MARK: - Metrics Forwarding

    private func startForwarding() {
        forwardingTask?.cancel()
        forwardingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.forwardInterval))
                guard !Task.isCancelled else { break }
                await self.forwardCurrentMetrics()
                // 멀티라이브 부가 채널 메트릭도 전송
                await self.forwardMultiLiveMetrics()
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
        let hlsjs = latestHLSJSMetrics

        // 엔진 판별: HLS.js 메트릭이 있으면 HLS.js, AVPlayer 메트릭이 있으면 AVPlayer, 그 외 VLC
        let isHLSJSEngine = hlsjs != nil
        let isAVPlayerEngine = !isHLSJSEngine && vlc == nil && avp != nil
        let engineName = isHLSJSEngine ? "HLS.js" : (isAVPlayerEngine ? "AVPlayer" : "VLC")

        // 재생 위치 수집 (seconds)
        let playbackTime = await currentTimeCallback?()
        // PDT 레이턴시 수집 (seconds → ms)
        let pdtLat = await pdtLatencyCallback?()
        let pdtLatMs = pdtLat.map { $0 * 1000.0 }
        let pdtTimestampMs = pdtLat.map { _ in Date().timeIntervalSince1970 * 1000.0 }

        // [Fix 32] 엔진별 payload 빌더로 분리 — forwardCurrentMetrics 가독성 개선
        let payload: CViewHeartbeatPayload
        if isHLSJSEngine, let hlsjs {
            payload = makeHLSJSHeartbeat(
                hlsjs: hlsjs, channelId: channelId, channelName: channelName,
                engineName: engineName, playbackTime: playbackTime,
                pdtLatMs: pdtLatMs, pdtTimestampMs: pdtTimestampMs
            )
        } else if isAVPlayerEngine, let avp {
            payload = makeAVPlayerHeartbeat(
                avp: avp, channelId: channelId, channelName: channelName,
                engineName: engineName, playbackTime: playbackTime,
                pdtLatMs: pdtLatMs, pdtTimestampMs: pdtTimestampMs
            )
        } else {
            payload = await makeVLCHeartbeat(
                vlc: vlc, metrics: metrics, channelId: channelId, channelName: channelName,
                engineName: engineName, playbackTime: playbackTime,
                pdtLatMs: pdtLatMs, pdtTimestampMs: pdtTimestampMs
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
                let directLat = await latencyMsCallback?()
                let hybridPayload = HybridHeartbeatPayload(
                    channelId: channelId,
                    clientId: clientId,
                    clientType: isAVPlayerEngine ? "avplayer" : "vlc",
                    engine: engineName,
                    vlcPosition: playbackTime?.safeForJSON,
                    pdtTimestamp: pdtTimestampMs?.safeForJSON,
                    latencyMs: pdtLatMs?.safeForJSON ?? directLat?.safeForJSON ?? (metrics?.latencyMs ?? 0).safeForJSON
                )
                do {
                    _ = try await apiClient.hybridHeartbeat(hybridPayload)
                } catch {
                    Log.network.debug("Hybrid heartbeat failed: \(error.localizedDescription)")
                }
            }
            
            // 서버 동기화 추천 → 클라이언트 측 검증 + 재생 속도 적용
            // [Fix 20 Phase3] Rate Arbiter — PID/서버 통합 속도 결정
            if let rec = response.recommendation,
               let confidence = rec.confidence, confidence >= 0.3,
               let action = rec.action, action != "waiting" {
                let validatedSpeed = validateAndComputeSyncSpeed(
                    recommendation: rec,
                    syncData: response.syncData
                )
                if let arbitrated = await arbitrateServerSpeed(validatedSpeed) {
                    // [P0 / 2026-04-25] 정책 단일화 — rateControlEnabled 가 켜진
                    // 경우에만 외부에 rate 변경을 전파. 기본값 off.
                    if rateControlEnabled {
                        onSyncSpeedChange?(Float(arbitrated))
                    }
                }
            }
            // 하트비트 응답에서도 적응형 폴링 간격 업데이트
            updateAdaptiveSyncInterval(
                recommendation: response.recommendation,
                syncData: response.syncData
            )
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

    // MARK: - Multi-Live Metrics Forwarding

    /// 멀티라이브 부가 채널 메트릭 일괄 전송
    private func forwardMultiLiveMetrics() async {
        guard isEnabled, !multiLiveChannels.isEmpty else { return }
        for (_, channelState) in multiLiveChannels {
            await forwardMultiLiveChannelMetrics(channelState)
        }
    }

    /// 개별 멀티라이브 채널의 메트릭을 하트비트로 전송
    private func forwardMultiLiveChannelMetrics(_ ch: MultiLiveChannelState) async {
        let vlc = ch.vlcMetrics
        let avp = ch.avPlayerMetrics
        let hlsjs = ch.hlsjsMetrics

        let isHLSJSEngine = hlsjs != nil
        let isAVPEngine = !isHLSJSEngine && vlc == nil && avp != nil
        let engineName = isHLSJSEngine ? "HLS.js" : (isAVPEngine ? "AVPlayer" : "VLC")

        let playbackTime = await ch.currentTimeCallback?()
        let pdtLat = await ch.pdtLatencyCallback?()
        let pdtLatMs = pdtLat.map { $0 * 1000.0 }
        let pdtTimestampMs = pdtLat.map { _ in Date().timeIntervalSince1970 * 1000.0 }

        let payload: CViewHeartbeatPayload
        if isHLSJSEngine, let hlsjs {
            payload = CViewHeartbeatPayload(
                clientId: clientId,
                channelId: ch.channelId,
                channelName: ch.channelName,
                latency: (hlsjs.latency * 1000.0).safeForJSON,
                resolution: hlsjs.resolution,
                bitrate: Int(hlsjs.bitrateKbps.safeForJSON),
                fps: hlsjs.fps.safeForJSON,
                bufferHealth: (hlsjs.bufferHealth * 100).safeForJSON,
                playbackRate: Double(hlsjs.playbackRate).safeForJSON,
                droppedFrames: hlsjs.droppedFramesDelta,
                healthScore: hlsjs.healthScore.safeForJSON,
                engine: engineName,
                vlcMetrics: nil,
                targetLatency: ch.targetLatencyMs,
                connectionState: hlsjs.bufferHealth > 0.5 ? "connected" : "degraded",
                connectionQuality: hlsjs.bufferHealth > 0.7 ? "excellent" : hlsjs.bufferHealth > 0.3 ? "good" : "poor",
                isBuffering: hlsjs.bufferHealth < 0.3,
                latePictures: nil,
                currentTime: playbackTime?.safeForJSON,
                pdtTimestamp: pdtTimestampMs?.safeForJSON,
                pdtLatency: pdtLatMs?.safeForJSON,
                latencyUnit: "ms"
            )
        } else if isAVPEngine, let avp {
            payload = CViewHeartbeatPayload(
                clientId: clientId,
                channelId: ch.channelId,
                channelName: ch.channelName,
                latency: (avp.measuredLatency * 1000.0).safeForJSON,
                resolution: avp.resolution,
                bitrate: Int(avp.bitrateKbps.safeForJSON),
                fps: nil,
                bufferHealth: (avp.bufferHealth * 100).safeForJSON,
                playbackRate: Double(avp.playbackRate).safeForJSON,
                droppedFrames: avp.droppedFramesDelta,
                healthScore: avp.healthScore.safeForJSON,
                engine: engineName,
                vlcMetrics: nil,
                targetLatency: ch.targetLatencyMs,
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
            let vlcPayload = vlc.map { CViewVLCMetrics(from: $0) }
            // 레이턴시 우선순위: PDT(초→ms) → latencyMsCallback(ms)
            let directLatencyMs = await ch.latencyMsCallback?()
            let effectiveLatencyMs: Double
            let latencySourceTag: String
            if let pdt = pdtLatMs, pdt > 0 {
                effectiveLatencyMs = pdt
                latencySourceTag = "pdt+buffer"
            } else if let direct = directLatencyMs, direct > 0 {
                effectiveLatencyMs = direct
                latencySourceTag = "buffer"
            } else {
                effectiveLatencyMs = 0
                latencySourceTag = "none"
            }
            payload = CViewHeartbeatPayload(
                clientId: clientId,
                channelId: ch.channelId,
                channelName: ch.channelName,
                latency: effectiveLatencyMs.safeForJSON,
                resolution: vlc?.resolution,
                bitrate: vlc.map { Int($0.demuxBitrateKbps.safeForJSON) },
                fps: vlc?.fps.safeForJSON,
                bufferHealth: vlc.map { ($0.bufferHealth * 100).safeForJSON },
                playbackRate: vlc.map { Double($0.playbackRate).safeForJSON },
                droppedFrames: vlc?.droppedFramesDelta,
                healthScore: vlc.map { $0.healthScore.safeForJSON },
                engine: engineName,
                vlcMetrics: vlcPayload,
                targetLatency: ch.targetLatencyMs,
                connectionState: vlc.map { $0.bufferHealth < 0.1 ? "poor" : "connected" } ?? "unknown",
                connectionQuality: vlc.map { $0.healthScore >= 0.9 ? "excellent" : ($0.healthScore >= 0.7 ? "good" : "fair") } ?? "unknown",
                isBuffering: vlc.map { $0.bufferHealth < 0.3 },
                latePictures: vlc?.latePicturesDelta,
                currentTime: playbackTime?.safeForJSON,
                pdtTimestamp: pdtTimestampMs?.safeForJSON,
                pdtLatency: pdtLatMs?.safeForJSON,
                latencyUnit: "ms",
                latencySource: latencySourceTag
            )
        }

        do {
            _ = try await apiClient.cviewHeartbeat(payload)
            totalSent += 1
            lastSentAt = Date()
        } catch is DecodingError {
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
        // 멀티라이브 부가 채널 전체 해제
        for channelId in multiLiveChannels.keys {
            if isEnabled {
                let payload = CViewDisconnectPayload(clientId: clientId, channelId: channelId)
                try? await apiClient.cviewDisconnect(payload)
            }
        }
        multiLiveChannels.removeAll()

        await deactivateCurrentChannel()
        forwardingTask?.cancel()
        forwardingTask = nil
        pingTask?.cancel()
        pingTask = nil
        syncStatusTask?.cancel()
        syncStatusTask = nil
    }

    // MARK: - Sync Status Polling (Adaptive)

    private func startSyncStatusPolling() {
        syncStatusTask?.cancel()
        adaptiveSyncInterval = pingInterval  // 초기값
        consecutiveHoldCount = 0
        syncStatusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.adaptiveSyncInterval))
                guard !Task.isCancelled else { break }
                await self.fetchSyncStatus()
            }
        }
    }

    private func stopSyncStatusPolling() {
        syncStatusTask?.cancel()
        syncStatusTask = nil
        consecutiveHoldCount = 0
    }

    private func fetchSyncStatus() async {
        guard isEnabled, let channelId = activeChannelId else { return }
        do {
            let response = try await apiClient.cviewSyncStatus(channelId: channelId)
            lastSyncData = response.syncData
            if let rec = response.recommendation {
                lastRecommendation = rec

                // 적응형 폴링 간격 재계산
                let validatedSpeed = validateAndComputeSyncSpeed(
                    recommendation: rec,
                    syncData: response.syncData
                )
                // [Fix 20 Phase3] Rate Arbiter — PID/서버 통합 속도 결정
                if let arbitrated = await arbitrateServerSpeed(validatedSpeed) {
                    // [P0 / 2026-04-25] 정책 단일화 — rateControlEnabled gate.
                    if rateControlEnabled {
                        onSyncSpeedChange?(Float(arbitrated))
                    }
                }

                updateAdaptiveSyncInterval(recommendation: rec, syncData: response.syncData)
            }
        } catch {
            Log.network.debug("Sync status fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Adaptive Sync Intelligence

    /// 적응형 폴링 간격 계산
    /// - 큰 델타 (>2000ms): 3~5초 간격으로 빠르게 수렴
    /// - 중간 델타 (500~2000ms): 8~12초 간격
    /// - 작은 델타 (<500ms): 20~30초 간격으로 리소스 절약
    /// - [Fix 20] 히스테리시스: 경계값에서 빈번한 전환 방지 (±150ms 히스테리시스 밴드)
    private func updateAdaptiveSyncInterval(
        recommendation: CViewSyncRecommendation?,
        syncData: CViewSyncData?
    ) {
        let absDelta = computeClientSideDelta(syncData: syncData)
        
        // [Fix 20] 히스테리시스 — 현재 간격 기준으로 경계값 조정
        // 빠른 폴링 상태에서 느린 폴링으로 전환할 때는 임계값을 낮게 (더 빨리 전환)
        // 느린 폴링 상태에서 빠른 폴링으로 전환할 때는 임계값을 높게 (지연 전환)
        let hysteresis: Double = 150.0  // ms
        let isCurrentlyFast = adaptiveSyncInterval <= 12.0
        
        // 경계값 조정: 빠른→느린 전환은 더 낮은 값에서, 느린→빠른 전환은 더 높은 값에서
        let threshold500 = isCurrentlyFast ? (500.0 - hysteresis) : (500.0 + hysteresis)
        let threshold1000 = isCurrentlyFast ? (1000.0 - hysteresis) : (1000.0 + hysteresis)
        let threshold2000 = isCurrentlyFast ? (2000.0 - hysteresis) : (2000.0 + hysteresis)

        let newInterval: TimeInterval
        if absDelta > 3000 {
            // 심각한 격차 — 가장 빠른 폴링
            newInterval = 3.0
            consecutiveHoldCount = 0
        } else if absDelta > threshold2000 {
            // 큰 격차 — 빠른 폴링
            newInterval = 5.0
            consecutiveHoldCount = 0
        } else if absDelta > threshold1000 {
            // 중간 격차
            newInterval = 8.0
            consecutiveHoldCount = 0
        } else if absDelta > threshold500 {
            // 작은 격차
            newInterval = 12.0
            consecutiveHoldCount = 0
        } else {
            // 동기화 양호 — hold 연속 시 점진적 확대
            if recommendation?.action == "hold" {
                consecutiveHoldCount += 1
            } else {
                consecutiveHoldCount = 0
            }
            // hold 3회 이상 연속 → 최대 간격, 아니면 기본 간격
            newInterval = consecutiveHoldCount >= 3 ? 30.0 : 20.0
        }

        // 간격이 변경되면 동기화 태스크 재시작
        if abs(newInterval - adaptiveSyncInterval) > 1.0 {
            adaptiveSyncInterval = newInterval
            restartSyncPolling()
        }
    }

    /// 동기화 폴링 태스크 재시작 (새 간격 적용)
    private func restartSyncPolling() {
        syncStatusTask?.cancel()
        syncStatusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.adaptiveSyncInterval))
                guard !Task.isCancelled else { break }
                await self.fetchSyncStatus()
            }
        }
    }

    /// 클라이언트 측 델타 계산 (서버 데이터 검증용)
    /// 서버의 latencyDelta 부호가 이상할 수 있으므로 원시 값에서 직접 계산
    private func computeClientSideDelta(syncData: CViewSyncData?) -> Double {
        guard let sd = syncData,
              let appLat = sd.appLatency, appLat > 0,
              let webLat = sd.webLatency, webLat > 0 else {
            return abs(lastClientDelta)
        }
        let delta = appLat - webLat
        lastClientDelta = delta
        return abs(delta)
    }

    // MARK: - Rate Arbiter (Fix 20 Phase3)
    
    /// [Fix 20 Phase3] 통합 속도 결정기 — PID 출력과 서버 추천을 중재
    ///
    /// 규칙:
    /// 1. PID 비활성 → 서버 추천 그대로 적용
    /// 2. PID 활성 + PID 보정량 > 서버 보정량 → PID 우선 (서버 무시)
    /// 3. PID 활성 + 방향 불일치 → 보수적 판단 (서버 무시)
    /// 4. PID 활성 + 미미한 보정 + 같은 방향 → 서버 미세 조정 허용
    private func arbitrateServerSpeed(_ serverSpeed: Double) async -> Double? {
        let pidActive = await isPIDActiveCallback?() ?? false
        
        // PID 비활성(데드존/idle) → 서버 추천 그대로 적용
        guard pidActive else { return serverSpeed }
        
        let pidRate = await pidCurrentRateCallback?() ?? 1.0
        let pidOffset = abs(pidRate - 1.0)
        let serverOffset = abs(serverSpeed - 1.0)
        
        // PID가 활발한 보정 중 (0.5% 이상) + PID 보정 ≥ 서버 보정 → 서버 무시
        if pidOffset >= 0.005 && pidOffset >= serverOffset {
            return nil
        }
        
        // 방향 불일치 → 보수적으로 서버 무시
        let pidDirection = pidRate - 1.0
        let serverDirection = serverSpeed - 1.0
        if pidDirection * serverDirection < 0 && pidOffset > 0.002 {
            return nil
        }
        
        // PID 미미한 보정 + 서버가 더 큰 보정 + 같은 방향 → 서버 미세 조정 허용
        return serverSpeed
    }
    
    /// 서버 추천 검증 + 클라이언트 보정 속도 계산
    ///
    /// **핵심 로직**: 서버의 delta 부호가 데이터 타이밍 차로 뒤집힐 수 있으므로
    /// syncData의 원시 webLatency/appLatency에서 직접 방향 판단
    ///
    /// - 앱 > 웹: 앱이 뒤처짐 → 가속 (>1.0)
    /// - 앱 < 웹: 앱이 앞섬 → 감속 (<1.0)
    /// - 차이 < 200ms: 동기화 양호 → 1.0
    private func validateAndComputeSyncSpeed(
        recommendation: CViewSyncRecommendation,
        syncData: CViewSyncData?
    ) -> Double {
        // 원시 레이턴시 값이 없으면 서버 추천 그대로 사용
        guard let sd = syncData,
              let appLat = sd.appLatency, appLat > 0,
              let webLat = sd.webLatency, webLat > 0 else {
            return recommendation.suggestedSpeed ?? 1.0
        }

        // 클라이언트 직접 계산: 양수 = 앱 뒤처짐, 음수 = 앱 앞섬
        let clientDelta = appLat - webLat
        let absDelta = abs(clientDelta)
        lastClientDelta = clientDelta

        // 500ms 이내 — 동기화 양호, 속도 복원 (VLC 버퍼링 방지를 위해 넓은 허용 범위)
        if absDelta < 500 {
            return 1.0
        }

        // 방향 결정: 앱이 뒤처지면 가속, 앞서면 감속
        let direction: Double = clientDelta > 0 ? 1.0 : -1.0

        // 서버 추천 방향과 클라이언트 판단이 일치하는지 검증
        let serverDirection: Double
        if let action = recommendation.action {
            serverDirection = action == "speed_up" ? 1.0 : action == "slow_down" ? -1.0 : 0.0
        } else {
            serverDirection = 0.0
        }

        let directionMismatch = direction * serverDirection < 0

        // 델타 크기 기반 속도 결정 — 완화된 보정폭 (버퍼링 방지 우선)
        let speedOffset: Double
        if absDelta > 3000 {
            // 심각한 격차 — 중간 보정 (급격한 속도 변화 방지)
            speedOffset = 0.05
        } else if absDelta > 2000 {
            speedOffset = 0.04
        } else if absDelta > 1000 {
            speedOffset = 0.03
        } else if absDelta > 800 {
            // 중간 격차 — 미세 보정
            speedOffset = 0.02
        } else {
            // 500~800ms — 매우 미세 보정
            speedOffset = 0.01
        }

        let computedSpeed = 1.0 + (direction * speedOffset)

        if directionMismatch {
            // 서버와 방향 불일치 → 클라이언트 계산 사용 (서버 데이터 타이밍 차 보정)
            let action = recommendation.action ?? "unknown"
            Log.network.debug("동기화 방향 보정: 서버=\(action), 클라이언트 델타=\(clientDelta, format: .fixed(precision: 0))ms → 속도=\(computedSpeed, format: .fixed(precision: 4))")
            return computedSpeed
        }

        // 서버와 방향 일치 — 서버 추천과 클라이언트 계산의 가중 평균
        if let serverSpeed = recommendation.suggestedSpeed, abs(serverSpeed - 1.0) > 0.001 {
            // 서버 40% + 클라이언트 60% (클라이언트가 더 최신 판단)
            let blended = serverSpeed * 0.4 + computedSpeed * 0.6
            return blended
        }
        return computedSpeed
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
    
    /// [Fix 20] PID 활성 상태 확인 콜백 등록 — LowLatencyController.isPIDActive 연결
    public func setPIDActiveCallback(_ callback: @escaping @Sendable () async -> Bool) {
        isPIDActiveCallback = callback
    }
    
    /// [Fix 20 Phase3] PID 현재 재생 배율 콜백 — Rate Arbiter에서 사용
    public func setPIDCurrentRateCallback(_ callback: @escaping @Sendable () async -> Double) {
        pidCurrentRateCallback = callback
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

    // MARK: - [Fix 32] Heartbeat Payload Builders (엔진별)
    //
    // forwardCurrentMetrics 가독성 개선 — 228줄 단일 함수 → 메인 50줄 + 빌더 3개로 분리.
    // NaN/Infinity 방어를 위해 모든 수치는 .safeForJSON 적용.

    /// HLS.js 엔진용 하트비트 페이로드 빌더
    private func makeHLSJSHeartbeat(
        hlsjs: HLSJSLiveMetrics,
        channelId: String,
        channelName: String,
        engineName: String,
        playbackTime: Double?,
        pdtLatMs: Double?,
        pdtTimestampMs: Double?
    ) -> CViewHeartbeatPayload {
        CViewHeartbeatPayload(
            clientId: clientId,
            channelId: channelId,
            channelName: channelName,
            latency: (hlsjs.latency * 1000.0).safeForJSON, // sec → ms
            resolution: hlsjs.resolution,
            bitrate: Int(hlsjs.bitrateKbps.safeForJSON),
            fps: hlsjs.fps.safeForJSON,
            bufferHealth: (hlsjs.bufferHealth * 100).safeForJSON,
            playbackRate: Double(hlsjs.playbackRate).safeForJSON,
            droppedFrames: hlsjs.droppedFramesDelta,
            healthScore: hlsjs.healthScore.safeForJSON,
            engine: engineName,
            vlcMetrics: nil,
            targetLatency: targetLatencyMs,
            connectionState: hlsjs.bufferHealth > 0.5 ? "connected" : "degraded",
            connectionQuality: hlsjs.bufferHealth > 0.7 ? "excellent" : hlsjs.bufferHealth > 0.3 ? "good" : "poor",
            isBuffering: hlsjs.bufferHealth < 0.3,
            latePictures: nil,
            currentTime: playbackTime?.safeForJSON,
            pdtTimestamp: pdtTimestampMs?.safeForJSON,
            pdtLatency: pdtLatMs?.safeForJSON,
            latencyUnit: "ms"
        )
    }

    /// AVPlayer 엔진용 하트비트 페이로드 빌더
    private func makeAVPlayerHeartbeat(
        avp: AVPlayerLiveMetrics,
        channelId: String,
        channelName: String,
        engineName: String,
        playbackTime: Double?,
        pdtLatMs: Double?,
        pdtTimestampMs: Double?
    ) -> CViewHeartbeatPayload {
        CViewHeartbeatPayload(
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
    }

    /// VLC 엔진용 하트비트 페이로드 빌더
    /// 레이턴시 우선순위: PDT(초→ms) → latencyMsCallback(ms) → PerformanceMonitor
    private func makeVLCHeartbeat(
        vlc: VLCLiveMetrics?,
        metrics: PerformanceMonitor.Metrics?,
        channelId: String,
        channelName: String,
        engineName: String,
        playbackTime: Double?,
        pdtLatMs: Double?,
        pdtTimestampMs: Double?
    ) async -> CViewHeartbeatPayload {
        let directLatencyMs = await latencyMsCallback?()
        let effectiveLatencyMs: Double
        let latencySourceTag: String
        if let pdt = pdtLatMs, pdt > 0 {
            effectiveLatencyMs = pdt
            latencySourceTag = "pdt+buffer"  // PDT + VLC buffer 합산
        } else if let direct = directLatencyMs, direct > 0 {
            effectiveLatencyMs = direct
            latencySourceTag = "buffer"  // VLC buffer fallback
        } else {
            effectiveLatencyMs = metrics?.latencyMs ?? 0
            latencySourceTag = "monitor"  // PerformanceMonitor 추정값
        }
        let vlcPayload = vlc.map { CViewVLCMetrics(from: $0) }
        return CViewHeartbeatPayload(
            clientId: clientId,
            channelId: channelId,
            channelName: channelName,
            latency: effectiveLatencyMs.safeForJSON,
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
            latencyUnit: "ms",
            latencySource: latencySourceTag
        )
    }
}
