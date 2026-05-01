// MARK: - CViewCore/DesignSystem/DesignTokens+Modifiers.swift
// Dark Glass 디자인 시스템 v2 — ViewModifier, ButtonStyle, View Extensions

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Glass Card Modifier (Real Glassmorphism)
// ═══════════════════════════════════════════════════════════════════

/// 진짜 Glass 카드 — Material blur + 미세 테두리 + 그림자
public struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let borderOpacity: Double
    let hasShadow: Bool

    public init(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        material: Material = .thinMaterial,
        borderOpacity: Double = DesignTokens.Glass.borderOpacity,
        hasShadow: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.borderOpacity = borderOpacity
        self.hasShadow = hasShadow
    }

    public func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: hasShadow ? DesignTokens.Shadow.card.color : .clear,
                radius: hasShadow ? DesignTokens.Shadow.card.radius : 0,
                y: hasShadow ? DesignTokens.Shadow.card.y : 0
            )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Surface Card Modifier (Solid Surface)
// ═══════════════════════════════════════════════════════════════════

/// 솔리드 서피스 카드 — 단색 표면 + 테두리
public struct SurfaceCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fillColor: Color
    let border: Bool

    public init(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        fillColor: Color = DesignTokens.Colors.surfaceBase,
        border: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.border = border
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
            }
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: DesignTokens.Shadow.card.color,
                radius: DesignTokens.Shadow.card.radius,
                y: DesignTokens.Shadow.card.y
            )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Hover Card Modifier (60fps Spring)
// ═══════════════════════════════════════════════════════════════════

/// 호버 카드 효과 — scale + shadow spring 애니메이션
public struct HoverCardModifier: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat
    let scaleEffect: CGFloat

    public init(cornerRadius: CGFloat = DesignTokens.Radius.md, scaleEffect: CGFloat = 1.015) {
        self.cornerRadius = cornerRadius
        self.scaleEffect = scaleEffect
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scaleEffect : 1.0)
            // shadow 제거 — GPU blur 재계산 방지 (기본 카드에 이미 shadow 존재)
            .animation(DesignTokens.Animation.micro, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Glow Border Modifier
// ═══════════════════════════════════════════════════════════════════

/// 액센트 글로우 테두리
public struct GlowBorderModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let isActive: Bool

    public init(
        color: Color = DesignTokens.Colors.chzzkGreen,
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        isActive: Bool = true
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color.opacity(0.4), lineWidth: 1)
                }
            }
            .shadow(
                color: isActive ? color.opacity(0.15) : .clear,
                radius: isActive ? 8 : 0
            )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Pill Button Style
// ═══════════════════════════════════════════════════════════════════

/// Pill(캡슐) 모양 버튼 스타일
public struct PillButtonStyle: ButtonStyle {
    let fillColor: Color
    let textColor: Color
    let isCompact: Bool

    public init(
        fillColor: Color = DesignTokens.Colors.chzzkGreen,
        textColor: Color = DesignTokens.Colors.onPrimary,
        isCompact: Bool = false
    ) {
        self.fillColor = fillColor
        self.textColor = textColor
        self.isCompact = isCompact
    }

    @State private var isHovered = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? DesignTokens.Typography.captionMedium : DesignTokens.Typography.bodyMedium)
            .foregroundStyle(textColor)
            .padding(.horizontal, isCompact ? DesignTokens.Spacing.md : DesignTokens.Spacing.lg)
            .padding(.vertical, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
            .background(fillColor.opacity(isHovered ? 0.85 : 1.0), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .animation(DesignTokens.Animation.fast, value: isHovered)
            .customCursor(.pointingHand)
    }
}

/// Ghost Pill 스타일 — 테두리만
public struct GhostPillButtonStyle: ButtonStyle {
    let borderColor: Color
    let textColor: Color
    let isCompact: Bool

    public init(
        borderColor: Color = DesignTokens.Colors.border,
        textColor: Color = DesignTokens.Colors.textPrimary,
        isCompact: Bool = false
    ) {
        self.borderColor = borderColor
        self.textColor = textColor
        self.isCompact = isCompact
    }

