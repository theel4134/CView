// MARK: - AVPlayerEngine+LiveStream.swift
// CViewPlayer - 라이브 캐치업 + 통합 스톨 워치독
//
// 설계 원칙
//   - 캐치업: 2초 측정 → EMA 스무딩 → 0.03 이하 변화는 무시 (API 호출 최소화)
//   - 스톨 감지: currentTime 정체 + 버퍼 고갈 두 신호를 OR 판정하는 단일 워치독
//   - 재연결 폭주 보호: 5분 내 3회 초과 시 영구 에러 전환
//   - 배경 세션(isBackgroundMode)은 두 루프 모두 건너뜀 → 유휴 CPU 절감

import Foundation
import AVFoundation
import CViewCore

// MARK: - Live Catchup Configuration

/// 라이브 스트림 저지연 캐치업 설정.
/// `AVPlayerEngine.catchupConfig`에 프리셋 중 하나를 대입하거나 커스텀 값 구성.
public struct AVLiveCatchupConfig: Sendable, Equatable {

    /// 목표 지연 시간(초). 이 값 근처로 수렴 시 재생 속도 1.0x로 복귀.
    public var targetLatency: Double
    /// 최대 허용 지연(초). 초과 시 라이브 엣지로 seek.
    public var maxLatency: Double
    /// 캐치업 중 허용되는 최대 배속.
    public var maxCatchupRate: Float
    /// AVPlayerItem.preferredForwardBufferDuration (초).
    public var preferredForwardBuffer: Double

    public init(
        targetLatency: Double,
        maxLatency: Double,
        maxCatchupRate: Float,
        preferredForwardBuffer: Double
    ) {
        self.targetLatency = targetLatency
        self.maxLatency = maxLatency
        self.maxCatchupRate = maxCatchupRate
        self.preferredForwardBuffer = preferredForwardBuffer
    }

    // MARK: Presets

    /// [외부 리서치: Apple LL-HLS] 최저 지연 — 유선/고속WiFi 전용
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
    /// hls.js 동기화 — 3×TARGETDURATION(2s)=6s 버퍼에 맞춤
    public static let webSync = AVLiveCatchupConfig(
        targetLatency: 5.0, maxLatency: 12.0,
        maxCatchupRate: 1.10, preferredForwardBuffer: 5.0
    )
    public static let stable = AVLiveCatchupConfig(
        targetLatency: 8.0, maxLatency: 20.0,
        maxCatchupRate: 1.1, preferredForwardBuffer: 12.0
    )
}

// MARK: - Network-Aware Catchup Adjustment

extension AVPlayerEngine {

    /// 네트워크 인터페이스에 따라 catchupConfig 조정.
    /// 호출자: play() 진입 시 + NetworkMonitor 구독 콜백.
    ///
    /// [P2-2 / 2026-04-25] `catchupConfigLocked == true` 인 경우 외부에서
    /// catchupConfig 를 점유 중(예: PDT 정밀 동기화) 으로 간주하고 즉시 반환한다.
    /// 이로써 webSync 등 명시 프리셋이 네트워크 전환에 의해 덮어써지는 회귀를 방지.
    internal func adjustCatchupConfigForNetwork() {
        let (type, locked) = stateLock.withLock { ($0.networkType, $0.catchupConfigLocked) }
        if locked {
            logger.debug("AVPlayerEngine: adjustCatchupConfigForNetwork skipped (catchupConfigLocked=true)")
            return
        }
        let cfg: AVLiveCatchupConfig = {
            switch type {
            case .wiredEthernet:
                // 유선: 저지연 유지하되 1080p60 VBR 피크(8-12Mbps) 지터 흡수용 6s 버퍼로 상향
                // (기존 4s는 장시간 재생 시 간헐적 스톨 유발)
                return AVLiveCatchupConfig(
                    targetLatency: 3.0, maxLatency: 8.0,
                    maxCatchupRate: 1.4, preferredForwardBuffer: 6.0
                )
            case .wifi:
                // WiFi: RSSI 변동/혼선 흡수용 10s 버퍼 — VLC 수준의 안정성 확보
                return AVLiveCatchupConfig(
                    targetLatency: 5.0, maxLatency: 12.0,
                    maxCatchupRate: 1.2, preferredForwardBuffer: 10.0
                )
            case .cellular:
                return AVLiveCatchupConfig(
                    targetLatency: 6.0, maxLatency: 15.0,
                    maxCatchupRate: 1.15, preferredForwardBuffer: 14.0
                )
            case .offline, .other:
                // 네트워크 타입 불명 — WiFi 수준의 안전 프리셋 적용
                return AVLiveCatchupConfig(
                    targetLatency: 5.0, maxLatency: 12.0,
                    maxCatchupRate: 1.2, preferredForwardBuffer: 10.0
                )
            }
        }()
        stateLock.withLock { $0.catchupConfig = cfg }
    }
}

