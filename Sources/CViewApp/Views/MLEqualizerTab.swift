// MARK: - MLEqualizerTab.swift
// 멀티라이브 설정 — 이퀄라이저 탭 (프리셋, 프리앰프, 밴드)

import SwiftUI
import CViewCore

struct MLEqualizerTab: View {
    let playerVM: PlayerViewModel?
    @State private var presets: [String] = []
    @State private var frequencies: [Float] = []
    @State private var selectedPreset: String = ""
    @State private var isEnabled = false
    @State private var preAmp: Float = 0
    @State private var bands: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("이퀄라이저")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newVal in
                        isEnabled = newVal
                        if !newVal {
                            playerVM?.disableEqualizer()
                            bands = []
                            preAmp = 0
                            selectedPreset = ""
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if isEnabled {
                Picker("프리셋", selection: $selectedPreset) {
                    Text("선택...").tag("")
                    ForEach(presets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPreset) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    playerVM?.applyEqualizerPreset(newValue)
                    preAmp = playerVM?.equalizerPreAmp ?? 0
                    bands = playerVM?.equalizerBands ?? []
                }

                // 프리앰프
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("프리앰프")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f dB", preAmp))
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    Slider(value: $preAmp, in: -20...20, step: 0.5)
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .onChange(of: preAmp) { _, newValue in
                            playerVM?.setEqualizerPreAmp(newValue)
                        }
                }

                // 밴드 슬라이더
                if !bands.isEmpty {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        Text("주파수 밴드")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 4) {
                            ForEach(Array(bands.enumerated()), id: \.offset) { index, _ in
                                VStack(spacing: 4) {
                                    Text(String(format: "%.0f", bands[index]))
                                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                                    VerticalSlider(
                                        value: Binding(
                                            get: { bands.indices.contains(index) ? bands[index] : 0 },
                                            set: { newVal in
                                                if bands.indices.contains(index) {
                                                    bands[index] = newVal
                                                    playerVM?.setEqualizerBand(index: index, value: newVal)
                                                }
                                            }
                                        ),
                                        range: -20...20
                                    )
                                    .frame(height: 80)

                                    Text(formatFreq(index))
                                        .font(DesignTokens.Typography.custom(size: 8, weight: .regular))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadState() }
    }

    private func loadState() {
        presets = playerVM?.getEqualizerPresets() ?? []
        frequencies = playerVM?.getEqualizerFrequencies() ?? []
        isEnabled = playerVM?.isEqualizerEnabled ?? false
        selectedPreset = playerVM?.equalizerPresetName ?? ""
        preAmp = playerVM?.equalizerPreAmp ?? 0
        bands = playerVM?.equalizerBands ?? []
    }

    private func formatFreq(_ index: Int) -> String {
        guard index < frequencies.count else { return "" }
        let f = frequencies[index]
        if f >= 1000 { return String(format: "%.0fK", f / 1000) }
        return String(format: "%.0f", f)
    }
}
