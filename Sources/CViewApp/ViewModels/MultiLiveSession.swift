// MARK: - MultiLiveSession.swift
// 멀티 라이브 — 탭 하나에 해당하는 플레이어+채팅 세션

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking
import CViewMonitoring

// MARK: - 세션 로딩 상태

enum MultiLiveLoadState: Equatable {
    case idle
    case loading
    case playing(channelName: String, liveTitle: String)
    case offline
    case error(String)
}

// MARK: - MultiLiveSession

/// 멀티 라이브 탭 하나를 나타내는 독립적인 재생 세션
@Observable
@MainActor
final class MultiLiveSession: Identifiable {

    let id: UUID

    // MARK: - 채널 정보

    var channelId: String
    var channelName: String = ""
    var liveTitle: String = ""
    var thumbnailURL: URL?
    var profileImageURL: URL?
    var viewerCount: Int = 0
    /// 누적 시청자 수 (chzzk live-status `accumulateCount`)
    var accumulateCount: Int = 0
    var isOffline: Bool = false

    /// MultiLiveManager 방식: 세션 내부에 apiClient 보관 (파라미터 없는 start() 지원)
    private weak var storedApiClient: ChzzkAPIClient?

    /// 메트릭 전송용 포워더 (AppState에서 주입)
    var metricsForwarder: MetricsForwarder?

    // MARK: - ViewModel

    let playerViewModel: PlayerViewModel
    let chatViewModel: ChatViewModel

    // MARK: - UI 상태

    var loadState: MultiLiveLoadState = .idle
    var latestMetrics: VLCLiveMetrics?
    var latestAVMetrics: AVPlayerLiveMetrics?
    var latestHLSJSMetrics: HLSJSLiveMetrics?
    var latestProxyStats: ProxyNetworkStats?
    var showStats: Bool = false
    var showNetworkMetrics: Bool = false {
        didSet {
            // [Fix 2026-04-30] oldValue 변화가 없으면 task 를 그대로 둔다.
            // SwiftUI 가 view 재구성 중 onAppear/onDisappear 를 자주 트리거하면
            // task 가 매번 cancel & restart 되어 lastProxyBytesReceived 가 reset →
            // 첫 폴(2s) 까지는 항상 0 으로 보이는 문제를 야기했음.
            guard oldValue != showNetworkMetrics else { return }
            if showNetworkMetrics {
                startProxyMonitorTask()
            } else {
                stopProxyMonitorTask()
            }
        }
    }
    var isMuted: Bool { playerViewModel.isMuted }

    // MARK: - 네트워크 모니터링 보조 상태
    /// 프록시 누적 바이트 변화량으로 계산한 "최근 구간 평균 대역폭" (Bytes/sec).
    /// VLC 통계 stall 시 fallback. 0 이면 미측정.
    var proxyBandwidthBytesPerSec: Double = 0
    /// MLNetworkTab/MLNetworkAggregateTab 표시용 통합 대역폭 — 프록시 우선.
    /// 우선순위: 슬라이딩 평균(5s) > 직전 측정 > VLC networkBytes > VLC inputBitrate > AV/HLS bitrate.
    var displayBandwidthBytesPerSec: Double {
        if proxyBandwidthBytesPerSec > 0 { return proxyBandwidthBytesPerSec }
        if let m = latestMetrics {
            if m.networkBytesPerSec > 0 { return Double(m.networkBytesPerSec) }
            // [Fix] inputBitrateKbps fallback — proxy 폴이 아직 시드 전이거나 stall 시.
            if m.inputBitrateKbps > 0 { return m.inputBitrateKbps * 1000.0 / 8.0 }
        }
        if let av = latestAVMetrics, av.bitrateKbps > 0 { return av.bitrateKbps * 1000.0 / 8.0 }
        if let hls = latestHLSJSMetrics, hls.bitrateKbps > 0 { return hls.bitrateKbps * 1000.0 / 8.0 }
        return 0
    }
    /// 60-샘플 링버퍼 — 스파크라인/CSV 출력용.
    let networkHistory = NetworkMonitorHistory()
    private var lastProxyBytesReceived: Int64 = 0
    private var lastProxyBytesTimestamp: Date?
    private var proxyMonitorTask: Task<Void, Never>?
    /// [정밀화] 누적 바이트 30초 윈도우 — 세그먼트 burst (4-6s마다 1회 큰 증가) ÷ 시간으로
    /// 안정적인 평균 대역폭 산출. 단발 delta + slidingAvg 보다 burst 워크로드에 훨씬 강건.
    private var byteHistory: [(Date, Int64)] = []
    /// [정밀화] VLC stat HW-decode 경로에서 fps/displayed/buffer 가 0으로 고착되는
    /// 현상 대응 — 최근 유효 값을 캡쳐해 표시 시 fallback.
    private(set) var lastNonZeroFps: Double = 0
    private(set) var lastNonZeroBufferHealth: Double = 0

