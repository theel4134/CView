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
    
    var listener: NWListener?
    let targetScheme = "https"
    
    /// isRunning / port / targetHost 동시 접근 보호 — Swift Concurrency 안전한 Mutex 사용
    struct ProxyState: Sendable {
        var isRunning = false
        var port: UInt16 = 0
        var targetHost: String = ""
        var isStarting = false // 동시 start() 호출 경쟁 조건 방지
    }
    let proxyState = Mutex(ProxyState())
    
    /// 외부 접근용 computed property
    public var port: UInt16 { proxyState.withLock { $0.port } }
    public var targetHost: String { proxyState.withLock { $0.targetHost } }
    
    /// CDN 절대 URL 검출 정규식 — 매 M3U8 요청마다 컴파일하지 않도록 캐시
    static let cdnRegex: NSRegularExpression = {
        let pattern = "https://([a-zA-Z0-9][a-zA-Z0-9.-]*(?:navercdn\\.com|pstatic\\.net|naver\\.com|akamaized\\.net))"
        // 패턴이 고정되어 있으므로 try! 는 안전
        return try! NSRegularExpression(pattern: pattern) // swiftlint:disable:this force_try
    }()
    
    /// 활성 NWConnection 추적 — stop() 시 일괄 cancel용 + 연결 수 제한
    /// [Fix 26A] 기존 Int 카운터 → 실제 참조 컬렉션으로 변경하여 CLOSE_WAIT 누수 방지
    let _activeConnections = Mutex<Set<NWConnectionWrapper>>([])
    let maxActiveConnections = ProxyDefaults.maxActiveConnections
    
    /// NWConnection을 Set에 저장하기 위한 ObjectIdentifier 기반 래퍼
    final class NWConnectionWrapper: Hashable, Sendable {
        let connection: NWConnection
        nonisolated init(_ connection: NWConnection) { self.connection = connection }
        nonisolated static func == (lhs: NWConnectionWrapper, rhs: NWConnectionWrapper) -> Bool {
            ObjectIdentifier(lhs.connection) == ObjectIdentifier(rhs.connection)
        }
        nonisolated func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(connection))
        }
    }
    
    /// CDN 인증 실패(403) 연속 카운터 — 토큰 만료 감지용
    let _consecutive403Count = Mutex<Int>(0)
    let _consecutive403Threshold = 3
    
    /// CDN 인증 실패 콜백 — 연속 403 감지 시 StreamCoordinator에 통보
    public var onUpstreamAuthFailure: (@Sendable () -> Void)?

    // MARK: - Network Stats (실시간 모니터링용)

    /// 누적 통계 카운터 — Mutex로 스레드 안전 보장
    struct _NetworkCounters: Sendable {
        var totalRequests: Int = 0
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
        var errorCount: Int = 0
        var totalBytesReceived: Int64 = 0
        var totalBytesServed: Int64 = 0
    }
    let _netCounters = Mutex(_NetworkCounters())

    /// CDN 응답 시간 슬라이딩 윈도우 (최근 20개)
    let _responseTimes = Mutex<[Double]>([])
    let _responseTimeWindowSize = 20

    /// 네트워크 통계 스냅샷 생성
    public func networkStats() -> ProxyNetworkStats {
        let counters = _netCounters.withLock { $0 }
        let (avg, max_) = _responseTimes.withLock { times -> (Double, Double) in
            guard !times.isEmpty else { return (0, 0) }
            let sum = times.reduce(0, +)
            return (sum / Double(times.count), times.max() ?? 0)
        }
        let active = _activeConnections.withLock { $0.count }
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
    struct M3U8CacheEntry: Sendable {
        let data: Data
        let contentType: String
        let statusCode: Int
        let timestamp: Date
    }
    let _m3u8Cache = Mutex<[String: M3U8CacheEntry]>([:])
    // [Fix 19] 0.3→0.8초: CDN 중복 요청 감소 + 세그먼트 도착 지터 흡수
    // 2초 세그먼트 기준 매니페스트 갱신 주기(~1s)의 80% 커버
    let _m3u8CacheTTL: TimeInterval = 0.8
    /// 캐시 최대 엔트리 수 — CDN 토큰 변경으로 URL 키가 누적되므로 제한 필수
    let _m3u8CacheMaxEntries = 50
    let _m3u8DebugCount = Mutex<Int>(0)

    let queue = DispatchQueue(label: "com.cview.streamproxy", qos: .userInteractive, attributes: .concurrent)
    let logger = AppLogger.player
    
    let keepAliveTimeout = ProxyDefaults.keepAliveTimeout
    
    /// URLSession 인스턴스 — Mutex로 동시 접근 시 이중 생성 방지
    let _proxySessionStorage = Mutex<URLSession?>(nil)
    
    var proxySession: URLSession {
        _proxySessionStorage.withLock { session in
            if let existing = session { return existing }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = ProxyDefaults.requestTimeout
            config.timeoutIntervalForResource = ProxyDefaults.resourceTimeout
            config.httpMaximumConnectionsPerHost = ProxyDefaults.maxConnectionsPerHost
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let newSession = URLSession(configuration: config)
            session = newSession
            return newSession
        }
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
        // [Fix 26A] 모든 활성 NWConnection을 명시적으로 cancel — CLOSE_WAIT 방지
        let connections = _activeConnections.withLock { conns -> Set<NWConnectionWrapper> in
            let snapshot = conns
            conns.removeAll()
            return snapshot
        }
        for wrapper in connections {
            wrapper.connection.stateUpdateHandler = nil  // .cancelled 콜백에서 이중 제거 방지
            wrapper.connection.cancel()
        }
        // proxySession 무효화 — 장시간 재생 시 URLSession 연결 풀 축적 방지
        _proxySessionStorage.withLock { session in
            session?.invalidateAndCancel()
            session = nil
        }
        proxyState.withLock {
            $0.isRunning = false
            $0.port = 0
            $0.targetHost = ""
        }
        // _activeConnections는 stop()에서 이미 정리됨
        _consecutive403Count.withLock { $0 = 0 }
        _m3u8Cache.withLock { $0.removeAll() }
        resetNetworkStats()
        onUpstreamAuthFailure = nil
        logger.info("Proxy stopped, session invalidated")
    }
    
    /// 프록시 세션만 리셋 — stale 연결 풀 + M3U8 캐시 정리 (재연결 시 사용)
    public func resetSession() {
        _proxySessionStorage.withLock { session in
            session?.invalidateAndCancel()
            session = nil
        }
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
        // 활성 연결 수 제한 — 연결 누수 시 시스템 자원 고갈 방지
