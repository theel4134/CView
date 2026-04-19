// MARK: - MultiChatSessionManager.swift
// CViewApp - 멀티채팅 세션 관리 Actor
// 여러 채널의 채팅을 동시에 관리

import Foundation
import CViewCore
import CViewChat
import CViewPersistence
import CViewNetworking

/// 멀티채팅 세션을 관리하는 Actor
/// 채널당 1개의 ChatViewModel 인스턴스를 관리
@Observable
@MainActor
public final class MultiChatSessionManager {

    // MARK: - Constants

    /// 최대 동시 세션 수
    public static let maxSessions = 8

    // MARK: - Types

    public struct ChatSession: Identifiable {
        public let id: String // channelId
        public let channelName: String
        public let chatViewModel: ChatViewModel
        public var unreadCount: Int = 0

        public init(channelId: String, channelName: String, chatViewModel: ChatViewModel) {
            self.id = channelId
            self.channelName = channelName
            self.chatViewModel = chatViewModel
        }
    }

    /// 세션 추가 결과
    public enum AddSessionResult: Sendable {
        case success
        case alreadyExists
        case maxSessionsReached
        case connectionFailed(String)
    }

    // MARK: - State

    public var sessions: [ChatSession] = []
    public var selectedChannelId: String?

    /// 그리드 레이아웃 분할 비율 (P2-4)
    public var gridHorizontalRatio: CGFloat = 0.5
    public var gridVerticalRatio: CGFloat = 0.5

    /// 세션 영속 저장용 SettingsStore 참조
    private var settingsStore: SettingsStore?

    /// P0-4: addSession 중복 진입 방지 가드 (channelId 단위)
    /// MainActor 격리이지만 await 경계에서 다른 호출이 끼어들 수 있어
    /// 동일 channelId의 중복 connect/append를 차단한다.
    private var inFlightChannelIds: Set<String> = []

    public var selectedSession: ChatSession? {
        sessions.first { $0.id == selectedChannelId }
    }

    public var canAddSession: Bool {
        sessions.count < Self.maxSessions
    }

    // MARK: - Configuration

    /// SettingsStore 연결 (세션 영속화 활성화)
    public func configure(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        // 저장된 그리드 비율 복원
        gridHorizontalRatio = settingsStore.multiChat.gridHorizontalRatio
        gridVerticalRatio = settingsStore.multiChat.gridVerticalRatio
    }

    /// 저장된 세션 목록 반환 (앱 시작 시 복원용)
    public var savedSessions: [SavedChatSession] {
        settingsStore?.multiChat.savedSessions ?? []
    }

    /// 마지막 선택된 채널 ID
    public var savedSelectedChannelId: String? {
        settingsStore?.multiChat.selectedChannelId
    }

    // MARK: - Session Management

    /// 새 채널 채팅 세션 추가
    @discardableResult
    public func addSession(
        channelId: String,
        channelName: String,
        chatChannelId: String,
        accessToken: String,
        extraToken: String? = nil,
        uid: String? = nil,
        nickname: String? = nil
    ) async -> AddSessionResult {
        // P0-4: 동일 channelId 중복 진입 차단 (await 경계 race 방지)
        guard !inFlightChannelIds.contains(channelId) else {
            return .alreadyExists
        }
        // 이미 존재하면 피드백
        guard !sessions.contains(where: { $0.id == channelId }) else {
            return .alreadyExists
        }

        // 세션 수 제한
        guard sessions.count < Self.maxSessions else {
            return .maxSessionsReached
        }

        inFlightChannelIds.insert(channelId)
        defer { inFlightChannelIds.remove(channelId) }

        let vm = ChatViewModel()
        vm.currentUserUid = uid
        vm.currentUserNickname = nickname

        // 이미 세션이 있으면 새 세션은 백그라운드 모드로 시작 (CPU/메모리 절약)
        let startAsBackground = !sessions.isEmpty
        if startAsBackground {
            vm.isBackgroundMode = true
            vm.messages.resize(to: 50)
        }

        await vm.connect(
            chatChannelId: chatChannelId,
            accessToken: accessToken,
            extraToken: extraToken,
            uid: uid,
            channelId: channelId
        )

        // [M-3] connect 이전에 isBackgroundMode를 세팅했으나 당시 chatEngine이 nil이었으므로
        // connect 완료 후 엔진에 재전파 (ping 주기 감쇄)
        if startAsBackground, let engine = vm.chatEngine {
            await engine.setBackgroundMode(true)
        }

        // connect await 동안 다른 경로로 동일 채널이 추가되었을 수 있음 — 최종 방어
        if sessions.contains(where: { $0.id == channelId }) {
            await vm.disconnect()
            return .alreadyExists
        }

        let session = ChatSession(
            channelId: channelId,
            channelName: channelName,
            chatViewModel: vm
        )
        sessions.append(session)

        // 첫 세션이면 자동 선택
        if selectedChannelId == nil {
            selectedChannelId = channelId
        }

        persistSessions()
        return .success
    }

