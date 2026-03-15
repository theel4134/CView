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
        var isStarting = false // 동시 start() 호출 경쟁 조건 방지
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
    private let activeConnectionCount = Mutex<Int>(0)
    private let maxActiveConnections = ProxyDefaults.maxActiveConnections
    
    /// CDN 인증 실패(403) 연속 카운터 — 토큰 만료 감지용
    private let _consecutive403Count = Mutex<Int>(0)
    private let _consecutive403Threshold = 3
    
    /// CDN 인증 실패 콜백 — 연속 403 감지 시 StreamCoordinator에 통보
    public var onUpstreamAuthFailure: (@Sendable () -> Void)?

    // MARK: - Network Stats (실시간 모니터링용)

    /// 누적 통계 카운터 — Mutex로 스레드 안전 보장
    private struct _NetworkCounters: Sendable {
        var totalRequests: Int = 0
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
        var errorCount: Int = 0
        var totalBytesReceived: Int64 = 0
        var totalBytesServed: Int64 = 0
    }
    private let _netCounters = Mutex(_NetworkCounters())

    /// CDN 응답 시간 슬라이딩 윈도우 (최근 20개)
    private let _responseTimes = Mutex<[Double]>([])
    private let _responseTimeWindowSize = 20

    /// 네트워크 통계 스냅샷 생성
    public func networkStats() -> ProxyNetworkStats {
        let counters = _netCounters.withLock { $0 }
        let (avg, max_) = _responseTimes.withLock { times -> (Double, Double) in
            guard !times.isEmpty else { return (0, 0) }
            let sum = times.reduce(0, +)
            return (sum / Double(times.count), times.max() ?? 0)
        }
        let active = activeConnectionCount.withLock { $0 }
        let c403 = _consecutive403Count.withLock { $0 }

        return ProxyNetworkStats(
            totalRequests: counters.totalRequests,
            cacheHits: counters.cacheHits,
            cacheMisses: counters.cacheMisses,
            errorCount: counters.errorCount,
            totalBytesReceived: counters.totalBytesReceived,
            totalBytesServed: counters.totalBytesServed,
            activeConnections: active,
            consecutive403Count: c403,
            avgResponseTime: avg,
            maxResponseTime: max_
        )
    }

    /// 통계 리셋 (세션 종료 시)
    public func resetNetworkStats() {
        _netCounters.withLock { $0 = _NetworkCounters() }
        _responseTimes.withLock { $0.removeAll() }
    }

    // MARK: - M3U8 Response Cache
    // VLC adaptive 모듈은 M3U8를 ~1ms 간격으로 폴링 (39K+ 회/35초)
    // CDN에 매번 요청하면 프록시 과부하 → 세그먼트 응답 지연 → 버퍼링 고착
    // 1초 TTL 캐싱으로 동일 M3U8 반복 요청을 즉시 응답 → CDN 요청 ~1000배 감소
    private struct M3U8CacheEntry: Sendable {
        let data: Data
        let contentType: String
        let statusCode: Int
        let timestamp: Date
    }
    private let _m3u8Cache = Mutex<[String: M3U8CacheEntry]>([:])
    // [Fix 16h-opt3] 0.5→0.3초: 새 세그먼트 감지 속도 40% 향상 → 초기 버퍼링 단축
    private let _m3u8CacheTTL: TimeInterval = 0.3
    private let _m3u8DebugCount = Mutex<Int>(0)

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
        // 동시 start() 호출 경쟁 조건 방지:
        // 멀티라이브 복원 시 여러 세션이 동시에 start() 호출 가능
        // → 이미 시작 중이면 시작 완료될 때까지 대기 후 기존 포트 반환
        let state = proxyState.withLock { s -> (running: Bool, starting: Bool, port: UInt16, sameHost: Bool) in
            (s.isRunning, s.isStarting, s.port, s.targetHost == host)
        }
        
        if state.running && state.sameHost && state.port > 0 {
            logger.info("Proxy already running: localhost:\(state.port) → \(host)")
            return state.port
        }
        
        if state.starting && state.sameHost {
            // 다른 호출이 시작 중 — 완료 대기 (최대 5초)
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초
                let current = proxyState.withLock { ($0.isRunning, $0.port) }
                if current.0 && current.1 > 0 {
                    logger.info("Proxy start wait complete: localhost:\(current.1) → \(host)")
                    return current.1
                }
            }
            // 타임아웃 — 이전 시작이 실패했을 수 있으므로 새로 시작
        }
        
        // isStarting 플래그 설정
        proxyState.withLock { $0.isStarting = true }
        defer { proxyState.withLock { $0.isStarting = false } }
        
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
        activeConnectionCount.withLock { $0 = 0 }
        _consecutive403Count.withLock { $0 = 0 }
        _m3u8Cache.withLock { $0.removeAll() }
        resetNetworkStats()
        onUpstreamAuthFailure = nil
        logger.info("Proxy stopped, session invalidated")
    }
    
    /// 프록시 세션만 리셋 — stale 연결 풀 + M3U8 캐시 정리 (재연결 시 사용)
    public func resetSession() {
        _proxySession?.invalidateAndCancel()
        _proxySession = nil
        _consecutive403Count.withLock { $0 = 0 }
        // 재연결 시 stale 매니페스트 캐시 제거 — 새 CDN 토큰이 반영된 URL 사용 보장
        _m3u8Cache.withLock { $0.removeAll() }
        logger.info("Proxy session reset — stale connections + M3U8 cache cleared")
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
        let count = activeConnectionCount.withLock { count -> Int in
            count += 1
            return count
        }
        if count > maxActiveConnections {
            logger.warning("Proxy: max connections (\(self.maxActiveConnections)) exceeded, rejecting")
            activeConnectionCount.withLock { $0 -= 1 }
            connection.cancel()
            return
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled:
                self?.activeConnectionCount.withLock { $0 -= 1 }
            case .failed:
                // cancel() 전에 handler를 nil로 설정하여 .cancelled 재진입 방지 → 이중 decrement 방지
                connection.stateUpdateHandler = nil
                self?.activeConnectionCount.withLock { $0 -= 1 }
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
            
            // [Fix 16d] 프록시 요청 로깅 (debug 레벨로 전환 — CPU 절약)
            if reqNum <= 10 {
                let pathSuffix = String(path.suffix(120))
                self.logger.debug("[PROXY-REQ] #\(reqNum, privacy: .public) GET \(pathSuffix, privacy: .public)")
            }

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
        
        // [Fix 16] M3U8 캐시 히트 체크 — VLC의 초고속 M3U8 폴링을 CDN 요청 없이 즉시 응답
        let isLikelyM3U8 = targetURL.contains(".m3u8") || targetURL.contains("chunklist") || targetURL.contains("mpegurl")
        if isLikelyM3U8 {
            let cached = _m3u8Cache.withLock { cache -> M3U8CacheEntry? in
                guard let entry = cache[targetURL],
                      Date().timeIntervalSince(entry.timestamp) < self._m3u8CacheTTL else { return nil }
                return entry
            }
            if let cached {
                // [Fix 16h] M3U8도 keep-alive 유지 — http-continuous 제거로
                // VLC가 Content-Length 존중하여 응답 완료 인식
                self._netCounters.withLock { c in
                    c.totalRequests += 1
                    c.cacheHits += 1
                    c.totalBytesServed += Int64(cached.data.count)
                }
                sendResponse(to: connection, status: cached.statusCode, contentType: cached.contentType, data: cached.data, requestNum: requestNum)
                return
            }
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
        
        let requestStart = CFAbsoluteTimeGetCurrent()
        proxySession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                connection.cancel()
                return
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - requestStart
            
            guard let data, let httpResponse = response as? HTTPURLResponse else {
                self._netCounters.withLock { c in
                    c.totalRequests += 1
                    c.cacheMisses += 1
                    c.errorCount += 1
                }
                self.sendError(to: connection, status: 502, message: "Bad Gateway", keepAlive: true)
                return
            }
            
            // 응답 시간 기록 (슬라이딩 윈도우)
            self._responseTimes.withLock { times in
                times.append(elapsed)
                if times.count > self._responseTimeWindowSize {
                    times.removeFirst(times.count - self._responseTimeWindowSize)
                }
            }

            // Content-Type 수정 (fMP4 → mp4)
            var contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"

            // 에러 응답만 로그 (정상 세그먼트 로그 억제 — 초당 수십 건 발생)
            if httpResponse.statusCode >= 400 {
                self._netCounters.withLock { c in
                    c.totalRequests += 1
                    c.cacheMisses += 1
                    c.errorCount += 1
                    c.totalBytesReceived += Int64(data.count)
                }
                let urlSuffix = String(targetURL.suffix(80))
                self.logger.warning("Proxy → CDN res#\(requestNum, privacy: .public): HTTP \(httpResponse.statusCode, privacy: .public) [\(urlSuffix, privacy: .public)]")
                
                // CDN 토큰 만료 감지: 403 연속 발생 시 상위에 통보
                if httpResponse.statusCode == 403 {
                    let count = self._consecutive403Count.withLock { c -> Int in
                        c += 1
                        return c
                    }
                    if count == self._consecutive403Threshold {
                        self.logger.warning("Proxy: CDN 403 \(count)회 연속 — 토큰 만료 의심, 상위 통보")
                        self.onUpstreamAuthFailure?()
                    }
                }
            } else {
                // 정상 응답(2xx/3xx) 시 403 카운터 리셋
                self._consecutive403Count.withLock { $0 = 0 }
                self._netCounters.withLock { c in
                    c.totalRequests += 1
                    c.cacheMisses += 1
                    c.totalBytesReceived += Int64(data.count)
                }
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
                    // [Fix 16d] M3U8 내용 디버그 로깅 (최초 5회만, %문자 안전 처리)
                    let debugCount = self._m3u8DebugCount.withLock { c -> Int in
                        c += 1
                        return c
                    }
                    if debugCount <= 3 {
                        self.logger.debug("[PROXY-M3U8] #\(debugCount, privacy: .public) CDN target: \(String(targetURL.suffix(80)), privacy: .public)")
                    }
                    
                    // 1단계: 절대 CDN URL → 프록시 URL (기존 로직)
                    let proxyBase = "http://127.0.0.1:\(self.port)"
                    var rewritten = self.rewriteM3U8URLs(m3u8Content, proxyBase: proxyBase)
                    
                    // [Fix 16d] 2단계: 모든 상대 URL → 절대 프록시 URL
                    // master playlist의 variant URL + chunklist의 segment URL 모두 처리
                    // VLC가 %2f 포함 경로에서 상대 URL 해석 실패 → 전부 절대 URL로 변환
                    let basePath = self.extractDirectoryPath(from: targetURL)
                    rewritten = self.makeRelativeURLsAbsolute(rewritten, proxyBase: proxyBase, basePath: basePath)
                    
                    if debugCount <= 3 {
                        let rewrittenPreview = String(rewritten.prefix(400))
                        self.logger.debug("[PROXY-M3U8] #\(debugCount, privacy: .public) REWRITTEN (basePath=\(basePath, privacy: .public)):\n\(rewrittenPreview, privacy: .public)")
                    }
                    
                    responseData = rewritten.data(using: .utf8) ?? data
                    
                    if !contentType.contains("mpegurl") {
                        contentType = "application/vnd.apple.mpegurl"
                    }
                }
            }
            
            // [Fix 16] M3U8 응답 캐싱 — URL 재작성 후 최종 데이터를 캐시
            if isM3U8 {
                self._m3u8Cache.withLock { cache in
                    cache[targetURL] = M3U8CacheEntry(
                        data: responseData,
                        contentType: contentType,
                        statusCode: httpResponse.statusCode,
                        timestamp: Date()
                    )
                }
            }
            
            // [Fix 16h] 모든 응답 keep-alive — http-continuous 제거로
            // VLC HTTP 모듈이 Content-Length 기반 응답 완료 올바르게 인식
            self._netCounters.withLock { $0.totalBytesServed += Int64(responseData.count) }
            self.sendResponse(to: connection, status: httpResponse.statusCode, contentType: contentType, data: responseData, requestNum: requestNum)
        }.resume()
    }
    
    // MARK: - HTTP Response Helpers (Keep-Alive)
    
    private func sendResponse(to connection: NWConnection, status: Int, contentType: String, data: Data, requestNum: Int, keepAlive: Bool = true) {
        var header = "HTTP/1.1 \(status) OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        if keepAlive {
            header += "Connection: keep-alive\r\n"
            header += "Keep-Alive: timeout=\(Int(keepAliveTimeout))\r\n"
        } else {
            header += "Connection: close\r\n"
        }
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "\r\n"
        
        var fullResponse = Data(header.utf8)
        fullResponse.append(data)
        
        connection.send(content: fullResponse, contentContext: .defaultMessage, isComplete: !keepAlive, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.debug("Proxy response send: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                return
            }
            if keepAlive {
                self?.readHTTPRequest(from: connection, requestCount: requestNum)
            } else {
                connection.cancel()
            }
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
    
    // MARK: - [Fix 16d] M3U8 URL Absolutization
    
    /// CDN URL에서 디렉토리 경로 추출 (percent-encoding 보존)
    /// "https://host/path/to/file.m3u8?q=v" → "/path/to/"
    private func extractDirectoryPath(from urlString: String) -> String {
        guard let protEnd = urlString.range(of: "://") else { return "/" }
        let rest = urlString[protEnd.upperBound...]
        guard let pathStart = rest.firstIndex(of: "/") else { return "/" }
        var path = String(rest[pathStart...])
        // 쿼리 스트링 제거
        if let qIdx = path.firstIndex(of: "?") {
            path = String(path[..<qIdx])
        }
        // 마지막 '/' 까지가 디렉토리 (% 인코딩된 %2f는 무시 — 실제 '/'만 기준)
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[...lastSlash])
        }
        return "/"
    }
    
    /// M3U8 내 모든 상대 URL을 절대 프록시 URL로 변환
    /// master playlist의 variant URL + chunklist의 segment URL 모두 처리
    /// VLC가 %2f 포함 경로에서 상대 URL 해석 실패 → 절대 URL로 우회
    private func makeRelativeURLsAbsolute(_ content: String, proxyBase: String, basePath: String) -> String {
        content.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let lineStr = String(line)
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // #EXT-X-MAP:URI="..." → 절대 URL로 변환
            if trimmed.hasPrefix("#EXT-X-MAP:") {
                if let uriStart = lineStr.range(of: "URI=\""),
                   let closingQuote = lineStr[uriStart.upperBound...].firstIndex(of: "\"") {
                    let uri = String(lineStr[uriStart.upperBound..<closingQuote])
                    if !uri.hasPrefix("http") {
                        let absolute = "\(proxyBase)\(basePath)\(uri)"
                        return lineStr.replacingCharacters(in: uriStart.upperBound..<closingQuote, with: absolute)
                    }
                }
                return lineStr
            }
            
            // 빈 줄, 주석 줄 → 그대로 통과
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return lineStr
            }
            
            // 비-# 줄 = URI (variant 또는 segment) → 상대이면 절대로 변환
            if !trimmed.hasPrefix("http") {
                return "\(proxyBase)\(basePath)\(trimmed)"
            }
            
            return lineStr
        }.joined(separator: "\n")
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
    private let state = Mutex<CheckedContinuation<UInt16, any Error>?>(nil)
    
    init(continuation: CheckedContinuation<UInt16, any Error>) {
        state.withLock { $0 = continuation }
    }
    
    func resumeOnce(returning value: UInt16) {
        state.withLock { cont in
            guard let c = cont else { return }
            cont = nil
            c.resume(returning: value)
        }
    }
    
    func resumeOnce(throwing error: any Error) {
        state.withLock { cont in
            guard let c = cont else { return }
            cont = nil
            c.resume(throwing: error)
        }
    }
}
