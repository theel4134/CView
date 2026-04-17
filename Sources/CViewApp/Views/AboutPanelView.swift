// MARK: - AboutPanelView.swift
// CView 정보 패널

import SwiftUI
import CViewCore

struct AboutPanelView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            // 앱 아이콘
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            // 앱 이름 & 버전
            VStack(spacing: 4) {
                Text("CView")
                    .font(DesignTokens.Typography.custom(size: 24, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text("v\(appVersion) (\(buildNumber))")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            // 설명
            Text("치지직 라이브 스트리밍 뷰어")
                .font(DesignTokens.Typography.custom(size: 13, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            // 시스템 정보
            VStack(spacing: 4) {
                Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            Button("닫기") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 320, height: 360)
        .background(DesignTokens.Colors.surfaceBase)
    }
}
