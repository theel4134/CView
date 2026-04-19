import SwiftUI
import UniformTypeIdentifiers
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
        .animation(DesignTokens.Animation.interactive, value: chatSwipeDragOffset)
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

    // MARK: - Multi-Chat Tab Bar (MultiLive 디자인과 통일)

    var multiChatTabBar: some View {
        MCTabBar(
            manager: chatSessionManager,
            showMergedChat: Binding(
                get: { showMergedChat },
                set: { showMergedChat = $0 }
            ),
            showDisconnectAllConfirm: Binding(
                get: { showDisconnectAllConfirm },
                set: { showDisconnectAllConfirm = $0 }
            ),
            sessionCount: chatSessionManager.sessions.count,
            onAdd: { showChatAddChannel = true },
            onOpenSettings: { showChatSettings = true },
            onReconnectAll: { Task { await chatSessionManager.reconnectAll() } },
            onDisconnectAll: { Task { await chatSessionManager.disconnectAll() } },
            onHidePanel: {
                withAnimation(DesignTokens.Animation.snappy) { showMultiChat = false }
            }
        )
    }

    // MARK: - Chat Empty State

    var chatEmptyState: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "멀티채팅",
            message: "여러 채널의 채팅을 동시에\n모니터링할 수 있습니다",
            actionTitle: "채널 추가",
            action: { showChatAddChannel = true },
            style: .panel
        )
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
            // 채팅 입력 활성화를 위해 userIdHash 조회 (단일 채팅과 동일한 패턴)
            // userChannelId(OAuth 전용) 폴백 — 쿠키 로그인 사용자도 채팅 가능하도록 보장
            let chatUid: String?
            if appState.isLoggedIn,
               let userInfo = try? await apiClient.userStatus() {
                chatUid = userInfo.userIdHash ?? appState.userChannelId
            } else {
                chatUid = appState.userChannelId
            }
            let result = await chatSessionManager.addSession(
                channelId: channelId,
                channelName: channelName,
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken,
                extraToken: tokenInfo.extraToken,
                uid: chatUid,
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
        guard let apiClient = appState.apiClient else { return }

        // 채팅 입력 활성화에 필요한 userIdHash 선조회 (쿠키/OAuth 모두 대응)
        let chatUid: String?
        if appState.isLoggedIn,
           let userInfo = try? await apiClient.userStatus() {
            chatUid = userInfo.userIdHash ?? appState.userChannelId
        } else {
            chatUid = appState.userChannelId
        }

        let summary = await chatSessionManager.restoreSessions(
            apiClient: apiClient,
            uid: chatUid,
            nickname: appState.userNickname
        )

        if summary.anyRestored {
            showMultiChat = true
        }

        // P1-3: 복원 중 일부 채널이 오프라인이거나 실패한 경우 사용자에게 알림
        if summary.hasIssues {
            var lines: [String] = []
            if summary.restored > 0 {
                lines.append("\(summary.restored)개 채널 복원 완료")
            }
            if !summary.skippedOffline.isEmpty {
                let names = summary.skippedOffline.prefix(3).joined(separator: ", ")
                let suffix = summary.skippedOffline.count > 3 ? " 외 \(summary.skippedOffline.count - 3)개" : ""
                lines.append("방송 종료: \(names)\(suffix)")
            }
            if !summary.failed.isEmpty {
                let detail = summary.failed.prefix(3).map { "\($0.name) — \($0.reason)" }.joined(separator: "\n")
                lines.append("연결 실패:\n\(detail)")
            }
            chatAddError = lines.joined(separator: "\n\n")
        }
    }
}

// MARK: - MCTabBar (멀티라이브와 통일된 단일 40pt 탭 바)

private struct MCTabBar: View {
    let manager: MultiChatSessionManager
    @Binding var showMergedChat: Bool
    @Binding var showDisconnectAllConfirm: Bool
    let sessionCount: Int
    let onAdd: () -> Void
    let onOpenSettings: () -> Void
    let onReconnectAll: () -> Void
    let onDisconnectAll: () -> Void
    let onHidePanel: () -> Void

    @State private var draggingSessionId: String?

