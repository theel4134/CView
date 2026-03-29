// MARK: - MultiLiveSettingsPanel.swift
// 멀티라이브 설정 사이드 패널 — 6개 탭 (오디오, 이퀄라이저, 영상, 재생, 네트워크, 도구)
// MLAddChannelPanel과 동일한 push 패턴 (380pt, glass, left border)

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence
import CViewMonitoring

// MARK: - Tab Enum

enum MLSettingsTab: String, CaseIterable {
    case audio = "오디오"
    case equalizer = "이퀄라이저"
    case video = "영상"
    case playback = "재생"
    case latency = "지연"
    case network = "네트워크"
    case tools = "도구"
    case metrics = "메트릭"

    var icon: String {
        switch self {
        case .audio:      return "speaker.wave.2"
        case .equalizer:  return "slider.vertical.3"
        case .video:      return "tv"
        case .playback:   return "play.circle"
        case .latency:    return "clock.arrow.2.circlepath"
        case .network:    return "antenna.radiowaves.left.and.right"
        case .tools:      return "wrench"
        case .metrics:    return "chart.bar.xaxis"
        }
    }
}

// MARK: - Main Panel

struct MLSettingsPanel: View {
    let manager: MultiLiveManager
    let settingsStore: SettingsStore
    @Binding var isPresented: Bool
    @State private var selectedTab: MLSettingsTab = .audio
    @State private var isCloseHovered = false

    private var activeSession: MultiLiveSession? {
        if !manager.isGridLayout {
            return manager.selectedSession
        } else {
            return manager.sessions.first { $0.id == (manager.audioSessionId ?? manager.selectedSessionId) }
        }
    }

    private var playerVM: PlayerViewModel? {
        activeSession?.playerViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 헤더 ──
            header
            // ── 탭 바 ──
            tabBar
            Divider()
            // ── 탭 콘텐츠 ──
            if activeSession != nil {
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .audio:      MLAudioTab(session: activeSession!, manager: manager)
                        case .equalizer:  MLEqualizerTab(playerVM: playerVM)
                        case .video:      MLVideoTab(playerVM: playerVM)
                        case .playback:   MLPlaybackTab(session: activeSession!, manager: manager)
                        case .latency:    LatencySettingsCompact(settings: settingsStore) {
                                              playerVM?.applyLatencySettings(settingsStore.player)
                                          }
                        case .network:    MLNetworkTab(session: activeSession!, settingsStore: settingsStore)
                        case .tools:      MLToolsTab(playerVM: playerVM)
                        case .metrics:    MetricsForwardingStatusView()
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            } else {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("활성 세션이 없습니다")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("채널을 추가한 뒤 설정을 조정하세요")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
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

            VStack(alignment: .leading, spacing: 2) {
                Text("멀티라이브 설정")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let session = activeSession {
                    Text(session.channelName)
                        .font(DesignTokens.Typography.caption)
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
                    .foregroundStyle(isCloseHovered ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary)
                    .scaleEffect(isCloseHovered ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .animation(DesignTokens.Animation.fast, value: isCloseHovered)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(MLSettingsTab.allCases, id: \.self) { tab in
                MLSettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(DesignTokens.Animation.fast) { selectedTab = tab }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }
}
