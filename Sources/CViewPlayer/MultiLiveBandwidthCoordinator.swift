// MARK: - MultiLiveBandwidthCoordinator.swift
// CViewPlayer — flashls AutoLevelManager/AutoBufferManager 참조
// 멀티라이브 세션 간 대역폭 분배 + 화질 캡핑 + 버퍼 히스테리시스 조율

import Foundation
import CViewCore

// MARK: - Per-Stream State

/// 개별 스트림의 대역폭/버퍼 상태
public struct StreamBandwidthState: Sendable {
    public let sessionId: UUID
    public var currentBitrate: Double = 0
    public var bufferLength: TimeInterval = 0
    public var maxLevelBitrate: Double = 0
    public var cappedMaxBitrate: Double = 0
    public var paneWidth: Int = 1920
    public var paneHeight: Int = 1080
    public var isSelected: Bool = false
    public var lastFetchDuration: TimeInterval = 0
    public var lastSegmentDuration: TimeInterval = 4.0
    /// [Fix 20 Phase3] 현재 재생 배율 — 대역폭 소비 추정에 반영
    public var playbackRate: Double = 1.0

    public init(sessionId: UUID) {
        self.sessionId = sessionId
    }
}

// MARK: - Buffer Hysteresis State

/// flashls HLSNetStream 참조 — 2단계 임계값 버퍼링 상태 머신
public enum BufferHysteresisPhase: Sendable, Equatable {
    case playing
    case buffering
}

// MARK: - Bandwidth Advice

/// 코디네이터가 개별 세션에 내리는 지시
public struct BandwidthAdvice: Sendable {
    public let sessionId: UUID
    /// 이 세션이 사용할 수 있는 최대 비트레이트 (bps)
    public let maxAllowedBitrate: Double
    /// 화면 크기 기반 최대 해상도 높이 (0이면 제한 없음)
    public let cappedMaxHeight: Int
    /// 긴급 품질 강등 필요 여부
    public let emergencyDowngrade: Bool
    /// 버퍼 히스테리시스 위상
    public let bufferPhase: BufferHysteresisPhase
}

// MARK: - Coordinator Configuration

public struct BandwidthCoordinatorConfig: Sendable {
    /// 총 대역폭 풀에서 실제 사용 비율 (안전 마진)
    public var safetyFactor: Double
    /// 스트림당 최소 보장 대역폭 (bps)
    public var minPerStreamBitrate: Double
    /// 대역폭 히스토리 링 버퍼 크기
    public var historySize: Int
    /// 버퍼 저수위 임계값 (초) — 이 아래로 내려가면 buffering 진입
    public var lowBufferThreshold: TimeInterval
    /// 버퍼 고수위 임계값 (초) — 이 위로 올라가면 playing 복귀
    public var highBufferThreshold: TimeInterval
    /// 화면 크기 기반 레벨 캡핑 활성화
    public var enableLevelCapping: Bool
    /// 선택 세션 대역폭 가중치 (1.0 = 균등)
    public var selectedSessionWeight: Double
    /// 긴급 강등 버퍼 임계값 (초) — 전체 합산 버퍼가 이 값 미만이면 전체 강등
    public var emergencyBufferThreshold: TimeInterval

    public static let `default` = BandwidthCoordinatorConfig(
        safetyFactor: MultiLiveBWDefaults.safetyFactor,
        minPerStreamBitrate: MultiLiveBWDefaults.minPerStreamBitrate,
        historySize: MultiLiveBWDefaults.historySize,
        lowBufferThreshold: MultiLiveBWDefaults.lowBufferThreshold,
        highBufferThreshold: MultiLiveBWDefaults.highBufferThreshold,
        enableLevelCapping: true,
        selectedSessionWeight: MultiLiveBWDefaults.selectedSessionWeight,
        emergencyBufferThreshold: MultiLiveBWDefaults.emergencyBufferThreshold
    )

