// MARK: - CookieManagerTests.swift
// CViewAuth — CookieManager 쿠키 관리 테스트

import Testing
import Foundation
@testable import CViewAuth
@testable import CViewCore

// MARK: - Test Helpers

/// 테스트용 격리된 HTTPCookieStorage + KeychainService 생성
private func makeTestDeps() -> (CookieManager, HTTPCookieStorage, KeychainService) {
    let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "test.\(UUID().uuidString)")
    let keychain = KeychainService(serviceName: "test.\(UUID().uuidString)")
    let manager = CookieManager(keychainService: keychain, cookieStorage: storage)
    return (manager, storage, keychain)
}

/// 네이버 인증 쿠키 생성 헬퍼
private func makeNaverCookie(name: String, value: String, domain: String = ".naver.com") -> HTTPCookie? {
    HTTPCookie(properties: [
        .name: name,
        .value: value,
        .domain: domain,
        .path: "/",
        .expires: Date().addingTimeInterval(86400),
    ])
}

// MARK: - authCookies / hasCookies

@Suite("CookieManager — 쿠키 조회")
struct CookieManagerQueryTests {

    @Test("쿠키 없으면 빈 배열")
    func noCookies() async {
        let (manager, _, _) = makeTestDeps()
        let cookies = await manager.authCookies
        #expect(cookies.isEmpty)
    }

    @Test("hasCookies — 쿠키 없으면 false")
    func hasCookiesFalse() async {
        let (manager, _, _) = makeTestDeps()
        let has = await manager.hasCookies
        #expect(!has)
    }

    @Test("NID_AUT + NID_SES 모두 있으면 hasCookies true")
    func hasCookiesTrue() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: "auth-val"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "ses-val") {
            storage.setCookie(c1)
            storage.setCookie(c2)
        }

        let has = await manager.hasCookies
        #expect(has)
    }

    @Test("NID_AUT만 있으면 hasCookies false")
    func partialCookies() async {
        let (manager, storage, _) = makeTestDeps()

        if let c = makeNaverCookie(name: "NID_AUT", value: "auth-only") {
            storage.setCookie(c)
        }

        let has = await manager.hasCookies
        #expect(!has)
    }

    @Test("빈 값 쿠키는 무시")
    func emptyValueCookieIgnored() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: ""),
           let c2 = makeNaverCookie(name: "NID_SES", value: "ses-val") {
            storage.setCookie(c1)
            storage.setCookie(c2)
        }

        let has = await manager.hasCookies
        #expect(!has)
    }

    @Test("naver.com 이외 도메인 쿠키는 무시")
    func wrongDomainIgnored() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: "v1", domain: ".example.com"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "v2", domain: ".example.com") {
            storage.setCookie(c1)
            storage.setCookie(c2)
        }

        let cookies = await manager.authCookies
        #expect(cookies.isEmpty)
    }

    @Test("authCookies는 NID_AUT/NID_SES만 반환")
    func authCookiesFilter() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: "auth"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "ses"),
           let c3 = makeNaverCookie(name: "OTHER", value: "other") {
            storage.setCookie(c1)
            storage.setCookie(c2)
            storage.setCookie(c3)
        }

        let cookies = await manager.authCookies
        #expect(cookies.count == 2)
        let names = Set(cookies.map(\.name))
        #expect(names == ["NID_AUT", "NID_SES"])
    }
}

// MARK: - 키체인 저장/복원

@Suite("CookieManager — 키체인 저장/복원")
struct CookieManagerKeychainTests {

    @Test("쿠키 키체인 저장 후 키체인에 데이터 존재")
    func saveAndVerifyKeychainData() async throws {
        let (manager, storage, keychain) = makeTestDeps()

        // 쿠키 설정
        if let c1 = makeNaverCookie(name: "NID_AUT", value: "save-auth"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "save-ses") {
            storage.setCookie(c1)
            storage.setCookie(c2)
        }

        // 키체인에 저장
        try await manager.saveCookiesToKeychain()

        // 키체인에 데이터가 실제로 저장되었는지 확인
        let data = try await keychain.load(key: "naver_auth_cookies")
        #expect(data != nil)

        // 저장된 쿠키 데이터 형식 확인
        let decoded = try JSONDecoder().decode([[String: String]].self, from: data!)
        #expect(decoded.count == 2)

        let names = Set(decoded.compactMap { $0["name"] })
        #expect(names.contains("NID_AUT"))
        #expect(names.contains("NID_SES"))
        try await keychain.delete(key: "naver_auth_cookies")
    }

    @Test("키체인에 저장된 쿠키 없으면 복원 false")
    func restoreEmpty() async {
        let (manager, _, _) = makeTestDeps()
        let result = await manager.restoreCookiesFromKeychain()
        #expect(!result)
    }

    @Test("쿠키 없으면 saveCookiesToKeychain 아무것도 안함")
    func saveNoCookies() async throws {
        let (manager, _, _) = makeTestDeps()
        // 에러 없이 완료되어야 함
        try await manager.saveCookiesToKeychain()
    }
}

// MARK: - clearCookies

@Suite("CookieManager — 쿠키 삭제")
struct CookieManagerClearTests {

    @Test("clearCookies로 인증 쿠키 삭제")
    func clearRemovesAuthCookies() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: "del-auth"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "del-ses") {
            storage.setCookie(c1)
            storage.setCookie(c2)
        }

        #expect(await manager.hasCookies)
        await manager.clearCookies()
        #expect(!(await manager.hasCookies))
    }

    @Test("clearCookies는 관련 없는 쿠키는 유지")
    func clearKeepsOtherCookies() async {
        let (manager, storage, _) = makeTestDeps()

        if let c1 = makeNaverCookie(name: "NID_AUT", value: "del"),
           let c2 = makeNaverCookie(name: "NID_SES", value: "del"),
           let c3 = makeNaverCookie(name: "OTHER_COOKIE", value: "keep") {
            storage.setCookie(c1)
            storage.setCookie(c2)
            storage.setCookie(c3)
        }

        await manager.clearCookies()

        let remaining = storage.cookies ?? []
        let otherCookies = remaining.filter { $0.name == "OTHER_COOKIE" }
        #expect(!otherCookies.isEmpty)
    }
}

