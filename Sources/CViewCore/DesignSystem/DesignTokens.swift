// MARK: - CViewCore/DesignSystem/DesignTokens.swift
// Minimal Monochrome 디자인 시스템
// Design: 흑/백/그레이 + 치지직 그린 단일 액센트

import SwiftUI

/// 디자인 시스템 토큰 — Minimal Monochrome
public enum DesignTokens {

    // MARK: - Spacing (8pt Grid)

    public enum Spacing {
        public static let xxxs: CGFloat = 2
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let mdl: CGFloat = 20
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
        public static let xxxl: CGFloat = 64
    }

    // MARK: - Typography

    public enum Typography {
        public static let largeTitleSize: CGFloat = 32
        public static let titleSize: CGFloat = 24
        public static let subtitleSize: CGFloat = 20
        public static let headingSize: CGFloat = 17
        public static let bodySize: CGFloat = 14
        public static let bodySmallSize: CGFloat = 12
        public static let captionSize: CGFloat = 11
        public static let chatSize: CGFloat = 14
        public static let badgeSize: CGFloat = 10

        public static let largeTitle = Font.system(size: largeTitleSize, weight: .bold)
        public static let title = Font.system(size: titleSize, weight: .bold)
        public static let subtitle = Font.system(size: subtitleSize, weight: .semibold)
        public static let heading = Font.system(size: headingSize, weight: .semibold)
        public static let body = Font.system(size: bodySize, weight: .regular)
        public static let bodySmall = Font.system(size: bodySmallSize, weight: .regular)
        public static let caption = Font.system(size: captionSize, weight: .regular)
        public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
        public static let chat = Font.system(size: chatSize, weight: .regular)
        public static let badge = Font.system(size: badgeSize, weight: .bold)
    }

    // MARK: - Colors (Adaptive — Light/Dark)

