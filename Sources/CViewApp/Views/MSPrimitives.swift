// MARK: - MultiStage/MSTokens.swift
// 멀티라이브 · 멀티채팅 전용 레이아웃 상수 + 공용 모디파이어.
// DesignTokens에 의존하며, "멀티 무대" 컴포넌트들이 공유하는 수치를 이 한 곳에서 관리한다.

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSTokens
// ═══════════════════════════════════════════════════════════════════

/// 멀티라이브/멀티채팅 공용 레이아웃 토큰.
/// - 배경: 탭바/오버레이/스플리터/페인 chrome이 공유하는 수치가 흩어져 있어 시각적 일관성이 깨지는 문제를
///   하나의 토큰 소스로 수렴시킨다.
public enum MSTokens {

    // MARK: Chrome Heights
    /// 상단 탭바 표준 높이.
    /// - 풍성한 2줄 칩(아바타 26pt + 채널명 + 라이브 제목, 높이 ~44pt)
    ///   + 상단 드래그 여유(10pt) + 하단 4pt = 58pt.
    public static let tabBarHeight: CGFloat = 58
    /// 채팅/설정 패널 헤더 높이
    public static let paneHeaderHeight: CGFloat = 36
    /// 페인 내부 컨트롤 오버레이 바 높이 (hover 시 노출)
    public static let paneControlBarHeight: CGFloat = 44

    // MARK: Splitter
    /// 영상/채팅 분할선 기본 두께
    public static let splitHandleThickness: CGFloat = 1
    /// 분할선 hover 확장 두께 (드래그 타겟)
    public static let splitHandleHoverThickness: CGFloat = 6
    /// 분할선 드래그 히트 존 (실제 마우스 영역, 시각적 두께보다 넓게)
    public static let splitHandleHitSize: CGFloat = 12

    // MARK: Pane
    /// 페인 모서리 반경 (그리드 셀)
    public static let paneRadius: CGFloat = DesignTokens.Radius.md
    /// 선택된 페인 네온 테두리 두께
    public static let paneSelectedStroke: CGFloat = 1.5
    /// 오디오 활성 페인 링 두께
    public static let paneAudioRing: CGFloat = 1
    /// 페인 간 간격 (그리드)
    public static let paneGap: CGFloat = DesignTokens.Spacing.xs

    // MARK: Chip / Tab
    /// 탭 칩 최소 너비
    public static let tabChipMinWidth: CGFloat = 132
    /// 탭 칩 최대 너비 (채널명 절단)
    public static let tabChipMaxWidth: CGFloat = 220
    /// 오버레이용 원형 아이콘 버튼 지름
    public static let overlayIconSize: CGFloat = 32
    /// 인라인 pill 높이
    public static let pillHeight: CGFloat = 28

    // MARK: Chat
    /// 채팅 메시지 행 수직 패딩
    public static let chatRowVPad: CGFloat = 3
    /// 채팅 메시지 행 수평 패딩
    public static let chatRowHPad: CGFloat = DesignTokens.Spacing.md
    /// 채팅 이모지 인라인 크기 (본문과 높이 일치)
    public static let chatEmojiSize: CGFloat = 20
    /// 머지 채팅에서 채널 표시 뱃지 너비
    public static let channelBadgeWidth: CGFloat = 6

    // MARK: Following Card
    /// Following 진입 카드 최소 높이
    public static let entryCardMinHeight: CGFloat = 72
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Selection / Audio Glow Modifier
// ═══════════════════════════════════════════════════════════════════

extension View {
    /// 멀티라이브 페인용 선택/오디오 상태 chrome.
    /// - 선택: Chzzk 네온 그린 테두리 + 은은한 글로우
    /// - 오디오만: 얇은 그린 링 (글로우 없음)
    /// - 일반: 얇은 중립 테두리
    func msPaneChrome(
        isSelected: Bool,
        isAudioActive: Bool,
        radius: CGFloat = MSTokens.paneRadius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let strokeColor: Color = {
            if isSelected { return DesignTokens.Colors.chzzkGreen }
            if isAudioActive { return DesignTokens.Colors.chzzkGreen.opacity(0.55) }
            return DesignTokens.Glass.borderColor
        }()
        let strokeWidth: CGFloat = isSelected
            ? MSTokens.paneSelectedStroke
            : (isAudioActive ? MSTokens.paneAudioRing : 0.5)
        return self
            .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
            .shadow(
                color: isSelected
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.28)
                    : .clear,
                radius: isSelected ? 10 : 0
            )
            .animation(DesignTokens.Animation.fast, value: isSelected)
            .animation(DesignTokens.Animation.fast, value: isAudioActive)
    }
}
// MARK: - MultiStage/MSControls.swift
// 멀티 무대 전용 공용 컨트롤: pill 버튼 · 원형 아이콘 버튼 · 세그먼티드 스위처.
// 기존 UIComponents와 독립적으로 "멀티 영역"의 시각 문법을 통일하기 위한 로컬 프리미티브.

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSChipButton (Pill + Icon + Label)
// ═══════════════════════════════════════════════════════════════════

