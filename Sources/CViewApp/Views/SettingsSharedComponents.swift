// MARK: - SettingsSharedComponents.swift
// Settings 탭 공유 컴포넌트 (SettingsView에서 추출)
// macOS System Settings 스타일 — Glass 카드 + 아이콘 + 현대적 레이아웃

import SwiftUI
import CViewCore

// MARK: - Settings Page Header

/// 설정 페이지 상단 타이틀 — 크고 굵은 현대적 헤더
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.subhead)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.bottom, DesignTokens.Spacing.xs)
    }
}

// MARK: - Settings Section

/// 설정 섹션 컨테이너 — 아이콘 헤더 + Glass 카드
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더 — 아이콘 + 텍스트
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.sm)

            // 내용 카드 — ultraThinMaterial Glass 효과
            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
}

// MARK: - Settings Section Footer

/// 섹션 카드 아래 보충 설명 텍스트
struct SettingsSectionFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.footnote)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.top, DesignTokens.Spacing.xs)
    }
}

// MARK: - Settings Row

/// 설정 행 — 아이콘 + 라벨 + 컨트롤, 현대적 tinted icon 스타일
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
        HStack(spacing: DesignTokens.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 26, height: 26)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let description {
                    Text(description)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, 11)
    }
}

// MARK: - Row Divider

struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 54) // lg(16) + icon(26) + md(12) = 54 — 텍스트 시작점 정렬
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
