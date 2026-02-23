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
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Button {
                        errorMessage = nil
                        Task { await connectChat() }
                    } label: {
                        Text("재시도")
                            .font(.system(size: 11, weight: .medium))
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
        .background(DesignTokens.Colors.backgroundDark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.navigate(to: .live(channelId: channelId))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.tv")
                            .font(.system(size: 11))
                        Text("방송 보기")
                            .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(channelName.isEmpty ? "채팅" : channelName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                if isConnecting {
                    Text("연결 중...")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.backgroundElevated)
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
            let accessToken = tokenResponse.accessToken ?? ""
            
            // uid
            var uid: String? = nil
            if let userStatus = try? await apiClient.userStatus() {
                uid = userStatus.userIdHash
            }
            
            // 채널 이모티콘 로드 (기본 + 구독 + 채널 전용, soft auth)
            let allPacks = await apiClient.basicEmoticonPacks(channelId: channelId)
            let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(allPacks)
            Log.chat.info("채널 이모티콘: \(emoMap.count)개 로드 완료 (팩 \(loadedPacks.count)개)")
            chatVM.channelEmoticons = emoMap
            chatVM.emoticonPacks = loadedPacks
            
            // 채팅 연결
            await chatVM.connect(chatChannelId: chatChannelId, accessToken: accessToken, uid: uid)
            
            isConnecting = false
        } catch {
            errorMessage = error.localizedDescription
            isConnecting = false
        }
    }
}