/// 탭바/오버레이/시트 공통 pill 버튼.
struct MSChipButton: View {
    enum Style {
        case ghost        // 투명 + 호버 시 surfaceElevated
        case solid        // surfaceElevated 고정
        case accent       // chzzkGreen 틴트 (활성 상태)
        case destructive  // red 틴트
    }

    let icon: String?
    let title: String?
    var style: Style = .ghost
    var isActive: Bool = false
    var count: Int? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .font(DesignTokens.Typography.captionSemibold)
                        .lineLimit(1)
                }
                if let count, count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.microSemibold)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.22))
                        )
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
            }
            .foregroundStyle(foreground)
            .frame(height: MSTokens.pillHeight)
            .padding(.horizontal, DesignTokens.Spacing.sm + 2)
            .background(
                Capsule(style: .continuous).fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovering)
        .animation(DesignTokens.Animation.fast, value: isActive)
    }

    private var foreground: Color {
        if isActive {
            switch style {
            case .accent, .ghost, .solid: return DesignTokens.Colors.chzzkGreen
            case .destructive: return DesignTokens.Colors.error
            }
        }
        switch style {
        case .ghost, .solid: return DesignTokens.Colors.textPrimary
        case .accent:        return DesignTokens.Colors.chzzkGreen
        case .destructive:   return DesignTokens.Colors.error
        }
    }

    private var background: Color {
        if isActive {
            return DesignTokens.Colors.chzzkGreen.opacity(0.15)
        }
        switch style {
        case .ghost:
            return isHovering ? DesignTokens.Colors.surfaceElevated : .clear
        case .solid:
            return isHovering
                ? DesignTokens.Colors.surfaceOverlay
                : DesignTokens.Colors.surfaceElevated
        case .accent:
            return DesignTokens.Colors.chzzkGreen.opacity(isHovering ? 0.22 : 0.12)
        case .destructive:
            return DesignTokens.Colors.error.opacity(isHovering ? 0.18 : 0.10)
        }
    }

    private var border: Color {
        if isActive {
            return DesignTokens.Colors.chzzkGreen.opacity(0.45)
        }
        return DesignTokens.Glass.borderColor.opacity(isHovering ? 1.0 : 0.6)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSIconButton (Circular, for overlays on dark media)
// ═══════════════════════════════════════════════════════════════════

/// 영상 위에 얹는 원형 아이콘 버튼 (화이트 텍스트 on 반투명).
/// - 호버 시 표면이 한 단계 밝아지고, 활성 시 Chzzk 그린으로 채워진다.
struct MSIconButton: View {
    let icon: String
    var size: CGFloat = MSTokens.overlayIconSize
    var isActive: Bool = false
    var tint: Color? = nil
    var help: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(background)
                    .overlay(Circle().stroke(border, lineWidth: 0.5))
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help ?? "")
        .animation(DesignTokens.Animation.micro, value: isHovering)
        .animation(DesignTokens.Animation.micro, value: isActive)
    }

    private var background: Color {
        if isActive { return DesignTokens.Colors.chzzkGreen }
        return DesignTokens.Colors.controlOnDarkMedia.opacity(isHovering ? 1.0 : 0.7)
    }
    private var foreground: Color {
        if isActive { return DesignTokens.Colors.onPrimary }
        return tint ?? DesignTokens.Colors.textOnDarkMedia
    }
    private var border: Color {
        isActive
            ? DesignTokens.Colors.chzzkGreen.opacity(0.65)
            : DesignTokens.Colors.borderOnDarkMedia
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSSegmentedSwitcher (Grid/List, Tab/Channel, etc.)
// ═══════════════════════════════════════════════════════════════════

/// 두 개 이상의 상호 배타적 모드를 토글하는 세그먼티드 스위처.
/// SwiftUI `Picker(.segmented)`보다 높은 밀도와 Chzzk 그린 활성 표시를 제공한다.
struct MSSegmentedSwitcher<Value: Hashable>: View {
    struct Item: Identifiable {
        let id: Value
        let icon: String?
        let title: String?
        var help: String? = nil
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(DesignTokens.Animation.fast) {
                        selection = item.id
                    }
                } label: {
                    segment(for: item)
                }
                .buttonStyle(.plain)
                .help(item.help ?? "")
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func segment(for item: Item) -> some View {
        let selected = item.id == selection
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            if let title = item.title {
                Text(title).font(DesignTokens.Typography.captionSemibold)
            }
        }
        .foregroundStyle(
            selected ? DesignTokens.Colors.onPrimary : DesignTokens.Colors.textSecondary
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? DesignTokens.Colors.chzzkGreen : .clear)
        )
        .contentShape(Capsule())
    }
}
// MARK: - MultiStage/MSChrome.swift
// 멀티 무대 chrome 요소: LIVE 펄스 · 섹션 헤더 · 빈 상태 placeholder.

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSLiveDot
// ═══════════════════════════════════════════════════════════════════

