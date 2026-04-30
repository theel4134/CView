// MARK: - KeyboardShortcutsHelpView.swift
// 키보드 단축키 도움말 시트

import SwiftUI
import CViewCore

struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // ── 헤더 ──
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("키보드 단축키")
                    .font(DesignTokens.Typography.title)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    shortcutSection("일반", shortcuts: [
                        ("⌘K", "커맨드 팔레트"),
                        ("⌘N", "새 플레이어 창"),
                        ("⌘,", "설정"),
                        ("⌘/", "단축키 도움말"),
                    ])

                    shortcutSection("탐색", shortcuts: [
                        ("⌘1", "홈"),
                        ("⌘2", "라이브"),
                        ("⌘3", "카테고리"),
                        ("⌘4", "검색"),
                        ("⌘5", "클립"),
                        ("⌘6", "최근/즐겨찾기"),
                        ("⌘[", "뒤로 가기"),
                    ])

                    shortcutSection("스트림", shortcuts: [
                        ("⌘R", "새로고침"),
                        ("⌘S", "스크린샷"),
                        ("⌃⌘F", "전체 화면"),
                        ("⇧⌘F", "플레이어 전체 화면"),
                    ])

                    shortcutSection("재생", shortcuts: [
                        ("Space", "재생/일시정지"),
                        ("M", "음소거 토글"),
                        ("↑", "볼륨 올리기"),
                        ("↓", "볼륨 내리기"),
                        ("⌥⌘P", "PiP 토글"),
                    ])

                    shortcutSection("채팅", shortcuts: [
                        ("⇧⌘K", "채팅 지우기"),
                        ("⌘J", "자동 스크롤 토글"),
                        ("⇧⌘C", "채팅 독립 창"),
                        ("⇧⌘M", "멀티채팅"),
                    ])

                    shortcutSection("윈도우", shortcuts: [
                        ("⇧⌘T", "통계 창"),
                        ("⌥⌘N", "네트워크 모니터"),
                    ])
                }
                .padding()
            }
        }
        .frame(width: 420, height: 520)
        .background(DesignTokens.Colors.surfaceBase)
    }

    @ViewBuilder
    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            ForEach(shortcuts, id: \.1) { key, label in
                HStack {
                    Text(label)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Text(key)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignTokens.Colors.surfaceElevated)
                        )
                }
            }
        }
    }
}