    /// 시청자 수 포맷 (3곳에서 중복 사용하던 로직 통합)
    var formattedViewerCount: String {
        let n = viewerCount
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n) 명"
    }
    /// 누적 시청자 수 포맷 (예: "12.3만", "5.4k", "234")
    var formattedAccumulateCount: String {
        let n = accumulateCount
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
    // MARK: - 태스크

    var pollTask: Task<Void, Never>?
    var startTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var offlineRetryTask: Task<Void, Never>?
    private var chatConnectionTask: Task<Void, Never>?
    private(set) var isBackground: Bool = false

    // MARK: - Init

    init(channelId: String, engineType: PlayerEngineType = .vlc, engine: (any PlayerEngineProtocol)? = nil) {
        self.id = UUID()
        self.channelId = channelId
        self.playerViewModel = PlayerViewModel(engineType: engineType)
        self.playerViewModel.isMultiLive = true
        if let engine {
            self.playerViewModel.injectEngine(engine)
        }
        self.chatViewModel = ChatViewModel()
    }

    // [Bug-fix] deinit 안전장치 — 멀티라이브 탭 삭제/재생성 중 stop() 호출이 누락되어도
    // 남아있는 Task 들을 취소하여 메모리 고착과 불필요한 폴링/백그라운드
    // 연산을 방지한다. Swift 6 에서 main-actor isolated stored property 는
    // nonisolated deinit 에서 바로 접근 불가 → MainActor.assumeIsolated 로 감싼다.
    deinit {
        MainActor.assumeIsolated {
            startTask?.cancel()
            pollTask?.cancel()
            refreshTask?.cancel()
            offlineRetryTask?.cancel()
            chatConnectionTask?.cancel()
            proxyMonitorTask?.cancel()
        }
    }

    // MARK: - 네트워크 모니터링 보조 (프록시 폴링 / 히스토리)

    /// 프록시 누적 바이트 30초 윈도우로 안정된 "평균 대역폭" 을 계산하고 60-샘플 링버퍼에 추가.
    /// 호출자: showNetworkMetrics didSet, 메트릭 콜백, proxyMonitorTask.
    func recordNetworkSample() {
        let now = Date()
        // [정밀화] 누적 바이트 링버퍼 관리 — burst 도착 패턴에 관계없이
        // (latest_bytes - oldest_bytes) / (latest_ts - oldest_ts) 로 정확한 평균 산출.
        var avgBps: Double = 0
        if let proxy = playerViewModel.proxyNetworkStats() {
            latestProxyStats = proxy
            byteHistory.append((now, proxy.totalBytesReceived))
            let cutoff = now.addingTimeInterval(-30.0)
            byteHistory.removeAll { $0.0 < cutoff }
            // 최소 2개 샘플 + 1초 이상 경과 해야 신뢰 가능한 평균
            if let first = byteHistory.first, let last = byteHistory.last,
               last.0.timeIntervalSince(first.0) >= 1.0 {
                let elapsed = last.0.timeIntervalSince(first.0)
                let deltaBytes = max(0, last.1 - first.1)
                avgBps = Double(deltaBytes) / elapsed
            }
            // 하위 호환성 — 기존 lastProxyBytes 필드도 유지 (다른 로직에서 참조 가능성).
            lastProxyBytesReceived = proxy.totalBytesReceived
            lastProxyBytesTimestamp = now
        }
        // 시드 직후 또는 stall 시 VLC 통계로 보강 (하위 우선순위)
        if avgBps == 0, let m = latestMetrics {
            if m.networkBytesPerSec > 0 {
                avgBps = Double(m.networkBytesPerSec)
            } else if m.inputBitrateKbps > 0 {
                avgBps = m.inputBitrateKbps * 1000.0 / 8.0
            } else if m.demuxBitrateKbps > 0 {
                avgBps = m.demuxBitrateKbps * 1000.0 / 8.0
            }
        }
        proxyBandwidthBytesPerSec = avgBps

        // [정밀화] VLC stat HW-decode 경로에서 0으로 고착되는 값 캡쳐
        if let m = latestMetrics {
            if m.fps > 0 { lastNonZeroFps = m.fps }
            if m.bufferHealth > 0 { lastNonZeroBufferHealth = m.bufferHealth }
        } else if let m = latestHLSJSMetrics {
            if m.fps > 0 { lastNonZeroFps = m.fps }
            if m.bufferHealth > 0 { lastNonZeroBufferHealth = m.bufferHealth }
        } else if let m = latestAVMetrics {
            if m.bufferHealth > 0 { lastNonZeroBufferHealth = m.bufferHealth }
        }

        // 통합 표시용 health/fps/buffer 도 함께 링버퍼에 적재
        let (health, fps, buffer, drops, late): (Double, Double, Double, Int, Int) = {
            if let m = latestMetrics {
                return (m.healthScore, m.fps, m.bufferHealth, m.droppedFramesDelta, m.latePicturesDelta)
            }
            if let m = latestAVMetrics {
                return (m.healthScore, 0, m.bufferHealth, m.droppedFramesDelta, 0)
            }
            if let m = latestHLSJSMetrics {
                return (m.healthScore, m.fps, m.bufferHealth, m.droppedFramesDelta, 0)
            }
            return (0, 0, 0, 0, 0)
        }()
        networkHistory.append(NetworkMonitorHistory.Sample(
            timestamp: now,
            bandwidthBytesPerSec: avgBps,
            fps: fps,
            healthScore: health,
            bufferHealth: buffer,
            dropsDelta: drops,
            lateDelta: late))
    }

    fileprivate func startProxyMonitorTask() {
        proxyMonitorTask?.cancel()
        // 리셋 후 시작 — 이전 세션 데이터가 그래프에 섞이지 않도록.
        lastProxyBytesReceived = 0
        lastProxyBytesTimestamp = nil
        proxyBandwidthBytesPerSec = 0
        byteHistory.removeAll()
        networkHistory.clear()
        // [Fix 정밀화] 즉시 시드(seed) — 현재 누적 바이트/타임스탬프를 채워두면
        // 첫 폴(1s 후) 부터 정상적인 delta 계산이 가능.
        if let proxy = playerViewModel.proxyNetworkStats() {
            latestProxyStats = proxy
            lastProxyBytesReceived = proxy.totalBytesReceived
            lastProxyBytesTimestamp = Date()
            byteHistory.append((Date(), proxy.totalBytesReceived))
        }
        proxyMonitorTask = Task { [weak self] in
            // 1초 폴 — 빠른 첫 표시 + 60샘플로 1분 분량 추세.
            let interval: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) } catch { break }
                guard let self else { break }
                await MainActor.run {
                    self.recordNetworkSample()
                }
            }
        }
    }

    fileprivate func stopProxyMonitorTask() {
        proxyMonitorTask?.cancel()
        proxyMonitorTask = nil
        byteHistory.removeAll()
    }

    /// MultiLiveManager용 convenience init — liveInfo/apiClient/사용자 정보 포함
    convenience init(
        channelId: String,
        channelName: String,
        profileImageURL: URL?,
        liveInfo: LiveInfo,
        apiClient: ChzzkAPIClient,
        userUid: String?,
        userNickname: String?,
        cachedBasicEmoticonMap: [String: String],
        cachedBasicEmoticonPacks: [EmoticonPack],
        engineType: PlayerEngineType = .vlc,
        engine: (any PlayerEngineProtocol)? = nil
    ) {
        self.init(channelId: channelId, engineType: engineType, engine: engine)
        self.channelName = channelName
        self.profileImageURL = profileImageURL
        self.liveTitle = liveInfo.liveTitle
        self.thumbnailURL = liveInfo.liveImageURL
        self.storedApiClient = apiClient
        self.chatViewModel.currentUserUid = userUid
        self.chatViewModel.currentUserNickname = userNickname
        self.chatViewModel.channelEmoticons = cachedBasicEmoticonMap
        self.chatViewModel.emoticonPacks = cachedBasicEmoticonPacks
    }

    /// 파라미터 없는 start — storedApiClient/storedAppState 사용 (MultiLiveManager 호환)
    func start() async {
        guard loadState != .loading else { return }
        guard let apiClient = storedApiClient else {
            loadState = .error("API 클라이언트 없음")
            return
        }
        // appState 없이 시작 — 간소화된 스트림 시작
        loadState = .loading
        do {
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)
            guard let playbackJSON = liveInfo.livePlaybackJSON,
                  let jsonData = playbackJSON.data(using: .utf8) else {
                loadState = .error("재생 정보를 찾을 수 없습니다.")
                return
            }
            let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
            let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" } ?? playback.media.first
            guard let mediaPath = media?.path, let streamURL = URL(string: mediaPath) else {
                loadState = .error("HLS 스트림 URL을 찾을 수 없습니다.")
                return
            }
            channelName = liveInfo.channel?.channelName ?? channelId
            liveTitle = liveInfo.liveTitle
            thumbnailURL = liveInfo.liveImageURL
            viewerCount = liveInfo.concurrentUserCount
            if liveInfo.accumulateCount > 0 {
                accumulateCount = liveInfo.accumulateCount
            }
            loadState = .playing(channelName: channelName, liveTitle: liveTitle)
            // 방송 종료 확인 콜백 설정 — 재연결 시 API로 라이브 상태 확인
            let _channelId = channelId
            playerViewModel.onCheckStreamEnded = { [weak apiClient] in
                guard let api = apiClient else { return false }
                do {
                    let status = try await api.liveStatus(channelId: _channelId)
                    return status.status == .close
                } catch {
                    return false
                }
            }
            await playerViewModel.startStream(
                channelId: channelId,
                streamUrl: streamURL,
                channelName: channelName,
                liveTitle: liveTitle
            )
            // startStream 내부에서 에러 발생 시 loadState를 .error로 전환
            // startStream은 throw하지 않고 내부적으로 errorMessage를 설정하므로 여기서 확인
            if let errorMsg = playerViewModel.errorMessage {
                loadState = .error(errorMsg)
                return
            }

            // VLC 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            let _forwarder = metricsForwarder
            let sessionChannelId = channelId
            // [Fix 24F] 콜백당 2개 Task → 1개로 통합 (4세션 × 2초 = 초당 4 Task 절약)
            playerViewModel.setVLCMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder?.updateVLCMetrics(metrics, forChannel: sessionChannelId)
                }
            }

            // AVPlayer 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            // [Fix 24F] 콜백당 2개 Task → 1개로 통합
            playerViewModel.setAVPlayerMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestAVMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder?.updateAVPlayerMetrics(metrics, forChannel: sessionChannelId)
                }
            }

            // HLS.js 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            // [Fix 24F] 콜백당 2개 Task → 1개로 통합
            playerViewModel.setHLSJSMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestHLSJSMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder?.updateHLSJSMetrics(metrics, forChannel: sessionChannelId)
                }
            }

            // 메트릭 채널 활성화 — 포그라운드 세션은 주 채널, 백그라운드 세션은 부가 채널로 등록
            if !isBackground {
                Task { await _forwarder?.activateChannel(channelId: channelId, channelName: channelName, streamUrl: streamURL.absoluteString) }
                // 서버 동기화 추천 → 재생 속도 적용 콜백
                let _playerVM = playerViewModel
                Task {
                    await _forwarder?.setSyncSpeedCallback { [weak _playerVM] speed in
                        Task { @MainActor in
                            _playerVM?.applySyncSpeed(speed)
                        }
                    }
                    // [Fix 20] PID 활성 상태 콜백 — PID 능동 제어 중이면 서버 추천 무시
                    await _forwarder?.setPIDActiveCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return false }
                        return await coord.lowLatencyController?.isPIDActive ?? false
                    }
                    // [Fix 20 Phase3] PID 현재 배율 콜백 — Rate Arbiter 통합 속도 결정
                    await _forwarder?.setPIDCurrentRateCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 1.0 }
                        return await coord.lowLatencyController?.currentRate ?? 1.0
                    }
                    // 현재 엔진의 목표 레이턴시를 서버 동기화 기준값으로 전달
                    if let targetLatencyMs = _playerVM.currentLatencyTargets()?.syncTargetMs {
                        await _forwarder?.setTargetLatency(targetLatencyMs)
                    }
                    // 재생 위치(currentTime) 콜백 연결
                    await _forwarder?.setCurrentTimeCallback { [weak _playerVM] in
                        await MainActor.run { _playerVM?.currentTime ?? 0 }
                    }
                    // PDT 기반 레이턴시 콜백 — StreamCoordinator에서 직접 조회 (초 단위)
                    await _forwarder?.setPDTLatencyCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return nil }
                        if let latency = await coord.currentLatencySeconds() {
                            return latency  // 초 단위 (MetricsForwarder에서 ×1000)
                        }
                        return nil
                    }
                    // 레이턴시(ms) 직접 조회 콜백 — PDT 미지원 시 VLC buffer fallback
                    await _forwarder?.setLatencyMsCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 0 }
                        let latency = await coord.currentLatencySeconds() ?? 0
                        return latency * 1000  // 초 → ms
                    }
                }
            } else {
                // 백그라운드 세션 → 멀티라이브 부가 채널로 등록
                let _playerVM = playerViewModel
                Task {
                    await _forwarder?.registerMultiLiveChannel(channelId: channelId, channelName: channelName)
                    // 채널별 콜백 등록
                    if let targetLatencyMs = _playerVM.currentLatencyTargets()?.syncTargetMs {
                        await _forwarder?.setTargetLatency(targetLatencyMs, forChannel: sessionChannelId)
                    }
                    await _forwarder?.setCurrentTimeCallback({ [weak _playerVM] in
                        await MainActor.run { _playerVM?.currentTime ?? 0 }
                    }, forChannel: sessionChannelId)
                    // PDT 기반 레이턴시 콜백 — StreamCoordinator에서 직접 조회 (초 단위)
                    await _forwarder?.setPDTLatencyCallback({ [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return nil }
                        if let latency = await coord.currentLatencySeconds() {
                            return latency
                        }
                        return nil
                    }, forChannel: sessionChannelId)
                    // 레이턴시(ms) 직접 조회 콜백 — PDT 미지원 시 VLC buffer fallback
                    await _forwarder?.setLatencyMsCallback({ [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 0 }
                        let latency = await coord.currentLatencySeconds() ?? 0
                        return latency * 1000
                    }, forChannel: sessionChannelId)
                }
            }

            // 채팅 연결
            if let chatChannelId = liveInfo.chatChannelId {
                let chatVM = chatViewModel
                let _channelId = channelId
                let _apiClient = apiClient
                chatConnectionTask = Task {
                    do {
                        let tokenInfo = try await _apiClient.chatAccessToken(chatChannelId: chatChannelId)
                        await chatVM.connect(
                            chatChannelId: chatChannelId,
                            accessToken: tokenInfo.accessToken,
                            extraToken: tokenInfo.extraToken,
                            uid: chatVM.currentUserUid,
                            channelId: _channelId
                        )
                    } catch {
                        Log.chat.error("멀티라이브 채팅 연결 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - 스트림 시작

    func start(using apiClient: ChzzkAPIClient, appState: AppState, paneCount: Int = 1) async {
        guard loadState != .loading else { return }
        loadState = .loading

        playerViewModel.onPlaybackStateChanged = { [weak appState] in
            appState?.updatePlaybackActivity()
        }

        do {
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)

            guard let playbackJSON = liveInfo.livePlaybackJSON,
                  let jsonData = playbackJSON.data(using: .utf8) else {
                loadState = .error("재생 정보를 찾을 수 없습니다.")
                return
            }

            let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
            let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                ?? playback.media.first

            guard let mediaPath = media?.path, let streamURL = URL(string: mediaPath) else {
                loadState = .error("HLS 스트림 URL을 찾을 수 없습니다.")
                return
            }

            channelName  = liveInfo.channel?.channelName ?? channelId
            liveTitle    = liveInfo.liveTitle
            thumbnailURL = liveInfo.liveImageURL
            viewerCount  = liveInfo.concurrentUserCount
            if liveInfo.accumulateCount > 0 {
                accumulateCount = liveInfo.accumulateCount
            }

            let ps = appState.settingsStore.player
            playerViewModel.preferredEngineType = ps.preferredEngine

            // [로딩 상태 조기 전환] API 데이터 확보 후 즉시 .playing으로 전환하여
            // VLC 버퍼링 중에도 비디오 레이어가 노출되도록 한다.
            // 기존: startStream() 완료 후 전환 → 버퍼링 중 전체 화면 StreamLoadingOverlay 표시
            // 개선: API 응답 확보 시점에 전환 → 버퍼링은 소형 스피너로만 표시, 비디오 보임
            loadState = .playing(channelName: channelName, liveTitle: liveTitle)

            await playerViewModel.startStream(
                channelId: channelId,
                streamUrl: streamURL,
                channelName: channelName,
                liveTitle: liveTitle,
                playerSettings: ps
            )
            // startStream 내부 에러 확인 → loadState 동기화
            if let errorMsg = playerViewModel.errorMessage {
                loadState = .error(errorMsg)
                return
            }
            playerViewModel.applySettings(
                volume: ps.volumeLevel,
                lowLatency: ps.lowLatencyMode,
                catchupRate: ps.catchupRate
            )
            playerViewModel.applyForceHighestQuality(ps.forceHighestQuality)
            playerViewModel.applySharpPixelScaling(ps.sharpPixelScaling)
            playerViewModel.applyMultiLiveConstraints(paneCount: paneCount)

            // [P0-4 2026-04-24] forceHighestQuality 시에도 비선택 세션의 일괄 .active 승격 제거.
            //   기존 동작: 모든 세션이 시작과 동시에 multiLiveHQ tier 로 올라가 1080p 변종 선택 →
            //   대역폭 코디네이터/비선택 절약 정책이 무력화되어 디코딩/프록시/GPU 병목 발생.
            //   변경 동작: 첫 세션은 MultiLiveManager 가 selectedSessionId 지정 시 .active 로 승격,
            //   비선택 세션은 .multiLive 프로파일(480p 시작) 그대로 두어 선택 시점에만 HQ 승격.
            //   AVPlayer 도 동일 원칙: 선택된 세션만 isSelectedMultiLiveSession=true.

            // VLC 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            // [Bug-fix] 콜백당 2개 Task → 1개로 통합 (상단 start() 경로와 동일 패턴 적용).
            // 기존 fire-and-forget Task 는 weak self 가 없어 세션 해제 후에도 계속 실행되어 리소스 낭비.
            let _forwarder2 = metricsForwarder ?? appState.metricsForwarder
            let sessionChannelId2 = channelId
            playerViewModel.setVLCMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder2?.updateVLCMetrics(metrics, forChannel: sessionChannelId2)
                }
            }

            // AVPlayer 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            playerViewModel.setAVPlayerMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestAVMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder2?.updateAVPlayerMetrics(metrics, forChannel: sessionChannelId2)
                }
            }

            // HLS.js 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송 (멀티라이브: 모든 세션 전송)
            playerViewModel.setHLSJSMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestHLSJSMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                    await _forwarder2?.updateHLSJSMetrics(metrics, forChannel: sessionChannelId2)
                }
            }

            // 메트릭 채널 활성화 — 포그라운드 세션은 주 채널, 백그라운드 세션은 부가 채널로 등록
            if !isBackground {
                let _playerVM = playerViewModel
                Task {
                    await _forwarder2?.activateChannel(channelId: channelId, channelName: channelName, streamUrl: streamURL.absoluteString)
                    // PDT 기반 레이턴시 콜백 — StreamCoordinator에서 직접 조회 (초 단위)
                    await _forwarder2?.setPDTLatencyCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return nil }
                        if let latency = await coord.currentLatencySeconds() {
                            return latency
                        }
                        return nil
                    }
                    // 레이턴시(ms) 직접 조회 콜백 — PDT 미지원 시 VLC buffer fallback
                    await _forwarder2?.setLatencyMsCallback { [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 0 }
                        let latency = await coord.currentLatencySeconds() ?? 0
                        return latency * 1000
                    }
                    await _forwarder2?.setCurrentTimeCallback { [weak _playerVM] in
                        await MainActor.run { _playerVM?.currentTime ?? 0 }
                    }
                    if let targetLatencyMs = _playerVM.currentLatencyTargets()?.syncTargetMs {
                        await _forwarder2?.setTargetLatency(targetLatencyMs)
                    }
                }
            } else {
                // 백그라운드 세션 → 멀티라이브 부가 채널로 등록
                let _playerVM = playerViewModel
                Task {
                    await _forwarder2?.registerMultiLiveChannel(channelId: channelId, channelName: channelName)
                    if let targetLatencyMs = _playerVM.currentLatencyTargets()?.syncTargetMs {
                        await _forwarder2?.setTargetLatency(targetLatencyMs, forChannel: sessionChannelId2)
                    }
                    await _forwarder2?.setCurrentTimeCallback({ [weak _playerVM] in
                        await MainActor.run { _playerVM?.currentTime ?? 0 }
                    }, forChannel: sessionChannelId2)
                    // PDT 기반 레이턴시 콜백 — StreamCoordinator에서 직접 조회 (초 단위)
                    await _forwarder2?.setPDTLatencyCallback({ [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return nil }
                        if let latency = await coord.currentLatencySeconds() {
                            return latency
                        }
                        return nil
                    }, forChannel: sessionChannelId2)
                    // 레이턴시(ms) 직접 조회 콜백 — PDT 미지원 시 VLC buffer fallback
                    await _forwarder2?.setLatencyMsCallback({ [weak _playerVM] in
                        guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 0 }
                        let latency = await coord.currentLatencySeconds() ?? 0
                        return latency * 1000
                    }, forChannel: sessionChannelId2)
                }
            }

            startPolling(apiClient: apiClient, appState: appState)

            // 채팅 연결 (백그라운드 병렬)
            if let chatChannelId = liveInfo.chatChannelId {
                let _channelId = channelId
                let chatVM = chatViewModel
                chatConnectionTask = Task { [isLoggedIn = appState.isLoggedIn, fallbackUid = appState.userChannelId] in
                    do {
                        async let tokenTask = apiClient.chatAccessToken(chatChannelId: chatChannelId)
                        async let userTask: UserStatusInfo? = isLoggedIn ? (try? await apiClient.userStatus()) : nil
                        async let packsTask = apiClient.basicEmoticonPacks(channelId: _channelId)

                        let tokenInfo = try await tokenTask
                        let userInfo  = await userTask
                        let packs     = await packsTask
                        let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(packs)

                        let uid: String? = userInfo?.userIdHash ?? (isLoggedIn ? fallbackUid : nil)
                        await MainActor.run {
                            chatVM.channelEmoticons = emoMap
                            chatVM.emoticonPacks = loadedPacks
                            if let uid { chatVM.currentUserUid = uid }
                            chatVM.currentUserNickname = userInfo?.nickname
                        }
                        await chatVM.connect(
                            chatChannelId: chatChannelId,
                            accessToken: tokenInfo.accessToken,
                            extraToken: tokenInfo.extraToken,
                            uid: uid,
                            channelId: _channelId
                        )
                    } catch {
                        Log.chat.error("멀티라이브 채팅 연결 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - 종료

    func stop() async {
        startTask?.cancel(); startTask = nil
        pollTask?.cancel(); pollTask = nil
        refreshTask?.cancel(); refreshTask = nil
        offlineRetryTask?.cancel(); offlineRetryTask = nil
        chatConnectionTask?.cancel(); chatConnectionTask = nil
        proxyMonitorTask?.cancel(); proxyMonitorTask = nil
        // [장시간 안정성] 메트릭 콜백 해제 — 해제된 세션에서 fire-and-forget Task 생성 방지
        playerViewModel.setVLCMetricsCallback(nil)
        playerViewModel.setAVPlayerMetricsCallback(nil)
        playerViewModel.setHLSJSMetricsCallback(nil)
        // 메트릭 포워더 채널 해제 — 주 채널이면 비활성화, 부가 채널이면 등록 해제
        if await metricsForwarder?.currentChannelId == channelId {
            await metricsForwarder?.deactivateCurrentChannel()
        } else {
            await metricsForwarder?.unregisterMultiLiveChannel(channelId: channelId)
        }
        await playerViewModel.stopStream()
        await chatViewModel.disconnect()
        loadState = .idle
        latestMetrics = nil
        latestAVMetrics = nil
        latestHLSJSMetrics = nil
        latestProxyStats = nil
        proxyBandwidthBytesPerSec = 0
        networkHistory.clear()
        lastProxyBytesReceived = 0
        lastProxyBytesTimestamp = nil
        byteHistory.removeAll()
        lastNonZeroFps = 0
        lastNonZeroBufferHealth = 0
    }

    func retry(using apiClient: ChzzkAPIClient, appState: AppState) async {
        // [장시간 안정성] 재시도 전 기존 리소스 정리 — 중복 연결 방지
        offlineRetryTask?.cancel(); offlineRetryTask = nil
        chatConnectionTask?.cancel(); chatConnectionTask = nil
        await playerViewModel.stopStream()
        await chatViewModel.disconnect()
        loadState = .idle
        isOffline = false
        await start(using: apiClient, appState: appState)
    }

    func refreshStream(using apiClient: ChzzkAPIClient, appState: AppState) async {
        await stop()
        await start(using: apiClient, appState: appState)
    }

    // MARK: - 배경 모드

    func setBackgroundMode(_ background: Bool) {
        guard isBackground != background else { return }
        isBackground = background
        playerViewModel.setBackgroundMode(background)
    }

    func setMuted(_ muted: Bool) {
        playerViewModel.isMuted = muted
        playerViewModel.setVolume(muted ? 0 : playerViewModel.volume)
    }

    // MARK: - 폴링

    private func startPolling(apiClient: ChzzkAPIClient, appState: AppState) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var consecutiveErrors = 0
            var totalRetries = 0
            let maxTotalRetries = 10
            do {
                while !Task.isCancelled {
                    // [장시간 안정성] sleep 전에는 weak 접근만 — sleep 중 세션 해제 허용
                    // [Tune] 배경 모드 60→180s: 비활성 윈도우에서 폴링 빈도 1/3로 축소 — 배터리/데이터 절감
                    let interval: Duration = (self?.isBackground ?? false) ? .seconds(180) : .seconds(30)
                    try await Task.sleep(for: interval)
                    guard !Task.isCancelled, let self else { break }

                    // 방송 상태 폴링
                    do {
                        let status = try await apiClient.liveStatus(channelId: self.channelId)
                        self.viewerCount = status.concurrentUserCount
                        if status.accumulateCount > 0 {
                            self.accumulateCount = status.accumulateCount
                        }
                        if status.status == .close {
                            if !self.isOffline {
                                self.isOffline = true
                                self.loadState = .offline
                                Task { await self.playerViewModel.stopStream() }
                                // 오프라인 감지 → 2분 후 자동 재시도
                                self.offlineRetryTask?.cancel()
                                // [Bug-fix] apiClient/appState 를 weak 캐프처하여 세션 해제 시
                                // 120s 대기하던 Task 가 이들을 강하게 잡아두지 않도록 함.
                                self.offlineRetryTask = Task { [weak self, weak apiClient, weak appState] in
                                    try? await Task.sleep(for: .seconds(120))
                                    guard !Task.isCancelled,
                                          let self, self.isOffline,
                                          let apiClient, let appState else { return }
                                    await self.retry(using: apiClient, appState: appState)
                                }
                            }
                        } else {
                            self.isOffline = false
                        }
                    } catch {
                        Log.network.debug("멀티라이브 상태 폴링 실패 channelId=\(self.channelId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }

                    // VLC 엔진 헬스 체크 (오프라인 아닐 때)
                    guard !self.isOffline else { consecutiveErrors = 0; continue }
                    let inError = self.playerViewModel.playerEngine?.isInErrorState ?? false
                    if inError {
                        consecutiveErrors += 1
                        Log.player.warning("멀티라이브 엔진 ERROR (\(consecutiveErrors)연속) channelId=\(self.channelId, privacy: .public)")
                        if consecutiveErrors >= 2 {
                            consecutiveErrors = 0
                            totalRetries += 1
                            if totalRetries > maxTotalRetries {
                                Log.player.error("멀티라이브 최대 재시도 초과(\(maxTotalRetries)회) — 재시도 중단 channelId=\(self.channelId, privacy: .public)")
                                self.loadState = .error("재시도 한도 초과")
                                break
                            }
                            await self.retry(using: apiClient, appState: appState)
                        }
                    } else {
                        consecutiveErrors = 0
                    }
                }
            } catch {
                // CancellationError → 폴링 종료
            }
        }

        scheduleProactiveRefresh(apiClient: apiClient, appState: appState)
    }

    /// CDN 토큰 만료 대비 50분마다 스트림 URL 재취득 — [Tune] 55→50분으로 안전 마진 확대 (일반적으로 CDN 토큰은 60분 TTL)
    private func scheduleProactiveRefresh(apiClient: ChzzkAPIClient, appState: AppState) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(50 * 60))
                while !Task.isCancelled {
                    // [장시간 안정성] sleep 전에는 weak 접근만
                    if self?.isOffline ?? true {
                        try await Task.sleep(for: .seconds(60))
                        continue
                    }
                    guard let self else { break }
                    Log.player.info("멀티라이브 주기적 URL 재취득 — CDN 토큰 만료 예방 channelId=\(self.channelId, privacy: .public)")
                    self.playerViewModel.playerEngine?.resetRetries()
                    await self.retry(using: apiClient, appState: appState)
                    try await Task.sleep(for: .seconds(50 * 60))
                }
            } catch {
                // CancellationError → 정상 종료
            }
        }
    }
}

