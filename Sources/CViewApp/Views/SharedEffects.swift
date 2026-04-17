// MARK: - SharedEffects.swift
// CViewApp - 공유 뷰 모디파이어, 이펙트, 헬퍼 뷰
// Shimmer 효과 + Live Pulse 배지 + 커서 헬퍼

import SwiftUI
import CViewCore

// MARK: - Shimmer Effect (Metal 3 Canvas)

// Metal 3 Canvas 기반 shimmer — GeometryReader/LinearGradient/offset 제거
// TimelineView(.animation) + Canvas: SwiftUI 레이아웃 엔진 우회, 단일 GPU 드로우 패스
// 20+ 동시 인스턴스에서 프레임별 레이아웃 연산 제거 → GPU 가속 shimmer sweep
struct ShimmerModifier: ViewModifier {
    private static let duration: Double = 1.8

    // easeInOut 커브: 양 끝에서 감속, 중앙에서 가속
    @inline(__always)
    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                // motionSafe: 접근성 모션 감소 시 shimmer 비활성화
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            let elapsed = timeline.date.timeIntervalSinceReferenceDate
                            let t = elapsed.truncatingRemainder(dividingBy: Self.duration) / Self.duration
                            let phase = CGFloat(Self.easeInOut(t) * 2 - 1)  // -1 → 1
                            let w = size.width

                            let gradient = Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: DesignTokens.Colors.textPrimary.opacity(0.06), location: 0.35),
                                .init(color: DesignTokens.Colors.textPrimary.opacity(0.10), location: 0.5),
                                .init(color: DesignTokens.Colors.textPrimary.opacity(0.06), location: 0.65),
                                .init(color: .clear, location: 1),
                            ])

                            context.fill(
                                Path(CGRect(origin: .zero, size: size)),
                                with: .linearGradient(
                                    gradient,
                                    startPoint: CGPoint(x: phase * w, y: 0),
                                    endPoint: CGPoint(x: (phase + 1) * w, y: 0)
                                )
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Live Pulse Badge
// 최소 LIVE 배지 — 소프트 글로우만, 무(無)애니메이션 → GPU/CPU 제로코스트

struct LivePulseBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(DesignTokens.Colors.textOnOverlay)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 1.0 : 0.5)
            Text("LIVE")
                .font(DesignTokens.Typography.custom(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(DesignTokens.Gradients.live)
                .shadow(color: DesignTokens.Colors.live.opacity(0.35), radius: 4, y: 1)
        )
        .clipShape(Capsule())
        .compositingGroup()
        .onAppear {
            withAnimation(DesignTokens.Animation.motionSafe(
                .easeInOut(duration: 3.0).repeatForever(autoreverses: true)
            )) {
                isPulsing = true
            }
        }
        .onDisappear {
            isPulsing = false
        }
    }
}

// MARK: - Subtle Hover Glow Modifier

struct SubtleGlowModifier: ViewModifier {
    let color: Color
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(0.15) : .clear,
                radius: isActive ? 8 : 0,
                y: isActive ? 2 : 0
            )
            .animation(DesignTokens.Animation.fast, value: isActive)
    }
}

extension View {
    func subtleGlow(_ color: Color, isActive: Bool) -> some View {
        modifier(SubtleGlowModifier(color: color, isActive: isActive))
    }
}

// MARK: - Pointing Hand Cursor Helper
// NOTE: Moved to CViewCore/Utilities/CursorHelper.swift for cross-module access
