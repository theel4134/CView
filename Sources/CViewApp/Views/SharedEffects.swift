// MARK: - SharedEffects.swift
// CViewApp - 공유 뷰 모디파이어, 이펙트, 헬퍼 뷰
// Shimmer 효과 + Live Pulse 배지 + 커서 헬퍼

import SwiftUI
import CViewCore

// MARK: - Shimmer Effect

// Metal 3: TimelineView 드라이브 shimmer — CPU @State 애니메이션 루프 제거
// @State phase 변이 사이클 없이 GPU 타임라인에서 직접 phase 계산
struct ShimmerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    GeometryReader { geometry in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.5) / 1.5)
                        LinearGradient(
                            colors: [
                                .clear,
                                DesignTokens.Colors.textPrimary.opacity(0.1),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                        // Metal 오프스크린 합성 — TimelineView 드라이브 GPU 갱신
                        .drawingGroup()
                    }
                    .clipped()
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
// Metal 3: TimelineView 드라이브 — CPU @State repeatForever 루프 제거
// sin 파형으로 GPU 직접 계산, 30fps 최소 간격으로 쓸데없는 렌더 방지

struct LivePulseBadge: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 0.25 ~ 1.0 사이 sin 진동 (주기 1.8s = easeInOut 0.9s × 2)
            let opacity = sin(t * .pi / 0.9) * 0.375 + 0.625
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(opacity)
                Text("LIVE")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs + 1)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.live)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
        }
        .drawingGroup(opaque: false)  // 배지 전체를 단일 Metal 텍스처로 격리
    }
}
