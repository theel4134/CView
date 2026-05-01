// MARK: - AppState.swift
// AppState - Observable application state container

import SwiftUI
import CViewCore
import CViewNetworking
import CViewAuth
import CViewPersistence
import CViewMonitoring
import CViewPlayer

// MARK: - App State

@Observable
@MainActor
final class AppState {

    // MARK: - Launch Mode

    /// 현재 프로세스가 멀티라이브 자식 인스턴스(`--multilive-child`)로 부팅되었는지 여부.
    /// 자식 프로세스는 부모와 동일 번들 ID 라 UserDefaults 가 공유되므로,
    /// 워크스페이스 스냅샷 복원 / 종료 시 공유 상태 정리 / 멀티라이브 launcher 주입 등
    /// "메인 인스턴스 전용" 동작을 자식에서 건너뛰는 데 사용한다.
    /// CommandLine.arguments 기반이라 프로세스 lifetime 동안 불변.
    let isChildInstance: Bool

    init() {
        self.isChildInstance = AppLaunchModeParser.detect().isChild
    }

    // MARK: - Published Properties

    var isInitialized = false
    var isLoggedIn = false
    /// [2026-04-19] 자식 프로세스(분리 인스턴스) 대응: `authManager.initialize()`가 완료되어
    /// 키체인/WebKit에서 NID 쿠키 복원이 끝났는지 여부. 채팅 WebSocket 연결 시 쿠키 헤더 주입에
    /// 사용되므로, 채팅 시작 전 이 플래그를 대기해야 로그인 상태가 정확히 반영된다.
    var isAuthInitialized = false
    var userNickname: String?
    var userChannelId: String?
    var userProfileURL: URL?
    let launchTime = Date()

    /// 서버 401 응답으로 세션이 만료될 때 true → .alert 표시
    var sessionExpiredAlert = false

    /// 커맨드 팔레트 표시 여부 (⌘K)
    var showCommandPalette = false

    /// 키보드 단축키 도움말 시트 표시 여부
    var showKeyboardShortcutsHelp = false

    /// CView 정보 패널 표시 여부
    var showAboutPanel = false

    /// 앱이 현재 활성 상태(포커스)인지 여부
    var isAppActive: Bool = true

    /// 새 창(player-window)으로 분리돼 재생 중인 채널 ID 집합
    /// 메인 LiveStreamView가 사라질 때 이 집합에 포함된 채널은 스트림을 중단하지 않음
    var detachedChannelIds: Set<String> = []

    /// [Plan 2026-04-30 ACT-1] 메트릭 사이드바로 진입 후 특정 탭으로 점프하기 위한 pending 값.
    /// MetricsDashboardView가 소비 후 nil로 비운다.
    var pendingMetricsTab: MetricsDashboardTab?

    /// [Plan 2026-04-30 ACT-1] CommandPalette/DeepLink/Widget/AppIntent가 공유하는
    /// 단일 액션 dispatcher. `bindActionRegistry(router:)` 로 라우터 주입 후 사용.
    var actionRegistry: CViewActionRegistry?

    /// [Plan 2026-04-30 SES-1] AppLifecycle 에서 router 접근용 weak 참조.
    /// `bindActionRegistry(router:)` 시 함께 설정된다.
    weak var router: AppRouter?

    /// 액션 레지스트리를 주입한다. App 진입 시 `AppRouter`가 만들어진 직후 1회 호출.
    func bindActionRegistry(router: AppRouter) {
        self.router = router
        self.actionRegistry = CViewActionRegistry(router: router, appState: self)
    }

    // MARK: - Workspace Snapshot (SES-1)

