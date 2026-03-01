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
                .frame(minWidth: 900, minHeight: 600)
                // 60fps: 트랜잭션 기본값 — 모든 암묵적 애니메이션에 spring 적용
                .transaction { t in
                    if t.animation == nil {
                        t.animation = DesignTokens.Animation.contentTransition
                    }
                }
                .onAppear {
                    // Force dark mode app-wide for Glass Morphism design
                    NSApp.appearance = NSAppearance(named: .darkAqua)

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
                    .preferredColorScheme(.dark)
            }
        }
        .defaultSize(width: 960, height: 600)

        // Statistics window
        WindowGroup("통계", id: "statistics-window") {
            StatisticsView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 500)

        // Chat popup window
        WindowGroup("채팅", id: "chat-window") {
            ChatWindowWrapper()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 360, height: 600)

        // Multi-chat window
        WindowGroup("멀티채팅", id: "multi-chat-window") {
            MultiChatView()
                .environment(appState)
                .preferredColorScheme(.dark)
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

        CommandGroup(after: .toolbar) {
            Button("커맨드 팔레트") {
                appState.showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
        }

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
