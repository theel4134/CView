// MARK: - MultiLiveStateViews.swift
// CViewApp - MLLoadingState + MLEmptyState + MLStatsOverlay + MLQualityPopover
// Extracted from MultiLiveOverlays.swift

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Loading State
struct MLLoadingState: View {
    let session: MultiLiveSession

    var body: some View {
        ZStack {
            Color.black
            if let url = session.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill).blur(radius: 20).opacity(0.35)
                } placeholder: { Color.clear }
                .ignoresSafeArea()
            }
            Color.black.opacity(0.45)
            VStack(spacing: DesignTokens.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.8)
                    .tint(DesignTokens.Colors.chzzkGreen)
                VStack(spacing: DesignTokens.Spacing.xs) {
                    let name = session.channelName.isEmpty ? session.channelId : session.channelName
                    Text(name)
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    Text("스트림 연결 중...")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State
struct MLEmptyState: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.6))
                .symbolEffect(.pulse)

            Text("멀티 라이브")
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text("여러 방송을 동시에 시청할 수 있습니다")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.sm) {
                featureCard(icon: "rectangle.grid.2x2", title: "그리드 모드", desc: "최대 4개 동시 시청")
                featureCard(icon: "speaker.wave.2.fill", title: "오디오 라우팅", desc: "개별 음량 조절")
                featureCard(icon: "bubble.left.and.bubble.right", title: "채팅 분리", desc: "각 채팅을 별도 표시")
                featureCard(icon: "arrow.up.left.and.arrow.down.right", title: "포커스 확대", desc: "원하는 방송 확대")
            }
            .frame(maxWidth: 340)

            Button {
                onAdd()
            } label: {
                Label("채널 추가", systemImage: "plus.circle.fill")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.chzzkGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            DesignTokens.Colors.backgroundElevated
                .overlay(
                    Image(systemName: "dot.squareshape.split.2x2")
                        .font(.system(size: 260, weight: .ultraLight))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.02))
                )
        )
    }

    private func featureCard(icon: String, title: String, desc: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 22, weight: .light))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
            Text(title)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(desc)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
    }
}

// MARK: - Stats Overlay
struct MLStatsOverlay: View {
    let session: MultiLiveSession
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .trailing, spacing: compact ? 2 : 4) {
            if let m = session.latestMetrics {
                statBadge("FPS", "\(Int(m.fps))")
                if let res = m.resolution {
                    statBadge("해상도", res)
                }
                statBadge("비트레이트", String(format: "%.1f Mbps", m.inputBitrateKbps / 1_000))
                statBadge("드롭", "\(m.droppedFramesDelta)")
                statBadge("버퍼", String(format: "%.0f%%", m.bufferHealth * 100))
                statBadge("네트워크", String(format: "%.1f Mbps", Double(m.networkBytesPerSec) * 8 / 1_000_000))
            } else {
                statBadge("통계", "수집 중...")
            }
        }
        .padding(compact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial.opacity(compact ? 0.8 : 0.9))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(DesignTokens.Spacing.xs)
    }

    private func statBadge(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: compact ? 8 : 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(DesignTokens.Typography.custom(size: compact ? 8 : 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Quality Popover
struct MLQualityPopover: View {
    let session: MultiLiveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("화질 선택")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            ForEach(session.playerViewModel.availableQualities, id: \.name) { q in
                Button {
                    Task { await session.playerViewModel.switchQuality(q) }
                } label: {
                    HStack {
                        Text(q.name)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Spacer()
                        if session.playerViewModel.currentQuality?.name == q.name {
                            Image(systemName: "checkmark")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 180)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

