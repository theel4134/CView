// MARK: - NetworkSettingsTab.swift
// 네트워크 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

struct NetworkSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Environment(AppState.self) private var appState
    @State private var selectedPreset: NetworkPreset = .balanced

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("네트워크")

                // MARK: - 네트워크 프리셋
                SettingsSection(title: "네트워크 프리셋", icon: "wand.and.stars", color: DesignTokens.Colors.chzzkGreen) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(NetworkPreset.allCases, id: \.self) { preset in
                                PresetButton(
                                    preset: preset,
                                    isSelected: selectedPreset == preset,
                                    action: { applyPreset(preset) }
                                )
                            }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: selectedPreset.icon)
                                .font(DesignTokens.Typography.custom(size: 11))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            Text(selectedPreset.description)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.md)
                }

                // MARK: - 연결 타임아웃
                SettingsSection(title: "연결 타임아웃", icon: "timer", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("API 요청 타임아웃",
                                description: "API 서버 응답 대기 최대 시간. 너무 짧으면 느린 네트워크에서 오류 빈발",
                                icon: "network", iconColor: DesignTokens.Colors.accentBlue) {
                        NetworkIntField(value: $settings.network.connectionTimeout, unit: "초", range: 5...60)
                    }
                    RowDivider()
                    SettingsRow("스트림 연결 타임아웃",
                                description: "라이브 스트림 초기 연결 대기 최대 시간",
                                icon: "video.badge.waveform", iconColor: DesignTokens.Colors.textSecondary) {
                        NetworkIntField(value: $settings.network.streamConnectionTimeout, unit: "초", range: 5...30)
                    }
                }

                // MARK: - API 설정
                SettingsSection(title: "API 설정", icon: "server.rack", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("요청 제한",
                                description: "초당 최대 API 요청 수 (너무 낮으면 실시간 업데이트에 영향)",
                                icon: "speedometer", iconColor: DesignTokens.Colors.accentBlue) {
                        NetworkIntField(value: $settings.network.requestRateLimit, unit: "req/s", range: 1...30)
                    }
                    RowDivider()
                    SettingsRow("캐시 유효 시간",
                                description: "API 응답을 캐시로 유지하는 시간",
                                icon: "clock.arrow.circlepath", iconColor: DesignTokens.Colors.textSecondary) {
                        NetworkIntField(value: $settings.network.cacheExpiry, unit: "초", range: 30...3600)
                    }
                    RowDivider()
                    SettingsRow("재시도 횟수",
                                description: "요청 실패 시 재시도 횟수",
                                icon: "arrow.clockwise", iconColor: DesignTokens.Colors.textSecondary) {
                        NetworkIntField(value: $settings.network.retryCount, unit: "회", range: 0...10)
                    }
                    RowDivider()
                    SettingsRow("호스트당 동시 연결",
                                description: "HTTP 호스트당 최대 동시 연결 수. 높을수록 병렬 요청이 빠르지만 서버 부하 증가",
                                icon: "arrow.left.arrow.right", iconColor: DesignTokens.Colors.textSecondary) {
                        NetworkIntField(value: $settings.network.maxConnectionsPerHost, unit: "개", range: 1...16)
                    }
                }

                // MARK: - WebSocket / 재연결
                SettingsSection(title: "WebSocket / 재연결", icon: "bolt.horizontal.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("자동 재연결",
                                description: "채팅 연결이 끊어졌을 때 자동으로 재연결합니다",
                                icon: "antenna.radiowaves.left.and.right", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.network.autoReconnect)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("최대 재연결 시도",
                                description: "연속 실패 후 포기하기까지의 시도 횟수",
                                icon: "arrow.triangle.2.circlepath", iconColor: DesignTokens.Colors.textSecondary) {
                        NetworkIntField(value: $settings.network.maxReconnectAttempts, unit: "회", range: 1...30)
                    }
                    RowDivider()
                    SettingsRow("재연결 기본 대기 시간",
                                description: "첫 번째 재연결 전 대기 시간. 이후 지수 백오프로 증가",
                                icon: "clock.badge.questionmark", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.network.reconnectBaseDelay, format: .number.precision(.fractionLength(1)))
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                            Text("초")
                                .font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }

                // MARK: - 스트림 프록시
                SettingsSection(title: "스트림 프록시", icon: "arrow.triangle.branch", color: DesignTokens.Colors.chzzkGreen) {
                    SettingsRow("CDN 프록시 사용",
                                description: "로컬 프록시를 통해 CDN의 잘못된 Content-Type(video/MP2T)을 video/mp4로 수정합니다. VLC/AVPlayer 모두 해당. 문제 발생 시 비활성화",
                                icon: "arrow.left.arrow.right.circle.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.network.forceStreamProxy)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.chzzkGreen).labelsHidden()
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onChange(of: settings.network) { _, newValue in
            Task {
                await settings.save()
                await appState.apiClient?.updateRetryCount(newValue.retryCount)
            }
            // 수동 변경 시 프리셋 자동 감지
            let detected = newValue.matchingPreset()
            if selectedPreset != detected {
                selectedPreset = detected
            }
        }
        .onAppear {
            selectedPreset = settings.network.matchingPreset()
        }
    }

    private func applyPreset(_ preset: NetworkPreset) {
        selectedPreset = preset
        guard preset != .custom else { return }
        settings.network = preset.settings
    }
}

/// 프리셋 선택 버튼
private struct PresetButton: View {
    let preset: NetworkPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(DesignTokens.Typography.custom(size: 14))
                Text(preset.displayName)
                    .font(DesignTokens.Typography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? DesignTokens.Colors.chzzkGreen.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Glass.borderColor, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// 정수 입력 필드 + 단위 레이블 조합 (NetworkSettingsTab 전용)
private struct NetworkIntField: View {
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .frame(width: 52)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onChange(of: value) { _, newVal in
                    if !range.contains(newVal) {
                        value = min(max(newVal, range.lowerBound), range.upperBound)
                    }
                }
            Text(unit)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}
