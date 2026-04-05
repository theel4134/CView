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

            // 채팅 콘텐츠 영역
            if chatSessionManager.sessions.isEmpty {
                chatEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showMergedChat {
                MergedChatView(sessionManager: chatSessionManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .updating($chatSwipeDragOffset) { value, state, _ in
                    let dx = value.translation.width
                    if dx > 0 && abs(dx) > abs(value.translation.height) * 1.5 {
                        state = dx
                    }
                }
                .onEnded { value in
                    // 오른쪽으로 충분히 스와이프 + 수평 이동이 수직보다 큰 경우
                    if value.translation.width > 80 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                        withAnimation(DesignTokens.Animation.snappy) {
                            showMultiChat = false
                        }
                    }
                }
        )
        .offset(x: chatSwipeDragOffset * 0.3)
        .opacity(chatSwipeDragOffset > 0 ? 1 - Double(chatSwipeDragOffset) / 300 : 1)
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
            ChatChannelPickerView(
                apiClient: appState.apiClient,
                onChannelSelected: { channelId in await addChatChannel(channelId: channelId) },
                onDismiss: { showChatAddChannel = false },
                sheetWidth: layout.chatAddSheetWidth
            )
        }
    }

    // MARK: - Multi-Chat Tab Bar

    var multiChatTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)

                Text("멀티채팅")
                    .font(DesignTokens.Typography.footnoteMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                if !chatSessionManager.sessions.isEmpty {
                    Text("\(chatSessionManager.sessions.count)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignTokens.Colors.accentOrange.opacity(DesignTokens.Opacity.medium), in: Capsule())
                }

                Spacer()

                // 통합 모드 토글
                if chatSessionManager.sessions.count >= 2 {
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) {
                            showMergedChat.toggle()
                        }
                    } label: {
                        Image(systemName: showMergedChat
                            ? "text.line.first.and.arrowtriangle.forward"
                            : "text.line.first.and.arrowtriangle.forward")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                            .foregroundStyle(showMergedChat
                                ? DesignTokens.Colors.accentOrange
                                : DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(showMergedChat ? "개별 채널 보기" : "통합 타임라인")
                }

                // 전체 재연결
                if !chatSessionManager.sessions.isEmpty {
                    Button {
                        Task { await chatSessionManager.reconnectAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .buttonStyle(.plain)
                    .help("전체 채널 재연결")
                }

                // 전체 해제
                if !chatSessionManager.sessions.isEmpty {
                    Button {
                        showDisconnectAllConfirm = true
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("전체 채널 해제")
                    .confirmationDialog(
                        "멀티채팅 전체 해제",
                        isPresented: $showDisconnectAllConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("전체 해제", role: .destructive) {
                            Task { await chatSessionManager.disconnectAll() }
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("\(chatSessionManager.sessions.count)개 채널의 채팅 연결을 모두 해제할까요?")
                    }
                }

                // 채널 추가 버튼
                Button {
                    showChatAddChannel = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(DesignTokens.Typography.captionMedium)
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
                        .font(DesignTokens.Typography.microSemibold)
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
                        ForEach(Array(chatSessionManager.sessions.enumerated()), id: \.element.id) { index, session in
                            multiChatTab(session)
                                .contextMenu {
                                    if index > 0 {
                                        Button {
                                            chatSessionManager.moveSession(from: IndexSet([index]), to: index - 1)
                                        } label: {
                                            Label("왼쪽으로 이동", systemImage: "arrow.left")
                                        }
                                    }
                                    if index < chatSessionManager.sessions.count - 1 {
                                        Button {
                                            chatSessionManager.moveSession(from: IndexSet([index]), to: index + 2)
                                        } label: {
                                            Label("오른쪽으로 이동", systemImage: "arrow.right")
                                        }
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        Task { await chatSessionManager.removeSession(channelId: session.id) }
                                    } label: {
                                        Label("채널 제거", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }

            Divider().opacity(DesignTokens.Opacity.divider)
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
                    .font(DesignTokens.Typography.custom(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                if session.chatViewModel.messageCount > 0 {
                    Text("\(session.chatViewModel.messageCount)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.textTertiary)
                }

                // 채널 제거 버튼
                Button {
                    Task { await chatSessionManager.removeSession(channelId: session.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
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
                    ? DesignTokens.Colors.accentOrange.opacity(DesignTokens.Opacity.heavy)
                    : DesignTokens.Colors.surfaceElevated.opacity(0.5),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.accentOrange.opacity(0.3) : Color.clear,
                        lineWidth: DesignTokens.Border.thin
                    )
            )
            .foregroundStyle(
                isSelected ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.textSecondary
            )
        }
        .buttonStyle(.plain)
        .help(session.chatViewModel.connectionState.displayText)
    }

    // MARK: - Chat Empty State

    var chatEmptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(DesignTokens.Typography.display.weight(.ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.4))
            Text("멀티채팅")
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("여러 채널의 채팅을 동시에\n모니터링할 수 있습니다")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                showChatAddChannel = true
            } label: {
                Label("채널 추가", systemImage: "plus")
                    .font(DesignTokens.Typography.footnoteMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.accentOrange)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat Actions

    func addChatChannel(channelId: String) async {
        // 세션 수 사전 체크
        guard chatSessionManager.canAddSession else {
            chatAddError = "최대 \(MultiChatSessionManager.maxSessions)개 채널까지 추가할 수 있습니다."
            return
        }

        guard let apiClient = appState.apiClient else { return }
        do {
            let liveDetail = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveDetail.chatChannelId else {
                chatAddError = "채널 '\(channelId)'은(는) 현재 방송 중이 아닙니다."
                return
            }
            let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let channelName = liveDetail.channel?.channelName ?? channelId
            let result = await chatSessionManager.addSession(
                channelId: channelId,
                channelName: channelName,
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken,
                extraToken: tokenInfo.extraToken,
                uid: appState.userChannelId,
                nickname: appState.userNickname
            )
            switch result {
            case .alreadyExists:
                chatAddError = "'\(channelName)' 채널은 이미 추가되어 있습니다."
            case .maxSessionsReached:
                chatAddError = "최대 \(MultiChatSessionManager.maxSessions)개 채널까지 추가할 수 있습니다."
            case .success, .connectionFailed:
                break
            }
        } catch {
            chatAddError = "채널 '\(channelId)'에 연결할 수 없습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - Session Restore

    /// 저장된 멀티채팅 세션 복원 (앱 시작 시 호출)
    func restoreSavedChatSessions() async {
        let saved = chatSessionManager.savedSessions
        guard !saved.isEmpty else { return }

        guard let apiClient = appState.apiClient else { return }

        var restoredAny = false
        let lastSelected = chatSessionManager.savedSelectedChannelId

        for session in saved {
            do {
                let liveDetail = try await apiClient.liveDetail(channelId: session.channelId)
                guard let chatChannelId = liveDetail.chatChannelId else { continue }
                let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
                let channelName = liveDetail.channel?.channelName ?? session.channelName
                let result = await chatSessionManager.addSession(
                    channelId: session.channelId,
                    channelName: channelName,
                    chatChannelId: chatChannelId,
                    accessToken: tokenInfo.accessToken,
                    extraToken: tokenInfo.extraToken,
                    uid: appState.userChannelId,
                    nickname: appState.userNickname
                )
                if case .success = result {
                    restoredAny = true
                }
            } catch {
                // 방송 종료 등으로 연결 실패 — 무시하고 다음 채널 시도
                continue
            }
        }

        // 마지막 선택 채널 복원
        if let lastSelected, chatSessionManager.sessions.contains(where: { $0.id == lastSelected }) {
            chatSessionManager.selectChannel(lastSelected)
        }

        // 복원된 세션이 있으면 멀티채팅 패널 표시
        if restoredAny {
            showMultiChat = true
        }
    }
}
