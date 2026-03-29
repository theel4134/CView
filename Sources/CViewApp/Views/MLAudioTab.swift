// MARK: - MLAudioTab.swift
// 멀티라이브 설정 — 오디오 탭 (볼륨, A/V 싱크, 오디오 전용)

import SwiftUI
import CViewCore

struct MLAudioTab: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    @State private var volumeValue: Float = 1.0
    @State private var isMuted: Bool = false
    @State private var audioDelay: Double = 0
    @State private var isAudioOnly: Bool = false
    @State private var isMuteHovered: Bool = false

    private var playerVM: PlayerViewModel { session.playerViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 볼륨
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("볼륨")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                        .foregroundStyle(isMuted ? DesignTokens.Colors.error : DesignTokens.Colors.chzzkGreen)
                        .font(DesignTokens.Typography.caption)
                    Text(isMuted ? "음소거" : "\(Int(volumeValue * 100))%")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(value: $volumeValue, in: 0...1, step: 0.01)
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .onChange(of: volumeValue) { _, newVal in
                            playerVM.setVolume(newVal)
                            if isMuted && newVal > 0 {
                                isMuted = false
                                session.setMuted(false)
                            }
                        }

                    Button {
                        isMuted.toggle()
                        session.setMuted(isMuted)
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isMuted ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                    .fill(isMuteHovered ? Color.white.opacity(0.06) : .clear)
                            )
                            .scaleEffect(isMuteHovered ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { isMuteHovered = $0 }
                    .animation(DesignTokens.Animation.fast, value: isMuteHovered)
                }
            }

            Divider()

            // A/V 싱크 (오디오 지연)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("A/V 동기화")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Spacer()
                    Text(String(format: "%.1fms", audioDelay / 1000))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    if audioDelay != 0 {
                        Button {
                            audioDelay = 0
                            playerVM.setAudioDelay(0)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Slider(value: $audioDelay, in: -500_000...500_000, step: 10_000)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: audioDelay) { _, newVal in
                        playerVM.setAudioDelay(Int(newVal))
                    }

                Text("음수: 오디오가 빨라짐 / 양수: 오디오가 느려짐")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Divider()

            // 오디오 전용 모드
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오디오 전용")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Text("영상을 끄고 소리만 재생 (CPU 절약)")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $isAudioOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isAudioOnly) { _, _ in
                        playerVM.toggleAudioOnly()
                    }
            }
        }
        .onAppear {
            volumeValue = playerVM.volume
            isMuted = playerVM.isMuted
            audioDelay = Double(playerVM.audioDelay)
            isAudioOnly = playerVM.isAudioOnly
        }
        .id(session.id)
    }

    private var volumeIcon: String {
        if volumeValue == 0 { return "speaker.fill" }
        if volumeValue < 0.33 { return "speaker.wave.1.fill" }
        if volumeValue < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