/// LIVE 상태를 표시하는 펄스 점.
/// 기본은 Chzzk 그린을 쓰지만, 강조가 필요한 경우(예: 녹화/경고) red로 지정할 수 있다.
struct MSLiveDot: View {
    var size: CGFloat = 6
    var color: Color = DesignTokens.Colors.chzzkGreen
    var isPulsing: Bool = true

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: size * 2.3, height: size * 2.3)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(pulse ? 0.0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.55), radius: 3)
        }
        .onAppear {
            guard isPulsing else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSSectionHeader
// ═══════════════════════════════════════════════════════════════════

/// 시트/설정/패널 내부 섹션 헤더.
/// 좌측 타이틀 + 선택적 카운트 뱃지 + 우측 액션.
struct MSSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.subheadSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let count {
                    Text("\(count)")
                        .font(DesignTokens.Typography.captionSemibold)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.14))
                        )
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

extension MSSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, count: Int? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.trailing = EmptyView()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSEmptyStage
// ═══════════════════════════════════════════════════════════════════

/// 멀티라이브/멀티채팅 영역이 비었을 때의 안내.
struct MSEmptyStage: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                MSChipButton(
                    icon: "plus",
                    title: actionTitle,
                    style: .accent,
                    isActive: true,
                    action: action
                )
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: 360)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MSChannelAvatar
// ═══════════════════════════════════════════════════════════════════

/// 채널 아이콘 (원형) + 라이브 테두리 + 선택적 오디오 배지.
struct MSChannelAvatar<Content: View>: View {
    var size: CGFloat = 28
    var isLive: Bool = false
    var isAudio: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.Colors.surfaceElevated)
                .overlay(
                    Circle().stroke(
                        isLive
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Glass.borderColor,
                        lineWidth: isLive ? 1.5 : 0.5
                    )
                )
            content
                .clipShape(Circle())
                .padding(isLive ? 2 : 0)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if isAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.onPrimary)
                    .frame(width: size * 0.48, height: size * 0.48)
                    .background(Circle().fill(DesignTokens.Colors.chzzkGreen))
                    .overlay(
                        Circle().stroke(DesignTokens.Colors.background, lineWidth: 1)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
}

// MARK: - Liquid Glass (macOS 26 / Tahoe Style)
//
// macOS 26(Tahoe)부터 시스템 전역에 적용된 "Liquid Glass" 비주얼 언어를 구현한다.
// 핵심 구성 요소:
//  1. Material 베이스 (ultraThin/thin/regular) — blur + saturation
//  2. 선택 색상 오버레이 (Gradient, 0.18 → 0.04)
//  3. 상단 specular highlight (내부 top edge, white 0.22 → 0)
//  4. 상단 rim stroke (white 0.35 → clear) — 광원이 위에서 내려오는 느낌
//  5. 외곽 subtle stroke (Glass.borderColor) — 배경 대비
//  6. drop shadow (radius 6, y 2, opacity 0.20) — 떠 있는 느낌
//
// 모든 레이어는 `Shape` 파라미터로 받은 동일한 형상(Capsule/RoundedRectangle)에
// 클리핑되어 concentric curves 를 유지한다.

public struct LiquidGlassStyle {
    public enum Variant {
        /// 기본 상태 — 아주 은은한 유리
        case quiet
        /// hover 상태 — 유리가 밝아짐
        case hover
        /// 선택 상태 — tint 색으로 물든 유리
        case selected(tint: Color)
    }
}

public extension View {
    /// Liquid Glass(macOS 26 Tahoe) 배경을 임의의 Shape 에 적용한다.
    ///
    /// 사용 예:
    /// ```swift
    /// Text("Hi")
    ///     .padding(10)
    ///     .liquidGlass(shape: Capsule(), variant: .selected(tint: .green))
    /// ```
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(
        shape: S,
        variant: LiquidGlassStyle.Variant = .quiet,
        material: Material = DesignTokens.Glass.regular
    ) -> some View {
        self
            .background {
                ZStack {
                    // 1) Material blur 베이스
                    shape.fill(material)

                    // 2) Variant tint overlay
                    switch variant {
                    case .quiet:
                        shape.fill(Color.white.opacity(0.02))
                    case .hover:
                        shape.fill(Color.white.opacity(0.06))
                    case .selected(let tint):
                        shape.fill(
                            LinearGradient(
                                colors: [tint.opacity(0.20), tint.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // 3) 상단 specular highlight (내부 글로우)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.04),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.7)
                }
                .clipShape(shape)
            }
            .overlay {
                // 4) Outer rim — 광원 방향 (상단 밝음, 하단 어두움)
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: {
                                switch variant {
                                case .selected(let tint):
                                    return [
                                        tint.opacity(0.55),
                                        tint.opacity(0.20),
                                    ]
                                default:
                                    return [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.06),
                                    ]
                                }
                            }(),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
    }
}

