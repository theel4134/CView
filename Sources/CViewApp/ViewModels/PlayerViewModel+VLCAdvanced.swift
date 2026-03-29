// MARK: - PlayerViewModel+VLCAdvanced.swift
// CViewApp — PlayerViewModel VLC 고급 설정 + 스크린샷 + 녹화

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer

extension PlayerViewModel {

    // MARK: - 스크린샷

    public func takeScreenshot() {
        guard let engine = playerEngine as? VLCPlayerEngine else { return }
        guard let tempURL = engine.captureSnapshot() else { return }
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let dir = picturesDir?.appendingPathComponent("CView Screenshots")
        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "CView_\(channelName)_\(Int(Date().timeIntervalSince1970)).png"
            let dest = dir.appendingPathComponent(name)
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                try? FileManager.default.copyItem(at: tempURL, to: dest)
                await MainActor.run { Log.player.info("스크린샷 저장: \(dest.path)") }
            }
        }
    }

    // MARK: - 이퀄라이저

    public func getEqualizerPresets() -> [String] {
        (playerEngine as? VLCPlayerEngine)?.equalizerPresets() ?? []
    }

    public func getEqualizerFrequencies() -> [Float] {
        (playerEngine as? VLCPlayerEngine)?.equalizerBandFrequencies() ?? []
    }

    public func applyEqualizerPreset(_ name: String) {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        vlc.setEqualizerPresetByName(name)
        equalizerPresetName = name
        isEqualizerEnabled = true
        equalizerPreAmp = vlc.equalizerPreAmpValue()
        equalizerBands = vlc.equalizerBandValues()
    }

    public func setEqualizerPreAmp(_ value: Float) {
        (playerEngine as? VLCPlayerEngine)?.setEqualizerPreAmp(value)
        equalizerPreAmp = value
    }

    public func setEqualizerBand(index: Int, value: Float) {
        (playerEngine as? VLCPlayerEngine)?.setEqualizerBand(index: index, value: value)
        if index < equalizerBands.count { equalizerBands[index] = value }
    }

    public func disableEqualizer() {
        (playerEngine as? VLCPlayerEngine)?.resetEqualizer()
        isEqualizerEnabled = false
        equalizerPresetName = ""
        equalizerPreAmp = 0
        equalizerBands = []
    }

    // MARK: - 비디오 조정

    public func setVideoAdjust(enabled: Bool) {
        (playerEngine as? VLCPlayerEngine)?.setVideoAdjustEnabled(enabled)
        isVideoAdjustEnabled = enabled
    }

    public func setVideoBrightness(_ v: Float)  { (playerEngine as? VLCPlayerEngine)?.setVideoBrightness(v); videoBrightness = v }
    public func setVideoContrast(_ v: Float)    { (playerEngine as? VLCPlayerEngine)?.setVideoContrast(v); videoContrast = v }
    public func setVideoSaturation(_ v: Float)  { (playerEngine as? VLCPlayerEngine)?.setVideoSaturation(v); videoSaturation = v }
    public func setVideoHue(_ v: Float)         { (playerEngine as? VLCPlayerEngine)?.setVideoHue(v); videoHue = v }
    public func setVideoGamma(_ v: Float)       { (playerEngine as? VLCPlayerEngine)?.setVideoGamma(v); videoGamma = v }

    public func resetVideoAdjust() {
        (playerEngine as? VLCPlayerEngine)?.resetVideoAdjust()
        isVideoAdjustEnabled = false
        videoBrightness = 1.0; videoContrast = 1.0; videoSaturation = 1.0
        videoHue = 0; videoGamma = 1.0
    }

    // MARK: - 화면 비율

    public func setAspectRatio(_ ratio: String?) {
        (playerEngine as? VLCPlayerEngine)?.setAspectRatio(ratio)
        aspectRatio = ratio
    }

    // MARK: - 오디오 고급

    public func setAudioStereoMode(_ mode: UInt) {
        (playerEngine as? VLCPlayerEngine)?.setAudioStereoMode(mode)
        audioStereoMode = mode
    }

    public func setAudioDelay(_ delay: Int) {
        (playerEngine as? VLCPlayerEngine)?.setAudioDelay(delay)
        audioDelay = delay
    }

    public func setAudioMixMode(_ mode: UInt32) {
        (playerEngine as? VLCPlayerEngine)?.setAudioMixMode(mode)
        audioMixMode = mode
    }

    // MARK: - 자막

    public func refreshSubtitleTracks() {
        subtitleTracks = (playerEngine as? VLCPlayerEngine)?.textTracks() ?? []
    }

    public func selectSubtitleTrack(_ index: Int) {
        if index < 0 {
            (playerEngine as? VLCPlayerEngine)?.deselectAllTextTracks()
            selectedSubtitleTrack = -1
        } else {
            (playerEngine as? VLCPlayerEngine)?.selectTextTrack(index)
            selectedSubtitleTrack = index
        }
    }

    public func addSubtitleFile(url: URL) {
        (playerEngine as? VLCPlayerEngine)?.addSubtitleFile(url: url)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            refreshSubtitleTracks()
        }
    }

    public func setSubtitleDelay(_ delay: Int) {
        (playerEngine as? VLCPlayerEngine)?.setSubtitleDelay(delay)
        subtitleDelay = delay
    }

    public func setSubtitleFontScale(_ scale: Float) {
        (playerEngine as? VLCPlayerEngine)?.setSubtitleFontScale(scale)
        subtitleFontScale = scale
    }

    /// 고급 설정 일괄 적용
    public func applyAdvancedSettings(from settings: PlayerSettings) {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        vlc.applyAdvancedSettings(settings)
        if let preset = settings.equalizerPreset {
            isEqualizerEnabled = true
            equalizerPresetName = preset
            equalizerPreAmp = vlc.equalizerPreAmpValue()
            equalizerBands = vlc.equalizerBandValues()
        }
        if settings.videoAdjustEnabled {
            isVideoAdjustEnabled = true
            videoBrightness = settings.videoBrightness; videoContrast = settings.videoContrast
            videoSaturation = settings.videoSaturation; videoHue = settings.videoHue
            videoGamma = settings.videoGamma
        }
        aspectRatio = settings.aspectRatio
        audioStereoMode = UInt(settings.audioStereoMode)
        audioMixMode = settings.audioMixMode
        audioDelay = Int(settings.audioDelay)
    }

    // MARK: - 녹화

    public func startRecording(to customURL: URL? = nil) async {
        guard let engine = playerEngine, !isRecording else { return }
        let url = customURL ?? StreamRecordingService.defaultRecordingURL(channelName: channelName)
        recordingURL = url
        do {
            try await engine.startRecording(to: url)
            isRecording = true
            recordingDuration = 0
            startRecordingTimer()
            logger.info("녹화 시작: \(url.lastPathComponent, privacy: .public)")
        } catch {
            errorMessage = "녹화 시작 실패: \(error.localizedDescription)"
        }
    }

    public func stopRecording() async {
        guard let engine = playerEngine, isRecording else { return }
        await engine.stopRecording()
        isRecording = false
        recordingTimerTask?.cancel(); recordingTimerTask = nil
        if let url = recordingURL {
            logger.info("녹화 저장 완료: \(url.path, privacy: .public)")
        }
    }

    public func toggleRecording() async {
        if isRecording { await stopRecording() } else { await startRecording() }
    }

    public func startRecordingWithSavePanel() async {
        let panel = NSSavePanel()
        panel.title = "녹화 파일 저장"
        panel.nameFieldStringValue = StreamRecordingService.defaultRecordingURL(channelName: channelName).lastPathComponent
        panel.allowedContentTypes = [.mpeg2TransportStream]
        panel.canCreateDirectories = true
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        if let dir = moviesDir?.appendingPathComponent("CView") {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            panel.directoryURL = dir
        }
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSPanel())
        guard response == .OK, let url = panel.url else { return }
        await startRecording(to: url)
    }

    public var formattedRecordingDuration: String { Self.formatTimeInterval(recordingDuration) }

    func startRecordingTimer() {
        recordingTimerTask?.cancel()
        let start = Date()
        recordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }
}
