// MARK: - LocalStreamProxy.swift
// CViewPlayer - 로컬 HTTP 리버스 프록시 — CDN Content-Type 헤더 수정
//
// 문제: ex-nlive-streaming.navercdn.com CDN이 fMP4 세그먼트를
//       Content-Type: video/MP2T (MPEG-TS)로 잘못 응답
//       → VLC adaptive demux가 MP4→TS로 포맷 전환
//       → fMP4 데이터를 TS로 파싱 → transport_error_indicator 에러
//
// 해결: 로컬 프록시가 CDN 응답의 Content-Type을 video/mp4로 수정
//       VLC → localhost:PORT → CDN (HTTPS) → 응답 Content-Type 수정 → VLC

import Foundation
import Network
import CViewCore

public final class LocalStreamProxy: @unchecked Sendable {
    
    public static let shared = LocalStreamProxy()
    
    // MARK: - Properties
    
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0
    public private(set) var targetHost: String = ""
    private let targetScheme = "https"
    private var isRunning = false
    
    /// isRunning / port / targetHost 동시 접근 보호용 잠금
    private let stateLock = NSLock()
    
    /// CDN 절대 URL 검출 정규식 — 매 M3U8 요청마다 컴파일하지 않도록 캐시
    private static let cdnRegex: NSRegularExpression = {
        let pattern = "https://([a-zA-Z0-9][a-zA-Z0-9.-]*(?:navercdn\\.com|pstatic\\.net|naver\\.com|akamaized\\.net))"
        // 패턴이 고정되어 있으므로 try! 는 안전
        return try! NSRegularExpression(pattern: pattern) // swiftlint:disable:this force_try
    }()
    
    private let queue = DispatchQueue(label: "com.cview.streamproxy", qos: .userInteractive, attributes: .concurrent)
    private let logger = AppLogger.player
    
    private let keepAliveTimeout: TimeInterval = 30.0
    
    private lazy var proxySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    public init() {}
    
    // MARK: - Lifecycle
    
    @discardableResult
    public func start(for host: String) throws -> UInt16 {
        // stateLock으로 읽기/쓰기 경쟁 방지
        let alreadyRunning = stateLock.withLock { isRunning && targetHost == host && port > 0 }
        if alreadyRunning {
            let p = stateLock.withLock { port }
            logger.info("Proxy already running: localhost:\(p) → \(host)")
            return p
        }
        
        stop()
        stateLock.withLock { targetHost = host }
        
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        
        let readySemaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var startError: Error?
        
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.stateLock.withLock {
                    self.port = listener.port?.rawValue ?? 0
                    self.isRunning = true
                }
                self.logger.info("Proxy started: localhost:\(self.port) → \(host)")
                readySemaphore.signal()
            case .failed(let error):
                self.logger.error("Proxy start failed: \(error.localizedDescription, privacy: .public)")
                startError = error
                self.stateLock.withLock { self.isRunning = false }
                readySemaphore.signal()
            case .cancelled:
                self.stateLock.withLock { self.isRunning = false }
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener.start(queue: queue)
        
        let result = readySemaphore.wait(timeout: .now() + 3.0)
        if result == .timedOut {
            throw ProxyError.startTimeout
        }
        if let error = startError { throw error }
        
        return port
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        stateLock.withLock {
            isRunning = false
            port = 0
            targetHost = ""
        }
    }
    
    // MARK: - URL Transformation
    
    public func proxyURL(from originalURL: URL) -> URL {
        guard isRunning, port > 0, !targetHost.isEmpty,
              let host = originalURL.host, host == targetHost else {
            return originalURL
        }
        
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        components?.scheme = "http"
        components?.host = "127.0.0.1"
        components?.port = Int(port)
        
        return components?.url ?? originalURL
    }
    
    public func proxyURLString(_ originalURL: String) -> String {
        guard isRunning, port > 0, !targetHost.isEmpty,
              originalURL.contains(targetHost) else {
            return originalURL
        }
        
        return originalURL.replacingOccurrences(
            of: "\(targetScheme)://\(targetHost)",
            with: "http://127.0.0.1:\(port)"
        )
    }
    
