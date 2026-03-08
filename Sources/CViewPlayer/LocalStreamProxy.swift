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
import Synchronization
import CViewCore

public final class LocalStreamProxy: @unchecked Sendable {
    
    public static let shared = LocalStreamProxy()
    
    // MARK: - Properties
    
    private var listener: NWListener?
    private let targetScheme = "https"
    
    /// isRunning / port / targetHost 동시 접근 보호 — Swift Concurrency 안전한 Mutex 사용
    private struct ProxyState: Sendable {
        var isRunning = false
        var port: UInt16 = 0
        var targetHost: String = ""
    }
    private let proxyState = Mutex(ProxyState())
    
    /// 외부 접근용 computed property
    public var port: UInt16 { proxyState.withLock { $0.port } }
    public var targetHost: String { proxyState.withLock { $0.targetHost } }
    
    /// CDN 절대 URL 검출 정규식 — 매 M3U8 요청마다 컴파일하지 않도록 캐시
    private static let cdnRegex: NSRegularExpression = {
        let pattern = "https://([a-zA-Z0-9][a-zA-Z0-9.-]*(?:navercdn\\.com|pstatic\\.net|naver\\.com|akamaized\\.net))"
        // 패턴이 고정되어 있으므로 try! 는 안전
        return try! NSRegularExpression(pattern: pattern) // swiftlint:disable:this force_try
    }()
    
    /// 활성 NWConnection 수 추적 — 연결 누수 감지 및 제한용
    private var activeConnectionCount: Int = 0
    private let connectionCountLock = NSLock()
    private let maxActiveConnections = ProxyDefaults.maxActiveConnections

    private let queue = DispatchQueue(label: "com.cview.streamproxy", qos: .userInteractive, attributes: .concurrent)
    private let logger = AppLogger.player
    
    private let keepAliveTimeout = ProxyDefaults.keepAliveTimeout
    
    private var _proxySession: URLSession?
    
    private var proxySession: URLSession {
        if let existing = _proxySession { return existing }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = ProxyDefaults.requestTimeout
        config.timeoutIntervalForResource = ProxyDefaults.resourceTimeout
        config.httpMaximumConnectionsPerHost = ProxyDefaults.maxConnectionsPerHost
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        _proxySession = session
        return session
    }
    
    public init() {}
    
    // MARK: - Lifecycle
    
