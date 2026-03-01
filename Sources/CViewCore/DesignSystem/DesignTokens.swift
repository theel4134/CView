// MARK: - CViewCore/DesignSystem/DesignTokens.swift
// Dark Glass 디자인 시스템 v2
// Design: 딥 차콜 기반 + 글래스모피즘 + 치지직 그린 액센트
// Reference: Raycast Surface Stack, YouTube 2025 Pill Controls, macOS Glassmorphism

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - DesignTokens (Core)
// ═══════════════════════════════════════════════════════════════════

/// 디자인 시스템 토큰 — Dark Glass v2
public enum DesignTokens {

    // MARK: - Spacing (8pt Grid — 10 tokens)

    public enum Spacing {
        /// 2pt — 테두리/구분선 간격
        public static let xxs: CGFloat = 2
        /// 4pt — 아이콘-텍스트, 인라인 간격
        public static let xs: CGFloat = 4
        /// 8pt — 요소 내부 패딩, 기본 단위
        public static let sm: CGFloat = 8
        /// 12pt — 카드 내부 패딩
        public static let md: CGFloat = 12
        /// 16pt — 섹션 내 간격
        public static let lg: CGFloat = 16
        /// 24pt — 섹션 구분
        public static let xl: CGFloat = 24
        /// 32pt — 대 섹션 간격
        public static let xxl: CGFloat = 32
        /// 48pt — 페이지 마진
        public static let xxxl: CGFloat = 48
        /// 64pt — 섹션 구분선
        public static let section: CGFloat = 64
        /// 80pt — 페이지 레벨 마진
        public static let page: CGFloat = 80

        // ── Deprecated aliases (점진 마이그레이션) ──
        @available(*, deprecated, renamed: "xxs")
        public static let hair: CGFloat = 1
        @available(*, deprecated, renamed: "xxs")
        public static let xxxs: CGFloat = 2
        @available(*, deprecated, renamed: "xxs")
        public static let nano: CGFloat = 3
        @available(*, deprecated, renamed: "xs")
        public static let mini: CGFloat = 5
        @available(*, deprecated, renamed: "xs")
        public static let xss: CGFloat = 6
        @available(*, deprecated, renamed: "sm")
        public static let xsm: CGFloat = 7
        @available(*, deprecated, renamed: "sm")
        public static let smXs: CGFloat = 9
        @available(*, deprecated, renamed: "md")
        public static let compact: CGFloat = 10
        @available(*, deprecated, renamed: "md")
        public static let cozy: CGFloat = 14
        @available(*, deprecated, renamed: "xl")
        public static let mdl: CGFloat = 20
    }

    // MARK: - Typography (Streamlined Presets)

    public enum Typography {
        // ── 사이즈 토큰 (8 sizes) ──
        public static let displaySize: CGFloat = 32
        public static let titleSize: CGFloat = 24
        public static let headlineSize: CGFloat = 20
        public static let subheadSize: CGFloat = 16
        public static let bodySize: CGFloat = 14
        public static let captionSize: CGFloat = 12
        public static let footnoteSize: CGFloat = 11
        public static let microSize: CGFloat = 9

        // ── 프리셋 폰트 (핵심 16개) ──
        public static let display = Font.system(size: displaySize, weight: .bold)
        public static let displaySemibold = Font.system(size: displaySize, weight: .semibold)
        public static let title = Font.system(size: titleSize, weight: .bold)
        public static let titleSemibold = Font.system(size: titleSize, weight: .semibold)
        public static let headline = Font.system(size: headlineSize, weight: .semibold)
        public static let headlineBold = Font.system(size: headlineSize, weight: .bold)
        public static let subhead = Font.system(size: subheadSize, weight: .medium)
        public static let subheadSemibold = Font.system(size: subheadSize, weight: .semibold)
        public static let body = Font.system(size: bodySize, weight: .regular)
        public static let bodyMedium = Font.system(size: bodySize, weight: .medium)
        public static let bodySemibold = Font.system(size: bodySize, weight: .semibold)
        public static let bodyBold = Font.system(size: bodySize, weight: .bold)
        public static let caption = Font.system(size: captionSize, weight: .regular)
        public static let captionMedium = Font.system(size: captionSize, weight: .medium)
        public static let captionSemibold = Font.system(size: captionSize, weight: .semibold)
        public static let footnote = Font.system(size: footnoteSize, weight: .regular)
        public static let footnoteMedium = Font.system(size: footnoteSize, weight: .medium)
        public static let micro = Font.system(size: microSize, weight: .medium)
        public static let microSemibold = Font.system(size: microSize, weight: .semibold)
        public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)

