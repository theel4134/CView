// MARK: - MLToolsTab.swift
// 멀티라이브 설정 — 도구 탭 (스크린샷, 녹화, 화질 선택)

import SwiftUI
import CViewCore

struct MLToolsTab: View {
    let playerVM: PlayerViewModel?
    @State private var isRecording = false
    @State private var isScreenshotHovered = false
    @State private var isRecordHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 스크린샷
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("스크린샷")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                Button {
                    playerVM?.takeScreenshot()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "camera.fill")
                            .font(DesignTokens.Typography.caption)
                        Text("현재 화면 캡처")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isScreenshotHovered ? DesignTokens.Colors.surfaceOverlay : DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(
                                isScreenshotHovered
                                    ? Color.white.opacity(0.12)
                                    : DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isScreenshotHovered = $0 }
                .animation(DesignTokens.Animation.fast, value: isScreenshotHovered)
            }

            Divider()

            // 녹화
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("녹화")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    if isRecording {
                        Circle()
                            .fill(DesignTokens.Colors.error)
                            .frame(width: 8, height: 8)
                        Text(playerVM?.formattedRecordingDuration ?? "")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.error)
                    }
                }

                Button {
                    Task {
                        if isRecording {
                            await playerVM?.stopRecording()
                            isRecording = false
                        } else {
                            await playerVM?.startRecordingWithSavePanel()
                            isRecording = playerVM?.isRecording ?? false
                        }
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isRecording ? DesignTokens.Colors.live : DesignTokens.Colors.textPrimary)
                        Text(isRecording ? "녹화 중지" : "녹화 시작")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isRecording
                                  ? DesignTokens.Colors.live.opacity(0.12)
                                  : isRecordHovered
                                      ? DesignTokens.Colors.surfaceOverlay
                                      : DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(
                                isRecording
                                    ? DesignTokens.Colors.live.opacity(0.3)
                                    : isRecordHovered
                                        ? Color.white.opacity(0.12)
                                        : DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isRecordHovered = $0 }
                .animation(DesignTokens.Animation.fast, value: isRecordHovered)
            }

            Divider()

            // 화질 선택
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("화질")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                let qualities = playerVM?.availableQualities ?? []
                if qualities.isEmpty {
                    Text("사용 가능한 화질 정보가 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    ForEach(qualities) { q in
                        Button {
                            Task { await playerVM?.switchQuality(q) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(q.name)
                                        .font(DesignTokens.Typography.captionMedium)
                                    Text(q.resolution)
                                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                Spacer()
                                if playerVM?.currentQuality?.id == q.id {
                                    Image(systemName: "checkmark")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                }
                            }
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(playerVM?.currentQuality?.id == q.id
                                          ? DesignTokens.Colors.chzzkGreen.opacity(0.1)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            isRecording = playerVM?.isRecording ?? false
        }
    }
}
