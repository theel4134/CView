// MARK: - MultiLiveSession.swift
// CViewApp — 멀티라이브 개별 세션 모델
// 각 세션은 AVPlayer 기반 독립 PlayerViewModel + ChatViewModel 소유

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking
import CViewPlayer
import CViewChat

// MARK: - Load State

enum MultiLiveLoadState: Equatable {
    case idle
    case loading
    case playing
    case error(String)
}

// MARK: - Multi Live Session

@Observable
@MainActor
final class MultiLiveSession: Identifiable {

    // MARK: - Identity

    let id: UUID
    let channelId: String
    var channelName: String
    var profileImageURL: URL?
    var liveTitle: String
    var viewerCount: Int = 0
    var categoryName: String?
    var thumbnailURL: URL?

    // MARK: - State

    var loadState: MultiLiveLoadState = .idle

    // MARK: - ViewModels

    let playerViewModel: PlayerViewModel
    let chatViewModel: ChatViewModel

    // MARK: - Tasks

    private var startTask: Task<Void, Never>?
    private var statusPollTask: Task<Void, Never>?
    private var chatConnectionTask: Task<Void, Never>?

    // MARK: - Dependencies

    private var liveInfo: LiveInfo?
    private weak var apiClient: ChzzkAPIClient?
    private let logger = AppLogger.player

    /// 로그인 사용자 정보 (채팅 전송용)
    private var userUid: String?
    private var userNickname: String?

    /// 앱 시작 시 프리로드된 기본 이모티콘 (채널 진입 전 즉시 사용)
    private let cachedBasicEmoticonMap: [String: String]
    private let cachedBasicEmoticonPacks: [EmoticonPack]

    // MARK: - Init

    init(
        channelId: String,
        channelName: String,
        profileImageURL: URL?,
        liveInfo: LiveInfo?,
        apiClient: ChzzkAPIClient,
        userUid: String? = nil,
        userNickname: String? = nil,
        cachedBasicEmoticonMap: [String: String] = [:],
        cachedBasicEmoticonPacks: [EmoticonPack] = []
    ) {
        self.id = UUID()
        self.channelId = channelId
        self.channelName = channelName
        self.profileImageURL = profileImageURL
        self.liveInfo = liveInfo
        self.liveTitle = liveInfo?.liveTitle ?? ""
        self.viewerCount = liveInfo?.concurrentUserCount ?? 0
        self.categoryName = liveInfo?.liveCategoryValue
        self.thumbnailURL = liveInfo?.liveImageURL
        self.apiClient = apiClient
        self.userUid = userUid
        self.userNickname = userNickname
        self.cachedBasicEmoticonMap = cachedBasicEmoticonMap
        self.cachedBasicEmoticonPacks = cachedBasicEmoticonPacks

        // AVPlayer 전용 PlayerViewModel 생성
        self.playerViewModel = PlayerViewModel(engineType: .avPlayer)
        self.chatViewModel = ChatViewModel()

        // 사용자 정보 설정 (채팅 전송 권한)
        if let userUid {
            self.chatViewModel.currentUserUid = userUid
        }
        self.chatViewModel.currentUserNickname = userNickname

        // 캐시된 기본 이모티콘 즉시 적용
        if !cachedBasicEmoticonMap.isEmpty {
            self.chatViewModel.channelEmoticons = cachedBasicEmoticonMap
            self.chatViewModel.emoticonPacks = cachedBasicEmoticonPacks
        }
    }

    // MARK: - Lifecycle

