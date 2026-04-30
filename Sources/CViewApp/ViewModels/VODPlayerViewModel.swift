// MARK: - VODPlayerViewModel.swift
// VOD 재생 ViewModel

import Foundation
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking

/// VOD 재생 관리 ViewModel
@Observable
@MainActor
public final class VODPlayerViewModel {
    
    // MARK: - Published State
    
    var playbackState: VODPlaybackState = .idle
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferedTime: TimeInterval = 0
    var playbackSpeed: PlaybackSpeed = .x100
    var volume: Float = 1.0
    var isMuted: Bool = false
    var isFullscreen: Bool = false
    var videoTitle: String = ""
    var channelName: String = ""
    var errorMessage: String?
    var streamInfo: VODStreamInfo?
    var isSeeking: Bool = false
    
    // MARK: - Player Engine
    
    private(set) var playerEngine: AVPlayerEngine?
    
    // MARK: - Dependencies
    
    private let resolver: VODStreamResolver
    private let logger = AppLogger.player
    private var previousVolume: Float = 1.0
    
    // MARK: - Initialization
    
    init(apiClient: ChzzkAPIClient) {
        self.resolver = VODStreamResolver(apiClient: apiClient)
    }
    
    // MARK: - Playback Control
    
    /// VOD 재생 시작
    func startVOD(videoNo: Int) async {
        playbackState = .loading
        errorMessage = nil
        
        do {
            let info = try await resolver.resolveVOD(videoNo: videoNo)
            self.streamInfo = info
            self.videoTitle = info.title
            self.channelName = info.channelName
            self.duration = info.duration
            
            let engine = AVPlayerEngine()
            self.playerEngine = engine
            
            // Setup callbacks
            engine.onStateChange = { [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch phase {
                    case .playing:
                        self.playbackState = .playing
                    case .paused:
                        self.playbackState = .paused
                    case .buffering:
                        self.playbackState = .buffering
                    case .ended:
                        self.playbackState = .ended
                    case .error:
                        self.playbackState = .error("재생 오류가 발생했습니다")
                    case .idle:
                        self.playbackState = .idle
                    case .loading:
                        self.playbackState = .loading
                    }
                }
            }
            
            engine.onTimeChange = { [weak self] current, total in
                Task { @MainActor [weak self] in
                    guard let self, !self.isSeeking else { return }
                    self.currentTime = current
                    if total > 0 { self.duration = total }
                }
            }
            
            try await engine.play(url: info.streamURL)
            engine.setRate(playbackSpeed.rawValue)
            engine.setVolume(volume)
            playbackState = .playing
            
            logger.info("VOD started: \(info.title)")
        } catch {
            playbackState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            logger.error("VOD start failed: \(error)")
        }
    }
    
    /// 재생/일시정지 토글
    func togglePlayPause() {
        guard let engine = playerEngine else { return }
        
        switch playbackState {
        case .playing:
            engine.pause()
            playbackState = .paused
        case .paused:
            engine.resume()
            playbackState = .playing
        case .ended:
            // Restart from beginning
            engine.seek(to: 0)
            engine.resume()
            playbackState = .playing
        default:
            break
        }
    }
    
    /// 특정 위치로 이동
    func seek(to time: TimeInterval) {
        guard let engine = playerEngine else { return }
        isSeeking = true
        currentTime = time
        engine.seek(to: time)
        
        // Reset seeking flag after a delay
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run { self?.isSeeking = false }
        }
    }
    
    /// 상대 시간 이동 (±초)
    func seekRelative(_ offset: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + offset))
        seek(to: newTime)
    }
    
    /// 재생 속도 변경
    func setSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        playerEngine?.setRate(speed.rawValue)
    }
    
    /// 볼륨 조절
    func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        volume = clamped
        playerEngine?.setVolume(clamped)
        if clamped > 0 { isMuted = false }
    }
    
    /// 음소거 토글
    func toggleMute() {
        if isMuted {
            isMuted = false
            playerEngine?.setVolume(previousVolume)
            volume = previousVolume
        } else {
            previousVolume = volume
            isMuted = true
            playerEngine?.setVolume(0)
            volume = 0
        }
    }
    
    /// 볼륨 증감
    func adjustVolume(_ delta: Float) {
        let newVol = max(0, min(1, volume + delta))
        setVolume(newVol)
    }
    
    /// 전체화면 토글
    func toggleFullscreen() {
        isFullscreen.toggle()
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }
    
    /// 정지 및 정리
    func stop() {
        // 콜백 정리 — 엔진 해제 전 dangling callback 방지
        if let av = playerEngine as? AVPlayerEngine {
            av.onStateChange = nil
            av.onTimeChange = nil
        }
        playerEngine?.stop()
        playerEngine = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        streamInfo = nil
    }
    
    /// 시간 포맷팅 헬퍼
    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    /// 진행률 (0.0 ~ 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
