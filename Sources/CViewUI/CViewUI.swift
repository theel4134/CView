// MARK: - CViewUI Module
// Dark Glass 디자인 시스템 v2 — 공유 UI 컴포넌트
// Glass + Pill + Spring 인터랙션

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - Loading Indicator (Glass Spinner)
// ═══════════════════════════════════════════════════════════════════

/// 로딩 인디케이터 — Glass 배경 + 브랜드 컬러 스피너
public struct CViewLoadingIndicator: View {
    let message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                // 외부 트랙
                Circle()
                    .strokeBorder(DesignTokens.Colors.border.opacity(0.3), lineWidth: 2.5)
                    .frame(width: 32, height: 32)

                // 회전 아크
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        AngularGradient(
                            colors: [DesignTokens.Colors.chzzkGreen.opacity(0), DesignTokens.Colors.chzzkGreen],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(spinnerRotation)
            }
            .onAppear { startSpinning() }

            if let message {
                Text(message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    @State private var spinnerRotation: Angle = .zero

    private func startSpinning() {
        guard let anim = DesignTokens.Animation.motionSafe(DesignTokens.Animation.loadingSpin) else { return }
        withAnimation(anim) {
            spinnerRotation = .degrees(360)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Live Badge (Glass Pill + Pulse)
// ═══════════════════════════════════════════════════════════════════

/// 라이브 뱃지 — Glass pill + 레드 그라데이션 + breath 펄스
public struct LiveBadge: View {
    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    @State private var isPulsing = false

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(Color.white)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                // shadow radius 보간 제거 — 매 프레임 GPU blur 재계산 방지
                // opacity toggle (2-state)로 교체: Core Animation이 alpha만 보간
                .opacity(isPulsing ? 1.0 : 0.5)
            Text("LIVE")
                .font(compact
                    ? DesignTokens.Typography.custom(size: 8, weight: .bold)
                    : DesignTokens.Typography.custom(size: 10, weight: .bold)
                )
                .tracking(0.5)
        }
        .padding(.horizontal, compact ? DesignTokens.Spacing.sm : DesignTokens.Spacing.md)
        .padding(.vertical, compact ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.xs)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFF3B30), Color(hex: 0xFF6259)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        .clipShape(Capsule())
        // drawingGroup 제거 — opaque:false는 offscreen Metal pass 추가 비용 발생
        .shadow(color: DesignTokens.Colors.live.opacity(0.35), radius: 6, y: 2)
        .onAppear {
            if DesignTokens.Animation.motionSafe(DesignTokens.Animation.pulse) != nil {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Viewer Count Badge (Glass Pill)
// ═══════════════════════════════════════════════════════════════════

/// 시청자 수 뱃지 — Glass pill + SF Symbol
public struct ViewerCountBadge: View {
    let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "eye.fill")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(formattedCount)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private var formattedCount: String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - User Avatar (Glass Ring)
// ═══════════════════════════════════════════════════════════════════

/// 사용자 아바타 — 원형 이미지 + optional 온라인 인디케이터
public struct UserAvatar: View {
    let imageUrl: String?
    let size: CGFloat
    let isLive: Bool

    public init(imageUrl: String?, size: CGFloat = 32, isLive: Bool = false) {
        self.imageUrl = imageUrl
        self.size = size
        self.isLive = isLive
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedAsyncImage(url: URL(string: imageUrl ?? "")) {
                Circle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(DesignTokens.Typography.custom(size: size * 0.4))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        isLive ? DesignTokens.Colors.chzzkGreen : DesignTokens.Glass.borderColor,
                        lineWidth: isLive ? 2 : 0.5
                    )
            }

            // 온라인 인디케이터
            if isLive {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay {
                        Circle()
                            .strokeBorder(DesignTokens.Colors.background, lineWidth: 1.5)
                    }
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Brand Button Style (Pill)
// ═══════════════════════════════════════════════════════════════════

/// 브랜드 버튼 스타일 — Pill 형태 + spring press
public struct CViewButtonStyle: ButtonStyle {
    public init() {}

    @State private var isHovered = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.bodyMedium)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.chzzkGreen.opacity(isHovered ? 0.85 : 1.0), in: Capsule())
            .foregroundStyle(DesignTokens.Colors.onPrimary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.micro, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .animation(DesignTokens.Animation.fast, value: isHovered)
            .customCursor(.pointingHand)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Pill Tag View
// ═══════════════════════════════════════════════════════════════════

/// 카테고리/태그 Pill — Glass 또는 Filled
public struct PillTagView: View {
    let text: String
    let icon: String?
    let isSelected: Bool
    let action: (() -> Void)?

    public init(_ text: String, icon: String? = nil, isSelected: Bool = false, action: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let content = HStack(spacing: DesignTokens.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.caption)
            }
            Text(text)
                .font(DesignTokens.Typography.captionMedium)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs + 2)
        .foregroundStyle(isSelected ? DesignTokens.Colors.onPrimary : DesignTokens.Colors.textSecondary)
        .background {
            if isSelected {
                Capsule().fill(DesignTokens.Colors.chzzkGreen)
            } else {
                Capsule().fill(DesignTokens.Colors.surfaceElevated)
                    .overlay {
                        Capsule().strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
                    }
            }
        }
        .clipShape(Capsule())

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stream Thumbnail View
// ═══════════════════════════════════════════════════════════════════

/// 스트림 썸네일 — 이미지 + Glass 오버레이 정보
public struct StreamThumbnailView: View {
    let imageUrl: String?
    let isLive: Bool
    let viewerCount: Int?
    let duration: String?
    let aspectRatio: CGFloat

    public init(
        imageUrl: String?,
        isLive: Bool = false,
        viewerCount: Int? = nil,
        duration: String? = nil,
        aspectRatio: CGFloat = 16.0 / 9.0
    ) {
        self.imageUrl = imageUrl
        self.isLive = isLive
        self.viewerCount = viewerCount
        self.duration = duration
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 썸네일 이미지
            CachedAsyncImage(url: URL(string: imageUrl ?? "")) {
                Rectangle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .overlay {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }
            .aspectRatio(aspectRatio, contentMode: .fill)
            .clipped()

            // 하단 그라데이션 오버레이
            DesignTokens.Gradients.thumbnailOverlay

            // 뱃지들
            HStack {
                if isLive {
                    LiveBadge(compact: true)
                }
                Spacer()
                if let viewerCount {
                    ViewerCountBadge(count: viewerCount)
                }
                if let duration {
                    Text(duration)
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
            .padding(DesignTokens.Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }
}
