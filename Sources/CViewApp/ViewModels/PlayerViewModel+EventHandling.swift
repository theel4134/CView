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
                } else {
                    // [Fix] 항상 기존 Task cancel 후 재할당 — 비원자적 nil 체크 race 제거
                    _bufferingDebounceTask?.cancel()
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
            let wasAlreadyPlaying = (_lastPlayingTime != nil)
            _lastPlayingTime = Date()
            streamPhase = .playing
            errorMessage = nil
            onPlaybackStateChanged?()
            // 재생 시작 시 고급 설정 적용 (설정이 기본값이 아닐 경우만)
            _applyVLCAdvancedSettingsIfNeeded()
            // [플리커 방지] 초기 재생 시작(idle/loading → playing)에서만 drawable 재바인딩.
            // buffering → playing 복귀 시에는 이미 vout이 올바르게 바인딩되어 있으므로
            // drawable 리셋을 생략하여 불필요한 검은 프레임 발생을 방지한다.
            // (멀티라이브 4세션에서 각 세션이 수십초 간격으로 리버퍼링하면
            //  매번 drawable 리셋 → 검은 프레임 → 눈에 보이는 플리커링)
            if !wasAlreadyPlaying, let vlcEngine = playerEngine as? VLCPlayerEngine {
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
                // [Fix] 항상 기존 Task cancel 후 재할당 — 비원자적 nil 체크 race 제거
                _bufferingDebounceTask?.cancel()
                _bufferingDebounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // [Fix 16h-opt3] 3→2초
                    guard !Task.isCancelled, let self else { return }
                    self.streamPhase = .buffering
                    self._bufferingDebounceTask = nil
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

    // MARK: - VLC → AVPlayer 자동 폴백 (No-Proxy 모드)

    /// VLC 가 chzzk CDN 응답을 처리하지 못해 FIX14 35초 타임아웃이 발생했을 때 호출.
    /// 단일 라이브 한정: preferredEngineType 을 AVPlayer 로 전환하고, 외부에 재시작을 요청한다.
    ///
    /// [Multi-live 보호 2026-04-24]
    /// 멀티라이브 컨텍스트(`isMultiLive == true`)에서는 자동 엔진 전환을 비활성화한다.
    ///   - 한 셀의 엔진이 갑자기 바뀌면 다른 셀과 코덱/오디오/HUD 동작이 어긋나고
    ///     화면이 강하게 깜빡여 사용자 경험이 악화된다.
    ///   - `preferredEngineType` 영구화는 사용자가 명시한 엔진 선호와 정면충돌
    ///     (다음에 같은 채널을 재추가해도 AVPlayer 로 시작됨).
    ///   - 일시적 버퍼링/지연을 "엔진 결함"으로 단정하기 어렵다 — 네트워크 변동이 더 흔함.
    ///
    /// 멀티라이브에서는 `.error` 로 보정하여 `MultiLivePlayerPane` 의 "재시도" 오버레이가
    /// 노출되도록 한다. 사용자가 직접 재시도하면 동일 VLC 엔진으로 새로 시작.
    @MainActor
    func _handleVLCFallback(reason: String) async {
        guard preferredEngineType == .vlc else { return }

        if isMultiLive {
            logger.warning("PlayerViewModel: 멀티라이브 — VLC → AVPlayer 자동 폴백 차단. reason=\(reason)")
            errorMessage = "스트림 연결이 지연되고 있습니다. 다시 시도해 주세요."
            streamPhase = .error("연결 지연")
            return
        }

        logger.warning("PlayerViewModel: VLC → AVPlayer 폴백 트리거 — \(reason)")

        // 화면에 에러를 띄우지 않도록 정리 (전환 직후 오버레이 방지)
        errorMessage = nil
        // 전환 의사를 영구화 — 재시작 시 AVPlayer 로 생성되도록
        preferredEngineType = .avPlayer

        // 외부 컨테이너(LiveStreamView) 가 실제 재시작을 담당
        if let cb = onEngineFallbackRequested {
            cb(reason)
        } else {
            logger.warning("PlayerViewModel: onEngineFallbackRequested 미설정 — 자동 폴백 불가")
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