// MARK: - Stall Watchdog (통합 단일 경로)

extension AVPlayerEngine {

    /// 통합 스톨 워치독 — 4초 주기로 다음 두 신호를 OR 판정:
    /// 1) currentTime 정체 12회 연속(≈48s): 재생 위치 미변화 (VLC 수준의 관대함)
    /// 2) isPlaybackLikelyToKeepUp=false 14회 연속(≈56s): 버퍼 회복 불능
    /// → 재연결 요청. 5분 내 3회 초과 시 .connectionLost 영구 에러 전환.
    ///
    /// `observeItem` → readyToPlay 시점에 호출. 중복 호출은 기존 Task를 자동 취소.
    /// 
    /// [안정성 튜닝] 기존 7/8 역치(21s/24s)는 WiFi/셀룰러 지터에서 false positive 다수 발생.
    /// VLC는 내부 http-reconnect로 60s+ 복구 대기 — 이에 맞춰 역치 상향.
    internal func startStallWatchdog() {
        let checkInterval: UInt64 = 4_000_000_000 // 4s

        let task = Task { [weak self] in
            // 초기 안정화 대기 — readyToPlay 직후 네트워크 RTT + HLS 초기 세그먼트 로드 흡수용 5s
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            var timeStallCount = 0
            var bufferStallCount = 0
            var previousCurrentTime: Double = -1

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: checkInterval)
                guard let self, !Task.isCancelled else { return }

                // 배경 세션은 스톨 감시 건너뜀 (비활성 세션 복구 지연 허용)
                if self.isBackgroundMode {
                    timeStallCount = 0
                    bufferStallCount = 0
                    previousCurrentTime = -1
                    continue
                }

                let phase = self.currentPhase
                // 재생/버퍼링 이외 단계에서는 카운터 리셋 후 유지
                if !phaseIsWatchable(phase) {
                    timeStallCount = 0
                    bufferStallCount = 0
                    previousCurrentTime = -1
                    continue
                }

                // ── 1) currentTime 정체 감지 ──
                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                if previousCurrentTime >= 0 && currentTime.isFinite {
                    if abs(currentTime - previousCurrentTime) < 0.1 {
                        timeStallCount += 1
                    } else {
                        timeStallCount = 0
                    }
                }
                if currentTime.isFinite { previousCurrentTime = currentTime }

                // ── 2) 버퍼 고갈 감지 ──
                let keepUp = self.player.currentItem?.isPlaybackLikelyToKeepUp ?? true
                if !keepUp { bufferStallCount += 1 } else { bufferStallCount = 0 }

                // ── 재연결 조건 OR 판정 (완화된 역치: 48s/56s) ──
                if timeStallCount >= 12 || bufferStallCount >= 14 {
                    self.logger.warning(
                        "AVPlayerEngine: stall detected — timeStalls=\(timeStallCount) bufferStalls=\(bufferStallCount) currentTime=\(String(format: "%.1f", currentTime))"
                    )
                    timeStallCount = 0
                    bufferStallCount = 0
                    previousCurrentTime = -1

                    if self.registerReconnectAndShouldGiveUp() {
                        self.logger.error(
                            "AVPlayerEngine: \(self.maxReconnectsInWindow)+ reconnects within \(Int(self.reconnectWindowSeconds))s — giving up"
                        )
                        self.handleError(.connectionLost)
                        return
                    }

                    self.stateLock.withLock { $0.lastProgressTime = Date() }
                    self.handleError(.connectionLost)
                    // 재연결 완료 대기 — play()가 재호출되면 stop→새 play 흐름으로 이 Task는 취소됨
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
        }
        tasks.set(AVPlayerTaskBag.kStallWatchdog, task)
    }

