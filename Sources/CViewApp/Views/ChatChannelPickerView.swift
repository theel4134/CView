// MARK: - ChatChannelPickerView.swift
// CViewApp - 채널 검색/추가 공유 시트
// MultiChatView와 FollowingView+MultiChat에서 공통 사용

import SwiftUI
import CViewCore
import CViewNetworking
import CViewUI

/// 채널 검색 + 추가 시트 (공유 컴포넌트)
struct ChatChannelPickerView: View {
    let apiClient: ChzzkAPIClient?
    let onChannelSelected: (String) async -> Void
    let onDismiss: () -> Void
    var sheetWidth: CGFloat = 360

    @State private var searchQuery = ""
    @State private var directChannelId = ""
    @State private var searchResults: [ChannelInfo] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("채팅 채널 추가")
                .font(.system(size: 15, weight: .semibold))

            // 검색 바
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널명 검색 또는 채널 ID 입력", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .onSubmit { searchChannels() }
                if isSearching {
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
            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(searchResults) { channel in
                            Button {
                                Task {
                                    await onChannelSelected(channel.channelId)
                                    searchQuery = ""
                                    searchResults = []
                                    onDismiss()
                                }
                            } label: {
                                channelRow(channel)
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
                TextField("채널 ID 직접 입력", text: $directChannelId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("추가") {
                    let channelId = directChannelId.trimmingCharacters(in: .whitespaces)
                    guard !channelId.isEmpty else { return }
                    Task {
                        await onChannelSelected(channelId)
                        directChannelId = ""
                        onDismiss()
                    }
                }
                .disabled(directChannelId.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button("취소") {
                    searchQuery = ""
                    directChannelId = ""
                    searchResults = []
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: sheetWidth)
    }

    // MARK: - Channel Row

    private func channelRow(_ channel: ChannelInfo) -> some View {
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

    // MARK: - Search

    private func searchChannels() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let apiClient else { return }
        isSearching = true
        Task {
            do {
                let result = try await apiClient.searchChannels(keyword: query, size: 10)
                searchResults = result.data
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }
}