    /// 현재 워크스페이스 상태를 스냅샷으로 캡처.
    /// router 가 nil 이면 sidebar/검색 query 는 비어있는 상태로 저장.
    func captureWorkspaceSnapshot(router: AppRouter?) -> WorkspaceSnapshot {
        var snap = WorkspaceSnapshot()
        snap.sidebar = router?.selectedSidebarItem.rawValue
        snap.hubMode = followingViewState.hubMode.rawValue
        snap.multiLiveChannelIds = multiLiveManager.sessions.map { $0.channelId }
        snap.multiChatChannelIds = followingViewState.chatSessionManager.sessions.map { $0.id }
        snap.pendingSearchQuery = router?.pendingSearchQuery
        snap.pendingMetricsTab = pendingMetricsTab?.rawValue
        snap.smartQueueChannelIds = followingViewState.smartQueueChannelIds
        return snap
    }

    /// 저장된 스냅샷을 워크스페이스에 적용.
    /// - 멀티라이브/멀티채팅 세션은 비어있을 때만 복원 (이미 진행중이면 덮어쓰지 않음)
    func applyWorkspaceSnapshot(_ snap: WorkspaceSnapshot, router: AppRouter) {
        if let raw = snap.sidebar,
           let item = AppRouter.SidebarItem(rawValue: raw) {
            router.selectedSidebarItem = item
        }
        if let raw = snap.hubMode,
           let mode = FollowingHubMode(rawValue: raw) {
            followingViewState.applyHubModePreset(mode, multiLiveManager: multiLiveManager)
        }
        if let q = snap.pendingSearchQuery, !q.isEmpty {
            router.pendingSearchQuery = q
        }
        if let raw = snap.pendingMetricsTab,
           let tab = MetricsDashboardTab(rawValue: raw) {
            pendingMetricsTab = tab
        }
        // 멀티라이브 세션 복원 (현재 비어있을 때만)
        //
        // [Bug-fix 2026-05-01] 워크스페이스 스냅샷의 `multiLiveChannelIds` 는
        // `captureWorkspaceSnapshot` 에서 `multiLiveManager.sessions.map { $0.channelId }` 로만
        // 채워지므로 **임베디드(in-process) 세션** 의 채널이다. 복원 시에도 반드시 `.embedded` 로
        // 강제해야, 사용자가 `useSeparateProcesses=true` (기본값) 로 설정해 둔 상태에서도
        // 자식 프로세스를 새로 띄우지 않고 부모 윈도우 내 멀티라이브 그리드로 그대로 복원된다.
        // 이전에는 override 미지정으로 launcher 분기를 타 "분할 인스턴스가 자동 재생되는" 회귀가 발생했다.
        if multiLiveManager.sessions.isEmpty, !snap.multiLiveChannelIds.isEmpty {
            for cid in snap.multiLiveChannelIds {
                Task { @MainActor in
                    await multiLiveManager.addSession(channelId: cid, presentationOverride: .embedded)
                }
            }
        }
        if !snap.smartQueueChannelIds.isEmpty {
            followingViewState.smartQueueChannelIds = snap.smartQueueChannelIds
        }
        // 멀티채팅은 액세스토큰 등 부수효과가 커서 v1에서는 sidebar/hubMode/multiLive 까지만 복원
    }

    /// 비동기 저장 헬퍼.
    func persistWorkspaceSnapshot(router: AppRouter?) {
        let snap = captureWorkspaceSnapshot(router: router)
        Task.detached(priority: .utility) {
            await WorkspaceStateStore.shared.save(snap)
        }
    }

    // MARK: - ViewModels & Stores

    var homeViewModel: HomeViewModel?
    var chatViewModel: ChatViewModel?
    var playerViewModel: PlayerViewModel?
    var settingsStore: SettingsStore = SettingsStore()
    let multiLiveManager = MultiLiveManager()

    /// 멀티라이브 자식 프로세스 launcher (각 채널을 별도 CView 인스턴스로 띄울 때 사용)
    let multiLiveLauncher = MultiLiveProcessLauncher()

    /// 라이브(팔로잉) 메뉴 영속 상태 — 메뉴 전환 시에도 설정/패널/채팅 유지
    let followingViewState = FollowingViewState()

