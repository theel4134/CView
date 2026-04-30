// MARK: - PlayerAdvancedSettings+MediaTabs.swift
// CViewApp - 비디오 필터, 화면 비율, 자막, 오디오, 재생 속도 탭

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence
import AppKit

// MARK: - Video Filter Tab

struct VideoFilterTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil
    @State private var isEnabled = false
    @State private var brightness: Float = 1.0
    @State private var contrast: Float = 1.0
    @State private var saturation: Float = 1.0
    @State private var hue: Float = 0
    @State private var gamma: Float = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("비디오 필터")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newVal in
                        isEnabled = newVal
                        playerVM?.setVideoAdjust(enabled: newVal)
                        settingsStore?.player.videoAdjustEnabled = newVal
                        if !newVal {
                            settingsStore?.player.videoBrightness = 1.0
                            settingsStore?.player.videoContrast = 1.0
                            settingsStore?.player.videoSaturation = 1.0
                            settingsStore?.player.videoHue = 0
                            settingsStore?.player.videoGamma = 1.0
                        }
                        persistSettings()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if isEnabled {
                filterSlider(title: "밝기", value: $brightness, range: 0...2, defaultVal: 1.0, settingsKey: \.videoBrightness) {
                    playerVM?.setVideoBrightness($0)
                }
                filterSlider(title: "대비", value: $contrast, range: 0...2, defaultVal: 1.0, settingsKey: \.videoContrast) {
                    playerVM?.setVideoContrast($0)
                }
                filterSlider(title: "채도", value: $saturation, range: 0...3, defaultVal: 1.0, settingsKey: \.videoSaturation) {
                    playerVM?.setVideoSaturation($0)
                }
                filterSlider(title: "색조", value: $hue, range: -180...180, defaultVal: 0, settingsKey: \.videoHue) {
                    playerVM?.setVideoHue($0)
                }
                filterSlider(title: "감마", value: $gamma, range: 0.01...10, defaultVal: 1.0, settingsKey: \.videoGamma) {
                    playerVM?.setVideoGamma($0)
                }

                Button("초기화") {
                    playerVM?.resetVideoAdjust()
                    brightness = 1.0; contrast = 1.0; saturation = 1.0
                    hue = 0; gamma = 1.0; isEnabled = false
                    settingsStore?.player.videoAdjustEnabled = false
                    settingsStore?.player.videoBrightness = 1.0
                    settingsStore?.player.videoContrast = 1.0
                    settingsStore?.player.videoSaturation = 1.0
                    settingsStore?.player.videoHue = 0
                    settingsStore?.player.videoGamma = 1.0
                    persistSettings()
                }
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            isEnabled = playerVM?.isVideoAdjustEnabled ?? false
            brightness = playerVM?.videoBrightness ?? 1.0
            contrast = playerVM?.videoContrast ?? 1.0
            saturation = playerVM?.videoSaturation ?? 1.0
            hue = playerVM?.videoHue ?? 0
            gamma = playerVM?.videoGamma ?? 1.0
        }
    }

    private func filterSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultVal: Float,
        settingsKey: WritableKeyPath<PlayerSettings, Float>,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                // 기본값 복원 버튼
                if abs(value.wrappedValue - defaultVal) > 0.01 {
                    Button {
                        value.wrappedValue = defaultVal
                        onChange(defaultVal)
                        settingsStore?.player[keyPath: settingsKey] = defaultVal
                        persistSettings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Slider(value: value, in: range)
                .tint(DesignTokens.Colors.chzzkGreen)
                .onChange(of: value.wrappedValue) { _, newValue in
                    onChange(newValue)
                    settingsStore?.player[keyPath: settingsKey] = newValue
                    persistSettings()
                }
        }
    }

    private func persistSettings() {
        guard let store = settingsStore else { return }
        Task { await store.save() }
    }
}

// MARK: - Aspect Ratio Tab

