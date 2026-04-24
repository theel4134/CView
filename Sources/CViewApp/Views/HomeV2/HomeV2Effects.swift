// MARK: - HomeV2Effects.swift
// CViewApp - HomeView_v2 전용 시각 효과 모음
//
// 제공 모디파이어/뷰:
//   • HomeSectionAppear           : 섹션이 처음 나타날 때 위→아래 슬라이드 + 페이드 (인덱스 기반 stagger)
//   • HomeHoverLift               : 호버 시 살짝 들어올림 + 그림자 강화 + 색조 보더
//   • HomeAccentPulse             : 라이브/포인트 컬러 보더 펄스 (gentle breathing)
//   • LivePulseDot                : LIVE 표시용 작은 빨간 점 (스케일 + 글로우 펄스)
//   • AnimatedGradientText        : 그라디언트 색상이 천천히 흐르는 텍스트 (greeting 등)

import SwiftUI
import CViewCore

// MARK: - Section Appear

/// 섹션이 처음 표시될 때 stagger 페이드/슬라이드 인.
struct HomeSectionAppear: ViewModifier {
    let index: Int
    @State private var visible: Bool = false

    private var delay: Double { min(0.05 * Double(index), 0.45) }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .blur(radius: visible ? 0 : 2)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    /// 섹션 stagger 페이드/슬라이드 인.
    func homeSectionAppear(index: Int) -> some View {
        modifier(HomeSectionAppear(index: index))
    }
}

// MARK: - Hover Lift

/// 호버 시 살짝 들어올림 (-2pt) + 그림자 강화 + accent 보더 페이드 인.
struct HomeHoverLift: ViewModifier {
    var lift: CGFloat = 2
    var scale: CGFloat = 1.012
    var accent: Color = DesignTokens.Colors.chzzkGreen
    var cornerRadius: CGFloat = DesignTokens.Radius.md
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? scale : 1.0, anchor: .center)
            .offset(y: hovered ? -lift : 0)
            .shadow(
                color: hovered ? accent.opacity(0.22) : .black.opacity(0.08),
                radius: hovered ? 14 : 5,
                y: hovered ? 6 : 2
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        accent.opacity(hovered ? 0.55 : 0.0),
                        lineWidth: hovered ? 1.0 : 0.0
                    )
                    .allowsHitTesting(false)
            }
            .animation(DesignTokens.Animation.smooth, value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func homeHoverLift(
        lift: CGFloat = 2,
        scale: CGFloat = 1.012,
        accent: Color = DesignTokens.Colors.chzzkGreen,
        cornerRadius: CGFloat = DesignTokens.Radius.md
    ) -> some View {
        modifier(HomeHoverLift(lift: lift, scale: scale, accent: accent, cornerRadius: cornerRadius))
    }
}

// MARK: - Accent Pulse Border

/// 글로우 보더가 천천히 호흡하는 효과 (Hero/포인트 카드용).
struct HomeAccentPulse: ViewModifier {
    var color: Color = DesignTokens.Colors.chzzkGreen
    var cornerRadius: CGFloat = DesignTokens.Radius.lg
    var enabled: Bool = true
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color.opacity(0.18 + 0.22 * phase), lineWidth: 1.0 + 0.6 * phase)
                        .blur(radius: 0.4)
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: enabled ? color.opacity(0.10 + 0.12 * phase) : .clear,
                radius: enabled ? 10 + 6 * phase : 0,
                y: 3
            )
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func homeAccentPulse(
        color: Color = DesignTokens.Colors.chzzkGreen,
        cornerRadius: CGFloat = DesignTokens.Radius.lg,
        enabled: Bool = true
    ) -> some View {
        modifier(HomeAccentPulse(color: color, cornerRadius: cornerRadius, enabled: enabled))
    }
}

// MARK: - Live Pulse Dot

/// LIVE 표시용 작은 빨간 점 — 스케일 + 글로우 펄스.
struct LivePulseDot: View {
    var size: CGFloat = 6
    var color: Color = DesignTokens.Colors.live
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.45))
                .frame(width: size * (pulsing ? 2.4 : 1.0), height: size * (pulsing ? 2.4 : 1.0))
                .opacity(pulsing ? 0.0 : 0.55)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: pulsing ? 4 : 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Animated Gradient Text

/// 그라디언트가 천천히 흐르는 텍스트 (greeting 같은 head 텍스트에 사용).
struct AnimatedGradientText: View {
    let text: String
    var font: Font = DesignTokens.Typography.titleSemibold
    var colors: [Color] = [
        DesignTokens.Colors.chzzkGreen,
        DesignTokens.Colors.textPrimary,
        DesignTokens.Colors.chzzkGreen
    ]
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let shift = CGFloat(sin(t * 0.6)) * 0.5 + 0.5
            Text(text)
                .font(font)
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: UnitPoint(x: shift - 0.3, y: 0),
                        endPoint: UnitPoint(x: shift + 0.7, y: 1)
                    )
                )
        }
    }
}
