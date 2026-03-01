// MARK: - CViewAuth/OAuthLoginWebView.swift
// 치지직 OAuth 인증용 WKWebView
// account-interlock 페이지 로드 → redirect URI 인터셉트 → code 반환

import SwiftUI
import WebKit
import CViewCore

/// 치지직 OAuth 인증 WebView
/// 인증 URL을 로드하고, redirect URI로의 이동을 인터셉트하여 authorization code를 추출합니다.
public struct OAuthLoginWebView: NSViewRepresentable {
    
    let authURL: URL
    let redirectURI: String
    let onCodeReceived: @Sendable (String, String?) -> Void  // (code, state)
    let onError: @Sendable (String) -> Void
    
    public init(
        authURL: URL,
        redirectURI: String,
        onCodeReceived: @escaping @Sendable (String, String?) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.authURL = authURL
        self.redirectURI = redirectURI
        self.onCodeReceived = onCodeReceived
        self.onError = onError
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        webView.customUserAgent = CommonHeaders.chromeUserAgent
        
        webView.load(URLRequest(url: authURL))
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    // MARK: - Coordinator
    
    public final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: OAuthLoginWebView
        private var hasCompleted = false
        
        init(parent: OAuthLoginWebView) {
            self.parent = parent
        }
        
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let isRedirect: Bool = {
                if url.absoluteString.hasPrefix(parent.redirectURI) { return true }
                if let host = url.host,
                   (host == "localhost" || host == "127.0.0.1"),
                   url.path == "/callback" { return true }
                return false
            }()
            
            if isRedirect {
                decisionHandler(.cancel)
                // OAuth 인증 중 WebView에서 NID_AUT/NID_SES 쿠키 추출 → HTTPCookieStorage 동기화
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    let authCookieNames: Set<String> = ["NID_AUT", "NID_SES"]
                    let naverCookies = cookies.filter { $0.domain.contains("naver.com") }
                    let authCookies = naverCookies.filter { authCookieNames.contains($0.name) && !$0.value.isEmpty }
                    
                    Log.auth.info("OAuth WebView cookies: total=\(cookies.count), naver=\(naverCookies.count), auth=\(authCookies.count)")
                    
                    for cookie in authCookies {
                        // 원본 쿠키 저장
                        HTTPCookieStorage.shared.setCookie(cookie)
                        // .naver.com 도메인 버전도 보장 (내부 API의 쿠키 조회 호환)
                        if cookie.domain != ".naver.com" {
                            if var props = cookie.properties {
                                props[.domain] = ".naver.com"
                                if let broadCookie = HTTPCookie(properties: props) {
                                    HTTPCookieStorage.shared.setCookie(broadCookie)
                                }
                            }
                        }
                        Log.auth.info("  \(cookie.name, privacy: .private): domain=\(cookie.domain, privacy: .private), session=\(cookie.isSessionOnly)")
                    }
                    
                    if authCookies.isEmpty {
                        Log.auth.warning("OAuth WebView: NO NID_AUT/NID_SES cookies found")
                        if !naverCookies.isEmpty {
                            Log.auth.info("  naver cookies: \(Set(naverCookies.map(\.name)).sorted().joined(separator: ", "), privacy: .private)")
                        }
                    }
                    self?.handleCallback(url: url)
                }
                return
            }
            
            decisionHandler(.allow)
        }
        
        public func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            // localhost 연결 실패는 무시 (이미 인터셉트 처리됨)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            
            if !hasCompleted {
                parent.onError(error.localizedDescription)
            }
        }
        
        public func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let nsError = error as NSError
            // localhost 연결 거부 에러는 인터셉트 후 발생할 수 있으므로 무시
            if nsError.domain == NSURLErrorDomain &&
               (nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorCancelled) {
                return
            }
            
            if !hasCompleted {
                parent.onError(error.localizedDescription)
            }
        }
        
        private func handleCallback(url: URL) {
            guard !hasCompleted else { return }
            hasCompleted = true
            
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                parent.onError("콜백 URL 파싱 실패")
                return
            }
            
            let queryItems = components.queryItems ?? []
            
            // 에러 확인
            if let error = queryItems.first(where: { $0.name == "error" })?.value {
                parent.onError("OAuth 에러: \(error)")
                return
            }
            
            // code 추출
            guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                parent.onError("인증 코드를 받지 못했습니다")
                return
            }
            
            let state = queryItems.first(where: { $0.name == "state" })?.value
            
            Log.auth.info("OAuth callback intercepted: code=\(LogMask.token(code), privacy: .private)")
            parent.onCodeReceived(code, state)
        }
    }
}
