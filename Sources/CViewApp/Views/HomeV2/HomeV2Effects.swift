// MARK: - HomeV2Effects.swift
// CViewApp - HomeView_v2 전용 시각 효과 모음 (60fps 최적화 버전)
//
// 최적화 원칙:
//   • TimelineView(.animation) 30Hz 폴링 제거 → SwiftUI implicit animation phase 기반
//     (CoreAnimation 이 GPU 합성 — Metal 백엔드. CPU 매 프레임 부담 0)
//   • 무한 애니메이션 뷰는 .drawingGroup() 으로 오프스크린 합성 → CALayer 단일 텍스처화
//   • @Environment(\.accessibilityReduceMotion) 존중 — 펄스/그라디언트 흐름 모두 비활성
//   • LazyVStack 셀 재사용 시 onAppear 가 반복 발화하므로 한 번 보이면 영구 유지
//
// 제공 모디파이어/뷰:
//   • HomeSectionAppear           : 섹션이 처음 나타날 때 위→아래 슬라이드 + 페이드 (인덱스 기반 stagger)
//   • HomeHoverLift               : 호버 시 들어올림 + 그림자 강화 + 색조 보더
//   • HomeAccentPulse             : 라이브/포인트 컬러 보더 펄스 (gentle breathing) — drawingGroup
//   • LivePulseDot                : LIVE 표시용 작은 빨간 점 — drawingGroup
//   • AnimatedGradientText        : 그라디언트가 천천히 흐르는 텍스트 — phase 기반 (TimelineView 미사용)

import SwiftUI
import CViewCore

// MARK: - Section Appear (한 번만 재생, ReduceMotion 존중)

struct HomeSectionAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Bool = false

    private var delay: Double { min(0.04 * Double(index), 0.32) }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (reduceMotion ? 0 : 10))
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.88).delay(delay)) {
                        visible = true
                    }
                }
            }
    }
}

extension View {
    func homeSectionAppear(index: Int) -> some View {
        modifier(HomeSectionAppear(index: index))
    }
}

// MARK: - Hover Lift

struct HomeHoverLift: ViewModifier {
    var lift: CGFloat = 2
    var scale: CGFloat = 1.012
    var accent: Color = DesignTokens.Colors.chzzkGreen
    var cornerRadius: CGFloat = DesignTokens.Radius.md
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered && !reduceMotion ? scale : 1.0, anchor: .center)
            .offset(y: hovered && !reduceMotion ? -lift : 0)
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

// MARK: - Accent Pulse Border (Metal 가속 — drawingGroup)

struct HomeAccentPulse: ViewModifier {
    var color: Color = DesignTokens.Colors.chzzkGreen
    var cornerRadius: CGFloat = DesignTokens.Radius.lg
    var enabled: Bool = true
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color.opacity(0.18 + 0.22 * phase), lineWidth: 1.0 + 0.6 * phase)
                        .blur(radius: 0.4)
                        .allowsHitTesting(false)
                        .drawingGroup()  // GPU 합성으로 위임 (Metal)
                }
            }
            .shadow(
                color: enabled ? color.opacity(0.10 + 0.10 * phase) : .clear,
                radius: enabled ? 10 + 4 * phase : 0,
                y: 3
            )
            .onAppear {
                guard enabled, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
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

// MARK: - Live Pulse Dot (Metal 가속)

struct LivePulseDot: View {
    var size: CGFloat = 6
    var color: Color = DesignTokens.Colors.live
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .frame(width: size * 2.5, height: size * 2.5)
        .drawingGroup()  // 단일 Metal 텍스처로 합성 — 화면 내 N개 인스턴스 비용 ↓
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Animated Gradient Text (TimelineView 제거 — phase 기반)

/// 그라디언트가 천천히 흐르는 텍스트.
/// 기존 TimelineView(.animation) 30Hz 폴링 → SwiftUI implicit animation phase 로 교체.
/// CPU 매 프레임 호출 비용 0, GPU 만 사용.
struct AnimatedGradientText: View {
    let text: String
    var font: Font = DesignTokens.Typography.titleSemibold
    var colors: [Color] = [
        DesignTokens.Colors.chzzkGreen,
        DesignTokens.Colors.textPrimary,
        DesignTokens.Colors.chzzkGreen
    ]
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                reduceMotion
                    ? AnyShapeStyle(DesignTokens.Colors.textPrimary)
                    : AnyShapeStyle(LinearGradient(
                        colors: colors,
                        startPoint: UnitPoint(x: phase - 0.3, y: 0),
                        endPoint: UnitPoint(x: phase + 0.7, y: 1)
                    ))
            )
            .onAppear {
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
    }
}
