// MARK: - OAuthModelsTests.swift
// CViewAuth — OAuthConfig, OAuthTokens 모델 테스트

import Testing
import Foundation
@testable import CViewAuth

// MARK: - OAuthConfig Tests

@Suite("OAuthConfig")
struct OAuthConfigTests {

    @Test("chzzk 프리셋 값 확인")
    func chzzkPreset() {
        let cfg = OAuthConfig.chzzk
        #expect(cfg.clientId == "a6e68dba-8cb1-4dd1-9695-a996200765f6")
        #expect(cfg.loopbackPort == 52735)
        #expect(cfg.redirectURI == "http://localhost:52735/callback")
        #expect(cfg.authBaseURL == "https://chzzk.naver.com/account-interlock")
        #expect(cfg.tokenURL == "https://openapi.chzzk.naver.com/auth/v1/token")
    }

    @Test("buildAuthURL 구성 확인")
    func buildAuthURL() {
        let cfg = OAuthConfig(
            clientId: "test-client",
            clientSecret: "secret",
            redirectURI: "http://localhost:9999/cb",
            loopbackPort: 9999
        )
        let url = cfg.buildAuthURL(state: "abc123")
        #expect(url != nil)

        let urlStr = url!.absoluteString
        #expect(urlStr.contains("clientId=test-client"))
        #expect(urlStr.contains("state=abc123"))
        #expect(urlStr.contains("redirectUri="))
        #expect(urlStr.hasPrefix("https://chzzk.naver.com/account-interlock"))
    }

    @Test("buildAuthURL — 커스텀 base URL")
    func buildAuthURLCustomBase() {
        let cfg = OAuthConfig(
            clientId: "c1",
            clientSecret: "s1",
            redirectURI: "http://localhost:8080/auth",
            loopbackPort: 8080,
            authBaseURL: "https://example.com/oauth"
        )
        let url = cfg.buildAuthURL(state: "s")
        #expect(url != nil)
        #expect(url!.absoluteString.hasPrefix("https://example.com/oauth"))
    }

    @Test("buildAuthURL — state에 특수문자")
    func buildAuthURLSpecialState() {
        let cfg = OAuthConfig.chzzk
        let url = cfg.buildAuthURL(state: "a+b=c&d")
        #expect(url != nil)
        // URL이 생성되기만 하면 OK (percent encoding은 URL 파서가 처리)
    }

    @Test("커스텀 init 기본값 확인")
    func customInitDefaults() {
        let cfg = OAuthConfig(
            clientId: "id",
            clientSecret: "sec",
            redirectURI: "http://localhost:1234/cb",
            loopbackPort: 1234
        )
        #expect(cfg.authBaseURL == "https://chzzk.naver.com/account-interlock")
        #expect(cfg.tokenURL == "https://openapi.chzzk.naver.com/auth/v1/token")
    }
}

// MARK: - OAuthTokens Tests

@Suite("OAuthTokens — 만료 처리")
struct OAuthTokensExpirationTests {

    @Test("expiresAt 계산")
    func expiresAtComputed() {
        let tokens = OAuthTokens(
            accessToken: "at",
            refreshToken: "rt",
            expiresIn: 3600
        )
        // createdAt 기준 + 3600초 = expiresAt
        let diff = tokens.expiresAt.timeIntervalSince(tokens.createdAt)
        #expect(abs(diff - 3600) < 1.0)
    }

    @Test("방금 생성된 토큰은 만료되지 않음")
    func freshTokenNotExpired() {
        let tokens = OAuthTokens(
            accessToken: "fresh",
            refreshToken: nil,
            expiresIn: 3600
        )
        #expect(!tokens.isExpired)
    }

    @Test("expiresIn=0 이면 즉시 만료")
    func zeroExpiresInIsExpired() {
        let tokens = OAuthTokens(
            accessToken: "zero",
            refreshToken: nil,
            expiresIn: 0
        )
        #expect(tokens.isExpired)
    }

    @Test("expiresIn 30초 이하면 만료 간주 (30초 버퍼)")
    func bufferEdgeCase() {
        let tokens = OAuthTokens(
            accessToken: "edge",
            refreshToken: "rt",
            expiresIn: 29
        )
        // 30초 버퍼이므로 29초 남은 토큰은 만료
        #expect(tokens.isExpired)
    }

    @Test("tokenType 기본값 Bearer")
    func defaultTokenType() {
        let tokens = OAuthTokens(
            accessToken: "a",
            refreshToken: nil,
            expiresIn: 100
        )
        #expect(tokens.tokenType == "Bearer")
    }

    @Test("refreshToken nil 허용")
    func refreshTokenOptional() {
        let tokens = OAuthTokens(
            accessToken: "a",
            refreshToken: nil,
            expiresIn: 100
        )
        #expect(tokens.refreshToken == nil)
    }
}

