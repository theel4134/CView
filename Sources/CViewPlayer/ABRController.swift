// MARK: - ABRController.swift
// CViewPlayer - Adaptive Bitrate Controller
// 원본: ABRController.swift (HLS.js port) → 개선: Actor-based, dual EWMA
// v2: flashls AutoLevelManager/AutoBufferManager 참조 → 버퍼 인지형 ABR + 동적 임계값

import Foundation
import CViewCore

// MARK: - ABR Controller

/// Adaptive Bitrate Rate controller using dual EWMA bandwidth estimation.
/// Ported from HLS.js ABR logic with Swift 6 concurrency improvements.
///
/// v2 개선사항 (flashls AutoLevelManager 참조):
/// - 버퍼 수위(bufferLength) + 세그먼트 fetch 시간을 ABR 결정에 반영
/// - 비트레이트 간격 기반 동적 전환 임계값 (고정 1.2x/0.8x → 적응형)
/// - 긴급 강등: 버퍼 위기 시 즉시 안전 레벨로 하향
/// - 동적 최소 버퍼 관리: 대역폭 변동성에 따라 최소 버퍼 목표 자동 조정
public actor ABRController {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        public let minBandwidthBps: Int
        public let maxBandwidthBps: Int
        public let bandwidthSafetyFactor: Double
        public let switchUpThreshold: Double
        public let switchDownThreshold: Double
        public let minSwitchInterval: TimeInterval
        public let initialBandwidthEstimate: Int
        
        public static let `default` = Configuration(
            minBandwidthBps: 500_000,
            maxBandwidthBps: 50_000_000,
            bandwidthSafetyFactor: 0.9,  // [Fix 23A] 0.7→0.9: 1080p(~8Mbps) 유지 위해 BW 활용률 향상
            switchUpThreshold: 1.15,     // [Fix 23A] 1.2→1.15: 1080p 업그레이드 더 적극적
            switchDownThreshold: 0.65,   // [Fix 23A] 0.7→0.65: 다운그레이드 더 보수적 (1080p 유지)
            minSwitchInterval: 8.0,      // [Fix 19] 5→8초: 대역폭 추정 안정화
            initialBandwidthEstimate: 8_000_000  // [Fix 23A] 5→8Mbps: 1080p 기준 초기값
        )

        /// 멀티라이브 전용 ABR 프로파일
        /// - 대역폭 안전 계수 0.85 (4스트림 공유 고려)
        /// - 초기 대역폭 추정치 2.5Mbps (4분배 가정)
        /// - 전환 간격 단축 3초 (빠른 적응)
        /// - 다운그레이드 임계값 완화 (빠른 강등)
        public static let multiLive = Configuration(
            minBandwidthBps: 300_000,
            maxBandwidthBps: 20_000_000,
            bandwidthSafetyFactor: 0.9,  // [Fix 23A] 0.85→0.9: 멀티라이브에서도 1080p 활용률 향상
            switchUpThreshold: 1.2,      // [Fix 23A] 1.3→1.2: 1080p 복귀 촉진
            switchDownThreshold: 0.65,   // [Fix 23A] 0.7→0.65: 다운그레이드 보수적
            minSwitchInterval: 3.0,
            initialBandwidthEstimate: 2_500_000
        )
        
        public init(
            minBandwidthBps: Int = 500_000,
            maxBandwidthBps: Int = 50_000_000,
            bandwidthSafetyFactor: Double = 0.7,
            switchUpThreshold: Double = 1.2,
            switchDownThreshold: Double = 0.7,
            minSwitchInterval: TimeInterval = 8.0,
            initialBandwidthEstimate: Int = 5_000_000
        ) {
            self.minBandwidthBps = minBandwidthBps
            self.maxBandwidthBps = maxBandwidthBps
            self.bandwidthSafetyFactor = bandwidthSafetyFactor
            self.switchUpThreshold = switchUpThreshold
            self.switchDownThreshold = switchDownThreshold
            self.minSwitchInterval = minSwitchInterval
            self.initialBandwidthEstimate = initialBandwidthEstimate
        }
    }
    
    // MARK: - Types
    
    public enum ABRDecision: Sendable, Equatable {
        case maintain
        case switchUp(toBandwidth: Int, reason: String)
        case switchDown(toBandwidth: Int, reason: String)
    }
    
    public struct BandwidthSample: Sendable {
        public let bytesLoaded: Int
        public let duration: TimeInterval
        public let timestamp: Date
        
        public var bitsPerSecond: Double {
            guard duration > 0 else { return 0 }
            return Double(bytesLoaded * 8) / duration
        }
        
        public init(bytesLoaded: Int, duration: TimeInterval, timestamp: Date = Date()) {
            self.bytesLoaded = bytesLoaded
            self.duration = duration
            self.timestamp = timestamp
        }
    }

    /// 버퍼 인지형 ABR에 필요한 재생 컨텍스트
    public struct PlaybackContext: Sendable {
        /// 현재 버퍼 수위 (초)
        public let bufferLength: TimeInterval
        /// 마지막 세그먼트 fetch에 걸린 시간 (초)
        public let lastFetchDuration: TimeInterval
        /// 마지막 세그먼트의 재생 duration (초)
        public let lastSegmentDuration: TimeInterval

        public init(bufferLength: TimeInterval, lastFetchDuration: TimeInterval, lastSegmentDuration: TimeInterval) {
            self.bufferLength = bufferLength
            self.lastFetchDuration = lastFetchDuration
            self.lastSegmentDuration = lastSegmentDuration
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let logger = AppLogger.hls
    
    // Dual EWMA bandwidth estimators (fast + slow)
    private var fastEWMA: EWMACalculator
    private var slowEWMA: EWMACalculator
    
    // State
    private var currentLevelIndex: Int = 0
    private var availableLevels: [MasterPlaylist.Variant] = []
    private var lastSwitchTime: Date?
    private var sampleCount: Int = 0

    /// 대역폭 코디네이터가 설정하는 최대 허용 비트레이트 (bps, 0 = 제한 없음)
    /// 멀티라이브 시 각 세션에 할당된 대역폭 예산을 초과하는 레벨 선택을 방지합니다.
    private var _maxAllowedBitrate: Double = 0

    // flashls-style 동적 전환 임계값
    private var dynamicSwitchUp: [Double] = []
    private var dynamicSwitchDown: [Double] = []

    // flashls AutoBufferManager: 대역폭 히스토리 링 버퍼
    private var bandwidthHistory: [Double] = []
    private let bandwidthHistoryMaxSize = ABRDefaults.bandwidthHistoryMaxSize
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.config = configuration
        self.fastEWMA = EWMACalculator(alpha: 0.5) // Fast response
        self.slowEWMA = EWMACalculator(alpha: 0.1) // Stable estimate
    }
    
    // MARK: - Public API
    
    /// Set available quality levels from master playlist
    public func setLevels(_ variants: [MasterPlaylist.Variant]) {
        // Sort ascending by bandwidth
        availableLevels = variants.sorted { $0.bandwidth < $1.bandwidth }
        // initialBandwidthEstimate 기반 초기 레벨 선택 (실제 재생 variant와 ABR 상태 동기화)
        if !availableLevels.isEmpty {
            let safeBw = Double(config.initialBandwidthEstimate) * config.bandwidthSafetyFactor
            var best = 0
            for (i, level) in availableLevels.enumerated() {
                if Double(level.bandwidth) <= safeBw { best = i }
            }
            currentLevelIndex = best
        } else {
            currentLevelIndex = 0
        }
        // flashls AutoLevelManager: 비트레이트 간격 기반 동적 전환 임계값 계산
        computeDynamicThresholds()
        let levelCount = self.availableLevels.count
        logger.info("ABR: Set \(levelCount) levels, initial=\(self.currentLevelIndex), dynamic thresholds computed")
    }
    
    /// Record a bandwidth measurement sample
    public func recordSample(_ sample: BandwidthSample) {
        let bps = sample.bitsPerSecond
        guard bps > 0 else { return }
        
        let _ = fastEWMA.update(bps)
        let _ = slowEWMA.update(bps)
        sampleCount += 1

        // 대역폭 히스토리 관리 (flashls AutoBufferManager)
        bandwidthHistory.append(bps)
        if bandwidthHistory.count > bandwidthHistoryMaxSize {
            bandwidthHistory.removeFirst()
        }
    }
    
    /// Get the recommended quality level based on current bandwidth (기존 bandwidth-only 방식)
    public func recommendLevel() -> ABRDecision {
        return recommendLevel(context: nil)
    }

    /// 버퍼 인지형 ABR 결정 — flashls AutoLevelManager.getnextlevel() 포팅
    ///
    /// context가 nil이면 기존 bandwidth-only 방식으로 폴백.
    /// context가 제공되면 sftm(Segment Fetch Time Margin)을 계산하여
    /// 버퍼 수위 + 세그먼트 다운로드 시간을 함께 고려합니다.
    public func recommendLevel(context: PlaybackContext?) -> ABRDecision {
        guard !availableLevels.isEmpty else { return .maintain }
        
        // Minimum interval between switches
        if let lastSwitch = lastSwitchTime,
           Date().timeIntervalSince(lastSwitch) < config.minSwitchInterval {
            return .maintain
        }
        
        let estimatedBandwidth = currentBandwidthEstimate()
        var safeBandwidth = estimatedBandwidth * config.bandwidthSafetyFactor

        // 대역폭 코디네이터 제한: 할당된 예산 이하로 클램핑
        if _maxAllowedBitrate > 0 {
            safeBandwidth = min(safeBandwidth, _maxAllowedBitrate)
        }

        // 버퍼 인지형 결정: context가 있고 충분한 샘플이 있으면 sftm 알고리즘 사용
        if let ctx = context,
           sampleCount >= ABRDefaults.bufferAwareMinSamples,
           ctx.lastFetchDuration > 0,
           ctx.lastSegmentDuration > 0 {
            return bufferAwareDecision(
                context: ctx,
                estimatedBandwidth: estimatedBandwidth,
                safeBandwidth: safeBandwidth
            )
        }

        // 폴백: bandwidth-only 결정
        return bandwidthOnlyDecision(safeBandwidth: safeBandwidth, estimatedBandwidth: estimatedBandwidth)
    }

    /// 동적 최소 버퍼 목표 계산 — flashls AutoBufferManager 알고리즘
    ///
    /// 대역폭 변동성이 클수록 더 큰 버퍼 목표를 반환합니다.
    /// - Parameters:
    ///   - currentBandwidth: 현재 대역폭 (bps)
    ///   - segmentDuration: 세그먼트 duration (초) — targetDuration
    ///   - processingTime: 마지막 세그먼트 처리 시간 (초) — fetch + decode
    /// - Returns: 권장 최소 버퍼 (초)
    public func dynamicMinBuffer(
        currentBandwidth: Double,
        segmentDuration: TimeInterval,
        processingTime: TimeInterval
    ) -> TimeInterval {
        guard !bandwidthHistory.isEmpty, segmentDuration > 0 else {
            return segmentDuration // 데이터 부족 시 1세그먼트 크기
        }

        let minBW = bandwidthHistory.min() ?? currentBandwidth
        // bw_ratio: 대역폭 안정 시 ~1.0, 불안정 시 ~2.0
        let bwRatio = (minBW + currentBandwidth) > 0
            ? 2.0 * currentBandwidth / (minBW + currentBandwidth)
            : 1.0

        // flashls: minBuffer = processingTime × (targetDuration / fragDuration) × bwRatio
        // fragDuration ≈ segmentDuration (실제 PTS 기반이지만, 매니페스트 duration으로 근사)
        let minBuffer = processingTime * bwRatio

        // 합리적 범위 클램핑: 0.5초 ~ 2 × segmentDuration
        return min(max(minBuffer, 0.5), segmentDuration * 2.0)
    }

    /// 대역폭 히스토리 기반 안정성 비율 (0.0=매우 불안정, 1.0=완전 안정)
    public var bandwidthStability: Double {
        guard bandwidthHistory.count >= 2 else { return 1.0 }
        let minBW = bandwidthHistory.min() ?? 0
        let maxBW = bandwidthHistory.max() ?? 1
        guard maxBW > 0 else { return 1.0 }
        return minBW / maxBW
    }
    
    /// Current bandwidth estimate using conservative EWMA
    public func currentBandwidthEstimate() -> Double {
        guard sampleCount > 0 else {
            return Double(config.initialBandwidthEstimate)
        }
        
        // [Fix 23C] 가중 평균 EWMA: min(fast,slow)는 과소 추정 → 1080p 불필요한 강등
        // slow(안정) 70% + fast(반응) 30% 가중 평균으로 변동에 민감하되 안정적
        let fast = fastEWMA.current
        let slow = slowEWMA.current
        
        if fast == 0 && slow == 0 {
            return Double(config.initialBandwidthEstimate)
        }
        
        // 둘 다 유효하면 가중 평균, 하나만 유효하면 해당 값 사용
        if fast == 0 { return slow }
        if slow == 0 { return fast }
        return 0.7 * slow + 0.3 * fast
    }
    
    /// Force a specific quality level
    public func forceLevelIndex(_ index: Int) {
        guard index >= 0, index < availableLevels.count else { return }
        currentLevelIndex = index
        lastSwitchTime = Date()
        logger.info("ABR: Forced to level \(index)")
    }

    /// 대역폭 코디네이터에서 할당된 최대 비트레이트 설정
    /// 0이면 제한 없음 (단일 스트림 모드)
    public func setMaxAllowedBitrate(_ maxBps: Double) {
        _maxAllowedBitrate = maxBps
        // 현재 레벨이 제한을 초과하면 즉시 하향
        if maxBps > 0, currentLevelIndex < availableLevels.count {
            let currentBps = Double(availableLevels[currentLevelIndex].bandwidth)
            if currentBps > maxBps {
                if let safeLevel = availableLevels.lastIndex(where: { Double($0.bandwidth) <= maxBps }) {
                    currentLevelIndex = safeLevel
                    lastSwitchTime = Date()
                    logger.info("ABR: maxAllowedBitrate=\(Int(maxBps / 1000))kbps → forced to level \(safeLevel)")
                }
            }
        }
    }

    /// 현재 설정된 최대 허용 비트레이트 (0 = 무제한)
    public var maxAllowedBitrate: Double { _maxAllowedBitrate }
    
    /// Currently selected level
    public var selectedLevel: MasterPlaylist.Variant? {
        guard currentLevelIndex < availableLevels.count else { return nil }
        return availableLevels[currentLevelIndex]
    }
    
    /// Reset ABR state
    public func reset() {
        fastEWMA = EWMACalculator(alpha: 0.5)
        slowEWMA = EWMACalculator(alpha: 0.1)
        currentLevelIndex = 0
        lastSwitchTime = nil
        sampleCount = 0
        bandwidthHistory = []
        dynamicSwitchUp = []
        dynamicSwitchDown = []
    }

    /// [Fix 26] 화질 프로빙용 합성 대역폭 샘플 주입
    /// EWMA가 현재 (저)화질 throughput에 수렴하여 switchUp이 불가능해지는
    /// "death spiral"을 해소합니다. 목표 비트레이트의 1.3배를 주입하여
    /// ABR이 상위 레벨 선택을 허용하도록 합니다.
    public func injectSyntheticSample(targetBitrate: Double) {
        let syntheticBps = targetBitrate * 1.3  // switchUp 임계값 통과용 여유 30%
        // fast EWMA를 즉시 업데이트하여 상위 레벨 허용
        let _ = fastEWMA.update(syntheticBps)
        let _ = fastEWMA.update(syntheticBps)
        // slow EWMA에도 부분 주입 (느린 수렴 끌어올리기)
        let _ = slowEWMA.update(syntheticBps)
        // 히스토리에도 반영
        bandwidthHistory.append(syntheticBps)
        if bandwidthHistory.count > bandwidthHistoryMaxSize {
            bandwidthHistory.removeFirst()
        }
        // minSwitchInterval 리셋으로 즉시 전환 허용
        lastSwitchTime = nil
        logger.info("ABR: 합성 샘플 주입 target=\(Int(targetBitrate / 1000))kbps synthetic=\(Int(syntheticBps / 1000))kbps")
    }

    // MARK: - flashls-style 동적 전환 임계값

    /// 비트레이트 간격 기반 동적 전환 임계값 계산
    /// flashls AutoLevelManager: 인접 레벨 간 비트레이트 상대 차이로 계산
    private func computeDynamicThresholds() {
        let count = availableLevels.count
        guard count >= 2 else {
            dynamicSwitchUp = Array(repeating: config.switchUpThreshold - 1.0, count: max(count, 1))
            dynamicSwitchDown = Array(repeating: 1.0 - config.switchDownThreshold, count: max(count, 1))
            return
        }

        let bitrates = availableLevels.map { Double($0.bandwidth) }
        var switchUp = [Double](repeating: 0, count: count)
        var switchDown = [Double](repeating: 0, count: count)

        // 최소 상대 차이 (flashls에서 minGap을 결정하는 데 사용)
        var minGap = Double.infinity
        for i in 0..<(count - 1) {
            let gap = (bitrates[i + 1] - bitrates[i]) / bitrates[i]
            minGap = min(minGap, gap)
        }
        if minGap == .infinity { minGap = 0.1 }

        for i in 0..<count {
            // switchUp: 상위 레벨로의 상대 비트레이트 차이
            if i < count - 1 {
                let rawUp = (bitrates[i + 1] - bitrates[i]) / bitrates[i]
                switchUp[i] = min(ABRDefaults.maxSwitchUpRatio, 2.0 * rawUp)
            } else {
                switchUp[i] = ABRDefaults.maxSwitchUpRatio // 최고 레벨
            }

            // switchDown: 하위 레벨로의 상대 비트레이트 차이
            if i > 0 {
                let rawDown = (bitrates[i] - bitrates[i - 1]) / bitrates[i]
                switchDown[i] = max(2.0 * minGap, rawDown)
            } else {
                switchDown[i] = ABRDefaults.minSwitchDownRatio // 최저 레벨
            }
        }

        dynamicSwitchUp = switchUp
        dynamicSwitchDown = switchDown
    }

    // MARK: - Buffer-Aware ABR Decision (flashls AutoLevelManager.getnextlevel)

    /// sftm(Segment Fetch Time Margin) 기반 레벨 결정
    ///
    /// flashls 공식:
    ///   rsft = buffer(ms) - 2 × lastFetchDuration(ms)
    ///   sftm = min(segmentDuration, rsft) / lastFetchDuration
    ///   레벨 업: sftm > 1 + switchUp[current]
    ///   레벨 다운: sftm < 1 - switchDown[current]
    private func bufferAwareDecision(
        context: PlaybackContext,
        estimatedBandwidth: Double,
        safeBandwidth: Double
    ) -> ABRDecision {
        let bufferMs = context.bufferLength * 1000.0
        let fetchMs = context.lastFetchDuration * 1000.0
        let segMs = context.lastSegmentDuration * 1000.0

        // rsft: "Remaining Segment Fetch Time" — 2개 세그먼트 다운 시간을 확보한 잔여 버퍼
        let rsft = bufferMs - 2.0 * fetchMs
        let sftm = min(segMs, rsft) / fetchMs

        let switchUpThreshold = dynamicSwitchUp.indices.contains(currentLevelIndex)
            ? dynamicSwitchUp[currentLevelIndex]
            : config.switchUpThreshold - 1.0
        let switchDownThreshold = dynamicSwitchDown.indices.contains(currentLevelIndex)
            ? dynamicSwitchDown[currentLevelIndex]
            : 1.0 - config.switchDownThreshold

        // 긴급 강등: 버퍼 비율 체크 (flashls 안전장치)
        let bufferRatio = context.lastSegmentDuration > 0
            ? context.bufferLength / context.lastSegmentDuration
            : 0

        if sftm > 1.0 + switchUpThreshold {
            // 레벨 업 후보 찾기
            let nextLevel = min(currentLevelIndex + 1, availableLevels.count - 1)
            if nextLevel > currentLevelIndex {
                // 추가 검증: 목표 레벨의 비트레이트가 safeBandwidth 이내인지
                if Double(availableLevels[nextLevel].bandwidth) <= safeBandwidth {
                    let oldLevel = currentLevelIndex
                    currentLevelIndex = nextLevel
                    lastSwitchTime = Date()
                    let reason = "sftm=\(String(format: "%.2f", sftm)) buf=\(String(format: "%.1f", context.bufferLength))s"
                    logger.info("ABR: Buffer-aware UP \(oldLevel) → \(nextLevel) (\(reason))")
                    return .switchUp(toBandwidth: availableLevels[nextLevel].bandwidth, reason: reason)
                }
            }
        } else if sftm < 1.0 - switchDownThreshold {
            // 레벨 다운 — 안전 레벨 탐색
            let targetLevel = findSafeLevel(
                below: currentLevelIndex,
                estimatedBandwidth: estimatedBandwidth,
                bufferRatio: bufferRatio
            )
            if targetLevel < currentLevelIndex {
                let oldLevel = currentLevelIndex
                currentLevelIndex = targetLevel
                lastSwitchTime = Date()
                let reason = "sftm=\(String(format: "%.2f", sftm)) buf=\(String(format: "%.1f", context.bufferLength))s"
                logger.info("ABR: Buffer-aware DOWN \(oldLevel) → \(targetLevel) (\(reason))")
                return .switchDown(toBandwidth: availableLevels[targetLevel].bandwidth, reason: reason)
            }
        }

        // [Fix 23B] 긴급 강등: 버퍼 비율 + 절대 길이 이중 조건
        // 기존: bufferRatio < 2.0만 → 정상 버퍼(4초/2초seg=2.0)에서도 발동
        // 개선: 절대 길이 < 2초 추가 — 실제 위험할 때만 긴급 강등
        if bufferRatio < ABRDefaults.emergencyBufferRatio && context.bufferLength < 2.0 && currentLevelIndex > 0 {
            let emergencyLevel = findSafeLevel(
                below: currentLevelIndex,
                estimatedBandwidth: estimatedBandwidth,
                bufferRatio: bufferRatio
            )
            if emergencyLevel < currentLevelIndex {
                let oldLevel = currentLevelIndex
                currentLevelIndex = emergencyLevel
                lastSwitchTime = Date()
                let reason = "EMERGENCY bufRatio=\(String(format: "%.2f", bufferRatio))"
                logger.warning("ABR: Emergency DROP \(oldLevel) → \(emergencyLevel) (\(reason))")
                return .switchDown(toBandwidth: availableLevels[emergencyLevel].bandwidth, reason: reason)
            }
        }

        return .maintain
    }

    /// 안전 하위 레벨 탐색 — flashls의 bufferRatio + bandwidth 이중 검증
    private func findSafeLevel(below current: Int, estimatedBandwidth: Double, bufferRatio: Double) -> Int {
        for j in stride(from: current - 1, through: 0, by: -1) {
            let bitrate = Double(availableLevels[j].bandwidth)
            // flashls: bitrate[j] <= lastBandwidth && bufferRatio > 2 × bitrate[j] / lastBandwidth
            let bwOk = bitrate <= estimatedBandwidth
            let bufOk = estimatedBandwidth > 0
                ? bufferRatio > ABRDefaults.emergencyBufferRatio * bitrate / estimatedBandwidth
                : true
            if bwOk && bufOk {
                return j
            }
        }
        return 0 // 최하위 레벨
    }

    // MARK: - Bandwidth-Only Decision (기존 방식)

    private func bandwidthOnlyDecision(safeBandwidth: Double, estimatedBandwidth: Double) -> ABRDecision {
        // Find the best level that fits within our bandwidth
        var bestLevel = 0
        for (index, level) in availableLevels.enumerated() {
            if Double(level.bandwidth) <= safeBandwidth {
                bestLevel = index
            }
        }
        
        if bestLevel == currentLevelIndex {
            return .maintain
        }
        
        let oldLevel = currentLevelIndex
        let newLevel = bestLevel
        
        // Apply hysteresis (동적 임계값 사용)
        if newLevel > currentLevelIndex {
            let threshold = dynamicSwitchUp.indices.contains(currentLevelIndex)
                ? 1.0 + dynamicSwitchUp[currentLevelIndex]
                : config.switchUpThreshold
            let requiredBandwidth = Double(availableLevels[newLevel].bandwidth) * threshold
            if safeBandwidth < requiredBandwidth {
                return .maintain
            }
            
            currentLevelIndex = newLevel
            lastSwitchTime = Date()
            let reason = "BW: \(formatBps(estimatedBandwidth)) > \(formatBps(requiredBandwidth))"
            logger.info("ABR: Switch UP \(oldLevel) → \(newLevel) (\(reason))")
            return .switchUp(toBandwidth: availableLevels[newLevel].bandwidth, reason: reason)
            
        } else {
            let threshold = dynamicSwitchDown.indices.contains(currentLevelIndex)
                ? 1.0 - dynamicSwitchDown[currentLevelIndex]
                : config.switchDownThreshold
            let requiredBandwidth = Double(availableLevels[currentLevelIndex].bandwidth) * threshold
            if safeBandwidth > requiredBandwidth {
                return .maintain
            }
            
            currentLevelIndex = newLevel
            lastSwitchTime = Date()
            let reason = "BW: \(formatBps(estimatedBandwidth)) < \(formatBps(requiredBandwidth))"
            logger.info("ABR: Switch DOWN \(oldLevel) → \(newLevel) (\(reason))")
            return .switchDown(toBandwidth: availableLevels[newLevel].bandwidth, reason: reason)
        }
    }
    
    // MARK: - Helpers
    
    private func formatBps(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1fMbps", bps / 1_000_000)
        } else {
            return String(format: "%.0fKbps", bps / 1_000)
        }
    }
}
