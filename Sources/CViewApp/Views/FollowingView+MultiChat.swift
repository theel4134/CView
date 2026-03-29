import SwiftUI
import CViewCore
import CViewChat
import CViewNetworking
import CViewUI

// MARK: - FollowingView + Multi-Chat Panel

extension FollowingView {

    var multiChatInlinePanel: some View {
        VStack(spacing: 0) {
            // 채팅 탭 바
            multiChatTabBar

            // 채팅 콘텐츠 영역 — leading 정렬로 중앙 정렬 방지
            if chatSessionManager.sessions.isEmpty {
                chatEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = chatSessionManager.selectedSession {
                ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: { showChatSettings = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(session.id) // 채널 전환 시 뷰 리셋
            } else {
                chatEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.Colors.background)
        // 오른쪽 스와이프로 멀티채팅 숨기기
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    // 오른쪽으로 충분히 스와이프 + 수평 이동이 수직보다 큰 경우
                    if value.translation.width > 80 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                        withAnimation(DesignTokens.Animation.snappy) {
                            showMultiChat = false
                        }
                    }
                }
        )
        .alert("채팅 연결 실패", isPresented: Binding(
            get: { chatAddError != nil },
            set: { if !$0 { chatAddError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(chatAddError ?? "")
        }
        .sheet(isPresented: Binding(
            get: { ps.showChatSettings },
            set: { ps.showChatSettings = $0 }
        )) {
            ChatSettingsView()
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { ps.showChatAddChannel },
            set: { ps.showChatAddChannel = $0 }
        )) {
            chatAddChannelSheet
        }
    }

    // MARK: - Multi-Chat Tab Bar

    var multiChatTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)

                Text("멀티채팅")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                if !chatSessionManager.sessions.isEmpty {
                    Text("\(chatSessionManager.sessions.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignTokens.Colors.accentOrange.opacity(0.12), in: Capsule())
                }

                Spacer()

                // 전체 해제
                if !chatSessionManager.sessions.isEmpty {
                    Button {
                        Task { await chatSessionManager.disconnectAll() }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("전체 채널 해제")
                }

                // 채널 추가 버튼
                Button {
                    showChatAddChannel = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                }
                .buttonStyle(.plain)
                .help("채팅 채널 추가")

                // 채팅 패널 숨기기 버튼
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showMultiChat = false
                    }
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("멀티채팅 숨기기")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // 채널 탭 스크롤
            if !chatSessionManager.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(chatSessionManager.sessions) { session in
                            multiChatTab(session)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }

            Divider().opacity(0.4)
        }
        .background(DesignTokens.Colors.surfaceBase.opacity(0.95))
    }

    func multiChatTab(_ session: MultiChatSessionManager.ChatSession) -> some View {
        let isSelected = session.id == chatSessionManager.selectedChannelId
        let isConnected = session.chatViewModel.connectionState.isConnected

        return Button {
            chatSessionManager.selectChannel(session.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isConnected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.error)
                    .frame(width: 5, height: 5)

                Text(session.channelName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                if session.chatViewModel.messageCount > 0 {
                    Text("\(session.chatViewModel.messageCount)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.textTertiary)
                }

                // 채널 제거 버튼
                Button {
                    Task { await chatSessionManager.removeSession(channelId: session.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 14, height: 14)
                        .background(
                            isSelected ? Color.white.opacity(0.1) : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? DesignTokens.Colors.accentOrange.opacity(0.15)
                    : DesignTokens.Colors.surfaceElevated.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.accentOrange.opacity(0.3) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .foregroundStyle(
                isSelected ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.textSecondary
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat Empty State

    var chatEmptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.4))
            Text("멀티채팅")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("여러 채널의 채팅을 동시에\n모니터링할 수 있습니다")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                showChatAddChannel = true
            } label: {
                Label("채널 추가", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.accentOrange)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat Add Channel Sheet

    var chatAddChannelSheet: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("채팅 채널 추가")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널명 검색 또는 채널 ID 입력", text: $chatSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .onSubmit { searchChatChannels() }
                if isSearchingChatChannels {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
            )

            // 검색 결과
            if !chatSearchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(chatSearchResults) { channel in
                            Button {
                                Task {
                                    await addChatChannel(channelId: channel.channelId)
                                    chatSearchQuery = ""
                                    chatSearchResults = []
                                    showChatAddChannel = false
                                }
                            } label: {
                                HStack(spacing: DesignTokens.Spacing.sm) {
                                    if let url = channel.channelImageURL {
                                        CachedAsyncImage(url: url) {
                                            Circle().fill(DesignTokens.Colors.surfaceElevated)
                                        }
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                    } else {
                                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                                            .frame(width: 28, height: 28)
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .font(DesignTokens.Typography.micro)
                                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                            }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(channel.channelName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        Text("팔로워 \(channel.followerCount.formatted())")
                                            .font(.system(size: 9, weight: .regular))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .background(DesignTokens.Colors.surfaceOverlay.opacity(0.001))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // 직접 입력
            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("채널 ID 직접 입력", text: $newChatChannelId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("추가") {
                    let channelId = newChatChannelId.trimmingCharacters(in: .whitespaces)
                    guard !channelId.isEmpty else { return }
                    Task {
                        await addChatChannel(channelId: channelId)
                        newChatChannelId = ""
                        showChatAddChannel = false
                    }
                }
                .disabled(newChatChannelId.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button("취소") {
                    newChatChannelId = ""
                    chatSearchQuery = ""
                    chatSearchResults = []
                    showChatAddChannel = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: layout.chatAddSheetWidth)
    }

    // MARK: - Chat Actions

    func searchChatChannels() {
        let query = chatSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let apiClient = appState.apiClient else { return }
        isSearchingChatChannels = true
        Task {
            do {
                let result = try await apiClient.searchChannels(keyword: query, size: 10)
                chatSearchResults = result.data
            } catch {
                chatSearchResults = []
            }
            isSearchingChatChannels = false
        }
    }

    func addChatChannel(channelId: String) async {
        guard let apiClient = appState.apiClient else { return }
        do {
            let liveDetail = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveDetail.chatChannelId else { return }
            let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let channelName = liveDetail.channel?.channelName ?? channelId
            await chatSessionManager.addSession(
                channelId: channelId,
                channelName: channelName,
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken,
                extraToken: tokenInfo.extraToken,
                uid: appState.userChannelId,
                nickname: appState.userNickname
            )
        } catch {
            chatAddError = "채널 '\(channelId)'에 연결할 수 없습니다: \(error.localizedDescription)"
        }
    }
}
