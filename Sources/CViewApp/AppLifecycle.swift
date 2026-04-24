// MARK: - AppLifecycle.swift
// AppState extension - App lifecycle observers and background updates

import AppKit
import CViewCore
import CViewNetworking
import CViewPersistence
import CViewPlayer

// MARK: - Session Expiry

extension AppState {

    /// 서버 401 응답(세션 만료) 알림 구독 — initialize()에서 한 번 호출
    func observeSessionExpiry() {
        sessionExpiryObserver = NotificationCenter.default.addObserver(
            forName: .chzzkSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoggedIn else { return }
                self.logger.warning("Session expired (server 401) — forcing logout")
                await self.handleLogout()
                self.sessionExpiredAlert = true
            }
        }
    }
}

// MARK: - App Lifecycle Optimization

extension AppState {

    /// 앱 활성/비활성 NSNotification 옵저버 등록
    func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        // [Power-Aware] 전원 소스 모니터 강제 초기화 —
        // shared 접근 시점에 IOPSNotificationCreateRunLoopSource 가 메인 RunLoop에 부착됨.
        // AC⇔Battery 전환 시 cviewPowerSourceChanged 노티피케이션 발화.
        _ = PowerSourceMonitor.shared
        powerSourceObserver = nc.addObserver(
            forName: .cviewPowerSourceChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let src = PowerSourceMonitor.shared.current.rawValue
                let pref = PowerSourceMonitor.shared.prefersHighPerformance ? "P-core" : "E-core"
                self.logger.info("PowerSource changed: \(src) → prefer \(pref)")
            }
        }
        appActiveObserver = nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppBecameActive() }
        }

        appResignObserver = nc.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppResignedActive() }
        }

        // 창 최소화 복원 시 VLC drawable 재설정 (vout 컨텍스트 유효성 보장)
        deminiaturizeObserver = nc.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowRestored()
            }
        }

        // [백그라운드 1080p 유지] 창 가림 상태 변경 — 다른 앱이 CView 창을 가리거나 다시 노출될 때
        // AVPlayer 내부 ABR 이 저화질에 갇히지 않도록 즉시 화질 ceiling을 재확인한다.
        windowOcclusionObserver = nc.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowOcclusionChanged()
            }
        }

        // [Phase E] Low Power Mode 변경 — 비선택 세션 contentsScale 즉시 재적용 (0.75↔0.625)
        lowPowerModeObserver = nc.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playerViewModel?.engine_setGPURenderTier_active()
                self.multiLiveManager.restoreGPURenderTiersFromSelection()
            }
        }

        // [Phase F] Thermal State 변경 — serious/critical 시 비선택 세션 GPU 렌더 티어 자동 강등
        // ProcessInfo.thermalStateDidChangeNotification은 OS가 자동 발화 — 비용 0
        thermalStateObserver = nc.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleThermalStateChanged()
            }
        }

        // 앱 종료 시 멀티라이브 세션 상태 제거 — 재시작 시 빈 메인 화면으로 시작
        terminateObserver = nc.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.multiLiveManager.isTerminating = true
            MultiLivePersistedState.clear()

            // [\ud504\ub85c\uc138\uc2a4 \uaca9\ub9ac] \ub54c\uc5b0\ub85c launch \ub41c \uc790\uc2dd \uc778\uc2a4\ud134\uc2a4\ub4e4 \uc885\ub8cc
            self?.multiLiveLauncher.terminateAll()

            // 멀티채팅 초기화 플래그 — DataStore는 actor라 동기 저장 불가하므로
            // UserDefaults 플래그만 설정하고 다음 실행 시 load()에서 처리
            UserDefaults.standard.set(true, forKey: "multiChatShouldClear")

            // NotificationCenter observer 명시적 해제
            self?.removeAllObservers()
        }

        // [Live Settings] 스트림 보정 모드 변경 — 활성 멀티라이브 세션을 즉시 재시작
        // (메인 단일 LiveStreamView는 자체 .onReceive로 직접 처리)
        streamProxyModeObserver = nc.addObserver(
            forName: .cviewStreamProxyModeChanged,
            object: nil, queue: .main
        ) { [weak self] note in
            // Notification 은 non-Sendable — userInfo 의 모드 값만 미리 추출해 캡처
            let modeName = (note.userInfo?["mode"] as? StreamProxyMode)?.displayName ?? "?"
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.info("StreamProxyMode changed → restart active streams (mode=\(modeName))")
                await self.restartMultiLiveSessionsForProxyChange()
            }
        }
    }

    /// 모든 NotificationCenter observer 해제
    /// [Code Review 2026-04-24] 개별 올범이터를 배열로 나열하는 방식은 새 올범이터 추가 시 누락 위험 →
        ///   등록 시점에 lifecycleObservers 배열에 누적하는 패턴으로 일원화 권장 (추후 리팩터링 대상).
    private func removeAllObservers() {
        let nc = NotificationCenter.default
        [appActiveObserver, appResignObserver, sessionExpiryObserver,
         deminiaturizeObserver, terminateObserver, streamProxyModeObserver,
         powerSourceObserver, windowOcclusionObserver,
         lowPowerModeObserver, thermalStateObserver].compactMap { $0 }.forEach {
            nc.removeObserver($0)
        }
        appActiveObserver = nil
        appResignObserver = nil
        sessionExpiryObserver = nil
        deminiaturizeObserver = nil
        terminateObserver = nil
        streamProxyModeObserver = nil
        powerSourceObserver = nil
        windowOcclusionObserver = nil
        lowPowerModeObserver = nil
        thermalStateObserver = nil
    }

    /// 스트림 보정 모드 변경 시 활성 멀티라이브 세션을 모두 재시작
    /// — `MultiLiveSession.refreshStream` 은 stop + start 로 새 `Configuration` 생성
    func restartMultiLiveSessionsForProxyChange() async {
        guard let api = apiClient else { return }
        // 현재 재생/로딩 상태인 세션만 재시작 (idle/offline/error 세션은 다음 시작 시 자동 반영됨)
        let targets = multiLiveManager.sessions.filter { session in
            switch session.loadState {
            case .playing, .loading: return true
            default: return false
            }
        }
        guard !targets.isEmpty else { return }
        logger.info("Restarting \(targets.count) multi-live session(s) for new StreamProxyMode")
        // [Code Review 2026-04-24] 순차 재시작 → TaskGroup 병렬화 —
        //   각 refreshStream 은 네트워크 요청(2~5초)을 포함하므로
        //   N세션 × 5초 = 최대 N×5초 순차 대기 문제 해소.
        //   refreshStream 은 세션 개별 stop+start 로 세션 간 공유 자원 없음 → 병렬 안전.
        await withTaskGroup(of: Void.self) { group in
            for session in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await session.refreshStream(using: api, appState: self)
                }
            }
        }
    }

    /// 앱 포커스 복귀 — 폴링 주기를 정상(30s)으로 복구 & 즉시 1회 갱신
    /// 백그라운드에서 재생이 멈춘 경우 자동 복구를 시도한다.
    func handleAppBecameActive() {
        guard !isAppActive else { return }
        isAppActive = true
        // [Tune] 장기 idle WS suspend 예약 취소 + WS 재연결
        longIdleSuspendTask?.cancel(); longIdleSuspendTask = nil
        homeViewModel?.resumeMetricsAfterIdle()
        homeViewModel?.resumeMetricsPolling()

        // 백그라운드 체류 시간 계산
        let backgroundDuration: TimeInterval
        if let entry = _backgroundEntryTime {
            backgroundDuration = Date().timeIntervalSince(entry)
            _backgroundEntryTime = nil
        } else {
            backgroundDuration = 0
        }

        // 5초 이상 백그라운드에 있었으면 재생 복구 시도
        if backgroundDuration > 5 {
            // 메인 플레이어 복구
            playerViewModel?.recoverFromBackground()

            // 멀티라이브 세션 복구
            for session in multiLiveManager.sessions {
                session.playerViewModel.recoverFromBackground()
            }
            logger.info("App became active — stream recovery triggered (background \(String(format: "%.0f", backgroundDuration))s)")
        } else {
            logger.info("App became active – resumed metrics polling")
        }

        // [백그라운드 1080p 유지] 백그라운드 체류 시간과 무관하게 포그라운드 복귀 즉시
        // AVPlayer ABR 을 nudge 해 720p 이하에 고정된 경우 1080p 로 재평가 유도.
        // (recoverFromBackground 은 5s+ 에만 실행되므로 짧은 백그라운드 복귀에도 커버)
        reassertPlaybackQuality(reason: "app-became-active")
    }

    /// 앱 포커스 이탈 — 메트릭 폴링 주기 느리게 (2분)
    /// 백그라운드 재생 설정이 켜져 있으면 스트림을 중단하지 않고 App Nap을 방지한다.
    func handleAppResignedActive() {
        guard isAppActive else { return }
        isAppActive = false
        _backgroundEntryTime = Date()
        homeViewModel?.pauseMetricsPolling()

        // [Tune] 5분 이상 비활성 지속 시 메트릭 WebSocket 완전 단절
        // — 세션 keep-alive 트래픽 및 부수적 재연결 대기 제거
        longIdleSuspendTask?.cancel()
        longIdleSuspendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard let self, !Task.isCancelled, !self.isAppActive else { return }
            await MainActor.run { self.homeViewModel?.suspendMetricsForLongIdle() }
        }

        // 백그라운드 재생 유지: 활성 스트림이 있으면 App Nap 방지 activity 시작
        if settingsStore.player.continuePlaybackInBackground {
            let hasActiveStream = isAnyStreamPlaying()
            if hasActiveStream {
                beginPlaybackActivity()
            }
            // [백그라운드 1080p 유지] 백그라운드 진입 직전 화질 ceiling 재확인.
            // AVPlayer item 의 preferredPeakBitRate/preferredMaximumResolution 를 다시 써서
            // 시스템이 백그라운드 스로틀링을 시작해도 ABR 이 1080p60/8Mbps 상한을 유지하도록 한다.
            reassertPlaybackQuality(reason: "app-resigned-active")
        }

        logger.info("App resigned active – throttled metrics polling, background playback: \(self.settingsStore.player.continuePlaybackInBackground)")
    }

    // MARK: - App Nap Prevention

    /// 활성 스트림이 재생 중인지 확인
    func isAnyStreamPlaying() -> Bool {
        if let phase = playerViewModel?.streamPhase,
           case .playing = phase {
            return true
        }
        // 멀티라이브 세션 확인
        if multiLiveManager.hasActiveStreams() {
            return true
        }
        return false
    }

    /// App Nap 방지 activity 시작 — 재생 중 시스템 절전/스로틀링 차단
    /// macOS는 비활성 앱에 App Nap을 적용하여 CPU/네트워크를 제한할 수 있다.
    /// 이를 방지해야 백그라운드에서도 라이브 스트림이 끊김 없이 재생된다.
    func beginPlaybackActivity() {
        guard playbackActivity == nil else { return }
        playbackActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Live stream background playback"
        )
        logger.info("App Nap prevention started — live stream playing in background")
    }

    /// App Nap 방지 activity 종료
    func endPlaybackActivity() {
        guard let activity = playbackActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        playbackActivity = nil
        logger.info("App Nap prevention ended")
    }

    /// 재생 상태 변경 시 App Nap 방지를 동적으로 관리
    /// PlayerViewModel에서 재생 시작/종료 시 호출
    func updatePlaybackActivity() {
        let shouldPrevent = settingsStore.player.continuePlaybackInBackground && isAnyStreamPlaying()
        if shouldPrevent {
            beginPlaybackActivity()
        } else {
            endPlaybackActivity()
        }
    }

    /// 창 최소화에서 복원 시 플레이어 렌더링 상태를 복구
    /// VLC 렌더링 서피스는 창 최소화 중 무효화될 수 있다.
    /// AVPlayer는 최소화 중 macOS에 의해 일시정지될 수 있다.
    func handleWindowRestored() {
        if let vlcEngine = playerViewModel?.mediaPlayer,
           case .playing = playerViewModel?.streamPhase {
            vlcEngine.refreshDrawable()
            logger.info("Window restored — VLC drawable refreshed")
        }
        // 멀티라이브 세션 복구 (AVPlayer 기반)
        for session in multiLiveManager.sessions {
            if let vlcEngine = session.playerViewModel.mediaPlayer {
                vlcEngine.refreshDrawable()
            }
            // AVPlayer 세션: 최소화 중 일시정지된 경우 재개
            session.playerViewModel.recoverFromBackground()
        }
        // [백그라운드 1080p 유지] 최소화 해제 후 AVPlayer ABR 재평가 유도
        reassertPlaybackQuality(reason: "window-restored")
    }

    /// [백그라운드 1080p 유지 + Phase D GPU 절감] 창 가림 상태 변경 핸들러.
    ///   1) ABR ceiling 재확인 (가림 해제 시 저화질 고착 방지)
    ///   2) **새로 추가**: 모든 윈도우가 완전히 가려졌을 때 비디오 레이어를 `.hidden`
    ///      티어로 강등하여 Metal 합성 부하를 0에 가깝게 만든다. 디코딩/오디오는 유지.
    ///      가림이 해제되면 선택 상태에 맞춰 `.active`/`.visible` 로 복원.
    func handleWindowOcclusionChanged() {
        // 활성 스트림이 없으면 스킵 (불필요한 nudge 방지)
        guard isAnyStreamPlaying() else { return }

        // 모든 NSApp 윈도우가 비가시(완전 가림 / 다른 Space)인지 판정.
        // `NSWindow.occlusionState.contains(.visible)` 가 true 이면 일부라도 보이는 것.
        let anyVisible = NSApp.windows.contains { win in
            win.isVisible && !win.isMiniaturized && win.occlusionState.contains(.visible)
        }

        if anyVisible {
            // 다시 보임 — 비디오 레이어 복원 + ABR ceiling 재확인
            playerViewModel?.engine_setGPURenderTier_active()
            multiLiveManager.restoreGPURenderTiersFromSelection()
            reassertPlaybackQuality(reason: "window-occlusion-changed")
        } else {
            // 완전 가림 — 모든 비디오 레이어 hidden (Metal 합성 정지)
            playerViewModel?.engine_setGPURenderTier_hidden()
            multiLiveManager.suspendAllGPURenderTiers()
        }
    }

    /// 메인 플레이어 + 활성 멀티라이브 세션의 화질 ceiling을 즉시 재확인.
    /// `forceHighestQuality=true` 일 때만 nudge 수행 (사용자가 자동 ABR 을 선택한 경우 존중).
    func reassertPlaybackQuality(reason: String) {
        guard settingsStore.player.forceHighestQuality else { return }

        // 메인 플레이어
        playerViewModel?.reassertHighestQuality(reason: reason)

        // 활성 멀티라이브 세션 — 선택된 세션만 nudge (비선택 세션은 의도적 저화질)
        let selectedId = multiLiveManager.selectedSessionId
        for session in multiLiveManager.sessions where session.id == selectedId {
            session.playerViewModel.reassertHighestQuality(reason: reason)
        }
    }

    // MARK: - Thermal State GPU Auto-Degradation (Phase F)

    /// [Phase F] 시스템 열 상태 변경 핸들러 — serious/critical 시 GPU 렌더 티어 자동 강등.
    ///
    /// 정책:
    ///   - nominal/fair: 정상 → 선택 상태 기반 티어 복원
    ///   - serious: 비선택 세션 contentsScale 추가 축소 — 디코딩 유지
    ///   - critical: 비선택 세션 레이어 완전 숨김 (.hidden) — Metal 합성 0
    ///
    /// `SystemLoadMonitor.shared.currentMode`와 연동하여 디코더 스레드도 함께 조정.
    func handleThermalStateChanged() {
        let state = ProcessInfo.processInfo.thermalState
        let stateLabel: String
        switch state {
        case .nominal:  stateLabel = "nominal"
        case .fair:     stateLabel = "fair"
        case .serious:  stateLabel = "serious"
        case .critical: stateLabel = "critical"
        @unknown default: stateLabel = "unknown"
        }

        logger.info("🌡️ Thermal state changed: \(stateLabel)")

        switch state {
        case .nominal, .fair:
            // 정상 — 선택 상태 기반 티어 복원
            playerViewModel?.engine_setGPURenderTier_active()
            multiLiveManager.restoreGPURenderTiersFromSelection()

        case .serious:
            // 과열 경고 — 메인 플레이어는 유지, 비선택 멀티라이브 세션은
            // contentsScale 추가 축소로 GPU 부하 감소
            playerViewModel?.engine_setGPURenderTier_active()
            multiLiveManager.degradeGPURenderTiersForThermal()
            logger.warning("🌡️ Thermal serious — 비선택 세션 GPU 렌더 티어 추가 강등")

        case .critical:
            // 심각 과열 — 비선택 세션 레이어 완전 숨김
            playerViewModel?.engine_setGPURenderTier_active()
            multiLiveManager.suspendAllGPURenderTiers()
            // 선택 세션만 복원
            if let selectedId = multiLiveManager.selectedSessionId,
               let session = multiLiveManager.sessions.first(where: { $0.id == selectedId }) {
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.setGPURenderTier(.active)
                }
                if let av = session.playerViewModel.playerEngine as? AVPlayerEngine {
                    av.setGPURenderTier(.active)
                }
            }
            logger.warning("🌡️ Thermal critical — 비선택 세션 GPU 렌더 완전 정지")

        @unknown default:
            break
        }
    }
}

