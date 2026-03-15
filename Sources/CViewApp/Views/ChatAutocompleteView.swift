// MARK: - ChatAutocompleteView.swift
// CViewApp - 채팅 입력 자동완성 팝업

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Chat Autocomplete Popup

/// 채팅 입력창 위에 표시되는 자동완성 제안 팝업
/// `:` 이모티콘 / `@` 멘션 자동완성
struct ChatAutocompleteView: View {
    let viewModel: ChatViewModel
    let onSelect: (Int) -> Void

    private var isEmoticonMode: Bool { !viewModel.emoticonSuggestions.isEmpty }
    private var totalCount: Int {
        isEmoticonMode ? viewModel.emoticonSuggestions.count : viewModel.mentionSuggestions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 — Glass
            HStack(spacing: 6) {
                Image(systemName: isEmoticonMode ? "face.smiling" : "at")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text(isEmoticonMode ? "이모티콘" : "멘션")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("↑↓ 이동 · Tab/Enter 선택 · Esc 닫기")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated)

            Rectangle()
                .fill(DesignTokens.Glass.borderColorLight)
                .frame(height: 0.5)

            // 제안 목록
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        if isEmoticonMode {
                            ForEach(Array(viewModel.emoticonSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                emoticonRow(suggestion, index: index)
                                    .id(index)
                            }
                        } else {
                            ForEach(Array(viewModel.mentionSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                mentionRow(suggestion, index: index)
                                    .id(index)
                            }
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                }
                .onChange(of: viewModel.autocompleteSelectedIndex) { _, newIndex in
                    withAnimation(DesignTokens.Animation.micro) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: min(CGFloat(totalCount) * 36 + 32, 220))
        .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .shadow(color: .black.opacity(0.3), radius: 16, y: -6)
    }

    // MARK: - Emoticon Row

    private func emoticonRow(_ suggestion: EmoticonSuggestion, index: Int) -> some View {
        let isSelected = index == viewModel.autocompleteSelectedIndex
        return Button {
            onSelect(index)
        } label: {
            HStack(spacing: 10) {
                // 이모티콘 미리보기 이미지
                if let url = suggestion.imageURL {
                    CachedAsyncImage(url: url) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                    }
                    .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "face.smiling")
                        .font(DesignTokens.Typography.custom(size: 16))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 24, height: 24)
                }

                // 이모티콘 이름
                Text(suggestion.displayName)
                    .font(DesignTokens.Typography.custom(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                // 패턴 힌트
                Text(suggestion.chatPattern)
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mention Row

    private func mentionRow(_ suggestion: MentionSuggestion, index: Int) -> some View {
        let isSelected = index == viewModel.autocompleteSelectedIndex
        return Button {
            onSelect(index)
        } label: {
            HStack(spacing: 10) {
                // 프로필 이미지 또는 기본 아이콘
                if let urlStr = suggestion.profileImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        Circle()
                            .fill(DesignTokens.Colors.surfaceElevated)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(DesignTokens.Typography.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                }

                // 닉네임
                Text(suggestion.nickname)
                    .font(DesignTokens.Typography.custom(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                // @멘션 힌트
                Text("@\(suggestion.nickname)")
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
