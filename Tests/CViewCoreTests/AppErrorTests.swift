// MARK: - AppErrorTests.swift
// CViewCore 에러 타입 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - AppError Tests

@Suite("AppError Comprehensive")
struct AppErrorComprehensiveTests {

    @Test("errorDescription — network")
    func networkDescription() {
        let err = AppError.network(.noConnection)
        #expect(err.errorDescription == "인터넷에 연결되어 있지 않습니다")
    }

    @Test("errorDescription — auth")
    func authDescription() {
        let err = AppError.auth(.notLoggedIn)
        #expect(err.errorDescription == "로그인이 필요합니다")
    }

    @Test("errorDescription — api")
    func apiDescription() {
        let err = AppError.api(.unauthorized)
        #expect(err.errorDescription == "인증이 필요합니다")
    }

    @Test("errorDescription — player")
    func playerDescription() {
        let err = AppError.player(.streamNotFound)
        #expect(err.errorDescription == "스트림을 찾을 수 없습니다")
    }

    @Test("errorDescription — chat")
    func chatDescription() {
        let err = AppError.chat(.notConnected)
        #expect(err.errorDescription == "채팅에 연결되어 있지 않습니다")
    }

    @Test("errorDescription — persistence")
    func persistenceDescription() {
        let err = AppError.persistence(.containerNotLoaded)
        #expect(err.errorDescription == "데이터 저장소가 로드되지 않았습니다")
    }

    @Test("errorDescription — unknown")
    func unknownDescription() {
        let err = AppError.unknown("테스트")
        #expect(err.errorDescription == "알 수 없는 오류: 테스트")
    }

    @Test("recoverySuggestion — 각 케이스별")
    func recoverySuggestions() {
        #expect(AppError.network(.timeout).recoverySuggestion == "네트워크 연결을 확인하고 다시 시도해주세요.")
        #expect(AppError.auth(.notLoggedIn).recoverySuggestion == "다시 로그인해주세요.")
        #expect(AppError.api(.unauthorized).recoverySuggestion == "잠시 후 다시 시도해주세요.")
        #expect(AppError.player(.streamNotFound).recoverySuggestion == "다른 품질로 재생하거나 플레이어를 재시작해보세요.")
        #expect(AppError.chat(.notConnected).recoverySuggestion == "채팅 연결을 다시 시도합니다.")
        #expect(AppError.persistence(.containerNotLoaded).recoverySuggestion == "앱을 재시작해주세요.")
        #expect(AppError.unknown("x").recoverySuggestion == "앱을 재시작해주세요.")
    }
}

// MARK: - NetworkError Tests

@Suite("NetworkError")
struct NetworkErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(NetworkError.noConnection.errorDescription == "인터넷에 연결되어 있지 않습니다")
        #expect(NetworkError.timeout.errorDescription == "요청 시간이 초과되었습니다")
        #expect(NetworkError.dnsResolutionFailed.errorDescription == "DNS 조회 실패")
        #expect(NetworkError.sslError.errorDescription == "보안 연결 오류")
        #expect(NetworkError.invalidURL("http://bad").errorDescription == "잘못된 URL: http://bad")
    }
}

// MARK: - APIError Tests

@Suite("APIError")
struct APIErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(APIError.unauthorized.errorDescription == "인증이 필요합니다")
        #expect(APIError.invalidResponse.errorDescription == "잘못된 응답")
        #expect(APIError.httpError(statusCode: 404).errorDescription == "HTTP 오류: 404")
        #expect(APIError.emptyContent.errorDescription == "빈 응답")
        #expect(APIError.decodingFailed("x").errorDescription == "응답 파싱 실패: x")
        #expect(APIError.networkError("timeout").errorDescription == "네트워크 오류: timeout")
        #expect(APIError.rateLimited(retryAfter: 30).errorDescription == "요청 제한 (30초 후 재시도)")
        #expect(APIError.malformedResponse("bad json").errorDescription == "응답 구조 오류: bad json")
    }

    @Test("Equatable — 동일 케이스")
    func equatable() {
        #expect(APIError.unauthorized == APIError.unauthorized)
        #expect(APIError.httpError(statusCode: 200) == APIError.httpError(statusCode: 200))
        #expect(APIError.httpError(statusCode: 200) != APIError.httpError(statusCode: 404))
        #expect(APIError.rateLimited(retryAfter: 10) == APIError.rateLimited(retryAfter: 10))
        #expect(APIError.rateLimited(retryAfter: 10) != APIError.rateLimited(retryAfter: 30))
    }
}

