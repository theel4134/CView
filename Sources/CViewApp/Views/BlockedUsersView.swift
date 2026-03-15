// MARK: - BlockedUsersView.swift
// CViewApp - 차단 사용자 관리 뷰

import SwiftUI
import CViewCore
import CViewChat

/// 차단된 사용자 목록 관리 뷰
struct BlockedUsersView: View {
    let chatVM: ChatViewModel?
    @State private var blockedUsers: Set<String> = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredUsers: [String] {
        let sorted = blockedUsers.sorted()
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.error)

                VStack(alignment: .leading, spacing: 2) {
                    Text("차단된 사용자")
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("\(blockedUsers.count)명 차단됨")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.title3)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                TextField("사용자 ID 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.captionMedium)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.xs)

            Divider()

            // List
            if filteredUsers.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: blockedUsers.isEmpty ? "face.smiling" : "magnifyingglass")
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(blockedUsers.isEmpty ? "차단된 사용자가 없습니다" : "검색 결과가 없습니다")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredUsers, id: \.self) { userId in
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.xmark")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.error.opacity(0.7))

                            Text(userId)
                                .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                Task {
                                    await chatVM?.unblockUser(userId)
                                    blockedUsers.remove(userId)
                                }
                            } label: {
                                Text("차단 해제")
                                    .font(DesignTokens.Typography.captionMedium)
                                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                                    .padding(.vertical, DesignTokens.Spacing.xxs)
                                    .background(DesignTokens.Colors.surfaceElevated)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 380, height: 420)
        .background(DesignTokens.Colors.backgroundElevated)
        .task {
            blockedUsers = await chatVM?.getBlockedUsers() ?? []
        }
    }
}