    /// 최근 재연결 이력에 현재 시각 기록 후 포기해야 하는지 판단.
    private func registerReconnectAndShouldGiveUp() -> Bool {
        let now = Date()
        return stateLock.withLock { state in
            state.recentReconnectTimestamps.append(now)
            state.recentReconnectTimestamps.removeAll { now.timeIntervalSince($0) > reconnectWindowSeconds }
            return state.recentReconnectTimestamps.count > maxReconnectsInWindow
        }
    }

    // MARK: - HQ 복귀 워치독

    /// AVFoundation 내부 ABR이 레이턴시 캐치업(`rate > 1.0`) 중 버퍼 부족으로
    /// 720p 이하 variant 에 "고정"되는 현상을 복구하기 위한 워치독.
    ///
    /// 동작 원리:
    /// - `isQualityLocked=true` 상태에서 `preferredPeakBitRate`(ceiling)는 재업그레이드 요인이 되지 못한다.
    ///   AVPlayer 내부 ABR은 observedBitrate/buffer 조건이 좋아져도 ceiling 밑에서 머무는 경우가 많다.
    /// - 주기적으로 AccessLog 의 `indicatedBitrate`가 ceiling 의 70% 미만으로 오래 지속되고,
    ///   버퍼가 정상이며 재생 속도가 1.0 근처로 돌아왔다면(레이턴시 정상화) ceiling 을 잠시 해제했다가
    ///   다시 적용하여 내부 ABR 재평가를 유도한다. (업계 통용되는 nudge 패턴)
    ///
    /// [Safety]
    /// - 실제로 비트레이트 상향이 관찰되지 않으면 60초 쿨다운 후 재시도.
    /// - `isBackgroundMode=true` 세션은 건너뜀.
    /// - 화질 잠금이 꺼진 경우에도 아무것도 하지 않는다.
    /// - **비선택 멀티라이브 세션도 회복 시도** (이전: 절약 우선으로 건너뜀):
    ///   사용자가 다시 선택했을 때 720p 이하에 고정된 채 노출되는 회귀 차단.
    ///   단, 더 보수적인 조건(샘플 5회·쿨다운 120s·ceiling 60% 임계)을 적용해
    ///   백그라운드 nudge 가 셀룰러/저속 회선에서 burst 를 만들지 않도록 한다.
    internal func startHQRecoveryWatchdog() {
        let task = Task { [weak self] in
            // 초기 안정화 대기 (readyToPlay 직후에는 ABR 정보가 부정확)
            try? await Task.sleep(nanoseconds: 12_000_000_000)  // 12s

            var lowBitrateSamples: Int = 0
            var lastNudgeAt: Date = .distantPast

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)  // 6s 주기
                guard let self, !Task.isCancelled else { return }

                // 가드: 잠금 해제 / 비활성 세션 / 비라이브 → 건너뜀
                let snap = self.stateLock.withLock { s in
                    (
                        locked: s.isQualityLocked,
                        bgMode: s.isBackgroundMode,
                        isLive: s.isLiveStream,
                        isSelMulti: s.isSelectedMultiLiveSession,
                        warmup: s.isWarmingUpForHQ,
                        peakCeiling: s.lockedPeakBitRate,
                        indicated: s.indicatedBitrate
                    )
                }
                if !snap.locked || !snap.isLive { continue }
                if snap.bgMode { continue }
                if snap.warmup { continue }                // warm-up 중에는 건드리지 않음
                guard snap.peakCeiling > 0 else { continue }

                // [Quality 2026-04-24] 비선택 세션은 더 보수적인 조건 적용
                //   · 임계값 0.70 → 0.60 (더 심한 강등에서만 nudge)
                //   · 쿨다운 60s → 120s
                //   · 누적 샘플 3 → 5
                let isSelectedSession = snap.isSelMulti
                let thresholdRatio: Double = isSelectedSession ? 0.70 : 0.60
                let cooldownSec: Double = isSelectedSession ? 60 : 120
                let requiredSamples: Int = isSelectedSession ? 3 : 5

                // 현재 재생/버퍼/속도 상태 확인 (MainActor)
                let status = await MainActor.run { () -> (keepUp: Bool, rate: Float, hasItem: Bool) in
                    guard let item = self.player.currentItem else { return (false, 1.0, false) }
                    return (item.isPlaybackLikelyToKeepUp, self.player.rate, true)
                }
                guard status.hasItem else { continue }

                // 네트워크/버퍼 전제: 재생 쾌적 + 속도 정상(≤1.05) → 레이턴시 캐치업 종료 상태
                let bufferOk = status.keepUp
                let rateNormal = status.rate > 0 && status.rate <= 1.05

                // AccessLog 기반 observedBitrate (indicatedBitrate) 정확도 확보
                let indicated = snap.indicated
                let ceiling = snap.peakCeiling
                let threshold = ceiling * thresholdRatio  // 비선택은 0.60, 선택은 0.70

                // 조건 미충족 시 카운터 리셋
                guard bufferOk, rateNormal, indicated > 0, indicated < threshold else {
                    lowBitrateSamples = 0
                    continue
                }

                // 쿨다운 (nudge 후 일정 시간 이내 재시도 금지)
                if Date().timeIntervalSince(lastNudgeAt) < cooldownSec { continue }

                lowBitrateSamples += 1
                // 누적 샘플 충족 시 nudge (선택=3 ≈18s, 비선택=5 ≈30s)
                guard lowBitrateSamples >= requiredSamples else { continue }
                lowBitrateSamples = 0

                await MainActor.run {
                    guard let item = self.player.currentItem else { return }
                    self.logger.info(
                        "AVPlayerEngine: HQ recovery nudge — indicated=\(Int(indicated/1000))kbps ceiling=\(Int(ceiling/1000))kbps selected=\(isSelectedSession)"
                    )
                    // ceiling 잠시 해제 → AVFoundation 내부 ABR 재평가 유도
                    item.preferredPeakBitRate = 0
                    item.preferredMaximumResolution = .zero
                }
                // 250ms 후 ceiling 복구 (충분히 ABR 재탐색 트리거하는 최소 시간)
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let item = self.player.currentItem else { return }
                    let (locked2, bitrate2, res2) = self.stateLock.withLock { s in
                        (s.isQualityLocked, s.lockedPeakBitRate, s.lockedMaximumResolution)
                    }
                    // 도중 잠금 해제된 경우 ceiling 을 그대로 둔다(시스템 자동 ABR 유지).
                    if locked2 {
                        item.preferredPeakBitRate = bitrate2
                        item.preferredMaximumResolution = res2
                    }
                }
                lastNudgeAt = Date()
            }
        }
        tasks.set(AVPlayerTaskBag.kHQRecovery, task)
    }

    /// [Quality 2026-04-18] 외부에서 즉시 화질 ceiling nudge 를 요청하는 진입점.
    /// 멀티라이브 세션이 비선택 → 선택 으로 전환되었을 때 워치독의 60s 쿨다운/3샘플
    /// 누적을 기다리지 않고 즉시 ABR 재평가를 트리거한다.
    /// (`isQualityLocked=true` 가 아니면 no-op)
    public func nudgeQualityCeiling(reason: String) {
        let (locked, isLive, bitrate, res) = stateLock.withLock { s in
            (s.isQualityLocked, s.isLiveStream, s.lockedPeakBitRate, s.lockedMaximumResolution)
        }
        guard locked, isLive, bitrate > 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, let item = self.player.currentItem else { return }
            self.logger.info("AVPlayerEngine: HQ nudge (immediate) — reason=\(reason)")
            // ceiling 잠시 해제 → AVFoundation 내부 ABR 재평가 유도
            item.preferredPeakBitRate = 0
            item.preferredMaximumResolution = .zero
            try? await Task.sleep(nanoseconds: 250_000_000)
            // 도중 잠금 해제된 경우 ceiling 을 그대로 둔다
            let (locked2, bitrate2, res2) = self.stateLock.withLock { s in
                (s.isQualityLocked, s.lockedPeakBitRate, s.lockedMaximumResolution)
            }
            if locked2 {
                item.preferredPeakBitRate = bitrate2
                item.preferredMaximumResolution = res2
            } else {
                _ = (bitrate, res) // 잠금 해제 시 값 사용 안 함
            }
        }
    }
}

