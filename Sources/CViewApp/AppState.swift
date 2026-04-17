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

    /// App Nap 방지 activity 토큰 — 재생 중 시스템 절전 및 스로틀링 방지
    var playbackActivity: NSObjectProtocol?

    /// 백그라운드 진입 시각 — 포그라운드 복귀 시 체류 시간 산출용
    var _backgroundEntryTime: Date?

    // MARK: - Detached Channels

    func registerDetachedChannel(_ channelId: String) {
        detachedChannelIds.insert(channelId)
    }

    func unregisterDetachedChannel(_ channelId: String) {
        detachedChannelIds.remove(channelId)
    }

    // MARK: - Auth & Login

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

    /// 로그아웃 처리
    func handleLogout() async {
        guard let authManager else { return }
        await authManager.logout()
        isLoggedIn = false
        userNickname = nil
        userChannelId = nil
        userProfileURL = nil
        multiLiveManager.updateUserInfo(uid: nil, nickname: nil)
        backgroundUpdateService.stop()
        logger.info("Logged out")
    }

    // MARK: - Metrics

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

        logger.info("Metrics settings applied – enabled: \(ms.metricsEnabled), url: \(ms.serverURL, privacy: .private)")
    }

    // MARK: - User Profile

    /// 사용자 프로필 정보 로드
    func loadUserProfile(apiClient: ChzzkAPIClient) async {
        do {
            let userInfo = try await apiClient.userStatus()
            if userNickname == nil {
                userNickname = userInfo.nickname
            }
            if let imageURL = userInfo.profileImageURL, userProfileURL == nil {
                userProfileURL = URL(string: imageURL)
            }
            // 멀티라이브 채팅 전송용 사용자 정보 동기화
            multiLiveManager.updateUserInfo(uid: userChannelId, nickname: userNickname)
            logger.info("프로필 로드 완료: \(userInfo.nickname ?? "unknown"), channelId: \(self.userChannelId ?? "none")")
        } catch {
            logger.error("프로필 로드 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// OAuth 사용자 프로필 로드 (채널 ID 포함)
    func loadOAuthUserProfile(authManager: AuthManager) async {
        do {
            let profile = try await authManager.fetchOAuthProfile()
            userNickname = profile.nickname ?? userNickname
            userChannelId = profile.channelId
            if let imageURL = profile.profileImageUrl {
                userProfileURL = URL(string: imageURL)
            }
            // 멀티라이브 채팅 전송용 사용자 정보 동기화
            multiLiveManager.updateUserInfo(uid: userChannelId, nickname: userNickname)
            logger.info("OAuth 프로필: \(profile.nickname ?? "unknown"), 채널ID: \(profile.channelId ?? "none")")
        } catch {
            logger.error("OAuth 프로필 로드 실패: \(error.localizedDescription)")
        }
    }
}
