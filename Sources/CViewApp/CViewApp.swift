// MARK: - CViewApp.swift
// CViewApp - Application entry point
// 원본: chzzkViewApp.swift → 개선: 모듈화된 DI, @Observable, SwiftData

import SwiftUI
import SwiftData
import AppKit
import CViewCore
import CViewNetworking
import CViewAuth
import CViewPersistence
import CViewChat
import CViewPlayer
import CViewMonitoring
import UserNotifications

// MARK: - App Entry Point

@main
struct CViewApplication: App {
    
    // MARK: - State
    
    @Environment(\.openWindow) private var openWindow
    @State private var router = AppRouter()
    @State private var appState = AppState()
    
    // MARK: - Services
    
    private let serviceContainer: ServiceContainer
    private let apiClient: ChzzkAPIClient
    private let authManager: AuthManager
    private let metricsClient: MetricsAPIClient
    private let metricsWebSocket: MetricsWebSocketClient
    
    // MARK: - Initialization
    
    init() {
        // Initialize service container
        serviceContainer = ServiceContainer.shared
        
        // Initialize core services (AuthManager를 AuthTokenProvider로 연결)
        authManager = AuthManager()
        apiClient = ChzzkAPIClient(authProvider: authManager)
        
        // Initialize metrics services
        metricsClient = MetricsAPIClient()
        metricsWebSocket = MetricsWebSocketClient()
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(router)
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    // 알림 콜백 설정 (동기, MainActor)
                    NotificationService.shared.onWatchChannel = { [router] channelId in
                        router.navigate(to: .live(channelId: channelId))
                    }
                    
                    // 서비스 등록 (비차단)
                    Task {
                        await serviceContainer.register(ChzzkAPIClient.self, instance: apiClient)
                        await serviceContainer.register(AuthManager.self, instance: authManager)
                    }
                    
                    // 앱 초기화 (내부적으로 모든 작업을 분리된 Task로 실행)
                    Task { await appState.initialize(apiClient: apiClient, authManager: authManager, metricsClient: metricsClient, metricsWebSocket: metricsWebSocket) }

                    // 만료된 이미지 캐시 백그라운드 정리 (앱 시작 3초 후)
                    Task.detached(priority: .background) {
                        try? await Task.sleep(for: .seconds(3))
                        await ImageCacheService.shared.pruneExpiredEntries()
                    }
                }
                // 세션 만료 알림 (서버 401 수신 시 자동 로그아웃 후 표시)
                .alert("세션이 만료되었습니다", isPresented: $appState.sessionExpiredAlert) {
                    Button("확인", role: .cancel) {}
                } message: {
                    Text("자동으로 로그아웃되었습니다. 다시 로그인하면 채팅 및 구독 기능을 이용할 수 있어요.")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            appCommands
        }
        
        // Player window (for multi-window viewing)
        WindowGroup("플레이어", id: "player-window", for: String.self) { $channelId in
            if let channelId {
                LiveStreamView(channelId: channelId, isDetachedWindow: true)
                    .environment(router)
                    .environment(appState)
                    .onAppear { appState.registerDetachedChannel(channelId) }
                    .onDisappear { appState.unregisterDetachedChannel(channelId) }
            }
        }
        .defaultSize(width: 960, height: 600)
        
        // Statistics window
        WindowGroup("통계", id: "statistics-window") {
            StatisticsView()
                .environment(appState)
        }
        .defaultSize(width: 700, height: 500)
        
        // Chat popup window
        WindowGroup("채팅", id: "chat-window") {
            ChatWindowWrapper()
                .environment(appState)
        }
        .defaultSize(width: 360, height: 600)
        
        // Multi-chat window
        WindowGroup("멀티채팅", id: "multi-chat-window") {
            MultiChatView()
                .environment(appState)
        }
        .defaultSize(width: 700, height: 550)
        
        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        // MenuBarExtra (macOS 메뉴바 아이콘)
        // 주의: Scene body에서 @Observable 프로퍼티를 읽으면 전체 Scene 재평가 → 앱 멈춤
        // 동적 아이콘/표시 여부는 MenuBarView 내부에서 처리
        MenuBarExtra("CView", systemImage: "play.tv") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
    
