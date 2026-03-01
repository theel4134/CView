// MARK: - SplashView.swift
// CViewApp — 앱 초기 실행 스플래시 애니메이션

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Splash View

struct SplashView: View {

    var onFinished: () -> Void

    // MARK: Animation States

    @State private var iconScale: CGFloat = 0.4
    @State private var iconOpacity: CGFloat = 0
    @State private var textOpacity: CGFloat = 0
    @State private var textOffset: CGFloat = 14
    @State private var ring1Scale: CGFloat = 0.6
    @State private var ring1Opacity: CGFloat = 0
    @State private var ring2Scale: CGFloat = 0.6
    @State private var ring2Opacity: CGFloat = 0
    @State private var ring3Scale: CGFloat = 0.6
    @State private var ring3Opacity: CGFloat = 0
    @State private var fadeOut: CGFloat = 1

    var body: some View {
        ZStack {
            // 배경
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // ── 확산 링 ─────────────────────────────────────────────
            expandRing(scale: ring1Scale, opacity: ring1Opacity, radius: 130)
            expandRing(scale: ring2Scale, opacity: ring2Opacity, radius: 170)
            expandRing(scale: ring3Scale, opacity: ring3Opacity, radius: 210)

            // ── 아이콘 + 텍스트 ──────────────────────────────────────
            VStack(spacing: 20) {
                AppIconView(size: 110, showLiveDot: true, animated: true)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
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
                .opacity(textOpacity)
                .offset(y: textOffset)
            }
        }
        // Metal 3: compositingGroup — fadeOut opacity를 레이어별이 아닌 합성 후 단일 패스로 적용
        .compositingGroup()
        .opacity(fadeOut)
        .onAppear(perform: runAnimation)
    }

    // MARK: - Helpers

    private func expandRing(scale: CGFloat, opacity: CGFloat, radius: CGFloat) -> some View {
        Circle()
            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(opacity * 0.35), lineWidth: 1.5)
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(scale)
    }

    private func runAnimation() {
        // 1단계: 아이콘 등장 (스프링)
        withAnimation(DesignTokens.Animation.bouncy.delay(0.05)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }

        // 2단계: 링 확산
        withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
            ring1Scale = 1.0; ring1Opacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.25)) {
            ring2Scale = 1.0; ring2Opacity = 0.65
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.35)) {
            ring3Scale = 1.0; ring3Opacity = 0.35
        }

        // 링 페이드 아웃
        withAnimation(.easeIn(duration: 0.5).delay(0.7)) {
            ring1Opacity = 0; ring2Opacity = 0; ring3Opacity = 0
        }

        // 3단계: 텍스트 슬라이드 업
        withAnimation(DesignTokens.Animation.smooth.delay(0.35)) {
            textOpacity = 1.0
            textOffset = 0
        }

        // 4단계: 전체 페이드 아웃 → 메인 화면 전환
        withAnimation(DesignTokens.Animation.slow.delay(1.4)) {
            fadeOut = 0
        }
        // Swift Concurrency 기반 — DispatchQueue.main.asyncAfter 대체
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.85))
            onFinished()
        }
    }
}

#Preview {
    SplashView { }
        .frame(width: 500, height: 400)
}
