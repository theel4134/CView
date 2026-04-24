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
        public let resolution: String?           // 영상 해상도 (예: "1920x1080")
        public let inputBitrateKbps: Double      // 입력 비트레이트 (kbps)
        public let networkSpeedBytesPerSec: Int  // 실시간 네트워크 수신 속도 (bytes/sec)
        public let thermalState: String          // 시스템 열 상태 (nominal/fair/serious/critical)
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
            resolution: String? = nil,
            inputBitrateKbps: Double = 0,
            networkSpeedBytesPerSec: Int = 0,
            thermalState: String = "nominal",
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
            self.resolution = resolution
            self.inputBitrateKbps = inputBitrateKbps
            self.networkSpeedBytesPerSec = networkSpeedBytesPerSec
            self.thermalState = thermalState
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
    private var _resolution: String?
    private var _inputBitrateKbps: Double = 0
    private var _networkSpeedBytesPerSec: Int = 0
    
    // 메모리 압력 감시 — 장시간 재생 시 메모리 누수 대응
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    /// 메모리 압력 감지 시 호출되는 콜백 (캐시 정리 등)
    public var onMemoryWarning: (@Sendable () -> Void)?
    /// 메모리 사용량 이력 — 메모리 증가 추세 분석용 (최근 60개, 1분 간격)
    private var memoryTrend: [Double] = []
    private let memoryTrendMaxSize = 60
    /// 메모리 증가 추세 경고 임계치 (MB/분) — 이 이상이면 누수 의심
    private let memoryGrowthWarningThreshold: Double = 50.0
    /// 메모리 트렌드 샘플링 간격 (초) — collectMetrics interval 변경과 무관하게 정확히 60으로 유지
    private let memoryTrendSampleInterval: TimeInterval = 60.0
    private var _lastMemoryTrendSampleAt: Date = .distantPast
    
    /// CPU/GPU 캐시 — IOKit+task_threads 커널 호출을 매초→5초로 줄임
    /// [GPU/CPU 최적화] IORegistryEntryCreateCFProperties + task_threads 는 무거운 커널 호출.
    /// 3초 → 5초로 늘려 호출 빈도를 40% 줄임. 성능 오버레이는 참고 지표이므로 5초 지연 허용.
    private var _cachedCPU: Double = 0
    private var _cachedGPU: (usage: Double, renderer: Double, memMB: Double) = (0, 0, 0)
    private var _kernelSampleCounter: Int = 0
    private let kernelSampleInterval = 5  // 5초마다 커널 호출
    
    public var currentMetrics: Metrics? { metricsHistory.last }
    
    // MARK: - Initialization
    
    public init(maxHistorySize: Int = 300) {
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Control
    
    /// Start collecting metrics
    /// interval 기본값 10.0: VLC statTimer(5초)보다 느린 주기로 CPU 오버헤드 최소화.
    /// 성능 오버레이는 실시간 디버깅용이 아닌 추세 확인용이므로 10초면 충분.
    public func start(interval: TimeInterval = 10.0) {
        guard !isRunning else { return }
        isRunning = true
        
        // [Fix N-3] PowerAware: 호출자 인자를 그대로 두고 내부에서 Battery 모드 1.5× 적용
        // — AC 10s / Battery 15s, 추세 확인 정밀도 영향 미미
        let effectiveInterval = PowerAwareInterval.scaled(interval)
        collectionTask = Task {
            let timer = AsyncTimerSequence(interval: effectiveInterval)
            for await _ in timer {
                guard !Task.isCancelled else { break }
                await self.collectMetrics()
            }
        }
        
        // macOS 메모리 압력 이벤트 감시 — 시스템이 메모리 부족 시 자동 대응
        startMemoryPressureMonitor()
        
        logger.info("Performance monitoring started")
    }
    
    /// Stop collecting metrics
    public func stop() {
        isRunning = false
        collectionTask?.cancel()
        collectionTask = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        // stream 소비자가 hang하지 않도록 continuation 종료
        metricsContinuation?.finish()
        metricsContinuation = nil
        _metricsStream = nil
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
    
    public func updateResolution(_ resolution: String?) {
        _resolution = resolution
    }
    
    public func updateInputBitrate(_ kbps: Double) {
        _inputBitrateKbps = kbps
    }
    
    public func updateNetworkSpeed(_ bytesPerSec: Int) {
        _networkSpeedBytesPerSec = bytesPerSec
    }

    /// VLC 메트릭 일괄 업데이트 — 7개 개별 actor hop → 1회 호출로 통합
    /// MetricsForwarder.updateVLCMetrics() 에서 단일 호출로 사용.
    public func updateVLCMetricsBatch(
        fps: Double,
        droppedFrames: Int,
        networkBytes: Int,
        bufferHealth: Double,
        resolution: String?,
        inputBitrateKbps: Double,
        networkSpeedBytesPerSec: Int
    ) {
        _currentFPS = fps
        _droppedFrames = droppedFrames
        _networkBytes = networkBytes
        _bufferHealth = bufferHealth
        _resolution = resolution
        _inputBitrateKbps = inputBitrateKbps
        _networkSpeedBytesPerSec = networkSpeedBytesPerSec
    }

    // MARK: - Private
    
    private func collectMetrics() async {
        // CPU/GPU는 커널 호출(task_threads, IOKit)이므로 3초마다만 실제 샘플링
        _kernelSampleCounter += 1
        if _kernelSampleCounter >= kernelSampleInterval {
            _kernelSampleCounter = 0
            // [Power-Aware] AC: .utility (E-core 적당 응답), Battery: .background (E-core+스로틀)
            // IOKit/task_threads 호출은 반드시 백그라운드이므로 P-core 승격 불필요.
            let prio = PowerAwareTaskPriority.periodic
            async let gpuTask = Task.detached(priority: prio) { self.readGPUStats() }.value
            async let cpuTask = Task.detached(priority: prio) { self.currentCPUUsage() }.value
            let (gpu, cpu) = await (gpuTask, cpuTask)
            _cachedGPU = gpu
            _cachedCPU = cpu
        }
        
        let gpu = _cachedGPU
        let memUsage = currentMemoryUsage()
        // Thermal state 조회 — ProcessInfo 프로퍼티 참조만으로 비용 0
        let thermal: String = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:  return "nominal"
            case .fair:     return "fair"
            case .serious:  return "serious"
            case .critical: return "critical"
            @unknown default: return "unknown"
            }
        }()
        
        let metrics = Metrics(
            fps: _currentFPS,
            droppedFrames: _droppedFrames,
            memoryUsageMB: memUsage,
            cpuUsage: _cachedCPU,
            networkBytesReceived: _networkBytes,
            bufferHealthPercent: _bufferHealth,
            latencyMs: _latencyMs,
            gpuUsagePercent: gpu.usage,
            gpuRendererPercent: gpu.renderer,
            gpuMemoryUsedMB: gpu.memMB,
            resolution: _resolution,
            inputBitrateKbps: _inputBitrateKbps,
            networkSpeedBytesPerSec: _networkSpeedBytesPerSec,
            thermalState: thermal,
            timestamp: Date()
        )
        
        metricsHistory.append(metrics)
        if metricsHistory.count > maxHistorySize {
            metricsHistory.removeFirst()
        }
        
        metricsContinuation?.yield(metrics)
        
        // [Tune] 메모리 증가 추세 분석 (시간 기반 — collectMetrics interval 변경에 영향 받지 않음)
        // 매 collectMetrics 시간 기반으로 60초 경과 시마다 1개 샘플 기록 — 5개면 5분간 추세 분석
        let now = metrics.timestamp
        if now.timeIntervalSince(_lastMemoryTrendSampleAt) >= memoryTrendSampleInterval {
            _lastMemoryTrendSampleAt = now
            memoryTrend.append(memUsage)
            if memoryTrend.count > memoryTrendMaxSize {
                memoryTrend.removeFirst()
            }
            
            // 최근 5분(5 샘플) 동안 메모리 증가 추세 확인
            if memoryTrend.count >= 5 {
                let recentCount = min(5, memoryTrend.count)
                let recent = Array(memoryTrend.suffix(recentCount))
                if let last = recent.last, let first = recent.first {
                    let growthPerMinute = (last - first) / Double(recentCount - 1)
                
                    if growthPerMinute > memoryGrowthWarningThreshold {
                        logger.warning("⚠️ 메모리 증가 추세 감지: \(String(format: "%.1f", growthPerMinute))MB/분 (현재 \(String(format: "%.0f", memUsage))MB)")
                        // 메모리 경고 콜백 트리거
                        onMemoryWarning?()
                    }
                }
            }
        }
    }

    // MARK: - Memory Pressure Monitor
    
    /// macOS 메모리 압력 이벤트 감시 — DispatchSourceMemoryPressure 기반
    /// 시스템이 메모리 압력을 감지하면 캐시 정리 콜백을 자동 호출
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            let isCritical = source.data.contains(.critical)
            Task { [weak self] in
                guard let self else { return }
                let level = isCritical ? "CRITICAL" : "WARNING"
                await self.logger.warning("🔴 메모리 압력 감지: \(level) — 캐시 정리 실행")
                await self.onMemoryWarning?()
            }
        }
        source.resume()
        memoryPressureSource = source
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
    private nonisolated func currentMemoryUsage() -> Double {
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

    /// 현재 프로세스 스레드 개수 (task_threads 호출 후 count 반환)
    private nonisolated func currentThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let list = threadList else { return 0 }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: list),
            vm_size_t(MemoryLayout<thread_t>.size) * vm_size_t(threadCount)
        )
        return Int(threadCount)
    }

    // MARK: - On-Demand System Usage Snapshot

    /// 메뉴바/간이 모니터용 시스템 사용률 스냅샷
    /// 앱 프로세스 기준 CPU/Memory/GPU/스레드 수를 즉시 조회한다.
    /// 모니터 실행 여부와 무관하게 호출 가능 (isolated 상태에 의존하지 않음).
    public struct SystemUsageSnapshot: Sendable {
        public let cpuPercent: Double        // 0~N×100 (N=코어 수)
        public let memoryMB: Double
        public let gpuPercent: Double        // Device Utilization %
        public let gpuRendererPercent: Double
        public let gpuMemoryMB: Double
        public let threadCount: Int
        public let timestamp: Date
    }

    /// 현재 시점의 시스템 사용률을 즉시 반환한다.
    /// 내부적으로 task_threads + IOKit GPU 조회 수행 (수 밀리초 소요).
    public nonisolated func systemUsageSnapshot() -> SystemUsageSnapshot {
        let cpu = currentCPUUsage()
        let mem = currentMemoryUsage()
        let gpu = readGPUStats()
        let threads = currentThreadCount()
        return SystemUsageSnapshot(
            cpuPercent: cpu,
            memoryMB: mem,
            gpuPercent: gpu.usage,
            gpuRendererPercent: gpu.renderer,
            gpuMemoryMB: gpu.memMB,
            threadCount: threads,
            timestamp: Date()
        )
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

    // MARK: - GPU History API

    /// GPU 사용률 시계열 데이터 — 최근 N초간의 (timestamp, gpuUsage, gpuRenderer, gpuMemMB) 반환.
    /// 대시보드/차트 시각화에 사용.
    public struct GPUHistoryPoint: Sendable {
        public let timestamp: Date
        public let usagePercent: Double
        public let rendererPercent: Double
        public let memoryUsedMB: Double
        public let thermalState: String
    }

    /// 최근 N초간의 GPU 히스토리 반환 (기본 300초 = 5분)
    public func recentGPUHistory(seconds: Int = 300) -> [GPUHistoryPoint] {
        let cutoff = Date().addingTimeInterval(-Double(seconds))
        return metricsHistory
            .filter { $0.timestamp > cutoff }
            .map { GPUHistoryPoint(
                timestamp: $0.timestamp,
                usagePercent: $0.gpuUsagePercent,
                rendererPercent: $0.gpuRendererPercent,
                memoryUsedMB: $0.gpuMemoryUsedMB,
                thermalState: $0.thermalState
            )}
    }

    /// 최근 N초간의 피크 GPU 사용률 (Device Utilization %)
    public func peakGPUUsage(seconds: Int = 60) -> Double {
        let cutoff = Date().addingTimeInterval(-Double(seconds))
        return metricsHistory
            .filter { $0.timestamp > cutoff }
            .max(by: { $0.gpuUsagePercent < $1.gpuUsagePercent })?
            .gpuUsagePercent ?? 0
    }

    /// 최근 N초간의 평균 GPU 사용률
    public func averageGPUUsage(seconds: Int = 60) -> Double {
        let cutoff = Date().addingTimeInterval(-Double(seconds))
        let recent = metricsHistory.filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.gpuUsagePercent } / Double(recent.count)
    }
}
