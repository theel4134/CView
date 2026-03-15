// MARK: - PlayerAdvancedSettingsView.swift
// CViewApp - VLC 4.0 고급 플레이어 설정 Popover
// 이퀄라이저, 비디오 필터, 화면 비율, 자막, 오디오 설정

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
        .background(DesignTokens.Colors.surfaceBase.opacity(0.85))
        .background(.ultraThinMaterial)
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

// MARK: - Tools Tab (스크린샷, 녹화, 화질)

struct ToolsTabView: View {
    let playerVM: PlayerViewModel?
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 스크린샷
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("스크린샷")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                Button {
                    playerVM?.takeScreenshot()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "camera.fill")
                            .font(DesignTokens.Typography.caption)
                        Text("현재 화면 캡처")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 녹화
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("녹화")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(playerVM?.formattedRecordingDuration ?? "")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    Task {
                        if isRecording {
                            await playerVM?.stopRecording()
                            isRecording = false
                        } else {
                            await playerVM?.startRecordingWithSavePanel()
                            isRecording = playerVM?.isRecording ?? false
                        }
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isRecording ? .red : DesignTokens.Colors.textPrimary)
                        Text(isRecording ? "녹화 중지" : "녹화 시작")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isRecording ? Color.red.opacity(0.12) : DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(isRecording ? Color.red.opacity(0.3) : DesignTokens.Colors.border.opacity(DesignTokens.Glass.contentBorder), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 화질 선택
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("화질")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                let qualities = playerVM?.availableQualities ?? []
                if qualities.isEmpty {
                    Text("사용 가능한 화질 정보가 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    ForEach(qualities) { q in
                        Button {
                            Task { await playerVM?.switchQuality(q) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(q.name)
                                        .font(DesignTokens.Typography.captionMedium)
                                    Text(q.resolution)
                                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                Spacer()
                                if playerVM?.currentQuality?.id == q.id {
                                    Image(systemName: "checkmark")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                }
                            }
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(playerVM?.currentQuality?.id == q.id
                                          ? DesignTokens.Colors.chzzkGreen.opacity(0.1)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            isRecording = playerVM?.isRecording ?? false
        }
    }
}

// MARK: - Network Tab (싱글 플레이어)

struct SinglePlayerNetworkTabView: View {
    let playerVM: PlayerViewModel?
    var settingsStore: SettingsStore? = nil

    private var metrics: VLCLiveMetrics? { playerVM?.latestMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {

            // ── 실시간 스트림 모니터링 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("실시간 모니터링", icon: "waveform.path.ecg", color: DesignTokens.Colors.chzzkGreen)

                if let m = metrics {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(healthColor(m.healthScore))
                            .frame(width: 10, height: 10)
                        Text("스트림 건강도")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", m.healthScore * 100))
                            .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(healthColor(m.healthScore))
                    }

                    ProgressView(value: m.healthScore)
                        .tint(healthColor(m.healthScore))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                        metricCard("대역폭", formatBytesPerSec(m.networkBytesPerSec), icon: "arrow.down.circle")
                        metricCard("입력 비트레이트", String(format: "%.0f kbps", m.inputBitrateKbps), icon: "speedometer")
                        metricCard("FPS", String(format: "%.1f", m.fps), icon: "film")
                        metricCard("버퍼 건강도", String(format: "%.0f%%", m.bufferHealth * 100), icon: "heart.fill")
                        metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
                        metricCard("지연 프레임", "\(m.latePicturesDelta)", icon: "clock.badge.exclamationmark", alert: m.latePicturesDelta > 0)
                    }

                    HStack {
                        if let res = m.resolution {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(res)
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2fx", m.playbackRate))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if m.lostAudioBuffersDelta > 0 || m.demuxCorruptedDelta > 0 || m.demuxDiscontinuityDelta > 0 {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            if m.lostAudioBuffersDelta > 0 {
                                warningBadge("오디오 손실 \(m.lostAudioBuffersDelta)")
                            }
                            if m.demuxCorruptedDelta > 0 {
                                warningBadge("손상 패킷 \(m.demuxCorruptedDelta)")
                            }
                            if m.demuxDiscontinuityDelta > 0 {
                                warningBadge("불연속 \(m.demuxDiscontinuityDelta)")
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.xaxis.ascending")
                                .font(.title3)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("스트림 재생 시 메트릭이 표시됩니다")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, DesignTokens.Spacing.md)
                }
            }

            if let store = settingsStore {
                Divider()

                // ── 연결 설정 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("연결 설정", icon: "network", color: .orange)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("자동 재연결")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("스트림 연결 끊김 시 자동 재시도")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.network.autoReconnect },
                            set: { store.network.autoReconnect = $0; Task { await store.save() } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HStack {
                        Text("최대 재시도")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Spacer()
                        Stepper(
                            "\(store.network.maxReconnectAttempts)회",
                            value: Binding(
                                get: { store.network.maxReconnectAttempts },
                                set: { store.network.maxReconnectAttempts = $0; Task { await store.save() } }
                            ),
                            in: 1...30
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("재연결 대기 시간")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f초", store.network.reconnectBaseDelay))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { store.network.reconnectBaseDelay },
                                set: { store.network.reconnectBaseDelay = $0; Task { await store.save() } }
                            ),
                            in: 0.5...10.0,
                            step: 0.5
                        )
                        .tint(DesignTokens.Colors.chzzkGreen)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("스트림 타임아웃")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("스트림 초기 연결 대기 최대 시간")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Stepper(
                            "\(store.network.streamConnectionTimeout)초",
                            value: Binding(
                                get: { store.network.streamConnectionTimeout },
                                set: { store.network.streamConnectionTimeout = $0; Task { await store.save() } }
                            ),
                            in: 5...30
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }
                }

                Divider()

                // ── CDN 프록시 설정 ──
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    sectionHeader("CDN 프록시", icon: "shield.checkered", color: .purple)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("로컬 프록시 강제 사용")
                                .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                            Text("CDN Content-Type 수정 프록시 활성화")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.network.forceStreamProxy },
                            set: { store.network.forceStreamProxy = $0; Task { await store.save() } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    HStack {
                        Text("호스트당 최대 연결")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Spacer()
                        Stepper(
                            "\(store.network.maxConnectionsPerHost)",
                            value: Binding(
                                get: { store.network.maxConnectionsPerHost },
                                set: { store.network.maxConnectionsPerHost = $0; Task { await store.save() } }
                            ),
                            in: 1...24
                        )
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
        .onAppear { playerVM?.enableSelfMetrics(true) }
        .onDisappear { playerVM?.enableSelfMetrics(false) }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
        }
    }

    @ViewBuilder
    private func metricCard(_ label: String, _ value: String, icon: String, alert: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(alert ? .orange : DesignTokens.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(alert ? .orange : DesignTokens.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(alert ? Color.orange.opacity(0.06) : DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    @ViewBuilder
    private func warningBadge(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(text)
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.1)))
    }

    private func healthColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .orange }
        return .red
    }

    private func formatBytesPerSec(_ bytes: Int) -> String {
        let mbps = Double(bytes) * 8.0 / 1_000_000.0
        if mbps >= 1.0 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(bytes) * 8.0 / 1_000.0
        return String(format: "%.0f kbps", kbps)
    }
}
