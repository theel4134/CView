// MARK: - MetricsSettingsTab.swift
// 메트릭 서버 전송 설정 탭 (SettingsView에서 추출)

import SwiftUI
import AppKit
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

    // MARK: App Secret 표시 상태
    @State private var revealAppSecret = false
    @State private var copiedAppSecret = false
    @State private var secretValidation: SecretValidation?
    @State private var isValidatingSecret = false

    private enum SecretValidation {
        case ok
        case fail(String)
        var color: Color {
            switch self { case .ok: .green; case .fail: .red }
        }
        var icon: String {
            switch self { case .ok: "checkmark.seal.fill"; case .fail: "xmark.seal.fill" }
        }
        var text: String {
            switch self {
            case .ok: "✓ 인증 성공 — 서버에서 발급한 키와 일치합니다"
            case .fail(let m): "인증 실패: \(m)"
            }
        }
    }

    /// `Info.plist`의 `METRICS_APP_SECRET` (빌드 주입값) 또는
    /// 프로세스 환경변수 `METRICS_APP_SECRET`. 둘 다 없거나 dev placeholder면 nil.
    private var bundleAppSecret: String? {
        if let env = ProcessInfo.processInfo.environment["METRICS_APP_SECRET"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty, env != "dev-app-secret-change-in-production" {
            return env
        }
        let v = Bundle.main.object(forInfoDictionaryKey: "METRICS_APP_SECRET") as? String
        guard let v, !v.isEmpty, v != "dev-app-secret-change-in-production" else { return nil }
        return v
    }
    /// 메트릭 인증에 실제로 사용될 secret. (사용자 입력 > ENV/Bundle > dev fallback)
    private var effectiveAppSecret: String {
        let user = settings.metrics.appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return user }
        return bundleAppSecret ?? "dev-app-secret-change-in-production"
    }
    /// 현재 적용되는 secret 출처 레이블
    private var effectiveSourceLabel: String {
        let user = settings.metrics.appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return "사용자 입력값 (저장됨)" }
        if let env = ProcessInfo.processInfo.environment["METRICS_APP_SECRET"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty, env != "dev-app-secret-change-in-production" {
            return "환경변수 METRICS_APP_SECRET"
        }
        if bundleAppSecret != nil { return "빌드 주입값 (Info.plist)" }
        return "⚠️ 개발용 기본값 — 인증 실패합니다"
    }
    private var maskedAppSecret: String {
        let s = effectiveAppSecret
        guard s.count > 4 else { return String(repeating: "•", count: max(s.count, 4)) }
        let head = s.prefix(2)
        let tail = s.suffix(2)
        return "\(head)\(String(repeating: "•", count: max(s.count - 4, 4)))\(tail)"
    }

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

                // ─── App Secret (인증 키) ─────────────────────
                SettingsSection(title: "App Secret (인증 키)",
                                icon: "key.fill",
                                color: DesignTokens.Colors.accentCyan) {
                    SettingsRow("서버 발급 키 입력",
                                description: "운영 서버에서 발급받은 App Secret을 붙여넣으세요. 비워두면 빌드 시 주입된 키 또는 개발용 기본값이 사용됩니다.",
                                icon: "key", iconColor: DesignTokens.Colors.accentCyan) {
                        HStack(spacing: 6) {
                            if revealAppSecret {
                                TextField("서버에서 발급받은 키",
                                          text: $settings.metrics.appSecret)
                                    .textFieldStyle(.roundedBorder)
                                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                    .frame(width: 220)
                            } else {
                                SecureField("서버에서 발급받은 키",
                                            text: $settings.metrics.appSecret)
                                    .textFieldStyle(.roundedBorder)
                                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                    .frame(width: 220)
                            }
                            Button {
                                revealAppSecret.toggle()
                            } label: {
                                Image(systemName: revealAppSecret ? "eye.slash" : "eye")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help(revealAppSecret ? "마스킹" : "표시")
                        }
                    }
                    RowDivider()
                    SettingsRow("현재 적용 중인 키",
                                description: effectiveSourceLabel,
                                icon: "checkmark.shield",
                                iconColor: bundleAppSecret == nil
                                    && settings.metrics.appSecret.isEmpty
                                    ? .orange
                                    : DesignTokens.Colors.accentCyan) {
                        HStack(spacing: 6) {
                            Text(revealAppSecret ? effectiveAppSecret : maskedAppSecret)
                                .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: 200, alignment: .trailing)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(effectiveAppSecret, forType: .string)
                                copiedAppSecret = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    copiedAppSecret = false
                                }
                            } label: {
                                Image(systemName: copiedAppSecret ? "checkmark" : "doc.on.doc")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(copiedAppSecret
                                        ? DesignTokens.Colors.accentCyan
                                        : DesignTokens.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help(copiedAppSecret ? "복사됨" : "클립보드에 복사")
                        }
                    }
                    RowDivider()
                    SettingsRow("키 검증",
                                description: "현재 키로 /api/auth/token 인증을 시도합니다.",
                                icon: "lock.shield",
                                iconColor: DesignTokens.Colors.accentCyan) {
                        Button {
                            Task {
                                isValidatingSecret = true
                                secretValidation = nil
                                // 입력 즉시 검증 → 저장 후 client에 전파
                                await settings.save()
                                await appState.applyMetricsSettings()
                                let result = await appState.testMetricsConnection()
                                secretValidation = result.success
                                    ? .ok
                                    : .fail(result.message)
                                isValidatingSecret = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isValidatingSecret {
                                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .font(DesignTokens.Typography.caption)
                                }
                                Text(isValidatingSecret ? "검증 중…" : "인증 검증")
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
                        .disabled(isValidatingSecret)
                    }
                    if let v = secretValidation {
                        RowDivider()
                        SettingsRow(v.text, icon: v.icon, iconColor: v.color) {
                            EmptyView()
                        }
                    }
                    RowDivider()
                    SettingsRow("Chrome 확장에 입력",
                                description: "위 키를 복사한 뒤 Chrome 확장 → 설정 → 인증 → App Secret 칸에 붙여넣으세요.",
                                icon: "puzzlepiece.extension",
                                iconColor: DesignTokens.Colors.textSecondary) {
                        EmptyView()
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
