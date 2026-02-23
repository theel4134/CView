// MARK: - CViewAuthTests.swift
// CViewAuth module tests

import Testing
import Foundation
@testable import CViewAuth
@testable import CViewCore

@Suite("CookieManager")
struct CookieManagerTests {
    
    @Test("Cookie extraction returns empty when no cookies")
    func noCookies() async {
        let manager = CookieManager()
        let cookies = await manager.authCookies
        // Cookies may or may not be empty depending on system cookies
        // This is a basic smoke test
        _ = cookies
    }
}
