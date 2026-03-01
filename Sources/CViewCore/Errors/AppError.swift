// MARK: - CViewCore/Errors/AppError.swift
// 통합 에러 타입 시스템 — typed throws 지원

import Foundation

/// 앱 최상위 에러 타입
public enum AppError: Error, Sendable, LocalizedError {
    case network(NetworkError)
    case auth(AuthError)
    case api(APIError)
    case player(PlayerError)
    case chat(ChatError)
    case persistence(PersistenceError)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .network(let err): err.errorDescription
        case .auth(let err): err.errorDescription
        case .api(let err): err.errorDescription
        case .player(let err): err.errorDescription
        case .chat(let err): err.errorDescription
        case .persistence(let err): err.errorDescription
        case .unknown(let msg): "알 수 없는 오류: \(msg)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .network: "네트워크 연결을 확인하고 다시 시도해주세요."
        case .auth: "다시 로그인해주세요."
        case .api: "잠시 후 다시 시도해주세요."
        case .player: "다른 품질로 재생하거나 플레이어를 재시작해보세요."
        case .chat: "채팅 연결을 다시 시도합니다."
        case .persistence: "앱을 재시작해주세요."
        case .unknown: "앱을 재시작해주세요."
        }
    }
}

/// 네트워크 에러
public enum NetworkError: Error, Sendable, LocalizedError {
    case noConnection
    case timeout
    case dnsResolutionFailed
    case sslError
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .noConnection: "인터넷에 연결되어 있지 않습니다"
        case .timeout: "요청 시간이 초과되었습니다"
        case .dnsResolutionFailed: "DNS 조회 실패"
        case .sslError: "보안 연결 오류"
        case .invalidURL(let url): "잘못된 URL: \(url)"
        }
    }
}

/// API 에러
public enum APIError: Error, Sendable, LocalizedError, Equatable {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyContent
    case decodingFailed(String)
    case networkError(String)
    case rateLimited(retryAfter: TimeInterval)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "인증이 필요합니다"
        case .invalidResponse: "잘못된 응답"
        case .httpError(let code): "HTTP 오류: \(code)"
        case .emptyContent: "빈 응답"
        case .decodingFailed(let detail): "응답 파싱 실패: \(detail)"
        case .networkError(let msg): "네트워크 오류: \(msg)"
        case .rateLimited(let retryAfter): "요청 제한 (\(Int(retryAfter))초 후 재시도)"
        case .malformedResponse(let detail): "응답 구조 오류: \(detail)"
        }
    }
}

/// 인증 에러
public enum AuthError: Error, Sendable, LocalizedError {
    case notLoggedIn
    case cookieExpired
    case oauthFailed(String)
    case keychainAccessDenied
    case tokenRefreshFailed

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "로그인이 필요합니다"
        case .cookieExpired: "인증 쿠키가 만료되었습니다"
        case .oauthFailed(let detail): "OAuth 인증 실패: \(detail)"
        case .keychainAccessDenied: "키체인 접근이 거부되었습니다"
        case .tokenRefreshFailed: "토큰 갱신 실패"
        }
    }
}

/// 채팅 에러
public enum ChatError: Error, Sendable, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case sendFailed(String)
    case maxRetriesExceeded
    case invalidChannelId
    case serverError(String)
    case notConnected
    case invalidMessage

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): "채팅 연결 실패: \(reason)"
        case .authenticationFailed: "채팅 인증 실패"
        case .sendFailed(let reason): "메시지 전송 실패: \(reason)"
        case .maxRetriesExceeded: "최대 재연결 시도 횟수 초과"
        case .invalidChannelId: "잘못된 채널 ID"
        case .serverError(let msg): "서버 오류: \(msg)"
        case .notConnected: "채팅에 연결되어 있지 않습니다"
        case .invalidMessage: "잘못된 메시지 형식"
        }
    }
}

/// 데이터 영속화 에러
public enum PersistenceError: Error, Sendable, LocalizedError {
    case saveFailed(String)
    case fetchFailed(String)
    case migrationFailed(String)
    case containerNotLoaded

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let detail): "저장 실패: \(detail)"
        case .fetchFailed(let detail): "조회 실패: \(detail)"
        case .migrationFailed(let detail): "마이그레이션 실패: \(detail)"
        case .containerNotLoaded: "데이터 저장소가 로드되지 않았습니다"
        }
    }
}
