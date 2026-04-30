// MARK: - PlayerAdvancedSettingsView.swift
// CViewApp - VLC 4.0 고급 플레이어 설정 Popover
// 이퀄라이저, 비디오 필터, 화면 비율, 자막, 오디오 설정
// 탭 뷰: PlayerAdvancedSettings+Equalizer.swift, +MediaTabs.swift, +ToolsNetwork.swift

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence
import CViewMonitoring

// MARK: - Advanced Settings Tab

enum AdvancedSettingsTab: String, CaseIterable {
    case equalizer = "이퀄라이저"
    case videoFilter = "비디오"
    case aspectRatio = "화면"
    case subtitle = "자막"
    case audio = "오디오"
    case playback = "재생"
    case latency = "지연"
    case tools = "도구"
    case network = "네트워크"
    case metrics = "메트릭"

    var icon: String {
        switch self {
        case .equalizer:   return "waveform"
        case .videoFilter: return "camera.filters"
        case .aspectRatio: return "aspectratio"
        case .subtitle:    return "captions.bubble"
        case .audio:       return "speaker.wave.3"
        case .playback:    return "gauge.with.dots.needle.33percent"
        case .latency:     return "clock.arrow.2.circlepath"
        case .tools:       return "wrench.and.screwdriver"
        case .network:     return "network"
        case .metrics:     return "chart.bar.xaxis"
        }
    }
}

// MARK: - Main Container

struct PlayerAdvancedSettingsView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil
    @Binding var isPresented: Bool
    @State private var selectedTab: AdvancedSettingsTab = .equalizer

    var body: some View {
        VStack(spacing: 0) {
            // ── 헤더 ──
            header
            // ── 탭 바 ──
            HStack(spacing: 2) {
                ForEach(AdvancedSettingsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.top, DesignTokens.Spacing.xs)

            Divider()
                .padding(.top, DesignTokens.Spacing.xs)

            // ── 탭 콘텐츠 ──
            ScrollView {
                Group {
                    switch selectedTab {
                    case .equalizer:
                        EqualizerTabView(playerVM: playerVM, settingsStore: settingsStore)
                    case .videoFilter:
                        VideoFilterTabView(playerVM: playerVM, settingsStore: settingsStore)
                    case .aspectRatio:
                        AspectRatioTabView(playerVM: playerVM, settingsStore: settingsStore)
                    case .subtitle:
                        SubtitleTabView(playerVM: playerVM)
                    case .audio:
                        AudioTabView(playerVM: playerVM, settingsStore: settingsStore)
                    case .playback:
                        PlaybackTabView(playerVM: playerVM)
                    case .latency:
                        if let settingsStore {
                            LatencySettingsCompact(settings: settingsStore) {
                                playerVM?.applyLatencySettings(settingsStore.player)
                            }
                        }
                    case .tools:
                        ToolsTabView(playerVM: playerVM)
                    case .network:
                        SinglePlayerNetworkTabView(playerVM: playerVM, settingsStore: settingsStore)
                    case .metrics:
                        MetricsForwardingStatusView()
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
        .frame(width: 380)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.92))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.Glass.borderColor)
                .frame(width: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            VStack(alignment: .leading, spacing: 1) {
                Text("플레이어 설정")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let name = playerVM?.channelName, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                withAnimation(DesignTokens.Animation.snappy) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func tabButton(_ tab: AdvancedSettingsTab) -> some View {
        Button {
            withAnimation(DesignTokens.Animation.fast) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                Text(tab.rawValue)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.chzzkGreen : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(selectedTab == tab ? DesignTokens.Colors.chzzkGreen.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

