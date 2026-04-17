// VLCPlayerEngine+AudioVideo.swift
// CViewPlayer — 이퀄라이저, 비디오 조정, 화면비율, 자막, 오디오 스테레오/믹스, 고급 설정 일괄 적용

import Foundation
import CViewCore
@preconcurrency import VLCKitSPM

// MARK: - 이퀄라이저

extension VLCPlayerEngine {

    public func equalizerPresets() -> [String] {
        return VLCAudioEqualizer.presets.map { $0.name }
    }

    public func setEqualizerPreset(_ index: Int) {
        let presets = VLCAudioEqualizer.presets
        guard index >= 0 && index < presets.count else { return }
        player.equalizer = VLCAudioEqualizer(preset: presets[index])
    }

    public func setEqualizerPresetByName(_ name: String) {
        let presets = VLCAudioEqualizer.presets
        guard let index = presets.firstIndex(where: { $0.name == name }) else { return }
        setEqualizerPreset(index)
    }

    public func setEqualizerPreAmp(_ value: Float) {
        guard let eq = player.equalizer else { return }
        eq.preAmplification = value
        player.equalizer = eq
    }

    public func setEqualizerBand(index: Int, value: Float) {
        guard let eq = player.equalizer else { return }
        let bands = eq.bands
        guard index >= 0 && index < bands.count else { return }
        bands[index].amplification = value
        player.equalizer = eq
    }

    public func equalizerBandCount() -> Int {
        return player.equalizer?.bands.count ?? VLCAudioEqualizer().bands.count
    }

    public func equalizerBandValues() -> [Float] {
        guard let eq = player.equalizer else { return [] }
        return eq.bands.map { $0.amplification }
    }

    public func equalizerBandFrequencies() -> [Float] {
        let eq = player.equalizer ?? VLCAudioEqualizer()
        return eq.bands.map { $0.frequency }
    }

    public func equalizerPreAmpValue() -> Float {
        return player.equalizer?.preAmplification ?? 0
    }

    public func resetEqualizer() {
        player.equalizer = nil
    }
}

// MARK: - 비디오 조정 필터

extension VLCPlayerEngine {

    public func setVideoAdjustEnabled(_ enabled: Bool) {
        player.adjustFilter.isEnabled = enabled
    }

    public func setVideoBrightness(_ value: Float) {
        player.adjustFilter.brightness.value = NSNumber(value: value)
    }

    public func setVideoContrast(_ value: Float) {
        player.adjustFilter.contrast.value = NSNumber(value: value)
    }

    public func setVideoSaturation(_ value: Float) {
        player.adjustFilter.saturation.value = NSNumber(value: value)
    }

    public func setVideoHue(_ value: Float) {
        player.adjustFilter.hue.value = NSNumber(value: value)
    }

    public func setVideoGamma(_ value: Float) {
        player.adjustFilter.gamma.value = NSNumber(value: value)
    }

    public func resetVideoAdjust() {
        player.adjustFilter.resetParametersIfNeeded()
        player.adjustFilter.isEnabled = false
    }
}

// MARK: - 화면비율 / 크롭 / 스케일

extension VLCPlayerEngine {

    public func setAspectRatio(_ ratio: String?) {
        player.videoAspectRatio = ratio
    }

    public func setCropRatio(numerator: UInt32, denominator: UInt32) {
        player.setCropRatioWithNumerator(UInt32(numerator), denominator: UInt32(denominator))
    }

    public func setScaleFactor(_ scale: Float) {
        player.scaleFactor = scale
    }
}

// MARK: - 자막 트랙

extension VLCPlayerEngine {

    public func textTracks() -> [(Int, String)] {
        return player.textTracks.enumerated().map { (i, t) in (i, t.trackName) }
    }

    public func selectTextTrack(_ index: Int) {
        let tracks = player.textTracks
        guard index >= 0 && index < tracks.count else { return }
        tracks[index].isSelectedExclusively = true
    }

    public func deselectAllTextTracks() {
        player.deselectAllTextTracks()
    }

    public func addSubtitleFile(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    public func setSubtitleDelay(_ delay: Int) {
        player.currentVideoSubTitleDelay = delay
    }

    public func setSubtitleFontScale(_ scale: Float) {
        player.currentSubTitleFontScale = scale
    }
}

// MARK: - 오디오 스테레오 / 믹스 모드

extension VLCPlayerEngine {

    public func setAudioStereoMode(_ mode: UInt) {
        guard let stereoMode = VLCMediaPlayer.AudioStereoMode(rawValue: mode) else { return }
        player.audioStereoMode = stereoMode
    }

    public func currentAudioStereoMode() -> UInt {
        return player.audioStereoMode.rawValue
    }

    public func setAudioMixMode(_ mode: UInt32) {
        guard let mixMode = VLCMediaPlayer.AudioMixMode(rawValue: mode) else { return }
        player.audioMixMode = mixMode
    }

    public func currentAudioMixMode() -> UInt32 {
        player.audioMixMode.rawValue
    }

    /// 오디오 지연 설정 (마이크로초)
    public func setAudioDelay(_ delay: Int) {
        Task { @MainActor [weak self] in
            self?.player.currentAudioPlaybackDelay = delay
        }
    }

    public func currentAudioDelay() -> Int {
        player.currentAudioPlaybackDelay
    }
}

// MARK: - 고급 설정 일괄 적용 (PlayerSettings)

extension VLCPlayerEngine {

    public func applyAdvancedSettings(_ settings: PlayerSettings) {
        // 이퀄라이저
        if let preset = settings.equalizerPreset {
            setEqualizerPresetByName(preset)
            setEqualizerPreAmp(settings.equalizerPreAmp)
            for (i, val) in settings.equalizerBands.enumerated() {
                setEqualizerBand(index: i, value: val)
            }
        } else {
            resetEqualizer()
        }
        // 비디오 조정
        setVideoAdjustEnabled(settings.videoAdjustEnabled)
        if settings.videoAdjustEnabled {
            setVideoBrightness(settings.videoBrightness)
            setVideoContrast(settings.videoContrast)
            setVideoSaturation(settings.videoSaturation)
            setVideoHue(settings.videoHue)
            setVideoGamma(settings.videoGamma)
        }
        // 선명한 화면 (픽셀 샤프 스케일링)
        sharpPixelScaling = settings.sharpPixelScaling
        // 화면 비율
        setAspectRatio(settings.aspectRatio)
        // 오디오 고급
        setAudioStereoMode(UInt(settings.audioStereoMode))
        setAudioMixMode(settings.audioMixMode)
        setAudioDelay(Int(settings.audioDelay))
    }
}
