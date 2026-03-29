// MARK: - AVPlayerEngine+LiveStream.swift
// CViewPlayer - 라이브 스트림 지연 제어: 캐치업 설정, 스톨 감지, 네트워크 모니터링

import Foundation
import AVFoundation
import Network
import CViewCore

// MARK: - Live Catchup Configuration

/// 라이브 스트림 저지연 캐치업 설정
public struct AVLiveCatchupConfig: Sendable {
    /// 목표 지연 시간 (초)
    public var targetLatency: Double
    /// 최대 허용 지연 시간 (초) — 초과 시 캐치업 시작
    public var maxLatency: Double
    /// 최대 캐치업 재생 속도
    public var maxCatchupRate: Float
    /// 버퍼 전진 지속 시간 (초)
    public var preferredForwardBuffer: Double

    /// [외부 리서치: Apple LL-HLS] 최저 지연 — 안정적 네트워크(유선/고속WiFi) 전용
    /// 부분 세그먼트(~200ms) 지원 LL-HLS 서버에서 최적 성능
    public static let ultraLow = AVLiveCatchupConfig(
        targetLatency: 2.0, maxLatency: 5.0,
        maxCatchupRate: 1.5, preferredForwardBuffer: 2.0
    )
    public static let lowLatency = AVLiveCatchupConfig(
        targetLatency: 3.0, maxLatency: 8.0,
        maxCatchupRate: 1.3, preferredForwardBuffer: 3.0
    )
    public static let balanced = AVLiveCatchupConfig(
        targetLatency: 5.0, maxLatency: 12.0,
        maxCatchupRate: 1.2, preferredForwardBuffer: 7.0
    )
    /// 웹(hls.js) 동기화 — 앱↔웹 동일 재생 위치 목표
    /// hls.js 기본 3×TARGETDURATION(2s)=6.0s에 맞춰 5.0s 타겟, 최소 속도 변화로 수렴
    public static let webSync = AVLiveCatchupConfig(
        targetLatency: 5.0, maxLatency: 12.0,
        maxCatchupRate: 1.10, preferredForwardBuffer: 5.0
    )
    public static let stable = AVLiveCatchupConfig(
        targetLatency: 8.0, maxLatency: 20.0,
        maxCatchupRate: 1.1, preferredForwardBuffer: 12.0
    )

    public init(targetLatency: Double, maxLatency: Double,
                maxCatchupRate: Float, preferredForwardBuffer: Double) {
        self.targetLatency = targetLatency
        self.maxLatency = maxLatency
        self.maxCatchupRate = maxCatchupRate
        self.preferredForwardBuffer = preferredForwardBuffer
    }
}

// MARK: - Stall Watchdog & Live Catchup

extension AVPlayerEngine {

