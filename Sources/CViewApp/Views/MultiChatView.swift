// MARK: - MultiChatView.swift
// CViewApp - 멀티채팅 뷰
// 여러 채널의 채팅을 동시에 표시 (사이드바/그리드/통합 모드)

import SwiftUI
import CViewCore
import CViewNetworking
import CViewUI

/// 멀티채팅 레이아웃 모드
enum MultiChatLayoutMode: String, CaseIterable {
    case sidebar  // 사이드바 + 단일 채팅
    case grid     // 그리드 동시 표시
    case merged   // 통합 타임라인

    var icon: String {
        switch self {
        case .sidebar: return "sidebar.left"
        case .grid:    return "rectangle.split.2x2"
        case .merged:  return "text.line.first.and.arrowtriangle.forward"
        }
    }

    var label: String {
        switch self {
        case .sidebar: return "사이드바"
        case .grid:    return "그리드"
        case .merged:  return "통합"
        }
    }
}

/// 멀티채팅 뷰 - 사이드바(채널 목록) + 메인(선택된 채널 채팅)
struct MultiChatView: View {
    @Environment(AppState.self) private var appState
    @State private var sessionManager = MultiChatSessionManager()
    @State private var showAddChannel = false
    @State private var showChatSettings = false
    @State private var addChannelError: String?
    @State private var layoutMode: MultiChatLayoutMode = .sidebar

    var body: some View {
        Group {
            switch layoutMode {
            case .sidebar:
                sidebarLayout
            case .grid:
                gridLayout
            case .merged:
                mergedLayout
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            sessionManager.configure(settingsStore: appState.settingsStore)
            if sessionManager.sessions.isEmpty, let apiClient = appState.apiClient {
                await sessionManager.restoreSessions(
                    apiClient: apiClient,
                    uid: appState.userChannelId,
                    nickname: appState.userNickname
                )
            }
        }
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsView()
                .environment(appState)
        }
        .alert("채널 추가 실패", isPresented: Binding(
            get: { addChannelError != nil },
            set: { if !$0 { addChannelError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(addChannelError ?? "")
        }
        .sheet(isPresented: $showAddChannel) {
            ChatChannelPickerView(
                apiClient: appState.apiClient,
                onChannelSelected: { channelId in await addChannel(channelId: channelId) },
                onDismiss: { showAddChannel = false }
            )
        }
    }

    // MARK: - Sidebar Layout (기존)

    private var sidebarLayout: some View {
        HSplitView {
            channelSidebar
                .frame(minWidth: 160, maxWidth: 220)

            if let session = sessionManager.selectedSession {
                ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: { showChatSettings = true })
            } else {
                emptyState
            }
        }
    }

    // MARK: - Grid Layout (다중 채팅 동시 표시)

    private var gridLayout: some View {
        VStack(spacing: 0) {
            gridToolbar
            Divider()

            if sessionManager.sessions.isEmpty {
                emptyState
            } else {
                gridContent
            }
        }
    }

    private var gridToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            layoutModePicker

            Spacer()

            Text("\(sessionManager.sessions.count)개 채널")
                .font(DesignTokens.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            MSChipButton(
                icon: "arrow.clockwise",
                title: "재접속",
                style: .ghost,
                action: { Task { await sessionManager.reconnectAll() } }
            )
            .disabled(sessionManager.sessions.isEmpty)
            .opacity(sessionManager.sessions.isEmpty ? 0.4 : 1.0)
            .help("전체 채널 재접속")

            MSChipButton(
                icon: "plus",
                title: "채널 추가",
                style: .accent,
                isActive: true,
                action: { showAddChannel = true }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs + 1)
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }

    private var gridContent: some View {
        GeometryReader { geo in
            // [Fix] 세션 배열 스냅샷 캡처 — 렌더링 중 배열 변경에 의한 인덱스 초과 크래시 방지
            let sessions = Array(sessionManager.sessions)
            let count = sessions.count

            if count == 1, let s0 = sessions.first {
                gridCell(session: s0, width: geo.size.width, height: geo.size.height)
            } else if count == 2, let s0 = sessions[safe: 0], let s1 = sessions[safe: 1] {
                // 2개: 좌우 분할 + 리사이즈 디바이더
                let leftW = geo.size.width * sessionManager.gridHorizontalRatio
                HStack(spacing: 0) {
                    gridCell(session: s0, width: leftW, height: geo.size.height)
                    MLResizeDivider(
                        isHorizontal: true,
                        containerLength: geo.size.width,
                        currentRatio: sessionManager.gridHorizontalRatio,
                        onRatioChange: { sessionManager.gridHorizontalRatio = $0; sessionManager.persistGridRatio() }
                    )
                    gridCell(session: s1, width: geo.size.width - leftW, height: geo.size.height)
                }
            } else if count >= 3 {
                // 3개 이상: 상하 분할 — 상단 행 = ceil(count/2), 하단 행 = 나머지
                // · 3,4 → (2,1) (2,2)  · 5,6 → (3,2) (3,3)  · 7,8 → (4,3) (4,4)
                let topH = geo.size.height * sessionManager.gridVerticalRatio
                let botH = geo.size.height - topH
                let topCount = (count + 1) / 2
                let topRow = Array(sessions.prefix(topCount))
                let bottomRow = Array(sessions.dropFirst(topCount))
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(topRow) { session in
                            gridCell(session: session, width: geo.size.width / CGFloat(topRow.count), height: topH)
                        }
                    }
                    .frame(height: topH)

                    MLResizeDivider(
                        isHorizontal: false,
                        containerLength: geo.size.height,
                        currentRatio: sessionManager.gridVerticalRatio,
                        onRatioChange: { sessionManager.gridVerticalRatio = $0; sessionManager.persistGridRatio() }
                    )

                    HStack(spacing: 6) {
                        ForEach(bottomRow) { session in
                            gridCell(session: session, width: geo.size.width / CGFloat(max(1, bottomRow.count)), height: botH)
                        }
                    }
                }
            }
        }
        // [Modern Curves 2026-04-21] 라운드 셀 외곽 패딩
        .padding(6)
    }