// MARK: - Background Updates

extension AppState {

    /// 백그라운드 업데이트 시작
    func startBackgroundUpdates() {
        guard let apiClient else { return }
        guard settingsStore.general.autoRefreshEnabled else {
            backgroundUpdateService.stop()
            return
        }
        let interval = settingsStore.general.autoRefreshInterval
        backgroundUpdateService.start(
            apiClient: apiClient,
            interval: interval
        ) { [weak self] event in
            // notificationsEnabled를 클로저 캐처 시점 고정 대신 매번 읽어 설정 변경 반영
            guard let self, self.settingsStore.general.notificationsEnabled else { return }

            let channelSettings = self.settingsStore.channelNotificationsSnapshot()

            // 방송 시작 알림 — 채널별 필터링
            let filteredOnline = event.newlyOnline.filter {
                channelSettings.isLiveNotificationEnabled(for: $0.channelId)
            }
            if !filteredOnline.isEmpty {
                NotificationService.shared.notifyStreamerOnline(filteredOnline)
            }

            // 카테고리 변경 알림 — 채널별 필터링
            let filteredCategory = event.categoryChanged.filter {
                channelSettings.isCategoryChangeNotificationEnabled(for: $0.channelId)
            }
            if !filteredCategory.isEmpty {
                NotificationService.shared.notifyCategoryChange(filteredCategory)
            }

            // 제목 변경 알림 — 채널별 필터링
            let filteredTitle = event.titleChanged.filter {
                channelSettings.isTitleChangeNotificationEnabled(for: $0.channelId)
            }
            if !filteredTitle.isEmpty {
                NotificationService.shared.notifyTitleChange(filteredTitle)
            }
        }
    }

    /// 자동 새로고침 설정(`autoRefreshEnabled` / `autoRefreshInterval`) 변경 시 호출
    /// - 켜짐: 현재 설정의 간격으로 서비스 재시작 (기존 Task 취소)
    /// - 꺼짐: 서비스 중지
    func syncAutoRefreshState() {
        startBackgroundUpdates()
        // HomeViewModel 쪽 인플레이스 자동 갱신은 toggle과 별개(홈 화면 전용 90s 간격) — 설정으로 끌 수 있도록 처리
        if !settingsStore.general.autoRefreshEnabled {
            homeViewModel?.stopAutoRefresh()
        } else {
            homeViewModel?.startAutoRefresh()
        }
    }
}
