// MARK: - MultiChatView.swift
// CViewApp - 멀티채팅 뷰
// 여러 채널의 채팅을 동시에 표시

import SwiftUI
import CViewCore
import CViewNetworking
import CViewUI

/// 멀티채팅 뷰 - 사이드바(채널 목록) + 메인(선택된 채널 채팅)
struct MultiChatView: View {
    @Environment(AppState.self) private var appState
    @State private var sessionManager = MultiChatSessionManager()
    @State private var showAddChannel = false
    @State private var showChatSettings = false
    @State private var addChannelError: String?
    @State private var newChannelId = ""
    @State private var channelSearchQuery = ""
    @State private var channelSearchResults: [ChannelInfo] = []
    @State private var isSearchingChannels = false

    var body: some View {
        HSplitView {
            // 채널 사이드바
            channelSidebar
                .frame(minWidth: 160, maxWidth: 220)

            // 선택된 채널 채팅
            if let session = sessionManager.selectedSession {
                ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: { showChatSettings = true })
            } else {
                emptyState
            }
        }
        .frame(minWidth: 500, minHeight: 400)
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
            .background(DesignTokens.Colors.background)

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
        .background(DesignTokens.Colors.backgroundElevated)
        .sheet(isPresented: $showAddChannel) {
            addChannelSheet
        }
    }

    // MARK: - Add Channel Sheet

    private var addChannelSheet: some View {
        VStack(spacing: 16) {
            Text("채널 추가")
                .font(.headline)

            // 채널 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널명 검색 또는 채널 ID 입력", text: $channelSearchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.captionMedium)
                    .onSubmit { searchChannels() }
                if isSearchingChannels {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                    )
            )

            // 검색 결과
            if !channelSearchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(channelSearchResults) { channel in
                            Button {
                                Task {
                                    await addChannel(channelId: channel.channelId)
                                    channelSearchQuery = ""
                                    channelSearchResults = []
                                    showAddChannel = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if let url = channel.channelImageURL {
                                        CachedAsyncImage(url: url) {
                                            Circle().fill(DesignTokens.Colors.surfaceElevated)
                                        }
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    } else {
                                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                                            .frame(width: 32, height: 32)
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .font(DesignTokens.Typography.caption)
                                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                            }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(channel.channelName)
                                            .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        Text("팔로워 \(channel.followerCount.formatted())")
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
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

            // 채널 ID 직접 입력
            HStack(spacing: 8) {
                TextField("채널 ID 직접 입력", text: $newChannelId)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.caption)
                Button("추가") {
                    let channelId = newChannelId.trimmingCharacters(in: .whitespaces)
                    guard !channelId.isEmpty else { return }
                    Task {
                        await addChannel(channelId: channelId)
                        newChannelId = ""
                        showAddChannel = false
                    }
                }
                .disabled(newChannelId.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button("취소") {
                    newChannelId = ""
                    channelSearchQuery = ""
                    channelSearchResults = []
                    showAddChannel = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 360)
    }

    private func searchChannels() {
        let query = channelSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let apiClient = appState.apiClient else { return }
        isSearchingChannels = true
        Task {
            do {
                let result = try await apiClient.searchChannels(keyword: query, size: 10)
                channelSearchResults = result.data
            } catch {
                channelSearchResults = []
            }
            isSearchingChannels = false
        }
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
        .background(DesignTokens.Colors.backgroundElevated)
    }

    // MARK: - Actions

    private func addChannel(channelId: String) async {
        guard let apiClient = appState.apiClient else { return }
        do {
            let liveDetail = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveDetail.chatChannelId else { return }
            let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let channelName = liveDetail.channel?.channelName ?? channelId
            await sessionManager.addSession(
                channelId: channelId,
                channelName: channelName,
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken
            )
        } catch {
            await MainActor.run {
                addChannelError = "채널 '\(channelId)'에 연결할 수 없습니다: \(error.localizedDescription)"
            }
        }
    }
}
