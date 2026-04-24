// MARK: - CViewApp.swift
// CViewApp - Application entry point (minimal)
// 원본: chzzkViewApp.swift → 개선: 모듈화된 DI, @Observable, SwiftData

import SwiftUI
import AppKit
import CViewCore
import CViewNetworking
import CViewAuth
import CViewPlayer

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

    /// CommandLine 파싱 결과 (메인 / 자식 인스턴스)
    private let launchMode: AppLaunchMode

    // MARK: - Initialization

    init() {
        // 실행 모드 결정 (메인 / 맠티라이브 자식)
        self.launchMode = AppLaunchModeParser.detect()

        // [프로세스 격리 2026-04-19] embedded 자식: WindowGroup 가 창을 만들기 전에
        // activation policy 를 .accessory 로 미리 설정해 Dock 아이콘이 잠깐 뜨는 것을 방지.
        // 또한 NSWindow.didBecomeKey 를 한 번 가로채 borderless 스타일을 즉시 적용.
        // 주의: App.init() 시점에는 `NSApp` 전역이 아직 nil 일 수 있어 NSApplication.shared 를 사용한다.
        if let cfg = launchMode.childConfig, cfg.hideFromDock {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        if let cfg = launchMode.childConfig {
            ChildWindowChromeApplier.install(config: cfg)
        }

        // Initialize service container
        serviceContainer = ServiceContainer.shared

        // Initialize core services (AuthManager를 AuthTokenProvider로 연결)
        authManager = AuthManager()
        apiClient = ChzzkAPIClient(authProvider: authManager)

        // Initialize metrics services
        metricsClient = MetricsAPIClient()
        metricsWebSocket = MetricsWebSocketClient()

        // NSApp은 SwiftUI App.init()에서 아직 nil — onAppear에서 설정
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if let childCfg = launchMode.childConfig {
                    // ✨ 자식 인스턴스: 단독 채널 플레이어만 띄움
                    MultiLiveChildRootView(config: childCfg)
                        .environment(router)
                        .environment(appState)
                        .preferredColorScheme(.dark)
                } else {
                    MainContentView()
                        .environment(router)
                        .environment(appState)
                        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
                        .windowFrameAutosave("cview.main")
                }
            }
                // 60fps: 트랜잭션 기본값 — 모든 암묵적 애니메이션에 spring 적용.
                // 단, 다음 경우엔 주입을 건너뛰어 드래그/리사이즈/메뉴전환 시 프레임 드롭 방지:
                //   1) SwiftUI 가 명시적으로 disablesAnimations = true 를 설정한 경우
                //      (레이아웃 패스, 시스템 강제 동기 갱신 등)
                //   2) 어떤 NSWindow 든 라이브 리사이즈 중인 경우
                //      → 모든 레이아웃 변동을 spring 으로 보간하면 매 프레임 추가 비용
                //         발생 → 사용자 체감 stutter. 리사이즈 중엔 즉시 반영이 정답.
                //   3) 사이드바 메뉴 전환 직후 350ms (MenuTransitionGate)
                //      → 신규 detail 루트 뷰 마운트 시 발생하는 수십 개 암묵적 상태
                //         변화에 spring 보간이 일괄 적용되어 첫 프레임 드롭 유발.
                .transaction { t in
                    if t.animation == nil
                        && t.disablesAnimations == false
                        && LiveWindowResizeMonitor.isAnyWindowLiveResizing == false
                        && MenuTransitionGate.isTransitioning == false {
                        t.animation = DesignTokens.Animation.contentTransition
                    }
                }
                .onAppear {
                    // 라이브 리사이즈 모니터 설치 — 글로벌 .transaction 게이팅용
                    LiveWindowResizeMonitor.install()

                    // 테마 설정에 따라 NSApp.appearance 반영
                    applyAppTheme(appState.settingsStore.appearance.theme)

                    // 알림 콜백 설정 (동기, MainActor)
                    NotificationService.shared.onWatchChannel = { [router] channelId in
                        router.navigate(to: .live(channelId: channelId))
                    }

                    // 서비스 등록 (비차단)
                    Task {
                        await serviceContainer.register(ChzzkAPIClient.self, instance: apiClient)
                        await serviceContainer.register(AuthManager.self, instance: authManager)
                    }

                    // JWT 토큰 사전 발급 (POST 요청 인증용)
                    Task { await metricsClient.fetchJWT() }

                    // 앱 초기화 (내부적으로 모든 작업을 분리된 Task로 실행)
                    Task { await appState.initialize(apiClient: apiClient, authManager: authManager, metricsClient: metricsClient, metricsWebSocket: metricsWebSocket) }

                    // 만료된 이미지 캐시 백그라운드 정리 (앱 시작 3초 후)
                    // [Fix 32] PowerAware: 캐시 정리는 항상 .background
                    Task.detached(priority: PowerAwareTaskPriority.prefetch) {
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
                .onChange(of: appState.settingsStore.appearance.theme) { _, newTheme in
                    applyAppTheme(newTheme)
                }
                // [Widget 2026-04-24] 위젯/외부 cview:// URL Scheme 처리
                .onOpenURL { url in
                    DeepLinkRouter.handle(url: url, router: router, appState: appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.automatic)
        .commands {
            appCommands
        }

        // Player window (for multi-window viewing)
        // 플레이어 윈도우는 영상 위 오버레이이므로 항상 다크 테마 유지
        WindowGroup("플레이어", id: "player-window", for: String.self) { $channelId in
            if let channelId {
                LiveStreamView(channelId: channelId, isDetachedWindow: true)
                    .environment(router)
                    .environment(appState)
                    .onAppear { appState.registerDetachedChannel(channelId) }
                    .onDisappear { appState.unregisterDetachedChannel(channelId) }
                    .preferredColorScheme(.dark)
                    .windowFrameAutosave("cview.player")
            }
        }
        .defaultSize(width: 960, height: 600)

        // Statistics window
        WindowGroup("통계", id: "statistics-window") {
            StatisticsView()
                .environment(appState)
                .environment(router)
                .windowFrameAutosave("cview.statistics")
        }
        .defaultSize(width: 700, height: 500)

        // Chat popup window
        WindowGroup("채팅", id: "chat-window") {
            ChatWindowWrapper()
                .environment(appState)
                .environment(router)
                .windowFrameAutosave("cview.chat")
        }
        .defaultSize(width: 360, height: 600)

        // Multi-chat window (팔로잉에 통합됨)
        WindowGroup("멀티채팅", id: "multi-chat-window") {
            if let vm = appState.homeViewModel {
                FollowingView(viewModel: vm)
                    .environment(appState)
                    .environment(router)
                    .windowFrameAutosave("cview.multichat")
            } else {
                ProgressView()
                    .environment(appState)
                    .environment(router)
            }
        }
        .defaultSize(width: 700, height: 550)

        // Multi-live network monitor window
        WindowGroup("네트워크 모니터", id: "ml-network-window") {
            MLNetworkWindowView()
                .environment(appState)
                .environment(router)
                .windowFrameAutosave("cview.ml-network")
        }
        .defaultSize(width: 440, height: 600)

        // Multi-live metrics forwarding window
        WindowGroup("메트릭 전송", id: "ml-metrics-window") {
            MLMetricsWindowView()
                .environment(appState)
                .environment(router)
                .windowFrameAutosave("cview.ml-metrics")
        }
        .defaultSize(width: 420, height: 500)

        // System usage monitor window (보기 > 시스템 사용률 모니터)
        WindowGroup("시스템 사용률 모니터", id: "system-usage-window") {
            SystemUsageWindowView()
                .environment(appState)
                .environment(router)
                .windowFrameAutosave("cview.system-usage")
        }
        .defaultSize(width: 400, height: 460)

        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
                .environment(router)
        }

        // MenuBarExtra (macOS 메뉴바 아이콘)
        // 주의: Scene body에서 @Observable 프로퍼티를 읽으면 전체 Scene 재평가 → 앱 멈춤
        // 동적 아이콘/표시 여부는 MenuBarView 내부에서 처리
        MenuBarExtra("CView", systemImage: "play.tv") {
            MenuBarView()
                .environment(appState)
                .environment(router)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Commands

    @CommandsBuilder
    private var appCommands: some Commands {
        // ── 파일 메뉴 ──
        CommandGroup(replacing: .newItem) {
            Button("새 플레이어 창") {
                openWindow(id: "player-window", value: "")
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("통계 창") {
                openWindow(id: "statistics-window")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("네트워크 모니터") {
                openWindow(id: "ml-network-window")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("메트릭 전송 현황") {
                openWindow(id: "ml-metrics-window")
            }

            Button("시스템 사용률 모니터") {
                openWindow(id: "system-usage-window")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        // ── 보기 메뉴 ──
        CommandGroup(after: .toolbar) {
            Button("커맨드 팔레트") {
                appState.showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            // 사이드바 네비게이션
            Button("홈") {
                router.selectSidebar(.home)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("라이브") {
                router.selectSidebar(.following)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("카테고리") {
                router.selectSidebar(.category)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("검색") {
                router.selectSidebar(.search)
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("클립") {
                router.selectSidebar(.clips)
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("최근/즐겨찾기") {
                router.selectSidebar(.recentFavorites)
            }
            .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button("뒤로 가기") {
                router.navigateBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(router.path.isEmpty)
        }

        // ── 스트림 메뉴 ──
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
                NSApp?.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])

            Button("플레이어 전체 화면") {
                appState.playerViewModel?.toggleFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // ── 채팅 메뉴 ──
        CommandMenu("채팅") {
            Button("채팅 지우기") {
                appState.chatViewModel?.clearMessages()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

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

        // ── 재생 메뉴 ──
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

        // ── 도움말 메뉴 ──
        CommandGroup(replacing: .help) {
            Button("키보드 단축키") {
                appState.showKeyboardShortcutsHelp = true
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("CView 정보") {
                appState.showAboutPanel = true
            }
        }
    }
    
    // MARK: - Theme
    
    /// 테마 설정에 따라 NSApp.appearance를 업데이트한다.
    private func applyAppTheme(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp.appearance = nil  // 시스템 설정 따름
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
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