    /// 스마트 스톨 워치독 — currentTime 기반 실질 정체 감지:
    /// 1) currentTime 정체: 21초(7회 연속) 동안 재생 위치 변화 없음 → 재연결
    /// 2) 버퍼 고갈: 24초(8회 연속) isPlaybackLikelyToKeepUp=false → 재연결
    /// 3) 연속 재연결 실패 보호: 5분 내 3회 이상 재연결 시 에러 상태 전환
    /// 
    /// 이전 문제: lastProgressTime + timeControlStatus 기반 감지가 멀티라이브에서
    /// false positive를 일으킴 (timeControlStatus가 잠시 .waiting 상태일 때
    /// 실제로는 재생 중이지만 재연결 트리거). currentTime 직접 비교로 해결.
    internal func startStallWatchdog() {
        let kCheckInterval: UInt64 = 4_000_000_000 // 4초 (AVPlayer 기본엔진 전환: CPU 절감)

        stallWatchdogTask?.cancel()
        lastProgressTime = Date()
        recentReconnectTimestamps.removeAll()

        stallWatchdogTask = Task { [weak self] in
            // readyToPlay 이후 시작되므로 짧은 안정화 대기만 필요.
            // 이전 8초 대기는 play() 직후 호출 시 false positive 방지용이었으나,
            // 이제 readyToPlay KVO에서 호출되므로 2초면 충분.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            var bufferStallCount = 0
            var timeStallCount = 0
            var previousCurrentTime: Double = -1
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: kCheckInterval)
                guard let self, !Task.isCancelled else { return }

                // 백그라운드 세션은 스톨 감시 건너뜀 (비활성 세션 복구 지연 허용)
                guard !self.isBackgroundMode else {
                    bufferStallCount = 0
                    timeStallCount = 0
                    previousCurrentTime = -1
                    continue
                }

                let phase = self._avState.withLock { $0.state }

                // idle/ended/error 상태에서는 감시 일시 중지 (루프는 유지)
                if phase == .idle || phase == .ended {
                    bufferStallCount = 0
                    timeStallCount = 0
                    previousCurrentTime = -1
                    continue
                }
                if case .error = phase {
                    bufferStallCount = 0
                    timeStallCount = 0
                    previousCurrentTime = -1
                    continue
                }

                guard phase == .playing || phase == .buffering(progress: 0) else {
                    bufferStallCount = 0
                    timeStallCount = 0
                    previousCurrentTime = -1
                    continue
                }

                // ── currentTime 기반 실질 정체 감지 ──
                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                if previousCurrentTime >= 0 && currentTime.isFinite {
                    if abs(currentTime - previousCurrentTime) < 0.1 {
                        timeStallCount += 1
                    } else {
                        timeStallCount = 0
                    }
                }
                if currentTime.isFinite {
                    previousCurrentTime = currentTime
                }

                // 버퍼 부족 카운트
                let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? true
                if !keepUp { bufferStallCount += 1 } else { bufferStallCount = 0 }

                // 재연결 조건 (false positive 방지를 위해 더 보수적):
                // 1) currentTime 정체 7회 연속 (21초간 재생 위치 변화 없음)
                // 2) 버퍼 고갈 연속 8회 (24초간 isPlaybackLikelyToKeepUp=false)
                let shouldReconnect = timeStallCount >= 7 || bufferStallCount >= 8

                if shouldReconnect {
                    self.logger.warning(
                        "AVPlayerEngine: stall watchdog — timeStalls=\(timeStallCount) bufferStalls=\(bufferStallCount) currentTime=\(String(format: "%.1f", currentTime))"
                    )

                    // 연속 재연결 실패 보호: 5분 내 maxReconnectsInWindow회 초과 시 에러 전환
                    let now = Date()
                    self.recentReconnectTimestamps.append(now)
                    self.recentReconnectTimestamps.removeAll {
                        now.timeIntervalSince($0) > self.reconnectWindowSeconds
                    }

                    if self.recentReconnectTimestamps.count > self.maxReconnectsInWindow {
                        self.logger.error(
                            "AVPlayerEngine: \(self.maxReconnectsInWindow)+ reconnects in \(Int(self.reconnectWindowSeconds))s — giving up"
                        )
                        self.handleError(.connectionLost)
                        return // 워치독 종료 (복구 불가 상태)
                    }

                    // 재연결 요청 후 카운터 리셋, 루프 계속
                    bufferStallCount = 0
                    timeStallCount = 0
                    previousCurrentTime = -1
                    self.lastProgressTime = Date()
                    self.handleError(.connectionLost)
                    // 재연결 완료 대기 (15초) — play()가 다시 호출될 때까지 대기
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    continue
                }
            }
        }
    }

    // MARK: - Live Catchup Loop

    /// 2초마다 지연 측정 → 스무딩된 속도 조정
    /// - 급격한 속도 변화를 방지하기 위해 최근 4개 측정값의 EMA 사용
    /// - latency > maxLatency: 라이브 엣지로 즉시 점프 후 offset 재설정
    /// - 백그라운드 세션은 건너뜀 (비활성 세션에서 속도 조정 불필요)
    internal func startLiveCatchupLoop() {
        let kCheckInterval: UInt64 = 3_000_000_000 // 3초 (AVPlayer 기본엔진 전환: CPU 절감)

        liveCatchupTask?.cancel()
        liveCatchupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: kCheckInterval)
                guard let self, !Task.isCancelled else { return }
                guard !self.isBackgroundMode else { continue }
                await MainActor.run { self.adjustPlaybackRateForLatency() }
            }
        }
    }

    @MainActor
    internal func adjustPlaybackRateForLatency() {
        guard let item = player.currentItem,
              let seekRange = item.seekableTimeRanges.last?.timeRangeValue,
              player.timeControlStatus == .playing else { return }

        let liveEdge  = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
        let currentPos = CMTimeGetSeconds(player.currentTime())
        guard liveEdge.isFinite, currentPos.isFinite, liveEdge > 0 else { return }

        let latency = max(0, liveEdge - currentPos)
        measuredLatency = latency
        onLatencyChange?(latency)

        let cfg = catchupConfig

        // ── 지연 과다: 라이브 엣지 바로 앞으로 점프 ──────────────────────
        if latency > cfg.maxLatency {
            let target = max(0, liveEdge - cfg.targetLatency)
            logger.info("AVPlayerEngine: latency \(String(format: "%.1f", latency))s > max → snap to live edge")
            seek(to: target)
            rateHistory.removeAll()
            return
        }

        // ── 지연 정상 범위: 스무딩된 속도 계산 ───────────────────────────
        let targetRate: Float
        if latency > cfg.targetLatency {
            // 0~1로 정규화한 ratio → 로그 곡선으로 완만하게 가속
            let ratio = min((latency - cfg.targetLatency) / (cfg.maxLatency - cfg.targetLatency), 1.0)
            let curved = Float(1.0 - cos(ratio * .pi / 2))    // 코사인 이징
            targetRate = 1.0 + curved * (cfg.maxCatchupRate - 1.0)
        } else if latency < cfg.targetLatency * 0.6 {
            // 지연이 목표보다 충분히 낮으면 정상 속도로 복귀 + 히스토리 리셋
            // rateHistory를 유지하면 다음 캐치업 사이클에서 높은 과거 값이 EMA에 반영되어
            // 불필요하게 빠른 재생 속도로 시작하는 오버슈트 발생 → 명시적으로 리셋
            if player.rate != 1.0 || !rateHistory.isEmpty {
                player.rate = 1.0
                rateHistory.removeAll()
            }
            return
        } else {
            return // 목표 범위 내 → 아무것도 하지 않음
        }

        // EMA 스무딩 (α=0.4): 빠른 반응이면서 급격한 변화는 완충
        let alpha: Float = 0.4
        let last = rateHistory.last ?? player.rate
        let smoothed = alpha * targetRate + (1 - alpha) * last

        rateHistory.append(smoothed)
        if rateHistory.count > 4 { rateHistory.removeFirst() }

        // 0.03 미만 변화는 무시해서 불필요한 API 호출 제거
        if abs(player.rate - smoothed) > 0.03 {
            player.rate = smoothed
        }
    }

    // MARK: - Network Monitor

    internal func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previousType = self.currentNetworkType
            
            if path.usesInterfaceType(.wiredEthernet) {
                self.currentNetworkType = .wiredEthernet
            } else if path.usesInterfaceType(.wifi) {
                self.currentNetworkType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.currentNetworkType = .cellular
            } else {
                self.currentNetworkType = .other
            }
            
            // 네트워크 인터페이스 변경 시 자동 대응
            if previousType != self.currentNetworkType {
                self.logger.info("AVPlayerEngine: 네트워크 전환 \(String(describing: previousType)) → \(String(describing: self.currentNetworkType))")
                
                // 연결 상실 시 즉시 재연결 요청
                if path.status != .satisfied {
                    self.logger.warning("AVPlayerEngine: 네트워크 연결 해제 감지 — 재연결 대기")
                    return
                }
                
                // 라이브 스트림에서만 캐치업 설정 재조정
                let isLive = self.isLiveStream
                if isLive {
                    self.adjustCatchupConfigForNetwork()
                    
                    // 현재 재생 중인 아이템의 버퍼 설정 즉시 업데이트
                    Task { @MainActor [weak self] in
                        guard let self, let item = self.player.currentItem else { return }
                        item.preferredForwardBufferDuration = self.catchupConfig.preferredForwardBuffer
                        self.logger.info("AVPlayerEngine: 버퍼 설정 업데이트 — target=\(self.catchupConfig.targetLatency)s max=\(self.catchupConfig.maxLatency)s buffer=\(self.catchupConfig.preferredForwardBuffer)s")
                    }
                }
                
                // 스톨 워치독 타임스탬프 갱신 — 전환 순간의 일시 정지를 스톨로 오인 방지
                self.lastProgressTime = Date()
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    /// 네트워크 인터페이스에 따라 목표 지연 시간 조정
    internal func adjustCatchupConfigForNetwork() {
        switch currentNetworkType {
        case .wiredEthernet:
            // [외부 리서치: LL-HLS] 유선: 최저 지연 (안정적 네트워크)
            // 부분 세그먼트 활용으로 2초 미만 타겟 가능
            catchupConfig.targetLatency = 1.5
            catchupConfig.maxLatency = 4.0
            catchupConfig.maxCatchupRate = 1.5
            catchupConfig.preferredForwardBuffer = 2.0
        case .wifi:
            // WiFi: 저지연 기본값
            catchupConfig.targetLatency = 2.5
            catchupConfig.maxLatency = 6.0
            catchupConfig.maxCatchupRate = 1.3
            catchupConfig.preferredForwardBuffer = 3.0
        case .cellular:
            // 모바일: 안정 우선
            catchupConfig.targetLatency = 5.0
            catchupConfig.maxLatency = 12.0
            catchupConfig.maxCatchupRate = 1.2
            catchupConfig.preferredForwardBuffer = 8.0
        default:
            catchupConfig.targetLatency = 3.0
            catchupConfig.maxLatency = 8.0
            catchupConfig.maxCatchupRate = 1.3
            catchupConfig.preferredForwardBuffer = 4.0
        }
    }
}
