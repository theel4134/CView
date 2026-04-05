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
    @State private var hoveredAction: String?

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
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .frame(width: 56, height: 56)
                        Image(systemName: "person.circle.fill")
                            .font(DesignTokens.Typography.custom(size: 48))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.5))
                    }
                }

                Text(message.nickname)
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                // 역할 표시
                if let roleLabel = message.userRole.displayLabel,
                   let roleIcon = message.userRole.iconName {
                    HStack(spacing: 4) {
                        Image(systemName: roleIcon)
                            .font(.system(size: 10, weight: .bold))
                        Text(roleLabel)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(message.userRole == .streamer
                        ? DesignTokens.Colors.chzzkGreen
                        : Color(hex: 0x5C9DFF))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (message.userRole == .streamer
                            ? DesignTokens.Colors.chzzkGreen
                            : Color(hex: 0x5C9DFF)).opacity(0.12),
                        in: Capsule()
                    )
                }

                // 칭호 표시
                if let titleName = message.titleName, !titleName.isEmpty {
                    let titleCol: Color = {
                        if let hex = message.titleColor,
                           let val = UInt(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
                            return Color(hex: val)
                        }
                        return DesignTokens.Colors.textSecondary
                    }()
                    Text(titleName)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        .foregroundStyle(titleCol)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(titleCol.opacity(0.12), in: Capsule())
                }

                // 뱃지 목록
                if !message.badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(message.badges.prefix(5).enumerated()), id: \.offset) { _, badge in
                            if let url = badge.imageURL {
                                CachedAsyncImage(url: url) {
                                    EmptyView()
                                }
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }

                Text(message.userId)
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider().opacity(0.3)

            // Actions
            VStack(spacing: 2) {
                profileActionButton(label: "닉네임 복사", icon: "doc.on.doc", id: "copy-nick") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.nickname, forType: .string)
                    dismiss()
                }

                profileActionButton(label: "메시지 복사", icon: "text.bubble", id: "copy-msg") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    dismiss()
                }

                profileActionButton(label: "치지직에서 열기", icon: "safari", id: "open-chzzk") {
                    if let url = URL(string: "https://chzzk.naver.com/live/\(message.userId)") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }

                Divider().opacity(0.2)
                    .padding(.vertical, DesignTokens.Spacing.xxs)

                Button {
                    Task { await chatVM?.blockUser(message.userId) }
                    dismiss()
                } label: {
                    Label("차단", systemImage: "person.fill.xmark")
                        .font(DesignTokens.Typography.captionMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(hoveredAction == "block" ? DesignTokens.Colors.error.opacity(0.12) : DesignTokens.Colors.error.opacity(0.05))
                )
                .onHover { hoveredAction = $0 ? "block" : nil }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 260)
        .background(DesignTokens.Colors.surfaceOverlay)
    }

    private func profileActionButton(label: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(DesignTokens.Typography.captionMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(hoveredAction == id ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hoveredAction = $0 ? id : nil }
    }
}