struct AspectRatioTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil
    @State private var selectedRatio: String? = nil

    private let ratios: [(String?, String)] = [
        (nil, "기본"),
        ("16:9", "16:9"),
        ("4:3", "4:3"),
        ("21:9", "21:9 울트라와이드"),
        ("1:1", "1:1 정사각"),
        ("16:10", "16:10"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("화면 비율")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(ratios, id: \.1) { ratio, label in
                    ratioButton(ratio: ratio, label: label)
                }
            }
        }
        .onAppear {
            let current = playerVM?.aspectRatio
            // nil과 빈 문자열 모두 "기본"으로 취급
            selectedRatio = (current == nil || current?.isEmpty == true) ? nil : current
        }
    }

    private func ratioButton(ratio: String?, label: String) -> some View {
        Button {
            selectedRatio = ratio
            playerVM?.setAspectRatio(ratio)
            settingsStore?.player.aspectRatio = ratio
            Task { await settingsStore?.save() }
        } label: {
            VStack(spacing: 4) {
                ratioPreview(ratio)
                    .frame(width: 50, height: 35)

                Text(label)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(selectedRatio == ratio
                          ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                          : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(selectedRatio == ratio
                                  ? DesignTokens.Colors.chzzkGreen
                                  : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func ratioPreview(_ ratio: String?) -> some View {
        let w: CGFloat
        let h: CGFloat
        switch ratio {
        case "16:9":  w = 48; h = 27
        case "4:3":   w = 40; h = 30
        case "21:9":  w = 50; h = 21
        case "1:1":   w = 30; h = 30
        case "16:10": w = 48; h = 30
        default:      w = 48; h = 27
        }
        return RoundedRectangle(cornerRadius: 3)
            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.3))
            .frame(width: w, height: h)
    }
}

// MARK: - Subtitle Tab

struct SubtitleTabView: View {
    let playerVM: PlayerViewModel?
    @State private var tracks: [(Int, String)] = []
    @State private var selectedTrack: Int = -1
    @State private var delay: Double = 0
    @State private var fontScale: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("자막")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
                Button("새로고침") {
                    playerVM?.refreshSubtitleTracks()
                    tracks = playerVM?.subtitleTracks ?? []
                }
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }

            // 자막 트랙 선택
            Picker("자막 트랙", selection: $selectedTrack) {
                Text("없음").tag(-1)
                ForEach(tracks, id: \.0) { index, name in
                    Text(name).tag(index)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTrack) { _, newValue in
                playerVM?.selectSubtitleTrack(newValue)
            }

            // 외부 자막 파일 추가
            Button {
                openSubtitleFile()
            } label: {
                Label("외부 자막 파일 추가", systemImage: "doc.badge.plus")
                    .font(DesignTokens.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            Divider()

            // 자막 지연
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("지연")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f초", delay / 1_000_000))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $delay, in: -5_000_000...5_000_000, step: 100_000)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: delay) { _, newValue in
                        playerVM?.setSubtitleDelay(Int(newValue))
                    }
            }

            // 폰트 크기
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("폰트 크기")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fontScale))%")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $fontScale, in: 50...200, step: 10)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: fontScale) { _, newValue in
                        playerVM?.setSubtitleFontScale(Float(newValue))
                    }
            }
        }
        .onAppear {
            playerVM?.refreshSubtitleTracks()
            tracks = playerVM?.subtitleTracks ?? []
            selectedTrack = playerVM?.selectedSubtitleTrack ?? -1
            delay = Double(playerVM?.subtitleDelay ?? 0)
            fontScale = Double(playerVM?.subtitleFontScale ?? 100.0)
        }
    }

    private func openSubtitleFile() {
        let panel = NSOpenPanel()
        panel.title = "자막 파일 선택"
        panel.allowedContentTypes = [
            .init(filenameExtension: "srt")!,
            .init(filenameExtension: "ass")!,
            .init(filenameExtension: "ssa")!,
            .init(filenameExtension: "vtt")!,
            .init(filenameExtension: "sub")!,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            playerVM?.addSubtitleFile(url: url)
        }
    }
}

// MARK: - Audio Tab

struct AudioTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil
    @State private var stereoMode: UInt = 0
    @State private var mixMode: UInt32 = 0
    @State private var audioDelay: Double = 0

    private let stereoModes: [(UInt, String)] = [
        (0, "기본"),
        (1, "스테레오"),
        (5, "돌비 서라운드"),
        (7, "모노"),
        (3, "왼쪽만"),
        (4, "오른쪽만"),
    ]

    private let mixModes: [(UInt32, String)] = [
        (0, "기본"),
        (1, "스테레오"),
        (2, "바이노럴"),
        (3, "4.0"),
        (4, "5.1"),
        (5, "7.1"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("오디오 설정")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            // 스테레오 모드
            VStack(alignment: .leading, spacing: 4) {
                Text("스테레오 모드")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $stereoMode) {
                    ForEach(stereoModes, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: stereoMode) { _, newValue in
                    playerVM?.setAudioStereoMode(newValue)
                    settingsStore?.player.audioStereoMode = Int(newValue)
                    persistSettings()
                }
            }

            // 믹스 모드
            VStack(alignment: .leading, spacing: 4) {
                Text("믹스 모드")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $mixMode) {
                    ForEach(mixModes, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: mixMode) { _, newValue in
                    playerVM?.setAudioMixMode(newValue)
                    settingsStore?.player.audioMixMode = newValue
                    persistSettings()
                }
            }

            Divider()

            // 오디오 지연
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("오디오 지연 (A/V 동기화)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.1f초", audioDelay / 1_000_000))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $audioDelay, in: -3_000_000...3_000_000, step: 50_000)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: audioDelay) { _, newValue in
                        playerVM?.setAudioDelay(Int(newValue))
                        settingsStore?.player.audioDelay = Int64(newValue)
                        persistSettings()
                    }

                if abs(audioDelay) > 0 {
                    Button("지연 초기화") {
                        audioDelay = 0
                        playerVM?.setAudioDelay(0)
                        settingsStore?.player.audioDelay = 0
                        persistSettings()
                    }
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            stereoMode = playerVM?.audioStereoMode ?? 0
            mixMode = playerVM?.audioMixMode ?? 0
            audioDelay = Double(playerVM?.audioDelay ?? 0)
        }
    }

    private func persistSettings() {
        guard let store = settingsStore else { return }
        Task { await store.save() }
    }
}

// MARK: - Playback Tab (재생 속도)

struct PlaybackTabView: View {
    let playerVM: PlayerViewModel?
    @State private var playbackRate: Double = 1.0

    private let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("재생 속도")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        playbackRate = rate
                        Task { await playerVM?.setPlaybackRate(rate) }
                    } label: {
                        Text(rate == 1.0 ? "1x" : String(format: "%.2gx", rate))
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(abs(playbackRate - rate) < 0.01
                                          ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                                          : Color.gray.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .strokeBorder(abs(playbackRate - rate) < 0.01
                                                  ? DesignTokens.Colors.chzzkGreen
                                                  : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("미세 조정")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", playbackRate))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $playbackRate, in: 0.5...2.0, step: 0.05)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: playbackRate) { _, newValue in
                        Task { await playerVM?.setPlaybackRate(newValue) }
                    }
            }

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
}