// MARK: - OAuthTokens Codable

@Suite("OAuthTokens — Codable")
struct OAuthTokensCodableTests {

    @Test("Codable 왕복 보존")
    func codableRoundTrip() throws {
        let original = OAuthTokens(
            accessToken: "access-xyz",
            refreshToken: "refresh-abc",
            expiresIn: 7200
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)

        #expect(decoded.accessToken == original.accessToken)
        #expect(decoded.refreshToken == original.refreshToken)
        #expect(decoded.expiresIn == original.expiresIn)
        #expect(decoded.tokenType == original.tokenType)
        #expect(abs(decoded.createdAt.timeIntervalSince(original.createdAt)) < 1.0)
    }

    @Test("refreshToken nil 인코딩/디코딩")
    func codableNilRefreshToken() throws {
        let original = OAuthTokens(
            accessToken: "a",
            refreshToken: nil,
            expiresIn: 60
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)

        #expect(decoded.refreshToken == nil)
        #expect(decoded.accessToken == "a")
    }

    @Test("KeychainService 통해 OAuthTokens 저장/로드")
    func keychainRoundTrip() async throws {
        let svc = KeychainService()
        let key = "test-oauth-tokens-\(UUID().uuidString)"
        let tokens = OAuthTokens(
            accessToken: "kc-access",
            refreshToken: "kc-refresh",
            expiresIn: 1800
        )

        try await svc.saveCodable(key: key, value: tokens)
        let loaded = try await svc.loadCodable(key: key, as: OAuthTokens.self)

        #expect(loaded != nil)
        #expect(loaded!.accessToken == tokens.accessToken)
        #expect(loaded!.refreshToken == tokens.refreshToken)
        #expect(loaded!.expiresIn == tokens.expiresIn)
        try await svc.delete(key: key)
    }
}

// MARK: - OAuthTokenResponse Tests

@Suite("OAuthTokenResponse — JSON 디코딩")
struct OAuthTokenResponseTests {

    @Test("성공 응답 디코딩")
    func decodeSuccess() throws {
        let json = """
        {
            "code": 200,
            "content": {
                "accessToken": "at-123",
                "refreshToken": "rt-456",
                "expiresIn": 3600,
                "tokenType": "Bearer"
            },
            "message": null
        }
        """
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: Data(json.utf8))
        #expect(response.code == 200)
        #expect(response.content?.accessToken == "at-123")
        #expect(response.content?.refreshToken == "rt-456")
        #expect(response.content?.expiresIn == 3600)
        #expect(response.content?.tokenType == "Bearer")
    }

    @Test("에러 응답 디코딩")
    func decodeError() throws {
        let json = """
        {
            "code": 401,
            "content": null,
            "message": "Unauthorized"
        }
        """
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: Data(json.utf8))
        #expect(response.code == 401)
        #expect(response.content == nil)
        #expect(response.message == "Unauthorized")
    }

    @Test("refreshToken 없는 응답")
    func decodeNoRefreshToken() throws {
        let json = """
        {
            "code": 200,
            "content": {
                "accessToken": "at",
                "expiresIn": 600,
                "tokenType": "Bearer"
            }
        }
        """
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: Data(json.utf8))
        #expect(response.content?.refreshToken == nil)
        #expect(response.content?.accessToken == "at")
    }
}

// MARK: - OAuthProfileResponse Tests

@Suite("OAuthProfileResponse — JSON 디코딩")
struct OAuthProfileResponseTests {

    @Test("프로필 응답 디코딩")
    func decodeProfile() throws {
        let json = """
        {
            "code": 200,
            "content": {
                "channelId": "ch-001",
                "channelName": "테스트채널",
                "nickname": "테스터",
                "profileImageUrl": "https://example.com/img.png",
                "verifiedMark": true
            }
        }
        """
        let response = try JSONDecoder().decode(OAuthProfileResponse.self, from: Data(json.utf8))
        #expect(response.code == 200)
        #expect(response.content?.channelId == "ch-001")
        #expect(response.content?.nickname == "테스터")
        #expect(response.content?.verifiedMark == true)
    }

    @Test("부분 프로필 (일부 필드 null)")
    func decodePartialProfile() throws {
        let json = """
        {
            "code": 200,
            "content": {
                "channelId": "ch-002",
                "channelName": null,
                "nickname": null,
                "profileImageUrl": null,
                "verifiedMark": null
            }
        }
        """
        let response = try JSONDecoder().decode(OAuthProfileResponse.self, from: Data(json.utf8))
        #expect(response.content?.channelId == "ch-002")
        #expect(response.content?.nickname == nil)
        #expect(response.content?.verifiedMark == nil)
    }
}
