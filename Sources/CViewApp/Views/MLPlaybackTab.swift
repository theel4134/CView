// MARK: - MLPlaybackTab.swift
// 멀티라이브 설정 — 재생 탭 (엔진 선택, 재생 속도)

import SwiftUI
import CViewCore
import CViewPlayer

struct MLPlaybackTab: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    @State private var playbackRate: Double = 1.0
    @State private var isSwitchingEngine = false

    private var playerVM: PlayerViewModel? { session.playerViewModel }
    private let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            engineSelectionSection
            Divider()
            ratePresetSection
            fineTuneSection
            if abs(playbackRate - 1.0) > 0.01 {
                Text("⚠ 라이브 방송에서 속도 변경 시 지연이 누적될 수 있습니다")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .onAppear {
            playbackRate = playerVM?.playbackRate ?? 1.0
        }
    }

    @ViewBuilder
    private var engineSelectionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("플레이어 엔진")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(PlayerEngineType.allCases, id: \.self) { engineType in
                    MLSettingsGridButton(
                        label: engineType.displayName,
                        isSelected: playerVM?.currentEngineType == engineType
                    ) {
                        guard playerVM?.currentEngineType != engineType, !isSwitchingEngine else { return }
                        isSwitchingEngine = true
                        Task {
                            await manager.switchEngine(session: session, to: engineType)
                            isSwitchingEngine = false
                        }
                    }
                }
            }
            .opacity(isSwitchingEngine ? 0.5 : 1.0)
            .overlay {
                if isSwitchingEngine {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }

    @ViewBuilder
    private var ratePresetSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("재생 속도")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(rates, id: \.self) { rate in
                    MLSettingsGridButton(
                        label: rate == 1.0 ? "1x" : String(format: "%.2gx", rate),
                        isSelected: abs(playbackRate - rate) < 0.01
                    ) {
                        playbackRate = rate
                        Task { await playerVM?.setPlaybackRate(rate) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fineTuneSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("미세 조정")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.2fx", playbackRate))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Slider(value: $playbackRate, in: 0.5...2.0, step: 0.05)
                .tint(DesignTokens.Colors.chzzkGreen)
                .onChange(of: playbackRate) { _, newValue in
                    Task { await playerVM?.setPlaybackRate(newValue) }
                }
        }
    }
}
