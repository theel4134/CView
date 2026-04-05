// MARK: - VLCPlayerEngine+Playback.swift
// CViewPlayer — 미디어 전환 + 초기 재생 모니터링

import Foundation
import CViewCore
@preconcurrency import VLCKitSPM

extension VLCPlayerEngine {
    
    /// [P0: 채널 전환 최적화] 미디어 URL만 교체하여 vout 재생성 없이 빠른 채널 전환.
    /// 기존 VLC 엔진/drawable을 유지하면서 미디어만 스왑하므로:
    /// - FIQCA 큐 재생성 없음 (기존 vout 유지)
    /// - 전환 시간 1~3초 → 0.3~0.5초로 단축
    /// - 프레임 드롭 최소화 (초기화 비용 제거)
    @MainActor
    public func switchMedia(to url: URL) async {
        guard !Task.isCancelled else { return }
        let profile = streamingProfile

        // 현재 재생 중이면 stop → 짧은 대기 → 새 미디어 설정
        player.stop()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms — 최소 flush
        guard !Task.isCancelled else { return }

        guard let media = VLCMedia(url: url) else {
            _setPhase(.error(.streamNotFound))
            return
        }

        applyMediaOptions(media, profile: profile)
        player.media = media
        player.play()
    }

    @MainActor
    func _startPlay(url: URL, profile: VLCStreamingProfile, retryAttempt: Int = 0) async {
        guard !Task.isCancelled else { return }

        // 기존 재생 중이면 안전하게 정리
        if player.isPlaying || player.media != nil {
            Log.player.debug("[DIAG] _startPlay: stopping existing playback — isPlaying=\(self.player.isPlaying) hasMedia=\(self.player.media != nil)")
            player.stop()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms — VLC flush 대기
            guard !Task.isCancelled else { return }
        }

        // drawable 설정
        player.drawable = playerView

        // 뷰가 윈도우에 붙을 때까지 대기 (최대 5초, 100회 × 0.05초)
        if playerView.window == nil {
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                if playerView.window != nil { break }
            }
            if playerView.window == nil {
                Log.player.warning("VLCPlayerEngine: 5초 대기 후에도 playerView.window == nil — play() 계속 진행")
            }
        }

        guard !Task.isCancelled else { return }

        guard let media = VLCMedia(url: url) else {
            _setPhase(.error(.streamNotFound))
            return
        }
        applyMediaOptions(media, profile: profile)

        player.media = media
        // [Opt-A1/A2] VLC 내부 타이밍 이벤트 빈도 감소 — 멀티라이브 CPU 절감
        // minimalTimePeriod: VLC 내부 타이머 최소 주기 (µs). 기본 500,000(0.5s)
        // timeChangeUpdateInterval: delegate 시간 변경 콜백 간격 (초). 기본 1.0s
        if profile == .multiLive {
            player.minimalTimePeriod = 1_000_000  // 1초 — 타이밍 이벤트 50% 감소
            if !isSelectedSession {
                player.timeChangeUpdateInterval = 5.0  // 비선택: 5초 간격 (80% 감소)
            } else {
                player.timeChangeUpdateInterval = 2.0  // 선택: 2초 간격
            }
        }
        player.play()
        Log.player.debug("[DIAG] player.play() called — state=\(self.player.state.rawValue) media=\(url.lastPathComponent, privacy: .public) retry=\(retryAttempt)")
        startStatsTimer()
        Log.player.debug("[DIAG] _startPlay: profile=\(String(describing: profile)) isSelected=\(self.isSelectedSession) window=\(self.playerView.window != nil ? "attached" : "NIL") playerState=\(self.player.state.rawValue) url=\(url.lastPathComponent, privacy: .public)")
        
        // [Fix 14] VLC 4.0 초기 재생 모니터링
        _startPlayRetryTask?.cancel()
        if retryAttempt < 1 {
            let capturedUrl = url
            let capturedProfile = profile
            let pid = String(url.lastPathComponent.prefix(8))
            _startPlayRetryTask = Task { [weak self] in
                // Phase 1: 5초 안정화 대기
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                
                let (initState, initSize, initDecoded) = await MainActor.run {
                    (self.player.state, self.player.videoSize, self.player.media?.statistics.decodedVideo ?? 0)
                }
                Log.player.debug("[FIX14] [\(pid, privacy: .public)] initial: state=\(initState.rawValue)(0=stop,1=stopping,2=open,3=buf,4=err,5=play,6=pause) vSz=\(Int(initSize.width))x\(Int(initSize.height)) decoded=\(initDecoded)")
                
                // 즉시 성공
                if initState == .playing && initSize.width > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 5초 내 재생 확인")
                    return
                }
                if initState == .buffering && initSize.width > 0 && initDecoded > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 5초 내 buffering이지만 디코딩 활성 (decoded=\(initDecoded)) — 정상")
                    return
                }
                
                // 명확한 실패: stopped/stopping/error → 1회 재시도
                if initState == .stopped || initState == .stopping || initState == .error {
                    Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 즉시 실패 (state=\(initState.rawValue)) — retry")
                    await MainActor.run { self.player.stop() }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                    return
                }
                
                // Phase 2: 장기 폴링 (최대 30초 추가)
                Log.player.info("[FIX14] [\(pid, privacy: .public)] 장기 대기 시작 (최대 30초)")
                var lastPolledDecoded: Int32 = await MainActor.run { self.player.media?.statistics.decodedVideo ?? 0 }
                for pollIdx in 0..<10 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    
                    let (state, size, decoded) = await MainActor.run {
                        (self.player.state, self.player.videoSize, self.player.media?.statistics.decodedVideo ?? 0)
                    }
                    let decodedDelta = decoded - lastPolledDecoded
                    lastPolledDecoded = decoded
                    Log.player.debug("[FIX14] [\(pid, privacy: .public)] poll=\(pollIdx)/10: state=\(state.rawValue) vSz=\(Int(size.width))x\(Int(size.height)) decoded=\(decoded) Δ=\(decodedDelta)")
                    
