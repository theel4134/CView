// MARK: - SplashView.swift
// CViewApp — 앱 초기 실행 스플래시 애니메이션 (최적화)

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Splash View

struct SplashView: View {

    var onFinished: () -> Void

    // MARK: Animation States — 3개로 통합 (기존 7개에서 축소)

    @State private var phase: AnimationPhase = .initial
    @State private var fadeOut: CGFloat = 1

    private enum AnimationPhase {
        case initial    // 모든 요소 숨김
        case entrance   // 아이콘 + 링 + 텍스트 등장
        case ringsOut   // 링 페이드아웃
    }

    // 링 설정 (반복 코드 제거)
    private static let rings: [(radius: CGFloat, delay: Double, opacity: CGFloat)] = [
        (130, 0.10, 1.0),
        (170, 0.18, 0.65),
        (210, 0.26, 0.35),
    ]

    var body: some View {
        ZStack {
            // 배경
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // ── 확산 링 — ForEach로 통합 ─────────────────────────────
            ForEach(0..<Self.rings.count, id: \.self) { i in
                let ring = Self.rings[i]
                Circle()
                    .strokeBorder(
                        DesignTokens.Colors.chzzkGreen.opacity(ringOpacity(for: i) * 0.35),
                        lineWidth: 1.5
                    )
                    .frame(width: ring.radius * 2, height: ring.radius * 2)
                    .scaleEffect(phase == .initial ? 0.6 : 1.0)
                    .animation(
                        .easeOut(duration: 0.7 + Double(i) * 0.1).delay(ring.delay),
                        value: phase
                    )
            }
            // 링 합성을 Metal GPU 단일 패스로 오프로드
            .drawingGroup(opaque: false)

            // ── 아이콘 + 텍스트 ──────────────────────────────────────
            VStack(spacing: 20) {
                AppIconView(size: 110, showLiveDot: true, animated: true)
                    .scaleEffect(phase == .initial ? 0.4 : 1.0)
                    .opacity(phase == .initial ? 0 : 1)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 32)

                VStack(spacing: 6) {
                    Text("CView")
                        .font(DesignTokens.Typography.custom(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Text("치지직 스트리밍 뷰어")
                        .font(DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .tracking(0.8)
                }
                .opacity(phase == .initial ? 0 : 1)
                .offset(y: phase == .initial ? 14 : 0)
            }
        }
        // Metal 3: compositingGroup — fadeOut을 합성 후 단일 패스로 적용
        .compositingGroup()
        .opacity(fadeOut)
        .onAppear(perform: runAnimation)
    }

    // MARK: - Ring Opacity Helper

    private func ringOpacity(for index: Int) -> CGFloat {
        switch phase {
        case .initial: return 0
        case .entrance: return Self.rings[index].opacity
        case .ringsOut: return 0
        }
    }

    // MARK: - Animation Sequence (1.5초로 단축)

    private func runAnimation() {
        // 1단계: 아이콘 + 링 + 텍스트 동시 등장 (spring)
        withAnimation(DesignTokens.Animation.spring.delay(0.05)) {
            phase = .entrance
        }

        // 2단계: 링 페이드아웃
        withAnimation(.easeIn(duration: 0.4).delay(0.6)) {
            phase = .ringsOut
        }

        // 3단계: 전체 페이드 아웃 → 메인 화면 전환
        withAnimation(DesignTokens.Animation.smooth.delay(1.1)) {
            fadeOut = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            onFinished()
        }
    }
}

#Preview {
    SplashView { }
        .frame(width: 500, height: 400)
}