    /// 세션 제거
    public func removeSession(channelId: String) async {
        if let index = sessions.firstIndex(where: { $0.id == channelId }) {
            await sessions[index].chatViewModel.disconnect()
            sessions.remove(at: index)

            // 선택된 채널이 제거되면 다른 채널 선택
            if selectedChannelId == channelId {
                selectedChannelId = sessions.first?.id
            }

            persistSessions()
        }
    }

    /// 모든 세션 해제 — TaskGroup으로 병렬 처리 (각 WebSocket close는 독립적)
    public func disconnectAll() async {
        let viewModels = sessions.map(\.chatViewModel)
        await withTaskGroup(of: Void.self) { group in
            for vm in viewModels {
                group.addTask { await vm.disconnect() }
            }
        }
        sessions.removeAll()
        selectedChannelId = nil
        persistSessions()
    }

    /// 사용자 정보 업데이트 (로그인/로그아웃/프로필 로드 시)
    /// 기존 모든 세션의 ChatViewModel에 새 uid/nickname을 전파하여
    /// 채팅 입력 활성화(canSendChat) 상태가 즉시 갱신되도록 한다.
    public func updateUserInfo(uid: String?, nickname: String?) {
        for session in sessions {
            session.chatViewModel.currentUserUid = uid
            session.chatViewModel.currentUserNickname = nickname
        }
    }

    /// 채널 선택
    public func selectChannel(_ channelId: String) {
        guard sessions.contains(where: { $0.id == channelId }) else { return }

        // 이전 활성 세션 → 백그라운드 모드 (버퍼 축소 + flush 간격 증가)
        if let oldId = selectedChannelId, oldId != channelId,
           let oldIndex = sessions.firstIndex(where: { $0.id == oldId }) {
            sessions[oldIndex].chatViewModel.isBackgroundMode = true
            sessions[oldIndex].chatViewModel.messages.resize(to: 50)
        }

        selectedChannelId = channelId

        // 새 활성 세션 → 포그라운드 모드 복원
        if let index = sessions.firstIndex(where: { $0.id == channelId }) {
            sessions[index].chatViewModel.isBackgroundMode = false
            sessions[index].chatViewModel.messages.resize(to: 200)
            sessions[index].unreadCount = 0
        }
        persistSelection()
    }

    /// 모든 세션 재연결 — TaskGroup으로 병렬 시도 (각 세션의 재연결은 독립적)
    public func reconnectAll() async {
        let viewModels = sessions.map(\.chatViewModel)
        await withTaskGroup(of: Void.self) { group in
            for vm in viewModels {
                group.addTask { await vm.reconnect() }
            }
        }
    }

