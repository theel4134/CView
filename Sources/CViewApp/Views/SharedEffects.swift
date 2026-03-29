// MARK: - SharedEffects.swift
// CViewApp - 공유 뷰 모디파이어, 이펙트, 헬퍼 뷰
// Shimmer 효과 + Live Pulse 배지 + 커서 헬퍼

import SwiftUI
import CViewCore

// MARK: - Shimmer Effect (Fluid Gradient Sweep)

// CA 기반 shimmer — 소프트 3-stop gradient sweep, GPU 오프로드
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: DesignTokens.Colors.textPrimary.opacity(0.06), location: 0.35),
                            .init(color: DesignTokens.Colors.textPrimary.opacity(0.10), location: 0.5),
                            .init(color: DesignTokens.Colors.textPrimary.opacity(0.06), location: 0.65),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w)
                    .offset(x: phase * w)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
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
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(DesignTokens.Colors.live)
                .shadow(color: DesignTokens.Colors.live.opacity(0.35), radius: 4, y: 1)
        )
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
    }
}

extension View {
    func subtleGlow(_ color: Color, isActive: Bool) -> some View {
        modifier(SubtleGlowModifier(color: color, isActive: isActive))
    }
}

// MARK: - Pointing Hand Cursor Helper
// NOTE: Moved to CViewCore/Utilities/CursorHelper.swift for cross-module access
