// MARK: - ChatUserProfileSheet.swift
// CViewApp - 채팅 사용자 프로필 팝업 시트

import SwiftUI
import CViewCore
import CViewUI

/// 채팅에서 닉네임 클릭 시 표시되는 사용자 프로필 시트
struct ChatUserProfileSheet: View {
    let message: ChatMessageItem
    let chatVM: ChatViewModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Profile header
            VStack(spacing: 8) {
                if let urlString = message.profileImageUrl, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) {
                        Image(systemName: "person.circle.fill")
                            .font(DesignTokens.Typography.custom(size: 48))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 48))
                        .foregroundStyle(.secondary)
                }

                Text(message.nickname)
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text("ID: \(message.userId)")
                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            VStack(spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.nickname, forType: .string)
                    dismiss()
                } label: {
                    Label("닉네임 복사", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                Button {
                    if let url = URL(string: "https://chzzk.naver.com/live/\(message.userId)") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                } label: {
                    Label("치지직에서 열기", systemImage: "safari")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                Divider()
                    .padding(.vertical, DesignTokens.Spacing.xxs)

                Button(role: .destructive) {
                    Task { await chatVM?.blockUser(message.userId) }
                    dismiss()
                } label: {
                    Label("차단", systemImage: "person.fill.xmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
                .buttonStyle(.plain)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 260)
        .background(DesignTokens.Colors.backgroundElevated)
    }
}
