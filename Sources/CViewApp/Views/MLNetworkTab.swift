// MARK: - MLNetworkTab.swift
// 멀티라이브 설정 — 네트워크 탭 (모니터링, 프록시, 연결, CDN, 최적화)

import SwiftUI
import CViewCore
import CViewPersistence
import CViewMonitoring

struct MLNetworkTab: View {
    let session: MultiLiveSession
    @Bindable var settingsStore: SettingsStore

    private var metrics: VLCLiveMetrics? { session.latestMetrics }
    private var avMetrics: AVPlayerLiveMetrics? { session.latestAVMetrics }
    private var hlsjsMetrics: HLSJSLiveMetrics? { session.latestHLSJSMetrics }
    private var proxyStats: ProxyNetworkStats? { session.latestProxyStats }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            streamMonitoringSection
            Divider()
            proxyStatsSection
            Divider()
            connectionSettingsSection
            Divider()
            cdnProxySection
            Divider()
            backgroundOptSection
        }
        .onAppear { session.showNetworkMetrics = true }
        .onDisappear { session.showNetworkMetrics = false }
        .id(session.id)
    }

    // MARK: - Sections

    @ViewBuilder
    private var streamMonitoringSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("실시간 모니터링", icon: "waveform.path.ecg", color: DesignTokens.Colors.chzzkGreen)

            if let m = metrics {
                vlcMetricsContent(m)
            } else if let av = avMetrics {
                avPlayerMetricsContent(av)
            } else if let hls = hlsjsMetrics {
                hlsjsMetricsContent(hls)
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
    }

    @ViewBuilder
    private func vlcMetricsContent(_ m: VLCLiveMetrics) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(healthColor(m.healthScore))
                .frame(width: 10, height: 10)
            Text("스트림 건강도")
                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(String(format: "%.0f%%", m.healthScore * 100))
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(healthColor(m.healthScore))
        }

        ProgressView(value: m.healthScore)
            .tint(healthColor(m.healthScore))

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
            metricCard("대역폭", formatBandwidth(session.displayBandwidthBytesPerSec), icon: "arrow.down.circle",
                       sparkline: bandwidthSpark())
            // [정밀화] VLC inputBitrateKbps 가 0이면 프록시 대역폭을 kbps 로 환산해 관찰값 표시.
            metricCard("입력 비트레이트", inputBitrateText(m), icon: "speedometer")
            // [정밀화] VLC HW-decode 경로에서 fps=0 으로 고착 → 최근 유효 값 fallback.
            metricCard("FPS", fpsText(m.fps), icon: "film", sparkline: fpsSpark())
            // [정밀화] bufferHealth=0 stuck 시도 최근 유효 값 fallback.
            metricCard("버퍼 건강도", bufferText(m.bufferHealth), icon: "heart.fill",
                       alert: bufferAlert(m.bufferHealth),
                       sparkline: bufferSpark())
            metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
            metricCard("지연 프레임", "\(m.latePicturesDelta)", icon: "clock.badge.exclamationmark", alert: m.latePicturesDelta > 0)
        }

        HStack {
            if let res = m.resolution {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(res)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(format: "%.2fx", m.playbackRate))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
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
    }

    @ViewBuilder
    private func avPlayerMetricsContent(_ m: AVPlayerLiveMetrics) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(healthColor(m.healthScore))
                .frame(width: 10, height: 10)
            Text("스트림 건강도")
                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(String(format: "%.0f%%", m.healthScore * 100))
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(healthColor(m.healthScore))
        }

        ProgressView(value: m.healthScore)
            .tint(healthColor(m.healthScore))

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
            metricCard("대역폭", formatBytesPerSecD(session.displayBandwidthBytesPerSec), icon: "arrow.down.circle",
                       sparkline: bandwidthSpark())
            metricCard("비트레이트", String(format: "%.0f kbps", m.bitrateKbps), icon: "speedometer")
            metricCard("버퍼 건강도", String(format: "%.0f%%", m.bufferHealth * 100), icon: "heart.fill",
                       alert: m.bufferHealth < 0.3,
                       sparkline: bufferSpark())
            metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
            metricCard("지연 시간", String(format: "%.1f초", m.measuredLatency), icon: "timer")
        }

        HStack {
            if let res = m.resolution {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(res)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(format: "%.2fx", m.playbackRate))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                Text("AVPlayer")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
            }
        }
    }

    @ViewBuilder
    private func hlsjsMetricsContent(_ m: HLSJSLiveMetrics) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(healthColor(m.healthScore))
                .frame(width: 10, height: 10)
            Text("스트림 건강도")
                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(String(format: "%.0f%%", m.healthScore * 100))
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(healthColor(m.healthScore))
        }

        ProgressView(value: m.healthScore)
            .tint(healthColor(m.healthScore))

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
            metricCard("대역폭", formatBytesPerSecD(session.displayBandwidthBytesPerSec), icon: "arrow.down.circle",
                       sparkline: bandwidthSpark())
            metricCard("비트레이트", String(format: "%.0f kbps", m.bitrateKbps), icon: "speedometer")
            metricCard("버퍼 건강도", String(format: "%.0f%%", m.bufferHealth * 100), icon: "heart.fill",
                       alert: m.bufferHealth < 0.3,
                       sparkline: bufferSpark())
            metricCard("FPS", String(format: "%.1f", m.fps), icon: "film", sparkline: fpsSpark())
            metricCard("지연 시간", String(format: "%.1f초", m.latency), icon: "timer")
            metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
        }

        HStack {
            if let res = m.resolution {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(res)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(format: "%.2fx", m.playbackRate))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                Text("HLS.js")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
            }
        }
    }

    @ViewBuilder
    private var proxyStatsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("프록시 상태", icon: "server.rack", color: DesignTokens.Colors.accentBlue)

            if let p = proxyStats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                    metricCard("총 요청", "\(p.totalRequests)", icon: "arrow.up.arrow.down")
                    metricCard("캐시 적중률", String(format: "%.0f%%", p.cacheHitRatio * 100), icon: "memorychip")
                    metricCard("활성 연결", "\(p.activeConnections)", icon: "link")
                    metricCard("평균 응답", String(format: "%.0fms", p.avgResponseTime * 1000), icon: "timer")
                }

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                        Text("수신: \(formatBytes(p.totalBytesReceived))")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                        Text("전달: \(formatBytes(p.totalBytesServed))")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }

                if p.errorCount > 0 || p.consecutive403Count > 0 {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        if p.errorCount > 0 {
                            warningBadge("에러 \(p.errorCount) (비율 \(String(format: "%.1f%%", p.errorRate * 100)))")
                        }
                        if p.consecutive403Count > 0 {
                            warningBadge("연속 403: \(p.consecutive403Count)")
                        }
                    }
                }
            } else {
                Text("프록시 통계 없음")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var connectionSettingsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("연결 설정", icon: "network", color: DesignTokens.Colors.warning)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("자동 재연결")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Text("스트림 연결 끊김 시 자동 재시도")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settingsStore.network.autoReconnect)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack {
                Text("최대 재시도")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                Spacer()
                Stepper(
                    "\(settingsStore.network.maxReconnectAttempts)회",
                    value: $settingsStore.network.maxReconnectAttempts,
                    in: 1...30
                )
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("재연결 대기 시간")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.1f초", settingsStore.network.reconnectBaseDelay))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Slider(
                    value: $settingsStore.network.reconnectBaseDelay,
                    in: 0.5...10.0,
                    step: 0.5
                )
                .tint(DesignTokens.Colors.chzzkGreen)

                Text("첫 재시도 대기 간격 (이후 지수 백오프)")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
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
                    "\(settingsStore.network.streamConnectionTimeout)초",
                    value: $settingsStore.network.streamConnectionTimeout,
                    in: 5...30
                )
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var cdnProxySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("CDN 프록시", icon: "shield.checkered", color: DesignTokens.Colors.accentPurple)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("로컬 프록시 강제 사용")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Text("CDN Content-Type 수정 프록시 활성화")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settingsStore.network.forceStreamProxy)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack {
                Text("호스트당 최대 연결")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                Spacer()
                Stepper(
                    "\(settingsStore.network.maxConnectionsPerHost)",
                    value: $settingsStore.network.maxConnectionsPerHost,
                    in: 1...24
                )
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var backgroundOptSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeader("멀티라이브 최적화", icon: "bolt.circle", color: .cyan)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("백그라운드 품질 저하")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Text("비활성 세션의 화질을 자동 낮춤 (CPU/대역폭 절약)")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settingsStore.multiLive.backgroundQualityReduction)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
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
        metricCard(label, value, icon: icon, alert: alert, sparkline: AnyView?.none)
    }

    @ViewBuilder
    private func metricCard(_ label: String, _ value: String, icon: String, alert: Bool = false,
                            sparkline: AnyView?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(alert ? DesignTokens.Colors.warning : DesignTokens.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(alert ? DesignTokens.Colors.warning : DesignTokens.Colors.textPrimary)
                if let sparkline {
                    sparkline.frame(height: 12)
                }
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(alert ? DesignTokens.Colors.warning.opacity(0.06) : DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    // MARK: - Sparkline helpers

    private var historySamples: [NetworkMonitorHistory.Sample] { session.networkHistory.samples }

    private func bandwidthSpark() -> AnyView? {
        let values = historySamples.map(\.bandwidthBytesPerSec)
        guard values.count >= 2 else { return nil }
        return AnyView(NetworkSparkline(values: values, tint: DesignTokens.Colors.chzzkGreen))
    }

    private func fpsSpark() -> AnyView? {
        let values = historySamples.map(\.fps)
        guard values.count >= 2, (values.max() ?? 0) > 0 else { return nil }
        return AnyView(NetworkSparkline(values: values, tint: DesignTokens.Colors.accentBlue, displayMax: 60))
    }

    private func bufferSpark() -> AnyView? {
        let values = historySamples.map(\.bufferHealth)
        guard values.count >= 2 else { return nil }
        return AnyView(NetworkSparkline(values: values, tint: .orange, displayMax: 1.0))
    }

    @ViewBuilder
    private func warningBadge(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(text)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
        }
        .foregroundStyle(DesignTokens.Colors.warning)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(DesignTokens.Colors.warning.opacity(0.1)))
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

    private func formatBytesPerSecD(_ bytes: Double) -> String {
        let mbps = bytes * 8.0 / 1_000_000.0
        if mbps >= 1.0 { return String(format: "%.1f Mbps", mbps) }
        let kbps = bytes * 8.0 / 1_000.0
        return String(format: "%.0f kbps", kbps)
    }

    // MARK: - [정밀화] 표시 Helper — 0/미측정/fallback 구분

    /// 대역폭 표시 — 0 이면 "측정 중…", 그 외는 Mbps/kbps 자동 스케일.
    private func formatBandwidth(_ bytes: Double) -> String {
        guard bytes > 0 else { return "—" }
        return formatBytesPerSecD(bytes)
    }

    /// FPS — 0 이면 최근 유효 값 fallback (괄호 표기), 아예 관측 없으면 "—".
    private func fpsText(_ fps: Double) -> String {
        if fps > 0 { return String(format: "%.1f", fps) }
        if session.lastNonZeroFps > 0 {
            return String(format: "~%.1f", session.lastNonZeroFps)
        }
        return "—"
    }

    /// 버퍼 건강도 — 0 이면 최근 유효 값, 없으면 "—".
    private func bufferText(_ buffer: Double) -> String {
        if buffer > 0 { return String(format: "%.0f%%", buffer * 100) }
        if session.lastNonZeroBufferHealth > 0 {
            return String(format: "~%.0f%%", session.lastNonZeroBufferHealth * 100)
        }
        return "—"
    }

    private func bufferAlert(_ buffer: Double) -> Bool {
        let value = buffer > 0 ? buffer : session.lastNonZeroBufferHealth
        return value > 0 && value < 0.3
    }

    /// 입력 비트레이트 — VLC 수치가 0이면 프록시 관찰 대역폭을 kbps 로 환산해 표시.
    private func inputBitrateText(_ m: VLCLiveMetrics) -> String {
        if m.inputBitrateKbps > 0 { return String(format: "%.0f kbps", m.inputBitrateKbps) }
        if m.demuxBitrateKbps > 0 { return String(format: "%.0f kbps", m.demuxBitrateKbps) }
        let bw = session.proxyBandwidthBytesPerSec
        if bw > 0 { return String(format: "~%.0f kbps", bw * 8.0 / 1_000.0) }
        return "—"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
