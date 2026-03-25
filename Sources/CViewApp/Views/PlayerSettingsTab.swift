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

                // ── 레이턴시 동기화 (LatencySettingsFull) ──
                LatencySettingsFull(settings: settings)

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
