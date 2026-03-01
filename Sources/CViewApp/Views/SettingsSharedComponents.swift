// MARK: - SettingsSharedComponents.swift
// Settings 탭 공유 컴포넌트 (SettingsView에서 추출)

import SwiftUI
import CViewCore

/// 설정 섹션 컨테이너
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxs)
            .padding(.bottom, DesignTokens.Spacing.xs)

            // 내용 카드
            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
            }
        }
    }
}

/// 설정 행 - 레이블 + 컨트롤
struct SettingsRow<Control: View>: View {
    let label: String
    let description: String?
    let icon: String?
    let iconColor: Color
    @ViewBuilder let control: () -> Control

    init(
        _ label: String,
        description: String? = nil,
        icon: String? = nil,
        iconColor: Color = DesignTokens.Colors.textSecondary,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.description = description
        self.icon = icon
        self.iconColor = iconColor
        self.control = control
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let description {
                    Text(description)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(DesignTokens.Glass.borderOpacityLight))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }
}

/// SettingsView 내 태그 흐름 레이아웃 (차단 키워드용)
struct SettingsFlowTagView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        SettingsFlexibleLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                    Button { onRemove(tag) } label: {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.accentBlue.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(DesignTokens.Colors.accentBlue.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
    }
}

struct SettingsFlexibleLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowH + verticalSpacing; x = 0; rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + verticalSpacing; x = bounds.minX; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
    }
}
