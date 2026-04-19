// MARK: - CViewUI/Components/EmptyStateView.swift
// 표준 Empty State 컴포넌트 — 8+ 파일에 흩어져 있던 emptyState 인라인 구현 통합
// docs/design-improvement-plan-2026-04.md §4.2 참조

import SwiftUI
import CViewCore

/// 빈 상태(Empty State) 표준 뷰
///
/// 사용 예시:
/// ```swift
/// // 1) 사이드 패널 / 컨텐츠 영역 (기본)
/// EmptyStateView(
///     icon: "bubble.left.and.bubble.right",
///     title: "멀티채팅",
///     message: "여러 채널의 채팅을 동시에\n모니터링할 수 있습니다",
///     actionTitle: "채널 추가",
///     action: { showAddChannel = true }
/// )
///
/// // 2) 좁은 영역 (탭 콘텐츠 등)
/// EmptyStateView(icon: "play.rectangle", title: "VOD가 없습니다", style: .inline)
///
/// // 3) 전체 화면
/// EmptyStateView(icon: "tv.slash", title: "라이브가 없습니다", style: .page)
/// ```
public struct EmptyStateView: View {

    /// 표시 스타일 — 영역 크기에 맞는 아이콘/타이포 프리셋
    public enum Style: Sendable {
        /// 큰 아이콘 + 제목/본문/액션 — 전체 화면, 메인 뷰 빈 상태
        case page
        /// 중간 — 사이드 패널, 사이드바, 시트 등 (기본)
        case panel
        /// 작은 아이콘 + 짧은 텍스트 — 탭 콘텐츠, 좁은 카드 내부
        case inline
    }

    /// SF Symbol 이름
    let icon: String
    /// 제목 — 항상 표시
    let title: String
    /// 부가 설명 — 옵션
    let message: String?
    /// 액션 버튼 라벨 — `action` 과 함께 지정 시에만 표시
    let actionTitle: String?
    /// 액션 클로저
    let action: (() -> Void)?
    /// 표시 스타일
    let style: Style

    public init(
        icon: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        style: Style = .panel
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.style = style
    }

    public var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: icon)
                .font(iconFont)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(messageFont)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: messageMaxWidth)
                }
            }

            if let actionTitle, let action {
                Button {
                    action()
                } label: {
                    Label(actionTitle, systemImage: "plus")
                        .font(actionFont)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.chzzkGreen)
                .controlSize(actionControlSize)
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(containerPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Style mapping

    private var spacing: CGFloat {
        switch style {
        case .page:   return DesignTokens.Spacing.lg
        case .panel:  return DesignTokens.Spacing.md
        case .inline: return DesignTokens.Spacing.sm
        }
    }

    private var containerPadding: CGFloat {
        switch style {
        case .page:   return DesignTokens.Spacing.xl
        case .panel:  return DesignTokens.Spacing.lg
        case .inline: return DesignTokens.Spacing.md
        }
    }

    private var iconFont: Font {
        switch style {
        case .page:   return DesignTokens.Typography.custom(size: 48, weight: .thin)
        case .panel:  return DesignTokens.Typography.custom(size: 36, weight: .thin)
        case .inline: return DesignTokens.Typography.custom(size: 28, weight: .thin)
        }
    }

    private var titleFont: Font {
        switch style {
        case .page:   return DesignTokens.Typography.title3Dynamic.weight(.bold)
        case .panel:  return DesignTokens.Typography.bodyDynamicSemibold
        case .inline: return DesignTokens.Typography.captionDynamicMedium
        }
    }

    private var titleColor: Color {
        switch style {
        case .page:   return DesignTokens.Colors.textPrimary
        case .panel:  return DesignTokens.Colors.textSecondary
        case .inline: return DesignTokens.Colors.textTertiary
        }
    }

    private var messageFont: Font {
        switch style {
        case .page:   return DesignTokens.Typography.bodyDynamic
        case .panel:  return DesignTokens.Typography.footnoteDynamic
        case .inline: return DesignTokens.Typography.captionDynamic
        }
    }

    private var messageMaxWidth: CGFloat {
        switch style {
        case .page:   return 360
        case .panel:  return 280
        case .inline: return 240
        }
    }

    private var actionFont: Font {
        switch style {
        case .page:   return DesignTokens.Typography.bodyDynamic.weight(.medium)
        case .panel:  return DesignTokens.Typography.footnoteDynamic.weight(.medium)
        case .inline: return DesignTokens.Typography.captionDynamicMedium
        }
    }

    private var actionControlSize: ControlSize {
        switch style {
        case .page:   return .regular
        case .panel:  return .small
        case .inline: return .small
        }
    }

    private var accessibilityText: String {
        if let message {
            return "\(title). \(message)"
        }
        return title
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Page") {
    EmptyStateView(
        icon: "tv.slash",
        title: "라이브 중인 채널이 없습니다",
        message: "팔로우한 채널이 라이브를 시작하면\n여기에서 바로 시청할 수 있어요",
        actionTitle: "채널 둘러보기",
        action: {},
        style: .page
    )
    .frame(width: 800, height: 600)
}

#Preview("Panel") {
    EmptyStateView(
        icon: "bubble.left.and.bubble.right",
        title: "멀티채팅",
        message: "여러 채널의 채팅을 동시에\n모니터링할 수 있습니다",
        actionTitle: "채널 추가",
        action: {},
        style: .panel
    )
    .frame(width: 320, height: 400)
}

#Preview("Inline") {
    EmptyStateView(icon: "play.rectangle", title: "VOD가 없습니다", style: .inline)
        .frame(width: 240, height: 200)
}
#endif
