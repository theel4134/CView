// MARK: - MultiLiveSession.swift
// 멀티 라이브 — 탭 하나에 해당하는 플레이어+채팅 세션

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking

// MARK: - Session State

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

    // MARK: Channel Info
    var channelId: String
    var channelName: String = ""
    var liveTitle: String = ""
    var thumbnailURL: URL?
    var viewerCount: Int = 0
    var isOffline: Bool = false

    // MARK: ViewModels (독립 인스턴스)
    let playerViewModel: PlayerViewModel
    let chatViewModel: ChatViewModel

    // MARK: UI State
    var loadState: MultiLiveLoadState = .idle
    var isChatVisible: Bool = true
    var showDebug: Bool = false
    /// playerViewModel.isMuted를 단일 소스로 사용하는 computed property
    var isMuted: Bool { playerViewModel.isMuted }

    // MARK: Tasks
    var pollTask: Task<Void, Never>?
    /// CDN 세션 토큰 만료 대비 주기적 스트림 URL 갱신 태스크 (55분 주기)
    private var refreshTask: Task<Void, Never>?
    private(set) var isBackground: Bool = false

    // MARK: - Init

    public init(channelId: String) {
        self.id = UUID()
        self.channelId = channelId
        // 엔진 타입은 start() 시점에 settingsStore에서 주입.
        // 싱글라이브와 동일하게 startStream() 직전에 엔진을 결정하므로
        // 설정 변경이 항상 올바르게 반영됨.
        self.playerViewModel = PlayerViewModel(engineType: .vlc)
        self.chatViewModel = ChatViewModel()
    }

    // MARK: - Stream Start

    /// 스트림 + 채팅 연결
    /// - Parameter paneCount: 현재 활성 세션 수. AVPlayer의 해상도·비트레이트 상한을 세션 수에 맞게 조정한다.
    func start(using apiClient: ChzzkAPIClient, appState: AppState, paneCount: Int = 1) async {
        guard loadState != .loading else { return }
        loadState = .loading

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

            guard let mediaPath = media?.path,
                  let streamURL = URL(string: mediaPath) else {
                loadState = .error("HLS 스트림 URL을 찾을 수 없습니다.")
                return
            }

            channelName  = liveInfo.channel?.channelName ?? channelId
            liveTitle    = liveInfo.liveTitle ?? ""
            thumbnailURL = liveInfo.liveImageURL

            let ps = appState.settingsStore.player
            // 최신 설정 엔진 타입 적용 (싱글라이브와 동일한 패턴)
            playerViewModel.preferredEngineType = ps.preferredEngine
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
            // 세션 수에 따라 AVPlayer 디코딩 해상도·비트레이트를 제한해 GPU 부하 분산
            playerViewModel.applyMultiLiveConstraints(paneCount: paneCount)

            // ─── 영상 즉시 표시: 채팅 준비와 관계없이 로딩 오버레이 제거 ───
            loadState = .playing(channelName: channelName, liveTitle: liveTitle)
            startPolling(apiClient: apiClient, appState: appState)

            // ─── 채팅 준비: 백그라운드에서 병렬 로드 (영상과 동시 진행) ───
            if let chatChannelId = liveInfo.chatChannelId {
                let _channelId = channelId
                let chatVM = chatViewModel
                Task { [isLoggedIn = appState.isLoggedIn, fallbackUid = appState.userChannelId] in
                    do {
                        let tokenTask = Task { try await apiClient.chatAccessToken(chatChannelId: chatChannelId) }
                        let userTask  = Task<UserStatusInfo?, Never> {
                            guard isLoggedIn else { return nil }
                            return try? await apiClient.userStatus()
                        }
                        let packsTask = Task { await apiClient.basicEmoticonPacks(channelId: _channelId) }

                        let tokenInfo = try await tokenTask.value
                        let userInfo  = await userTask.value
                        let packs     = await packsTask.value
                        let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(packs)

                        await MainActor.run {
                            chatVM.channelEmoticons = emoMap
                            chatVM.emoticonPacks = loadedPacks
                        }

                        let uid: String? = userInfo?.userIdHash ?? (isLoggedIn ? fallbackUid : nil)
                        if let uid { await MainActor.run { chatVM.currentUserUid = uid } }
                        await MainActor.run { chatVM.currentUserNickname = userInfo?.nickname }

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

    /// 스트림 + 채팅 종료
    func stop() async {
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        await playerViewModel.stopStream()
        await chatViewModel.disconnect()
        loadState = .idle
    }

    /// 오프라인 이후 다시 연결 시도
    func retry(using apiClient: ChzzkAPIClient, appState: AppState) async {
        loadState = .idle
        isOffline = false
        await start(using: apiClient, appState: appState)
    }

    /// 배경/포그라운드 모드 전환 (VLC 프로파일 + 볼륨)
    func setBackgroundMode(_ background: Bool) {
        guard isBackground != background else { return }
        isBackground = background
        playerViewModel.setBackgroundMode(background)
    }

    /// 음소거 토글 (배경 탭 자동 관리)
    func setMuted(_ muted: Bool) {
        playerViewModel.isMuted = muted
        playerViewModel.setVolume(muted ? 0 : playerViewModel.volume)
    }

    // MARK: - Polling

    private func startPolling(apiClient: ChzzkAPIClient, appState: AppState) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var consecutiveVLCErrors = 0

            while !Task.isCancelled {
                // 배경 탭은 60초, 포그라운드는 30초 폴링
                let interval: Duration = self.isBackground ? .seconds(60) : .seconds(30)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }

                // ── 1. 방송 상태 폴링 ───────────────────────────────────────
                do {
                    let status = try await apiClient.liveStatus(channelId: self.channelId)
                    await MainActor.run {
                        self.viewerCount = status.concurrentUserCount
                        if status.status == .close {
                            if !self.isOffline {
                                self.isOffline = true
                                self.loadState = .offline
                                // 오프라인 감지 시 2분 후 자동 재시도
                                Task { [weak self] in
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

                // ── 2. VLC 엔진 헬스 체크 (오프라인 아닐 때만) ─────────────
                // VLC가 ERROR 상태를 2회 연속 유지하면 스트림 URL을 재취득하여 수정재시도
                let isCurrentlyOffline = self.isOffline
                guard !isCurrentlyOffline else { consecutiveVLCErrors = 0; continue }

                let vlcState = await MainActor.run {
                    self.playerViewModel.mediaPlayer?.mediaPlayer.state
                }
                if vlcState == .some(.error) {
                    consecutiveVLCErrors += 1
                    Log.player.warning("멀티라이브 VLC ERROR 감지 (\(consecutiveVLCErrors)연속) channelId=\(self.channelId, privacy: .public)")
                    if consecutiveVLCErrors >= 2 {
                        consecutiveVLCErrors = 0
                        Log.player.warning("⚠️ VLC ERROR 지속 → URL 재취득 후 재시작")
                        await self.retry(using: apiClient, appState: appState)
                    }
                } else {
                    consecutiveVLCErrors = 0
                }
            }
        }

        // ── 3. 주기적 스트림 URL 갱신 (CDN 토큰 만료 대비) ────────────
        scheduleProactiveRefresh(apiClient: apiClient, appState: appState)
    }

    /// CDN 세션 토큰 만료에 대비해 55분마다 스트림 URL을 강제 재취득합니다.
    /// Chzzk HLS URL에는 90~120분에 만료되는 세션 토큰이 포함되어 있습니다.
    private func scheduleProactiveRefresh(apiClient: ChzzkAPIClient, appState: AppState) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            // 55분 대기 후 최초 갱신 (실제 토큰 만료(90-120분)보다 원시 예방적 갱신)
            try? await Task.sleep(for: .seconds(55 * 60))
            while !Task.isCancelled {
                // 오프라인 중에는 대기야 함 (방송 재개를 기다려야 하는데 재실행해서는 안 됨)
                if self.isOffline {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }
                Log.player.info("플레이어 주기적 URL 재취득 — CDN 토큰 만료 예방 channelId=\(self.channelId, privacy: .public)")
                // engineRetries 리셋: URL 재취득 후에는 새 기회를 주어야 함
                await MainActor.run {
                    self.playerViewModel.mediaPlayer?.resetRetries()
                }
                // retry()는 liveDetail을 재취득하고 VLC를 새 URL로 재시작
                await self.retry(using: apiClient, appState: appState)
                // 다음 갱신은 55분 후
                try? await Task.sleep(for: .seconds(55 * 60))
            }
        }
    }
}

// MARK: - MultiLiveSessionManager

/// 멀티 라이브 세션 집합 관리
@Observable
@MainActor
final class MultiLiveSessionManager {

    public static let maxSessions = 4

    var sessions: [MultiLiveSession] = []
    var selectedSessionId: UUID?

    /// 그리드 레이아웃 활성화 여부 (뷰 재생성 시 초기화 방지를 위해 Manager에서 관리)
    var isGridLayout: Bool = false

    /// 그리드 모드에서 오디오가 활성화된 세션 ID
    /// nil이면 selectedSession의 오디오가 활성 (탭 모드 기본 동작)
    var audioSessionId: UUID?

    var selectedSession: MultiLiveSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    var audioSession: MultiLiveSession? {
        guard let id = audioSessionId else { return selectedSession }
        return sessions.first { $0.id == id }
    }

    // MARK: - CRUD

    func addSession(channelId: String) -> MultiLiveSession? {
        guard sessions.count < Self.maxSessions else { return nil }
        // 중복 채널 방지
        if sessions.contains(where: { $0.channelId == channelId }) { return nil }
        let session = MultiLiveSession(channelId: channelId)
        sessions.append(session)
        selectedSessionId = session.id
        return session
    }

    func removeSession(_ session: MultiLiveSession) async {
        await session.stop()
        sessions.removeAll { $0.id == session.id }
        if selectedSessionId == session.id {
            selectedSessionId = sessions.last?.id
        }
        // 오디오 활성 세션이 제거된 경우: 남은 첫 세션으로 자동 라우팅
        if audioSessionId == session.id {
            audioSessionId = sessions.first?.id
            // 새 오디오 세션 언뮤트, 나머지 뮤트
            if let newAudioId = audioSessionId {
                for s in sessions { s.setMuted(s.id != newAudioId) }
            }
        }
        // 1개 이하 남으면 그리드 모드 자동 해제
        if sessions.count <= 1 {
            isGridLayout = false
        }
        // 세션 제거 후 남은 세션들의 AVPlayer 품질 제한을 새 pane 수에 맞게 갱신
        let remaining = sessions.count
        for s in sessions {
            s.playerViewModel.applyMultiLiveConstraints(paneCount: remaining)
        }
    }

    func select(_ session: MultiLiveSession) {
        guard selectedSessionId != session.id else { return }

        // 현재 선택된 탭 배경으로
        if let current = selectedSession, current.id != session.id {
            current.setBackgroundMode(true)
        }

        selectedSessionId = session.id

        // 새 탭 포그라운드로
        session.setBackgroundMode(false)

        // 탭 모드에서는 audioSessionId를 nil로 리셋 (선택된 탭이 오디오)
        audioSessionId = nil
    }

    /// 그리드 모드에서 특정 세션으로 오디오 라우팅
    /// - 지정 세션만 언뮤트, 나머지 모두 뮤트
    func routeAudio(to session: MultiLiveSession) {
        guard audioSessionId != session.id else { return }
        audioSessionId = session.id
        for s in sessions {
            s.setMuted(s.id != session.id)
        }
    }

    /// 탭 순서 변경 (드래그-리오더)
    func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
    }

    /// 세션을 앞/뒤로 한 칸씩 이동
    func moveSessionLeft(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx > 0 else { return }
        sessions.swapAt(idx, idx - 1)
    }

    func moveSessionRight(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx < sessions.count - 1 else { return }
        sessions.swapAt(idx, idx + 1)
    }

    /// 모든 세션 종료
    func stopAll() async {
        for s in sessions { await s.stop() }
        sessions.removeAll()
        selectedSessionId = nil
        audioSessionId = nil
        isGridLayout = false
    }
}
