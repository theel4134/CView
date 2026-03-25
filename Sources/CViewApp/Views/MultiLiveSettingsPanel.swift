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
                        case .playback:   MLPlaybackTab(playerVM: playerVM)
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

            VStack(alignment: .leading, spacing: 1) {
                Text("멀티라이브 설정")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let session = activeSession {
                    Text(session.channelName)
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
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MLSettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(DesignTokens.Animation.fast) { selectedTab = tab }
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
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }
}

// MARK: - Audio Tab

private struct MLAudioTab: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    @State private var volumeValue: Float = 1.0
    @State private var isMuted: Bool = false
    @State private var audioDelay: Double = 0
    @State private var isAudioOnly: Bool = false

    private var playerVM: PlayerViewModel { session.playerViewModel }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // 볼륨
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("볼륨")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                        .foregroundStyle(isMuted ? .red : DesignTokens.Colors.chzzkGreen)
                        .font(DesignTokens.Typography.caption)
                    Text(isMuted ? "음소거" : "\(Int(volumeValue * 100))%")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(value: $volumeValue, in: 0...1, step: 0.01)
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .onChange(of: volumeValue) { _, newVal in
                            playerVM.setVolume(newVal)
                            if isMuted && newVal > 0 {
                                isMuted = false
                                session.setMuted(false)
                            }
                        }

                    Button {
                        isMuted.toggle()
                        session.setMuted(isMuted)
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(isMuted ? .red : DesignTokens.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // A/V 싱크 (오디오 지연)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("A/V 동기화")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Spacer()
                    Text(String(format: "%.1fms", audioDelay / 1000))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if audioDelay != 0 {
                        Button {
                            audioDelay = 0
                            playerVM.setAudioDelay(0)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Slider(value: $audioDelay, in: -500_000...500_000, step: 10_000)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .onChange(of: audioDelay) { _, newVal in
                        playerVM.setAudioDelay(Int(newVal))
                    }

                Text("음수: 오디오가 빨라짐 / 양수: 오디오가 느려짐")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Divider()

            // 오디오 전용 모드
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오디오 전용")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                    Text("영상을 끄고 소리만 재생 (CPU 절약)")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $isAudioOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isAudioOnly) { _, _ in
                        playerVM.toggleAudioOnly()
                    }
            }
        }
        .onAppear {
            volumeValue = playerVM.volume
            isMuted = playerVM.isMuted
            audioDelay = Double(playerVM.audioDelay)
            isAudioOnly = playerVM.isAudioOnly
        }
        .id(session.id) // 세션 전환 시 상태 리셋
    }

    private var volumeIcon: String {
        if volumeValue == 0 { return "speaker.fill" }
        if volumeValue < 0.33 { return "speaker.wave.1.fill" }
        if volumeValue < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Equalizer Tab

private struct MLEqualizerTab: View {
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
                            ForEach(Array(bands.enumerated()), id: \.offset) { index, _ in
                                VStack(spacing: 4) {
                                    Text(String(format: "%.0f", bands[index]))
                                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)

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
                                        .foregroundStyle(.tertiary)
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

// MARK: - Video Tab

private struct MLVideoTab: View {
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
            // 화면 비율
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("화면 비율")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: DesignTokens.Spacing.xs) {
                    ForEach(ratios, id: \.1) { ratio, label in
                        Button {
                            selectedRatio = ratio
                            playerVM?.setAspectRatio(ratio)
                        } label: {
                            Text(label)
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
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
                }
            }

            Divider()

            // 비디오 필터
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
                    .foregroundStyle(.red)
                }
            }
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if abs(value.wrappedValue - defaultVal) > 0.01 {
                    Button {
                        value.wrappedValue = defaultVal
                        onChange(defaultVal)
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
                }
        }
    }
}

// MARK: - Playback Tab

private struct MLPlaybackTab: View {
    let playerVM: PlayerViewModel?
    @State private var playbackRate: Double = 1.0

    private let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("재생 속도")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            // 프리셋 버튼
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

            // 커스텀 슬라이더
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

// MARK: - Tools Tab

private struct MLToolsTab: View {
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

// MARK: - Network Tab

private struct MLNetworkTab: View {
    let session: MultiLiveSession
    @Bindable var settingsStore: SettingsStore

