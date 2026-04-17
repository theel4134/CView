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
import CViewCore

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
    // 전용 폴링 세션 — ephemeral(쿠키 격리) + 캐시 비활성화(라이브 플레이리스트)
    private nonisolated let hlsSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()
    
    // MARK: - Configuration
    
    private let playlistURL: URL
    private let pollInterval: TimeInterval
    
    // PDT 샘플의 보정용 EWMA (지터 노이즈 제거)
    private var ewmaLatency: TimeInterval?
    // [Fix 22C] α 0.3→0.2: 세그먼트 경계 톱니파(±2.1s 진폭) 노이즈 추가 억제
    private let ewmaAlpha: TimeInterval = 0.2
    
    /// 연속 범위 초과 카운터 — 15회 연속 실패 시 폴링 자동 중지 (30초간 유효 데이터 없음)
    private var _consecutiveOutOfRange: Int = 0
    private let _maxConsecutiveOutOfRange = 15
    
    // [Fix 20 Phase3] PDT 자동 재시도 — fallback 전환 후 주기적으로 PDT 복구 시도
    private var _retryTask: Task<Void, Never>?
    private let _retryInterval: TimeInterval = 60.0    // 재시도 간격 (초)
    private let _retryProbeCount: Int = 5              // 프로브 횟수
    private var _retryAttempts: Int = 0                // 총 재시도 횟수
    private let _maxRetryAttempts: Int = 10            // 최대 재시도 횟수 (10회 = ~10분)
    
    // [Fix 21] Clock Offset 자동 보정 — CDN/클라이언트 시계 편차 감지 및 보정
    private var _calibrationSamples: [TimeInterval] = []
    // [Fix 22C] 5→10 샘플: 세그먼트 경계 효과로 음수/양수 교대 → 5개로는 중앙값 불안정
    private let _calibrationCount: Int = 10
    private var _clockOffset: TimeInterval = 0         // 보정 오프셋 (양수 = 클라이언트 시계가 뒤처짐)
    private var _isCalibrated: Bool = false
    
    // MARK: - Init
    
    public init(playlistURL: URL, pollInterval: TimeInterval = 4.0) {
        self.playlistURL = playlistURL
        self.pollInterval = pollInterval
    }
    
    deinit {
        pollTask?.cancel()
        _retryTask?.cancel()
        hlsSession.invalidateAndCancel()
    }
    
    // MARK: - Public API
    
    /// 폴링 시작
    public func start() {
        guard pollTask == nil else { return }
        _retryTask?.cancel()
        _retryTask = nil
        _retryAttempts = 0
        // [Fix 21] 새 세션 시작 시 캘리브레이션 초기화
        _calibrationSamples.removeAll()
        _clockOffset = 0
        _isCalibrated = false
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
    
    /// 폴링 완전 중지 (외부 호출용 — 재시도 없음)
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        _retryTask?.cancel()
        _retryTask = nil
        _latency = nil
        _isReady = false
        ewmaLatency = nil
        logger.info("PDTLatencyProvider stopped")
    }
    
    /// [Fix 20 Phase3] 내부 중지 + 자동 재시도 스케줄링
    /// 연속 실패로 폴링 중지 시 호출 — 60초 후 5회 프로브 시도
    private func stopAndScheduleRetry() {
        pollTask?.cancel()
        pollTask = nil
        _latency = nil
        _isReady = false
        ewmaLatency = nil
        
        let attempts = _retryAttempts
        let maxAttempts = _maxRetryAttempts
        guard attempts < maxAttempts else {
            logger.warning("PDTLatencyProvider: 최대 재시도 횟수(\(maxAttempts))  도달 — 영구 중지")
            return
        }
        
        let interval = _retryInterval
        logger.info("PDTLatencyProvider: \(interval)초 후 PDT 프로브 재시도 예정 (시도 \(attempts + 1)/\(maxAttempts))")
        
        _retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch { return }
            await self?.attemptRetryProbes()
        }
    }
    
    /// [Fix 20 Phase3] 재시도 프로브 — 5회 폴링 시도, 1회라도 성공 시 정상 폴링 복귀
    private func attemptRetryProbes() {
        _retryAttempts += 1
        _retryTask = nil
        _consecutiveOutOfRange = 0
        
        let attempts = _retryAttempts
        let maxAttempts = _maxRetryAttempts
        logger.info("PDTLatencyProvider: 재시도 프로브 시작 (시도 \(attempts)/\(maxAttempts))")
        
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.runRetryProbeLoop()
        }
    }
    
    /// [Fix 20 Phase3] 재시도 프로브 루프 실행 (actor-isolated)
    private func runRetryProbeLoop() async {
        var successCount = 0
        
        for probeIndex in 0..<_retryProbeCount {
            guard !Task.isCancelled else { return }
            await poll()
            
            if _isReady {
                successCount += 1
            }
            
            if probeIndex < _retryProbeCount - 1 {
                do {
                    try await Task.sleep(for: .seconds(pollInterval))
                } catch { return }
            }
        }
        
        guard !Task.isCancelled else { return }
        
        if successCount > 0 {
            // 프로브 성공 → 정상 폴링 복귀
            _retryAttempts = 0
            let probeCount = _retryProbeCount
            logger.info("PDTLatencyProvider: 프로브 성공 (\(successCount)/\(probeCount)) — PDT 모드 복귀")
            // 기존 task를 정상 폴링으로 이어감
            while !Task.isCancelled {
                await poll()
                do {
                    try await Task.sleep(for: .seconds(pollInterval))
                } catch { break }
            }
        } else {
            // 프로브 전패 → 다시 재시도 스케줄
            logger.warning("PDTLatencyProvider: 프로브 실패 — 다음 재시도 대기")
            pollTask = nil
            stopAndScheduleRetry()
        }
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
            CommonHeaders.safariUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        // 캐시 무효화 - 매번 최신 플레이리스트를 가져와야 함
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (data, _) = try await hlsSession.data(for: request)
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
            
            // [Fix 21] 비현실적인 값 필터링 — clock skew 최대 ±5초 허용
            guard rawLatency < 60 else {
                self._consecutiveOutOfRange += 1
                if self._consecutiveOutOfRange >= self._maxConsecutiveOutOfRange {
                    self.logger.warning("PDT latency \(self._consecutiveOutOfRange)회 연속 범위 초과 — 재시도 스케줄링")
                    self.stopAndScheduleRetry()
                    return
                }
                if self._consecutiveOutOfRange <= 3 {
                    self.logger.warning("PDT latency out of range: \(rawLatency, format: .fixed(precision: 2))s – skipped (\(self._consecutiveOutOfRange)/\(self._maxConsecutiveOutOfRange))")
                }
                return
            }
            guard rawLatency >= -5.0 else {
                self._consecutiveOutOfRange += 1
                if self._consecutiveOutOfRange >= self._maxConsecutiveOutOfRange {
                    self.logger.warning("PDT latency \(self._consecutiveOutOfRange)회 연속 범위 초과 — 재시도 스케줄링")
                    self.stopAndScheduleRetry()
                    return
                }
                return
            }
            
            // 유효 값 → 연속 실패 카운터 리셋
            self._consecutiveOutOfRange = 0
            
            // [Fix 21] Clock Offset 캘리브레이션
            // 초기 N개 샘플 수집 후 중앙값으로 시계 편차 추정
            if !_isCalibrated {
                _calibrationSamples.append(rawLatency)
                if _calibrationSamples.count >= _calibrationCount {
                    let sorted = _calibrationSamples.sorted()
                    let median = sorted[sorted.count / 2]
                    if median < -0.3 {
                        // Clock skew 감지: CDN 시각이 클라이언트보다 앞서 있음
                        // median을 +0.5s로 매핑하여 양의 기준선 확보
                        _clockOffset = -median + 0.5
                        logger.info("PDT clock offset calibrated: +\(self._clockOffset, format: .fixed(precision: 2))s (median raw: \(median, format: .fixed(precision: 2))s)")
                    }
                    _isCalibrated = true
                    _calibrationSamples.removeAll()
                }
            }
            
            // [Fix 22C] 보정된 레이턴시 = raw + clockOffset
            // 기존 max(0, ...) 클램프는 세그먼트 경계 음수값을 0으로 만들어
            // EWMA에 비대칭 왜곡 발생 → 톱니파 불안정 악화
            // 개선: 소폭 음수(-0.5s 이내)는 EWMA에 그대로 투입하여 대칭 스무딩
            let correctedLatency = rawLatency + _clockOffset
            let clampedLatency = max(-0.5, correctedLatency)  // 극단값만 제한
            
            // EWMA로 노이즈 제거
            if let prev = ewmaLatency {
                ewmaLatency = ewmaAlpha * clampedLatency + (1 - ewmaAlpha) * prev
            } else {
                ewmaLatency = clampedLatency
            }
            
            // 외부 반환값은 0 이상으로 보장 (PID 컨트롤러 호환)
            _latency = max(0, ewmaLatency ?? 0)
            _isReady = true
            
            if _clockOffset > 0.1 {
                logger.debug("PDT latency: raw=\(rawLatency, format: .fixed(precision: 2))s offset=+\(self._clockOffset, format: .fixed(precision: 2))s corrected=\(correctedLatency, format: .fixed(precision: 2))s ewma=\(self._latency ?? 0, format: .fixed(precision: 2))s")
            } else {
                logger.debug("PDT latency: raw=\(rawLatency, format: .fixed(precision: 2))s ewma=\(self._latency ?? 0, format: .fixed(precision: 2))s")
            }
            
        } catch {
            logger.debug("PDT poll failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
