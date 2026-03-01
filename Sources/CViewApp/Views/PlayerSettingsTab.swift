// MARK: - PlayerSettingsTab.swift
// 플레이어 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

struct PlayerSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "재생 설정", icon: "play.circle.fill", color: DesignTokens.Colors.chzzkGreen) {
                    SettingsRow("기본 화질", icon: "4k.tv.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Picker("", selection: $settings.player.quality) {
                            ForEach(StreamQuality.allCases, id: \.self) { q in
                                Text(q.displayName).tag(q)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("재생 엔진", icon: "cpu", iconColor: DesignTokens.Colors.accentBlue) {
                        Picker("", selection: $settings.player.preferredEngine) {
                            ForEach(PlayerEngineType.allCases, id: \.self) { e in
                                Text(e.displayName).tag(e)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("자동 재생",
                                description: "채널 진입 시 즉시 재생을 시작합니다",
                                icon: "play.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.player.autoPlay)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("백그라운드 재생",
                                description: "앱이 비활성 상태여도 라이브 방송 재생을 유지합니다",
                                icon: "play.slash.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.player.continuePlaybackInBackground)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentPurple)
                            .labelsHidden()
                    }
                }

                SettingsSection(title: "저지연 최적화", icon: "bolt.circle.fill", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("저지연 모드",
                                description: "딜레이를 최소화합니다. 네트워크 부하가 증가할 수 있습니다",
                                icon: "bolt.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.player.lowLatencyMode)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("버퍼 시간",
                                description: "낮을수록 지연이 줄지만 끊김이 발생할 수 있습니다",
                                icon: "clock.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.player.bufferDuration, in: 0.5...8, step: 0.5)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                            Text(String(format: "%.1f초", settings.player.bufferDuration))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                    RowDivider()
                    SettingsRow("캐치업 속도",
                                description: "딜레이가 쌓일 때 재생 속도를 높여 따라잡습니다",
                                icon: "forward.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.player.catchupRate, in: 1.0...1.3, step: 0.01)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                            Text(String(format: "×%.2f", settings.player.catchupRate))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                }

                SettingsSection(title: "볼륨", icon: "speaker.wave.2.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("기본 볼륨", icon: "speaker.wave.2.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Slider(value: $settings.player.volumeLevel, in: 0...1, step: 0.05)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentPurple)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(Int(settings.player.volumeLevel * 100))%")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 36)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.player) { _, _ in Task { await settings.save() } }
    }
}
