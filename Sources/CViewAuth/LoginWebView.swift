// MARK: - LoginWebView.swift
// CViewAuth - 네이버 OAuth 로그인 WKWebView
// 네이버 로그인 → NID_AUT/NID_SES 쿠키 획득 → AuthManager 인증 완료

import SwiftUI
import WebKit
import CViewCore

// MARK: - Login Web View (SwiftUI)

/// 네이버 로그인을 위한 WKWebView 래퍼.
/// 로그인 완료 시 NID_AUT, NID_SES 쿠키를 감지하여 `onLoginSuccess`를 호출합니다.
public struct LoginWebView: NSViewRepresentable {

    /// 로그인 성공 시 호출될 콜백
    public let onLoginSuccess: () -> Void
    
    /// 로그인 실패 시 호출될 콜백
    public let onLoginFailed: ((String) -> Void)?

    private static let loginURL = URL(string: "https://nid.naver.com/nidlogin.login?url=https://chzzk.naver.com")!
    private static let requiredCookies = ["NID_AUT", "NID_SES"]

    public init(
        onLoginSuccess: @escaping () -> Void,
        onLoginFailed: ((String) -> Void)? = nil
    ) {
        self.onLoginSuccess = onLoginSuccess
        self.onLoginFailed = onLoginFailed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // 공유 쿠키 저장소 사용

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // User Agent 설정 (데스크톱 브라우저)
        webView.customUserAgent = CommonHeaders.chromeUserAgent

        // 로그인 페이지 로드
        let request = URLRequest(url: Self.loginURL)
        webView.load(request)

        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // no-op
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LoginWebView
        private var hasCompletedLogin = false

        init(parent: LoginWebView) {
            self.parent = parent
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForAuthCookies(in: webView)
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // chzzk.naver.com으로 리다이렉트되면 로그인 완료 가능성 높음
            if let url = navigationAction.request.url,
               url.host?.contains("chzzk.naver.com") == true {
                checkForAuthCookies(in: webView)
            }
            decisionHandler(.allow)
        }

        public func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onLoginFailed?(error.localizedDescription)
        }

        /// WKWebView 쿠키 저장소에서 NID_AUT / NID_SES 쿠키 확인
        private func checkForAuthCookies(in webView: WKWebView) {
            guard !hasCompletedLogin else { return }

            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.hasCompletedLogin else { return }

                let requiredNames = LoginWebView.requiredCookies
                let foundCookies = cookies.filter { requiredNames.contains($0.name) && !$0.value.isEmpty }

                if foundCookies.count >= requiredNames.count {
                    self.hasCompletedLogin = true

                    // WKWebView 쿠키를 HTTPCookieStorage로 복사
                    for cookie in cookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }

                    Log.auth.info("Login cookies acquired: \(foundCookies.map(\.name).joined(separator: ", "), privacy: .private)")

                    Task { @MainActor in
                        self.parent.onLoginSuccess()
                    }
                }
            }
        }
    }
}
