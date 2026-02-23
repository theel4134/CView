// MARK: - CViewMonitoring Module
// 성능 모니터링 & 메트릭 수집

import Foundation
import IOKit
import CViewCore

// MARK: - Performance Monitor

/// Actor-based performance metrics collector.
/// Tracks FPS, memory, CPU, network, and player-specific metrics.
public actor PerformanceMonitor {
    
    // MARK: - Metrics
    
    public struct Metrics: Sendable {
        public let fps: Double
        public let droppedFrames: Int
        public let memoryUsageMB: Double
        public let cpuUsage: Double
        public let networkBytesReceived: Int
        public let bufferHealthPercent: Double
        public let latencyMs: Double
        public let gpuUsagePercent: Double      // GPU 전체 사용률 (Device Utilization %)
        public let gpuRendererPercent: Double   // 렌더러 사용률 (Renderer Utilization %)
        public let gpuMemoryUsedMB: Double      // GPU 사용 중인 통합 메모리 (MB)
        public let timestamp: Date
        
        public init(
            fps: Double = 0,
            droppedFrames: Int = 0,
            memoryUsageMB: Double = 0,
            cpuUsage: Double = 0,
            networkBytesReceived: Int = 0,
            bufferHealthPercent: Double = 0,
            latencyMs: Double = 0,
            gpuUsagePercent: Double = 0,
            gpuRendererPercent: Double = 0,
            gpuMemoryUsedMB: Double = 0,
            timestamp: Date = Date()
        ) {
            self.fps = fps
            self.droppedFrames = droppedFrames
            self.memoryUsageMB = memoryUsageMB
            self.cpuUsage = cpuUsage
            self.networkBytesReceived = networkBytesReceived
            self.bufferHealthPercent = bufferHealthPercent
            self.latencyMs = latencyMs
            self.gpuUsagePercent = gpuUsagePercent
            self.gpuRendererPercent = gpuRendererPercent
            self.gpuMemoryUsedMB = gpuMemoryUsedMB
            self.timestamp = timestamp
        }
    }
    
    // MARK: - Properties
    
    private var isRunning = false
    private var metricsHistory: [Metrics] = []
    private let maxHistorySize: Int
    private var collectionTask: Task<Void, Never>?
    private let logger = AppLogger.app
    
    private var metricsContinuation: AsyncStream<Metrics>.Continuation?
    private var _metricsStream: AsyncStream<Metrics>?
    
    // Current values (updated by external sources)
    private var _currentFPS: Double = 0
    private var _droppedFrames: Int = 0
    private var _networkBytes: Int = 0
    private var _bufferHealth: Double = 0
    private var _latencyMs: Double = 0
    
    public var currentMetrics: Metrics? { metricsHistory.last }
    
    // MARK: - Initialization
    
    public init(maxHistorySize: Int = 300) {
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Control
    
    /// Start collecting metrics
    public func start(interval: TimeInterval = 1.0) {
        guard !isRunning else { return }
        isRunning = true
        
        collectionTask = Task { [weak self] in
            guard let self else { return }
            
            let timer = AsyncTimerSequence(interval: interval)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                await self.collectMetrics()
            }
        }
        
        logger.info("Performance monitoring started")
    }
    
    /// Stop collecting metrics
    public func stop() {
        isRunning = false
        collectionTask?.cancel()
        collectionTask = nil
        logger.info("Performance monitoring stopped")
    }
    
    /// Get metrics stream
    public func metrics() -> AsyncStream<Metrics> {
        if let existing = _metricsStream { return existing }
        
        let stream = AsyncStream<Metrics> { continuation in
            self.metricsContinuation = continuation
        }
        _metricsStream = stream
        return stream
    }
    
    // MARK: - External Updates
    
    public func updateFPS(_ fps: Double) {
        _currentFPS = fps
    }
    
    public func updateDroppedFrames(_ count: Int) {
        _droppedFrames = count
    }
    
    public func updateNetworkBytes(_ bytes: Int) {
        _networkBytes = bytes
    }
    
    public func updateBufferHealth(_ percent: Double) {
        _bufferHealth = percent
    }
    
    public func updateLatency(_ ms: Double) {
        _latencyMs = ms
    }
    
    // MARK: - Private
    
    private func collectMetrics() {
        let gpu = readGPUStats()
        let metrics = Metrics(
            fps: _currentFPS,
            droppedFrames: _droppedFrames,
            memoryUsageMB: currentMemoryUsage(),
            cpuUsage: currentCPUUsage(),
            networkBytesReceived: _networkBytes,
            bufferHealthPercent: _bufferHealth,
            latencyMs: _latencyMs,
            gpuUsagePercent: gpu.usage,
            gpuRendererPercent: gpu.renderer,
            gpuMemoryUsedMB: gpu.memMB,
            timestamp: Date()
        )
        
        metricsHistory.append(metrics)
        if metricsHistory.count > maxHistorySize {
            metricsHistory.removeFirst()
        }
        
        metricsContinuation?.yield(metrics)
    }
    
    /// Apple Silicon GPU 사용률 조회 (IOKit IOAccelerator → PerformanceStatistics)
    private nonisolated func readGPUStats() -> (usage: Double, renderer: Double, memMB: Double) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return (0, 0, 0) }
        defer { IOObjectRelease(service) }
        
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let retainedDict = propsRef?.takeRetainedValue(),
              let nsDict = retainedDict as? NSDictionary,
              let perf = nsDict["PerformanceStatistics"] as? NSDictionary
        else { return (0, 0, 0) }
        
        let usage  = (perf["Device Utilization %"]   as? NSNumber)?.doubleValue ?? 0
        let rndr   = (perf["Renderer Utilization %"]  as? NSNumber)?.doubleValue ?? 0
        let memB   = (perf["In use system memory"]    as? NSNumber)?.doubleValue ?? 0
        
        return (usage, rndr, memB / 1_048_576.0)
    }
    
    /// 프로세스 전체 스레드 CPU 사용량 합산 (0~N×100%, N=코어 수)
    /// `task_threads` + `thread_info(THREAD_BASIC_INFO)` — 비특권 API, 샌드박스 호환.
    private nonisolated func currentCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let list = threadList else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: list),
                vm_size_t(MemoryLayout<thread_t>.size) * vm_size_t(threadCount)
            )
        }
        var total = 0.0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
            )
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(list[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if kr == KERN_SUCCESS, (info.flags & Int32(TH_FLAGS_IDLE)) == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return total
    }

    /// Get current memory usage in MB
    private func currentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1_048_576.0 // bytes to MB
        }
        return 0
    }
    
    // MARK: - Statistics
    
    /// Average FPS over the last N seconds
    public func averageFPS(seconds: Int = 10) -> Double {
        let cutoff = Date().addingTimeInterval(-Double(seconds))
        let recent = metricsHistory.filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.fps } / Double(recent.count)
    }
    
    /// Peak memory usage
    public func peakMemoryMB() -> Double {
        metricsHistory.max(by: { $0.memoryUsageMB < $1.memoryUsageMB })?.memoryUsageMB ?? 0
    }
}
