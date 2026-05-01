// MARK: - Statistics/Components/SectionHeader.swift
// 통계 섹션 헤더 (아이콘 + 제목 + 옵션 액션 버튼)

import SwiftUI
import CViewCore
import CViewUI

struct StatSectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    var trailing: AnyView?

    init(_ title: String, icon: String, color: Color, trailing: AnyView? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            trailing
        }
    }
}

/// 통계 섹션 — 헤더 + 컨텐츠 wrapper
struct StatSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let trailing: AnyView?
    @ViewBuilder let content: () -> Content

    init(_ title: String, icon: String, color: Color, trailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            StatSectionHeader(title, icon: icon, color: color, trailing: trailing)
            content()
        }
    }
}