    public enum Colors {
        // MARK: Adaptive helper
        private static func adaptive(dark darkHex: UInt, light lightHex: UInt, alpha: CGFloat = 1.0) -> Color {
            Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? darkHex : lightHex
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                    green:   CGFloat((hex >> 8)  & 0xFF) / 255.0,
                    blue:    CGFloat( hex         & 0xFF) / 255.0,
                    alpha:   alpha
                )
            }))
        }

        /// 치지직 그린 — 유일한 액센트 컬러 (양 모드 동일)
        public static let primary       = Color(hex: 0x00FFA3)
        public static let chzzkGreen    = primary
        public static let primaryDark   = Color(hex: 0x00CC82)
        public static let primaryLight  = Color(hex: 0x33FFB8)

        /// 배경
        public static let backgroundDark     = adaptive(dark: 0x0A0A0A, light: 0xF2F2F7)
        public static let backgroundElevated = adaptive(dark: 0x111111, light: 0xEAEAF0)
        /// 서피스
        public static let surface      = adaptive(dark: 0x161616, light: 0xFFFFFF)
        public static let surfaceLight = adaptive(dark: 0x1E1E1E, light: 0xF0F0F5)
        public static let surfaceHover = adaptive(dark: 0x262626, light: 0xE4E4EB)
        /// 테두리
        public static let border      = adaptive(dark: 0x2A2A2A, light: 0xDDDDDD)
        public static let borderLight = adaptive(dark: 0x333333, light: 0xCCCCCC)
        /// 텍스트
        public static let textPrimary   = adaptive(dark: 0xFFFFFF, light: 0x111111)
        public static let textSecondary = adaptive(dark: 0x888888, light: 0x444444)
        public static let textTertiary  = adaptive(dark: 0x555555, light: 0x888888)
        /// 시맨틱 (양 모드 동일)
        public static let live         = Color(hex: 0xFF3B30)
        public static let liveGlow     = Color(hex: 0xFF3B30).opacity(0.3)
        public static let donation     = Color(hex: 0xFFD700)
        public static let donationEnd  = Color(hex: 0xFFA500)
        public static let error        = Color(hex: 0xFF453A)
        public static let success      = Color(hex: 0x00FFA3)
        public static let warning      = Color(hex: 0xFFAA00)
        /// 보조 액센트 컬러 (양 모드 동일)
        public static let accentBlue   = Color(hex: 0x5BA3FF)
        public static let accentPurple = Color(hex: 0xBF5FFF)
        public static let accentPink   = Color(hex: 0xFF5FA0)
        public static let accentOrange = Color(hex: 0xFF9F0A)
    }

    // MARK: - Gradients (Flat fills as LinearGradient)

    public enum Gradients {
        /// 프라이머리 — 단색 그린
        public static let primary = LinearGradient(
            colors: [Colors.chzzkGreen, Colors.chzzkGreen],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 라이브 배지
        public static let live = LinearGradient(
            colors: [Colors.live, Colors.live],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 도네이션
        public static let donation = LinearGradient(
            colors: [Colors.donation, Colors.donationEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 서피스 카드 — 단색
        public static let surfaceCard = LinearGradient(
            colors: [Colors.surface, Colors.surface],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 플레이어 오버레이
        public static let playerOverlayTop = LinearGradient(
            colors: [.black.opacity(0.8), .black.opacity(0.4), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        public static let playerOverlayBottom = LinearGradient(
            colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 썸네일 오버레이
        public static let thumbnailOverlay = LinearGradient(
            colors: [.clear, .clear, .black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 사이드바 선택 — 선명한 그린 틴트
        public static let sidebarActive = LinearGradient(
            colors: [Colors.chzzkGreen.opacity(0.13), Colors.chzzkGreen.opacity(0.04)],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 스탯 카드 — 모노크롬
        public static let statBlue = LinearGradient(
            colors: [Colors.surfaceLight, Colors.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        public static let statPurple = LinearGradient(
            colors: [Colors.surfaceLight, Colors.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Corner Radius

    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let full: CGFloat = 999
    }

    public typealias CornerRadius = Radius

    // MARK: - Shadows (미니멀)

    public enum Shadow {
        public static let sm = ShadowStyle(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        public static let md = ShadowStyle(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        public static let lg = ShadowStyle(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        public static let glow = ShadowStyle(color: Colors.chzzkGreen.opacity(0.2), radius: 8, x: 0, y: 0)
        public static let cardHover = ShadowStyle(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
    }

    // MARK: - Animation

    public enum Animation {
        public static let fast: SwiftUI.Animation = .easeInOut(duration: 0.15)
        public static let normal: SwiftUI.Animation = .easeInOut(duration: 0.25)
        public static let slow: SwiftUI.Animation = .easeInOut(duration: 0.4)
        public static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.7)
        public static let bouncy: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.65)
        public static let smooth: SwiftUI.Animation = .spring(response: 0.5, dampingFraction: 0.85)
        public static let snappy: SwiftUI.Animation = .spring(response: 0.25, dampingFraction: 0.8)
    }

    // MARK: - Layout

    public enum Layout {
        public static let sidebarMinWidth: CGFloat = 200
        public static let sidebarDefaultWidth: CGFloat = 260
        public static let sidebarMaxWidth: CGFloat = 350
        public static let minWindowWidth: CGFloat = 900
        public static let minWindowHeight: CGFloat = 600
        public static let chatPanelWidth: CGFloat = 340
        public static let playerMinHeight: CGFloat = 400
    }
}

/// 그림자 스타일 값 타입
public struct ShadowStyle: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

// MARK: - Color Hex Extension

extension Color {
    public init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Card ViewModifier (Minimal Monochrome)

/// 단색 카드 스타일 — fill + 1px border
public struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let border: Bool

    public init(cornerRadius: CGFloat = DesignTokens.Radius.lg, opacity: Double = 0.06, border: Bool = true) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.border = border
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(DesignTokens.Colors.surface)
            }
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 호버 카드 효과 — 미니멀
public struct HoverCardModifier: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat
    let scaleEffect: CGFloat

    public init(cornerRadius: CGFloat = DesignTokens.Radius.lg, scaleEffect: CGFloat = 1.01) {
        self.cornerRadius = cornerRadius
        self.scaleEffect = scaleEffect
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scaleEffect : 1.0)
            .shadow(
                color: isHovered ? .black.opacity(0.2) : .clear,
                radius: isHovered ? 8 : 0,
                y: isHovered ? 4 : 0
            )
            .animation(DesignTokens.Animation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// 미세한 테두리 효과 — glow 제거
public struct GlowBorderModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let isActive: Bool

    public init(color: Color = DesignTokens.Colors.chzzkGreen, cornerRadius: CGFloat = DesignTokens.Radius.lg, isActive: Bool = true) {
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
    }
}

// MARK: - View Extensions

extension View {
    public func glassCard(cornerRadius: CGFloat = DesignTokens.Radius.lg, opacity: Double = 0.06, border: Bool = true) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, opacity: opacity, border: border))
    }

    public func hoverCard(cornerRadius: CGFloat = DesignTokens.Radius.lg, scale: CGFloat = 1.01) -> some View {
        modifier(HoverCardModifier(cornerRadius: cornerRadius, scaleEffect: scale))
    }

    public func glowBorder(color: Color = DesignTokens.Colors.chzzkGreen, cornerRadius: CGFloat = DesignTokens.Radius.lg, isActive: Bool = true) -> some View {
        modifier(GlowBorderModifier(color: color, cornerRadius: cornerRadius, isActive: isActive))
    }

    public func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
