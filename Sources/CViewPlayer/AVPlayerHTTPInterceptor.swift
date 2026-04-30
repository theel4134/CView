// MARK: - AVPlayerHTTPInterceptor.swift
// CViewPlayer — AVAssetResourceLoaderDelegate 기반 인-프로세스 HTTP 인터셉터
//
// 목적: LocalStreamProxy(로컬 HTTP 서버)를 사용하지 않고 동일한 효과를 얻는다.
//   1) chzzk CDN(navercdn.com 등)이 fMP4 세그먼트를 Content-Type: video/MP2T 로
//      잘못 응답 → AVPlayer 가 MPEG-TS 디코더 경로로 진입하여 재생 실패.
//   2) AVAssetResourceLoaderDelegate 가 모든 HTTP(S) 요청을 가로채고
//      응답 Content-Type 을 video/mp4 로 교정하여 AVPlayer 에 전달.
//   3) M3U8 응답은 내부 URL 을 동일한 커스텀 스킴으로 재작성하여 후속 세그먼트
//      요청도 인터셉트 경로로 흐르게 한다.
//
// 동작:
//   - https URL 을 cviewhttps://... 로 치환하여 AVURLAsset 생성
//   - resourceLoader 가 cviewhttps://... 요청을 받으면 URLSession 으로
//     실제 https 호출 → 응답 헤더 교정 → loadingRequest 에 데이터/헤더 주입
//
// 주의:
//   - 인증 헤더(User-Agent / Referer / Origin)는 모든 요청에 자동 첨부
//   - 요청 범위 헤더(Range) 와 If-Modified-Since 등도 그대로 포워딩
//   - chzzk CDN 만 인터셉트 (LocalStreamProxy.needsProxy 와 동일 호스트 매칭)

import Foundation
import AVFoundation
import CViewCore

