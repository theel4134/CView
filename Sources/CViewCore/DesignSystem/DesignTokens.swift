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
        // ── 사이즈 토큰 (Retina 최적화 — 2x 밀도 기준) ──
        public static let displaySize: CGFloat = 34
        public static let titleSize: CGFloat = 26
        public static let headlineSize: CGFloat = 20
        public static let subheadSize: CGFloat = 16
        public static let bodySize: CGFloat = 14
        public static let captionSize: CGFloat = 13
        public static let footnoteSize: CGFloat = 12
        public static let microSize: CGFloat = 10

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

        // ── Retina 전용 모노스페이스 (숫자, 시청자 수 등) ──
        public static let monoMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
        public static let monoSemibold = Font.system(size: 13, weight: .semibold, design: .monospaced)

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
        /// 치지직 그린 — 유일한 브랜드 액센트 (라이트 WCAG AA 4.6:1+)
        public static let primary       = adaptive(dark: 0x00FFA3, light: 0x00875A)
        public static let chzzkGreen    = primary

        // ── 4-Layer Surface Stack (Raycast-inspired, 6-8pt luminance steps) ──
        /// 최하단 배경 — 앱 전체 배경
        public static let background         = adaptive(dark: 0x141416, light: 0xF5F5F7)
        /// 기본 표면 — 카드, 패널
        public static let surfaceBase        = adaptive(dark: 0x1C1C1E, light: 0xFFFFFF)
        /// 상승 표면 — 호버, 활성 패널
        public static let surfaceElevated    = adaptive(dark: 0x242426, light: 0xE8E8EF)
        /// 오버레이 표면 — 드롭다운, 툴팁
        public static let surfaceOverlay     = adaptive(dark: 0x2C2C2E, light: 0xDCDCE4)
        /// 팝오버 표면 — 커맨드 팔레트, 팝오버
        public static let surfacePopover     = adaptive(dark: 0x3A3A3C, light: 0xD2D2DC)

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
        public static let success      = adaptive(dark: 0x00FFA3, light: 0x00875A)
        public static let warning      = Color(hex: 0xFFAA00)

        // ── Accent Palette (라이트 WCAG AA 4.5:1+) ──
        public static let accentBlue   = adaptive(dark: 0x5BA3FF, light: 0x2E6BC6)
        public static let accentPurple = adaptive(dark: 0xBF5FFF, light: 0x7B3FA6)
        public static let accentPink   = adaptive(dark: 0xFF5FA0, light: 0xC93570)
        public static let accentOrange = adaptive(dark: 0xFF9F0A, light: 0xCC7A00)
        public static let accentCyan   = adaptive(dark: 0x33CCEE, light: 0x1A8FA8)

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
        /// macOS 사이드바 — 얇은 Material을 sidebar 역할로 사용
        public static let sidebar: Material = .ultraThinMaterial
        /// macOS 툴바/타이틀바 — 얇은 Material을 bar 역할로 사용
        public static let bar: Material = .ultraThinMaterial
        /// Glass 테두리 기본 투명도 (Retina: 더 선명하게)
        public static let borderOpacity: Double = 0.10
        /// Glass 테두리 밝은 투명도
        public static let borderOpacityLight: Double = 0.18
        
        // ── Adaptive Glass Border Colors (Light/Dark) ──
        /// Glass 테두리 색상 — 다크: white 0.10, 라이트: black 0.12
        public static let borderColor: Color = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.12)
        })
        /// Glass 테두리 밝은 색상 — 다크: white 0.18, 라이트: black 0.18
        public static let borderColorLight: Color = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.18)
        })
        /// Glass 구분선 색상 — 다크: white 0.22, 라이트: black 0.12
        public static let dividerColor: Color = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.12)
        })
        /// macOS 구분선 투명도 — System separator에 맞춤
        public static let dividerOpacity: Double = 0.22
        /// 선택 배경 투명도 — macOS list selection 수준
        public static let selectionOpacity: Double = 0.14
        /// 컨텐츠 테두리 투명도 — 카드/패널 테두리에 사용
        public static let contentBorder: Double = 0.38
        /// 썸네일 오버레이 — 강화된 그라데이션 (Retina)
        public static let thumbnailGradientOpacity: Double = 0.60
    }

    // MARK: - Gradients (Real gradients, not flat fills)

    public enum Gradients {
        /// 프라이머리 — 미묘한 그린 그라데이션 (적응형)
        public static let primary = LinearGradient(
            colors: [Colors.chzzkGreen, Colors.chzzkGreen.opacity(0.85)],
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
        /// 사이드바 선택 — macOS 네이티브 느낌의 미묘한 그린 틴트
        public static let sidebarActive = LinearGradient(
            colors: [Colors.chzzkGreen.opacity(0.10), Colors.chzzkGreen.opacity(0.03)],
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

        /// 메인 콘텐츠 배경 — 라이트: 미묘한 쿨 그라디언트, 다크: 투명 (기존 배경 유지)
        public static let contentBackground = LinearGradient(
            colors: [
                Colors.background,
                Colors.background.opacity(0.97),
                Colors.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 섹션 카드 배경 — 라이트: surfaceBase → 미묘한 그림자 느낌, 다크: 동일
        public static let sectionCard = LinearGradient(
            colors: [Colors.surfaceBase, Colors.surfaceBase.opacity(0.92)],
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

    // MARK: - Shadows (Retina-tuned — 라이트 모드에서 강화된 깊이감)

    public enum Shadow {
        // MARK: Adaptive shadow helper
        private static func adaptiveShadow(
            darkOpacity: Double, lightOpacity: Double,
            darkRadius: CGFloat, lightRadius: CGFloat,
            y: CGFloat
        ) -> ShadowStyle {
            let color = Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.black.withAlphaComponent(isDark ? darkOpacity : lightOpacity)
            })
            // 라이트 모드 radius를 약간 키워 더 소프트한 그림자 생성
            return ShadowStyle(color: color, radius: lightRadius, x: 0, y: y)
        }

        /// 작은 그림자 — 배지, 작은 요소 (라이트: 강화)
        public static let sm = adaptiveShadow(darkOpacity: 0.14, lightOpacity: 0.10, darkRadius: 4, lightRadius: 5, y: 1.5)
        /// 중간 그림자 — 카드, 패널 (라이트: 강화)
        public static let md = adaptiveShadow(darkOpacity: 0.18, lightOpacity: 0.12, darkRadius: 10, lightRadius: 12, y: 4)
        /// 큰 그림자 — 모달, 팝오버 (라이트: 강화)
        public static let lg = adaptiveShadow(darkOpacity: 0.26, lightOpacity: 0.18, darkRadius: 20, lightRadius: 24, y: 8)
        /// 액센트 글로우 — 브랜드 하이라이트
        public static let glow = ShadowStyle(color: Colors.chzzkGreen.opacity(0.30), radius: 16, x: 0, y: 0)
        /// 호버 카드 — 부유 효과 (라이트: 부드러운 elevation)
        public static let cardHover = adaptiveShadow(darkOpacity: 0.32, lightOpacity: 0.20, darkRadius: 22, lightRadius: 26, y: 10)
        /// Glass 그림자 — 유리 패널 하단 (라이트: 강화)
        public static let glass = adaptiveShadow(darkOpacity: 0.16, lightOpacity: 0.10, darkRadius: 24, lightRadius: 28, y: 6)
        /// 사이드바 행 선택 — 미세 elevation
        public static let rowSelected = adaptiveShadow(darkOpacity: 0.10, lightOpacity: 0.08, darkRadius: 6, lightRadius: 8, y: 2)
        /// 카드 기본 — 라이트 모드에서 플로팅 느낌 (다크: 없음)
        public static let card = adaptiveShadow(darkOpacity: 0.0, lightOpacity: 0.08, darkRadius: 0, lightRadius: 10, y: 3)
    }

    // MARK: - Animation (Spring-first, Metal 3 GPU 가속)

    public enum Animation {
        // ── 기본 (Spring 기반 — 자연스러운 감속) ──
        /// 빠른 전환 (hover, 토글 등) — 150ms급 spring
        public static let fast: SwiftUI.Animation = .spring(response: 0.15, dampingFraction: 0.9)
        /// 일반 전환 (패널 열기/닫기) — 250ms급 spring
        public static let normal: SwiftUI.Animation = .spring(response: 0.25, dampingFraction: 0.88)
        /// 느린 전환 (모달, 풀스크린) — 400ms급 spring
        public static let slow: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.86)

        // ── Spring (핵심) ──
        /// 범용 spring — 자연스러운 안착 (damping 0.82: 진동 최소화)
        public static let spring: SwiftUI.Animation = .spring(response: 0.32, dampingFraction: 0.82)
        /// 탄성 spring — 카드 등장, 드래그 릴리스 (damping 0.75: 미세 바운스)
        public static let bouncy: SwiftUI.Animation = .spring(response: 0.38, dampingFraction: 0.75)
        /// 부드러운 spring — 뷰 전환, 콘텐츠 이동 (개선)
        public static let smooth: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.88)
        /// 빠르고 정확한 spring — 탭 전환, 셀렉터
        public static let snappy: SwiftUI.Animation = .spring(response: 0.22, dampingFraction: 0.88)

        // ── 60fps 전용 ──
        /// 마이크로 인터랙션 — 호버, 아이콘 스케일 (즉각 반응)
        public static let micro: SwiftUI.Animation = .spring(response: 0.14, dampingFraction: 0.92)
        /// 인터랙티브 제스처 — 드래그 중 실시간 피드백
        public static let interactive: SwiftUI.Animation = .interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0.02)
        /// 콘텐츠 뷰 전환 — 사이드바→디테일 (자연스러운 안착)
        public static let contentTransition: SwiftUI.Animation = .spring(response: 0.28, dampingFraction: 0.92)
        /// 사이드바 인디케이터 / matchedGeometry (정밀 안착)
        public static let indicator: SwiftUI.Animation = .spring(response: 0.22, dampingFraction: 0.88)
        /// 반복(pulse) — LiveBadge, RecordButton (reduceMotion 시 nil 사용)
        public static let pulse: SwiftUI.Animation = .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        /// 채팅 스크롤 — 빠른 자동 스크롤
        public static let chatScroll: SwiftUI.Animation = .spring(response: 0.12, dampingFraction: 0.95)
        /// Glass 등장 — 모달/팝오버 등장
        public static let glassAppear: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.85)
        /// 로딩 스피너 — 무한 회전
        public static let loadingSpin: SwiftUI.Animation = .linear(duration: 1).repeatForever(autoreverses: false)
        /// 메뉴바 Pulse — 라이브 표시 느린 맥동
        public static let menuPulse: SwiftUI.Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        /// 이미지 페이드인 — 썸네일/프로필 등장 (즉각)
        public static let fadeIn: SwiftUI.Animation = .easeOut(duration: 0.16)
        /// 채팅 메시지 등장 — slide-up + fade-in용 경쾌한 spring (0.12초)
        public static let chatMessage: SwiftUI.Animation = .spring(response: 0.12, dampingFraction: 0.92)

        // ── Metal 3 고주사율 (카드 그리드, 페이지 전환) ──
        /// 카드 호버 — 고정밀 spring (Metal GPU 오프스크린 합성에 최적화, 짧은 response로 즉각 반응)
        public static let cardHover: SwiftUI.Animation = .interpolatingSpring(stiffness: 400, damping: 28)
        /// 그리드 페이지 전환 — 부드러운 보간 spring (drawingGroup 내부에서 Metal GPU가 중간 프레임 보간)
        public static let gridPageTransition: SwiftUI.Animation = .interpolatingSpring(stiffness: 200, damping: 22)
        /// 카드 등장 — 스태거 애니메이션에 적합한 탄성 spring
        public static let cardAppear: SwiftUI.Animation = .interpolatingSpring(stiffness: 300, damping: 24)

        // ── macOS 26+ 최신 전환 ──
        // 미사용 토큰 정리: dimTransition, staggerAppear, overlayBlur, elasticRelease 제거 (2026-04-04)

        /// reduceMotion 고려 — 모션 감소 설정 시 nil 반환 (즉시 전환)
        public static func motionSafe(_ animation: SwiftUI.Animation?) -> SwiftUI.Animation? {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                return nil
            }
            return animation
        }
    }

    // MARK: - Layout (Retina Display 최적화)

    public enum Layout {
        public static let sidebarMinWidth: CGFloat = 220
        public static let sidebarDefaultWidth: CGFloat = 260
        public static let sidebarMaxWidth: CGFloat = 320
        /// Retina: 최소 1280px 권장 (원래 900)
        public static let minWindowWidth: CGFloat = 1000
        public static let minWindowHeight: CGFloat = 660
        public static let chatPanelWidth: CGFloat = 300
        public static let playerMinHeight: CGFloat = 420
        /// 카드 그리드 — 기본 컬럼 최소 폭
        public static let gridCardMinWidth: CGFloat = 220
        /// 카드 그리드 — 이상적 컬럼 폭
        public static let gridCardIdealWidth: CGFloat = 260
        /// 썸네일 오프라인 행 아바타 크기
        public static let offlineAvatarSize: CGFloat = 36
        /// 온라인 카드 아바타 배지 크기
        public static let liveAvatarSize: CGFloat = 28
    }

    // MARK: - Border (선 두께 표준화)

    public enum Border {
        /// 0.5pt — 미세 테두리, 구분선
        public static let thin: CGFloat = 0.5
        /// 1pt — 기본 테두리
        public static let medium: CGFloat = 1.0
        /// 1.5pt — 강조 테두리, 포커스 링
        public static let thick: CGFloat = 1.5
    }

    // MARK: - Opacity (표준화된 투명도 레벨)

    public enum Opacity {
        /// 0.06 — 극미세 배경 틴트
        public static let subtle: Double = 0.06
        /// 0.10 — 배지/토글 비활성 배경
        public static let light: Double = 0.10
        /// 0.12 — 배지/카운트 배경 기본
        public static let medium: Double = 0.12
        /// 0.15 — 선택 상태 배경
        public static let heavy: Double = 0.15
        /// 0.25 — 호버 오버레이
        public static let overlay: Double = 0.25
        /// 0.40 — Divider 기본
        public static let divider: Double = 0.40
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
// MARK: - Icon Button Style (통일된 아이콘 버튼 스타일)
// ═══════════════════════════════════════════════════════════════════

/// 28×28 아이콘 버튼 — 호버/프레스 피드백 포함
public struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(isHovered
                        ? DesignTokens.Colors.surfaceElevated
                        : DesignTokens.Colors.surfaceElevated.opacity(0.5))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(DesignTokens.Animation.micro, value: isHovered)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// 캡슐형 액션 버튼 — 호버 시 미세 밝기 변화
public struct HoverPillButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : (isHovered ? 0.9 : 1.0))
            .animation(DesignTokens.Animation.micro, value: isHovered)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

