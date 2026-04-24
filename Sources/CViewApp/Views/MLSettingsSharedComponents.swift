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

// MARK: - Settings Side Nav Button (vertical list)

/// 세로 내비게이션용 탭 버튼.
/// - 활성: 좌측 네온 그린 인디케이터 바 + 엷은 그린 틴트 배경 + 그린 아이콘/라벨
/// - 호버: 엷은 surface 배경
/// - 기본: 투명 + 3차 텍스트 컬러
struct MLSettingsSideNavButton: View {
    let tab: MLSettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // 좌측 인디케이터 바 — 활성 시에만 Chzzk 그린으로 표시
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? DesignTokens.Colors.chzzkGreen : Color.clear)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 2)

                VStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    Text(tab.rawValue)
                        .font(DesignTokens.Typography.custom(size: 10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xs + 1)
                .padding(.trailing, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }

    private var foregroundColor: Color {
        if isSelected { return DesignTokens.Colors.chzzkGreen }
        if isHovered  { return DesignTokens.Colors.textSecondary }
        return DesignTokens.Colors.textTertiary
    }

    private var backgroundColor: Color {
        if isSelected { return DesignTokens.Colors.chzzkGreen.opacity(0.10) }
        if isHovered  { return DesignTokens.Colors.surfaceElevated.opacity(0.6) }
        return .clear
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
