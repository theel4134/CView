// MARK: - AppDependencies.swift
// AppState extension - Service initialization and dependency injection

import Foundation
import CViewCore
import CViewNetworking
import CViewAuth
import CViewPersistence
import CViewMonitoring
import CViewPlayer

// MARK: - Initialization & Dependency Setup

extension AppState {

    /// 앱 초기화 — ViewModel 생성, 서비스 연결, 비동기 로딩 시작
    func initialize(
        apiClient: ChzzkAPIClient,
        authManager: AuthManager,
        metricsClient: MetricsAPIClient? = nil,
        metricsWebSocket: MetricsWebSocketClient? = nil
    ) async {
        guard !isInitialized else { return }

        self.apiClient = apiClient
        self.authManager = authManager

        // HLS 프리페치 서비스 초기화 (채널 카드 호버 시 매니페스트 사전 로드)
        self.hlsPrefetchService = HLSPrefetchService(apiClient: apiClient)

        // 세션 만료 알림 구독 등록
        observeSessionExpiry()

        // 1. ViewModel을 먼저 생성 — UI 즉시 렌더링 가능
        homeViewModel = HomeViewModel(apiClient: apiClient)
        chatViewModel = ChatViewModel()
        playerViewModel = PlayerViewModel(engineType: settingsStore.player.preferredEngine)

        // 멀티라이브 매니저 API 클라이언트 + 사용자 정보 주입
        multiLiveManager.configure(apiClient: apiClient, settingsStore: settingsStore, userUid: userChannelId, userNickname: userNickname, metricsForwarder: nil, processLauncher: multiLiveLauncher)

        // 재생 상태 변경 시 App Nap 방지 관리 콜백 연결
        playerViewModel?.onPlaybackStateChanged = { [weak self] in
            self?.updatePlaybackActivity()
        }

        // 2. UI 사용 가능 상태로 즉시 전환 (ProgressView 해제)
        isInitialized = true

        // 3. SwiftUI에 첫 프레임을 렌더링할 시간을 줌
        await Task.yield()

        // 4. 라이브 채널 로딩 (공개 API, 비차단)
        Task { await homeViewModel?.loadLiveChannels() }

        // 4.5 메트릭 서버 연결 (비차단)
        if let metricsClient, let metricsWebSocket {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                self.homeViewModel?.configureMetrics(client: metricsClient, wsClient: metricsWebSocket)
            }

            // MetricsForwarder 설정 (settingsStore에서 isEnabled 읽기)
            // settingsStore는 이 시점에서 아직 로드 전일 수 있으므로 기본값 false 사용
            // initializeDataStore() 완료 후 applyMetricsSettings()에서 업데이트됨
            self.metricsClient = metricsClient
            self.metricsForwarder = MetricsForwarder(
                apiClient: metricsClient,
                monitor: performanceMonitor,
                isEnabled: false
            )
            // 멀티라이브 매니저에 메트릭 포워더 주입
            multiLiveManager.metricsForwarder = self.metricsForwarder
        }