    @State private var isHovered = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? DesignTokens.Typography.captionMedium : DesignTokens.Typography.bodyMedium)
            .foregroundStyle(textColor)
            .padding(.horizontal, isCompact ? DesignTokens.Spacing.md : DesignTokens.Spacing.lg)
            .padding(.vertical, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
            .background(
                Capsule()
                    .strokeBorder(isHovered ? borderColor.opacity(0.8) : borderColor, lineWidth: isHovered ? 1.0 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .animation(DesignTokens.Animation.fast, value: isHovered)
            .customCursor(.pointingHand)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Section Header
// ═══════════════════════════════════════════════════════════════════

/// 통일된 섹션 헤더
public struct SectionHeaderView: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionLabel: String?

    public init(_ title: String, subtitle: String? = nil, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionLabel = actionLabel
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(GhostPillButtonStyle(isCompact: true))
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - View Extensions
// ═══════════════════════════════════════════════════════════════════

extension View {
    /// Glass 카드 스타일 (진짜 Material blur)
    public func glassCard(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        material: Material = .thinMaterial,
        borderOpacity: Double = DesignTokens.Glass.borderOpacity,
        hasShadow: Bool = true
    ) -> some View {
        modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            material: material,
            borderOpacity: borderOpacity,
            hasShadow: hasShadow
        ))
    }

    /// 솔리드 서피스 카드 스타일
    public func surfaceCard(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        fillColor: Color = DesignTokens.Colors.surfaceBase,
        border: Bool = true
    ) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, fillColor: fillColor, border: border))
    }

    /// 호버 카드 효과
    public func hoverCard(cornerRadius: CGFloat = DesignTokens.Radius.md, scale: CGFloat = 1.015) -> some View {
        modifier(HoverCardModifier(cornerRadius: cornerRadius, scaleEffect: scale))
    }

    /// 액센트 글로우 테두리
    public func glowBorder(
        color: Color = DesignTokens.Colors.chzzkGreen,
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        isActive: Bool = true
    ) -> some View {
        modifier(GlowBorderModifier(color: color, cornerRadius: cornerRadius, isActive: isActive))
    }

    /// ShadowStyle 적용
    public func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Glass 배경 (간편)
    public func glassBackground(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        material: Material = .thinMaterial
    ) -> some View {
        self.background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 메인 콘텐츠 배경 — 라이트 모드에서 미묘한 깊이감 그라디언트 + 배경색
    public func contentBackground() -> some View {
        self.background {
            ZStack {
                DesignTokens.Colors.background
                // 라이트 모드에서 미묘한 쿨 그라디언트 효과
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.surfaceBase.opacity(0.3),
                        Color.clear,
                        DesignTokens.Colors.surfaceElevated.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }

    /// 커서 변경 — 인터랙티브 요소에 포인팅 핸드 등 커서 표시
    public func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active: cursor.push()
            case .ended:  NSCursor.pop()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════
    // MARK: - Menu Top Chrome
    // [Add 2026-05-01] 모든 메뉴 화면(라이브/카테고리/검색/메트릭/설정 등)의
    // 상단 영역에 적용하는 통일 디자인 언어. 색감 wash 대신 본문 배경으로
    // 자연스럽게 흡수되는 수직 페이드 + 좌·우 끝에서 사라지는 hairline
    // 디바이더로 시각 단절을 최소화한다.
    // ═════════════════════════════════════════════════════════════════

    /// 메뉴 상단 크롬 — `surfaceBase` 수직 페이드 + 페이드 hairline 디바이더.
    ///
    /// - Parameter showsDivider: 하단 페이드 hairline 표시 여부 (기본 `true`).
    ///   본문이 같은 surface 톤이면 `false` 로 두어 완전한 연속성을 만들 수 있다.
    public func menuTopChrome(showsDivider: Bool = true) -> some View {
        self.modifier(MenuTopChromeModifier(showsDivider: showsDivider))
    }
}

/// 메뉴 상단 영역에 통일 적용하는 ViewModifier.
///
/// 디자인 토큰:
/// - 배경: `surfaceBase`(상단 100%) → `surfaceBase × 0.0`(하단) 의 **수직** 그라디언트.
///   본문 배경이 `background` 이기 때문에 하단으로 갈수록 자연스럽게 본문에 흡수된다.
///   기존의 `chzzkGreen 좌→우 wash` 처럼 색감을 강제하지 않으므로 어떤 메뉴와도 어울린다.
/// - 디바이더: `border` 색상의 0.5pt hairline 을 좌·우 끝에서 0% 로 사라지게 처리.
///   하드 1pt 라인의 시각 단절(끊긴 줄) 을 완화한다.
public struct MenuTopChromeModifier: ViewModifier {
    let showsDivider: Bool

    public init(showsDivider: Bool = true) {
        self.showsDivider = showsDivider
    }

    public func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    stops: [
                        .init(color: DesignTokens.Colors.surfaceBase, location: 0),
                        .init(color: DesignTokens.Colors.surfaceBase.opacity(0.55), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                if showsDivider {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: DesignTokens.Colors.border.opacity(0.55), location: 0.18),
                            .init(color: DesignTokens.Colors.border.opacity(0.55), location: 0.82),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 0.5)
                }
            }
    }
}
