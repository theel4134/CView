// MARK: - MenuBarView.swift
// CViewApp - 프리미엄 메뉴바 팝업 뷰 (MenuBarExtra용)
// Design: 컴팩트 + 프리미엄 메뉴바 위젯

import SwiftUI
import CViewCore
import CViewMonitoring

/// 메뉴바에서 팔로잉 스트리머 온라인 상태를 보여주는 뷰
struct MenuBarView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Branded header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Gradients.primary)
                        .frame(width: 20, height: 20)
                    
                    Text("C")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .black))
                        .foregroundStyle(DesignTokens.Colors.onPrimary)
                }
                
                Text("CView")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer()

                if let lastUpdated = appState.backgroundUpdateService.lastUpdated {
                    Text(lastUpdated, style: .relative)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                if appState.backgroundUpdateService.isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.background)

            // Accent separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Online channels
            let onlineChannels = appState.backgroundUpdateService.onlineChannels

            if onlineChannels.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "tv.slash")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text(appState.isLoggedIn
                         ? "현재 방송 중인 라이브 채널이 없습니다"
                         : "로그인하면 라이브 채널을 확인할 수 있습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                // Online count badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 6, height: 6)
                    
                    Text("\(onlineChannels.count)개 채널 방송 중")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.xxs)
                
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(onlineChannels) { channel in
                            MenuBarChannelRow(channel: channel)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                }
                .frame(maxHeight: 400)
            }

            // Separator
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 1)
                .padding(.horizontal, DesignTokens.Spacing.sm)

            // 앱 시스템 사용률 (CPU/GPU/메모리)
            MenuBarSystemUsageSection(monitor: appState.performanceMonitor)

            // Separator
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 1)
                .padding(.horizontal, DesignTokens.Spacing.sm)

            // Footer actions
            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    if let apiClient = appState.apiClient {
                        Task {
                            await appState.backgroundUpdateService.refresh(apiClient: apiClient)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        Text("새로고침")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow || $0.isMainWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        Text("앱 열기")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .frame(width: 320)
        .background(DesignTokens.Colors.surfaceOverlay)
    }
}

// MARK: - Menu Bar Channel Row

struct MenuBarChannelRow: View {
    let channel: OnlineChannel
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    var body: some View {
        Button {
            openWindow(id: "player-window", value: channel.channelId)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // Live indicator with pulse animation
                Circle()
                    .fill(DesignTokens.Colors.live)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Text(channel.liveTitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Viewer count badge
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(DesignTokens.Typography.custom(size: 8))
                    Text(channel.formattedViewerCount)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.surfaceElevated)
                .clipShape(Capsule())
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .customCursor(.pointingHand)
    }
}

// MARK: - Menu Bar System Usage Section

/// 메뉴바에 표시되는 앱 프로세스 시스템 사용률 모니터
/// - CPU/GPU 사용률을 막대로 시각화 (코어 수 기반 정규화)
/// - 메모리/스레드/GPU 메모리를 칩으로 표시
/// - 메뉴가 열려 있을 때만 2초 간격으로 폴링 (onDisappear 시 자동 중단)
struct MenuBarSystemUsageSection: View {

    let monitor: PerformanceMonitor

    @State private var snapshot: PerformanceMonitor.SystemUsageSnapshot?
    @State private var pollTask: Task<Void, Never>?

    /// CPU 사용률 정규화 기준 (논리 코어 수 × 100%)
    /// Apple Silicon M1(8) ~ M3 Max(16) 자동 대응
    private let maxCPU: Double = Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 헤더
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)

                Text("앱 시스템 사용률")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Spacer()

                if snapshot != nil {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 5, height: 5)
                    Text("실시간")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            if let s = snapshot {
                // CPU / GPU 진행바
                usageBar(
                    label: "CPU",
                    display: String(format: "%.0f%%", s.cpuPercent),
                    ratio: min(max(s.cpuPercent / maxCPU, 0), 1)
                )
                usageBar(
                    label: "GPU",
                    display: String(format: "%.0f%%", s.gpuPercent),
                    ratio: min(max(s.gpuPercent / 100.0, 0), 1)
                )

                // Memory / Threads / GPU Memory 칩
                HStack(spacing: 6) {
                    metricChip(
                        icon: "memorychip",
                        label: formatMB(s.memoryMB),
                        color: memoryColor(s.memoryMB)
                    )
                    metricChip(
                        icon: "square.stack.3d.up",
                        label: "\(s.threadCount) TH",
                        color: DesignTokens.Colors.textTertiary
                    )
                    if s.gpuMemoryMB > 0 {
                        metricChip(
                            icon: "display",
                            label: formatMB(s.gpuMemoryMB),
                            color: DesignTokens.Colors.textTertiary
                        )
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("사용률 측정 중...")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        // 첫 샘플 즉시 표시
        snapshot = monitor.systemUsageSnapshot()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                snapshot = monitor.systemUsageSnapshot()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Subviews

    private func usageBar(label: String, display: String, ratio: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 22, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.Colors.surfaceElevated)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 6)

            Text(display)
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func metricChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 8))
            Text(label)
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func barColor(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.5: return DesignTokens.Colors.chzzkGreen
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    private func memoryColor(_ mb: Double) -> Color {
        switch mb {
        case ..<500: return DesignTokens.Colors.textTertiary
        case ..<1000: return .yellow
        default: return .red
        }
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }
}
