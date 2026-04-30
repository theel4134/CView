// StreamCoordinator+Reconnection.swift
// CView_v2 — Reconnection & Playback Watchdog

import Foundation
import CViewCore

// MARK: - Reconnection

extension StreamCoordinator {

    /// 엔진 특성에 맞춰 재연결 기준 URL을 선택합니다.
    /// - VLC: 이미 선택된 variant URL 유지 (수동 화질/ABR 상태 보존)
    /// - AVPlayer/HLS.js: master URL에서 다시 시작해 최신 토큰/매니페스트를 재해석
    func preferredReconnectBaseURL(rawURL: URL, currentVariantURL: URL?, keepCurrentVariant: Bool) -> URL {
        if keepCurrentVariant {
            return currentVariantURL ?? rawURL
        }
        return rawURL
    }

    /// 재연결 트리거 — 현재 URL로 재시도
    /// - Parameter reason: 로그용 재연결 원인
    public func triggerReconnect(reason: String = "") {
        guard let rawURL = _streamURL else {
            logger.warning("StreamCoordinator: 재연결 실패 — 저장된 URL 없음")
            return
        }
        // 이미 재연결 중이면 무시
        guard _phase != .reconnecting else { return }
        
        // 이중 트리거 방지: 최근 재연결로부터 cooldown 이내면 무시
        let now = Date()
        if now.timeIntervalSince(_lastReconnectTime) < _reconnectCooldown {
            logger.info("StreamCoordinator: 재연결 쿨다운 중 — 무시 (\(reason))")
            return
        }
        _lastReconnectTime = now
        
        updatePhase(.reconnecting)
        logger.info("StreamCoordinator: 재연결 시작 (\(reason))")

        Task { [weak self] in
            guard let self else { return }

            // 방송 종료 여부 API 확인 — 종료된 방송에 재연결하지 않도록
            if let checkEnded = await self.onCheckStreamEnded, await checkEnded() {
                await self.handleStreamEnded()
                return
            }

            // 재연결 전: PDT 폴링·로우레이턴시 PID를 중지하여 stale 데이터 오염 방지
            await self.stopLatencySubsystems()

            // 프록시 세션 리셋 — stale 연결 풀 정리
            if await self._isProxyActive {
                self.streamProxy.resetSession()
            }

            // [H4 fix] 재연결 전 초기 매니페스트 갱신
            await self.refreshMasterManifest()

            await self.reconnectionHandler.startReconnecting(
                onAttempt: { [weak self] attempt, delay in
                    guard let self else { return }
                    await self.logger.info("StreamCoordinator: 재시도 \(attempt) — \(String(format: "%.1f", delay))초 대기")
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    // 재시도 전 방송 종료 여부 재확인
                    if let checkEnded = await self.onCheckStreamEnded, await checkEnded() {
                        await self.handleStreamEnded()
                        return
                    }
                    // [H4 fix] 매 시도마다 매니페스트 재갱신 → 최신 CDN 토큰 URL 사용
                    if attempt > 1 {
                        await self.refreshMasterManifest()
                    }
                    let currentVariantURL = await self._currentVariantURL
                    let keepCurrentVariant = await (self.playerEngine is VLCPlayerEngine)
                    let reconnectBase = await self.preferredReconnectBaseURL(
                        rawURL: rawURL,
                        currentVariantURL: currentVariantURL,
                        keepCurrentVariant: keepCurrentVariant
                    )
                    let isProxyActive = await self._isProxyActive
                    let url = isProxyActive ? self.streamProxy.proxyURL(from: reconnectBase) : reconnectBase
                    await self.performReconnectAttempt(url: url)
                },
                onExhausted: { [weak self] in
                    await self?.handleReconnectExhausted()
                }
            )
        }
    }

