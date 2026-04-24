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