    // MARK: - Commands
    
    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 창") {
                openWindow(id: "player-window", value: "")
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Button("통계 창") {
                openWindow(id: "statistics-window")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        
        CommandMenu("스트림") {
            Button("새로고침") {
                Task { await appState.homeViewModel?.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("스크린샷") {
                appState.playerViewModel?.takeScreenshot()
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Divider()
            
            Button("전체 화면") {
                appState.playerViewModel?.toggleFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
        
        CommandMenu("채팅") {
            Button("채팅 지우기") {
                appState.chatViewModel?.clearMessages()
            }
            .keyboardShortcut("k", modifiers: .command)
            
            Button("자동 스크롤 토글") {
                appState.chatViewModel?.toggleAutoScroll()
            }
            .keyboardShortcut("j", modifiers: .command)
            
            Divider()
            
            Button("채팅 독립 창 열기") {
                openWindow(id: "chat-window")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button("멀티채팅 열기") {
                openWindow(id: "multi-chat-window")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        
        CommandMenu("재생") {
            Button("재생/일시정지") {
                Task { await appState.playerViewModel?.togglePlayPause() }
            }
            .keyboardShortcut(.space, modifiers: [])
            
            Divider()
            
            Button("음소거 토글") {
                appState.playerViewModel?.toggleMute()
            }
            .keyboardShortcut("m", modifiers: [])
            
            Button("볼륨 올리기") {
                appState.playerViewModel?.setVolume(min(1.0, (appState.playerViewModel?.volume ?? 0.5) + 0.1))
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            
            Button("볼륨 내리기") {
                appState.playerViewModel?.setVolume(max(0.0, (appState.playerViewModel?.volume ?? 0.5) - 0.1))
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            
            Divider()
            
            Button("PiP 토글") {
                if let engine = appState.playerViewModel?.mediaPlayer {
                    PiPController.shared.togglePiP(vlcEngine: engine, avEngine: nil, title: appState.playerViewModel?.channelName ?? "PiP")
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
        }
    }
}

// MARK: - App State

@Observable
@MainActor
final class AppState {
    
    var isInitialized = false
    var isLoggedIn = false
    var userNickname: String?
    var userChannelId: String?
    var userProfileURL: URL?
    let launchTime = Date()

    /// 서버 401 응답으로 세션이 만료될 때 true → . alert 표시
    var sessionExpiredAlert = false

    /// 앱이 현재 활성 상태(포커스)인지 여부
    private(set) var isAppActive: Bool = true

    /// 새 창(player-window)으로 분리돼 재생 중인 채널 ID 집합
    /// 메인 LiveStreamView가 사라질 때 이 집합에 포함된 채널은 스트림을 중단하지 않음
    private(set) var detachedChannelIds: Set<String> = []

    func registerDetachedChannel(_ channelId: String) {
        detachedChannelIds.insert(channelId)
    }
    func unregisterDetachedChannel(_ channelId: String) {
        detachedChannelIds.remove(channelId)
    }

    var homeViewModel: HomeViewModel?
    var chatViewModel: ChatViewModel?
    var playerViewModel: PlayerViewModel?
    var settingsStore: SettingsStore = SettingsStore()
    
    /// 멀티라이브 세션 매니저 — 네비게이션 전환 시에도 채널 목록 유지
    var multiLiveManager = MultiLiveSessionManager()
    
    /// 공유 성능 모니터 (LiveStreamView → MetricsForwarder 모두 같은 인스턴스 사용)
    let performanceMonitor = PerformanceMonitor()
    
    /// 메트릭 포워더 (채널 시청 시 서버로 메트릭 전송)
    private(set) var metricsForwarder: MetricsForwarder?
    /// MetricsAPIClient 참조 (설정 변경 시 URL 업데이트용)
    private var metricsClient: MetricsAPIClient?
    
    /// 백그라운드 팔로잉 업데이트 서비스
    let backgroundUpdateService = BackgroundUpdateService()
    
    // 공유 서비스 — View에서 접근 가능
    private(set) var apiClient: ChzzkAPIClient?
    private var authManager: AuthManager?
    private(set) var dataStore: CViewPersistence.DataStore?
    private let logger = AppLogger.app

    // 앱 활성/비활성 알림 옵저버
    private var appActiveObserver: (any NSObjectProtocol)?
    private var appResignObserver: (any NSObjectProtocol)?

    func initialize(apiClient: ChzzkAPIClient, authManager: AuthManager, metricsClient: MetricsAPIClient? = nil, metricsWebSocket: MetricsWebSocketClient? = nil) async {
        guard !isInitialized else { return }

        self.apiClient = apiClient
        self.authManager = authManager

        // 세션 만료 알림 구독 등록
        observeSessionExpiry()

        // 1. ViewModel을 먼저 생성 — UI 즉시 렌더링 가능
        homeViewModel = HomeViewModel(apiClient: apiClient)
        chatViewModel = ChatViewModel()
        playerViewModel = PlayerViewModel(engineType: settingsStore.player.preferredEngine)
        
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
                await self.homeViewModel?.configureMetrics(client: metricsClient, wsClient: metricsWebSocket)
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

        // 8. 앱 활성/비활성 생명주기 옵저버 등록
        setupLifecycleObservers()
    }
    
    /// DataStore 및 SettingsStore 초기화 (별도 Task에서 호출)
    private func initializeDataStore() async {
        do {
            let container = try await Task.detached(priority: .userInitiated) {
                try CViewPersistence.DataStore.createContainer()
            }.value
            let store = CViewPersistence.DataStore(modelContainer: container)
            self.dataStore = store
            await settingsStore.configure(dataStore: store)
            logger.info("DataStore and SettingsStore initialized")

            // 디스크에서 로드된 설정으로 PlayerViewModel 엔진 타입 동기화
            // initialize() 시점에는 settingsStore가 기본값이므로 여기서 반드시 갱신해야 함
            playerViewModel?.preferredEngineType = settingsStore.player.preferredEngine

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
    private func initializeAuth(authManager: AuthManager, apiClient: ChzzkAPIClient) async {
        await authManager.initialize()
        
        isLoggedIn = await authManager.isAuthenticated
        logger.info("Auth initialized, logged in: \(self.isLoggedIn)")
        
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
    
    /// 로그인 성공 처리 (LoginWebView에서 호출)
    func handleLoginSuccess() async {
        guard let authManager else { return }
        await authManager.handleLoginSuccess()
        isLoggedIn = await authManager.isAuthenticated
        logger.info("Login success, isLoggedIn: \(self.isLoggedIn)")
        
        // 쿠키 로그인 성공 → 팔로잉 재시도
        homeViewModel?.needsCookieLogin = false
        await homeViewModel?.loadFollowingChannels()
        
        // 프로필 로드
        if isLoggedIn, let apiClient {
            await loadUserProfile(apiClient: apiClient)
            startBackgroundUpdates()
        }
    }
    
    /// OAuth 로그인 성공 처리 (OAuthLoginWebView에서 호출)
    func handleOAuthLoginSuccess() async {
        guard let authManager else { return }
        isLoggedIn = await authManager.isAuthenticated
        logger.info("OAuth login success, isLoggedIn: \(self.isLoggedIn)")
        
        // 팔로잉 목록 새로 고침
        await homeViewModel?.loadFollowingChannels()
        
        // OAuth 프로필 로드 (채널 ID 포함)
        if isLoggedIn {
            await loadOAuthUserProfile(authManager: authManager)
            if let apiClient {
                await loadUserProfile(apiClient: apiClient)
            }
            startBackgroundUpdates()
        }
    }
    
    /// AuthManager 접근
    func getAuthManager() -> AuthManager? {
        authManager
    }
    
    /// 메트릭 서버 연결 테스트 (설정된 URL 기준)
    func testMetricsConnection() async -> (success: Bool, latencyMs: Double, message: String) {
        guard let client = metricsClient else {
            return (false, 0, "메트릭 클라이언트가 초기화되지 않았습니다")
        }
        // 최신 URL 반영
        if let url = URL(string: settingsStore.metrics.serverURL), !settingsStore.metrics.serverURL.isEmpty {
            await client.updateBaseURL(url)
        }
        return await client.testConnection()
    }

    /// 메트릭 설정을 MetricsAPIClient · MetricsForwarder에 적용
    /// DataStore 로드 완료 후, 또는 사용자가 설정을 변경할 때 호출
    func applyMetricsSettings() async {
        let ms = settingsStore.metrics

        // 서버 URL 업데이트
        if let url = URL(string: ms.serverURL), !ms.serverURL.isEmpty {
            await metricsClient?.updateBaseURL(url)
        }

        // 전송 주기 업데이트
        await metricsForwarder?.updateIntervals(
            forward: ms.forwardInterval,
            ping: ms.pingInterval
        )

        // 활성화/비활성화 (setEnabled가 내부에서 상태 변화 감지)
        await metricsForwarder?.setEnabled(ms.metricsEnabled)

        logger.info("Metrics settings applied – enabled: \(ms.metricsEnabled), url: \(ms.serverURL)")
    }

    /// 로그아웃 처리
    func handleLogout() async {
        guard let authManager else { return }
        await authManager.logout()
        isLoggedIn = false
        userNickname = nil
        userChannelId = nil
        userProfileURL = nil
        backgroundUpdateService.stop()
        logger.info("Logged out")
    }

    /// 서버 401 응답(세션 만료) 알림 구독 — initialize()에서 한 번 호출
    private func observeSessionExpiry() {
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
    
    // MARK: - App Lifecycle Optimization

    /// 앱 활성/비활성 NSNotification 옵저버 등록
    private func setupLifecycleObservers() {
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
    }

    /// 앱 포커스 복귀 — 폴링 주기를 정상(30s)으로 복구 & 즉시 1회 갱신
    private func handleAppBecameActive() {
        guard !isAppActive else { return }
        isAppActive = true
        homeViewModel?.resumeMetricsPolling()
        logger.info("App became active – resumed metrics polling")
    }

    /// 앱 포커스 이탈 — 메트릭 폴링 주기 느리게 (2분)
    private func handleAppResignedActive() {
        guard isAppActive else { return }
        isAppActive = false
        homeViewModel?.pauseMetricsPolling()
        logger.info("App resigned active – throttled metrics polling")
    }

    // MARK: - Background Updates
    
    /// 백그라운드 업데이트 시작
    private func startBackgroundUpdates() {
        guard let apiClient else { return }
        let interval = settingsStore.general.autoRefreshInterval
        let notificationsEnabled = settingsStore.general.notificationsEnabled
        
        backgroundUpdateService.start(
            apiClient: apiClient,
            interval: interval
        ) { newlyOnline in
            if notificationsEnabled {
                NotificationService.shared.notifyStreamerOnline(newlyOnline)
            }
        }
    }
    
    // MARK: - User Profile
    
    /// 사용자 프로필 정보 로드
    private func loadUserProfile(apiClient: ChzzkAPIClient) async {
        do {
            let userInfo = try await apiClient.userStatus()
            if userNickname == nil {
                userNickname = userInfo.nickname
            }
            if let imageURL = userInfo.profileImageURL, userProfileURL == nil {
                userProfileURL = URL(string: imageURL)
            }
            logger.info("프로필 로드 완료: \(userInfo.nickname ?? "unknown"), channelId: \(self.userChannelId ?? "none")")
        } catch {
            logger.error("프로필 로드 실패: \(String(describing: error), privacy: .public)")
        }
    }
    
    /// OAuth 사용자 프로필 로드 (채널 ID 포함)
    private func loadOAuthUserProfile(authManager: AuthManager) async {
        do {
            let profile = try await authManager.fetchOAuthProfile()
            userNickname = profile.nickname ?? userNickname
            userChannelId = profile.channelId
            if let imageURL = profile.profileImageUrl {
                userProfileURL = URL(string: imageURL)
            }
            logger.info("OAuth 프로필: \(profile.nickname ?? "unknown"), 채널ID: \(profile.channelId ?? "none")")
        } catch {
            logger.error("OAuth 프로필 로드 실패: \(error.localizedDescription)")
        }
    }
}

// MARK: - AppTheme + SwiftUI ColorScheme

extension AppTheme {
    /// SwiftUI preferredColorScheme 값으로 변환 (nil = 시스템 따름)
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

// MARK: - Chat Window Wrapper (with settings sheet)

private struct ChatWindowWrapper: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        ChatPanelView(chatVM: appState.chatViewModel, onOpenSettings: { showSettings = true })
            .sheet(isPresented: $showSettings) {
                ChatSettingsView()
            }
    }
}
