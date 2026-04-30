// MARK: - MLVideoTab.swift
// 멀티라이브 설정 — 영상 탭 (화면 비율, 비디오 필터)

import SwiftUI
import CViewCore

struct MLVideoTab: View {
    let playerVM: PlayerViewModel?
    @State private var isFilterEnabled = false
    @State private var brightness: Float = 1.0
    @State private var contrast: Float = 1.0
    @State private var saturation: Float = 1.0
    @State private var hue: Float = 0
    @State private var gamma: Float = 1.0
    @State private var selectedRatio: String? = nil

    private let ratios: [(String?, String)] = [
        (nil, "기본"),
        ("16:9", "16:9"),
        ("4:3", "4:3"),
        ("21:9", "21:9"),
        ("1:1", "1:1"),
        ("16:10", "16:10"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            aspectRatioSection
            Divider()
            videoFiltersSection
        }
        .onAppear {
            let ratio = playerVM?.aspectRatio
            selectedRatio = (ratio == nil || ratio?.isEmpty == true) ? nil : ratio
            isFilterEnabled = playerVM?.isVideoAdjustEnabled ?? false
            brightness = playerVM?.videoBrightness ?? 1.0
            contrast = playerVM?.videoContrast ?? 1.0
            saturation = playerVM?.videoSaturation ?? 1.0
            hue = playerVM?.videoHue ?? 0
            gamma = playerVM?.videoGamma ?? 1.0
        }
    }

    @ViewBuilder
    private var aspectRatioSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("화면 비율")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(ratios, id: \.1) { ratio, label in
                    MLSettingsGridButton(
                        label: label,
                        isSelected: selectedRatio == ratio
                    ) {
                        selectedRatio = ratio
                        playerVM?.setAspectRatio(ratio)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var videoFiltersSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("비디오 필터")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isFilterEnabled },
                    set: { newVal in
                        isFilterEnabled = newVal
                        playerVM?.setVideoAdjust(enabled: newVal)
                        if !newVal {
                            playerVM?.resetVideoAdjust()
                            brightness = 1.0; contrast = 1.0; saturation = 1.0
                            hue = 0; gamma = 1.0
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if isFilterEnabled {
                videoSlider(title: "밝기", value: $brightness, range: 0...2, defaultVal: 1.0) {
                    playerVM?.setVideoBrightness($0)
                }
                videoSlider(title: "대비", value: $contrast, range: 0...2, defaultVal: 1.0) {
                    playerVM?.setVideoContrast($0)
                }
                videoSlider(title: "채도", value: $saturation, range: 0...3, defaultVal: 1.0) {
                    playerVM?.setVideoSaturation($0)
                }
                videoSlider(title: "색조", value: $hue, range: -180...180, defaultVal: 0) {
                    playerVM?.setVideoHue($0)
                }
                videoSlider(title: "감마", value: $gamma, range: 0.01...10, defaultVal: 1.0) {
                    playerVM?.setVideoGamma($0)
                }

                Button("초기화") {
                    playerVM?.resetVideoAdjust()
                    brightness = 1.0; contrast = 1.0; saturation = 1.0
                    hue = 0; gamma = 1.0; isFilterEnabled = false
                }
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.error)
            }
        }
    }

    private func videoSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultVal: Float,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if abs(value.wrappedValue - defaultVal) > 0.01 {
                    Button {
                        value.wrappedValue = defaultVal
                        onChange(defaultVal)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Slider(value: value, in: range)
                .tint(DesignTokens.Colors.chzzkGreen)
                .onChange(of: value.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}
