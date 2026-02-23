// MARK: - ABRController.swift
// CViewPlayer - Adaptive Bitrate Controller
// 원본: ABRController.swift (HLS.js port) → 개선: Actor-based, dual EWMA

import Foundation
import CViewCore

// MARK: - ABR Controller

/// Adaptive Bitrate Rate controller using dual EWMA bandwidth estimation.
/// Ported from HLS.js ABR logic with Swift 6 concurrency improvements.
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
            bandwidthSafetyFactor: 0.7,
            switchUpThreshold: 1.2,
            switchDownThreshold: 0.8,
            minSwitchInterval: 5.0,
            initialBandwidthEstimate: 5_000_000
        )
        
        public init(
            minBandwidthBps: Int = 500_000,
            maxBandwidthBps: Int = 50_000_000,
            bandwidthSafetyFactor: Double = 0.7,
            switchUpThreshold: Double = 1.2,
            switchDownThreshold: Double = 0.8,
            minSwitchInterval: TimeInterval = 5.0,
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
        let levelCount = self.availableLevels.count
        logger.info("ABR: Set \(levelCount) levels")
    }
    
    /// Record a bandwidth measurement sample
    public func recordSample(_ sample: BandwidthSample) {
        let bps = sample.bitsPerSecond
        guard bps > 0 else { return }
        
        let _ = fastEWMA.update(bps)
        let _ = slowEWMA.update(bps)
        sampleCount += 1
    }
    
    /// Get the recommended quality level based on current bandwidth
    public func recommendLevel() -> ABRDecision {
        guard !availableLevels.isEmpty else { return .maintain }
        
        // Minimum interval between switches
        if let lastSwitch = lastSwitchTime,
           Date().timeIntervalSince(lastSwitch) < config.minSwitchInterval {
            return .maintain
        }
        
        let estimatedBandwidth = currentBandwidthEstimate()
        let safeBandwidth = estimatedBandwidth * config.bandwidthSafetyFactor
        
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
        
        // Apply hysteresis
        if newLevel > currentLevelIndex {
            // Switching up - require higher threshold
            let requiredBandwidth = Double(availableLevels[newLevel].bandwidth) * config.switchUpThreshold
            if safeBandwidth < requiredBandwidth {
                return .maintain
            }
            
            currentLevelIndex = newLevel
            lastSwitchTime = Date()
            let reason = "BW: \(formatBps(estimatedBandwidth)) > \(formatBps(requiredBandwidth))"
            logger.info("ABR: Switch UP \(oldLevel) → \(newLevel) (\(reason))")
            return .switchUp(toBandwidth: availableLevels[newLevel].bandwidth, reason: reason)
            
        } else {
            // Switching down - react faster
            let requiredBandwidth = Double(availableLevels[currentLevelIndex].bandwidth) * config.switchDownThreshold
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
    
    /// Current bandwidth estimate using conservative EWMA
    public func currentBandwidthEstimate() -> Double {
        guard sampleCount > 0 else {
            return Double(config.initialBandwidthEstimate)
        }
        
        // Use the lower of fast and slow EWMA for conservative estimate
        let fast = fastEWMA.current
        let slow = slowEWMA.current
        
        if fast == 0 && slow == 0 {
            return Double(config.initialBandwidthEstimate)
        }
        
        return min(fast, slow)
    }
    
    /// Force a specific quality level
    public func forceLevelIndex(_ index: Int) {
        guard index >= 0, index < availableLevels.count else { return }
        currentLevelIndex = index
        lastSwitchTime = Date()
        logger.info("ABR: Forced to level \(index)")
    }
    
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
