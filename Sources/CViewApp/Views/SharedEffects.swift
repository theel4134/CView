// MARK: - SharedEffects.swift
// CViewApp - 공유 뷰 모디파이어, 이펙트, 헬퍼 뷰
// Shimmer 효과 + Live Pulse 배지 + 커서 헬퍼

import SwiftUI
import CViewCore

// MARK: - Shimmer Effect

// Core Animation 기반 shimmer — TimelineView + GeometryReader 제거
// 단일 offset 애니메이션 → CA 오프로드
struct ShimmerModifier: ViewModifier {
    @State private var moveToRight = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [
                            .clear,
                            DesignTokens.Colors.textPrimary.opacity(0.08),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: moveToRight ? width * 1.2 : -width * 0.6)
                }
                .clipped()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        moveToRight = true
                    }
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
// 정적 LIVE 배지 — GPU/CPU 제로코스트
// TimelineView / repeatForever 완전 제거 → 렌더링 파이프라인 idle

struct LivePulseBadge: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs + 1)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.live)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
    }
}

// MARK: - Pointing Hand Cursor Helper
// NOTE: Moved to CViewCore/Utilities/CursorHelper.swift for cross-module access