        /// 커스텀 사이즈 + weight 조합용 헬퍼
        public static func custom(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
            Font.system(size: size, weight: weight, design: design)
        }

        // ── Deprecated aliases ──
        @available(*, deprecated, renamed: "display")
        public static let hero: Font = .system(size: 40, weight: .bold)
        @available(*, deprecated, renamed: "display")
        public static let largeTitle: Font = .system(size: 32, weight: .bold)
        @available(*, deprecated, renamed: "titleSemibold")
        public static let title2: Font = .system(size: 22, weight: .bold)
        @available(*, deprecated, renamed: "headline")
        public static let subtitle: Font = .system(size: 20, weight: .semibold)
        @available(*, deprecated, renamed: "subhead")
        public static let title3: Font = .system(size: 18, weight: .semibold)
        @available(*, deprecated, renamed: "subheadSemibold")
        public static let heading: Font = .system(size: 17, weight: .semibold)
        @available(*, deprecated, renamed: "bodySemibold")
        public static let sectionTitle: Font = .system(size: 15, weight: .bold)
        @available(*, deprecated, renamed: "captionMedium")
        public static let cardTitle: Font = .system(size: 13, weight: .medium)
        @available(*, deprecated, renamed: "captionSemibold")
        public static let cardTitleSemibold: Font = .system(size: 13, weight: .semibold)
        @available(*, deprecated, renamed: "caption")
        public static let bodySmall: Font = .system(size: 12, weight: .regular)
        @available(*, deprecated, renamed: "captionMedium")
        public static let bodySmallMedium: Font = .system(size: 12, weight: .medium)
        @available(*, deprecated, renamed: "captionSemibold")
        public static let bodySmallSemibold: Font = .system(size: 12, weight: .semibold)
        @available(*, deprecated, renamed: "captionSemibold")
        public static let bodySmallBold: Font = .system(size: 12, weight: .bold)
        @available(*, deprecated, renamed: "footnoteMedium")
        public static let badge: Font = .system(size: 10, weight: .bold)
        @available(*, deprecated, renamed: "footnoteMedium")
        public static let badgeMedium: Font = .system(size: 10, weight: .medium)
        @available(*, deprecated, renamed: "micro")
        public static let pico: Font = .system(size: 8, weight: .bold)
        @available(*, deprecated, renamed: "body")
        public static let chat: Font = .system(size: 14, weight: .regular)

