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
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.error)

                VStack(alignment: .leading, spacing: 2) {
                    Text("차단된 사용자")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("\(blockedUsers.count)명 차단됨")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                TextField("사용자 ID 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // List
            if filteredUsers.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: blockedUsers.isEmpty ? "face.smiling" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(blockedUsers.isEmpty ? "차단된 사용자가 없습니다" : "검색 결과가 없습니다")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredUsers, id: \.self) { userId in
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.xmark")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.error.opacity(0.7))

                            Text(userId)
                                .font(.system(size: 13, weight: .medium))
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
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.Colors.accentBlue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 380, height: 420)
        .background(DesignTokens.Colors.backgroundElevated)
        .task {
            blockedUsers = await chatVM?.getBlockedUsers() ?? []
        }
    }
}
