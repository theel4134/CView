// MARK: - CViewApp.swift
// CViewApp - Application entry point (minimal)
// 원본: chzzkViewApp.swift → 개선: 모듈화된 DI, @Observable, SwiftData

import SwiftUI
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

        // NSApp은 SwiftUI App.init()에서 아직 nil — onAppear에서 설정
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(router)
                .environment(appState)
                .frame(minWidth: 960, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
                // 60fps: 트랜잭션 기본값 — 모든 암묵적 애니메이션에 spring 적용
                .transaction { t in
                    if t.animation == nil {
                        t.animation = DesignTokens.Animation.contentTransition
                    }
                }
                .onAppear {
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
                .onChange(of: appState.settingsStore.appearance.theme) { _, newTheme in
                    applyAppTheme(newTheme)
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

        // Multi-chat window (팔로잉에 통합됨)
        WindowGroup("멀티채팅", id: "multi-chat-window") {
            if let vm = appState.homeViewModel {
                FollowingView(viewModel: vm)
                    .environment(appState)
            } else {
                ProgressView()
                    .environment(appState)
            }
        }
        .defaultSize(width: 700, height: 550)

        // Multi-live network monitor window
        WindowGroup("네트워크 모니터", id: "ml-network-window") {
            MLNetworkWindowView()
                .environment(appState)
        }
        .defaultSize(width: 440, height: 600)

        // Multi-live metrics forwarding window
        WindowGroup("메트릭 전송", id: "ml-metrics-window") {
            MLMetricsWindowView()
                .environment(appState)
        }
        .defaultSize(width: 420, height: 500)

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
