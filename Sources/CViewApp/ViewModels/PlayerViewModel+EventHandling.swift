// MARK: - PlayerViewModel+EventHandling.swift
// CViewApp — PlayerViewModel 이벤트 처리 + 내부 타이머

import Foundation
import CViewCore
import CViewPlayer

extension PlayerViewModel {

    // MARK: - Private Timers

    func startUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))  // 5→10초: uptime 표시 갱신 빈도 최적화
                guard !Task.isCancelled, let self else { break }
                if let coord = self.streamCoordinator {
                    self.uptime = await coord.uptime
                }
            }
        }
    }

    func startEventListening(_ coordinator: StreamCoordinator) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            let events = await coordinator.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                self?.handleStreamEvent(event)
            }
        }
    }

    // MARK: - Stream Event Handler

    @MainActor
    func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .phaseChanged(let phase):
            // [버퍼링 디바운스 통합] StreamCoordinator에서 오는 .buffering phase도
            // VLC 디바운스와 동일하게 처리해야 한다.
            // 그렇지 않으면 VLC 디바운스를 우회하여 즉시 streamPhase = .buffering이 되어
            // 정상 재생 중에도 버퍼링 스피너가 계속 표시된다.
            if phase == .buffering && streamPhase == .playing {
                // 이미 재생 중이면 디바운스 적용 (VLC _handleVLCPhase와 동일 로직)
                // [Fix 16h-opt3] 안티플리커: 5→3초, 디바운스: 3→2초
                if let lastPlaying = _lastPlayingTime,
                   Date().timeIntervalSince(lastPlaying) < 3.0 {
                    // 쿨다운 중 — 무시
                } else if _bufferingDebounceTask == nil {
                    _bufferingDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // [Fix 16h-opt3] 3→2초
                        guard !Task.isCancelled, let self else { return }
                        self.streamPhase = .buffering
                        self._bufferingDebounceTask = nil
                    }
                }
            } else if phase == .playing {
                // playing 전환 시 디바운스 취소 + 즉시 반영
                _bufferingDebounceTask?.cancel()
                _bufferingDebounceTask = nil
                _lastPlayingTime = Date()
                streamPhase = phase
            } else {
                streamPhase = phase
            }
            if case .error(let msg) = phase { errorMessage = msg }
            onPlaybackStateChanged?()

        case .qualitySelected(let q):
            currentQuality = q
            Task {
                if let coord = streamCoordinator {
                    self.availableQualities = await coord.availableQualities
                }
            }

        case .qualityChanged(let q):
            currentQuality = q

        case .abrDecision:
            break

        case .latencyUpdate(let info):
            latencyInfo = info
            if latencyHistory.isEmpty || latencyHistory.count % 10 == 0 {
                let point = LatencyDataPoint(timestamp: Date(), latency: info.current)
                latencyHistory.append(point)
                if latencyHistory.count > Self.maxLatencyHistory { latencyHistory.removeFirst() }
            }

        case .bufferUpdate(let health):
            bufferHealth = health

        case .error(let msg):
            errorMessage = msg

        case .streamEnded:
            _bufferingDebounceTask?.cancel()
            _bufferingDebounceTask = nil
            streamPhase = .streamEnded

        case .stopped:
            streamPhase = .idle
        }
    }

    // MARK: - VLC 상태 변경 처리

    /// VLC 상태 변경 처리
    @MainActor
    func _handleVLCPhase(_ phase: PlayerState.Phase, coordinator: StreamCoordinator?) {
        // StreamCoordinator 상태 전달 — fire-and-forget Task
        // 주의: coordinator task를 cancel하면 handleVLCEngineState 내부의
        // 재연결/워치독/품질 선택 로직이 중단되어 기능 장애 발생.
        // coordinator actor 큐는 순차 실행되므로 자연스럽게 직렬화됨.
        if let coord = coordinator {
            Task { await coord.handleVLCEngineState(phase) }
        }

        switch phase {
        case .error:
            logger.warning("VLC → ERROR: StreamCoordinator 재연결 트리거")
            if let coord = coordinator {
                Task { await coord.triggerReconnect(reason: "VLC error state") }
            }
        case .ended:
            logger.warning("VLC → ENDED: 라이브 스트림 재연결")
            if let coord = coordinator {
                Task { await coord.triggerReconnect(reason: "VLC ended (live stream)") }
            }
        case .playing:
            // 버퍼링 디바운스 취소 — VLC가 playing으로 돌아오면 즉시 반영
            _bufferingDebounceTask?.cancel()
            _bufferingDebounceTask = nil
            _lastPlayingTime = Date()
            streamPhase = .playing
            errorMessage = nil
            onPlaybackStateChanged?()
            // 재생 시작 시 고급 설정 적용 (설정이 기본값이 아닐 경우만)
            _applyVLCAdvancedSettingsIfNeeded()
            // VLC → playing 전환 시 drawable 재바인딩: vout이 올바른 레이어에서 렌더링되도록 보장
            // 멀티라이브에서 여러 세션이 동시 시작될 때 SwiftUI 뷰 마운트 타이밍으로
            // drawable이 올바르게 설정되지 않는 경우를 대비
            // [Freeze Fix] 이전 refreshDrawable Task 취소 — 중복 대기 해소
            if let vlcEngine = playerEngine as? VLCPlayerEngine {
                _refreshDrawableTask?.cancel()
                _refreshDrawableTask = Task { @MainActor [weak self, weak vlcEngine] in
                    // 200ms 후 drawable 재바인딩 — VLC vout 초기화 완료 대기
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    vlcEngine?.refreshDrawable()
                    self?._refreshDrawableTask = nil
                }
            }
        case .buffering:
            // [VLC 버퍼링 디바운스] VLC는 라이브 HLS 중 네트워크 버퍼를 채울 때
            // 수시로 .buffering 상태를 보고한다 (수백ms 이내 .playing으로 복귀).
            // 이 순간적인 버퍼링마다 UI 스피너를 표시하면 영상이 정상 재생되는데도
            // 스피너가 계속 깜빡이거나 고착되어 보인다.
            //
            // 해결 1: 이미 재생 중(.playing)이었으면 3초 디바운스 적용.
            //         3초 이상 버퍼링이 지속될 때만 streamPhase를 .buffering으로 전환.
            // 해결 2: 안티플리커 쿨다운 — 재생 시작 후 5초 이내 버퍼링은 무시.
            //         VLC가 재생 초반에 버퍼를 정리하는 과정에서 발생하는 순간 버퍼링 방지.
            if streamPhase == .playing {
                // 안티플리커: 재생 시작 후 3초 이내면 버퍼링 전환 억제
                if let lastPlaying = _lastPlayingTime,
                   Date().timeIntervalSince(lastPlaying) < 3.0 {
                    break
                }
                if _bufferingDebounceTask == nil {
                    _bufferingDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // [Fix 16h-opt3] 3→2초
                        guard !Task.isCancelled, let self else { return }
                        self.streamPhase = .buffering
                        self._bufferingDebounceTask = nil
                    }
                }
            } else {
                // 아직 재생 전이면 (connecting, idle 등) 즉시 반영
                if streamPhase != .buffering { streamPhase = .buffering }
            }
        case .paused:
            streamPhase = .paused
        case .loading:
            streamPhase = .connecting
        case .idle:
            break
        }
    }

    /// 재생 시작 시 VLC 고급 설정 적용 (기본값이 아닌 항목만)
    func _applyVLCAdvancedSettingsIfNeeded() {
        guard let vlc = playerEngine as? VLCPlayerEngine else { return }
        let hasEq = isEqualizerEnabled && !equalizerPresetName.isEmpty
        let hasVideoAdj = isVideoAdjustEnabled
        let hasAspect = aspectRatio != nil
        let hasAudio = audioStereoMode != 0 || audioMixMode != 0 || audioDelay != 0
        guard hasEq || hasVideoAdj || hasAspect || hasAudio else { return }

        if hasEq {
            vlc.setEqualizerPresetByName(equalizerPresetName)
            vlc.setEqualizerPreAmp(equalizerPreAmp)
            for (i, val) in equalizerBands.enumerated() { vlc.setEqualizerBand(index: i, value: val) }
        }
        if hasVideoAdj {
            vlc.setVideoAdjustEnabled(true)
            vlc.setVideoBrightness(videoBrightness); vlc.setVideoContrast(videoContrast)
            vlc.setVideoSaturation(videoSaturation); vlc.setVideoHue(videoHue); vlc.setVideoGamma(videoGamma)
        }
        if hasAspect { vlc.setAspectRatio(aspectRatio) }
        if audioStereoMode != 0 { vlc.setAudioStereoMode(audioStereoMode) }
        if audioMixMode != 0 { vlc.setAudioMixMode(audioMixMode) }
        if audioDelay != 0 { vlc.setAudioDelay(audioDelay) }
    }
}