    private var metrics: VLCLiveMetrics? { session.latestMetrics }
    private var proxyStats: ProxyNetworkStats? { session.latestProxyStats }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {

            // ── 실시간 스트림 모니터링 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("실시간 모니터링", icon: "waveform.path.ecg", color: DesignTokens.Colors.chzzkGreen)

                if let m = metrics {
                    // 건강도 게이지
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

                    // 메트릭 그리드
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                        metricCard("대역폭", formatBytesPerSec(m.networkBytesPerSec), icon: "arrow.down.circle")
                        metricCard("입력 비트레이트", String(format: "%.0f kbps", m.inputBitrateKbps), icon: "speedometer")
                        metricCard("FPS", String(format: "%.1f", m.fps), icon: "film")
                        metricCard("버퍼 건강도", String(format: "%.0f%%", m.bufferHealth * 100), icon: "heart.fill")
                        metricCard("드롭 프레임", "\(m.droppedFramesDelta)", icon: "exclamationmark.triangle", alert: m.droppedFramesDelta > 0)
                        metricCard("지연 프레임", "\(m.latePicturesDelta)", icon: "clock.badge.exclamationmark", alert: m.latePicturesDelta > 0)
                    }

                    // 해상도 & 재생 속도
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

                    // 추가 품질 지표
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

            Divider()

            // ── 프록시 상태 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("프록시 상태", icon: "server.rack", color: DesignTokens.Colors.accentBlue)

                if let p = proxyStats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                        metricCard("총 요청", "\(p.totalRequests)", icon: "arrow.up.arrow.down")
                        metricCard("캐시 적중률", String(format: "%.0f%%", p.cacheHitRatio * 100), icon: "memorychip")
                        metricCard("활성 연결", "\(p.activeConnections)", icon: "link")
                        metricCard("평균 응답", String(format: "%.0fms", p.avgResponseTime * 1000), icon: "timer")
                    }

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("수신: \(formatBytes(p.totalBytesReceived))")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("전달: \(formatBytes(p.totalBytesServed))")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if p.errorCount > 0 || p.consecutive403Count > 0 {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            if p.errorCount > 0 {
                                warningBadge("에러 \(p.errorCount) (비율 \(String(format: "%.1f%%", p.errorRate * 100)))")
                            }
                            if p.consecutive403Count > 0 {
                                warningBadge("연속 403: \(p.consecutive403Count)")
                            }
                        }
                    }
                } else {
                    Text("프록시 통계 없음")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
            }

            Divider()

            // ── 연결 설정 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("연결 설정", icon: "network", color: .orange)

                // 자동 재연결
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("자동 재연결")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Text("스트림 연결 끊김 시 자동 재시도")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsStore.network.autoReconnect)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // 최대 재시도 횟수
                HStack {
                    Text("최대 재시도")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Spacer()
                    Stepper(
                        "\(settingsStore.network.maxReconnectAttempts)회",
                        value: $settingsStore.network.maxReconnectAttempts,
                        in: 1...30
                    )
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                }

                // 재연결 대기 시간
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("재연결 대기 시간")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f초", settingsStore.network.reconnectBaseDelay))
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settingsStore.network.reconnectBaseDelay,
                        in: 0.5...10.0,
                        step: 0.5
                    )
                    .tint(DesignTokens.Colors.chzzkGreen)

                    Text("첫 재시도 대기 간격 (이후 지수 백오프)")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                // 스트림 연결 타임아웃
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
                        "\(settingsStore.network.streamConnectionTimeout)초",
                        value: $settingsStore.network.streamConnectionTimeout,
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
                    Toggle("", isOn: $settingsStore.network.forceStreamProxy)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                HStack {
                    Text("호스트당 최대 연결")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    Spacer()
                    Stepper(
                        "\(settingsStore.network.maxConnectionsPerHost)",
                        value: $settingsStore.network.maxConnectionsPerHost,
                        in: 1...24
                    )
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                }
            }

            Divider()

            // ── 백그라운드 절전 ──
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                sectionHeader("멀티라이브 최적화", icon: "bolt.circle", color: .cyan)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("백그라운드 품질 저하")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        Text("비활성 세션의 화질을 자동 낮춤 (CPU/대역폭 절약)")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsStore.multiLive.backgroundQualityReduction)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
        .onAppear { session.showNetworkMetrics = true }
        .onDisappear { session.showNetworkMetrics = false }
        .id(session.id)
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

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