// MARK: - 그리드 레이아웃 모드

enum MultiLiveGridLayoutMode: Equatable, Sendable {
    case preset
    case custom
    case focusLeft   // 포커스 레이아웃: 왼쪽 메인(70%) + 오른쪽 서브(30%)
}

// MARK: - 커스텀 레이아웃 비율

struct MultiLiveLayoutRatios: Equatable, Sendable {
    var horizontalRatio: CGFloat = 0.5
    var verticalRatio: CGFloat = 0.5

    static let minRatio: CGFloat = 0.2
    static let maxRatio: CGFloat = 0.8

    mutating func clampHorizontal() {
        horizontalRatio = min(Self.maxRatio, max(Self.minRatio, horizontalRatio))
    }
    mutating func clampVertical() {
        verticalRatio = min(Self.maxRatio, max(Self.minRatio, verticalRatio))
    }
}

// MARK: - 세션 지속성 (UserDefaults)

/// 멀티라이브 세션 상태를 UserDefaults에 저장하기 위한 Codable 모델
struct MultiLivePersistedState: Codable, Equatable {
    var channelIds: [String]
    var isGridLayout: Bool
    var gridLayoutMode: String   // "preset" | "custom" | "focusLeft"
    var horizontalRatio: Double
    var verticalRatio: Double

    static let userDefaultsKey = "multiLivePersistedState"

    @MainActor
    init(from manager: MultiLiveManager) {
        self.channelIds = manager.sessions.map { $0.channelId }
        self.isGridLayout = manager.isGridLayout
        switch manager.gridLayoutMode {
        case .preset:    self.gridLayoutMode = "preset"
        case .custom:    self.gridLayoutMode = "custom"
        case .focusLeft: self.gridLayoutMode = "focusLeft"
        }
        self.horizontalRatio = Double(manager.layoutRatios.horizontalRatio)
        self.verticalRatio = Double(manager.layoutRatios.verticalRatio)
    }



    var parsedGridLayoutMode: MultiLiveGridLayoutMode {
        switch gridLayoutMode {
        case "custom":    return .custom
        case "focusLeft": return .focusLeft
        default:          return .preset
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            Log.app.warning("멀티라이브 상태 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> MultiLivePersistedState? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(MultiLivePersistedState.self, from: data)
        } catch {
            Log.app.warning("멀티라이브 상태 복원 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
