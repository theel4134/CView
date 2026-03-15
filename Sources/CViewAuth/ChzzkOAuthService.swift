// MARK: - CViewAuth/ChzzkOAuthService.swift
// 치지직 OAuth 서비스 — 토큰 교환, 갱신, 검증

import Foundation
import CViewCore

/// 치지직 OAuth 서비스 (actor 기반)
public actor ChzzkOAuthService {
    private let config: OAuthConfig
    private let keychainService: KeychainService
    private let session: URLSession
    
    private var currentState: String?
    
    private static let keychainTokenKey = "oauth_tokens"
    
    public init(
        config: OAuthConfig = .chzzk,
        keychainService: KeychainService = KeychainService()
    ) {
        self.config = config
        self.keychainService = keychainService
        
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 30
        urlConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: urlConfig)
    }
    
    // MARK: - Auth URL
    
    /// OAuth 인증 URL 생성 (state 저장)
    public func generateAuthURL() -> URL? {
        let state = UUID().uuidString
        currentState = state
        return config.buildAuthURL(state: state)
    }
    
    /// 현재 state 값
    public var savedState: String? { currentState }
    
    /// Redirect URI
    public var redirectURI: String { config.redirectURI }
    
    // MARK: - Code Extraction
    
    /// 콜백 URL에서 authorization code 추출
    public func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let queryItems = components.queryItems ?? []
        
        // 에러 확인
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            Log.auth.error("OAuth server error: \(error)")
            return nil
        }
        
        // state 검증 — currentState가 없으면 CSRF 보호를 위해 거부
        let receivedState = queryItems.first(where: { $0.name == "state" })?.value
        guard let expected = currentState else {
            Log.auth.error("OAuth state not set — rejecting callback (CSRF protection)")
            return nil
        }
        guard receivedState == expected else {
            Log.auth.error("OAuth state mismatch (CSRF protection)")
            return nil
        }
        
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            Log.auth.error("No authorization code in callback URL")
            return nil
        }
        
        Log.auth.info("Authorization code extracted: \(LogMask.token(code), privacy: .private)")
        return code
    }
    
    // MARK: - Token Exchange
    
    /// Authorization code를 토큰으로 교환
    public func exchangeCodeForTokens(code: String) async throws -> OAuthTokens {
        guard let state = currentState else {
            throw AuthError.oauthFailed("State parameter missing")
        }
        
        let requestBody: [String: String] = [
            "grantType": "authorization_code",
            "clientId": config.clientId,
            "clientSecret": config.clientSecret,
            "code": code,
            "state": state,
        ]
        
        let tokens = try await performTokenRequest(body: requestBody)
        
        // 키체인에 저장 (실패해도 로그인은 진행 — 토큰은 메모리에 유지)
        do {
            try await keychainService.saveCodable(key: Self.keychainTokenKey, value: tokens)
        } catch {
            Log.auth.warning("키체인 저장 실패 (토큰은 메모리 유지): \(error.localizedDescription)")
        }
        
        // state 초기화
        currentState = nil
        
        Log.auth.info("OAuth tokens exchanged successfully")
        return tokens
    }
    
    // MARK: - Token Refresh
    
    /// 리프레시 토큰으로 액세스 토큰 갱신
    public func refreshTokens(refreshToken: String) async throws -> OAuthTokens {
        let requestBody: [String: String] = [
            "grantType": "refresh_token",
            "clientId": config.clientId,
            "clientSecret": config.clientSecret,
            "refreshToken": refreshToken,
        ]
        
        let tokens = try await performTokenRequest(body: requestBody)
        
        // 키체인에 갱신된 토큰 저장 (실패해도 갱신은 성공)
        do {
            try await keychainService.saveCodable(key: Self.keychainTokenKey, value: tokens)
        } catch {
            Log.auth.warning("키체인 갱신 저장 실패: \(error.localizedDescription)")
        }
        
        Log.auth.info("OAuth tokens refreshed successfully")
        return tokens
    }
    
    // MARK: - Token Validation
    
    /// 액세스 토큰 유효성 검증 (/service/v1/users/me 호출)
    public func validateToken(_ accessToken: String) async -> Bool {
        guard let url = URL(string: "https://api.chzzk.naver.com/service/v1/users/me") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - User Profile
    
    /// OAuth 토큰으로 사용자 프로필 조회 (Open API)
    public func fetchUserProfile(accessToken: String) async throws -> OAuthUserProfile {
        guard let url = URL(string: "https://openapi.chzzk.naver.com/open/v1/users/me") else {
            throw AuthError.oauthFailed("Invalid profile URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AuthError.oauthFailed("Profile fetch failed: HTTP \(statusCode)")
        }
        
        let profileResponse = try JSONDecoder().decode(OAuthProfileResponse.self, from: data)
        
        guard let content = profileResponse.content else {
            throw AuthError.oauthFailed("Empty profile response")
        }
        
        Log.auth.info("OAuth profile: \(content.nickname ?? "unknown") (channel: \(content.channelId ?? "none"))")
        return content
    }
    
    // MARK: - Token Storage
    
    /// 키체인에서 저장된 토큰 로드
    public func loadStoredTokens() async -> OAuthTokens? {
        do {
            return try await keychainService.loadCodable(key: Self.keychainTokenKey, as: OAuthTokens.self)
        } catch {
            Log.auth.error("Failed to load OAuth tokens: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 키체인에서 토큰 삭제
    public func clearStoredTokens() async {
        try? await keychainService.delete(key: Self.keychainTokenKey)
        currentState = nil
        Log.auth.info("OAuth tokens cleared")
    }
    
    // MARK: - Private
    
    private func performTokenRequest(body: [String: String]) async throws -> OAuthTokens {
        guard let url = URL(string: config.tokenURL) else {
            throw AuthError.oauthFailed("Invalid token URL")
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.oauthFailed("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            Log.auth.error("Token request failed: HTTP \(httpResponse.statusCode) - \(LogMask.body(errorBody), privacy: .private)")
            throw AuthError.oauthFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        guard let content = tokenResponse.content else {
            throw AuthError.oauthFailed(tokenResponse.message ?? "Empty token response")
        }
        
        return OAuthTokens(
            accessToken: content.accessToken,
            refreshToken: content.refreshToken,
            expiresIn: content.expiresIn,
            tokenType: content.tokenType
        )
    }
}
