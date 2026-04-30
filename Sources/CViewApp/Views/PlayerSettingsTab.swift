// MARK: - PlayerSettingsTab.swift
// 플레이어 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

struct PlayerSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("플레이어")

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
                    SettingsRow("스트림 보정 모드",
                                description: settings.player.streamProxyMode.description
                                    + (settings.player.streamProxyMode.isExperimental ? " · 실험적" : ""),
                                icon: "network", iconColor: DesignTokens.Colors.accentBlue) {
                        Picker("", selection: $settings.player.streamProxyMode) {
                            ForEach(StreamProxyMode.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .frame(width: 220)
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
                    RowDivider()
                    SettingsRow("항상 최고 화질 유지 (1080p60)",
                                description: "ABR 자동 하향/해상도 캡핑을 비활성화하여 멀티라이브에서도 최고 화질을 고정합니다",
                                icon: "4k.tv.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.player.forceHighestQuality)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("선명한 화면 (픽셀 샤프)",
                                description: "스케일링 보간을 Nearest-Neighbor로 고정하여 픽셀 경계를 선명하게 유지합니다. 업스케일 시 계단감이 보일 수 있습니다",
                                icon: "square.grid.3x3.square", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.player.sharpPixelScaling)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("버퍼 크기",
                                description: "초기 버퍼 크기. 높을수록 안정적이지만 지연 증가",
                                icon: "clock.arrow.circlepath", iconColor: DesignTokens.Colors.accentOrange) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.player.bufferDuration, in: 0.5...10.0, step: 0.5)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentOrange)
                            Text(String(format: "%.1f초", settings.player.bufferDuration))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                                .frame(width: 40)
                        }
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

                SettingsSection(title: "스크린샷", icon: "camera.fill", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("저장 포맷", icon: "doc.richtext", iconColor: DesignTokens.Colors.accentBlue) {
                        Picker("", selection: $settings.player.screenshotFormat) {
                            ForEach(ScreenshotFormat.allCases, id: \.self) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        .frame(width: 100)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("저장 경로",
                                description: settings.player.screenshotPath,
                                icon: "folder.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Button("변경…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.prompt = "선택"
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.player.screenshotPath = url.path
                            }
                        }
                        .font(DesignTokens.Typography.caption)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onChange(of: settings.player) { _, _ in Task { await settings.save() } }
    }
}