// MARK: - AuthError Tests

@Suite("AuthError")
struct AuthErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(AuthError.notLoggedIn.errorDescription == "로그인이 필요합니다")
        #expect(AuthError.cookieExpired.errorDescription == "인증 쿠키가 만료되었습니다")
        #expect(AuthError.oauthFailed("reason").errorDescription == "OAuth 인증 실패: reason")
        #expect(AuthError.keychainAccessDenied.errorDescription == "키체인 접근이 거부되었습니다")
        #expect(AuthError.tokenRefreshFailed.errorDescription == "토큰 갱신 실패")
    }
}

// MARK: - ChatError Tests

@Suite("ChatError")
struct ChatErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(ChatError.connectionFailed("timeout").errorDescription == "채팅 연결 실패: timeout")
        #expect(ChatError.authenticationFailed.errorDescription == "채팅 인증 실패")
        #expect(ChatError.sendFailed("오류").errorDescription == "메시지 전송 실패: 오류")
        #expect(ChatError.maxRetriesExceeded.errorDescription == "최대 재연결 시도 횟수 초과")
        #expect(ChatError.invalidChannelId.errorDescription == "잘못된 채널 ID")
        #expect(ChatError.serverError("500").errorDescription == "서버 오류: 500")
        #expect(ChatError.notConnected.errorDescription == "채팅에 연결되어 있지 않습니다")
        #expect(ChatError.invalidMessage.errorDescription == "잘못된 메시지 형식")
    }
}

// MARK: - PersistenceError Tests

@Suite("PersistenceError")
struct PersistenceErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(PersistenceError.saveFailed("disk full").errorDescription == "저장 실패: disk full")
        #expect(PersistenceError.fetchFailed("not found").errorDescription == "조회 실패: not found")
        #expect(PersistenceError.migrationFailed("v2").errorDescription == "마이그레이션 실패: v2")
        #expect(PersistenceError.containerNotLoaded.errorDescription == "데이터 저장소가 로드되지 않았습니다")
    }
}

// MARK: - PlayerError Tests

@Suite("PlayerError")
struct PlayerErrorTests {

    @Test("모든 케이스 errorDescription")
    func allCases() {
        #expect(PlayerError.streamNotFound.errorDescription == "스트림을 찾을 수 없습니다")
        #expect(PlayerError.networkTimeout.errorDescription == "네트워크 연결 시간 초과")
        #expect(PlayerError.decodingFailed("corrupt").errorDescription == "디코딩 실패: corrupt")
        #expect(PlayerError.engineInitFailed.errorDescription == "플레이어 엔진 초기화 실패")
        #expect(PlayerError.unsupportedFormat("mkv").errorDescription == "지원하지 않는 포맷: mkv")
        #expect(PlayerError.hlsParsingFailed("x").errorDescription == "HLS 파싱 실패: x")
        #expect(PlayerError.invalidManifest.errorDescription == "잘못된 매니페스트")
        #expect(PlayerError.connectionLost.errorDescription == "연결이 끊어졌습니다")
        #expect(PlayerError.authRequired.errorDescription == "인증이 필요합니다")
        #expect(PlayerError.recordingFailed("perm").errorDescription == "녹화 실패: perm")
    }
}