    private func gridCell(session: MultiChatSessionManager.ChatSession, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            let isSelectedCell = sessionManager.selectedChannelId == session.id
            // 채널 헤더
            HStack(spacing: 6) {
                // 선택된 셀: 채널 컬러 액센트 바
                if isSelectedCell {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(chatAvatarColor(for: session.id))
                        .frame(width: 3, height: 14)
                }

                ChatConnectionStatusBadge(state: session.chatViewModel.connectionState, compact: true)

                Text(session.channelName)
                    .font(DesignTokens.Typography.custom(size: 11, weight: isSelectedCell ? .bold : .semibold))
                    .foregroundStyle(
                        isSelectedCell
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)

                Spacer()

                Text("\(session.chatViewModel.messageCount)")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Button {
                    Task { await sessionManager.removeSession(channelId: session.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // 헤더 배경: 선택 시 채널 컬러 미세 틴트 추가
            .background(
                ZStack {
                    DesignTokens.Colors.surfaceElevated.opacity(0.85)
                    if isSelectedCell {
                        chatAvatarColor(for: session.id).opacity(0.12)
                    }
                }
                .clipShape(
                    .rect(
                        topLeadingRadius: DesignTokens.Radius.lg,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DesignTokens.Radius.lg,
                        style: .continuous
                    )
                )
            )

            Divider().opacity(DesignTokens.Opacity.divider)

            ChatMessagesView(viewModel: session.chatViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // P0-1: 그리드 모드 채팅 입력 — 일던 chat-only 이동 제거
            // · compact: true → 이모티콘 버튼 숨김 + 패딩/버튼 축소
            // · 최소 놈이 의미 있는 경우에만 표시(항상 표시 — 로그인 안된 경우도 안내 차원에서 유용)
            ChatInputView(viewModel: session.chatViewModel, compact: true, compactChannelHint: session.channelName)
        }
        .frame(width: width, height: height)
        .background(DesignTokens.Colors.surfaceBase)
        // [Modern Curves 2026-04-21] 멀티채팅 그리드 셀 — 8pt → 16pt continuous + 선택 글로우
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    sessionManager.selectedChannelId == session.id
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.75)
                        : DesignTokens.Glass.borderColor.opacity(0.55),
                    lineWidth: sessionManager.selectedChannelId == session.id ? 1.5 : DesignTokens.Border.thin
                )
        )
        .shadow(
            color: sessionManager.selectedChannelId == session.id
                ? DesignTokens.Colors.chzzkGreen.opacity(0.30) : .clear,
            radius: 10, y: 2
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // 그리드 셀 탭 → 통합 모드/사이드바 모드의 타겟 채널도 자연스럽게 움직이도록 선택 상태 동기
            sessionManager.selectChannel(session.id)
        }
    }

    // MARK: - Merged Layout (통합 타임라인)

    private var mergedLayout: some View {
        VStack(spacing: 0) {
            mergedToolbar
            Divider()

            if sessionManager.sessions.isEmpty {
                emptyState
            } else {
                MergedChatView(sessionManager: sessionManager)
            }
        }
    }

    private var mergedToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            layoutModePicker

            Spacer()

            Text("\(sessionManager.sessions.count)개 채널 통합")
                .font(DesignTokens.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            MSChipButton(
                icon: "plus",
                title: "채널 추가",
                style: .accent,
                isActive: true,
                action: { showAddChannel = true }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs + 1)
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }

    // MARK: - Layout Mode Picker

    private var layoutModePicker: some View {
        MSSegmentedSwitcher(
            items: MultiChatLayoutMode.allCases.map { mode in
                .init(id: mode, icon: mode.icon, title: nil, help: mode.label)
            },
            selection: Binding(
                get: { layoutMode },
                set: { newMode in
                    withAnimation(DesignTokens.Animation.snappy) { layoutMode = newMode }
                }
            )
        )
    }

    // MARK: - Channel Sidebar

    private var channelSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("멀티채팅")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                layoutModePicker

                Button {
                    showAddChannel = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 16))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.sm)
            .contentBackground()

            Divider()

            // Channel list
            if sessionManager.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.tertiary)
                    Text("채널을 추가하세요")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { sessionManager.selectedChannelId },
                    set: { id in if let id { sessionManager.selectChannel(id) } }
                )) {
                    ForEach(sessionManager.sessions) { session in
                        let isConnected = session.chatViewModel.connectionState.isConnected
                        let isCurrentlySelected = sessionManager.selectedChannelId == session.id
                        HStack(spacing: 10) {
                            // [Refined Classic 2026-04-22] 28pt 아바타 — specular 제거, 깨끗한 gradient.
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                chatAvatarColor(for: session.id),
                                                chatAvatarColor(for: session.id).opacity(0.55),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(String(session.channelName.prefix(1)).uppercased())
                                            .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                                    )
                                    .overlay(
                                        Circle().stroke(
                                            isConnected
                                                ? DesignTokens.Colors.chzzkGreen.opacity(0.75)
                                                : Color.white.opacity(0.08),
                                            lineWidth: isConnected ? 1.5 : 0.5
                                        )
                                    )

                                Circle()
                                    .fill(isConnected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.error)
                                    .frame(width: 9, height: 9)
                                    .overlay(
                                        Circle().stroke(DesignTokens.Colors.surfaceBase, lineWidth: 1.6)
                                    )
                                    .shadow(
                                        color: isConnected
                                            ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                                            : DesignTokens.Colors.error.opacity(0.4),
                                        radius: 2
                                    )
                                    .offset(x: 1, y: 1)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.channelName)
                                    .font(DesignTokens.Typography.custom(size: 11.5, weight: isCurrentlySelected ? .semibold : .medium))
                                    .foregroundStyle(
                                        isCurrentlySelected
                                            ? DesignTokens.Colors.textPrimary
                                            : DesignTokens.Colors.textSecondary
                                    )
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(isConnected ? "연결됨" : "연결 끊김")
                                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .medium))
                                        .foregroundStyle(
                                            isConnected
                                                ? DesignTokens.Colors.chzzkGreen.opacity(0.8)
                                                : DesignTokens.Colors.textTertiary
                                        )
                                    if session.chatViewModel.messageCount > 0 {
                                        Text("·")
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                        Text("\(session.chatViewModel.messageCount)")
                                            .font(DesignTokens.Typography.custom(size: 9.5, weight: .medium, design: .rounded))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .tag(session.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await sessionManager.removeSession(channelId: session.id) }
                            } label: {
                                Label("채널 제거", systemImage: "minus.circle")
                            }
                        }
                    }
                    .onMove { source, destination in
                        sessionManager.moveSession(from: source, to: destination)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()

            // Footer
            HStack {
                Text("\(sessionManager.sessions.count)개 채널")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await sessionManager.reconnectAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .disabled(sessionManager.sessions.isEmpty)
                .help("전체 재연결")

                Button(role: .destructive) {
                    Task { await sessionManager.disconnectAll() }
                } label: {
                    Text("전체 해제")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
                .disabled(sessionManager.sessions.isEmpty)
            }
            .padding(DesignTokens.Spacing.xs)
        }
        .background(DesignTokens.Colors.surfaceOverlay)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "멀티채팅",
            message: "좌측에서 채널을 추가하면\n여러 채널의 채팅을 동시에 볼 수 있습니다",
            actionTitle: "채널 추가",
            action: { showAddChannel = true },
            style: .page
        )
        .background(DesignTokens.Colors.surfaceOverlay)
    }

    // MARK: - Actions

    private func addChannel(channelId: String) async {
        // 세션 수 사전 체크
        guard sessionManager.canAddSession else {
            addChannelError = "최대 \(MultiChatSessionManager.maxSessions)개 채널까지 추가할 수 있습니다."
            return
        }

        guard let apiClient = appState.apiClient else { return }
        do {
            let liveDetail = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveDetail.chatChannelId else {
                addChannelError = "채널 '\(channelId)'은(는) 현재 방송 중이 아닙니다."
                return
            }
            let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let channelName = liveDetail.channel?.channelName ?? channelId
            let result = await sessionManager.addSession(
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
                addChannelError = "'\(channelName)' 채널은 이미 추가되어 있습니다."
            case .maxSessionsReached:
                addChannelError = "최대 \(MultiChatSessionManager.maxSessions)개 채널까지 추가할 수 있습니다."
            case .success, .connectionFailed:
                break
            }
        } catch {
            addChannelError = "채널 '\(channelId)'에 연결할 수 없습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - Avatar Color Helper

    private func chatAvatarColor(for channelId: String) -> Color {
        let palette: [Color] = [
            DesignTokens.Colors.accentBlue,
            DesignTokens.Colors.accentPurple,
            DesignTokens.Colors.accentPink,
            DesignTokens.Colors.accentOrange,
            DesignTokens.Colors.chzzkGreen,
        ]
        return palette[abs(channelId.hashValue) % palette.count]
    }
}
