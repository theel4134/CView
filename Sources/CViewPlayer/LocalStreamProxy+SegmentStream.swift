// MARK: - LocalStreamProxy+SegmentStream.swift
// CViewPlayer - Segment Streaming (P0-5)
//
// 미디어 세그먼트(.m4s/.m4v/.ts/.aac 등)를 chunk 단위로 즉시 downstream 에 전달.
// 기존 dataTask 기반은 세그먼트 전체를 메모리에 모은 뒤 한 번에 전송 → VLC 첫 바이트 지연 +
// 4채널 동시 다운로드 시 메모리 burst. URLSessionDataDelegate 로 chunk 즉시 forward.
//
// 동작 원칙:
// - M3U8 은 기존 경로(전체 수신 + URL rewrite + 캐시) 그대로. 본 파일은 세그먼트 전용.
// - expectedContentLength 가 양수면 Content-Length 헤더 + keep-alive 유지.
// - unknown 이면 Connection: close 로 안전하게 종료.
// - downstream connection cancel 시 upstream task 도 즉시 cancel (OWASP A05 자원 누수 방지).

import Foundation
import Network
import CViewCore

// MARK: - 세그먼트 스트리밍 핸들러

/// URLSessionDataDelegate 기반 세그먼트 chunk forwarder.
/// 각 세그먼트 요청마다 1회용 인스턴스로 사용된다.
final class SegmentStreamHandler: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let requestNum: Int
    private let targetURL: String
    private weak var proxy: LocalStreamProxy?
    private let requestStart: CFAbsoluteTime

    private var headersSent = false
    private var statusCode = 200
    private var contentType = "application/octet-stream"
    private var keepAlive = true
    private var totalBytes: Int64 = 0
    /// downstream 송신 실패 시 추가 chunk 전송/콜백 무시
    private var aborted = false
    /// [P1-1] 첫 바이트 도착까지의 시간 (초). 응답 헤더 수신 시점에 캡처.
    private var ttfb: Double = 0

    init(connection: NWConnection, requestNum: Int, targetURL: String, proxy: LocalStreamProxy) {
        self.connection = connection
        self.requestNum = requestNum
        self.targetURL = targetURL
        self.proxy = proxy
        self.requestStart = CFAbsoluteTimeGetCurrent()
        super.init()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !aborted, let proxy else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            proxy.recordSegmentError(targetURL: targetURL)
            proxy.sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: true)
            aborted = true
            completionHandler(.cancel)
            return
        }
        statusCode = http.statusCode
        // [P1-1] TTFB 캡처 — 헤더 응답 시점
        if ttfb == 0 {
            ttfb = CFAbsoluteTimeGetCurrent() - requestStart
        }

        // Content-Type 보정 (M3U8 경로와 동일 규칙)
        var ct = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        let lower = ct.lowercased()
        let lowerURL = targetURL.lowercased()
        if lower.contains("mp2t") {
            ct = "video/mp4"
        } else if (lower.contains("quicktime") || lower.contains("octet-stream"))
                  && (lowerURL.hasSuffix(".m4s") || lowerURL.hasSuffix(".m4v")
                      || lowerURL.contains(".m4v?") || lowerURL.contains(".m4s?")) {
            ct = "video/mp4"
        }
        contentType = ct

        // expectedContentLength > 0 → keep-alive + Content-Length, 그 외 → close
        let length = http.expectedContentLength
        keepAlive = length > 0

        // 에러 응답은 기존 dataTask 경로처럼 카운터/403 추적
        if http.statusCode >= 400 {
            proxy.recordSegmentHTTPError(statusCode: http.statusCode, targetURL: targetURL, requestNum: requestNum)
        } else {
            proxy.recordSegmentOK()
        }

        // 응답 헤더 즉시 전송 (body 없이)
        proxy.sendStreamingHeaders(
            to: connection,
            status: http.statusCode,
            contentType: contentType,
            contentLength: keepAlive ? length : -1,
            keepAlive: keepAlive
        ) { [weak self] sendError in
            guard let self else { return }
            if sendError != nil {
                self.aborted = true
                dataTask.cancel()
            }
        }
        headersSent = true
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !aborted, headersSent else { return }
        totalBytes += Int64(data.count)
        // raw body chunk 전송. isComplete=false 로 추가 chunk 가능.
        connection.send(content: data, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.proxy?.logSegmentSendError(error: error)
                self?.aborted = true
                dataTask.cancel()
            }
        })
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let elapsed = CFAbsoluteTimeGetCurrent() - requestStart
        proxy?.recordSegmentMetrics(elapsed: elapsed, bytesReceived: totalBytes)
        // [P1-1] 정상 다운로드 완료 시 segment fetch 샘플 1건 기록 (HTTP 4xx/5xx 제외)
        if error == nil, headersSent, statusCode < 400, totalBytes > 0 {
            proxy?.recordSegmentFetchSample(fetchDuration: elapsed, ttfb: ttfb)
        }

        // 헤더 전송 전 실패 → 502 응답
        if !headersSent {
            if let error {
                proxy?.logSegmentUpstreamError(error: error, targetURL: targetURL)
            }
            if !aborted {
                proxy?.sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: true)
            }
            return
        }

        if aborted {
            connection.cancel()
            return
        }

        if let error {
            // 본문 전송 도중 실패 — 응답 헤더는 이미 갔으므로 connection cancel
            proxy?.logSegmentUpstreamError(error: error, targetURL: targetURL)
            connection.cancel()
            return
        }

        // 정상 종료
        if keepAlive {
            // 다음 요청 대기 (keep-alive)
            proxy?.continueAfterStreaming(connection: connection, requestNum: requestNum, bytesServed: totalBytes)
        } else {
            // Content-Length 모름 → 마지막 send 로 종료 신호 후 close
            let conn = self.connection
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
            proxy?.recordBytesServed(totalBytes)
        }
    }
}

