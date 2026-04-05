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
        HStack(spacing: 8) {
            layoutModePicker

            Spacer()

            Text("\(sessionManager.sessions.count)개 채널")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Button { showAddChannel = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            .buttonStyle(.plain)

            Button { Task { await sessionManager.reconnectAll() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            .buttonStyle(.plain)
            .disabled(sessionManager.sessions.isEmpty)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceOverlay)
    }

    private var gridContent: some View {
        GeometryReader { geo in
            let sessions = sessionManager.sessions
            let count = sessions.count

            if count == 1 {
                gridCell(session: sessions[0], width: geo.size.width, height: geo.size.height)
            } else if count == 2 {
                // 2개: 좌우 분할 + 리사이즈 디바이더
                let leftW = geo.size.width * sessionManager.gridHorizontalRatio
                HStack(spacing: 0) {
                    gridCell(session: sessions[0], width: leftW, height: geo.size.height)
                    MLResizeDivider(
                        isHorizontal: true,
                        containerLength: geo.size.width,
                        currentRatio: sessionManager.gridHorizontalRatio,
                        onRatioChange: { sessionManager.gridHorizontalRatio = $0 }
                    )
                    gridCell(session: sessions[1], width: geo.size.width - leftW, height: geo.size.height)
                }
            } else if count >= 3 {
                // 3~4개: 상하 분할 (각 행은 좌우 균등)
                let topH = geo.size.height * sessionManager.gridVerticalRatio
                let botH = geo.size.height - topH
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        ForEach(0..<min(2, count), id: \.self) { i in
                            gridCell(session: sessions[i], width: geo.size.width / CGFloat(min(2, count)), height: topH)
                        }
                    }
                    .frame(height: topH)

                    MLResizeDivider(
                        isHorizontal: false,
                        containerLength: geo.size.height,
                        currentRatio: sessionManager.gridVerticalRatio,
                        onRatioChange: { sessionManager.gridVerticalRatio = $0 }
                    )

                    HStack(spacing: 1) {
                        let bottomSessions = Array(sessions.dropFirst(2))
                        ForEach(0..<bottomSessions.count, id: \.self) { i in
                            gridCell(session: bottomSessions[i], width: geo.size.width / CGFloat(bottomSessions.count), height: botH)
                        }
                    }
                }
            }
        }
    }

    private func gridCell(session: MultiChatSessionManager.ChatSession, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 채널 헤더
            HStack(spacing: 6) {
                Circle()
                    .fill(session.chatViewModel.connectionState.isConnected
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.error)
                    .frame(width: 5, height: 5)

                Text(session.channelName)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surfaceBase)

            Divider().opacity(DesignTokens.Opacity.divider)

            ChatMessagesView(viewModel: session.chatViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .background(DesignTokens.Colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: DesignTokens.Border.thin)
        )
    }

    private func gridColumns(for count: Int) -> Int {
        switch count {
        case 1:    return 1
        case 2:    return 2
        case 3, 4: return 2
        default:   return min(4, count)
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
        HStack(spacing: 8) {
            layoutModePicker

            Spacer()

            Text("\(sessionManager.sessions.count)개 채널 통합")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Button { showAddChannel = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceOverlay)
    }

    // MARK: - Layout Mode Picker

    private var layoutModePicker: some View {
        HStack(spacing: 2) {
            ForEach(MultiChatLayoutMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        layoutMode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(layoutMode == mode
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.textTertiary)
                        .frame(width: 26, height: 22)
                        .background(
                            layoutMode == mode
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(2)
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
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
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.chatViewModel.connectionState.isConnected
                                    ? DesignTokens.Colors.chzzkGreen
                                    : DesignTokens.Colors.error)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.channelName)
                                    .font(DesignTokens.Typography.captionMedium)
                                    .lineLimit(1)

                                Text("\(session.chatViewModel.messageCount)개 메시지")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
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
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(DesignTokens.Typography.custom(size: 40))
                .foregroundStyle(.tertiary)

            Text("멀티채팅")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("좌측에서 채널을 추가하면\n여러 채널의 채팅을 동시에 볼 수 있습니다")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showAddChannel = true
            } label: {
                Label("채널 추가", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                accessToken: tokenInfo.accessToken
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
            await MainActor.run {
                addChannelError = "채널 '\(channelId)'에 연결할 수 없습니다: \(error.localizedDescription)"
            }
        }
    }
}
