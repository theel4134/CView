// MARK: - VLCPlayerEngine+Features.swift
// CViewPlayer — drawable 재바인딩, 재사용, 녹화, 메트릭 수집

import Foundation
import CViewCore
@preconcurrency import VLCKitSPM

extension VLCPlayerEngine {
    
    // MARK: - drawable 재바인딩

    /// VLC drawable을 nil → playerView 순서로 강제 리셋하여 vout 재생성을 트리거한다.
    public func refreshDrawable() {
        if Thread.isMainThread {
            player.drawable = nil
            player.drawable = playerView
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.player.drawable = nil
                self.player.drawable = playerView
            }
        }
    }

    /// VLC vout 파이프라인 강제 재생성.
    /// refreshDrawable()만으로 부족할 때 — 비디오 트랙을 순환(deselect → select)하여
    /// samplebufferdisplay 모듈을 완전히 파괴 후 재생성한다.
    public func forceVoutRecovery() {
        let doRecovery = { [weak self] in
            guard let self else { return }
            guard self.playerView.window != nil else { return }
            let state = self.player.state
            guard state != .stopped && state != .stopping else { return }
            let wasPlaying = state == .playing || state == .buffering || state == .opening

            self.player.drawable = nil
            self.player.drawable = self.playerView

            guard !self.player.videoTracks.isEmpty else { return }
            self.player.deselectAllVideoTracks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.player.videoTracks.isEmpty else { return }
                let state = self.player.state
                guard state != .stopped && state != .stopping else { return }
                self.player.selectTrack(at: 0, type: .video)
                if wasPlaying && (state == .paused || !self.player.isPlaying) {
                    self.player.play()
                }
            }
        }
        if Thread.isMainThread {
            doRecovery()
        } else {
            DispatchQueue.main.async { doRecovery() }
        }
    }

    // MARK: - 재사용 지원

    /// 에러 상태 여부 (PlayerEngineProtocol)
    public var isInErrorState: Bool {
        if case .error = _state.withLock({ $0.currentPhase }) { return true }
        return false
    }

    public func resetRetries() {}

    /// 풀 반납 전 엔진 초기화
    public func resetForReuse() {
        playTask?.cancel()
        _startPlayRetryTask?.cancel()
        _startPlayRetryTask = nil
        statsTask?.cancel()
        statsTask = nil
        let p = player
        let pv = playerView
        let doStop = { [weak self] in
            self?._prevStats = nil
            self?._lastBufferingDecodedCount = 0
            self?._bufferingFilterStartTime = nil
            self?._zeroFrameCount = 0
            p.delegate = nil
            p.stop()
            p.drawable = nil
            pv.layer?.sublayers?.forEach { sub in
                if sub !== pv.layer { sub.removeFromSuperlayer() }
            }
            self?._setPhase(.idle)
            p.delegate = self
        }
        if Thread.isMainThread {
            doStop()
        } else {
            DispatchQueue.main.async { doStop() }
        }
        onStateChange = nil
        onTimeChange = nil
        onVLCMetrics = nil
        onTrackEvent = nil
        onQualityAdaptationRequest = nil
        onPlaybackStalled = nil
        streamingProfile = .multiLive
        isSelectedSession = true
    }

    /// 비디오 트랙 활성화/비활성화
    public func setVideoTrackEnabled(_ enabled: Bool) {
        if enabled {
            if !player.videoTracks.isEmpty {
                player.selectTrack(at: 0, type: .video)
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !self.player.videoTracks.isEmpty {
                        self.player.selectTrack(at: 0, type: .video)
                    }
                }
            }
        } else {
            player.deselectAllVideoTracks()
        }
    }

    /// 백그라운드 모드 시 통계 수집 주기 조절 + 오디오 디코딩 비활성화
    public func setTimeUpdateMode(background: Bool) {
        if background {
            statsTask?.cancel()
            statsTask = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.deselectAllAudioTracks()
            }
        } else {
            startStatsTimer()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.player.audioTracks.isEmpty {
                    self.player.selectTrack(at: 0, type: .audio)
                    self.player.currentAudioPlaybackDelay = 0
                }
            }
        }
    }

    // MARK: - 녹화

    public var isRecording: Bool { _state.withLock { $0.isRecording } }

    public func startRecording(to url: URL) async throws {
        guard !_state.withLock({ $0.isRecording }) else { return }
        player.startRecording(atPath: url.path)
        _state.withLock { $0.isRecording = true }
    }

    public func stopRecording() async {
        guard _state.withLock({ $0.isRecording }) else { return }
        player.stopRecording()
        _state.withLock { $0.isRecording = false }
    }

    public func captureSnapshot() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let name = "snapshot_\(Int(Date().timeIntervalSince1970)).png"
        let url = dir.appendingPathComponent(name)
        player.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 버퍼 상태

    @MainActor
    public func bufferHealth() -> BufferHealth {
        guard let stats = player.media?.statistics else {
            return BufferHealth(currentLevel: 0, targetLevel: 1.0, isHealthy: true)
        }
        let displayed = max(Int(stats.displayedPictures), 0)
        let decoded   = max(Int(stats.decodedVideo), 1)
        let lost      = max(Int(stats.lostPictures), 0)
        let ratio     = Float(displayed) / Float(decoded)
        let isBuffering = player.state == .buffering
        let isHealthy   = displayed > 0 && lost == 0 && !isBuffering
        return BufferHealth(currentLevel: Double(ratio), targetLevel: 1.0, isHealthy: isHealthy)
    }

    // MARK: - 오디오 트랙

    public func audioTracks() -> [(Int, String)] {
        return player.audioTracks.enumerated().map { (i, t) in (i, t.trackName) }
    }

    public func setAudioTrack(_ index: Int) {
        player.selectTrack(at: index, type: .audio)
    }

    // MARK: - Private Helpers

    func _setPhase(_ phase: PlayerState.Phase) {
        let isDuplicate = (_lastEmittedPhase == phase)
        _state.withLock { $0.currentPhase = phase }
        guard !isDuplicate else { return }
        _lastEmittedPhase = phase
        onStateChange?(phase)
    }

    func startStatsTimer() {
        statsTask?.cancel()
        let interval: UInt64 = streamingProfile == .multiLive ? 10_000_000_000 : 3_000_000_000
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, let self else { break }
                await self.collectMetrics()
            }
        }
    }

    @MainActor
    func collectMetrics() {
        guard let stats = player.media?.statistics else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(_lastMetricsTime)
        _lastMetricsTime = now

        let prev = _prevStats
        _prevStats = stats

        guard let prev else { return }

        let droppedDelta = Int(stats.lostPictures) - Int(prev.lostPictures)
        let decodedDelta = Int(stats.decodedVideo) - Int(prev.decodedVideo)
        let audioLostDelta = Int(stats.lostAudioBuffers) - Int(prev.lostAudioBuffers)
        let lateDelta = Int(stats.latePictures) - Int(prev.latePictures)
        let demuxCorruptDelta = Int(stats.demuxCorrupted) - Int(prev.demuxCorrupted)
        let demuxDiscDelta = Int(stats.demuxDiscontinuity) - Int(prev.demuxDiscontinuity)
        let decodedAudioDelta = Int(stats.decodedAudio) - Int(prev.decodedAudio)
        let displayedDelta = Int(stats.displayedPictures) - Int(prev.displayedPictures)
        let playedAudioDelta = Int(stats.playedAudioBuffers) - Int(prev.playedAudioBuffers)
        let readBytesDelta = Int(stats.readBytes) - Int(prev.readBytes)
        let demuxReadBytesDelta = Int(stats.demuxReadBytes) - Int(prev.demuxReadBytes)

        let netBytesPerSec = elapsed > 0 ? max(0, readBytesDelta) / Int(max(elapsed, 0.001)) : 0
        let inputKbps = elapsed > 0 ? Double(max(0, readBytesDelta)) * 8.0 / elapsed / 1000.0 : 0.0
        let demuxKbps = elapsed > 0 ? Double(max(0, demuxReadBytesDelta)) * 8.0 / elapsed / 1000.0 : 0.0
        let fps = elapsed > 0 ? Double(max(0, decodedDelta)) / elapsed : 0.0

        let size = player.videoSize
        if size != _cachedVideoSize {
            _cachedVideoSize = size
            let w = size.width, h = size.height
            _cachedResolutionString = w > 0 && w.isFinite && h.isFinite ? "\(Int(w))x\(Int(h))" : nil
        }
        let resolution = _cachedResolutionString

        let metrics = VLCLiveMetrics(
            fps: fps,
            droppedFramesDelta: max(0, droppedDelta),
            decodedFramesDelta: max(0, decodedDelta),
            networkBytesPerSec: max(0, netBytesPerSec),
            inputBitrateKbps: inputKbps,
            demuxBitrateKbps: demuxKbps,
            resolution: resolution,
            videoWidth: Double(size.width),
            videoHeight: Double(size.height),
            playbackRate: player.rate,
            bufferHealth: bufferHealth().currentLevel,
            lostAudioBuffersDelta: max(0, audioLostDelta),
            decodedAudioDelta: max(0, decodedAudioDelta),
            playedAudioBuffersDelta: max(0, playedAudioDelta),
            readBytesDelta: max(0, readBytesDelta),
            demuxReadBytesDelta: max(0, demuxReadBytesDelta),
            displayedPicturesDelta: max(0, displayedDelta),
            latePicturesDelta: max(0, lateDelta),
            demuxCorruptedDelta: max(0, demuxCorruptDelta),
            demuxDiscontinuityDelta: max(0, demuxDiscDelta)
        )
        onVLCMetrics?(metrics)

        // 재생 정체 감지
        let currentPhase = _state.withLock { $0.currentPhase }
        if case .playing = currentPhase {
            if decodedDelta <= 0 {
                _zeroFrameCount += 1
                if _zeroFrameCount >= _zeroFrameStallThreshold {
                    _zeroFrameCount = 0
                    onPlaybackStalled?()
                }
            } else {
                _zeroFrameCount = 0
            }
        } else {
            _zeroFrameCount = 0
        }
    }
}
