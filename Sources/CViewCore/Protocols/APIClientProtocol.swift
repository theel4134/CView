// MARK: - CViewCore/Protocols/APIClientProtocol.swift
// API 클라이언트 프로토콜 — DI 및 테스트 Mock 지원

import Foundation

/// API 클라이언트 프로토콜
public protocol APIClientProtocol: Actor {
    func request<T: Decodable & Sendable>(
        _ endpoint: any EndpointProtocol,
        as type: T.Type
    ) async throws -> T
}

/// 엔드포인트 프로토콜
public protocol EndpointProtocol: Sendable {
    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem]? { get }
    var body: Data? { get }
    var requiresAuth: Bool { get }
    var cachePolicy: CachePolicy { get }
}

/// HTTP 메서드
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// 캐시 정책
public enum CachePolicy: Sendable {
    case returnCacheElseLoad(ttl: TimeInterval)
    case reloadIgnoringCache
    case returnCacheOnly

    public static let standard = CachePolicy.returnCacheElseLoad(ttl: 60)
    public static let none = CachePolicy.reloadIgnoringCache
}
