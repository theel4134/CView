// MARK: - MultiLiveManager.swift
// CViewApp — 통합 엔진 풀 기반 멀티라이브 세션 매니저
// 최대 4개 채널 동시 시청, 각 세션은 독립 PlayerViewModel(VLC/AVPlayer) + ChatViewModel

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking
import CViewPlayer
import CViewPersistence
import CViewMonitoring

// MARK: - Multi Live Manager

@Observable
@MainActor
public final class MultiLiveManager {

    // MARK: - Constants

    static let maxSessions = 4

    /// 설정 기반 최대 세션 수
    var effectiveMaxSessions: Int {
        settingsStore?.multiLive.maxConcurrentSessions ?? Self.maxSessions
    }

    // MARK: - State

    var sessions: [MultiLiveSession] = []
    var selectedSessionId: UUID?
    var isGridLayout: Bool = false

    // MARK: - 그리드/오디오 확장 상태 (MultiLiveSessionManager 병합)
    var gridLayoutMode: MultiLiveGridLayoutMode = .preset
    var layoutRatios: MultiLiveLayoutRatios = MultiLiveLayoutRatios()
    var draggingSessionIndex: Int? = nil
    var audioSessionId: UUID?
    var isMultiAudioMode: Bool = false
    var audioEnabledSessionIds: Set<UUID> = []

    /// 현재 추가 중인 채널 ID 세트 (중복 추가 방지)
    private var addingChannelIds: Set<String> = []

    /// 통합 엔진 풀 (VLC + AVPlayer)
    let enginePool = MultiLiveEnginePool(maxPoolSize: maxSessions)

    /// 선택된 세션
    var selectedSession: MultiLiveSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    /// 오디오 활성 세션
    var audioSession: MultiLiveSession? {
        guard let id = audioSessionId else { return selectedSession }
        return sessions.first { $0.id == id }
    }

    /// 활성(재생 중) 세션 수
    var activeSessionCount: Int {
        sessions.filter { if case .playing = $0.loadState { return true } else { return false } }.count
    }

    /// 세션 추가 가능 여부
    var canAddSession: Bool {
        sessions.count < effectiveMaxSessions
    }

    // MARK: - 의존성

    private weak var apiClient: ChzzkAPIClient?
    private weak var settingsStore: SettingsStore?
    private let logger = AppLogger.player

    /// 메트릭 전송 포워더 (AppState에서 주입)
    var metricsForwarder: MetricsForwarder?

    /// 로그인 사용자 정보 (세션 채팅 전송용)
    private var userUid: String?
    private var userNickname: String?

    /// 캐시된 기본 이모티콘 (AppState에서 주입)
    private var cachedBasicEmoticonMap: [String: String] = [:]
    private var cachedBasicEmoticonPacks: [EmoticonPack] = []

    // MARK: - Init

    init() {}

