// MARK: - CViewAuth/AuthManager.swift
// 통합 인증 관리자 — 쿠키 + OAuth 하이브리드

import Foundation
import CViewCore

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
                Log.auth.info("Auth restored from OAuth tokens (cookies: \(cookieRestored))")
                return
            }
            
            // 만료된 경우 갱신 시도
            if let refreshToken = storedTokens.refreshToken {
                do {
                    let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
                    _oauthTokens = newTokens
                    updateState(.loggedIn(userId: "oauth"))
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
            } else {
                Log.auth.warning("OAuth login: no NID cookies — 팔로잉 조회는 네이버 로그인 필요")
            }
            
            updateState(.loggedIn(userId: "oauth"))
            Log.auth.info("OAuth login success (cookies: \(hasCookies))")
        } catch {
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    /// OAuth 토큰 갱신
    public func refreshOAuthTokenIfNeeded() async -> Bool {
        guard let tokens = _oauthTokens else { return false }
        
        // 아직 유효하면 갱신 불필요
        if !tokens.isExpired { return true }
        
        guard let refreshToken = tokens.refreshToken else {
            Log.auth.warning("No refresh token available")
            updateState(.expired)
            return false
        }
        
        do {
            let newTokens = try await oauthService.refreshTokens(refreshToken: refreshToken)
            _oauthTokens = newTokens
            updateState(.loggedIn(userId: "oauth"))
            return true
        } catch {
            Log.auth.error("Token refresh failed: \(error.localizedDescription)")
            updateState(.expired)
            return false
        }
    }

    /// 로그아웃 (쿠키 + OAuth 모두)
    public func logout() async {
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
}