/// 스톨 워치독이 감시해야 하는 단계인지 판정.
/// `.playing`과 `.buffering`만 대상(그 외는 스톨 감지 불가/불필요).
private func phaseIsWatchable(_ phase: PlayerState.Phase) -> Bool {
    switch phase {
    case .playing, .buffering:
        return true
    default:
        return false
    }
}

// MARK: - Live Catchup Loop

extension AVPlayerEngine {

    /// 라이브 정체 복구용: 현재 seekable range 기준 라이브 엣지 근처로 다시 맞춘 뒤 재생을 재개.
    @MainActor
    internal func seekToLiveEdgeForRecovery(reason: String) {
        guard let item = player.currentItem,
              let seekRange = item.seekableTimeRanges.last?.timeRangeValue else {
            player.play()
            return
        }

        let liveEdge = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
        guard liveEdge.isFinite, liveEdge > 0 else {
            player.play()
            return
        }

        let cfg = catchupConfig
        let target = max(0, liveEdge - cfg.targetLatency)
        logger.info("AVPlayerEngine: recover to live edge (\(reason)) → \(String(format: "%.1f", target))s")

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 1.0, preferredTimescale: 600),
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.player.play()
        }
    }

    /// 3초 주기로 지연 측정 → EMA 스무딩된 속도 조정.
    internal func startLiveCatchupLoop() {
        let checkInterval: UInt64 = 3_000_000_000 // 3s

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: checkInterval)
                guard let self, !Task.isCancelled else { return }
                if self.isBackgroundMode { continue }
                await self.adjustPlaybackRateForLatency()
            }
        }
        tasks.set(AVPlayerTaskBag.kLiveCatchup, task)
    }

    @MainActor
    private func adjustPlaybackRateForLatency() {
        guard let item = player.currentItem,
              let seekRange = item.seekableTimeRanges.last?.timeRangeValue,
              player.timeControlStatus == .playing else { return }

        let liveEdge = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
        let currentPos = CMTimeGetSeconds(player.currentTime())
        guard liveEdge.isFinite, currentPos.isFinite, liveEdge > 0 else { return }

        let latency = max(0, liveEdge - currentPos)

        // 측정값/레이턴시 콜백 전파
        stateLock.withLock { $0.measuredLatency = latency }
        if let cb = onLatencyChange {
            Task { @MainActor in cb(latency) }
        }

        let cfg = catchupConfig

        // ── 지연 과다: 라이브 엣지 근처로 즉시 점프 ──
        if latency > cfg.maxLatency {
            let target = max(0, liveEdge - cfg.targetLatency)
            logger.info("AVPlayerEngine: latency \(String(format: "%.1f", latency))s > max → snap to live edge")
            player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 1.0, preferredTimescale: 600),
                toleranceAfter: .zero
            )
            stateLock.withLock { $0.rateHistory.removeAll(keepingCapacity: true) }
            return
        }

        // ── 목표치 범위 결정 ──
        let targetRate: Float
        if latency > cfg.targetLatency {
            // 0~1 정규화 → 코사인 이징
            let ratio = min((latency - cfg.targetLatency) / (cfg.maxLatency - cfg.targetLatency), 1.0)
            let curved = Float(1.0 - cos(ratio * .pi / 2))
            targetRate = 1.0 + curved * (cfg.maxCatchupRate - 1.0)
        } else if latency < cfg.targetLatency * 0.6 {
            // 지연이 충분히 낮으면 1.0으로 복귀 + 히스토리 리셋 (오버슈트 방지)
            let needsReset = stateLock.withLock { state -> Bool in
                let had = !state.rateHistory.isEmpty
                state.rateHistory.removeAll(keepingCapacity: true)
                return had
            }
            if player.rate != 1.0 || needsReset {
                player.rate = 1.0
            }
            return
        } else {
            return
        }

        // ── EMA 스무딩 (α=0.4) ──
        let alpha: Float = 0.4
        let smoothed: Float = stateLock.withLock { state in
            let last = state.rateHistory.last ?? player.rate
            let s = alpha * targetRate + (1 - alpha) * last
            state.rateHistory.append(s)
            if state.rateHistory.count > 4 { state.rateHistory.removeFirst() }
            return s
        }

        // 0.03 미만 변화는 무시 (불필요한 API 호출 제거)
        if abs(player.rate - smoothed) > 0.03 {
            player.rate = smoothed
        }
    }
}
