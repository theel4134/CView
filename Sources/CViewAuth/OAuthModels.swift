// MARK: - CViewAuth/OAuthModels.swift
// 치지직 OAuth 모델 — 설정, 토큰, 에러

import Foundation
import CViewCore

// MARK: - OAuth Configuration

/// 치지직 OAuth 설정
public struct OAuthConfig: Sendable {
    public let clientId: String
    public let clientSecret: String
    public let redirectURI: String
    public let loopbackPort: UInt16
    
    /// 치지직 OAuth 인증 URL
    public let authBaseURL: String
    /// 치지직 OAuth 토큰 엔드포인트
    public let tokenURL: String
    
    public init(
        clientId: String,
        clientSecret: String,
        redirectURI: String,
        loopbackPort: UInt16,
        authBaseURL: String = "https://chzzk.naver.com/account-interlock",
        tokenURL: String = "https://openapi.chzzk.naver.com/auth/v1/token"
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.loopbackPort = loopbackPort
        self.authBaseURL = authBaseURL
        self.tokenURL = tokenURL
    }
    
    /// CView_v2 치지직 OAuth 설정
    public static let chzzk = OAuthConfig(
        clientId: "a6e68dba-8cb1-4dd1-9695-a996200765f6",
        clientSecret: "L8VLrG21dYSditcukQfDBZL9-V07vR5o4Br_MxJf0No",
        redirectURI: "http://localhost:52735/callback",
        loopbackPort: 52735
    )
    
    /// OAuth 인증 URL 생성 (state 파라미터 포함)
    public func buildAuthURL(state: String) -> URL? {
        let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI
        let urlString = "\(authBaseURL)?clientId=\(clientId)&redirectUri=\(encodedRedirect)&state=\(state)"
        return URL(string: urlString)
    }
}

// MARK: - OAuth Tokens

/// OAuth 액세스/리프레시 토큰
public struct OAuthTokens: Codable, Sendable {
    public let accessToken: String
    public var refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String
    public let createdAt: Date
    
    public init(
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int,
        tokenType: String = "Bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.createdAt = Date()
    }
    
    /// 토큰 만료 시점
    public var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }
    
    /// 토큰이 만료되었는지 (30초 버퍼)
    public var isExpired: Bool {
        Date().addingTimeInterval(30) > expiresAt
    }
}

// MARK: - Token Response (서버 JSON 응답)

/// 치지직 OAuth 토큰 교환 응답
struct OAuthTokenResponse: Decodable {
    let code: Int?
    let content: TokenContent?
    let message: String?
    
    struct TokenContent: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let tokenType: String
    }
}

// MARK: - OAuth User Profile

/// OAuth 사용자 프로필 응답
struct OAuthProfileResponse: Decodable {
    let code: Int?
    let content: OAuthUserProfile?
    let message: String?
}

/// OAuth 사용자 프로필 정보
public struct OAuthUserProfile: Decodable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let nickname: String?
    public let profileImageUrl: String?
    public let verifiedMark: Bool?
}