    /// 세션 순서 변경 (드래그앤드롭)
    public func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        persistSessions()
    }

    // MARK: - Persistence

    /// 세션 목록을 SettingsStore에 저장
    private func persistSessions() {
        guard let store = settingsStore else { return }
        store.multiChat.savedSessions = sessions.map {
            SavedChatSession(channelId: $0.id, channelName: $0.channelName)
        }
        store.multiChat.selectedChannelId = selectedChannelId
        store.multiChat.gridHorizontalRatio = gridHorizontalRatio
        store.multiChat.gridVerticalRatio = gridVerticalRatio
        store.scheduleDebouncedSave()
    }

    /// 선택 채널만 저장 (빠른 업데이트)
    private func persistSelection() {
        guard let store = settingsStore else { return }
        store.multiChat.selectedChannelId = selectedChannelId
        store.scheduleDebouncedSave()
    }

    /// 그리드 비율 변경 시 영속 저장
    public func persistGridRatio() {
        guard let store = settingsStore else { return }
        store.multiChat.gridHorizontalRatio = gridHorizontalRatio
        store.multiChat.gridVerticalRatio = gridVerticalRatio
        store.scheduleDebouncedSave()
    }

    /// 모든 세션을 포그라운드/백그라운드 모드로 일괄 전환
    /// MergedChatView 진입 시 foreground=true로 호출하여 3초 flush 지연을 해소
    public func setAllSessionsForeground(_ foreground: Bool) {
        for session in sessions {
            session.chatViewModel.isBackgroundMode = !foreground
            session.chatViewModel.messages.resize(to: foreground ? 200 : 50)
        }
    }

    /// 저장된 세션 복원 결과 요약 (P1-3)
    /// - restored: 성공적으로 복원된 세션 수
    /// - skippedOffline: 오프라인(방송 미진행)으로 건너뛴 채널명
    /// - failed: 네트워크/토큰 오류 등으로 실패한 (채널명, 사유) 페어
    public struct RestoreSummary: Sendable {
        public let restored: Int
        public let skippedOffline: [String]
        public let failed: [(name: String, reason: String)]
        public var anyRestored: Bool { restored > 0 }
        public var hasIssues: Bool { !skippedOffline.isEmpty || !failed.isEmpty }
        public var total: Int { restored + skippedOffline.count + failed.count }
    }

    /// 저장된 세션 복원 (앱 시작 시 호출)
    /// - Returns: 복원 결과 요약 (실패/스킵 사유 포함)
    @discardableResult
    public func restoreSessions(
        apiClient: ChzzkAPIClient,
        uid: String?,
        nickname: String?
    ) async -> RestoreSummary {
        let saved = savedSessions
        guard !saved.isEmpty else {
            return RestoreSummary(restored: 0, skippedOffline: [], failed: [])
        }

        var restored = 0
        var skippedOffline: [String] = []
        var failed: [(name: String, reason: String)] = []
        let lastSelected = savedSelectedChannelId

        // [M-5] liveDetail + chatAccessToken 조회를 병렬화 — 순차 호출 대비 N배 빠름 (8채널 기준).
        // addSession 자체는 MainActor 직렬성 유지를 위해 이후 순차 실행.
        struct PrefetchResult: Sendable {
            let savedChannelId: String
            let savedChannelName: String
            let outcome: Outcome
            enum Outcome: Sendable {
                case ready(chatChannelId: String, accessToken: String, extraToken: String?, channelName: String)
                case offline
                case error(String)
            }
        }

        let prefetched: [PrefetchResult] = await withTaskGroup(of: PrefetchResult.self) { group in
            for session in saved {
                group.addTask {
                    do {
                        let liveDetail = try await apiClient.liveDetail(channelId: session.channelId)
                        guard let chatChannelId = liveDetail.chatChannelId else {
                            return PrefetchResult(savedChannelId: session.channelId, savedChannelName: session.channelName, outcome: .offline)
                        }
                        let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
                        let channelName = liveDetail.channel?.channelName ?? session.channelName
                        return PrefetchResult(
                            savedChannelId: session.channelId,
                            savedChannelName: session.channelName,
                            outcome: .ready(
                                chatChannelId: chatChannelId,
                                accessToken: tokenInfo.accessToken,
                                extraToken: tokenInfo.extraToken,
                                channelName: channelName
                            )
                        )
                    } catch {
                        return PrefetchResult(
                            savedChannelId: session.channelId,
                            savedChannelName: session.channelName,
                            outcome: .error(error.localizedDescription)
                        )
                    }
                }
            }
            // 저장 순서 보존을 위해 savedChannelId 인덱스로 정렬
            var byId: [String: PrefetchResult] = [:]
            for await result in group { byId[result.savedChannelId] = result }
            return saved.compactMap { byId[$0.channelId] }
        }

        for result in prefetched {
            switch result.outcome {
            case .offline:
                skippedOffline.append(result.savedChannelName)
            case .error(let msg):
                failed.append((name: result.savedChannelName, reason: msg))
            case .ready(let chatChannelId, let accessToken, let extraToken, let channelName):
                let addResult = await addSession(
                    channelId: result.savedChannelId,
                    channelName: channelName,
                    chatChannelId: chatChannelId,
                    accessToken: accessToken,
                    extraToken: extraToken,
                    uid: uid,
                    nickname: nickname
                )
                switch addResult {
                case .success:
                    restored += 1
                case .alreadyExists:
                    break
                case .maxSessionsReached:
                    failed.append((name: channelName, reason: "최대 세션 수 초과"))
                case .connectionFailed(let msg):
                    failed.append((name: channelName, reason: msg))
                }
            }
        }

        if let lastSelected, sessions.contains(where: { $0.id == lastSelected }) {
            selectChannel(lastSelected)
        }

        return RestoreSummary(restored: restored, skippedOffline: skippedOffline, failed: failed)
    }
}
