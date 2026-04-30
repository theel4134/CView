// MARK: - CViewHTTPURLProtocol.swift
// CViewPlayer — 글로벌 URLProtocol 후크
//
// 목적:
//   chzzk CDN 의 잘못된 Content-Type(`video/MP2T` for fMP4) 을 글로벌하게 교정한다.
//   `URLProtocol.registerClass(_:)` 로 프로세스 전체 CFNetwork 요청에 끼어들어 응답 헤더를
//   가로채 fMP4 세그먼트는 `video/mp4` 로 교정한 응답을 만들어낸다.
//
// 한계:
//   - AVPlayer / VLC 의 내부 미디어 다운로더는 CFNetwork 가 아닌 자체 스택을 사용하므로
//     실제 비디오 페이로드는 후크되지 않는다.
//   - 매니페스트 사전 로딩 / 썸네일 / API 호출 등 보조 트래픽에는 정상 작동.
//
// 따라서 이 모드는 디버깅 / 진단 / 보조 도구 용도로 노출하며,
// `StreamCoordinator+Lifecycle` 은 안전망으로 항상 `localProxy` 를 함께 활성화한다.

import Foundation
import CViewCore

public final class CViewHTTPURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Registration

    private static let registered = NSLock()
    nonisolated(unsafe) private static var didRegister = false

    /// 한 번만 글로벌 등록한다. 이후 호출은 no-op.
    public static func registerIfNeeded() {
        registered.lock()
        defer { registered.unlock() }
        guard !didRegister else { return }
        URLProtocol.registerClass(CViewHTTPURLProtocol.self)
        didRegister = true
        AppLogger.player.info("CViewHTTPURLProtocol: 글로벌 URLProtocol 등록 완료")
    }

    public static func unregister() {
        registered.lock()
        defer { registered.unlock() }
        guard didRegister else { return }
        URLProtocol.unregisterClass(CViewHTTPURLProtocol.self)
        didRegister = false
    }

    // MARK: - Re-entry Guard

    /// 우리가 생성한 재요청을 다시 가로채는 무한 루프 방지 마커.
    private static let reentryHeader = "X-CView-Hooked"

    // MARK: - URLProtocol Overrides

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let scheme = url.scheme?.lowercased() else { return false }
        // http/https 만 처리 + chzzk CDN 호스트만 후크
        guard scheme == "http" || scheme == "https" else { return false }
        guard LocalStreamProxy.needsProxy(for: url) else { return false }
        // 우리가 보낸 재요청은 통과
        if request.value(forHTTPHeaderField: reentryHeader) != nil { return false }
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let originalURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        var newRequest = request
        newRequest.setValue("1", forHTTPHeaderField: Self.reentryHeader)
        // chzzk 인증 헤더 보강 (없으면)
        if newRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            newRequest.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
        }
        if newRequest.value(forHTTPHeaderField: "Referer") == nil {
            newRequest.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        }
        if newRequest.value(forHTTPHeaderField: "Origin") == nil {
            newRequest.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        }

        let task = Self.session.dataTask(with: newRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            // Content-Type 교정 — fMP4 세그먼트만 video/mp4 로 변경
            let pathLower = originalURL.path.lowercased()
            let isFmp4 = pathLower.hasSuffix(".m4s") || pathLower.hasSuffix(".mp4") || pathLower.contains(".m4s")
            var headers = httpResponse.allHeaderFields as? [String: String] ?? [:]
            if isFmp4, let original = headers["Content-Type"], original.lowercased().contains("mp2t") {
                headers["Content-Type"] = "video/mp4"
            }

            let corrected = HTTPURLResponse(
                url: httpResponse.url ?? originalURL,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) ?? httpResponse

            self.client?.urlProtocol(self, didReceive: corrected, cacheStoragePolicy: .notAllowed)
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        currentTask = task
        task.resume()
    }

    public override func stopLoading() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    private var currentTask: URLSessionDataTask?

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        // 우리 자신을 후크하지 않도록 protocolClasses 에서 우리 클래스 제외
        cfg.protocolClasses = (cfg.protocolClasses ?? []).filter { $0 != CViewHTTPURLProtocol.self }
        return URLSession(configuration: cfg)
    }()
}