// MARK: - LocalStreamProxy 확장: 스트리밍 진입점 + 메트릭 헬퍼

extension LocalStreamProxy {

    /// 미디어 세그먼트 스트리밍 진입점. proxyToUpstream() 의 비-M3U8 분기에서 호출.
    func proxyToUpstreamStreaming(targetURL: String, connection: NWConnection, requestNum: Int) {
        guard let url = URL(string: targetURL) else {
            sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: false)
            return
        }
        guard let upstreamHost = url.host else {
            sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ProxyDefaults.upstreamRequestTimeout
        request.setValue(upstreamHost, forHTTPHeaderField: "Host")
        request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        request.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        // 세그먼트는 이미 압축된 바이너리 → Accept-Encoding 미설정 (CPU 절약)

        let handler = SegmentStreamHandler(
            connection: connection,
            requestNum: requestNum,
            targetURL: targetURL,
            proxy: self
        )
        let task = proxySession.dataTask(with: request)
        task.delegate = handler   // macOS 14+ task-scoped delegate
        task.resume()
    }

    // MARK: 응답 헤더 전송 (body 없음, streaming 시작용)

    func sendStreamingHeaders(
        to connection: NWConnection,
        status: Int,
        contentType: String,
        contentLength: Int64,
        keepAlive: Bool,
        completion: @escaping (NWError?) -> Void
    ) {
        var header = "HTTP/1.1 \(status) OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        if contentLength >= 0 {
            header += "Content-Length: \(contentLength)\r\n"
        }
        if keepAlive {
            header += "Connection: keep-alive\r\n"
            header += "Keep-Alive: timeout=\(Int(keepAliveTimeout))\r\n"
        } else {
            header += "Connection: close\r\n"
        }
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "\r\n"

        let headerData = Data(header.utf8)
        connection.send(content: headerData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { error in
            completion(error)
        })
    }

    /// keep-alive 스트리밍 응답 종료 후 다음 요청 대기.
    func continueAfterStreaming(connection: NWConnection, requestNum: Int, bytesServed: Int64) {
        recordBytesServed(bytesServed)
        readHTTPRequest(from: connection, requestCount: requestNum)
    }

    // MARK: 메트릭 카운터 헬퍼 (delegate 콜백에서 호출)

    func recordSegmentOK() {
        _consecutive403Count.withLock { $0 = 0 }
        _netCounters.withLock { c in
            c.totalRequests += 1
            c.cacheMisses += 1
        }
    }

    func recordSegmentHTTPError(statusCode: Int, targetURL: String, requestNum: Int) {
        _netCounters.withLock { c in
            c.totalRequests += 1
            c.cacheMisses += 1
            c.errorCount += 1
        }
        let urlSuffix = String(targetURL.suffix(80))
        logger.warning("Proxy(stream) → CDN res#\(requestNum, privacy: .public): HTTP \(statusCode, privacy: .public) [\(urlSuffix, privacy: .public)]")

        if statusCode == 403 {
            let count = _consecutive403Count.withLock { c -> Int in
                c += 1
                return c
            }
            if count >= _consecutive403Threshold {
                _consecutive403Count.withLock { $0 = 0 }
                logger.warning("Proxy(stream): CDN 403 \(count, privacy: .public)회 연속 — 토큰 만료 의심, 상위 통보")
                onUpstreamAuthFailure?()
            }
        }
    }

    func recordSegmentError(targetURL: String) {
        _netCounters.withLock { c in
            c.totalRequests += 1
            c.cacheMisses += 1
            c.errorCount += 1
        }
    }

    func recordSegmentMetrics(elapsed: TimeInterval, bytesReceived: Int64) {
        _responseTimes.withLock { times in
            times.append(elapsed)
            if times.count > _responseTimeWindowSize {
                times.removeFirst(times.count - _responseTimeWindowSize)
            }
        }
        if bytesReceived > 0 {
            _netCounters.withLock { $0.totalBytesReceived += bytesReceived }
        }
    }

    func recordBytesServed(_ bytes: Int64) {
        guard bytes > 0 else { return }
        _netCounters.withLock { $0.totalBytesServed += bytes }
    }

    func logSegmentSendError(error: NWError) {
        logger.debug("Proxy(stream) downstream send: \(error.localizedDescription, privacy: .public)")
    }

    func logSegmentUpstreamError(error: Error, targetURL: String) {
        let urlSuffix = String(targetURL.suffix(80))
        logger.warning("Proxy(stream) upstream error: \(error.localizedDescription, privacy: .public) [\(urlSuffix, privacy: .public)]")
    }
}
