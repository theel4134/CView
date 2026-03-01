// MARK: - MultiLiveSession.swift
// 멀티 라이브 — 탭 하나에 해당하는 플레이어+채팅 세션

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking

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
    var viewerCount: Int = 0
    var isOffline: Bool = false

    // MARK: - ViewModel

    let playerViewModel: PlayerViewModel
    let chatViewModel: ChatViewModel

    // MARK: - UI 상태

    var loadState: MultiLiveLoadState = .idle
    var isChatVisible: Bool = true
    var latestMetrics: VLCLiveMetrics?
    var showStats: Bool = false
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

    init(channelId: String, preallocatedEngine: VLCPlayerEngine? = nil, engineType: PlayerEngineType = .vlc) {
        self.id = UUID()
        self.channelId = channelId
        if let engine = preallocatedEngine {
            self.playerViewModel = PlayerViewModel(preallocatedEngine: engine)
        } else {
            self.playerViewModel = PlayerViewModel(engineType: engineType)
        }
        self.chatViewModel = ChatViewModel()
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
            liveTitle    = liveInfo.liveTitle ?? ""
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
                liveTitle: liveTitle
            )
            playerViewModel.applySettings(
                volume: ps.volumeLevel,
                lowLatency: ps.lowLatencyMode,
                catchupRate: ps.catchupRate
            )
            playerViewModel.applyMultiLiveConstraints(paneCount: paneCount)

            // VLC 메트릭 콜백 — showStats가 true일 때만 업데이트
            playerViewModel.setVLCMetricsCallback { [weak self] metrics in
                Task { @MainActor [weak self] in
                    guard let self, self.showStats else { return }
                    self.latestMetrics = metrics
                }
            }

            // VLC 엔진일 때만 drawable 재바인딩 추가 시도
            // play() 후 vout 초기화 시점에 재바인딩으로 화면 출력 복구 보장
            if let vlc = playerViewModel.mediaPlayer {
                Task { @MainActor [weak vlc] in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
                    vlc?.refreshDrawable()
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
        await playerViewModel.stopStream()
        await chatViewModel.disconnect()
        loadState = .idle
        latestMetrics = nil
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
            try? await Task.sleep(for: .seconds(55 * 60))
            while !Task.isCancelled {
                if self.isOffline {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }
                Log.player.info("멀티라이브 주기적 URL 재취득 — CDN 토큰 만료 예방 channelId=\(self.channelId, privacy: .public)")
                await MainActor.run { self.playerViewModel.playerEngine?.resetRetries() }
                await self.retry(using: apiClient, appState: appState)
                try? await Task.sleep(for: .seconds(55 * 60))
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
    init(from manager: MultiLiveSessionManager) {
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

// MARK: - MultiLiveSessionManager

/// 멀티 라이브 세션 집합 관리
@Observable
@MainActor
final class MultiLiveSessionManager {

    static let maxSessions = 4

    var sessions: [MultiLiveSession] = []
    var selectedSessionId: UUID?
    var isGridLayout: Bool = false
    var gridLayoutMode: MultiLiveGridLayoutMode = .preset
    var layoutRatios: MultiLiveLayoutRatios = MultiLiveLayoutRatios()
    var draggingSessionIndex: Int? = nil
    var audioSessionId: UUID?

    /// 멀티 오디오 모드 — 여러 세션 동시 오디오 재생
    var isMultiAudioMode: Bool = false
    /// 멀티 오디오 모드에서 오디오가 활성화된 세션 ID 집합
    var audioEnabledSessionIds: Set<UUID> = []

    /// VLC 인스턴스 풀 — 멀티라이브 세션 간 엔진 재사용
    let enginePool = VLCInstancePool(maxPoolSize: maxSessions)

    var selectedSession: MultiLiveSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    var audioSession: MultiLiveSession? {
        guard let id = audioSessionId else { return selectedSession }
        return sessions.first { $0.id == id }
    }

    // MARK: - CRUD

    func addSession(channelId: String, preferredEngine: PlayerEngineType = .vlc) async -> MultiLiveSession? {
        guard sessions.count < Self.maxSessions else { return nil }
        guard !sessions.contains(where: { $0.channelId == channelId }) else { return nil }

        let session: MultiLiveSession
        switch preferredEngine {
        case .vlc:
            if sessions.isEmpty { await enginePool.warmup(count: 2) }
            let engine = await enginePool.acquire()
            session = MultiLiveSession(channelId: channelId, preallocatedEngine: engine)
        case .avPlayer:
            session = MultiLiveSession(channelId: channelId, engineType: .avPlayer)
        }

        // 기존 선택 탭을 배경 모드로 전환 (탭 모드)
        if !isGridLayout, let current = selectedSession {
            current.setBackgroundMode(true)
        }

        sessions.append(session)
        selectedSessionId = session.id

        let totalCount = sessions.count
        for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: totalCount) }
        saveState()
        return session
    }

    func removeSession(_ session: MultiLiveSession) async {
        // ⚠️ 세션을 먼저 정지한 후 엔진 반납 (순서 중요)
        // release 먼저 하면 resetForReuse 후 session.stop()이 같은 엔진을 이중 정리하여 충돌
        await session.stop()
        if let vlcEngine = session.playerViewModel.mediaPlayer {
            await enginePool.release(vlcEngine)
        }
        sessions.removeAll { $0.id == session.id }

        if selectedSessionId == session.id { selectedSessionId = sessions.last?.id }

        if audioSessionId == session.id {
            audioSessionId = sessions.first?.id
            if let newId = audioSessionId {
                for s in sessions { s.setMuted(s.id != newId) }
            }
        }
        audioEnabledSessionIds.remove(session.id)

        if sessions.count <= 1 { isGridLayout = false }

        let remaining = sessions.count
        for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: remaining) }
        saveState()
    }

    func select(_ session: MultiLiveSession) {
        guard selectedSessionId != session.id else { return }
        if !isGridLayout {
            if let current = selectedSession, current.id != session.id {
                current.setBackgroundMode(true)
            }
            session.setBackgroundMode(false)
        }
        selectedSessionId = session.id
        if !isGridLayout && !isMultiAudioMode {
            audioSessionId = nil
            for s in sessions { s.setMuted(s.id != session.id) }
        }
        // [VLC 안정 컨테이너 패턴] 뷰가 더이상 파괴→재생성되지 않으므로
        // ForEach + opacity/zIndex로 가시성만 전환 → drawable 연결이 유지됨.
        // 기존 0.3초 지연 refreshDrawable() 불필요 → 즉시 refreshDrawable()만 호출.
        // setBackgroundMode(false) 내부에서도 refreshDrawable()이 호출되므로 이중 보호.
        if let vlc = session.playerViewModel.mediaPlayer {
            vlc.refreshDrawable()
        }
        saveState()
    }

    func routeAudio(to session: MultiLiveSession) {
        guard audioSessionId != session.id else { return }
        audioSessionId = session.id
        for s in sessions { s.setMuted(s.id != session.id) }
    }

    /// 멀티 오디오 모드 토글
    func toggleMultiAudioMode() {
        isMultiAudioMode.toggle()
        if isMultiAudioMode {
            // 현재 오디오 세션을 멀티 오디오 초기 세션으로 설정
            audioEnabledSessionIds.removeAll()
            if let currentAudioId = audioSessionId ?? selectedSessionId {
                audioEnabledSessionIds.insert(currentAudioId)
            }
            // 활성화된 세션만 음소거 해제
            for s in sessions {
                s.setMuted(!audioEnabledSessionIds.contains(s.id))
            }
        } else {
            // 단일 오디오 모드로 복귀 — 선택된 세션만 오디오
            audioEnabledSessionIds.removeAll()
            let activeId = audioSessionId ?? selectedSessionId
            for s in sessions {
                s.setMuted(s.id != activeId)
            }
        }
    }

    /// 멀티 오디오 모드에서 개별 세션 오디오 토글
    func toggleSessionAudio(_ session: MultiLiveSession) {
        guard isMultiAudioMode else {
            routeAudio(to: session)
            return
        }
        if audioEnabledSessionIds.contains(session.id) {
            audioEnabledSessionIds.remove(session.id)
            session.setMuted(true)
        } else {
            audioEnabledSessionIds.insert(session.id)
            session.setMuted(false)
        }
    }

    /// 멀티 오디오 모드에서 세션의 오디오 활성 여부
    func isAudioEnabled(for session: MultiLiveSession) -> Bool {
        if isMultiAudioMode {
            return audioEnabledSessionIds.contains(session.id)
        } else {
            return (audioSessionId ?? selectedSessionId) == session.id
        }
    }

    func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
    }

    func swapSessions(_ i: Int, _ j: Int) {
        guard i != j, sessions.indices.contains(i), sessions.indices.contains(j) else { return }
        sessions.swapAt(i, j)
    }

    func resetLayoutRatios() { layoutRatios = MultiLiveLayoutRatios() }

    func moveSessionLeft(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx > 0 else { return }
        sessions.swapAt(idx, idx - 1)
    }

    func moveSessionRight(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx < sessions.count - 1 else { return }
        sessions.swapAt(idx, idx + 1)
    }

    func stopAll() async {
        for s in sessions { await s.stop() }
        sessions.removeAll()
        selectedSessionId = nil
        audioSessionId = nil
        isMultiAudioMode = false
        audioEnabledSessionIds.removeAll()
        isGridLayout = false
        gridLayoutMode = .preset
        layoutRatios = MultiLiveLayoutRatios()
        draggingSessionIndex = nil
        await enginePool.drain()
        MultiLivePersistedState.clear()
    }

    // MARK: - 세션 지속성

    /// 현재 세션 구성을 UserDefaults에 저장
    func saveState() {
        guard !sessions.isEmpty else {
            MultiLivePersistedState.clear()
            return
        }
        let state = MultiLivePersistedState(from: self)
        state.save()
    }

    /// 레이아웃 변경 시 자동 저장
    func saveLayoutChange() {
        saveState()
    }

    /// 저장된 세션 구성 복원 (비동기 — 채널 추가 + 스트림 시작 포함)
    /// - Returns: 복원된 세션 수 (0이면 저장된 상태 없음)
    @discardableResult
    func restoreState(appState: AppState) async -> Int {
        guard sessions.isEmpty else { return 0 }  // 이미 세션이 있으면 스킵
        guard let state = MultiLivePersistedState.load() else { return 0 }
        guard !state.channelIds.isEmpty else { return 0 }

        // 레이아웃 설정 먼저 복원
        isGridLayout = state.isGridLayout
        gridLayoutMode = state.parsedGridLayoutMode
        layoutRatios.horizontalRatio = CGFloat(state.horizontalRatio)
        layoutRatios.verticalRatio = CGFloat(state.verticalRatio)
        layoutRatios.clampHorizontal()
        layoutRatios.clampVertical()

        // 채널 순서대로 세션 추가 + 스트림 시작
        var restored = 0
        for channelId in state.channelIds {
            guard let session = await addSession(channelId: channelId) else { continue }
            let paneCount = sessions.count
            if let apiClient = appState.apiClient {
                let apiRef = apiClient
                let appRef = appState
                session.startTask = Task {
                    await session.start(using: apiRef, appState: appRef, paneCount: paneCount)
                }
            }
            restored += 1
        }
        return restored
    }
}
