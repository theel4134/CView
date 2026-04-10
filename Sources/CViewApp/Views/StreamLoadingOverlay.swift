// MARK: - StreamLoadingOverlay.swift
// 라이브 스트리밍 로딩/버퍼링 시 표시되는 풍부한 오버레이 뷰

import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Stream Loading Overlay

/// 스트리밍 연결/버퍼링/재연결 단계에서 표시되는 오버레이.
///
/// - 썸네일 배경 (블러)
/// - 회전 호 스피너 + 녹색 링 펄스
/// - 단계별 상태 텍스트 (연결 중 / 버퍼링 / 재연결 중 / 불러오는 중)
/// - 채널명 / 스트림 제목
/// - 버퍼 상태 바 (bufferHealth 제공 시)
struct StreamLoadingOverlay: View {

    let channelId: String
    let channelName: String
    let liveTitle: String
    let thumbnailURL: URL?
    let streamPhase: StreamCoordinator.StreamPhase?
    /// 0.0~1.0 (nil = 미제공)
    let bufferLevel: Double?
    /// true = API 요청 단계 (streamPhase 아직 .idle)
    let isApiLoading: Bool

    // MARK: - Animation State

    @State private var spinnerRotation: Double = 0
    @State private var ringScale: CGFloat = 0.82
    @State private var ringOpacity: Double = 0.5
    @State private var contentOpacity: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── 배경: 블러된 썸네일 ──────────────────────────
            thumbnailBackground

            // ── 다크 베일 ────────────────────────────────────
            Color.black.opacity(0.62)

            // ── 콘텐츠 ───────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()
                spinnerSection
                    .padding(.bottom, DesignTokens.Spacing.lg)
                infoSection
                    .padding(.bottom, DesignTokens.Spacing.md)
                if let level = bufferLevel {
                    bufferBar(level: level)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.bottom, DesignTokens.Spacing.sm)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(contentOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(DesignTokens.Animation.normal) {
                contentOpacity = 1.0
            }
            // 링 펄스: 단발 애니메이션으로 변경 (repeatForever 제거)
            withAnimation(.easeOut(duration: 0.6)) {
                ringScale = 1.0
                ringOpacity = 1.0
            }
            if let anim = DesignTokens.Animation.motionSafe(DesignTokens.Animation.loadingSpin) {
                withAnimation(anim) {
                    spinnerRotation = 360
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                AsyncImage(url: thumbnailURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 12, opaque: true)
                            .scaleEffect(1.04)
                            .drawingGroup(opaque: true)
                    }
                }
            }
        }
    }

    private var spinnerSection: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            // 링 + 회전 스피너 + 중앙 아이콘
            ZStack {
                // 서클 글로우
                Circle()
                    .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.12), lineWidth: 1)
                    .frame(width: 72, height: 72)
                    .scaleEffect(ringScale * 1.2)
                    .opacity(ringOpacity * 0.6)

                // 내부 배경 원
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))

                // 회전 호 스피너 — thin stroke
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        DesignTokens.Colors.chzzkGreen,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(spinnerRotation))

                // 중앙 SF Symbol
                Image(systemName: phaseIcon)
                    .font(DesignTokens.Typography.custom(size: 20, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .symbolEffect(.pulse)
            }

            // 상태 텍스트
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text(phaseTitle)
                    .font(DesignTokens.Typography.custom(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .contentTransition(.numericText())
                    .id(phaseTitle)
                    .transition(.blurReplace)

                Text(phaseSubtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.50))
                    .id(phaseSubtitle)
                    .transition(.blurReplace)
            }
            .animation(DesignTokens.Animation.spring, value: phaseTitle)
        }
    }

    private var infoSection: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            if !channelName.isEmpty {
                Text(channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .lineLimit(1)
            }
            if !liveTitle.isEmpty {
                Text(liveTitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
            }
        }
    }

    @ViewBuilder
    private func bufferBar(level: Double) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            HStack {
                Text("버퍼")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text("\(Int(level * 100))%")
                    .font(DesignTokens.Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(
                        level > 0.3
                        ? DesignTokens.Colors.chzzkGreen
                        : DesignTokens.Colors.warning
                    )
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: level > 0.3
                                    ? [DesignTokens.Colors.chzzkGreen.opacity(0.75), DesignTokens.Colors.chzzkGreen]
                                    : [DesignTokens.Colors.warning.opacity(0.75), DesignTokens.Colors.warning],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0, min(1, level)), height: 3)
                        .animation(DesignTokens.Animation.smooth, value: level)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Phase Helpers

    private var phaseTitle: String {
        if isApiLoading { return "불러오는 중..." }
        guard let phase = streamPhase else { return "불러오는 중..." }
        switch phase {
        case .connecting:    return "스트림에 연결하는 중..."
        case .buffering:     return "버퍼링 중..."
        case .reconnecting:  return "재연결하는 중..."
        default:             return "불러오는 중..."
        }
    }

    private var phaseSubtitle: String {
        if isApiLoading { return "스트림 정보를 가져오고 있습니다" }
        guard let phase = streamPhase else { return "잠시만 기다려 주세요" }
        switch phase {
        case .connecting:    return "서버와 연결을 설정하고 있습니다"
        case .buffering:     return "재생 데이터를 준비하고 있습니다"
        case .reconnecting:  return "연결이 끊어져 다시 연결합니다"
        default:             return "잠시만 기다려 주세요"
        }
    }

    private var phaseIcon: String {
        if isApiLoading { return "arrow.down.circle" }
        guard let phase = streamPhase else { return "arrow.down.circle" }
        switch phase {
        case .connecting:    return "network"
        case .buffering:     return "play.fill"
        case .reconnecting:  return "arrow.clockwise"
        default:             return "arrow.down.circle"
        }
    }
}
