// MARK: - ChannelMemoSheet.swift
// CViewApp - 채널 메모 편집 시트

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Channel Memo Sheet

struct ChannelMemoSheet: View {
    let channelName: String
    @Binding var memo: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedMemo: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(DesignTokens.Colors.warning)
                Text(channelName)
                    .font(DesignTokens.Typography.subheadSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(DesignTokens.Spacing.lg)

            Divider().background(.white.opacity(DesignTokens.Glass.borderOpacityLight))

            TextEditor(text: $editedMemo)
                .font(DesignTokens.Typography.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(DesignTokens.Spacing.sm)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(focused ? Color.orange.opacity(0.6) : .white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 1)
                )
                .focused($focused)
                .padding(DesignTokens.Spacing.lg)

            HStack {
                Spacer()
                Text("\(editedMemo.count)자")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xs)

            Divider().background(.white.opacity(DesignTokens.Glass.borderOpacityLight))

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
                    .buttonStyle(.bordered)

                Button("저장") {
                    onSave(editedMemo)
                    memo = editedMemo
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(width: 480, height: 360)
        .background(DesignTokens.Colors.background)
        .onAppear {
            editedMemo = memo
            focused = true
        }
    }
}
