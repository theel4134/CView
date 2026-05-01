// MARK: - Statistics/Components/EmptyStatePlaceholder.swift
// 통계 화면 공용 빈 상태 placeholder

import SwiftUI
import CViewCore
import CViewUI

struct EmptyStatePlaceholder: View {
    let icon: String
    let title: String
    let subtitle: String?
    var color: Color = DesignTokens.Colors.textTertiary

    @State private var appeared = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.surfaceBase)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(color)
            }
            Text(title)
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(DesignTokens.Animation.motionSafe(DesignTokens.Animation.spring)) {
                appeared = true
            }
        }
    }
}
