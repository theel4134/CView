// MARK: - PlayerEngineBadge.swift
// CViewApp - 현재 재생 중인 플레이어 엔진 표시 뱃지 (LiveStreamView / MLVideoArea 공용)

import SwiftUI
import CViewCore

struct PlayerEngineBadge: View {
    let engineType: PlayerEngineType

    private var badgeLabel: String {
        switch engineType {
        case .vlc:      "VLC"
        case .avPlayer: "AVPlayer"
        case .hlsjs:    "HLS.js"
        }
    }

    private var accentColor: Color {
        switch engineType {
        case .vlc:      Color(red: 1.0, green: 0.55, blue: 0.0)   // VLC 오렌지
        case .avPlayer: Color(red: 0.24, green: 0.52, blue: 1.0)  // 시스템 블루
        case .hlsjs:    Color(red: 0.0, green: 0.78, blue: 0.55)  // 저지연 그린
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)
            Text(badgeLabel)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
    }
}