    /// 단일 재연결 시도 — play()를 재호출하여 스트림 재시작
    func performReconnectAttempt(url: URL) async {
        guard let engine = playerEngine else { return }
        engine.stop()
        do {
            try await engine.play(url: url)
            await reconnectionHandler.handleSuccess()
            updatePhase(.playing)
            logger.info("StreamCoordinator: 재연결 성공")
            
            // 재연결 후 Watchdog 상태 리셋 — stale 값으로 즉시 재감지되는 것 방지
            _lastWatchdogTime = -1
            _lastWatchdogDecodedFrames = -1
            _stallCount = 0
            _playbackStartTime = Date()  // grace period 기준점 갱신 — 재시작 직후 stall 오탐 방지
            
            // 재연결 성공 후 PDT·로우레이턴시 동기화 재시작 (갱신된 URL 사용)
            if config.enableLowLatency {
                await startLowLatencySync()
            } else if playerEngine is VLCPlayerEngine {
                await startPDTMonitoring()
            }
        } catch {
            logger.warning("StreamCoordinator: 재연결 시도 실패 — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 재연결 시도 모두 소진
    func handleReconnectExhausted() {
        updatePhase(.error("재연결 최대 횟수 초과"))
        emitEvent(.error("재연결 최대 횟수 초과"))
        logger.error("StreamCoordinator: 재연결 소진")
    }
    
    /// 방송 종료 감지 — 플레이어 정지 및 streamEnded 이벤트 방출
    func handleStreamEnded() async {
        await reconnectionHandler.cancel()
        playerEngine?.stop()
        updatePhase(.streamEnded)
        emitEvent(.streamEnded)
        logger.info("StreamCoordinator: 방송 종료 감지 — 재연결 중단")
    }
    
    /// PDT 폴링·로우레이턴시 PID를 중지 — 재연결 전 stale 데이터 오염 방지
    func stopLatencySubsystems() async {
        await lowLatencyController?.stopSync()
        await pdtProvider?.stop()
        pdtProvider = nil
    }
}

// MARK: - Playback Watchdog

extension StreamCoordinator {

    /// 3초마다 `currentTime`을 확인하여 재생이 멈췄는지 감시합니다.
    /// 6초(2연속 체크) 동안 시간이 진행되지 않으면 자동 재연결을 시도합니다.
    func startPlaybackWatchdog() {
        _watchdogTask?.cancel()
        _stallCount = 0
        _lastWatchdogTime = -1
        _lastWatchdogDecodedFrames = -1
        
        _watchdogTask = Task { [weak self] in
            // onStateChange .playing 이후 시작되므로 짧은 안정화 대기면 충분
            try? await Task.sleep(for: .seconds(2))
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { break }
                
                let phase = await self._phase
                guard phase == .playing else {
                    await self.resetStallCounter()
                    continue
                }
                
                guard let engine = await self.playerEngine else { continue }
                let currentTime = engine.currentTime
                let lastTime = await self._lastWatchdogTime
                
                // 보조 감지: VLC 디코딩 프레임 수 확인
                let currentDecoded: Int32
                let lastDecoded: Int32
                if let vlcEngine = engine as? VLCPlayerEngine {
                    currentDecoded = vlcEngine.decodedVideoFrames
                    lastDecoded = await self._lastWatchdogDecodedFrames
                } else {
                    currentDecoded = -1
                    lastDecoded = -1
                }
                
                // currentTime 정체 감지
                let timeStalled = lastTime >= 0 && abs(currentTime - lastTime) < 0.1
                // 디코딩 프레임 정체 감지: 3초간 새 프레임이 2개 미만이면 실질적 정체
                // (VLC http-reconnect가 간헐적으로 1프레임만 디코딩하는 경우 잡아냄)
                let framesStalled = lastDecoded >= 0 && currentDecoded >= 0 && (currentDecoded - lastDecoded) < 2
                
                // [Fix 17b] Watchdog 정젠 로직: time AND frames 모두 정체해야 재연결
                // VLC가 buffering 상태로 currentTime을 업데이트하지 않지만
                // 실제로는 프레임을 디코딩/표시 중인 경우 재연결 방지
                if timeStalled && (lastDecoded < 0 || framesStalled) {
                    let count = await self.incrementStallCount()
                    let threshold = await self._stallThreshold
                    if count >= threshold {
                        // [Fix 15] Grace period: 초기 재생 후 40초간 watchdog 재연결 차단
                        // FIX14가 35초간 VLC 상태를 감시하므로 중복 재시작 방지
                        let playbackStart = await self._playbackStartTime
                        let gracePeriod = await self._watchdogGracePeriod
                        let elapsed = Date().timeIntervalSince(playbackStart)
                        if elapsed < gracePeriod {
                            await self.logger.info("Watchdog: grace period 중 (\(Int(elapsed))s/\(Int(gracePeriod))s) — 재연결 보류")
                            await self.resetStallCounter()
                            continue
                        }
                        // [Fix 15] 프레임이 한 번도 디코딩되지 않은 상태(decodedFrames==0)에서
                        // stall 감지는 무의미 — VLC가 아직 디코더를 생성하지 못한 것
                        if currentDecoded == 0 {
                            await self.logger.info("Watchdog: decodedFrames=0 — 디코더 미생성, 재연결 보류")
                            await self.resetStallCounter()
                            continue
                        }
                        let stallReason = timeStalled ? "currentTime 정체" : "디코딩 프레임 정체 (\(currentDecoded - lastDecoded)f/3s)"
                        await self.logger.warning("Watchdog: \(count * 3)초간 \(stallReason) 감지 — 재연결 시도")
                        await self.resetStallCounter()
                        await self.triggerReconnect(reason: "watchdog: \(stallReason)")
                        try? await Task.sleep(for: .seconds(6))
                    }
                } else {
                    await self.resetStallCounter()
                }
                
                await self.setLastWatchdogTime(currentTime)
                await self.setLastWatchdogDecodedFrames(currentDecoded)
            }
        }
    }
    
    func resetStallCounter() {
        _stallCount = 0
    }
    
    func incrementStallCount() -> Int {
        _stallCount += 1
        return _stallCount
    }
    
    func setLastWatchdogTime(_ time: TimeInterval) {
        _lastWatchdogTime = time
    }
    
    func setLastWatchdogDecodedFrames(_ count: Int32) {
        _lastWatchdogDecodedFrames = count
    }
}
