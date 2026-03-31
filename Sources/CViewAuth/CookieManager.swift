// MARK: - CViewAuth/CookieManager.swift
// 네이버 인증 쿠키 관리자

import Foundation
import WebKit
import CViewCore

/// 쿠키 관리자 (actor 기반)
public actor CookieManager {
    private let keychainService: KeychainService
    private let cookieStorage: HTTPCookieStorage

    /// 네이버 인증에 필요한 쿠키 이름
    private static let requiredCookieNames = ["NID_AUT", "NID_SES"]
    private static let keychainKey = "naver_auth_cookies"
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    public init(
        keychainService: KeychainService = KeychainService(),
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        self.keychainService = keychainService
        self.cookieStorage = cookieStorage
    }

    // MARK: - Cookie Operations

    /// 현재 유효한 인증 쿠키 목록 (모든 쿠키에서 NID_AUT/NID_SES 검색)
    public var authCookies: [HTTPCookie] {
        guard let allCookies = cookieStorage.cookies else { return [] }
        return allCookies.filter {
            Self.requiredCookieNames.contains($0.name) &&
            $0.domain.contains("naver.com") &&
            !$0.value.isEmpty
        }
    }

    /// 인증 쿠키 보유 여부
    public var hasCookies: Bool {
        let cookies = authCookies
        return Self.requiredCookieNames.allSatisfy { name in
            cookies.contains { $0.name == name && !$0.value.isEmpty }
        }
    }

    /// 쿠키를 키체인에 저장
    public func saveCookiesToKeychain() async throws {
        let cookies = authCookies
        guard !cookies.isEmpty else { return }

        let cookieData = cookies.compactMap { cookie -> [String: String]? in
            var props: [String: String] = [:]
            props["name"] = cookie.name
            props["value"] = cookie.value
            props["domain"] = cookie.domain
            props["path"] = cookie.path
            if let expires = cookie.expiresDate {
                props["expires"] = Self.isoFormatter.string(from: expires)
            }
            return props
        }

        let data = try JSONEncoder().encode(cookieData)
        try await keychainService.save(key: Self.keychainKey, data: data)
        Log.auth.info("Cookies saved to keychain (\(cookies.count) cookies)")
    }

    /// 키체인에서 쿠키 복원
    public func restoreCookiesFromKeychain() async -> Bool {
        do {
            guard let data = try await keychainService.load(key: Self.keychainKey) else {
                return false
            }

            let cookieData = try JSONDecoder().decode([[String: String]].self, from: data)

            for props in cookieData {
                guard let name = props["name"],
                      let value = props["value"],
                      let domain = props["domain"] else { continue }

                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: props["path"] ?? "/",
                ]

                if let expiresStr = props["expires"],
                   let date = Self.isoFormatter.date(from: expiresStr) {
                    properties[.expires] = date
                }

                if let cookie = HTTPCookie(properties: properties) {
                    cookieStorage.setCookie(cookie)
                }
            }

            Log.auth.info("Cookies restored from keychain (\(cookieData.count) cookies)")
            return hasCookies
        } catch {
            Log.auth.error("Failed to restore cookies: \(error.localizedDescription)")
            return false
        }
    }

    /// WKWebView 영구 저장소에서 인증 쿠키 추출 (OAuth 로그인 후 키체인 쿠키 부재 시 폴백)
    public func syncFromWebKitStore() async -> Bool {
        // GCD 대신 MainActor.run 사용 — Swift Concurrency와 GCD 혼합 제거, 우선순위 역전 방지
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            Task { @MainActor in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }

        let authCookies = cookies.filter { Self.requiredCookieNames.contains($0.name) && !$0.value.isEmpty }
        guard !authCookies.isEmpty else {
            Log.auth.info("WebKit store: no auth cookies found")
            return false
        }

        for cookie in authCookies {
            cookieStorage.setCookie(cookie)
        }

        Log.auth.info("WebKit store: synced \(authCookies.count) auth cookies")

        // 키체인에도 저장 (다음 앱 시작 시 복원 가능)
        do {
            try await saveCookiesToKeychain()
        } catch {
            Log.auth.error("Failed to save cookies to keychain: \(error.localizedDescription)")
        }

        return hasCookies
    }

    /// 쿠키 삭제
    public func clearCookies() async {
        // 모든 Naver 인증 쿠키 삭제
        if let allCookies = cookieStorage.cookies {
            for cookie in allCookies where Self.requiredCookieNames.contains(cookie.name) && cookie.domain.contains("naver.com") {
                cookieStorage.deleteCookie(cookie)
            }
        }
        do {
            try await keychainService.delete(key: Self.keychainKey)
        } catch {
            Log.auth.error("Failed to delete cookies from keychain: \(error.localizedDescription)")
        }
        Log.auth.info("All auth cookies cleared")
    }
}