    /// 공유 성능 모니터 (LiveStreamView → MetricsForwarder 모두 같은 인스턴스 사용)
    let performanceMonitor = PerformanceMonitor()

    /// 메트릭 포워더 (채널 시청 시 서버로 메트릭 전송)
    var metricsForwarder: MetricsForwarder?
    /// MetricsAPIClient 참조 (설정 변경 시 URL 업데이트용)
    var metricsClient: MetricsAPIClient?

    /// 백그라운드 팔로잉 업데이트 서비스
    let backgroundUpdateService = BackgroundUpdateService()

    /// 자동 업데이트 서비스 (GitHub Releases 기반 앱 버전 업데이트)
    let updateService = UpdateService()

    /// HLS 매니페스트 프리페치 서비스 (채널 카드 호버 시 사전 로드)
    var hlsPrefetchService: HLSPrefetchService?

    // MARK: - Cached Basic Emoticons (앱 시작 시 프리로드)

    /// 프리로드된 기본 이모티콘 팩 (전 채널 공통)
    var cachedBasicEmoticonPacks: [EmoticonPack] = []

    /// 프리로드된 기본 이모티콘 맵 (emoticonId → imageURL)
    var cachedBasicEmoticonMap: [String: String] = [:]

    // MARK: - Internal Services

    /// 공유 서비스 — View에서 접근 가능
    var apiClient: ChzzkAPIClient?
    var authManager: AuthManager?
    var dataStore: CViewPersistence.DataStore?
    let logger = AppLogger.app

    /// 앱 활성/비활성 알림 옵저버
    var appActiveObserver: (any NSObjectProtocol)?
    var appResignObserver: (any NSObjectProtocol)?
    var sessionExpiryObserver: (any NSObjectProtocol)?
    var deminiaturizeObserver: (any NSObjectProtocol)?
    var terminateObserver: (any NSObjectProtocol)?
    /// 스트림 보정 모드 변경 옵저버 — 멀티라이브 세션 재시작용
    var streamProxyModeObserver: (any NSObjectProtocol)?
    /// 전원 소스(AC↔Battery) 변경 옵저버 — P-core/E-core QoS 동적 전환 로깅용
    var powerSourceObserver: (any NSObjectProtocol)?
    /// 창 가림 상태(occlusion) 변경 옵저버 — 백그라운드 가림 시 화질 재확인용
    var windowOcclusionObserver: (any NSObjectProtocol)?
    /// Low Power Mode 변경 옵저버 — 비선택 세션 추가 다운스케일 재적용용 (Phase E)
    var lowPowerModeObserver: (any NSObjectProtocol)?
    /// Thermal State 변경 옵저버 — serious/critical 시 GPU 렌더 티어 자동 강등 (Phase F)
    var thermalStateObserver: (any NSObjectProtocol)?

    /// App Nap 방지 activity 토큰 — 재생 중 시스템 절전 및 스로틀링 방지
    var playbackActivity: NSObjectProtocol?

    /// 백그라운드 진입 시각 — 포그라운드 복귀 시 체류 시간 산출용
    var _backgroundEntryTime: Date?

    /// [Tune] 장기 idle으로 인한 메트릭 WS 단절 예약 Task
    var longIdleSuspendTask: Task<Void, Never>?

    // MARK: - Detached Channels

    func registerDetachedChannel(_ channelId: String) {
        detachedChannelIds.insert(channelId)
    }

    func unregisterDetachedChannel(_ channelId: String) {
        detachedChannelIds.remove(channelId)
    }

    // MARK: - Responsibility Splits
    //
    // 인증/로그인/프로필 로직 → AppState+Auth.swift
    // 메트릭 설정/테스트 로직 → AppState+Metrics.swift
    // 라이프사이클(앱 활성/비활성, 백그라운드 업데이트, 옵저버) → AppLifecycle.swift
}