    public init(
        safetyFactor: Double,
        minPerStreamBitrate: Double,
        historySize: Int,
        lowBufferThreshold: TimeInterval,
        highBufferThreshold: TimeInterval,
        enableLevelCapping: Bool,
        selectedSessionWeight: Double,
        emergencyBufferThreshold: TimeInterval
    ) {
        self.safetyFactor = safetyFactor
        self.minPerStreamBitrate = minPerStreamBitrate
        self.historySize = historySize
        self.lowBufferThreshold = lowBufferThreshold
        self.highBufferThreshold = highBufferThreshold
        self.enableLevelCapping = enableLevelCapping
        self.selectedSessionWeight = selectedSessionWeight
        self.emergencyBufferThreshold = emergencyBufferThreshold
    }
}

// MARK: - MultiLiveBandwidthCoordinator

/// flashls AutoLevelManager + AutoBufferManager 패턴을 멀티라이브에 적용.
///
/// 주요 기능:
/// 1. **집계 대역폭 추적**: 전체 세션 합산 대역폭을 히스토리로 유지
/// 2. **가중 분배**: 선택 세션에 더 많은 대역폭 할당
/// 3. **화면 캡핑**: flashls capLevelToStage — 실제 패인 크기 이상은 불필요
/// 4. **버퍼 히스테리시스**: 2단계 임계값으로 재버퍼링 핑퐁 방지
/// 5. **긴급 강등**: 전체 대역폭 부족 시 모든 세션 품질 하향
public actor MultiLiveBandwidthCoordinator {

    private var config: BandwidthCoordinatorConfig
    private let logger = AppLogger.player

    // MARK: - Aggregate Bandwidth History (flashls AutoBufferManager)

    /// 집계 대역폭 히스토리 (전체 세션 합산 bps)
    private var aggregateBWHistory: [Double] = []
    private var bwSampleIndex: Int = 0

    // MARK: - Per-Stream State

    private var streamStates: [UUID: StreamBandwidthState] = [:]
    private var bufferPhases: [UUID: BufferHysteresisPhase] = [:]

    // MARK: - Init

    public init(config: BandwidthCoordinatorConfig = .default) {
        self.config = config
    }

    /// 설정 업데이트 (런타임에 변경 가능)
    public func applyConfig(_ newConfig: BandwidthCoordinatorConfig) {
        self.config = newConfig
    }

    // MARK: - Stream Registration

    public func registerStream(sessionId: UUID, isSelected: Bool) {
        var state = StreamBandwidthState(sessionId: sessionId)
        state.isSelected = isSelected
        streamStates[sessionId] = state
        bufferPhases[sessionId] = .playing
        logger.info("BWCoordinator: 스트림 등록 \(sessionId) (selected=\(isSelected))")
    }

    public func unregisterStream(sessionId: UUID) {
        streamStates.removeValue(forKey: sessionId)
        bufferPhases.removeValue(forKey: sessionId)
        logger.info("BWCoordinator: 스트림 해제 \(sessionId)")
    }

    // MARK: - State Updates

    /// 세션 선택 상태 업데이트
    public func updateSelectedState(sessionId: UUID, isSelected: Bool) {
        streamStates[sessionId]?.isSelected = isSelected
    }

    /// 패인 디스플레이 크기 업데이트 (레이아웃 변경 시)
    public func updatePaneSize(sessionId: UUID, width: Int, height: Int) {
        streamStates[sessionId]?.paneWidth = width
        streamStates[sessionId]?.paneHeight = height
    }

    /// 스트림 대역폭 샘플 보고 (세그먼트 다운로드 완료 시)
    public func reportBandwidthSample(sessionId: UUID, bitrate: Double, bufferLength: TimeInterval, fetchDuration: TimeInterval, segmentDuration: TimeInterval) {
        streamStates[sessionId]?.currentBitrate = bitrate
        streamStates[sessionId]?.bufferLength = bufferLength
        streamStates[sessionId]?.lastFetchDuration = fetchDuration
        streamStates[sessionId]?.lastSegmentDuration = segmentDuration

        // [Fix 20 Phase3] 집계 대역폭에 playbackRate 반영:
        // 가속 중인 스트림은 단위 시간당 더 많은 세그먼트를 소비
        let totalBW = streamStates.values.reduce(0.0) { $0 + $1.currentBitrate * $1.playbackRate }
        recordAggregateBandwidth(totalBW)
    }

    /// 스트림 버퍼 상태만 업데이트 (주기적 폴링용)
    public func updateBufferLength(sessionId: UUID, bufferLength: TimeInterval) {
        streamStates[sessionId]?.bufferLength = bufferLength
    }

    /// 최대 가용 레벨 비트레이트 업데이트
    public func updateMaxLevelBitrate(sessionId: UUID, maxBitrate: Double) {
        streamStates[sessionId]?.maxLevelBitrate = maxBitrate
    }

    /// [Fix 20 Phase3] 재생 배율 업데이트 — 대역폭 계산에 반영
    public func updatePlaybackRate(sessionId: UUID, rate: Double) {
        streamStates[sessionId]?.playbackRate = rate
    }

    // MARK: - Bandwidth Advice Computation

    /// 모든 등록된 세션에 대한 대역폭 분배 어드바이스 계산
    public func computeAdvice() -> [BandwidthAdvice] {
        let activeStreams = Array(streamStates.values)
        guard !activeStreams.isEmpty else { return [] }

        let streamCount = Double(activeStreams.count)
        let estimatedAggregateBW = estimateAggregateBandwidth()

        // 안전 마진 적용 후 사용 가능 대역폭
        let usableBW = estimatedAggregateBW * config.safetyFactor

        // 긴급 강등 체크: 전체 합산 버퍼가 임계값 미만
        let totalBuffer = activeStreams.reduce(0.0) { $0 + $1.bufferLength }
        let avgBuffer = totalBuffer / streamCount
        let isEmergency = avgBuffer < config.emergencyBufferThreshold

        // 가중 분배 계산
        let selectedCount = activeStreams.filter(\.isSelected).count
        let unselectedCount = activeStreams.count - selectedCount

        let totalWeight: Double
        if selectedCount > 0 && unselectedCount > 0 {
            totalWeight = Double(selectedCount) * config.selectedSessionWeight + Double(unselectedCount) * 1.0
        } else {
            totalWeight = streamCount
        }

        var advices: [BandwidthAdvice] = []

        for stream in activeStreams {
            let weight = stream.isSelected ? config.selectedSessionWeight : 1.0
            var allocated = (weight / totalWeight) * usableBW
            allocated = max(allocated, config.minPerStreamBitrate)

            // 화면 크기 기반 레벨 캡핑 (flashls capLevelToStage)
            let cappedHeight: Int
            if config.enableLevelCapping {
                cappedHeight = capLevelByPaneSize(
                    paneWidth: stream.paneWidth,
                    paneHeight: stream.paneHeight,
                    isSelected: stream.isSelected
                )
            } else {
                cappedHeight = 0
            }

            // 버퍼 히스테리시스 계산 (flashls HLSNetStream 참조)
            let phase = computeBufferPhase(sessionId: stream.sessionId, bufferLength: stream.bufferLength)

            advices.append(BandwidthAdvice(
                sessionId: stream.sessionId,
                maxAllowedBitrate: allocated,
                cappedMaxHeight: cappedHeight,
                emergencyDowngrade: isEmergency,
                bufferPhase: phase
            ))
        }

        return advices
    }

    /// 특정 세션의 현재 어드바이스만 조회
    public func adviceFor(sessionId: UUID) -> BandwidthAdvice? {
        computeAdvice().first { $0.sessionId == sessionId }
    }

    // MARK: - Aggregate Bandwidth Estimation (flashls AutoBufferManager)

    /// 집계 대역폭 기록 — 슬라이딩 윈도우 링 버퍼
    private func recordAggregateBandwidth(_ totalBW: Double) {
        if aggregateBWHistory.count < config.historySize {
            aggregateBWHistory.append(totalBW)
        } else {
            aggregateBWHistory[bwSampleIndex % config.historySize] = totalBW
        }
        bwSampleIndex += 1
    }

    /// flashls: min_bw 기반 보수적 추정
    /// bw_ratio = 2 * cur_bw / (min_bw + cur_bw)
    /// estimated = cur_bw * bw_ratio (최근 대비 최솟값 가중)
    private func estimateAggregateBandwidth() -> Double {
        guard !aggregateBWHistory.isEmpty else {
            // 히스토리 없으면 기본값: 스트림 수 × 2.5Mbps
            return Double(streamStates.count) * 2_500_000
        }

        let currentBW = aggregateBWHistory.last ?? 0
        // [Fix 26] min() 대신 P20 백분위수 사용 — 단일 이상치가 영구 저하 유발 방지
        let sorted = aggregateBWHistory.sorted()
        let p20Index = max(0, Int(Double(sorted.count) * 0.2))
        let minBW = sorted[p20Index]

        guard minBW + currentBW > 0 else { return currentBW }

        let bwRatio = 2.0 * currentBW / (minBW + currentBW)
        return currentBW * bwRatio
    }

    // MARK: - Level Capping by Pane Size (flashls capLevelToStage)

    /// 패인 크기 기반 최대 해상도 높이 결정 — downscale 모드
    /// (패인보다 작은 최고 해상도를 선택, 불필요한 고해상도 방지)
    private func capLevelByPaneSize(paneWidth: Int, paneHeight: Int, isSelected: Bool) -> Int {
        // 표준 해상도 구간
        let resolutionTiers: [(width: Int, height: Int)] = [
            (640, 360),    // 360p
            (854, 480),    // 480p
            (1280, 720),   // 720p
            (1920, 1080),  // 1080p
        ]

        // downscale 모드: 패인 크기 이상의 최소 해상도
        for tier in resolutionTiers {
            if tier.width >= paneWidth || tier.height >= paneHeight {
                return tier.height
            }
        }
        return 1080 // 폴백
    }

    // MARK: - Buffer Hysteresis (flashls HLSNetStream)

    /// 2단계 임계값 버퍼링 상태 머신
    /// - ENTER buffering: buffer < lowThreshold
    /// - EXIT buffering:  buffer >= highThreshold (히스테리시스)
    private func computeBufferPhase(sessionId: UUID, bufferLength: TimeInterval) -> BufferHysteresisPhase {
        let currentPhase = bufferPhases[sessionId] ?? .playing

        switch currentPhase {
        case .playing:
            if bufferLength < config.lowBufferThreshold {
                bufferPhases[sessionId] = .buffering
                return .buffering
            }
            return .playing

        case .buffering:
            if bufferLength >= config.highBufferThreshold {
                bufferPhases[sessionId] = .playing
                return .playing
            }
            return .buffering
        }
    }

    // MARK: - Diagnostics

    /// 현재 코디네이터 상태 요약 (디버깅용)
    public func diagnostics() -> String {
        let streams = streamStates.values.sorted { $0.sessionId.uuidString < $1.sessionId.uuidString }
        let lines = streams.map { s in
            let phase = bufferPhases[s.sessionId] ?? .playing
            return "  [\(s.isSelected ? "★" : "·")] buf=\(String(format: "%.1f", s.bufferLength))s bw=\(String(format: "%.0f", s.currentBitrate / 1000))kbps pane=\(s.paneWidth)×\(s.paneHeight) phase=\(phase)"
        }
        let aggBW = estimateAggregateBandwidth()
        return "BWCoordinator: aggBW=\(String(format: "%.1f", aggBW / 1_000_000))Mbps streams=\(streams.count)\n" + lines.joined(separator: "\n")
    }

    /// 전체 상태 리셋
    public func reset() {
        streamStates.removeAll()
        bufferPhases.removeAll()
        aggregateBWHistory.removeAll()
        bwSampleIndex = 0
    }
}