    /// API 클라이언트 + 사용자 정보 설정 (AppState에서 지연 주입)
    func configure(apiClient: ChzzkAPIClient?, settingsStore: SettingsStore? = nil, userUid: String? = nil, userNickname: String? = nil, metricsForwarder: MetricsForwarder? = nil) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.userUid = userUid
        self.userNickname = userNickname
        self.metricsForwarder = metricsForwarder
    }

    /// 캐시된 기본 이모티콘 업데이트 (프리로드 완료 후 호출)
    func updateCachedEmoticons(map: [String: String], packs: [EmoticonPack]) {
        self.cachedBasicEmoticonMap = map
        self.cachedBasicEmoticonPacks = packs
    }

    /// 사용자 정보 업데이트 (로그인/로그아웃 시)
    func updateUserInfo(uid: String?, nickname: String?) {
        self.userUid = uid
        self.userNickname = nickname
        // 기존 세션의 chatViewModel에도 반영
        for session in sessions {
            session.chatViewModel.currentUserUid = uid
            session.chatViewModel.currentUserNickname = nickname
        }
    }

    // MARK: - 세션 관리

    /// 채널 ID로 새 세션 추가 (엔진 풀에서 엔진 할당)
    func addSession(channelId: String, preferredEngine: PlayerEngineType = .vlc, startImmediately: Bool = true) async {
        let maxSessions = effectiveMaxSessions
        guard canAddSession else {
            logger.warning("MultiLive: 최대 세션 수(\(maxSessions)) 도달")
            return
        }
        guard !sessions.contains(where: { $0.channelId == channelId }) else {
            logger.info("MultiLive: 이미 존재하는 채널 \(channelId)")
            return
        }
        guard !addingChannelIds.contains(channelId) else { return }
        addingChannelIds.insert(channelId)
        defer { addingChannelIds.remove(channelId) }

        guard let apiClient else {
            logger.error("MultiLive: API 클라이언트 없음")
            return
        }

        // 첫 세션 시 warmup
        if sessions.isEmpty {
            await enginePool.warmup(count: 2, type: preferredEngine)
        }

        // 엔진 풀에서 엔진 획득
        guard let engine = await enginePool.acquire(type: preferredEngine) else {
            logger.error("MultiLive: 엔진 풀 할당 실패")
            return
        }

        do {
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)

            // ISSUE-4 fix: await 이후 세션 수 재확인
            guard sessions.count < maxSessions else {
                logger.warning("MultiLive: await 이후 최대 세션 수 도달 — 추가 취소")
                await enginePool.release(engine)
                return
            }
            // ISSUE-4 fix: await 이후 동일 채널 재확인
            guard !sessions.contains(where: { $0.channelId == channelId }) else {
                logger.info("MultiLive: await 이후 중복 채널 감지 — 추가 취소 (\(channelId))")
                await enginePool.release(engine)
                return
            }

            let channelName = liveInfo.channel?.channelName ?? channelId
            let profileImageURL = liveInfo.channel?.channelImageURL

            let session = MultiLiveSession(
                channelId: channelId,
                channelName: channelName,
                profileImageURL: profileImageURL,
                liveInfo: liveInfo,
                apiClient: apiClient,
                userUid: userUid,
                userNickname: userNickname,
                cachedBasicEmoticonMap: cachedBasicEmoticonMap,
                cachedBasicEmoticonPacks: cachedBasicEmoticonPacks,
                engineType: preferredEngine,
                engine: engine
            )
            session.metricsForwarder = metricsForwarder
            sessions.append(session)

            // 첫 세션이면 자동 선택 + 오디오 활성화
            if sessions.count == 1 {
                selectedSessionId = session.id
            } else {
                // 추가 세션은 음소거 + 백그라운드 모드로 시작
                session.playerViewModel.toggleMute()
                session.chatViewModel.isBackgroundMode = true
                session.playerViewModel.setBackgroundMode(true)
                // [P0: 적응형 해상도] 비선택 세션은 720p로 시작
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = false
                }
            }

            // 멀티라이브 제약 조건 적용
            let paneCount = sessions.count
            for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: paneCount) }

            // [그리드 drawable 복구] 세션 추가로 그리드 레이아웃이 변경되면
            // 기존 세션의 PlayerVideoView가 새 PlayerContainerView에 재마운트된다.
            // SwiftUI 레이아웃 안정화 후 기존 세션의 VLC drawable을 재바인딩하여
            // Metal 렌더링 서피스가 올바른 레이어에 연결되도록 보장.
            if sessions.count >= 2 {
                let existingSessions = Array(sessions.dropLast())
                Task { @MainActor in
                    // SwiftUI 레이아웃 안정화 후 drawable 재바인딩
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    for s in existingSessions {
                        if let vlc = s.playerViewModel.playerEngine as? VLCPlayerEngine {
                            vlc.refreshDrawable()
                        }
                    }
                }
            }

            // 스트림 시작 (비동기) — restoreState에서는 startImmediately=false로
            // 모든 세션 추가 후 레이아웃 안정화 뒤 일괄 시작
            if startImmediately {
                Task {
                    await session.start()
                }
            }

            saveState()
            logger.info("MultiLive: 세션 추가 — \(channelName) (\(channelId)) [\(preferredEngine.rawValue)]")
        } catch {
            // API 실패 시 엔진 풀에 반환
            await enginePool.release(engine)
            logger.error("MultiLive: 세션 추가 실패 — \(error.localizedDescription)")
        }
    }

    /// 세션 제거 — 엔진 풀 반환 포함
    func removeSession(id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]

        // ⚠️ 세션 정지 후 엔진 분리 → 풀 반납 (순서 중요)
        await session.stop()
        if let engine = session.playerViewModel.detachEngine() {
            await enginePool.release(engine)
        }
        sessions.remove(at: index)

        // 선택 세션이 제거되면 다른 세션 선택
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
            if let newSelected = selectedSession {
                if newSelected.playerViewModel.isMuted {
                    newSelected.playerViewModel.toggleMute()
                }
                newSelected.playerViewModel.setBackgroundMode(false)
                newSelected.chatViewModel.isBackgroundMode = false
                newSelected.playerViewModel.recoverFromBackground()
            }
        }

        if audioSessionId == id {
            audioSessionId = sessions.first?.id
            if let newId = audioSessionId {
                for s in sessions { s.setMuted(s.id != newId) }
            }
        }
        audioEnabledSessionIds.remove(id)

        if sessions.count <= 1 { isGridLayout = false }

        let remaining = sessions.count
        for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: remaining) }

        // [그리드 drawable 복구] 세션 제거로 그리드 레이아웃이 변경되면
        // SwiftUI가 남은 세션의 PlayerVideoView를 새 PlayerContainerView에 재마운트.
        // VLC Metal 렌더링 서피스가 끊어지므로 drawable 재바인딩 필요.
        if !sessions.isEmpty {
            let remainingSessions = Array(sessions)
            Task { @MainActor in
                // SwiftUI 레이아웃 안정화 후 drawable 재바인딩
                try? await Task.sleep(nanoseconds: 500_000_000)
                for s in remainingSessions {
                    if let vlc = s.playerViewModel.playerEngine as? VLCPlayerEngine {
                        vlc.refreshDrawable()
                    }
                }
            }
        }

        saveState()
        logger.info("MultiLive: 세션 제거 — \(session.channelName)")
    }

    /// 세션 선택 (탭 전환)
    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        let previousId = selectedSessionId
        selectedSessionId = id

        // 오디오 라우팅 + CPU 최적화: 이전 세션 → 백그라운드, 새 세션 → 포그라운드
        if previousId != id {
            if let prev = sessions.first(where: { $0.id == previousId }) {
                if !isMultiAudioMode {
                    if !prev.playerViewModel.isMuted {
                        prev.playerViewModel.toggleMute()
                    }
                }
                prev.chatViewModel.isBackgroundMode = true
                prev.playerViewModel.setBackgroundMode(true)
                // [P0: 적응형 해상도] 비선택 세션 → 720p 다운그레이드
                if let vlc = prev.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = false
                }
            }
            if let current = sessions.first(where: { $0.id == id }) {
                if !isMultiAudioMode {
                    if current.playerViewModel.isMuted {
                        current.playerViewModel.toggleMute()
                    }
                }
                current.chatViewModel.isBackgroundMode = false
                current.playerViewModel.setBackgroundMode(false)
                current.playerViewModel.recoverFromBackground()
                // [P0: 적응형 해상도] 선택된 세션 → 1080p 업그레이드
                if let vlc = current.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = true
                }
                // 메트릭 포워더: 선택된 세션으로 채널 전환
                if let forwarder = metricsForwarder {
                    let chId = current.channelId
                    let chName = current.channelName
                    Task { await forwarder.activateChannel(channelId: chId, channelName: chName) }
                }
            }
        }
        saveState()
    }

    /// 모든 세션 종료 (엔진 풀 반환 포함)
    func removeAllSessions() async {
        for session in sessions {
            await session.stop()
            if let engine = session.playerViewModel.detachEngine() {
                await enginePool.release(engine)
            }
        }
        sessions.removeAll()
        selectedSessionId = nil
    }

    /// 활성 스트림 존재 여부 (App Nap 방지용)
    func hasActiveStreams() -> Bool {
        sessions.contains { if case .playing = $0.loadState { return true } else { return false } }
    }

    // MARK: - 세션 선택/제거 편의 메서드 (뷰에서 session 객체로 호출)

    /// 세션 선택 (탭 전환) — session 객체로 호출
    func select(_ session: MultiLiveSession) {
        selectSession(id: session.id)
    }

    /// 세션 제거 — session 객체로 호출
    func removeSession(_ session: MultiLiveSession) async {
        await removeSession(id: session.id)
    }

    // MARK: - 오디오 라우팅

    func routeAudio(to session: MultiLiveSession) {
        guard audioSessionId != session.id else { return }
        audioSessionId = session.id
        for s in sessions { s.setMuted(s.id != session.id) }
    }

    func toggleMultiAudioMode() {
        isMultiAudioMode.toggle()
        if isMultiAudioMode {
            audioEnabledSessionIds.removeAll()
            if let currentAudioId = audioSessionId ?? selectedSessionId {
                audioEnabledSessionIds.insert(currentAudioId)
            }
            for s in sessions {
                s.setMuted(!audioEnabledSessionIds.contains(s.id))
            }
        } else {
            audioEnabledSessionIds.removeAll()
            let activeId = audioSessionId ?? selectedSessionId
            for s in sessions {
                s.setMuted(s.id != activeId)
            }
        }
    }

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

    func isAudioEnabled(for session: MultiLiveSession) -> Bool {
        if isMultiAudioMode {
            return audioEnabledSessionIds.contains(session.id)
        } else {
            return (audioSessionId ?? selectedSessionId) == session.id
        }
    }

    // MARK: - 그리드 관리

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
        // 순차 해제 (동시 해제 시 VLC 데드락 위험)
        for s in sessions {
            await s.stop()
            if let engine = s.playerViewModel.detachEngine() {
                await enginePool.release(engine)
            }
        }
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

    func saveState() {
        guard !sessions.isEmpty else {
            MultiLivePersistedState.clear()
            return
        }
        let state = MultiLivePersistedState(from: self)
        state.save()
    }

    func saveLayoutChange() {
        saveState()
    }

    @discardableResult
    func restoreState(appState: AppState) async -> Int {
        guard sessions.isEmpty else { return 0 }
        guard let state = MultiLivePersistedState.load() else { return 0 }
        guard !state.channelIds.isEmpty else { return 0 }

        isGridLayout = state.isGridLayout
        gridLayoutMode = state.parsedGridLayoutMode
        layoutRatios.horizontalRatio = CGFloat(state.horizontalRatio)
        layoutRatios.verticalRatio = CGFloat(state.verticalRatio)

        let engine = appState.settingsStore.player.preferredEngine
        var restoredCount = 0

        // Phase 1: 모든 세션을 추가 (스트림 시작 없이)
        // 각 추가 시 SwiftUI가 그리드 레이아웃을 변경하지만, VLC가 아직 재생 전이므로
        // drawable 바인딩 문제가 발생하지 않는다.
        for channelId in state.channelIds {
            await addSession(channelId: channelId, preferredEngine: engine, startImmediately: false)
            restoredCount += 1
        }

        guard restoredCount > 0 else { return 0 }

        // Phase 2: SwiftUI 레이아웃 안정화 대기
        // 모든 PlayerContainerView가 최종 그리드 위치에 마운트될 시간 확보.
        // MainActor yield 2회 + 300ms 대기로 SwiftUI 렌더 사이클 완료 보장.
        await MainActor.run { /* yield to allow SwiftUI layout pass */ }
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Phase 3: 모든 세션 스트림 시작 (레이아웃 안정 후)
        // 각 VLC 인스턴스가 안정된 뷰 계층에서 play()를 호출하여
        // Metal 렌더링 서피스가 올바른 레이어에 생성된다.
        // Phase 3: 세션 순차 시작 (staggered start)
        // 4개 세션을 동시에 시작하면 CDN 연결 경합 + VLC 내부 리소스 경쟁으로
        // 초기 HLS 세그먼트 다운로드가 지연되어 VLC가 stopping 상태로 전환될 수 있음.
        // 선택된(포그라운드) 세션을 먼저 시작하고, 나머지를 500ms 간격으로 순차 시작.
        let sessionsToStart = Array(sessions)
        let selectedFirst = sessionsToStart.sorted { a, b in
            // 선택된 세션을 첫 번째로
            (a.id == selectedSessionId ? 0 : 1) < (b.id == selectedSessionId ? 0 : 1)
        }
        for (index, session) in selectedFirst.enumerated() {
            if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                vlc.isSelectedSession = (session.id == selectedSessionId)
            }
            await session.start()
            // 첫 세션 이후 500ms 대기로 CDN 연결 안정화
            if index < selectedFirst.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        // [세션 복원 그리드 복구] 세션 시작 후 SwiftUI 레이아웃 안정화 뒤
        // drawable 재바인딩으로 Metal 렌더링 서피스를 올바른 레이어에 연결.
        // forceVoutRecovery(트랙 순환)는 VLC를 paused 상태로 만들어 재생 실패를 유발하므로
        // refreshDrawable만 사용한다.
        if sessionsToStart.count >= 2 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                for s in sessionsToStart {
                    if let vlc = s.playerViewModel.playerEngine as? VLCPlayerEngine {
                        vlc.refreshDrawable()
                    }
                }
            }
        }

        return restoredCount
    }
}
