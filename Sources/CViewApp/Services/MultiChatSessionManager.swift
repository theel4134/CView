// MARK: - MultiChatSessionManager.swift
// CViewApp - 멀티채팅 세션 관리 Actor
// 여러 채널의 채팅을 동시에 관리

import Foundation
import CViewCore
import CViewChat

/// 멀티채팅 세션을 관리하는 Actor
/// 채널당 1개의 ChatViewModel 인스턴스를 관리
@Observable
@MainActor
public final class MultiChatSessionManager {

    // MARK: - Types

    public struct ChatSession: Identifiable {
        public let id: String // channelId
        public let channelName: String
        public let chatViewModel: ChatViewModel

        public init(channelId: String, channelName: String, chatViewModel: ChatViewModel) {
            self.id = channelId
            self.channelName = channelName
            self.chatViewModel = chatViewModel
        }
    }

    // MARK: - State

    public var sessions: [ChatSession] = []
    public var selectedChannelId: String?

    public var selectedSession: ChatSession? {
        sessions.first { $0.id == selectedChannelId }
    }

    // MARK: - Session Management

    /// 새 채널 채팅 세션 추가
    public func addSession(
        channelId: String,
        channelName: String,
        chatChannelId: String,
        accessToken: String
    ) async {
        // 이미 존재하면 무시
        guard !sessions.contains(where: { $0.id == channelId }) else { return }

        let vm = ChatViewModel()
        await vm.connect(chatChannelId: chatChannelId, accessToken: accessToken)

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
        }
    }

    /// 모든 세션 해제
    public func disconnectAll() async {
        for session in sessions {
            await session.chatViewModel.disconnect()
        }
        sessions.removeAll()
        selectedChannelId = nil
    }

    /// 채널 선택
    public func selectChannel(_ channelId: String) {
        guard sessions.contains(where: { $0.id == channelId }) else { return }
        selectedChannelId = channelId
    }
}
