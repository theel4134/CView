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

    // [Perf 2026-04-24] stagger 0.04 → 0.03 (7 섹션 누적 0.28 → 0.21s)
    private var delay: Double { min(0.03 * Double(index), 0.24) }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (reduceMotion ? 0 : 8))
            .onAppear {
                guard !visible else { return }
                // [Perf 2026-04-24] 메뉴 전환 중에는 explicit animation 도 생략.
                //   루트 transaction gate 는 implicit 만 막고 withAnimation 은 우회한다.
                //   메뉴 클릭 직후 7개 섹션 stagger 가 detail mount 비용과 겹쳐 첫
                //   프레임 드롭의 주범이었음 → 전환 중이면 즉시 표시.
                if reduceMotion || MenuTransitionGate.isTransitioning {
                    visible = true
                } else {
                    // easeOut 단조 곡선 (이전 spring 대비 잔진동 0).
                    withAnimation(.easeOut(duration: 0.22).delay(delay)) {
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
            // [Perf 2026-04-27] offset 제거 — scaleEffect 와 동시 적용 시 추가 geometry pass
            // 발생. scale 만으로 시각적 들어올림 효과 충분.
            // [Perf 2026-04-24] shadow radius 애니메이션 제거.
            //   이전: radius 가 5 ↔ 14 로 애니메이션 되면 SwiftUI 가 중간값마다
            //   가우시안 블러 커널을 재생성 → 호버 시 0.18s 동안 매 프레임 GPU 스파이크
            //   (클래식 stutter 원인). 수정: radius 고정 + opacity 만 애니메이션
            //   (CALayer 는 opacity 변화는 블러 재생성 없이 합성—비용 거의 0).
            .shadow(
                color: (hovered ? accent.opacity(0.22) : .black.opacity(0.08)),
                radius: 8,
                y: hovered ? 4 : 2
            )
            // [Perf 2026-04-27] overlay 조건부 렌더링 — opacity:0 상태에서도 strokeBorder
            // overlay 가 합성 레이어로 상시 존재하던 문제 수정. HomeContinueWatchingStrip
            // 12개 항목 × 1 레이어 절약 → WindowServer 합성 비용 감소.
            .overlay {
                if hovered {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(accent.opacity(0.55), lineWidth: 1.0)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
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
            // [Perf 2026-04-24] shadow radius 애니메이션 제거 — radius 가 변하면 GPU 가
            // 매 프레임 가우시안 블러를 재계산 (전형적 stutter 원인). 고정 radius 로 위임,
            // 펄스는 stroke 의 opacity/lineWidth 만 바뀌므로 합성 비용 ≈ 0.
            .shadow(
                color: enabled ? color.opacity(0.16) : .clear,
                radius: enabled ? 12 : 0,
                y: 3
            )
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled {
                    phase = 0
                }
            }
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
    var animate: Bool = false
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
                // [Perf 2026-04-24] shadow radius 애니메이션 → 고정.
                // pulsing 의 opacity/scale 만으로 충분히 "숨쉬는" 표현 가능.
                .shadow(color: color.opacity(0.55), radius: 2.5)
        }
        .frame(width: size * 2.5, height: size * 2.5)
        .onChange(of: animate) { _, shouldAnimate in
            if !shouldAnimate {
                pulsing = false
            }
        }
        .onAppear {
            guard animate, !reduceMotion else { return }
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
    var animate: Bool = false
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
                reduceMotion || !animate
                    ? AnyShapeStyle(DesignTokens.Colors.textPrimary)
                    : AnyShapeStyle(LinearGradient(
                        colors: colors,
                        startPoint: UnitPoint(x: phase - 0.3, y: 0),
                        endPoint: UnitPoint(x: phase + 0.7, y: 1)
                    ))
            )
            .onChange(of: animate) { _, shouldAnimate in
                if !shouldAnimate {
                    phase = 0
                }
            }
            .onAppear {
                guard animate, !reduceMotion else { return }
                phase = 0
                // [Perf] duration 5.2 → 7.0 — 사이클을 길게 하여 단위시간당 합성 frame 수 감소
                withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
    }
}
