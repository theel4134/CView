// MARK: - CViewCore/Protocols/AuthManagerProtocol.swift
// 인증 관리자 프로토콜

import Foundation

/// 인증 관리 프로토콜
public protocol AuthManagerProtocol: Sendable {
    /// 로그인 상태
    var isLoggedIn: Bool { get async }

    /// 현재 사용자 쿠키
    var cookies: [HTTPCookie] { get async }

    /// 로그인
    func login() async throws

    /// 로그아웃
    func logout() async

    /// 인증 상태 스트림
    var authStateStream: AsyncStream<AuthState> { get }
}

/// 인증 상태
public enum AuthState: Sendable, Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(userId: String)
    case expired
    case error(String)

    public var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }
}

/// 인증 토큰 제공자 (API 클라이언트에서 사용)
public protocol AuthTokenProvider: Sendable {
    var cookies: [HTTPCookie]? { get async }
    var accessToken: String? { get async }
    var isAuthenticated: Bool { get async }
}