    var body: some View {
        HStack(spacing: 0) {
            tabScrollArea
            Spacer(minLength: 0)
            toolButtonArea
        }
        .frame(height: 40)
        .background { DesignTokens.Colors.surfaceBase }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    // MARK: - Tab Scroll

    private var tabScrollArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if manager.sessions.isEmpty {
                    emptyTabHint
                } else {
                    ForEach(manager.sessions) { session in
                        MCTabChip(
                            session: session,
                            manager: manager,
                            isSelected: manager.selectedChannelId == session.id,
                            onSelect: {
                                withAnimation(DesignTokens.Animation.micro) {
                                    manager.selectChannel(session.id)
                                }
                            },
                            onClose: { Task { await manager.removeSession(channelId: session.id) } },
                            onMoveLeft: { moveSession(session.id, delta: -1) },
                            onMoveRight: { moveSession(session.id, delta: 1) }
                        )
                        .onDrag {
                            draggingSessionId = session.id
                            return NSItemProvider(object: session.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: MCTabReorderDropDelegate(
                            targetSessionId: session.id,
                            manager: manager,
                            draggingSessionId: $draggingSessionId
                        ))
                        .opacity(draggingSessionId == session.id ? 0.4 : 1.0)
                        .animation(DesignTokens.Animation.fast, value: draggingSessionId)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
    }

    private var emptyTabHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
            Text("멀티채팅")
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func moveSession(_ channelId: String, delta: Int) {
        guard let idx = manager.sessions.firstIndex(where: { $0.id == channelId }) else { return }
        let target = idx + delta
        guard target >= 0, target < manager.sessions.count else { return }
        // IndexSet/toOffset: moving right needs target+1
        let toOffset = delta > 0 ? target + 1 : target
        withAnimation(DesignTokens.Animation.fast) {
            manager.moveSession(from: IndexSet(integer: idx), to: toOffset)
        }
    }

    // MARK: - Tool Buttons

    @ViewBuilder
    private var toolButtonArea: some View {
        // 통합 모드 토글 (2개 이상)
        if sessionCount >= 2 {
            MCToolButton(
                icon: "text.line.first.and.arrowtriangle.forward",
                isActive: showMergedChat,
                help: showMergedChat ? "개별 채널 보기" : "통합 타임라인"
            ) {
                withAnimation(DesignTokens.Animation.snappy) { showMergedChat.toggle() }
            }
            .padding(.trailing, DesignTokens.Spacing.xxs)
        }

        // 전체 재연결
        if sessionCount > 0 {
            MCToolButton(
                icon: "arrow.clockwise",
                isActive: false,
                help: "전체 채널 재연결",
                action: onReconnectAll
            )
            .padding(.trailing, DesignTokens.Spacing.xxs)

            mcDivider

            // 채팅 설정
            MCToolButton(
                icon: "gearshape",
                isActive: false,
                help: "채팅 설정",
                action: onOpenSettings
            )
            .padding(.trailing, DesignTokens.Spacing.xxs)

            // 전체 해제
            MCToolButton(
                icon: "xmark.circle",
                isActive: false,
                help: "전체 채널 해제"
            ) { showDisconnectAllConfirm = true }
            .padding(.trailing, DesignTokens.Spacing.xxs)
            .confirmationDialog(
                "멀티채팅 전체 해제",
                isPresented: $showDisconnectAllConfirm,
                titleVisibility: .visible
            ) {
                Button("전체 해제", role: .destructive, action: onDisconnectAll)
                Button("취소", role: .cancel) {}
            } message: {
                Text("\(sessionCount)개 채널의 채팅 연결을 모두 해제할까요?")
            }
        }

        // 채널 추가
        MCToolButton(
            icon: "plus",
            isActive: false,
            help: "채팅 채널 추가",
            action: onAdd
        )
        .padding(.trailing, DesignTokens.Spacing.xxs)

        mcDivider

        // 패널 숨기기
        MCToolButton(
            icon: "chevron.right.2",
            isActive: false,
            help: "멀티채팅 숨기기",
            action: onHidePanel
        )
        .padding(.trailing, DesignTokens.Spacing.sm)
    }

    private var mcDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColorLight)
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, DesignTokens.Spacing.xxs)
    }
}

// MARK: - MCToolButton (MLToolButton과 동일 스타일)

private struct MCToolButton: View {
    let icon: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(
                    isActive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary
                )
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.15), lineWidth: 0.5)
                            }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated.opacity(0.3))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - MCTabChip (MLTabChip과 동일 시각 스타일)

private struct MCTabChip: View {
    let session: MultiChatSessionManager.ChatSession
    let manager: MultiChatSessionManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        Button(action: onSelect) {
            chipContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .contextMenu { contextMenuItems }
    }

