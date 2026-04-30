// MARK: - MultiLiveSettingsTab.swift
// 멀티라이브 설정 탭 (SettingsView에서 호출)

import SwiftUI
import CViewCore
import CViewPersistence

struct MultiLiveSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("멀티라이브")

                // MARK: - 세션 관리
                SettingsSection(title: "세션 관리", icon: "square.grid.2x2.fill", color: DesignTokens.Colors.chzzkGreen) {
                    SettingsRow("최대 동시 세션",
                                description: "동시에 시청할 수 있는 최대 채널 수 (2~6)",
                                icon: "number.square.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
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

                // MARK: - 프로세스 모드 (2026-04-19)
                SettingsSection(title: "프로세스 모드", icon: "rectangle.split.3x1", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("인스턴스 방식",
                                description: "분리 인스턴스: 각 채널을 별도 CView 프로세스(앱)로 띄워 안정성과 리소스를 분산합니다(권장).  단일 인스턴스: 기존처럼 모든 채널을 부모 앱 한 프로세스에서 함께 실행합니다.",
                                icon: "rectangle.split.3x1.fill", iconColor: DesignTokens.Colors.accentPurple) {
                        Picker("", selection: $settings.multiLive.useSeparateProcesses) {
                            Label("분리 인스턴스", systemImage: "rectangle.split.3x1.fill").tag(true)
                            Label("단일 인스턴스", systemImage: "square.fill").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        .labelsHidden()
                    }
                    if settings.multiLive.useSeparateProcesses {
                        RowDivider()
                        SettingsRow("자식 창 자동 배치",
                                    description: "자유 배치는 OS 기본 위치, 그리드는 균등 분할, 탭은 선택된 채널만 전체화면",
                                    icon: "square.grid.2x2.fill", iconColor: DesignTokens.Colors.accentPurple) {
                            Picker("", selection: $settings.multiLive.processLayoutMode) {
                                ForEach(MultiLiveProcessLayoutMode.allCases) { mode in
                                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 280)
                            .labelsHidden()
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

                // MARK: - 대역폭 조율 (flashls 기반)
                SettingsSection(title: "대역폭 조율", icon: "chart.bar.fill", color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("대역폭 자동 분배",
                                description: "세션 간 대역폭을 자동으로 분배하여 전체 안정성을 높입니다",
                                icon: "arrow.triangle.branch", iconColor: DesignTokens.Colors.accentCyan) {
                        Toggle("", isOn: $settings.multiLive.bandwidthCoordinationEnabled)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentCyan)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("화면 크기 화질 캡핑",
                                description: "패인 크기보다 높은 해상도를 제한하여 대역폭을 절약합니다",
                                icon: "rectangle.compress.vertical", iconColor: DesignTokens.Colors.accentCyan) {
                        Toggle("", isOn: $settings.multiLive.levelCappingEnabled)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentCyan)
                            .labelsHidden()
                            .disabled(!settings.multiLive.bandwidthCoordinationEnabled)
                    }
                    RowDivider()
                    SettingsRow("선택 세션 대역폭 가중치",
                                description: "선택된 채널에 더 많은 대역폭을 할당 (1.0=균등)",
                                icon: "star.fill", iconColor: DesignTokens.Colors.accentOrange) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.multiLive.selectedSessionBWWeight, in: 1.0...3.0, step: 0.1)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentCyan)
                                .disabled(!settings.multiLive.bandwidthCoordinationEnabled)
                            Text(String(format: "×%.1f", settings.multiLive.selectedSessionBWWeight))
                                .font(DesignTokens.Typography.custom(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .frame(width: 42, alignment: .trailing)
                        }
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