        // ── Deprecated size tokens ──
        @available(*, deprecated, renamed: "displaySize")
        public static let heroSize: CGFloat = 40
        @available(*, deprecated, renamed: "displaySize")
        public static let largeTitleSize: CGFloat = 32
        @available(*, deprecated, renamed: "titleSize")
        public static let title2Size: CGFloat = 22
        @available(*, deprecated, renamed: "headlineSize")
        public static let subtitleSize: CGFloat = 20
        @available(*, deprecated, renamed: "subheadSize")
        public static let title3Size: CGFloat = 18
        @available(*, deprecated, renamed: "subheadSize")
        public static let headingSize: CGFloat = 17
        @available(*, deprecated, renamed: "bodySize")
        public static let sectionTitleSize: CGFloat = 15
        @available(*, deprecated, renamed: "captionSize")
        public static let cardTitleSize: CGFloat = 13
        @available(*, deprecated, renamed: "captionSize")
        public static let bodySmallSize: CGFloat = 12
        @available(*, deprecated, renamed: "footnoteSize")
        public static let captionSize_old: CGFloat = 11
        @available(*, deprecated, renamed: "bodySize")
        public static let chatSize: CGFloat = 14
        @available(*, deprecated, renamed: "footnoteSize")
        public static let badgeSize: CGFloat = 10
        @available(*, deprecated, renamed: "microSize")
        public static let picoSize: CGFloat = 8
    }

    // MARK: - Colors (4-Layer Surface Stack + Glass — Adaptive Light/Dark)

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

        // ── Accent ──
        /// 치지직 그린 — 유일한 브랜드 액센트 (양 모드 동일)
        public static let primary       = Color(hex: 0x00FFA3)
        public static let chzzkGreen    = primary

        // ── 4-Layer Surface Stack (Raycast-inspired, 6-8pt luminance steps) ──
        /// 최하단 배경 — 앱 전체 배경
        public static let background         = adaptive(dark: 0x141416, light: 0xF5F5F7)
        /// 기본 표면 — 카드, 패널
        public static let surfaceBase        = adaptive(dark: 0x1C1C1E, light: 0xFFFFFF)
        /// 상승 표면 — 호버, 활성 패널
        public static let surfaceElevated    = adaptive(dark: 0x242426, light: 0xF0F0F5)
        /// 오버레이 표면 — 드롭다운, 툴팁
        public static let surfaceOverlay     = adaptive(dark: 0x2C2C2E, light: 0xEAEAF0)
        /// 팝오버 표면 — 커맨드 팔레트, 팝오버
        public static let surfacePopover     = adaptive(dark: 0x3A3A3C, light: 0xE0E0E8)

        // ── Text ──
        public static let textPrimary   = adaptive(dark: 0xF5F5F7, light: 0x1D1D1F)
        public static let textSecondary = adaptive(dark: 0x8E8E93, light: 0x48484A)
        public static let textTertiary  = adaptive(dark: 0x636366, light: 0x8E8E93)

        // ── Border ──
        public static let border        = adaptive(dark: 0x38383A, light: 0xD1D1D6)
        public static let borderSubtle  = adaptive(dark: 0x2C2C2E, light: 0xE5E5EA)

        // ── Semantic (양 모드 동일) ──
        public static let live         = Color(hex: 0xFF3B30)
        public static let liveGlow     = Color(hex: 0xFF3B30).opacity(0.3)
        public static let donation     = Color(hex: 0xFFD700)
        public static let donationEnd  = Color(hex: 0xFFA500)
        public static let error        = Color(hex: 0xFF453A)
        public static let success      = Color(hex: 0x00FFA3)
        public static let warning      = Color(hex: 0xFFAA00)

        // ── Accent Palette ──
        public static let accentBlue   = Color(hex: 0x5BA3FF)
        public static let accentPurple = Color(hex: 0xBF5FFF)
        public static let accentPink   = Color(hex: 0xFF5FA0)
        public static let accentOrange = Color(hex: 0xFF9F0A)

        // ── On-surface ──
        public static let onPrimary    = adaptive(dark: 0x0A0A0A, light: 0x0A0A0A)
        public static let textOnOverlay = Color.white

        // ── Deprecated aliases ──
        @available(*, deprecated, renamed: "background")
        public static let backgroundDark: Color = adaptive(dark: 0x141416, light: 0xF5F5F7)
        @available(*, deprecated, renamed: "surfaceOverlay")
        public static let backgroundElevated: Color = adaptive(dark: 0x242426, light: 0xF0F0F5)
        @available(*, deprecated, renamed: "surfaceBase")
        public static let surface: Color = adaptive(dark: 0x1C1C1E, light: 0xFFFFFF)
        @available(*, deprecated, renamed: "surfaceElevated")
        public static let surfaceLight: Color = adaptive(dark: 0x242426, light: 0xF0F0F5)
        @available(*, deprecated, renamed: "surfaceOverlay")
        public static let surfaceHover: Color = adaptive(dark: 0x2C2C2E, light: 0xEAEAF0)
        @available(*, deprecated, renamed: "borderSubtle")
        public static let borderLight: Color = adaptive(dark: 0x2C2C2E, light: 0xE5E5EA)
        @available(*, deprecated, message: "Use primary instead")
        public static let primaryDark: Color = Color(hex: 0x00CC82)
        @available(*, deprecated, message: "Use primary instead")
        public static let primaryLight: Color = Color(hex: 0x33FFB8)
    }

    // MARK: - Glass (Material 기반 Glassmorphism)

    public enum Glass {
        /// 얇은 유리 — 사이드바, 호버 오버레이
        public static let thin: Material = .ultraThinMaterial
        /// 보통 유리 — 카드, 패널
        public static let regular: Material = .thinMaterial
        /// 두꺼운 유리 — 모달, 팝오버, 커맨드 팔레트
        public static let thick: Material = .regularMaterial
        /// Glass 테두리 기본 투명도
        public static let borderOpacity: Double = 0.12
        /// Glass 테두리 밝은 투명도
        public static let borderOpacityLight: Double = 0.18
    }

    // MARK: - Gradients (Real gradients, not flat fills)

    public enum Gradients {
        /// 프라이머리 — 미묘한 그린 그라데이션
        public static let primary = LinearGradient(
            colors: [Color(hex: 0x00FFA3), Color(hex: 0x00E08E)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        /// 라이브 배지 — 레드 그라데이션
        public static let live = LinearGradient(
            colors: [Color(hex: 0xFF3B30), Color(hex: 0xFF6259)],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 도네이션 — 골드 그라데이션
        public static let donation = LinearGradient(
            colors: [Colors.donation, Colors.donationEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// 서피스 카드 — 미묘한 높이 차 그라데이션
        public static let surfaceCard = LinearGradient(
            colors: [Colors.surfaceBase, Colors.surfaceBase.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 플레이어 오버레이 — 상단
        public static let playerOverlayTop = LinearGradient(
            colors: [.black.opacity(0.75), .black.opacity(0.35), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 플레이어 오버레이 — 하단
        public static let playerOverlayBottom = LinearGradient(
            colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 썸네일 오버레이 — 하단 정보 영역
        public static let thumbnailOverlay = LinearGradient(
            colors: [.clear, .clear, .black.opacity(0.55)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// 사이드바 선택 — 그린 틴트
        public static let sidebarActive = LinearGradient(
            colors: [Colors.chzzkGreen.opacity(0.13), Colors.chzzkGreen.opacity(0.04)],
            startPoint: .leading,
            endPoint: .trailing
        )
        /// Glass shimmer — 카드 위 미묘한 하이라이트
        public static let glassShimmer = LinearGradient(
            colors: [.white.opacity(0.0), .white.opacity(0.04), .white.opacity(0.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        /// 스탯 카드
        public static let statBlue = LinearGradient(
            colors: [Colors.surfaceElevated, Colors.surfaceBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        public static let statPurple = LinearGradient(
            colors: [Colors.accentPurple.opacity(0.08), Colors.surfaceBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Corner Radius (6 tokens)

    public enum Radius {
        /// 4pt — 배지, 태그, 인라인 요소
        public static let xs: CGFloat = 4
        /// 8pt — 버튼, 입력 필드, 작은 카드
        public static let sm: CGFloat = 8
        /// 12pt — 카드, 패널
        public static let md: CGFloat = 12
        /// 16pt — 대형 카드, 모달
        public static let lg: CGFloat = 16
        /// 24pt — 대형 이미지, 패널
        public static let xl: CGFloat = 24
        /// 999pt — Pill, 원형
        public static let full: CGFloat = 999

        // ── Deprecated aliases ──
        @available(*, deprecated, renamed: "xs")
        public static let hair: CGFloat = 1
        @available(*, deprecated, renamed: "xs")
        public static let xxs: CGFloat = 2
        @available(*, deprecated, renamed: "xs")
        public static let nano: CGFloat = 3
        @available(*, deprecated, renamed: "xs")
        public static let mini: CGFloat = 5
        @available(*, deprecated, renamed: "sm")
        public static let xsm: CGFloat = 6
        @available(*, deprecated, renamed: "sm")
        public static let xsml: CGFloat = 7
        @available(*, deprecated, renamed: "md")
        public static let smMd: CGFloat = 9
        @available(*, deprecated, renamed: "md")
        public static let smd: CGFloat = 10
        @available(*, deprecated, renamed: "lg")
        public static let mdl: CGFloat = 14
    }

    public typealias CornerRadius = Radius

    // MARK: - Shadows (Glass-friendly)

    public enum Shadow {
        /// 작은 그림자 — 배지, 작은 요소
        public static let sm = ShadowStyle(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
        /// 중간 그림자 — 카드, 패널
        public static let md = ShadowStyle(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        /// 큰 그림자 — 모달, 팝오버
        public static let lg = ShadowStyle(color: .black.opacity(0.22), radius: 16, x: 0, y: 6)
        /// 액센트 글로우 — 브랜드 하이라이트
        public static let glow = ShadowStyle(color: Colors.chzzkGreen.opacity(0.25), radius: 12, x: 0, y: 0)
        /// 호버 카드 — 부유 효과
        public static let cardHover = ShadowStyle(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
        /// Glass 그림자 — 유리 패널 하단
        public static let glass = ShadowStyle(color: .black.opacity(0.12), radius: 20, x: 0, y: 4)
    }

    // MARK: - Animation (Spring-first, 60fps)

    public enum Animation {
        // ── 기본 (easeInOut — 짧은 단발 전환만) ──
        /// 150ms 빠른 전환 (hover, 토글 등)
        public static let fast: SwiftUI.Animation = .easeInOut(duration: 0.15)
        /// 250ms 일반 전환 (패널 열기/닫기)
        public static let normal: SwiftUI.Animation = .easeInOut(duration: 0.25)
        /// 400ms 느린 전환 (모달, 풀스크린)
        public static let slow: SwiftUI.Animation = .easeInOut(duration: 0.4)

        // ── Spring (핵심) ──
        /// 범용 spring — 자연스러운 바운스
        public static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.72)
        /// 탄성 spring — 카드 등장, 드래그 릴리스
        public static let bouncy: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.65)
        /// 부드러운 spring — 뷰 전환, 콘텐츠 이동
        public static let smooth: SwiftUI.Animation = .spring(response: 0.5, dampingFraction: 0.85)
        /// 빠르고 정확한 spring — 탭 전환, 셀렉터
        public static let snappy: SwiftUI.Animation = .spring(response: 0.25, dampingFraction: 0.82)

        // ── 60fps 전용 ──
        /// 마이크로 인터랙션 — 호버, 아이콘 스케일
        public static let micro: SwiftUI.Animation = .spring(response: 0.2, dampingFraction: 0.82)
        /// 인터랙티브 제스처 — 드래그 중 실시간 피드백
        public static let interactive: SwiftUI.Animation = .interactiveSpring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.04)
        /// 콘텐츠 뷰 전환 — 사이드바→디테일
        public static let contentTransition: SwiftUI.Animation = .spring(response: 0.32, dampingFraction: 0.88)
        /// 사이드바 인디케이터 / matchedGeometry
        public static let indicator: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.78)
        /// 반복(pulse) — LiveBadge, RecordButton
        public static let pulse: SwiftUI.Animation = .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        /// 채팅 스크롤 — 빠른 자동 스크롤
        public static let chatScroll: SwiftUI.Animation = .spring(response: 0.15, dampingFraction: 0.92)
        /// Glass 등장 — 모달/팝오버 등장
        public static let glassAppear: SwiftUI.Animation = .spring(response: 0.38, dampingFraction: 0.78)
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

// ═══════════════════════════════════════════════════════════════════
// MARK: - ShadowStyle
// ═══════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════
// MARK: - Color Hex Extension
// ═══════════════════════════════════════════════════════════════════

extension Color {
    public init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

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
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: hasShadow ? .black.opacity(0.12) : .clear,
                radius: hasShadow ? 12 : 0,
                y: hasShadow ? 4 : 0
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
            .shadow(
                color: isHovered ? .black.opacity(0.22) : .clear,
                radius: isHovered ? 12 : 0,
                y: isHovered ? 6 : 0
            )
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

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? DesignTokens.Typography.captionMedium : DesignTokens.Typography.bodyMedium)
            .foregroundStyle(textColor)
            .padding(.horizontal, isCompact ? DesignTokens.Spacing.md : DesignTokens.Spacing.lg)
            .padding(.vertical, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
            .background(fillColor, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
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

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? DesignTokens.Typography.captionMedium : DesignTokens.Typography.bodyMedium)
            .foregroundStyle(textColor)
            .padding(.horizontal, isCompact ? DesignTokens.Spacing.md : DesignTokens.Spacing.lg)
            .padding(.vertical, isCompact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
            .background(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
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
}