    public static func needsProxy(for url: URL) -> Bool {
        guard let host = url.host else { return false }
        // chzzk CDN: livecloud.pstatic.net, ex-nlive-streaming.navercdn.com 등
        // fMP4 세그먼트를 video/MP2T로 잘못 응답 → VLC 파싱 실패
        return host.contains("nlive-streaming") || host.contains("navercdn.com") || host.contains("pstatic.net")
    }
    
    // MARK: - Connection Handling (HTTP/1.1 Keep-Alive)
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(from: connection, requestCount: 0)
    }
    
    private func readHTTPRequest(from connection: NWConnection, requestCount: Int) {
        let timeoutWorkItem = DispatchWorkItem {
            connection.cancel()
        }
        queue.asyncAfter(deadline: .now() + keepAliveTimeout, execute: timeoutWorkItem)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            timeoutWorkItem.cancel()
            
            guard let self else {
                connection.cancel()
                return
            }
            
            if isComplete && (data == nil || data!.isEmpty) {
                connection.cancel()
                return
            }
            
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            guard let requestStr = String(data: data, encoding: .utf8),
                  let path = self.extractPath(from: requestStr) else {
                self.sendError(to: connection, status: 400, message: "Bad Request", keepAlive: false)
                return
            }
            
            let reqNum = requestCount + 1
            let pathPreview = String(path.prefix(120))
            self.logger.info("Proxy ← VLC req#\(reqNum, privacy: .public): \(pathPreview, privacy: .public)")

            // [멀티CDN 지원] /_p_/HOST/path 형식이면 해당 CDN 호스트로 직접 라우팅
            // M3U8 URL 재작성 시 크로스CDN 절대 URL을 이 형식으로 인코딩함
            let targetURL: String
            let crossPrefix = "/_p_/"
            if path.hasPrefix(crossPrefix) {
                let rest = String(path.dropFirst(crossPrefix.count))
                if let slashIdx = rest.firstIndex(of: "/") {
                    let cdnHost = String(rest[rest.startIndex..<slashIdx])
                    let realPath = String(rest[slashIdx...])
                    targetURL = "\(self.targetScheme)://\(cdnHost)\(realPath)"
                } else {
                    // 경로만 있고 슬래시 없음 → 그냥 루트 경로
                    targetURL = "\(self.targetScheme)://\(rest)/"
                }
            } else {
                targetURL = "\(self.targetScheme)://\(self.targetHost)\(path)"
            }
            
            self.proxyToUpstream(targetURL: targetURL, connection: connection, requestNum: reqNum)
        }
    }
    
    private func extractPath(from request: String) -> String? {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }
    
    // MARK: - Upstream Proxying
    
    private func proxyToUpstream(targetURL: String, connection: NWConnection, requestNum: Int) {
        guard let url = URL(string: targetURL), let upstreamHost = url.host else {
            sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        // [멀티CDN] 실제 업스트림 호스트 헤더 사용 (크로스CDN 요청 포함)
        request.setValue(upstreamHost, forHTTPHeaderField: "Host")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Origin")
        
        proxySession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                connection.cancel()
                return
            }
            
            guard let data, let httpResponse = response as? HTTPURLResponse else {
                self.sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: true)
                return
            }
            
            // Content-Type 수정 (fMP4 → mp4)
            var contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            let origContentType = contentType
            let urlSuffix = String(targetURL.suffix(80))
            self.logger.info("Proxy → CDN res#\(requestNum, privacy: .public): HTTP \(httpResponse.statusCode, privacy: .public) Content-Type=\(origContentType, privacy: .public) size=\(data.count, privacy: .public) [\(urlSuffix, privacy: .public)]")

            // fMP4/CMAF 세그먼트에 대한 Content-Type 강제 수정
            // CDN이 잘못된 MIME 타입으로 응답하는 경우 처리
            let lower = contentType.lowercased()
            let lowerURL = targetURL.lowercased()
            if lower.contains("mp2t") {
                self.logger.info("Proxy: Content-Type fix mp2t→mp4: [\(urlSuffix, privacy: .public)]")
                contentType = "video/mp4"
            } else if (lower.contains("quicktime") || lower.contains("octet-stream"))
                      && (lowerURL.hasSuffix(".m4s") || lowerURL.hasSuffix(".m4v")
                          || lowerURL.contains(".m4v?") || lowerURL.contains(".m4s?")) {
                self.logger.info("Proxy: Content-Type fix \(origContentType)→video/mp4: [\(urlSuffix, privacy: .public)]")
                contentType = "video/mp4"
            }
            
            // M3U8 응답의 URL 재작성 (동일 CDN 호스트 + 크로스CDN 절대 URL 모두 처리)
            var responseData = data
            let isM3U8 = contentType.contains("mpegurl") ||
                         targetURL.contains(".m3u8") ||
                         (String(data: data.prefix(20), encoding: .utf8)?.contains("#EXTM3U") == true)
            
            if isM3U8 {
                if var m3u8Content = String(data: data, encoding: .utf8) {
                    // 1) 현재 타겟 호스트의 절대 URL 재작성 (기존 방식)
                    let sameHostOriginal = "\(self.targetScheme)://\(self.targetHost)"
                    let proxyBase = "http://127.0.0.1:\(self.port)"
                    m3u8Content = m3u8Content.replacingOccurrences(of: sameHostOriginal, with: proxyBase)
                    
                    // 2) 크로스CDN 절대 URL 재작성 (/_p_/HOST/path 인코딩)
                    // Chzzk CDN에서 M3U8에 다른 CDN 호스트의 절대 URL이 포함될 수 있음
                    // 예: https://ex-nlive-streaming.navercdn.com/... → /_p_/ex-nlive-streaming.navercdn.com/...
                    let regex = LocalStreamProxy.cdnRegex
                    let range = NSRange(m3u8Content.startIndex..., in: m3u8Content)
                    // 매칭된 호스트 수집
                    var crossHosts = Set<String>()
                    regex.enumerateMatches(in: m3u8Content, range: range) { match, _, _ in
                        guard let match,
                              let hostRange = Range(match.range(at: 1), in: m3u8Content) else { return }
                        let host = String(m3u8Content[hostRange])
                        if host != self.targetHost { crossHosts.insert(host) }
                    }
                    // 크로스CDN 호스트를 순서대로 재작성
                    for cdnHost in crossHosts {
                        let crossOriginal = "https://\(cdnHost)"
                        let crossReplacement = "\(proxyBase)/_p_/\(cdnHost)"
                        m3u8Content = m3u8Content.replacingOccurrences(of: crossOriginal, with: crossReplacement)
                        self.logger.info("Proxy: cross-CDN URL rewrite \(cdnHost) → /_p_/\(cdnHost)")
                    }
                    
                    responseData = m3u8Content.data(using: .utf8) ?? data
                    
                    if !contentType.contains("mpegurl") {
                        contentType = "application/vnd.apple.mpegurl"
                    }
                }
            }
            
            self.sendResponse(to: connection, status: httpResponse.statusCode, contentType: contentType, data: responseData, requestNum: requestNum)
        }.resume()
    }
    
    // MARK: - HTTP Response Helpers (Keep-Alive)
    
    private func sendResponse(to connection: NWConnection, status: Int, contentType: String, data: Data, requestNum: Int) {
        var header = "HTTP/1.1 \(status) OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: keep-alive\r\n"
        header += "Keep-Alive: timeout=\(Int(keepAliveTimeout))\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "\r\n"
        
        var fullResponse = Data(header.utf8)
        fullResponse.append(data)
        
        connection.send(content: fullResponse, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Proxy response send failed: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                return
            }
            self?.readHTTPRequest(from: connection, requestCount: requestNum)
        })
    }
    
    private func sendError(to connection: NWConnection, status: Int, message: String, keepAlive: Bool) {
        let body = message.data(using: .utf8) ?? Data()
        var header = "HTTP/1.1 \(status) \(message)\r\n"
        header += "Content-Type: text/plain\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        header += "\r\n"
        
        var fullResponse = Data(header.utf8)
        fullResponse.append(body)
        
        connection.send(content: fullResponse, contentContext: .defaultMessage, isComplete: !keepAlive, completion: .contentProcessed { [weak self] _ in
            if keepAlive {
                self?.readHTTPRequest(from: connection, requestCount: 0)
            } else {
                connection.cancel()
            }
        })
    }
}

// MARK: - Proxy Error

public enum ProxyError: Error, LocalizedError, Sendable {
    case startTimeout
    case invalidRequest
    
    public var errorDescription: String? {
        switch self {
        case .startTimeout: "프록시 시작 시간 초과"
        case .invalidRequest: "잘못된 요청"
        }
    }
}
