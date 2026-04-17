// MARK: - CViewAuth/AuthManager.swift
// 통합 인증 관리자 — 쿠키 + OAuth 하이브리드

import Foundation
import CViewCore
import CViewNetworking

/// 통합 인증 관리자 (actor 기반)
/// 쿠키 기반 네이버 로그인과 치지직 OAuth 토큰 인증을 모두 지원합니다.
public actor AuthManager: AuthTokenProvider {
    private let cookieManager: CookieManager
    private let keychainService: KeychainService
    public let oauthService: ChzzkOAuthService

    private var _authState: AuthState = .loggedOut
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    
    /// OAuth 토큰 (메모리 캐시)
    private var _oauthTokens: OAuthTokens?
    
    // MARK: - Token Auto-Rotation
    
    /// 자동 토큰 갱신 백그라운드 태스크
    private var tokenRefreshTask: Task<Void, Never>?
    /// 동시 갱신 방지 — in-flight refresh Task 공유 (이전 isRefreshing flag + sleep 대체)
    private var inFlightRefresh: Task<Bool, Never>?

    public init(
        cookieManager: CookieManager = CookieManager(),
        keychainService: KeychainService = KeychainService(),
        oauthService: ChzzkOAuthService = ChzzkOAuthService()
    ) {
        self.cookieManager = cookieManager
        self.keychainService = keychainService
        self.oauthService = oauthService
    }

    // MARK: - AuthTokenProvider

    public var cookies: [HTTPCookie]? {
        get async {
            let cookies = await cookieManager.authCookies
            return cookies.isEmpty ? nil : cookies
        }
    }
    
    public var accessToken: String? {
        get async {
            // 만료되지 않은 OAuth 토큰이 있으면 반환
            if let tokens = _oauthTokens, !tokens.isExpired {
                return tokens.accessToken
            }
            // 만료된 경우 자동 갱신 시도
            if _oauthTokens != nil {
                if await refreshOAuthTokenIfNeeded() {
                    return _oauthTokens?.accessToken
                }
            }
            return nil
        }
    }

    public var isAuthenticated: Bool {
        get async {
            _authState.isLoggedIn
        }
    }
    
    /// 현재 OAuth 토큰 (읽기 전용)
    public var oauthTokens: OAuthTokens? { _oauthTokens }

    // MARK: - State

    public var authState: AuthState { _authState }

    /// 인증 상태 스트림 (multiple observers 지원)
    public var authStateStream: AsyncStream<AuthState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(_authState)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func updateState(_ state: AuthState) {
        _authState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
        Log.auth.info("Auth state: \(String(describing: state))")
    }

    // MARK: - Login / Logout

    /// 초기화 시 기존 인증 복원 시도 (쿠키 항상 복원 + OAuth 토큰)
    public func initialize() async {
        Log.auth.info("Initializing auth...")

        // 1. 쿠키 항상 복원 (내부 API는 쿠키 인증 필수)
        var cookieRestored = await cookieManager.restoreCookiesFromKeychain()
        Log.auth.info("Cookie restore from keychain: \(cookieRestored)")

        // 키체인 복원 실패 시 WKWebView 영구 저장소에서 추출 시도
        if !cookieRestored {
            cookieRestored = await cookieManager.syncFromWebKitStore()
            Log.auth.info("Cookie restore from WebKit: \(cookieRestored)")
        }

        // 2. OAuth 토큰 복원 시도
        if let storedTokens = await oauthService.loadStoredTokens() {
            if !storedTokens.isExpired {
                _oauthTokens = storedTokens
                updateState(.loggedIn(userId: "oauth"))
                scheduleTokenAutoRefresh()
                Log.auth.info("Auth restored from OAuth tokens (cookies: \(cookieRestored))")
                return
            }
            
            // 만료된 경우 갱신 시도
            if let refreshToken = storedTokens.refreshToken {
                do {
                    let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
                    _oauthTokens = newTokens
                    updateState(.loggedIn(userId: "oauth"))
                    scheduleTokenAutoRefresh()
                    Log.auth.info("Auth restored via token refresh (cookies: \(cookieRestored))")
                    return
                } catch {
                    Log.auth.warning("Token refresh failed: \(error.localizedDescription)")
                    await oauthService.clearStoredTokens()
                }
            }
        }

        // 3. 쿠키만으로 로그인
        if cookieRestored {
            updateState(.loggedIn(userId: "cookie"))
            Log.auth.info("Auth restored from cookies only")
        } else {
            updateState(.loggedOut)
        }
    }

    /// 쿠키 기반 로그인 완료 처리 (WKWebView에서 쿠키 획득 후 호출)
    public func handleLoginSuccess() async {
        do {
            try await cookieManager.saveCookiesToKeychain()
        } catch {
            Log.auth.warning("키체인 쿠키 저장 실패 (로그인은 계속 진행): \(error.localizedDescription)")
        }
        await syncNidCookiesToServer()
        updateState(.loggedIn(userId: "cookie"))
    }
    
    /// OAuth 로그인 완료 처리 (authorization code 교환 후 호출)
    public func handleOAuthLoginSuccess(code: String) async throws {
        updateState(.loggingIn)
        
        do {
            let tokens = try await oauthService.exchangeCodeForTokens(code: code)
            _oauthTokens = tokens
            
            // OAuth 로그인 시 WebView에서 추출된 쿠키도 키체인에 저장
            // (api.chzzk.naver.com 내부 API는 쿠키 인증을 사용)
            let hasCookies = await cookieManager.hasCookies
            Log.auth.info("OAuth login: NID cookies in HTTPCookieStorage = \(hasCookies)")
            
            if hasCookies {
                do {
                    try await cookieManager.saveCookiesToKeychain()
                    Log.auth.info("OAuth login: cookies saved to keychain")
                } catch {
                    Log.auth.error("OAuth login: keychain save failed: \(error.localizedDescription)")
                }
                await syncNidCookiesToServer()
            } else {
                Log.auth.warning("OAuth login: no NID cookies — 팔로잉 조회는 네이버 로그인 필요")
            }
            
            updateState(.loggedIn(userId: "oauth"))
            scheduleTokenAutoRefresh()
            Log.auth.info("OAuth login success (cookies: \(hasCookies))")
        } catch {
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    // MARK: - NID Cookie Server Sync
    
    /// NID 쿠키를 대시보드 서버에 동기화 (실패해도 로그인은 유지)
    private func syncNidCookiesToServer() async {
        let cookies = await cookieManager.authCookies
        guard let nidAut = cookies.first(where: { $0.name == "NID_AUT" })?.value,
              let nidSes = cookies.first(where: { $0.name == "NID_SES" })?.value else {
            return
        }
        do {
            let payload = AuthCookieSyncPayload(nidAut: nidAut, nidSes: nidSes)
            let response = try await MetricsAPIClient().syncAuthCookies(payload)
            if response.success {
                Log.auth.info("NID 쿠키 서버 동기화 성공 (userIdHash: \(response.userIdHash?.prefix(8) ?? "nil"))")
            } else {
                Log.auth.warning("NID 쿠키 서버 동기화 실패: \(response.message ?? "unknown")")
            }
        } catch {
            Log.auth.warning("NID 쿠키 서버 동기화 오류 (로그인은 유지): \(error.localizedDescription)")
        }
    }
    
    /// OAuth 토큰 갱신
    public func refreshOAuthTokenIfNeeded() async -> Bool {
        guard let tokens = _oauthTokens else { return false }
        
        // 아직 유효하면 갱신 불필요
        if !tokens.isExpired { return true }

        // [Fix] in-flight Task 공유 — 동시 호출자는 실제 갱신 1회만 수행하고 결과 await
        if let existing = inFlightRefresh {
            return await existing.value
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performTokenRefresh(tokens: tokens)
        }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    private func performTokenRefresh(tokens: OAuthTokens) async -> Bool {
        guard let refreshToken = tokens.refreshToken else {
            Log.auth.warning("No refresh token available")
            updateState(.expired)
            return false
        }
        
        do {
            let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
            _oauthTokens = newTokens
            updateState(.loggedIn(userId: "oauth"))
            scheduleTokenAutoRefresh()
            return true
        } catch {
            Log.auth.error("Token refresh failed: \(error.localizedDescription)")
            updateState(.expired)
            return false
        }
    }

    /// 로그아웃 (쿠키 + OAuth 모두)
    public func logout() async {
        cancelTokenAutoRefresh()
        await cookieManager.clearCookies()
        await oauthService.clearStoredTokens()
        _oauthTokens = nil
        updateState(.loggedOut)
        Log.auth.info("Logged out (cookies + OAuth)")
    }

    /// OAuth 사용자 프로필 조회
    public func fetchOAuthProfile() async throws -> OAuthUserProfile {
        guard let tokens = _oauthTokens else {
            throw AuthError.oauthFailed("No OAuth tokens")
        }
        return try await oauthService.fetchUserProfile(accessToken: tokens.accessToken)
    }
    
    /// 인증 상태 검증
    public func validateAuth() async -> Bool {
        // OAuth 토큰 검증
        if let tokens = _oauthTokens {
            if !tokens.isExpired {
                return await oauthService.validateToken(tokens.accessToken)
            }
            // 만료 시 갱신 시도
            return await refreshOAuthTokenIfNeeded()
        }
        
        // 쿠키 검증
        return await cookieManager.hasCookies
    }
    
    // MARK: - Token Auto-Rotation (S1)
    
    /// 토큰 자동 갱신 스케줄링
    /// - ContinuousClock 사용: 시스템 슬립 중에도 wall-clock 시간이 흘러
    ///   슬립 후 깨어났을 때 즉시 갱신 실행
    /// - 만료 15분 전에 갱신 시도, 이미 갱신 윈도우 안이면 즉시 실행
    private func scheduleTokenAutoRefresh() {
        // 기존 스케줄 취소
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        
        guard let tokens = _oauthTokens, !tokens.isExpired else { return }
        guard tokens.refreshToken != nil else {
            Log.auth.info("No refresh token — auto-rotation disabled")
            return
        }
        
        let expiresAt = tokens.expiresAt
        // 만료 15분 전
        let refreshAt = expiresAt.addingTimeInterval(-15 * 60)
        let delay = refreshAt.timeIntervalSinceNow
        
        if delay <= 0 {
            // 이미 갱신 윈도우 안 — 즉시 갱신
            Log.auth.info("Token within refresh window — refreshing now")
            tokenRefreshTask = Task {
                await self.performAutoRefresh()
            }
            return
        }
        
        Log.auth.info("Token auto-refresh scheduled in \(Int(delay))s (expires at \(expiresAt))")
        
        tokenRefreshTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay), clock: .continuous)
            } catch {
                return // Task cancelled
            }
            guard !Task.isCancelled else { return }
            await self.performAutoRefresh()
        }
    }
    
    /// 자동 토큰 갱신 실행 (최대 2회 시도)
    /// - 1차 실패 시 30초 후 재시도
    /// - 2차 실패 시 세션 만료 상태로 전환
    private func performAutoRefresh() async {
        // [Fix] in-flight Task가 있으면 중복 갱신 방지 — 결과만 await
        if let existing = inFlightRefresh {
            _ = await existing.value
            return
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performAutoRefreshAttempts()
        }
        inFlightRefresh = task
        _ = await task.value
        inFlightRefresh = nil
    }

    private func performAutoRefreshAttempts() async -> Bool {
        guard let tokens = _oauthTokens, let refreshToken = tokens.refreshToken else {
            Log.auth.warning("No refresh token available for auto-refresh")
            updateState(.expired)
            return false
        }
        
        // 1차 시도
        do {
            let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
            _oauthTokens = newTokens
            updateState(.loggedIn(userId: "oauth"))
            Log.auth.info("Token auto-refresh succeeded")
            scheduleTokenAutoRefresh()
            return true
        } catch {
            Log.auth.warning("Token auto-refresh attempt 1 failed: \(error.localizedDescription)")
        }
        
        // 30초 대기 후 재시도
        do {
            try await Task.sleep(for: .seconds(30), clock: .continuous)
        } catch {
            return false // Task cancelled
        }
        guard !Task.isCancelled else { return false }
        
        // 2차 시도
        do {
            let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
            _oauthTokens = newTokens
            updateState(.loggedIn(userId: "oauth"))
            Log.auth.info("Token auto-refresh succeeded (attempt 2)")
            scheduleTokenAutoRefresh()
            return true
        } catch {
            Log.auth.error("Token auto-refresh failed permanently: \(error.localizedDescription)")
            updateState(.expired)
            return false
        }
    }
    
    /// 토큰 자동 갱신 취소 (로그아웃 시 호출)
    private func cancelTokenAutoRefresh() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
    }
}
