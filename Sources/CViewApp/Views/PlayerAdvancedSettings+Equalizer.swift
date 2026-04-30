// MARK: - PlayerAdvancedSettings+Equalizer.swift
// CViewApp - 이퀄라이저 탭 (EQ 밴드, 프리셋, 프리앰프)

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Equalizer Tab

struct EqualizerTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil
    @State private var presets: [String] = []
    @State private var frequencies: [Float] = []
    @State private var selectedPreset: String = ""
    @State private var isEnabled = false
    @State private var preAmp: Float = 0
    @State private var bands: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 활성화 토글
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
                            settingsStore?.player.equalizerPreset = nil
                            settingsStore?.player.equalizerPreAmp = 0
                            settingsStore?.player.equalizerBands = []
                            persistSettings()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if isEnabled {
                // 프리셋 선택
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
                    settingsStore?.player.equalizerPreset = newValue
                    settingsStore?.player.equalizerPreAmp = preAmp
                    settingsStore?.player.equalizerBands = bands
                    persistSettings()
                }

                // 프리앰프
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("프리앰프")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f dB", preAmp))
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $preAmp, in: -20...20, step: 0.5)
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .onChange(of: preAmp) { _, newValue in
                            playerVM?.setEqualizerPreAmp(newValue)
                            settingsStore?.player.equalizerPreAmp = newValue
                            persistSettings()
                        }
                }

                // 밴드 슬라이더
                if !bands.isEmpty {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        Text("주파수 밴드")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 4) {
                            ForEach(Array(bands.enumerated()), id: \.offset) { index, value in
                                VStack(spacing: 4) {
                                    Text(String(format: "%.0f", value))
                                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    VerticalSlider(
                                        value: Binding(
                                            get: { bands.indices.contains(index) ? bands[index] : 0 },
                                            set: { newVal in
                                                if bands.indices.contains(index) {
                                                    bands[index] = newVal
                                                    playerVM?.setEqualizerBand(index: index, value: newVal)
                                                    settingsStore?.player.equalizerBands = bands
                                                    persistSettings()
                                                }
                                            }
                                        ),
                                        range: -20...20
                                    )
                                    .frame(height: 80)

                                    Text(formatFreq(index))
                                        .font(DesignTokens.Typography.custom(size: 8, weight: .regular))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            presets = playerVM?.getEqualizerPresets() ?? []
            frequencies = playerVM?.getEqualizerFrequencies() ?? []
            isEnabled = playerVM?.isEqualizerEnabled ?? false
            selectedPreset = playerVM?.equalizerPresetName ?? ""
            preAmp = playerVM?.equalizerPreAmp ?? 0
            bands = playerVM?.equalizerBands ?? []
        }
    }

    private func formatFreq(_ index: Int) -> String {
        guard index < frequencies.count else { return "" }
        let f = frequencies[index]
        if f >= 1000 {
            return String(format: "%.0fK", f / 1000)
        }
        return String(format: "%.0f", f)
    }

    private func persistSettings() {
        guard let store = settingsStore else { return }
        Task { await store.save() }
    }
}

// MARK: - Vertical Slider (for EQ bands)

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let yPos = height * (1 - normalized)
            // 0dB 기준선 위치 계산
            let zeroNorm = CGFloat((0 - range.lowerBound) / (range.upperBound - range.lowerBound))
            let zeroY = height * (1 - zeroNorm)

            ZStack {
                // 트랙
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)

                // 0dB 기준선
                Rectangle()
                    .fill(DesignTokens.Colors.textTertiary.opacity(0.4))
                    .frame(width: 14, height: 1)
                    .offset(y: zeroY - height / 2)

                // 활성 영역 — 0dB 기준에서 현재 값까지 채움
                let barTop = min(yPos, zeroY)
                let barBottom = max(yPos, zeroY)
                let barHeight = barBottom - barTop
                RoundedRectangle(cornerRadius: 2)
                    .fill(value >= 0 ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.chzzkGreen.opacity(0.6))
                    .frame(width: 4, height: max(0, barHeight))
                    .offset(y: barTop + barHeight / 2 - height / 2)

                // 핸들
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: 10, height: 10)
                    .shadow(radius: 2)
                    .offset(y: yPos - height / 2)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let ratio = Float(1 - drag.location.y / height)
                        let clamped = max(0, min(1, ratio))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}
