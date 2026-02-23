// MARK: - ClipPlayerViewModel.swift
// 클립 재생 ViewModel

import Foundation
import SwiftUI
import WebKit
import CViewCore
import CViewPlayer
import CViewNetworking

/// 클립 재생 관리 ViewModel (VOD보다 단순한 구조)
@Observable
@MainActor
public final class ClipPlayerViewModel {
    
    // MARK: - State
    
    var playbackState: VODPlaybackState = .idle
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0
    var isMuted: Bool = false
    var clipTitle: String = ""
    var channelName: String = ""
    var errorMessage: String?
    var isSeeking: Bool = false
    /// ABR_HLS 등 직접 재생 불가 시 embed URL로 WebView 재생
    var embedFallbackURL: URL?
    
    // MARK: - Player Engine
    
    private(set) var playerEngine: VLCPlayerEngine?
    
    // MARK: - Dependencies
    
    private let apiClient: ChzzkAPIClient?
    private let logger = AppLogger.player
    private var previousVolume: Float = 1.0
    
    // MARK: - Init
    
    init(apiClient: ChzzkAPIClient? = nil) {
        self.apiClient = apiClient
    }
    
    // MARK: - Playback Control
    
    /// 클립 재생 시작 (URL 직접 제공)
    func startClip(config: ClipPlaybackConfig) async {
        playbackState = .loading
        errorMessage = nil
        clipTitle = config.title
        channelName = config.channelName
        duration = config.duration
        
        do {
            let engine = VLCPlayerEngine()
            self.playerEngine = engine
            
            engine.onStateChange = { [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch phase {
                    case .playing: self.playbackState = .playing
                    case .paused: self.playbackState = .paused
                    case .buffering: self.playbackState = .buffering
                    case .ended: self.playbackState = .ended
                    case .error: self.playbackState = .error("재생 오류")
                    case .idle: self.playbackState = .idle
                    case .loading: self.playbackState = .loading
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
            
            try await engine.play(url: config.streamURL)
            engine.setVolume(volume)
            playbackState = .playing
            
            logger.info("Clip started: \(config.title)")
        } catch {
            playbackState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            logger.error("Clip start failed: \(error)")
        }
    }
    
    /// 클립 재생 시작 (ClipInfo에서)
    /// - Note: 대부분의 클립이 ABR_HLS 타입이므로 embed WebView를 즉시 표시하고,
    ///         백그라운드에서 직접 재생 URL을 탐색합니다 (발견 시 VLC로 전환).
    func startClip(from clipInfo: ClipInfo) async {
        guard !clipInfo.clipUID.isEmpty else {
            playbackState = .error("클립 ID가 없습니다")
            errorMessage = "클립 ID가 없습니다"
            return
        }

        // ClipInfo에서 바로 제목/채널 설정 (즉시 표시)
        clipTitle = clipInfo.clipTitle
        channelName = clipInfo.channel?.channelName ?? ""
        errorMessage = nil

        // embed WebView 즉시 표시 — 로딩 없이 바로 재생 시작
        let embedURL = URL(string: "https://chzzk.naver.com/embed/clip/\(clipInfo.clipUID)")!
        embedFallbackURL = embedURL
        playbackState = .paused

        // 백그라운드에서 직접 재생 URL 탐색 (드물게 직접 URL이 있을 때만 VLC 전환)
        guard let api = apiClient else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await api.clipDetail(clipUID: clipInfo.clipUID)
                await MainActor.run {
                    if !detail.clipTitle.isEmpty { self.clipTitle = detail.clipTitle }
                    if let ch = detail.channel?.channelName, !ch.isEmpty { self.channelName = ch }
                }
                // 직접 재생 URL이 있으면 VLC로 전환 (ABR_HLS인 경우 bestPlaybackURL = nil)
                if let url = detail.bestPlaybackURL {
                    await self.switchToVLCPlayer(streamURL: url, clipUID: clipInfo.clipUID)
                }
                // ABR_HLS + videoId: inkey 시도 (로그인 쿠키 있을 때만 성공)
                else if let videoId = detail.videoId, !videoId.isEmpty {
                    await self.syncWebKitCookies()
                    do {
                        let hlsURL = try await api.clipStreamURL(clipUID: clipInfo.clipUID, videoId: videoId)
                        await self.switchToVLCPlayer(streamURL: hlsURL, clipUID: clipInfo.clipUID)
                    } catch {
                        // inkey 실패 — embed 유지 (이미 재생 중)
                        self.logger.info("Clip inkey failed (embed already playing): \(clipInfo.clipUID)")
                    }
                }
            } catch {
                // detail API 실패 — embed 유지
                self.logger.warning("Clip detail fetch failed (embed already playing): \(error)")
            }
        }
    }
    
    /// embed WebView에서 video URL이 추출되면 VLC로 전환
    func switchToVLCPlayer(streamURL: URL, clipUID: String) async {
        let urlString = streamURL.absoluteString
        // blob: URL 제외, http(s) URL만 허용
        guard !urlString.hasPrefix("blob:"),
              urlString.hasPrefix("http") else {
            logger.warning("Clip embed ignored non-http URL: \(urlString.prefix(80))")
            return
        }
        // 이미 직접 재생 중이면 무시
        guard embedFallbackURL != nil else { return }
        logger.info("Clip embed extracted URL, switching to VLC: \(urlString.prefix(100))")
        let savedEmbedURL = embedFallbackURL
        embedFallbackURL = nil
        let config = ClipPlaybackConfig(
            clipUID: clipUID,
            title: clipTitle,
            streamURL: streamURL,
            duration: duration,
            channelName: channelName,
            thumbnailURL: nil
        )
        await startClip(config: config)
        // VLC 재생 실패 시 embed WebView로 복귀
        if case .error = playbackState {
            logger.warning("VLC failed for extracted URL, reverting to embed WebView")
            playerEngine = nil
            embedFallbackURL = savedEmbedURL
            playbackState = .paused
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
        
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isSeeking = false
        }
    }
    
    /// 상대 시간 이동
    func seekRelative(_ offset: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + offset))
        seek(to: newTime)
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
    
    /// 정지
    func stop() {
        playerEngine?.stop()
        playerEngine = nil
        playbackState = .idle
        currentTime = 0
    }
    
    /// WKWebsiteDataStore NID 쿠키를 HTTPCookieStorage.shared에 동기화 (inkey 인증용)
    @MainActor
    private func syncWebKitCookies() async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where ["NID_AUT", "NID_SES"].contains(cookie.name) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                continuation.resume()
            }
        }
    }

    /// 시간 포맷팅
    static func formatTime(_ seconds: TimeInterval) -> String {
        VODPlayerViewModel.formatTime(seconds)
    }
    
    /// 진행률
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    /// 재생 중/일시정지/버퍼링 여부 (에러/종료/로딩 상태 아님)
    var isPlaybackActive: Bool {
        switch playbackState {
        case .playing, .paused, .buffering: return true
        default: return false
        }
    }
}
