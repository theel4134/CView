// MARK: - PlayerAdvancedSettings+ToolsNetwork.swift
// CViewApp - 도구 탭 (스크린샷, 녹화, 화질) + 네트워크 탭

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence
import CViewMonitoring

// MARK: - Tools Tab (스크린샷, 녹화, 화질)

struct ToolsTabView: View {
    let playerVM: PlayerViewModel?
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 스크린샷
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("스크린샷")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                Button {
                    playerVM?.takeScreenshot()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "camera.fill")
                            .font(DesignTokens.Typography.caption)
                        Text("현재 화면 캡처")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 녹화
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("녹화")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(playerVM?.formattedRecordingDuration ?? "")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    Task {
                        if isRecording {
                            await playerVM?.stopRecording()
                            isRecording = false
                        } else {
                            await playerVM?.startRecordingWithSavePanel()
                            isRecording = playerVM?.isRecording ?? false
                        }
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isRecording ? .red : DesignTokens.Colors.textPrimary)
                        Text(isRecording ? "녹화 중지" : "녹화 시작")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isRecording ? Color.red.opacity(0.12) : DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(isRecording ? Color.red.opacity(0.3) : DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 화질 선택
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("화질")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                let qualities = playerVM?.availableQualities ?? []
                if qualities.isEmpty {
                    Text("사용 가능한 화질 정보가 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    ForEach(qualities) { q in
                        Button {
                            Task { await playerVM?.switchQuality(q) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(q.name)
                                        .font(DesignTokens.Typography.captionMedium)
                                    Text(q.resolution)
                                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                Spacer()
                                if playerVM?.currentQuality?.id == q.id {
                                    Image(systemName: "checkmark")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                }
                            }
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(playerVM?.currentQuality?.id == q.id
                                          ? DesignTokens.Colors.chzzkGreen.opacity(0.1)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            isRecording = playerVM?.isRecording ?? false
        }
    }
}

// MARK: - Network Tab (싱글 플레이어)

struct SinglePlayerNetworkTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil

    private var metrics: VLCLiveMetrics? { playerVM?.latestMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {

            // ── 실시간 스트림 모니터링 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("실시간 모니터링", icon: "waveform.path.ecg", color: DesignTokens.Colors.chzzkGreen)

                if let m = metrics {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(healthColor(m.healthScore))
                            .frame(width: 10, height: 10)
                        Text("스트림 건강도")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", m.healthScore * 100))
                            .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(healthColor(m.healthScore))
                    }

                    ProgressView(value: m.healthScore)
                        .tint(healthColor(m.healthScore))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                        metricCard("대역폭", formatBytesPerSec(m.networkBytesPerSec), icon: "arrow.down.circle")
                        metricCard("입력 비트레이트", String(format: "%.0f kbps", m.inputBitrateKbps), icon: "speedometer")
                        metricCard("FPS", String(format: "%.1f", m.fps), icon: "film")
                        metricCard("버퍼 건강도", String(format: "%.0f%%", m.bufferHealth * 100), icon: "heart.fill")
                        metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
                        metricCard("지연 프레임", "\(m.latePicturesDelta)", icon: "clock.badge.exclamationmark", alert: m.latePicturesDelta > 0)
                    }

                    HStack {
                        if let res = m.resolution {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(res)
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2fx", m.playbackRate))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if m.lostAudioBuffersDelta > 0 || m.demuxCorruptedDelta > 0 || m.demuxDiscontinuityDelta > 0 {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            if m.lostAudioBuffersDelta > 0 {
                                warningBadge("오디오 손실 \(m.lostAudioBuffersDelta)")
                            }
                            if m.demuxCorruptedDelta > 0 {
                                warningBadge("손상 패킷 \(m.demuxCorruptedDelta)")
                            }
                            if m.demuxDiscontinuityDelta > 0 {
                                warningBadge("불연속 \(m.demuxDiscontinuityDelta)")
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.xaxis.ascending")
                                .font(.title3)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("스트림 재생 시 메트릭이 표시됩니다")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, DesignTokens.Spacing.md)
                }
            }

            // ── 정밀 동기화 (PDT) — VLC + WebLatencyClient 연결 시에만 ──
            if let vm = playerVM, vm.webSyncPhaseLabel != "-" {
                Divider()
                webSyncSection(vm)
            }

            if let store = settingsStore {
                Divider()

                // ── 연결 설정 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("연결 설정", icon: "network", color: .orange)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("자동 재연결")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("스트림 연결 끊김 시 자동 재시도")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.network.autoReconnect },
                            set: { store.network.autoReconnect = $0; Task { await store.save() } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HStack {
                        Text("최대 재시도")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Spacer()
                        Stepper(
                            "\(store.network.maxReconnectAttempts)회",
                            value: Binding(
                                get: { store.network.maxReconnectAttempts },
                                set: { store.network.maxReconnectAttempts = $0; Task { await store.save() } }
                            ),
                            in: 1...30
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("재연결 대기 시간")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f초", store.network.reconnectBaseDelay))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { store.network.reconnectBaseDelay },
                                set: { store.network.reconnectBaseDelay = $0; Task { await store.save() } }
                            ),
                            in: 0.5...10.0,
                            step: 0.5
                        )
                        .tint(DesignTokens.Colors.chzzkGreen)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("스트림 타임아웃")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("스트림 초기 연결 대기 최대 시간")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Stepper(
                            "\(store.network.streamConnectionTimeout)초",
                            value: Binding(
                                get: { store.network.streamConnectionTimeout },
                                set: { store.network.streamConnectionTimeout = $0; Task { await store.save() } }
                            ),
                            in: 5...30
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }
                }

                Divider()

                // ── CDN 프록시 설정 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("CDN 프록시", icon: "shield.checkered", color: .purple)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("로컬 프록시 강제 사용")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("CDN Content-Type 수정 프록시 활성화")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.network.forceStreamProxy },
                            set: { store.network.forceStreamProxy = $0; Task { await store.save() } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HStack {
                        Text("호스트당 최대 연결")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Spacer()
                        Stepper(
                            "\(store.network.maxConnectionsPerHost)",
                            value: Binding(
                                get: { store.network.maxConnectionsPerHost },
                                set: { store.network.maxConnectionsPerHost = $0; Task { await store.save() } }
                            ),
                            in: 1...24
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .onAppear { playerVM?.enableSelfMetrics(true) }
        .onDisappear { playerVM?.enableSelfMetrics(false) }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
        }
    }

    @ViewBuilder
    private func metricCard(_ label: String, _ value: String, icon: String, alert: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(alert ? .orange : DesignTokens.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(alert ? .orange : DesignTokens.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(alert ? Color.orange.opacity(0.06) : DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    @ViewBuilder
    private func warningBadge(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(text)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.1)))
    }

    private func healthColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .orange }
        return .red
    }

    private func formatBytesPerSec(_ bytes: Int) -> String {
        let mbps = Double(bytes) * 8.0 / 1_000_000.0
        if mbps >= 1.0 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(bytes) * 8.0 / 1_000.0
        return String(format: "%.0f kbps", kbps)
    }

    // MARK: - Web Sync (PDT) Section

    @ViewBuilder
    private func webSyncSection(_ vm: PlayerViewModel) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("정밀 동기화 (PDT)", icon: "waveform.badge.magnifyingglass",
                          color: webSyncPhaseColor(vm.webSyncPhaseLabel))

            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(webSyncPhaseColor(vm.webSyncPhaseLabel))
                    .frame(width: 10, height: 10)
                Text(vm.webSyncPhaseLabel)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(webSyncPhaseColor(vm.webSyncPhaseLabel))
                Spacer()
                if vm.webSyncIsPrecisionEligible {
                    Text("PDT")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Text("PDT 없음")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                metricCard(
                    "Drift (web↔app)",
                    formatDriftMs(vm.webSyncDriftMs),
                    icon: "arrow.left.and.right",
                    alert: (vm.webSyncDriftMs.map { abs($0) > 1500 }) ?? false
                )
                metricCard(
                    "Sample age",
                    formatAgeMs(vm.webSyncSampleAgeMs),
                    icon: "clock.arrow.circlepath",
                    alert: (vm.webSyncSampleAgeMs.map { $0 > 5_000 }) ?? false
                )
                metricCard(
                    "Web latency",
                    formatLatencyMs(vm.webSyncWebLatencyMs),
                    icon: "globe"
                )
                metricCard(
                    "App latency",
                    formatLatencyMs(vm.webSyncAppLatencyMs),
                    icon: "play.rectangle"
                )
            }
        }
    }

    private func webSyncPhaseColor(_ label: String) -> Color {
        if label.hasPrefix("hold") { return .orange }
        if label.hasPrefix("snap") || label.hasPrefix("reacquire") { return .red }
        if label == "tracking" { return .green }
        if label == "acquiring" { return .yellow }
        return DesignTokens.Colors.textTertiary
    }

    private func formatDriftMs(_ ms: Double?) -> String {
        guard let ms else { return "-" }
        let sign = ms >= 0 ? "+" : "-"
        return String(format: "%@%.0f ms", sign, abs(ms))
    }

    private func formatLatencyMs(_ ms: Double?) -> String {
        guard let ms else { return "-" }
        if ms >= 1_000 { return String(format: "%.2f s", ms / 1_000) }
        return String(format: "%.0f ms", ms)
    }

    private func formatAgeMs(_ ms: Int64?) -> String {
        guard let ms else { return "-" }
        if ms >= 1_000 { return String(format: "%.1f s", Double(ms) / 1_000.0) }
        return "\(ms) ms"
    }
}
