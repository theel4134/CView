// MARK: - MultiLiveManager.swift
// CViewApp — AVPlayer 기반 멀티라이브 세션 매니저
// 최대 4개 채널 동시 시청, 각 세션은 독립 PlayerViewModel(AVPlayer) + ChatViewModel

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking
import CViewPlayer

// MARK: - Multi Live Manager

@Observable
@MainActor
public final class MultiLiveManager {

    // MARK: - Constants

    static let maxSessions = 4

    // MARK: - State

    var sessions: [MultiLiveSession] = []
    var selectedSessionId: UUID?
    var isGridLayout: Bool = false
    var showAddSheet: Bool = false

    /// 현재 추가 중인 채널 ID 세트 (중복 추가 방지)
    private var addingChannelIds: Set<String> = []

    /// 선택된 세션
    var selectedSession: MultiLiveSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    /// 활성(재생 중) 세션 수
    var activeSessionCount: Int {
        sessions.filter { $0.loadState == .playing }.count
    }

    /// 세션 추가 가능 여부
    var canAddSession: Bool {
        sessions.count < Self.maxSessions
    }

    // MARK: - 의존성

    private weak var apiClient: ChzzkAPIClient?
    private let logger = AppLogger.player

    // MARK: - Init

    init() {}

    /// API 클라이언트 설정 (AppState에서 지연 주입)
    func configure(apiClient: ChzzkAPIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - 세션 관리

    /// 채널 ID로 새 세션 추가
    func addSession(channelId: String) async {
        guard canAddSession else {
            logger.warning("MultiLive: 최대 세션 수(\(Self.maxSessions)) 도달")
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

        do {
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)
            let channelName = liveInfo.channel?.channelName ?? channelId
            let profileImageURL = liveInfo.channel?.channelImageURL

            let session = MultiLiveSession(
                channelId: channelId,
                channelName: channelName,
                profileImageURL: profileImageURL,
                liveInfo: liveInfo,
                apiClient: apiClient
            )
            sessions.append(session)

            // 첫 세션이면 자동 선택 + 오디오 활성화
            if sessions.count == 1 {
                selectedSessionId = session.id
            } else {
                // 추가 세션은 음소거 상태로 시작
                session.playerViewModel.toggleMute()
            }

            // 스트림 시작 (비동기)
            Task {
                await session.start()
            }

            logger.info("MultiLive: 세션 추가 — \(channelName) (\(channelId))")
        } catch {
            logger.error("MultiLive: 세션 추가 실패 — \(error.localizedDescription)")
        }
    }

    /// 세션 제거
    func removeSession(id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        await session.stop()
        sessions.remove(at: index)

        // 선택 세션이 제거되면 다른 세션 선택
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
            // 새로 선택된 세션 음소거 해제
            if let newSelected = selectedSession {
                if newSelected.playerViewModel.isMuted {
                    newSelected.playerViewModel.toggleMute()
                }
            }
        }
        logger.info("MultiLive: 세션 제거 — \(session.channelName)")
    }

    /// 세션 선택 (탭 전환)
    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        let previousId = selectedSessionId
        selectedSessionId = id

        // 오디오 라우팅: 이전 세션 음소거, 새 세션 음소거 해제
        if previousId != id {
            if let prev = sessions.first(where: { $0.id == previousId }) {
                if !prev.playerViewModel.isMuted {
                    prev.playerViewModel.toggleMute()
                }
            }
            if let current = sessions.first(where: { $0.id == id }) {
                if current.playerViewModel.isMuted {
                    current.playerViewModel.toggleMute()
                }
            }
        }
    }

    /// 모든 세션 종료
    func removeAllSessions() async {
        for session in sessions {
            await session.stop()
        }
        sessions.removeAll()
        selectedSessionId = nil
    }

    /// 활성 스트림 존재 여부 (App Nap 방지용)
    func hasActiveStreams() -> Bool {
        sessions.contains { $0.loadState == .playing }
    }
}
