// MARK: - ChatOnlyView.swift
// CViewApp - 채팅 전용 뷰 (플레이어 없이 채팅만 표시)

import SwiftUI
import CViewCore
import CViewChat
import CViewNetworking

struct ChatOnlyView: View {
    
    let channelId: String
    
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    
    @State private var channelName: String = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    @State private var chatVM = ChatViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Channel header
            chatOnlyHeader
            
            // Error banner
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Button {
                        errorMessage = nil
                        Task { await connectChat() }
                    } label: {
                        Text("재시도")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.Colors.error.opacity(0.2))
            }
            
            Divider().overlay(DesignTokens.Colors.border)
            
            // Chat messages + input
            ChatPanelView(chatVM: chatVM) {
                router.presentSheet(.chatSettings)
            }
        }
        .contentBackground()
        .background(DesignTokens.Colors.surfaceElevated)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.navigate(to: .live(channelId: channelId))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.tv")
                            .font(DesignTokens.Typography.caption)
                        Text("방송 보기")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
        }
        .task {
            await connectChat()
        }
        .onDisappear {
            Task { await chatVM.disconnect() }
        }
    }
    
    // MARK: - Header
    
    private var chatOnlyHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(channelName.isEmpty ? "채팅" : channelName)
                    .font(DesignTokens.Typography.custom(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                if isConnecting {
                    Text("연결 중...")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceBase)
    }
    
    // MARK: - Connect
    
    private func connectChat() async {
        guard let apiClient = appState.apiClient else { return }
        isConnecting = true
        
        do {
            // 채널 정보 가져오기
            let channelInfo = try await apiClient.channelInfo(channelId: channelId)
            channelName = channelInfo.channelName
            
            // 라이브 상세 → chatChannelId
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveInfo.chatChannelId else {
                errorMessage = "채팅 채널을 찾을 수 없습니다"
                isConnecting = false
                return
            }
            
            // 액세스 토큰
            let tokenResponse = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let accessToken = tokenResponse.accessToken
            
            // uid
            var uid: String? = nil
            if let userStatus = try? await apiClient.userStatus() {
                uid = userStatus.userIdHash
            }
            
            // 캐시된 기본 이모티콘 즉시 적용
            let cachedMap = appState.cachedBasicEmoticonMap
            let cachedPacks = appState.cachedBasicEmoticonPacks
            if !cachedMap.isEmpty {
                chatVM.channelEmoticons = cachedMap
                chatVM.emoticonPacks = cachedPacks
            }

            // 채널 이모티콘 로드 (기본 + 구독 + 채널 전용, soft auth)
            let allPacks = await apiClient.basicEmoticonPacks(channelId: channelId)
            let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(allPacks)

            // 채널별 이모티콘을 기본 이모티콘과 병합
            let mergedMap = cachedMap.merging(emoMap) { _, channel in channel }
            let mergedPacks = cachedPacks + loadedPacks.filter { pack in
                !cachedPacks.contains(where: { $0.id == pack.id })
            }

            Log.chat.info("채널 이모티콘: \(mergedMap.count)개 로드 완료 (팩 \(mergedPacks.count)개, 기본 \(cachedMap.count)개 포함)")
            chatVM.channelEmoticons = mergedMap
            chatVM.emoticonPacks = mergedPacks
            
            // 채팅 연결
            await chatVM.connect(chatChannelId: chatChannelId, accessToken: accessToken, uid: uid)
            
            isConnecting = false
        } catch {
            errorMessage = error.localizedDescription
            isConnecting = false
        }
    }
}
