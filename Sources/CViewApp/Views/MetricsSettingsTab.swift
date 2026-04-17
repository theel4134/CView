// MARK: - MetricsSettingsTab.swift
// 메트릭 서버 전송 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

/// 메트릭 서버 전송 설정 탭
@MainActor
struct MetricsSettingsTab: View {

    @Bindable var settings: SettingsStore
    @Environment(AppState.self) private var appState

    // MARK: 연결 테스트 상태
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false

    private enum ConnectionTestResult {
        case success(latencyMs: Double, message: String)
        case failure(message: String)

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .failure: "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .success: .green
            case .failure: .red
            }
        }
        var text: String {
            switch self {
            case .success(let ms, let msg): String(format: "연결 성공 (%.0fms) %@", ms, msg)
            case .failure(let msg): "연결 실패: \(msg)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("메트릭")

                // ─── 서버 설정 ────────────────────────────────
                SettingsSection(title: "서버 설정", icon: "server.rack", color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("메트릭 전송 활성화",
                                description: "라이브 시청 시 레이턴시·FPS·버퍼 데이터를 서버로 전송합니다.",
                                icon: "chart.line.uptrend.xyaxis", iconColor: DesignTokens.Colors.accentCyan) {
                        Toggle("", isOn: $settings.metrics.metricsEnabled)
                            .toggleStyle(.switch)
                            .tint(DesignTokens.Colors.accentCyan)
                            .labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("서버 URL",
                                description: "cv.dododo.app 메트릭 서버 주소",
                                icon: "link", iconColor: DesignTokens.Colors.textSecondary) {
                        TextField("https://cv.dododo.app", text: $settings.metrics.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignTokens.Typography.custom(size: 12, design: .monospaced))
                            .frame(width: 200)
                    }
                }

                // ─── 연결 테스트 ──────────────────────────────
                SettingsSection(title: "연결 확인", icon: "network.badge.shield.half.filled", color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("연결 테스트",
                                description: "서버 연결 상태 및 응답 지연 시간을 확인합니다.",
                                icon: "bolt.fill", iconColor: DesignTokens.Colors.accentCyan) {
                        Button {
                            Task {
                                isTesting = true
                                testResult = nil
                                let result = await appState.testMetricsConnection()
                                if result.success {
                                    testResult = .success(latencyMs: result.latencyMs, message: result.message)
                                } else {
                                    testResult = .failure(message: result.message)
                                }
                                isTesting = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "bolt.horizontal.fill")
                                        .font(DesignTokens.Typography.caption)
                                }
                                Text(isTesting ? "테스트 중…" : "테스트")
                                    .font(DesignTokens.Typography.captionMedium)
                            }
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(DesignTokens.Colors.accentCyan.opacity(0.9))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTesting)
                    }
                    if let result = testResult {
                        RowDivider()
                        SettingsRow(result.text,
                                    icon: result.icon, iconColor: result.color) {
                            EmptyView()
                        }
                    }
                }

                // ─── 전송 주기 ────────────────────────────────
                SettingsSection(title: "전송 주기", icon: "timer", color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("메트릭 전송 주기",
                                description: "레이턴시·FPS·버퍼 상태를 서버로 전송하는 주기 (2~30초)",
                                icon: "clock.arrow.circlepath", iconColor: DesignTokens.Colors.accentCyan) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.metrics.forwardInterval, in: 2...30, step: 1)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentCyan)
                            Text(String(format: "%.0f초", settings.metrics.forwardInterval))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentCyan)
                                .frame(width: 34)
                        }
                    }
                    RowDivider()
                    SettingsRow("Keep-alive 핑 주기",
                                description: "서버에 시청 중임을 알리는 핑 전송 주기 (10~120초)",
                                icon: "antenna.radiowaves.left.and.right", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.metrics.pingInterval, in: 10...120, step: 5)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentCyan)
                            Text(String(format: "%.0f초", settings.metrics.pingInterval))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentCyan)
                                .frame(width: 34)
                        }
                    }
                }

                // ─── 전송 데이터 안내 ──────────────────────────
                SettingsSection(title: "전송 데이터 목록", icon: "list.bullet.clipboard", color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("레이턴시", description: "PDT 기반 스트림 지연 (ms)",
                                icon: "timer", iconColor: DesignTokens.Colors.accentCyan) { EmptyView() }
                    RowDivider()
                    SettingsRow("FPS", description: "VLC 초당 프레임 수",
                                icon: "film.stack", iconColor: DesignTokens.Colors.accentCyan) { EmptyView() }
                    RowDivider()
                    SettingsRow("드롭 프레임", description: "VLC 손실 프레임 수",
                                icon: "backward.frame", iconColor: DesignTokens.Colors.accentCyan) { EmptyView() }
                    RowDivider()
                    SettingsRow("버퍼 상태", description: "버퍼 충전률 (%)",
                                icon: "waveform.path", iconColor: DesignTokens.Colors.accentCyan) { EmptyView() }
                    RowDivider()
                    SettingsRow("플레이어", description: "엔진 식별자 (VLC)",
                                icon: "play.fill", iconColor: DesignTokens.Colors.accentCyan) { EmptyView() }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        // 설정 변경 시 MetricsForwarder / APIClient에 즉시 적용
        .onChange(of: settings.metrics) { _, _ in
            Task {
                await settings.save()
                await appState.applyMetricsSettings()
            }
        }
    }
}
