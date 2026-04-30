// MARK: - AppState+Auth.swift
// AppState의 인증/로그인/프로필 책임 분리 (Refactor P1-5)
//
// 분리 이유:
// - AppState 본체는 상태 컨테이너 역할만 유지
// - Auth 흐름(쿠키/OAuth/Logout/Profile 로드)은 본 extension으로 격리
// - 동일 모듈 내 extension이므로 internal 멤버 접근 가능 (캡슐화 손상 없음)

import Foundation
import CViewCore
import CViewNetworking
import CViewAuth

@MainActor
extension AppState {

    // MARK: - Login

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

        // [Widget 2026-04-24] 로그인 상태 변화 → 위젯 즉시 갱신
        scheduleWidgetSnapshotUpdate()
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

        // [Widget 2026-04-24] OAuth 로그인 후 위젯 즉시 갱신
        scheduleWidgetSnapshotUpdate()
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
        followingViewState.chatSessionManager.updateUserInfo(uid: nil, nickname: nil)
        backgroundUpdateService.stop()
        logger.info("Logged out")

        // [Widget 2026-04-24] 로그아웃 → 위젯 비로그인 상태로 즉시 갱신
        scheduleWidgetSnapshotUpdate()
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
            // 멀티채팅 세션의 chatViewModel에도 userIdHash 전파 — canSendChat 활성화
            // (userChannelId는 OAuth 로그인 시에만 설정되므로 쿠키 로그인에서는 userIdHash 사용)
            followingViewState.chatSessionManager.updateUserInfo(
                uid: userInfo.userIdHash ?? userChannelId,
                nickname: userNickname
            )
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
            // 멀티채팅 세션의 chatViewModel에도 사용자 정보 전파 — canSendChat 활성화
            followingViewState.chatSessionManager.updateUserInfo(
                uid: userChannelId,
                nickname: userNickname
            )
            logger.info("OAuth 프로필: \(profile.nickname ?? "unknown"), 채널ID: \(profile.channelId ?? "none")")
        } catch {
            logger.error("OAuth 프로필 로드 실패: \(error.localizedDescription)")
        }
    }
}
