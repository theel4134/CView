// MARK: - MLSettingsSharedComponents.swift
// 멀티라이브 설정 — 공유 컴포넌트 (탭 버튼, 그리드 버튼)

import SwiftUI
import CViewCore

// MARK: - Settings Tab Button (with hover)

struct MLSettingsTabButton: View {
    let tab: MLSettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                Text(tab.rawValue)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
            }
            .foregroundStyle(
                isSelected
                    ? DesignTokens.Colors.chzzkGreen
                    : isHovered
                        ? DesignTokens.Colors.textSecondary
                        : DesignTokens.Colors.textTertiary
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(
                        isSelected
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                            : isHovered
                                ? DesignTokens.Colors.borderOnDarkMedia
                                : .clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}

// MARK: - Shared Grid Button (with hover)

struct MLSettingsGridButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(
                            isSelected
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                                : isHovered
                                    ? DesignTokens.Colors.borderOnDarkMedia
                                    : Color.gray.opacity(0.08)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(
                            isSelected
                                ? DesignTokens.Colors.chzzkGreen
                                : isHovered
                                    ? DesignTokens.Colors.borderOnDarkMediaStrong
                                    : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