    @discardableResult
    public func start(for host: String) async throws -> UInt16 {
        // Mutex로 읽기/쓰기 경쟁 방지 (NSLock 대비 cooperative thread 안전)
        let alreadyRunning = proxyState.withLock { $0.isRunning && $0.targetHost == host && $0.port > 0 }
        if alreadyRunning {
            let p = proxyState.withLock { $0.port }
            logger.info("Proxy already running: localhost:\(p) → \(host)")
            return p
        }
        
        stop()
        proxyState.withLock { $0.targetHost = host }
        
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        
        // CheckedContinuation으로 cooperative thread 블로킹 방지
        // 기존 DispatchSemaphore.wait(3초)는 actor의 cooperative thread를 차단하여
        // actor 작업을 지연시키고 thread starvation을 유발했음
        let assignedPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            // Swift 6 strict concurrency: var를 concurrent 클로저에서 캡처 불가
            // Sendable 호환 atomicFlag 래퍼로 guard
            let onceGuard = _ProxyContinuationGuard(continuation: continuation)
            
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.proxyState.withLock {
                        $0.port = listener.port?.rawValue ?? 0
                        $0.isRunning = true
                    }
                    let p = self.proxyState.withLock { $0.port }
                    self.logger.info("Proxy started: localhost:\(p) → \(host)")
                    onceGuard.resumeOnce(returning: p)
                case .failed(let error):
                    self.logger.error("Proxy start failed: \(error.localizedDescription, privacy: .public)")
                    self.proxyState.withLock { $0.isRunning = false }
                    onceGuard.resumeOnce(throwing: error)
                case .cancelled:
                    self.proxyState.withLock { $0.isRunning = false }
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener.start(queue: self.queue)
            
            // 3초 타임아웃 — NWListener가 응답하지 않으면 에러 반환
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                onceGuard.resumeOnce(throwing: ProxyError.startTimeout)
            }
        }
        
        return assignedPort
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        // proxySession 무효화 — 장시간 재생 시 URLSession 연결 풀 축적 방지
        _proxySession?.invalidateAndCancel()
        _proxySession = nil
        proxyState.withLock {
            $0.isRunning = false
            $0.port = 0
            $0.targetHost = ""
        }
        connectionCountLock.withLock { activeConnectionCount = 0 }
        logger.info("Proxy stopped, session invalidated")
    }
    
    // MARK: - URL Transformation
    
    public func proxyURL(from originalURL: URL) -> URL {
        let (running, currentPort, currentHost) = proxyState.withLock {
            ($0.isRunning, $0.port, $0.targetHost)
        }
        guard running, currentPort > 0, !currentHost.isEmpty,
              let host = originalURL.host, host == currentHost else {
            return originalURL
        }
        
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        components?.scheme = "http"
        components?.host = "127.0.0.1"
        components?.port = Int(currentPort)
        
        return components?.url ?? originalURL
    }
    
    public func proxyURLString(_ originalURL: String) -> String {
        let (running, currentPort, currentHost) = proxyState.withLock {
            ($0.isRunning, $0.port, $0.targetHost)
        }
        guard running, currentPort > 0, !currentHost.isEmpty,
              originalURL.contains(currentHost) else {
            return originalURL
        }
        
        return originalURL.replacingOccurrences(
            of: "\(targetScheme)://\(currentHost)",
            with: "http://127.0.0.1:\(currentPort)"
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
        // 활성 연결 수 제한 — 연결 누수 시 시스템 자원 고갈 방지
        let count = connectionCountLock.withLock {
            activeConnectionCount += 1
            return activeConnectionCount
        }
        if count > maxActiveConnections {
            logger.warning("Proxy: max connections (\(self.maxActiveConnections)) exceeded, rejecting")
            connectionCountLock.withLock { activeConnectionCount -= 1 }
            connection.cancel()
            return
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled:
                self?.connectionCountLock.withLock { self?.activeConnectionCount -= 1 }
            case .failed:
                // cancel() 전에 handler를 nil로 설정하여 .cancelled 재진입 방지 → 이중 decrement 방지
                connection.stateUpdateHandler = nil
                self?.connectionCountLock.withLock { self?.activeConnectionCount -= 1 }
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        readHTTPRequest(from: connection, requestCount: 0)
    }
    
    private func readHTTPRequest(from connection: NWConnection, requestCount: Int) {
        let timeoutWorkItem = DispatchWorkItem {
            connection.cancel()
        }
        queue.asyncAfter(deadline: .now() + keepAliveTimeout, execute: timeoutWorkItem)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: ProxyDefaults.maxReceiveLength) { [weak self] data, _, isComplete, error in
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
        request.timeoutInterval = ProxyDefaults.upstreamRequestTimeout
        
        // [멀티CDN] 실제 업스트림 호스트 헤더 사용 (크로스CDN 요청 포함)
        request.setValue(upstreamHost, forHTTPHeaderField: "Host")
        request.setValue(
            CommonHeaders.safariUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        request.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        
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

            // 에러 응답만 로그 (정상 세그먼트 로그 억제 — 초당 수십 건 발생)
            if httpResponse.statusCode >= 400 {
                let urlSuffix = String(targetURL.suffix(80))
                self.logger.warning("Proxy → CDN res#\(requestNum, privacy: .public): HTTP \(httpResponse.statusCode, privacy: .public) [\(urlSuffix, privacy: .public)]")
            }

            // fMP4/CMAF 세그먼트에 대한 Content-Type 강제 수정
            // CDN이 잘못된 MIME 타입으로 응답하는 경우 처리
            let lower = contentType.lowercased()
            let lowerURL = targetURL.lowercased()
            if lower.contains("mp2t") {
                contentType = "video/mp4"
            } else if (lower.contains("quicktime") || lower.contains("octet-stream"))
                      && (lowerURL.hasSuffix(".m4s") || lowerURL.hasSuffix(".m4v")
                          || lowerURL.contains(".m4v?") || lowerURL.contains(".m4s?")) {
                contentType = "video/mp4"
            }
            
            // M3U8 응답의 URL 재작성 (동일 CDN 호스트 + 크로스CDN 절대 URL 모두 처리)
            var responseData = data
            let isM3U8 = contentType.contains("mpegurl") ||
                         targetURL.contains(".m3u8") ||
                         (String(data: data.prefix(20), encoding: .utf8)?.contains("#EXTM3U") == true)
            
            if isM3U8 {
                if let m3u8Content = String(data: data, encoding: .utf8) {
                    // 단일 패스 URL 재작성 — 정규식 1회 스캔으로 sameHost + crossCDN 동시 처리
                    // 기존: replacingOccurrences × (1 + N_크로스호스트) + regex 스캔 1회
                    // 개선: regex 1회 스캔 → 매치 역순 치환 (String 1회 복사)
                    let proxyBase = "http://127.0.0.1:\(self.port)"
                    let rewritten = self.rewriteM3U8URLs(m3u8Content, proxyBase: proxyBase)
                    
                    responseData = rewritten.data(using: .utf8) ?? data
                    
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
                self?.logger.debug("Proxy response send: \(error.localizedDescription, privacy: .public)")
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
    
    // MARK: - Single-Pass M3U8 URL Rewriting
    
    /// 단일 정규식 스캔으로 sameHost + crossCDN URL을 동시 치환
    /// 기존: replacingOccurrences×(1+N) + regex 1회 = O(M×(1+N))
    /// 개선: regex 1회 + 역순 치환 = O(M) (M=M3U8 길이)
    private func rewriteM3U8URLs(_ content: String, proxyBase: String) -> String {
        // https:// 뒤에 CDN 호스트가 오는 패턴 + 현재 타겟 호스트 모두 매치
        // cdnRegex는 navercdn.com|pstatic.net|naver.com|akamaized.net 호스트를 매치
        // 타겟 호스트도 포함되므로 단일 패스로 처리
        let regex = LocalStreamProxy.cdnRegex
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        
        // 모든 매치를 수집 (range가 큰 쪽부터 치환하기 위해)
        let matches = regex.matches(in: content, range: fullRange)
        guard !matches.isEmpty else { return content }
        
        var result = content
        // 역순으로 치환하여 앞쪽 인덱스가 무효화되지 않도록
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hostRange = Range(match.range(at: 1), in: result) else { continue }
            let host = String(result[hostRange])
            
            let replacement: String
            if host == targetHost {
                // 동일 호스트 → 프록시 주소로 직접 치환
                replacement = proxyBase
            } else {
                // 크로스CDN → /_p_/HOST 인코딩
                replacement = "\(proxyBase)/_p_/\(host)"
            }
            result.replaceSubrange(fullRange, with: replacement)
        }
        
        return result
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

// MARK: - Continuation Guard (Swift 6 Concurrency Safe)

/// CheckedContinuation을 정확히 한 번만 resume하도록 보장하는 스레드 안전 래퍼.
/// Swift 6 strict concurrency에서 var 캡처가 불가하므로 클래스 기반으로 구현.
private final class _ProxyContinuationGuard: @unchecked Sendable {
    private var continuation: CheckedContinuation<UInt16, any Error>?
    private let lock = NSLock()
    
    init(continuation: CheckedContinuation<UInt16, any Error>) {
        self.continuation = continuation
    }
    
    func resumeOnce(returning value: UInt16) {
        lock.withLock {
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(returning: value)
        }
    }
    
    func resumeOnce(throwing error: any Error) {
        lock.withLock {
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(throwing: error)
        }
    }
}
