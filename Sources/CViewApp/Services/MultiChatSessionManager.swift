// MARK: - MultiChatSessionManager.swift
// CViewApp - 멀티채팅 세션 관리 Actor
// 여러 채널의 채팅을 동시에 관리

import Foundation
import CViewCore
import CViewChat
import CViewPersistence

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
        // 이미 존재하면 피드백
        guard !sessions.contains(where: { $0.id == channelId }) else {
            return .alreadyExists
        }

        // 세션 수 제한
        guard sessions.count < Self.maxSessions else {
            return .maxSessionsReached
        }

        let vm = ChatViewModel()
        vm.currentUserUid = uid
        vm.currentUserNickname = nickname

        // 이미 세션이 있으면 새 세션은 백그라운드 모드로 시작 (CPU/메모리 절약)
        if !sessions.isEmpty {
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

    /// 모든 세션 해제
    public func disconnectAll() async {
        for session in sessions {
            await session.chatViewModel.disconnect()
        }
        sessions.removeAll()
        selectedChannelId = nil
        persistSessions()
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

    /// 모든 세션 재연결
    public func reconnectAll() async {
        for session in sessions {
            await session.chatViewModel.reconnect()
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
        store.scheduleDebouncedSave()
    }

    /// 선택 채널만 저장 (빠른 업데이트)
    private func persistSelection() {
        guard let store = settingsStore else { return }
        store.multiChat.selectedChannelId = selectedChannelId
        store.scheduleDebouncedSave()
    }
}
