// MARK: - LocalStreamProxy+Upstream.swift
// CViewPlayer - Connection Handling + Upstream Proxying

import Foundation
import Network
import CViewCore

extension LocalStreamProxy {
    
    // MARK: - Connection Handling (HTTP/1.1 Keep-Alive)
    
    func handleConnection(_ connection: NWConnection) {
        // [Fix 32 / SEC-6] Defense-in-depth: 원격 endpoint 검증 — loopback이 아니면 거절
        // requiredInterfaceType = .loopback 이 1차 방어이고, 이것은 2차 방어 (설정 누락 대비).
        if case let .hostPort(host, _) = connection.endpoint {
            let isLocal: Bool
            switch host {
            case .ipv4(let addr): isLocal = (addr == .loopback)
            case .ipv6(let addr): isLocal = (addr == .loopback)
            case .name(let name, _): isLocal = (name == "localhost")
            @unknown default: isLocal = false
            }
            guard isLocal else {
                logger.warning("Proxy: rejecting non-loopback connection from \(String(describing: host), privacy: .public)")
                connection.cancel()
                return
            }
        }
        
        let wrapper = NWConnectionWrapper(connection)
        // [Fix 26A] 활성 연결 추적 — stop() 시 일괄 cancel 가능
        let count = _activeConnections.withLock { conns -> Int in
            conns.insert(wrapper)
            return conns.count
        }
        if count > maxActiveConnections {
            logger.warning("Proxy: max connections (\(self.maxActiveConnections)) exceeded, rejecting")
            _activeConnections.withLock { $0.remove(wrapper) }
            connection.cancel()
            return
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled:
                self?._activeConnections.withLock { $0.remove(wrapper) }
            case .failed:
                connection.stateUpdateHandler = nil
                self?._activeConnections.withLock { $0.remove(wrapper) }
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        readHTTPRequest(from: connection, requestCount: 0)
    }
    
    func readHTTPRequest(from connection: NWConnection, requestCount: Int) {
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
            
            if isComplete && (data?.isEmpty ?? true) {
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
    
    func extractPath(from request: String) -> String? {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }
    
    // MARK: - Upstream Proxying
    
    func proxyToUpstream(targetURL: String, connection: NWConnection, requestNum: Int) {
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

        // [P0-5 2026-04-24] 미디어 세그먼트는 chunk-streaming 경로로 분리.
        //   기존: 세그먼트 전체를 메모리에 모은 뒤 한 번에 sendResponse → 첫 바이트 지연 + 4채널 burst.
        //   변경: URLSessionDataDelegate 로 chunk 즉시 forward → VLC demux 입력 평활화.
        //   M3U8 은 URL rewrite/캐싱 필요로 기존 경로 유지.
        if !isLikelyM3U8 {
            proxyToUpstreamStreaming(targetURL: targetURL, connection: connection, requestNum: requestNum)
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

        // [패킷 압축] M3U8 매니페스트만 gzip 요청 — 텍스트는 70-85% 압축, 세그먼트는 이미
        // 압축된 바이너리라 CPU만 소모하므로 제외. URLSession은 gzip 응답을 자동 해제하므로
        // VLC에는 평문으로 전달되어 프로토콜 변경 없이 업스트림 대역폭만 절감된다.
        if isLikelyM3U8 {
            request.setValue(ProxyDefaults.manifestAcceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        }
        
        let requestStart = CFAbsoluteTimeGetCurrent()
        proxySession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                connection.cancel()
                return
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - requestStart
            
            guard let data, let httpResponse = response as? HTTPURLResponse else {
                if let error {
                    self.logger.warning("Proxy upstream error: \(error.localizedDescription, privacy: .public)")
                } else {
                    self.logger.warning("Proxy upstream: nil data or non-HTTP response")
                }
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
                    if count >= self._consecutive403Threshold {
                        // 즉시 리셋하여 재트리거 가능하게 함
                        self._consecutive403Count.withLock { $0 = 0 }
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
                    // stale 엔트리 제거 + 최대 사이즈 제한 (CDN 토큰 변경으로 URL 키 누적 방지)
                    if cache.count >= self._m3u8CacheMaxEntries {
                        let now = Date()
                        let ttl = self._m3u8CacheTTL * 3 // stale 기준: TTL의 3배
                        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < ttl }
                        // 여전히 초과하면 가장 오래된 절반 제거
                        if cache.count >= self._m3u8CacheMaxEntries {
                            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
                            let removeCount = cache.count / 2
                            for entry in sorted.prefix(removeCount) {
                                cache.removeValue(forKey: entry.key)
                            }
                        }
                    }
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
}