        // 5. DataStore/Settings 초기화 (디스크 I/O, 비차단) — 살짝 지연
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await self.initializeDataStore()
        }

        // 6. 인증 초기화 (네트워크 타임아웃 가능, 비차단) — 살짝 지연
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await self.initializeAuth(authManager: authManager, apiClient: apiClient)
        }

        // 7. 알림 설정 (비차단)
        Task {
            await NotificationService.shared.requestAuthorization()
            NotificationService.shared.registerCategories()
        }

        // 8. 기본 이모티콘 프리로드 — 모든 채널 공통 이모티콘을 앱 시작 시 1회 다운로드
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await self.preloadBasicEmoticons(apiClient: apiClient)
        }

        // 9. 앱 활성/비활성 생명주기 옵저버 등록
        setupLifecycleObservers()
    }

    /// DataStore 및 SettingsStore 초기화 (별도 Task에서 호출)
    func initializeDataStore() async {
        do {
            // [Power-Aware] AC: .userInitiated (P-core, 앞당겨 초기화 빠르게), Battery: .utility (E-core, 배터리 보호)
            let container = try await Task.detached(priority: PowerAwareTaskPriority.userVisible) {
                try CViewPersistence.DataStore.createContainer()
            }.value
            let store = CViewPersistence.DataStore(modelContainer: container)
            self.dataStore = store
            await settingsStore.configure(dataStore: store)
            logger.info("DataStore and SettingsStore initialized")

            // 디스크에서 로드된 설정으로 PlayerViewModel 엔진 타입 동기화
            // initialize() 시점에는 settingsStore가 기본값이므로 여기서 반드시 갱신해야 함
            playerViewModel?.preferredEngineType = settingsStore.player.preferredEngine

            // [Persistence 2026-04-18] 저장된 볼륨/음소거 복원 + 사용자 변경 시 영구 저장 콜백 연결
            playerViewModel?.volume = settingsStore.player.volumeLevel
            playerViewModel?.isMuted = settingsStore.player.startMuted
            playerViewModel?.onVolumeChanged = { [weak self] newVolume in
                guard let self else { return }
                self.settingsStore.player.volumeLevel = newVolume
                self.settingsStore.scheduleDebouncedSave()
            }
            playerViewModel?.onMuteChanged = { [weak self] muted in
                guard let self else { return }
                self.settingsStore.player.startMuted = muted
                self.settingsStore.scheduleDebouncedSave()
            }

            // HomeViewModel에 캐시 저장소 연결 (didSet → loadFromCache() 자동 호출)
            homeViewModel?.dataStore = store

            // 저장된 설정을 ChatViewModel에 일괄 적용
            chatViewModel?.applySettings(settingsStore.chat)
            chatViewModel?.onBlockedUsersChanged = { [weak self] users in
                Task { @MainActor in
                    self?.settingsStore.chat.blockedUsers = users
                    await self?.settingsStore.save()
                }
            }

            // 메트릭 설정 적용 (DataStore 로드 완료 후)
            await applyMetricsSettings()
        } catch {
            logger.error("Failed to create DataStore: \(error.localizedDescription)")
        }
    }

    /// 인증 초기화 및 후속 작업 (별도 Task에서 호출)
    func initializeAuth(authManager: AuthManager, apiClient: ChzzkAPIClient) async {
        await authManager.initialize()

        isLoggedIn = await authManager.isAuthenticated
        logger.info("Auth initialized, logged in: \(self.isLoggedIn)")

        // [2026-04-19] 자식 프로세스 대응: 쿠키 복원 완료 시점을 소비자(채팅 시작 경로 등)가 대기할 수 있도록 플래그 노출.
        // 로그인 여부와 무관하게 "auth 초기화가 끝났다"는 의미이므로 guard 이전에 세팅.
        isAuthInitialized = true

        guard isLoggedIn else { return }

        // 프로필/팔로잉 병렬 로드
        async let profileLoad: Void = loadOAuthUserProfile(authManager: authManager)
        async let userLoad: Void = loadUserProfile(apiClient: apiClient)
        async let followingLoad: Void = { await self.homeViewModel?.loadFollowingChannels() }()
        await profileLoad
        await userLoad
        await followingLoad

        startBackgroundUpdates()
    }

    // MARK: - Basic Emoticon Preloading

    /// 치지직 기본 이모티콘을 앱 시작 시 1회 프리로드
    /// API에서 팩 목록 로드 → 상세 조회(resolve) → 이미지 프리페치 → AppState에 캐시
    func preloadBasicEmoticons(apiClient: ChzzkAPIClient) async {
        let packs = await apiClient.globalBasicEmoticons()
        guard !packs.isEmpty else {
            logger.info("기본 이모티콘: 팩 없음 (API 실패 또는 빈 응답)")
            return
        }

        let (emoMap, resolvedPacks) = await apiClient.resolveEmoticonPacks(packs)
        guard !emoMap.isEmpty else {
            logger.info("기본 이모티콘: resolve 후 이모티콘 없음")
            return
        }

        // AppState 캐시에 저장
        cachedBasicEmoticonPacks = resolvedPacks
        cachedBasicEmoticonMap = emoMap

        // MultiLiveManager에도 전달
        multiLiveManager.updateCachedEmoticons(map: emoMap, packs: resolvedPacks)

        logger.info("기본 이모티콘 프리로드 완료: \(resolvedPacks.count)개 팩, \(emoMap.count)개 이모티콘")

        // 모든 이모티콘 이미지를 디스크/메모리 캐시에 미리 다운로드
        let urls = emoMap.values.compactMap { URL(string: $0) }
        // [Fix 32] PowerAware: 프리페치는 항상 .background
        Task.detached(priority: PowerAwareTaskPriority.prefetch) {
            await ImageCacheService.shared.prefetch(urls)
        }
    }
}
