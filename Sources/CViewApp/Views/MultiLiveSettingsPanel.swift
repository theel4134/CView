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
            Divider()
                .overlay(DesignTokens.Glass.dividerColor)
            // ── 본문: 좌측 세로 내비 + 우측 콘텐츠 카드 ──
            HStack(spacing: 0) {
                sideNav
                Divider()
                    .overlay(DesignTokens.Glass.dividerColor)
                contentArea
            }
        }
        .frame(width: 380)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.92))
        .overlay(alignment: .leading) {
            // [Depth] 좌측 inner shadow — 메인 영역 뒤에서 나오는 깊이감
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 8)
        }
    }

    // MARK: - Side Navigation (vertical)

    /// 좌측 세로 내비게이션 — 아이콘 + 라벨을 세로 스택으로 배치하고
    /// 활성 탭은 Chzzk 네온 그린 좌측 인디케이터 바 + 엷은 틴트로 강조.
    /// 가로 탭 바(기존)는 탭 8개 기준 각 40pt로 축소되어 히트 영역/가독성이 악화되었음.
    private var sideNav: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(MLSettingsTab.allCases, id: \.self) { tab in
                    MLSettingsSideNavButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(DesignTokens.Animation.fast) { selectedTab = tab }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
            .padding(.horizontal, DesignTokens.Spacing.xxs)
        }
        .frame(width: 96)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.55))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let activeSession {
            ScrollView {
                Group {
                    switch selectedTab {
                    case .audio:      MLAudioTab(session: activeSession, manager: manager)
                    case .equalizer:  MLEqualizerTab(playerVM: playerVM)
                    case .video:      MLVideoTab(playerVM: playerVM)
                    case .playback:   MLPlaybackTab(session: activeSession, manager: manager)
                    case .latency:    LatencySettingsCompact(settings: settingsStore) {
                                          playerVM?.applyLatencySettings(settingsStore.player)
                                      }
                    case .network:    MLNetworkTab(session: activeSession, settingsStore: settingsStore)
                    case .tools:      MLToolsTab(playerVM: playerVM)
                    case .metrics:    MetricsForwardingStatusView()
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
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
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