/// AVPlayer 용 인-프로세스 HTTP 인터셉터.
/// LocalStreamProxy 와 동일한 Content-Type 교정 + M3U8 재작성을 별도 포트 없이 수행.
public final class AVPlayerHTTPInterceptor: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    // MARK: - Constants

    /// 커스텀 스킴 (https → 이 값으로 치환). AVPlayer 가 모르는 스킴이어야 ResourceLoader 로 라우팅됨.
    public static let interceptScheme = "cviewhttps"

    /// 동일 호스트 동시 연결 수 / 응답 타임아웃은 LocalStreamProxy 와 동일 정책
    private static let requestTimeout: TimeInterval = 15
    private static let resourceTimeout: TimeInterval = 60

    // MARK: - Properties

    private let session: URLSession
    private let queue: DispatchQueue
    private let logger = AppLogger.player

    // MARK: - Init

    public override init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Self.requestTimeout
        cfg.timeoutIntervalForResource = Self.resourceTimeout
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
        self.queue = DispatchQueue(label: "com.cview.avinterceptor", qos: .userInitiated)
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Public Helpers

    /// 인터셉트 대상 호스트인지 판정 — LocalStreamProxy 와 동일 정책
    public static func needsInterception(for url: URL) -> Bool {
        LocalStreamProxy.needsProxy(for: url)
    }

    /// https URL → cviewhttps URL 변환 (AVURLAsset 에 전달할 URL)
    public static func interceptedURL(from url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if comps.scheme == "https" {
            comps.scheme = interceptScheme
        }
        return comps.url ?? url
    }

    /// cviewhttps URL → https URL 복원 (실제 네트워크 호출용)
    private static func originalURL(from interceptedURL: URL) -> URL? {
        guard var comps = URLComponents(url: interceptedURL, resolvingAgainstBaseURL: false) else { return nil }
        if comps.scheme == interceptScheme {
            comps.scheme = "https"
        }
        return comps.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let interceptedURL = loadingRequest.request.url,
              interceptedURL.scheme == Self.interceptScheme,
              let originalURL = Self.originalURL(from: interceptedURL) else {
            return false
        }

        var request = URLRequest(url: originalURL)
        request.timeoutInterval = Self.requestTimeout

        // 원본 요청 헤더 포워딩 (Range, If-Modified-Since 등)
        if let originalHeaders = loadingRequest.request.allHTTPHeaderFields {
            for (key, value) in originalHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // chzzk CDN 인증 헤더 강제 적용 (원본 요청에 포함되지 않은 경우만)
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        }
        if request.value(forHTTPHeaderField: "Origin") == nil {
            request.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                self.handleResponse(loadingRequest: loadingRequest,
                                    originalURL: originalURL,
                                    data: data,
                                    response: response,
                                    error: error)
            }
        }
        task.resume()
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // dataTask 가 자체 취소되도록 두면 충분 (loadingRequest 는 더 이상 사용되지 않음)
    }

    // MARK: - Response Handling

    private func handleResponse(loadingRequest: AVAssetResourceLoadingRequest,
                                originalURL: URL,
                                data: Data?,
                                response: URLResponse?,
                                error: Error?) {
        if let error {
            loadingRequest.finishLoading(with: error)
            logger.warning("AVInterceptor: \(originalURL.lastPathComponent, privacy: .public) failed — \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let httpResponse = response as? HTTPURLResponse, var data else {
            loadingRequest.finishLoading(with: URLError(.badServerResponse))
            return
        }

        // 1) Content-Type 결정 — fMP4 세그먼트면 video/mp4 로 강제 교정
        let originalContentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let pathLower = originalURL.path.lowercased()
        let isFmp4Segment = pathLower.hasSuffix(".m4s") ||
                            pathLower.hasSuffix(".mp4") ||
                            pathLower.contains(".m4s")
        let isM3U8 = pathLower.hasSuffix(".m3u8") || pathLower.contains(".m3u8")

        let correctedContentType: String
        if isM3U8 {
            correctedContentType = "application/vnd.apple.mpegurl"
        } else if isFmp4Segment {
            // CDN 이 video/MP2T 로 잘못 보고하더라도 video/mp4 로 교정
            correctedContentType = "video/mp4"
        } else if originalContentType.isEmpty {
            correctedContentType = "application/octet-stream"
        } else {
            correctedContentType = originalContentType
        }

        // 2) M3U8 응답이면 본문 내 URL 을 인터셉트 스킴으로 재작성
        if isM3U8, let body = String(data: data, encoding: .utf8) {
            let rewritten = rewriteM3U8(body, base: originalURL)
            data = Data(rewritten.utf8)
        }

        // 3) contentInformationRequest 채우기 (AVPlayer 가 첫 호출에서 메타 조회)
        if let contentInfo = loadingRequest.contentInformationRequest {
            contentInfo.contentType = correctedContentType
            contentInfo.contentLength = Int64(data.count)
            contentInfo.isByteRangeAccessSupported = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        }

        // 4) Range 요청 처리 — AVPlayer 가 부분 요청을 보낼 수 있음
        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let availableLength = max(0, data.count - requestedOffset)
            let lengthToServe = min(requestedLength, availableLength)
            if lengthToServe > 0 {
                let slice = data.subdata(in: requestedOffset..<(requestedOffset + lengthToServe))
                dataRequest.respond(with: slice)
            }
        }
        loadingRequest.finishLoading()
    }

    // MARK: - M3U8 Rewriter

    /// M3U8 본문 내 절대/상대 URL 을 cviewhttps:// 스킴으로 재작성하여 후속 요청도 인터셉트.
    private func rewriteM3U8(_ body: String, base: URL) -> String {
        var out: [String] = []
        out.reserveCapacity(body.split(separator: "\n").count)
        let lines = body.components(separatedBy: "\n")
        for raw in lines {
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // EXT-X-KEY / EXT-X-MEDIA / EXT-X-MAP URI="..." 재작성
            if trimmed.hasPrefix("#EXT-X-KEY") || trimmed.hasPrefix("#EXT-X-MEDIA") ||
               trimmed.hasPrefix("#EXT-X-MAP") || trimmed.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") ||
               trimmed.hasPrefix("#EXT-X-SESSION-DATA") || trimmed.hasPrefix("#EXT-X-SESSION-KEY") {
                out.append(rewriteURIAttribute(in: line, base: base))
                continue
            }

            // 주석 / 빈 줄 그대로
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                out.append(line)
                continue
            }

            // URL 라인 — 절대/상대 모두 인터셉트 URL 로 치환
            if let resolved = absoluteURL(from: trimmed, base: base) {
                let intercepted = Self.interceptedURL(from: resolved)
                out.append(intercepted.absoluteString)
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// EXT-X-* 태그의 `URI="..."` 속성만 추출하여 인터셉트 URL 로 치환
    private func rewriteURIAttribute(in line: String, base: URL) -> String {
        guard let uriRange = line.range(of: "URI=\"", options: .caseInsensitive) else { return line }
        let valueStart = uriRange.upperBound
        guard let endQuote = line.range(of: "\"", range: valueStart..<line.endIndex) else { return line }
        let originalValue = String(line[valueStart..<endQuote.lowerBound])
        guard let resolved = absoluteURL(from: originalValue, base: base) else { return line }
        let intercepted = Self.interceptedURL(from: resolved)
        return line.replacingCharacters(in: valueStart..<endQuote.lowerBound, with: intercepted.absoluteString)
    }

    /// 절대/상대 URL 문자열 → 절대 URL (https 스킴 기준)
    private func absoluteURL(from string: String, base: URL) -> URL? {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        if string.hasPrefix("\(Self.interceptScheme)://") {
            return URL(string: string)
        }
        // 상대 경로 — base URL 기준으로 해석
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}