    private var chipContent: some View {
        HStack(spacing: 6) {
            avatarView
            channelInfo
            if isHovered || isSelected { reorderArrows }
            closeButton
        }
        .padding(.leading, 6)
        .padding(.trailing, isHovered ? 4 : 6)
        .padding(.vertical, 4)
        .background(chipBackground)
        .clipShape(Capsule(style: .continuous))
        .overlay(chipBorder)
        .shadow(
            color: isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.10) : .clear,
            radius: 4, y: 1
        )
    }

    // MARK: - Channel Info

    private var channelInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.channelName)
                .font(DesignTokens.Typography.custom(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary
                )
                .lineLimit(1)
            statusSubtext
        }
    }

    @ViewBuilder
    private var statusSubtext: some View {
        let state = session.chatViewModel.connectionState
        let count = session.chatViewModel.messageCount
        HStack(spacing: 4) {
            Text(statusLabel(state))
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(statusLabelColor(state))
            if count > 0 {
                Text("·")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("\(count)")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private func statusLabel(_ state: ChatConnectionState) -> String {
        switch state {
        case .connected: return "연결됨"
        case .connecting: return "연결 중..."
        case .reconnecting(let attempt) where attempt > 0: return "재연결 \(attempt)회"
        case .reconnecting: return "재연결 중..."
        case .disconnected: return "연결 끊김"
        case .failed: return "연결 실패"
        }
    }

    private func statusLabelColor(_ state: ChatConnectionState) -> Color {
        switch state {
        case .connected: return DesignTokens.Colors.chzzkGreen.opacity(0.8)
        case .connecting, .reconnecting: return DesignTokens.Colors.warning
        case .failed: return DesignTokens.Colors.error
        case .disconnected: return DesignTokens.Colors.textTertiary
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [avatarColor, avatarColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                Text(String(session.channelName.prefix(1)).uppercased())
                    .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            statusDot
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        let isConnected = session.chatViewModel.connectionState.isConnected
        ZStack {
            Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 10, height: 10)
            Circle()
                .fill(isConnected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.error)
                .frame(width: 7, height: 7)
                .shadow(
                    color: isConnected
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Colors.error.opacity(0.4),
                    radius: 2
                )
        }
        .offset(x: 3, y: 3)
    }

    // MARK: - Reorder Arrows

    @ViewBuilder
    private var reorderArrows: some View {
        if manager.sessions.count > 1 {
            HStack(spacing: 2) {
                reorderButton(icon: "chevron.left",  action: onMoveLeft)
                reorderButton(icon: "chevron.right", action: onMoveRight)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private func reorderButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 7, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DesignTokens.Typography.custom(size: 8, weight: .bold))
                .foregroundStyle(
                    isCloseHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary
                )
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .background {
                    Circle().fill(
                        isCloseHovered
                            ? DesignTokens.Colors.surfaceOverlay.opacity(0.9)
                            : (isHovered ? DesignTokens.Colors.surfaceElevated.opacity(0.5) : Color.clear)
                    )
                }
                .scaleEffect(isCloseHovered ? 1.08 : 1.0)
                .compositingGroup()
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isCloseHovered)
        .opacity(isHovered || isSelected ? 1 : 0)
    }

    // MARK: - Background / Border

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            ZStack {
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.75))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen.opacity(0.10),
                                DesignTokens.Colors.chzzkGreen.opacity(0.04),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        } else if isHovered {
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.25))
        } else {
            Color.clear
        }
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.30)
                    : (isHovered ? DesignTokens.Glass.borderColorLight.opacity(0.5) : Color.clear),
                lineWidth: isSelected ? 1.0 : 0.5
            )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        let idx = manager.sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        if idx > 0 {
            Button(action: onMoveLeft) {
                Label("왼쪽으로 이동", systemImage: "arrow.left")
            }
        }
        if idx < manager.sessions.count - 1 {
            Button(action: onMoveRight) {
                Label("오른쪽으로 이동", systemImage: "arrow.right")
            }
        }
        Divider()
        Button(role: .destructive, action: onClose) {
            Label("채널 제거", systemImage: "minus.circle")
        }
    }

    // MARK: - Avatar Color

    private var avatarColor: Color {
        let palette: [Color] = [
            DesignTokens.Colors.accentBlue.opacity(0.8),
            DesignTokens.Colors.accentPurple.opacity(0.75),
            DesignTokens.Colors.accentPink.opacity(0.75),
            DesignTokens.Colors.accentOrange.opacity(0.75),
            DesignTokens.Colors.chzzkGreen.opacity(0.65),
        ]
        return palette[abs(session.id.hashValue) % palette.count]
    }
}

// MARK: - MCTabReorderDropDelegate

private struct MCTabReorderDropDelegate: DropDelegate {
    let targetSessionId: String
    let manager: MultiChatSessionManager
    @Binding var draggingSessionId: String?

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingSessionId,
              dragId != targetSessionId,
              let fromIndex = manager.sessions.firstIndex(where: { $0.id == dragId }),
              let toIndex = manager.sessions.firstIndex(where: { $0.id == targetSessionId })
        else { return }

        withAnimation(DesignTokens.Animation.fast) {
            manager.moveSession(
                from: IndexSet(integer: fromIndex),
                to: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSessionId = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingSessionId != nil
    }
}
