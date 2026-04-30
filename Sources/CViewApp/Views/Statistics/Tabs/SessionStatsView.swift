// MARK: - Statistics/Tabs/SessionStatsView.swift
// 세션 탭 — 앱 런치/로그인/플레이어 상태 요약.
// 보강: 사용자 프로필 칩 + 재생 시간 sparkline (5초 간격 in-memory 샘플)

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI

struct SessionStatsView: View {
    @Environment(AppState.self) private var appState
    @State private var uptimeSamples: [Double] = []  // 직전 60포인트 (≈5분)
    @State private var sampleTask: Task<Void, Never>? = nil

    /// 단일/멀티라이브 어느 쪽이든 현재 재생 중인 PVM
    private var activePVM: PlayerViewModel? { appState.activePlayerViewModel }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 사용자 프로필 칩 (로그인 시에만)
                if appState.isLoggedIn {
                    userProfileChip
                }

                // ── 세션 개요
                StatSection("세션 개요", icon: "clock.fill", color: DesignTokens.Colors.accentBlue) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(title: "앱 시작 시간", value: formattedLaunchTime, icon: "clock.fill", color: DesignTokens.Colors.accentBlue)
                        StatCard(title: "현재 상태", value: streamPhaseText, icon: "play.circle.fill", color: streamPhaseColor)
                        StatCard(title: "로그인", value: appState.isLoggedIn ? "로그인됨" : "비로그인", icon: "person.fill", color: DesignTokens.Colors.accentPurple)
                    }
                }

                // ── 플레이어 상태 (재생시간 KPI는 sparkline 포함)
                StatSection("플레이어 상태", icon: "play.rectangle.fill", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "채널",
                            value: channelDisplay,
                            icon: "tv",
                            color: DesignTokens.Colors.accentOrange
                        )
                        StatCard(
                            title: "화질",
                            value: activePVM?.currentQuality?.name ?? "-",
                            icon: "sparkles",
                            color: DesignTokens.Colors.accentCyan
                        )
                        StatCard(
                            title: "볼륨",
                            value: "\(Int((activePVM?.volume ?? 0) * 100))%",
                            icon: "speaker.wave.2.fill",
                            color: DesignTokens.Colors.accentBlue
                        )
                        KPICard(
                            title: "재생 시간",
                            value: activePVM?.formattedUptime ?? "00:00",
                            subValue: uptimeSubValue,
                            icon: "timer",
                            color: DesignTokens.Colors.chzzkGreen,
                            sparkline: uptimeSamples.count >= 2 ? uptimeSamples : nil
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .contentBackground()
        .onAppear { startSampling() }
        .onDisappear { sampleTask?.cancel(); sampleTask = nil }
    }

    // MARK: - User Profile Chip

    @ViewBuilder
    private var userProfileChip: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if let url = appState.userProfileURL {
                CachedAsyncImage(url: url) {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(DesignTokens.Colors.accentPurple.opacity(0.15))
                    Image(systemName: "person.fill")
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                }
                .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.userNickname ?? "사용자")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let cid = appState.userChannelId {
                    Text(cid)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("로그인됨")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, 4)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.12), in: Capsule())
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - Sampling

    private func startSampling() {
        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled {
                // 재생 중일 때만 누적 (대기 시 0 으로 리셋되지 않도록 직전 값 유지)
                if let phase = activePVM?.streamPhase, phase == .playing {
                    let secs = activePVM?.uptime ?? 0
                    uptimeSamples.append(secs)
                    if uptimeSamples.count > 60 { uptimeSamples.removeFirst(uptimeSamples.count - 60) }
                }
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    // MARK: - Computed

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var formattedLaunchTime: String {
        Self.timeFormatter.string(from: appState.launchTime)
    }

    private var channelDisplay: String {
        let name = activePVM?.channelName ?? ""
        return name.isEmpty ? "-" : name
    }

    private var streamPhaseText: String {
        switch activePVM?.streamPhase {
        case .playing: return "재생 중"
        case .buffering: return "버퍼링"
        case .paused: return "일시정지"
        case .loadingInfo, .loadingManifest: return "로딩"
        case .error(_): return "오류"
        case .idle, .none: return "대기"
        case .some: return "-"
        }
    }

    private var streamPhaseColor: Color {
        switch activePVM?.streamPhase {
        case .playing: return DesignTokens.Colors.chzzkGreen
        case .buffering, .loadingInfo, .loadingManifest: return .orange
        case .error(_): return .red
        default: return DesignTokens.Colors.textTertiary
        }
    }

    private var uptimeSubValue: String? {
        guard uptimeSamples.count >= 2,
              let first = uptimeSamples.first, let last = uptimeSamples.last else { return nil }
        let delta = last - first
        guard delta > 0 else { return nil }
        return String(format: "↑ %.0fs", delta)
    }
}
