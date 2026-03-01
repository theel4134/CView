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
            VStack(alignment: .leading, spacing: 20) {

                // ─── 헤더 ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Label("메트릭 서버 전송", systemImage: "chart.line.uptrend.xyaxis")
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))

                    Text("VLC 플레이어 라이브 재생 데이터를 cv.dododo.app 메트릭 서버로 전송합니다.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                // ─── 기본 설정 ────────────────────────────────
                GroupBox {
                    VStack(spacing: 12) {
                        // 메트릭 전송 토글
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("메트릭 전송 활성화")
                                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text("라이브 시청 시 레이턴시·FPS·버퍼 데이터를 서버로 전송합니다.")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.metrics.metricsEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        Divider()
                            .background(.white.opacity(DesignTokens.Glass.borderOpacityLight))

                        // 서버 URL 입력
                        VStack(alignment: .leading, spacing: 6) {
                            Text("서버 URL")
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            TextField("https://cv.dododo.app", text: $settings.metrics.serverURL)
                                .textFieldStyle(.plain)
                                .font(DesignTokens.Typography.custom(size: 12, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .background(.white.opacity(DesignTokens.Glass.borderOpacityLight))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                    }
                    .padding(DesignTokens.Spacing.xxs)
                } label: {
                    Label("서버 설정", systemImage: "server.rack")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 연결 테스트 ──────────────────────────────
                GroupBox {
                    VStack(spacing: 10) {
                        // 테스트 버튼
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
                                    Image(systemName: "bolt.fill")
                                        .font(DesignTokens.Typography.caption)
                                }
                                Text(isTesting ? "테스트 중…" : "연결 테스트")
                                    .font(DesignTokens.Typography.captionMedium)
                            }
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(Color(red: 0.2, green: 0.8, blue: 0.9).opacity(0.9))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTesting)

                        // 테스트 결과
                        if let result = testResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.icon)
                                    .foregroundStyle(result.color)
                                    .font(DesignTokens.Typography.caption)
                                Text(result.text)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(result.color.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignTokens.Spacing.xxs)
                } label: {
                    Label("연결 확인", systemImage: "network.badge.shield.half.filled")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 전송 주기 ────────────────────────────────
                GroupBox {
                    VStack(spacing: 14) {
                        // 메트릭 전송 주기
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("메트릭 전송 주기")
                                    .font(DesignTokens.Typography.captionMedium)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.0f초", settings.metrics.forwardInterval))
                                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Slider(
                                value: $settings.metrics.forwardInterval,
                                in: 2...30,
                                step: 1
                            )
                            .tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            Text("레이턴시·FPS·버퍼 상태를 서버로 전송하는 주기 (2~30초)")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }

                        Divider()
                            .background(.white.opacity(DesignTokens.Glass.borderOpacityLight))

                        // 핑 주기
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Keep-alive 핑 주기")
                                    .font(DesignTokens.Typography.captionMedium)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.0f초", settings.metrics.pingInterval))
                                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Slider(
                                value: $settings.metrics.pingInterval,
                                in: 10...120,
                                step: 5
                            )
                            .tint(Color(red: 0.2, green: 0.8, blue: 0.9))
                            Text("서버에 시청 중임을 알리는 핑 전송 주기 (10~120초)")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .padding(DesignTokens.Spacing.xxs)
                } label: {
                    Label("전송 주기", systemImage: "timer")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                // ─── 전송 데이터 안내 ──────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        payloadRow(icon: "timer",            label: "레이턴시",  desc: "PDT 기반 스트림 지연 (ms)")
                        payloadRow(icon: "film.stack",       label: "FPS",       desc: "VLC 초당 프레임 수")
                        payloadRow(icon: "backward.frame",   label: "드롭 프레임", desc: "VLC 손실 프레임 수")
                        payloadRow(icon: "waveform.path",    label: "버퍼 상태",  desc: "버퍼 충전률 (%)")
                        payloadRow(icon: "play.fill",        label: "플레이어",   desc: "엔진 식별자 (VLC)")
                    }
                    .padding(DesignTokens.Spacing.xxs)
                } label: {
                    Label("전송 데이터 목록", systemImage: "list.bullet.clipboard")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .groupBoxStyle(MetricsGroupBoxStyle())

                Spacer(minLength: 20)
            }
            .padding(DesignTokens.Spacing.md)
        }
        // 설정 변경 시 MetricsForwarder / APIClient에 즉시 적용
        .onChange(of: settings.metrics) { _, _ in
            Task {
                await settings.save()
                await appState.applyMetricsSettings()
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func payloadRow(icon: String, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.9))
                .frame(width: 18)
            Text(label)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(width: 70, alignment: .leading)
            Text(desc)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}

// MARK: - MetricsGroupBoxStyle

private struct MetricsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }
}