                    if state == .playing && size.width > 0 {
                        Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 폴링 중 재생 확인")
                        return
                    }
                    if state == .buffering && size.width > 0 && decodedDelta > 0 {
                        Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ buffering이지만 프레임 디코딩 중 (Δ=\(decodedDelta)) — 정상")
                        return
                    }
                    if state == .stopped || state == .stopping || state == .error {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 폴링 중 실패 (state=\(state.rawValue)) — retry")
                        await MainActor.run { self.player.stop() }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                    if state == .playing && size.width == 0 && pollIdx >= 3 {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ playing+noVideo 15s+ — retry")
                        await MainActor.run { self.player.stop() }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                    if state == .paused && pollIdx >= 3 {
                        Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ paused 15s+ — retry")
                        await MainActor.run { self.player.stop() }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        await self._startPlay(url: capturedUrl, profile: capturedProfile, retryAttempt: 1)
                        return
                    }
                }
                
                // 35초 경과 — 최종 확인
                guard !Task.isCancelled else { return }
                let (finalState, finalSize, finalDecoded) = await MainActor.run {
                    (self.player.state, self.player.videoSize, self.player.media?.statistics.decodedVideo ?? 0)
                }
                if finalState == .playing && finalSize.width > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 35초 후 재생 확인")
                    return
                }
                if finalState == .buffering && finalSize.width > 0 && finalDecoded > 0 {
                    Log.player.info("[FIX14] [\(pid, privacy: .public)] ✓ 35초 후 buffering이지만 디코딩 활성 (decoded=\(finalDecoded)) — 정상")
                    return
                }
                Log.player.warning("[FIX14] [\(pid, privacy: .public)] ✗ 35초 타임아웃 — 에러 전환 (state=\(finalState.rawValue) decoded=\(finalDecoded))")
                await MainActor.run { self._setPhase(.error(.networkTimeout)) }
            }
        }
    }
    
    // MARK: - 미디어 옵션 헬퍼
    
    /// VLCStreamingProfile에 따른 미디어 옵션 일괄 적용
    func applyMediaOptions(_ media: VLCMedia, profile: VLCStreamingProfile) {
        media.addOption(":network-caching=\(profile.networkCaching)")
        media.addOption(":live-caching=\(profile.liveCaching)")
        media.addOption(":file-caching=0")
        media.addOption(":disc-caching=0")
        media.addOption(":cr-average=\(profile.crAverage)")
        media.addOption(":avcodec-threads=\(profile.decoderThreads)")
        media.addOption(":avcodec-fast=1")
        media.addOption(":http-reconnect")
        let maxW = profile.adaptiveMaxWidth(isSelected: isSelectedSession)
        var maxH = profile.adaptiveMaxHeight(isSelected: isSelectedSession)
        // 대역폭 코디네이터의 화면 캡핑이 설정된 경우 더 제한적인 값 사용
        if maxAdaptiveHeight > 0 {
            maxH = min(maxH, maxAdaptiveHeight)
        }
        media.addOption(":adaptive-maxwidth=\(maxW)")
        media.addOption(":adaptive-maxheight=\(maxH)")
        // [Opt-A3] 멀티라이브 비선택 세션: predictive 알고리즘으로 대역폭 예측 기반 리버퍼링 감소
        // 선택 세션 및 단일 스트림: highest로 최고 화질 유지
        if profile == .multiLive && !isSelectedSession {
            media.addOption(":adaptive-logic=predictive")
        } else {
            media.addOption(":adaptive-logic=highest")
        }
        media.addOption(":deinterlace=0")
        media.addOption(":postproc-q=0")
        media.addOption(":clock-jitter=\(profile.clockJitter)")
        media.addOption(":clock-synchro=0")
        media.addOption(":codec=videotoolbox,avcodec")
        media.addOption(":avcodec-hw=videotoolbox")
        media.addOption(":http-referrer=\(CommonHeaders.chzzkReferer)")
        media.addOption(":http-user-agent=\(CommonHeaders.safariUserAgent)")
        if profile.dropLateFrames { media.addOption(":drop-late-frames=1") }
        if profile.skipFrames { media.addOption(":skip-frames=1") }
        media.addOption(":avcodec-hurry-up=1")
        if profile == .multiLive {
            media.addOption(":prefetch-buffer-size=786432")
        } else {
            media.addOption(":prefetch-buffer-size=393216")
        }
        // [Opt-A4] 루프필터 스킵 — VideoToolbox 활성 시 GPU 처리되어 무시되지만
        // SW 폴백 시 CPU 5~15% 절감 보험. multiLive: 전체 스킵, 그 외: Non-ref만.
        if profile == .multiLive {
            media.addOption(":avcodec-skiploopfilter=4")  // All
        } else {
            media.addOption(":avcodec-skiploopfilter=1")  // Non-ref only
        }
        if profile == .multiLive {
            media.addOption(":avcodec-skip-idct=4")
        }
        // [Opt-A5] 멀티라이브 비선택: B프레임 디코딩 스킵 — 시각적 끊김 미미(480p)
        // VLC 레벨 프레임 스킵은 VideoToolbox에도 일부 효과 (프레임 미전달)
        if profile == .multiLive && !isSelectedSession {
            media.addOption(":avcodec-skip-frame=1")  // B-frames skip
        }
    }
}
