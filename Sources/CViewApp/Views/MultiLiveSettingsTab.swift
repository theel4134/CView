// MARK: - MultiLiveSettingsTab.swift
// 멀티라이브 설정 탭 (SettingsView에서 호출)

import SwiftUI
import CViewCore
import CViewPersistence

struct MultiLiveSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // MARK: - 세션 관리
                SettingsSection(title: "세션 관리", icon: "square.grid.2x2.fill", color: Color.green) {
                    SettingsRow("최대 동시 세션",
                                description: "동시에 시청할 수 있는 최대 채널 수 (2~6)",
                                icon: "number.square.fill", iconColor: Color.green) {
                        Stepper(value: $settings.multiLive.maxConcurrentSessions, in: 2...6) {
                            Text("\(settings.multiLive.maxConcurrentSessions)개")
                                .font(DesignTokens.Typography.custom(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    RowDivider()
                    SettingsRow("기본 엔진",
                                description: "멀티라이브에서 사용할 기본 재생 엔진",
                                icon: "cpu", iconColor: DesignTokens.Colors.accentBlue) {
                        Picker("", selection: $settings.multiLive.preferredEngine) {
                            ForEach(PlayerEngineType.allCases, id: \.self) { e in
                                Text(e.displayName).tag(e)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("레이아웃 모드",
                                description: "멀티라이브 기본 화면 배치 방식",
                                icon: "rectangle.split.2x2.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        Picker("", selection: $settings.multiLive.defaultLayoutMode) {
                            ForEach(MultiLiveLayoutMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .frame(width: 170)
                        .labelsHidden()
                    }
                }

                // MARK: - 오디오
                SettingsSection(title: "오디오", icon: "speaker.wave.2.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("멀티오디오",
                                description: "여러 채널의 소리를 동시에 재생합니다",
                                icon: "speaker.wave.3.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.multiLive.multiAudioEnabled)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentPurple)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("보조 스트림 볼륨",
                                description: "선택되지 않은 채널의 기본 볼륨",
                                icon: "speaker.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.multiLive.secondaryVolume, in: 0...1, step: 0.05)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentPurple)
                                .disabled(!settings.multiLive.multiAudioEnabled)
                            Text(String(format: "%d%%", Int(settings.multiLive.secondaryVolume * 100)))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                }

                // MARK: - 품질 및 안정성
                SettingsSection(title: "품질 및 안정성", icon: "gauge.with.dots.needle.33percent", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("백그라운드 품질 저하",
                                description: "비활성 세션의 화질을 낮춰 리소스를 절약합니다",
                                icon: "arrow.down.circle.fill", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.multiLive.backgroundQualityReduction)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentOrange)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("자동 재연결",
                                description: "스트림 연결이 끊어지면 자동으로 재연결합니다",
                                icon: "arrow.triangle.2.circlepath", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.multiLive.autoReconnect)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("최대 재시도 횟수",
                                description: "자동 재연결 최대 시도 횟수",
                                icon: "repeat", iconColor: DesignTokens.Colors.textSecondary) {
                        Stepper(value: $settings.multiLive.autoReconnectMaxRetries, in: 1...30) {
                            Text("\(settings.multiLive.autoReconnectMaxRetries)회")
                                .font(DesignTokens.Typography.custom(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .disabled(!settings.multiLive.autoReconnect)
                    }
                }

                // MARK: - 채팅
                SettingsSection(title: "채팅", icon: "bubble.left.and.bubble.right.fill", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("그리드 채팅 오버레이",
                                description: "그리드 모드에서 각 채널 위에 채팅을 표시합니다",
                                icon: "text.bubble.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.multiLive.chatOverlayInGrid)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentBlue)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("오버레이 투명도",
                                description: "채팅 오버레이의 배경 투명도",
                                icon: "circle.lefthalf.filled", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.multiLive.chatOverlayOpacity, in: 0...1, step: 0.05)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                                .disabled(!settings.multiLive.chatOverlayInGrid)
                            Text(String(format: "%d%%", Int(settings.multiLive.chatOverlayOpacity * 100)))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                    RowDivider()
                    SettingsRow("오버레이 글꼴 크기",
                                description: "채팅 오버레이 텍스트 크기 (8~24pt)",
                                icon: "textformat.size", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.multiLive.chatOverlayFontSize, in: 8...24, step: 1)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentBlue)
                                .disabled(!settings.multiLive.chatOverlayInGrid)
                            Text(String(format: "%.0fpt", settings.multiLive.chatOverlayFontSize))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 42)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onChange(of: settings.multiLive) { _, _ in
            settings.scheduleDebouncedSave()
        }
    }
}
