// MARK: - AppLifecycle.swift
// AppState extension - App lifecycle observers and background updates

import AppKit
import CViewCore
import CViewNetworking

// MARK: - Session Expiry

extension AppState {

    /// 서버 401 응답(세션 만료) 알림 구독 — initialize()에서 한 번 호출
    func observeSessionExpiry() {
        NotificationCenter.default.addObserver(
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
        nc.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowRestored()
            }
        }
    }

    /// 앱 포커스 복귀 — 폴링 주기를 정상(30s)으로 복구 & 즉시 1회 갱신
    func handleAppBecameActive() {
        guard !isAppActive else { return }
        isAppActive = true
        homeViewModel?.resumeMetricsPolling()
        logger.info("App became active – resumed metrics polling")
    }

    /// 앱 포커스 이탈 — 메트릭 폴링 주기 느리게 (2분)
    /// 백그라운드 재생 설정이 켜져 있으면 스트림을 중단하지 않고 App Nap을 방지한다.
    func handleAppResignedActive() {
        guard isAppActive else { return }
        isAppActive = false
        homeViewModel?.pauseMetricsPolling()

        // 백그라운드 재생 유지: 활성 스트림이 있으면 App Nap 방지 activity 시작
        if settingsStore.player.continuePlaybackInBackground {
            let hasActiveStream = isAnyStreamPlaying()
            if hasActiveStream {
                beginPlaybackActivity()
            }
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

    /// 창 최소화에서 복원 시 VLC drawable 컨텍스트를 재설정
    /// VLC 렌더링 서피스는 창 최소화 중 무효화될 수 있다.
    func handleWindowRestored() {
        if let vlcEngine = playerViewModel?.mediaPlayer,
           case .playing = playerViewModel?.streamPhase {
            vlcEngine.refreshDrawable()
            logger.info("Window restored — VLC drawable refreshed")
        }
    }
}

// MARK: - Background Updates

extension AppState {

    /// 백그라운드 업데이트 시작
    func startBackgroundUpdates() {
        guard let apiClient else { return }
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
}
