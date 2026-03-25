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
    var isChatVisible: Bool = true
    var latestMetrics: VLCLiveMetrics?
    var latestProxyStats: ProxyNetworkStats?
    var showStats: Bool = false
    var showNetworkMetrics: Bool = false
    var isMuted: Bool { playerViewModel.isMuted }

    /// 시청자 수 포맷 (3곳에서 중복 사용하던 로직 통합)
    var formattedViewerCount: String {
        let n = viewerCount
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n) 명"
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

            // VLC 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송
            let _forwarder = metricsForwarder
            let sessionChannelId = channelId
            playerViewModel.setVLCMetricsCallback { [weak self] metrics in
                Task {
                    // 선택된 세션(활성 채널)의 메트릭만 서버로 전송
                    if await _forwarder?.currentChannelId == sessionChannelId {
                        await _forwarder?.updateVLCMetrics(metrics)
                    }
                }
                Task { @MainActor [weak self] in
                    guard let self, self.showStats || self.showNetworkMetrics else { return }
                    self.latestMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                }
            }

            // 메트릭 채널 활성화 (포그라운드 세션만)
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
                    // VLC 엔진의 liveCaching 값을 targetLatency로 전달
                    if let vlc = _playerVM.playerEngine as? VLCPlayerEngine {
                        await _forwarder?.setTargetLatency(Double(vlc.streamingProfile.liveCaching))
                    }
                    // 재생 위치(currentTime) 콜백 연결
                    await _forwarder?.setCurrentTimeCallback { [weak _playerVM] in
                        await MainActor.run { _playerVM?.currentTime ?? 0 }
                    }
                    // PDT 기반 레이턴시 콜백 연결 (초 → 밀리초 변환)
                    await _forwarder?.setPDTLatencyCallback { [weak _playerVM] in
                        let info = await MainActor.run { _playerVM?.latencyInfo }
                        return info.map { $0.current * 1000 }
                    }
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
                    } catch {}
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
            playerViewModel.applyMultiLiveConstraints(paneCount: paneCount)

            // VLC 메트릭 콜백 — 로컬 표시 + MetricsForwarder 전송
            let _forwarder2 = metricsForwarder ?? appState.metricsForwarder
            let sessionChannelId2 = channelId
            playerViewModel.setVLCMetricsCallback { [weak self] metrics in
                Task {
                    // 선택된 세션(활성 채널)의 메트릭만 서버로 전송
                    if await _forwarder2?.currentChannelId == sessionChannelId2 {
                        await _forwarder2?.updateVLCMetrics(metrics)
                    }
                }
                Task { @MainActor [weak self] in
                    guard let self, self.showStats || self.showNetworkMetrics else { return }
                    self.latestMetrics = metrics
                    self.latestProxyStats = await self.playerViewModel.proxyNetworkStats()
                }
            }

            // 메트릭 채널 활성화 (포그라운드 세션만)
            if !isBackground {
                Task { await _forwarder2?.activateChannel(channelId: channelId, channelName: channelName, streamUrl: streamURL.absoluteString) }
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
        // 메트릭 포워더 채널 비활성화 — 이 세션이 활성 채널인 경우에만
        if await metricsForwarder?.currentChannelId == channelId {
            await metricsForwarder?.deactivateCurrentChannel()
        }
        await playerViewModel.stopStream()
        await chatViewModel.disconnect()
        loadState = .idle
        latestMetrics = nil
        latestProxyStats = nil
    }

    func retry(using apiClient: ChzzkAPIClient, appState: AppState) async {
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
            guard let self else { return }
            var consecutiveErrors = 0
            var totalRetries = 0
            let maxTotalRetries = 10
            do {
                while !Task.isCancelled {
                    let interval: Duration = self.isBackground ? .seconds(60) : .seconds(30)
                    try await Task.sleep(for: interval)
                    guard !Task.isCancelled else { break }

                    // 방송 상태 폴링
                    do {
                        let status = try await apiClient.liveStatus(channelId: self.channelId)
                        await MainActor.run {
                            self.viewerCount = status.concurrentUserCount
                            if status.status == .close {
                                if !self.isOffline {
                                    self.isOffline = true
                                    self.loadState = .offline
                                    Task { await self.playerViewModel.stopStream() }
                                    // 오프라인 감지 → 2분 후 자동 재시도
                                    self.offlineRetryTask?.cancel()
                                    self.offlineRetryTask = Task { [weak self] in
                                        guard let self else { return }
                                        try? await Task.sleep(for: .seconds(120))
                                        guard !Task.isCancelled, self.isOffline else { return }
                                        await self.retry(using: apiClient, appState: appState)
                                    }
                                }
                            } else {
                                self.isOffline = false
                            }
                        }
                    } catch {}

                    // VLC 엔진 헬스 체크 (오프라인 아닐 때)
                    guard !self.isOffline else { consecutiveErrors = 0; continue }
                    let inError = await MainActor.run {
                        self.playerViewModel.playerEngine?.isInErrorState ?? false
                    }
                    if inError {
                        consecutiveErrors += 1
                        Log.player.warning("멀티라이브 엔진 ERROR (\(consecutiveErrors)연속) channelId=\(self.channelId, privacy: .public)")
                        if consecutiveErrors >= 2 {
                            consecutiveErrors = 0
                            totalRetries += 1
                            if totalRetries > maxTotalRetries {
                                Log.player.error("멀티라이브 최대 재시도 초과(\(maxTotalRetries)회) — 재시도 중단 channelId=\(self.channelId, privacy: .public)")
                                await MainActor.run { self.loadState = .error("재시도 한도 초과") }
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

    /// CDN 토큰 만료 대비 55분마다 스트림 URL 재취득
    private func scheduleProactiveRefresh(apiClient: ChzzkAPIClient, appState: AppState) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(55 * 60))
                while !Task.isCancelled {
                    if self.isOffline {
                        try await Task.sleep(for: .seconds(60))
                        continue
                    }
                    Log.player.info("멀티라이브 주기적 URL 재취득 — CDN 토큰 만료 예방 channelId=\(self.channelId, privacy: .public)")
                    await MainActor.run { self.playerViewModel.playerEngine?.resetRetries() }
                    await self.retry(using: apiClient, appState: appState)
                    try await Task.sleep(for: .seconds(55 * 60))
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
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> MultiLivePersistedState? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(MultiLivePersistedState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
