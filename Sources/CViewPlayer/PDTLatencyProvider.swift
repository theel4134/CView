// MARK: - PDTLatencyProvider.swift
// CViewPlayer - #EXT-X-PROGRAM-DATE-TIME 기반 실제 레이턴시 측정 (Method A)
//
// 웹 플레이어와 동일한 기준으로 레이턴시를 계산:
//  latency = Date.now - (lastSegment.PDT + lastSegment.duration)
//
// 이 값은 실제로 방송이 캡처된 시각 대비 현재 재생 중인 콘텐츠의 지연을 나타냄.
// VLC 내부 duration - currentTime 방식보다 훨씬 정확한 절대 시간 기준.

import Foundation
import os.log

// MARK: - PDTLatencyProvider

/// HLS 미디어 플레이리스트를 주기적으로 폴링해서 PDT 기반 절대 레이턴시를 측정하는 actor.
///
/// 치지직 CDN의 HLS 스트림은 각 세그먼트에 `#EXT-X-PROGRAM-DATE-TIME` 태그가 붙어 있음.
/// 마지막 세그먼트의 PDT + duration = 라이브 엣지 시각이며,
/// 현재 시각에서 이를 빼면 실제 엔드-투-엔드 레이턴시를 구할 수 있음.
public actor PDTLatencyProvider {
    
    // MARK: - State
    
    private var pollTask: Task<Void, Never>?
    private var _latency: TimeInterval?
    private var _isReady = false
    private let parser = HLSManifestParser()
    private let logger = Logger(subsystem: "com.cview", category: "PDTLatency")
    
    // MARK: - Configuration
    
    private let playlistURL: URL
    private let pollInterval: TimeInterval
    
    // PDT 샘플의 보정용 EWMA (지터 노이즈 제거)
    private var ewmaLatency: TimeInterval?
    private let ewmaAlpha: TimeInterval = 0.3   // 빠른 반응 / 노이즈 억제 균형
    
    // MARK: - Init
    
    public init(playlistURL: URL, pollInterval: TimeInterval = 2.0) {
        self.playlistURL = playlistURL
        self.pollInterval = pollInterval
    }
    
    // MARK: - Public API
    
    /// 폴링 시작
    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do {
                    try await Task.sleep(for: .seconds(self?.pollInterval ?? 2.0))
                } catch {
                    break  // Task cancelled
                }
            }
        }
        logger.info("PDTLatencyProvider started: \(self.playlistURL.lastPathComponent, privacy: .public)")
    }
    
    /// 폴링 중지
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        _latency = nil
        _isReady = false
        ewmaLatency = nil
        logger.info("PDTLatencyProvider stopped")
    }
    
    /// 현재 PDT 기반 레이턴시 (nil = 아직 측정 전 또는 측정 불가)
    public func currentLatency() -> TimeInterval? {
        return _latency
    }
    
    /// PDT 측정값이 준비됐는지 여부
    public var isReady: Bool { _isReady }
    
    // MARK: - Private
    
    private func poll() async {
        var request = URLRequest(url: playlistURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
        // 캐시 무효화 - 매번 최신 플레이리스트를 가져와야 함
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let content = String(data: data, encoding: .utf8) else { return }
            
            // 미디어 플레이리스트 파싱
            let playlist = try parser.parseMediaPlaylist(content: content, baseURL: playlistURL)
            
            // 마지막 세그먼트의 PDT를 기준으로 레이턴시 계산
            guard let lastSegment = playlist.segments.last,
                  let pdt = lastSegment.programDateTime else {
                // PDT 없는 플레이리스트 - 폴링하되 값은 nil 유지
                logger.debug("PDT not found in playlist, skipping")
                return
            }
            
            // 라이브 엣지 시각 = PDT + 세그먼트 길이
            let liveEdge = pdt.addingTimeInterval(lastSegment.duration)
            let rawLatency = Date().timeIntervalSince(liveEdge)
            
            // 비현실적인 값 필터링 (음수 or 60초 초과)
            guard rawLatency >= 0, rawLatency < 60 else {
                logger.warning("PDT latency out of range: \(rawLatency, format: .fixed(precision: 2))s – skipped")
                return
            }
            
            // EWMA로 노이즈 제거
            if let prev = ewmaLatency {
                ewmaLatency = ewmaAlpha * rawLatency + (1 - ewmaAlpha) * prev
            } else {
                ewmaLatency = rawLatency  // 첫 샘플은 그대로
            }
            
            _latency = ewmaLatency
            _isReady = true
            
            logger.debug("PDT latency: raw=\(rawLatency, format: .fixed(precision: 2))s ewma=\(self.ewmaLatency ?? 0, format: .fixed(precision: 2))s")
            
        } catch {
            logger.debug("PDT poll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
