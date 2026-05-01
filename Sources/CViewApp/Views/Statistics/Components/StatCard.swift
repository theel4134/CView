// MARK: - Statistics/Components/StatCard.swift
// 기존 StatCard — 통계 폴더로 이동 (시그니처 그대로)
// 다른 통계 탭에서 단순 KPI 표시용으로 계속 사용한다.
// 신규 KPICard (서브라벨·sparkline·상태칩 지원)와 병행 사용한다.

import SwiftUI
import CViewCore
import CViewUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 17))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(DesignTokens.Typography.custom(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered ? color.opacity(0.3) : DesignTokens.Glass.borderColor,
                    lineWidth: isHovered ? 1 : 0.5
                )
        }
        // Metal 3: hover scaleEffect 제거 — GPU texture scale 연산 방지
        .animation(DesignTokens.Animation.smooth, value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
    }
}
