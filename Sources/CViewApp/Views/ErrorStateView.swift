// MARK: - ErrorStateView.swift
// CViewApp - 에러/빈 상태 뷰

import SwiftUI
import CViewCore

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void

    @State private var appeared = false
    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.warning.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.warning)
            }

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("오류가 발생했습니다")
                    .font(DesignTokens.Typography.custom(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(message)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: retryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionSemibold)
                    Text("다시 시도")
                        .font(DesignTokens.Typography.captionSemibold)
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(isButtonHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.85) : DesignTokens.Colors.chzzkGreen)
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .clipShape(Capsule())
                .shadow(isButtonHovered ? DesignTokens.Shadow.glow : DesignTokens.Shadow.sm)
                .scaleEffect(isButtonHovered ? 1.03 : 1.0)
                .animation(DesignTokens.Animation.fast, value: isButtonHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isButtonHovered = hovering }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            withAnimation(DesignTokens.Animation.motionSafe(DesignTokens.Animation.spring)) {
                appeared = true
            }
        }
    }
}