    /// 스트림 + 채팅 시작
    func start() async {
        guard loadState != .loading else { return }
        loadState = .loading

        do {
            guard let apiClient else {
                loadState = .error("API 클라이언트 없음")
                return
            }

            // liveInfo가 없으면 새로 조회
            let info: LiveInfo
            if let cached = liveInfo {
                info = cached
            } else {
                info = try await apiClient.liveDetail(channelId: channelId)
                liveInfo = info
                channelName = info.channel?.channelName ?? channelId
                profileImageURL = info.channel?.channelImageURL
                liveTitle = info.liveTitle
                viewerCount = info.concurrentUserCount
                categoryName = info.liveCategoryValue
                thumbnailURL = info.liveImageURL
            }

            // HLS 스트림 URL 추출 — JSON 디코딩을 백그라운드에서 수행
            guard let playbackJSON = info.livePlaybackJSON,
                  let jsonData = playbackJSON.data(using: .utf8) else {
                loadState = .error("재생 정보 없음")
                return
            }
            let streamURL: URL = try await Task.detached(priority: .userInitiated) {
                let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
                let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                    ?? playback.media.first
                guard let mediaPath = media?.path,
                      let url = URL(string: mediaPath) else {
                    throw AppError.player(.invalidManifest)
                }
                return url
            }.value

            // AVPlayer로 스트림 시작
            await playerViewModel.startStream(
                channelId: channelId,
                streamUrl: streamURL,
                channelName: channelName,
                liveTitle: liveTitle,
                thumbnailURL: thumbnailURL
            )
            loadState = .playing

            // 채팅 연결 (병렬)
            chatConnectionTask = Task {
                await connectChat(info: info, apiClient: apiClient)
            }

            // 상태 폴링 시작 (30초마다)
            startStatusPolling(apiClient: apiClient)

            logger.info("MultiLive: 세션 시작 — \(self.channelName)")
        } catch {
            loadState = .error(error.localizedDescription)
            logger.error("MultiLive: 세션 시작 실패 — \(error.localizedDescription)")
        }
    }

    /// 세션 중지 (모든 리소스 해제)
    func stop() async {
        startTask?.cancel()
        startTask = nil
        statusPollTask?.cancel()
        statusPollTask = nil
        chatConnectionTask?.cancel()
        chatConnectionTask = nil

        await playerViewModel.stopStream()
        await chatViewModel.disconnect()

        loadState = .idle
        logger.info("MultiLive: 세션 중지 — \(self.channelName)")
    }

    // MARK: - Chat Connection

    private func connectChat(info: LiveInfo, apiClient: ChzzkAPIClient) async {
        guard let chatChannelId = info.chatChannelId else { return }

        do {
            // 병렬: 토큰 + 이모티콘 팩 로드
            let tokenTask = Task { try await apiClient.chatAccessToken(chatChannelId: chatChannelId) }
            let packsTask = Task { await apiClient.basicEmoticonPacks(channelId: channelId) }

            let tokenInfo = try await tokenTask.value
            let packs = await packsTask.value
            let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(packs)

            // 채널별 이모티콘을 캐시된 기본 이모티콘과 병합
            let mergedMap = cachedBasicEmoticonMap.merging(emoMap) { _, channel in channel }
            let mergedPacks = cachedBasicEmoticonPacks + loadedPacks.filter { pack in
                !cachedBasicEmoticonPacks.contains(where: { $0.id == pack.id })
            }

            chatViewModel.channelEmoticons = mergedMap
            chatViewModel.emoticonPacks = mergedPacks

            // 채팅 연결 (extraToken + uid 전달 → SEND 권한)
            await chatViewModel.connect(
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken,
                extraToken: tokenInfo.extraToken,
                uid: userUid,
                channelId: channelId
            )
        } catch {
            logger.error("MultiLive: 채팅 연결 실패 — \(error.localizedDescription)")
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling(apiClient: ChzzkAPIClient) {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self, channelId] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }

                do {
                    let info = try await apiClient.liveDetail(channelId: channelId)
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self?.viewerCount = info.concurrentUserCount
                        self?.liveTitle = info.liveTitle
                        self?.categoryName = info.liveCategoryValue
                    }
                } catch {
                    // 폴링 실패는 무시 (다음 주기에 재시도)
                }
            }
        }
    }
}
