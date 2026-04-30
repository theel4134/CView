// MARK: - AppIconView.swift
// CViewApp — 앱 아이콘 SwiftUI 렌더링 (사이드바, 스플래시 공용)

import SwiftUI
import CViewCore
import CViewUI

// MARK: - App Icon View

struct AppIconView: View {
    let size: CGFloat
    var showLiveDot: Bool = true
    var animated: Bool = false

    @State private var glowPulse: Bool = false

    var body: some View {
        ZStack {
            // ── 배경 그라디언트 ──────────────────────────────────────
            LinearGradient(
                colors: [Color(hex: 0x0A0C1A), Color(hex: 0x12182C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // ── 글로우 원 ────────────────────────────────────────────
            Circle()
                .fill(DesignTokens.Colors.chzzkGreen.opacity(animated && glowPulse ? 0.18 : 0.10))
                .frame(width: size * 0.62, height: size * 0.62)
                .blur(radius: size * 0.08)
                .animation(
                    animated ? DesignTokens.Animation.motionSafe(DesignTokens.Animation.pulse) : .default,
                    value: glowPulse
                )

            // ── 스크린 패널 ──────────────────────────────────────────
            if size >= 28 {
                RoundedRectangle(cornerRadius: size * 0.12)
                    .fill(Color(hex: 0x16183A).opacity(0.85))
                    .frame(width: size * 0.66, height: size * 0.60)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.12)
                            .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.22), lineWidth: max(0.5, size * 0.01))
                    }
            }

            // ── 플레이 삼각형 ────────────────────────────────────────
            PlayTriangle()
                .fill(DesignTokens.Colors.chzzkGreen)
                .frame(width: size * 0.38, height: size * 0.38)
                .offset(x: -size * 0.02)
                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.6), radius: size * 0.06)

            // ── LIVE 뱃지 (우상단) ───────────────────────────────────
            if showLiveDot && size >= 20 {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(hex: 0xFF2D2D))
                            .frame(width: size * 0.18, height: size * 0.18)
                            .overlay {
                                Circle()
                                    .fill(.white)
                                    .frame(width: size * 0.08, height: size * 0.08)
                            }
                            .shadow(color: Color(hex: 0xFF2D2D).opacity(0.7), radius: size * 0.04)
                    }
                    Spacer()
                }
                .padding(size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.20), lineWidth: max(0.5, size * 0.012))
        }
        // Metal 오프스크린 합성 — blur·shadow·gradient 레이어를 GPU에서 일괄 처리
        .drawingGroup(opaque: false)
        .onAppear {
            if animated { glowPulse = true }
        }
    }
}

// MARK: - Play Triangle Shape

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 1.0, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.92))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        AppIconView(size: 32)
        AppIconView(size: 64, animated: true)
        AppIconView(size: 128, animated: true)
    }
    .padding(40)
    .background(Color(hex: 0x0A0A0A))
}
