// MARK: - StreamCoordinatorTests.swift
// Mock-based integration tests for StreamCoordinator lifecycle,
// quality switching, error recovery, and event emission.

import Testing
import Foundation
import AppKit
@testable import CViewPlayer
@testable import CViewCore

// MARK: - Mock Player Engine

/// Mock PlayerEngineProtocol for testing StreamCoordinator without real VLC/AVPlayer.
/// Uses @unchecked Sendable because all mutable state is accessed serially in tests.
/// Helper to create NSView off main actor for tests.
private struct UnsafeSendableView: @unchecked Sendable {
    let nsView: NSView
    @MainActor init() { nsView = NSView(frame: .zero) }
}

private final class MockPlayerEngine: PlayerEngineProtocol, @unchecked Sendable {
    // State tracking
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var seekPositions: [TimeInterval] = []
    private(set) var lastPlayURL: URL?
    private(set) var lastRate: Float = 1.0
    private(set) var lastVolume: Float = 1.0

    // Configurable behavior
    var shouldThrowOnPlay = false
    var playError: Error?

    // PlayerEngineProtocol properties
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var rate: Float = 1.0

    // NSView required by protocol — use a pre-built view
    nonisolated(unsafe) private var _videoView: NSView?
    var videoView: NSView {
        if let v = _videoView { return v }
        let v = NSView()
        _videoView = v
        return v
    }

    init() {}

    func play(url: URL) async throws {
        playCallCount += 1
        lastPlayURL = url
        if shouldThrowOnPlay, let error = playError {
            throw error
        }
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func resume() {
        resumeCallCount += 1
        isPlaying = true
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        currentTime = 0
    }

    func seek(to position: TimeInterval) {
        seekPositions.append(position)
        currentTime = position
    }

    func setRate(_ rate: Float) {
        lastRate = rate
        self.rate = rate
    }

    func setVolume(_ volume: Float) {
        lastVolume = volume
    }

    /// Reset all tracking state
    func reset() {
        playCallCount = 0
        stopCallCount = 0
        pauseCallCount = 0
        resumeCallCount = 0
        seekPositions = []
        lastPlayURL = nil
        lastRate = 1.0
        lastVolume = 1.0
        isPlaying = false
        currentTime = 0
        duration = 0
        shouldThrowOnPlay = false
        playError = nil
    }
}

// MARK: - Test Helpers

private func makeTestConfig(
    channelId: String = "test-channel",
    enableLowLatency: Bool = false,
    enableABR: Bool = false,
    preferredQuality: StreamQuality? = nil
) -> StreamCoordinator.Configuration {
    StreamCoordinator.Configuration(
        channelId: channelId,
        enableLowLatency: enableLowLatency,
        enableABR: enableABR,
        preferredQuality: preferredQuality
    )
}

private let testStreamURL = URL(string: "https://example.com/live/stream.m3u8")!
private let testStreamURL2 = URL(string: "https://example.com/live/stream-720p.m3u8")!

/// Thread-safe event collector for async stream testing.
private actor EventCollector {
    var events: [StreamEvent] = []
    func add(_ event: StreamEvent) { events.append(event) }
    var count: Int { events.count }
    func result() -> [StreamEvent] { events }
}

/// Collect events from stream with proper timeout.
/// Uses Task.sleep for cooperative timeout — `for await` alone blocks indefinitely if no events arrive.
private func collectEvents(
    from stream: AsyncStream<StreamEvent>,
    count: Int,
    timeout: TimeInterval = 2.0
) async -> [StreamEvent] {
    let collector = EventCollector()
    let task = Task {
        for await event in stream {
            await collector.add(event)
            if await collector.count >= count { return }
        }
    }
    try? await Task.sleep(for: .seconds(timeout))
    task.cancel()
    try? await Task.sleep(for: .milliseconds(100))
    return await collector.result()
}

// MARK: - StreamCoordinator Initialization Tests

@Suite("StreamCoordinator — Initialization")
struct StreamCoordinatorInitTests {

    @Test("Coordinator starts in idle phase")
    func initialPhaseIdle() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let phase = await coordinator.phase
        #expect(phase == .idle)
    }

    @Test("Coordinator starts with no quality info")
    func initialNoQuality() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let quality = await coordinator.currentQuality
        #expect(quality == nil)
    }

    @Test("Coordinator isPlaying is false initially")
    func initialNotPlaying() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let playing = await coordinator.isPlaying
        #expect(playing == false)
    }

    @Test("Coordinator uptime is zero initially")
    func initialUptimeZero() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let uptime = await coordinator.uptime
        #expect(uptime == 0)
    }

    @Test("Available qualities empty before manifest load")
    func initialNoQualities() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let qualities = await coordinator.availableQualities
        #expect(qualities.isEmpty)
    }
}

// MARK: - StreamCoordinator Lifecycle Tests

@Suite("StreamCoordinator — Stream Lifecycle")
struct StreamCoordinatorLifecycleTests {

    @Test("Start stream transitions to playing phase")
    func startStreamPlaying() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)

        let phase = await coordinator.phase
        #expect(phase == .playing)
        #expect(engine.playCallCount == 1)
        #expect(engine.lastPlayURL != nil)
    }

    @Test("Stop stream transitions to idle phase")
    func stopStreamIdle() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        await coordinator.stopStream()

        let phase = await coordinator.phase
        #expect(phase == .idle)
        #expect(engine.stopCallCount == 1)
    }

    @Test("Start then stop resets uptime tracking")
    func startStopResetsUptime() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        let uptimeBefore = await coordinator.uptime
        #expect(uptimeBefore >= 0)

        await coordinator.stopStream()
        let uptimeAfter = await coordinator.uptime
        #expect(uptimeAfter == 0)
    }

    @Test("Pause transitions to paused phase")
    func pausePhase() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        await coordinator.pause()

        let phase = await coordinator.phase
        #expect(phase == .paused)
        #expect(engine.pauseCallCount == 1)
    }

    @Test("Resume after pause transitions back to playing")
    func resumeAfterPause() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        await coordinator.pause()
        await coordinator.resume()

        let phase = await coordinator.phase
        #expect(phase == .playing)
        #expect(engine.resumeCallCount == 1)
    }

    @Test("Start stream with failing engine transitions to error phase")
    func startStreamError() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        engine.shouldThrowOnPlay = true
        engine.playError = PlayerError.streamNotFound
        await coordinator.setPlayerEngine(engine)

        do {
            try await coordinator.startStream(url: testStreamURL)
            Issue.record("Expected error to be thrown")
        } catch {
            let phase = await coordinator.phase
            if case .error = phase {
                // Expected
            } else {
                Issue.record("Expected .error phase, got \(phase)")
            }
        }
    }
}

// MARK: - StreamCoordinator Quality Tests

@Suite("StreamCoordinator — Quality")
struct StreamCoordinatorQualityTests {

    @Test("switchQualityByBandwidth throws when quality not found")
    func switchQualityNotFound() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        await #expect(throws: StreamCoordinatorError.self) {
            try await coordinator.switchQualityByBandwidth(9999999)
        }
    }

    @Test("StreamQualityInfo stores name, resolution, bandwidth")
    func qualityInfoProperties() {
        let info = StreamQualityInfo(name: "1080p", resolution: "1920x1080", bandwidth: 5_000_000)
        #expect(info.name == "1080p")
        #expect(info.resolution == "1920x1080")
        #expect(info.bandwidth == 5_000_000)
        #expect(info.id == "1080p") // id == name
    }

    @Test("StreamQualityInfo equatable conformance")
    func qualityInfoEquatable() {
        let a = StreamQualityInfo(name: "720p", resolution: "1280x720", bandwidth: 3_000_000)
        let b = StreamQualityInfo(name: "720p", resolution: "1280x720", bandwidth: 3_000_000)
        let c = StreamQualityInfo(name: "1080p", resolution: "1920x1080", bandwidth: 5_000_000)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - StreamCoordinator Event Tests

@Suite("StreamCoordinator — Events")
struct StreamCoordinatorEventTests {

    @Test("Event stream is accessible")
    func eventStreamAccessible() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let stream = await coordinator.events()
        #expect(type(of: stream) == AsyncStream<StreamEvent>.self)
    }

    @Test("Start stream emits phaseChanged events")
    func startStreamEmitsPhaseChanged() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)
        let stream = await coordinator.events()

        Task { try await coordinator.startStream(url: testStreamURL) }

        let events = await collectEvents(from: stream, count: 2, timeout: 2.0)
        let phaseEvents = events.compactMap { event -> StreamCoordinator.StreamPhase? in
            if case .phaseChanged(let phase) = event { return phase }
            return nil
        }

        // Should include .connecting and .playing
        #expect(phaseEvents.contains(.connecting))
        #expect(phaseEvents.contains(.playing))
    }

    @Test("Stop stream emits stopped event")
    func stopStreamEmitsStopped() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        let stream = await coordinator.events()

        Task { await coordinator.stopStream() }

        let events = await collectEvents(from: stream, count: 3, timeout: 2.0)
        let hasStopped = events.contains { event in
            if case .stopped = event { return true }
            return false
        }
        #expect(hasStopped)
    }
}

// MARK: - StreamCoordinator Snapshot Tests

@Suite("StreamCoordinator — Snapshot")
struct StreamCoordinatorSnapshotTests {

    @Test("Snapshot reflects idle state")
    func snapshotIdle() async {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let snapshot = await coordinator.snapshot()

        #expect(snapshot.phase == .idle)
        #expect(snapshot.quality == nil)
        #expect(snapshot.uptime == 0)
    }

    @Test("Snapshot reflects playing state")
    func snapshotPlaying() async throws {
        let coordinator = StreamCoordinator(configuration: makeTestConfig())
        let engine = MockPlayerEngine()
        engine.rate = 1.0
        await coordinator.setPlayerEngine(engine)

        try await coordinator.startStream(url: testStreamURL)
        let snapshot = await coordinator.snapshot()

        #expect(snapshot.phase == .playing)
        #expect(snapshot.playbackRate == 1.0)
        #expect(snapshot.uptime >= 0)
    }
}

// MARK: - StreamPhase Tests

@Suite("StreamPhase — Equatable & Coverage")
struct StreamPhaseTests {

    @Test("All phases are equatable")
    func phasesEquatable() {
        #expect(StreamCoordinator.StreamPhase.idle == .idle)
        #expect(StreamCoordinator.StreamPhase.loadingInfo == .loadingInfo)
        #expect(StreamCoordinator.StreamPhase.loadingManifest == .loadingManifest)
        #expect(StreamCoordinator.StreamPhase.connecting == .connecting)
        #expect(StreamCoordinator.StreamPhase.playing == .playing)
        #expect(StreamCoordinator.StreamPhase.paused == .paused)
        #expect(StreamCoordinator.StreamPhase.buffering == .buffering)
        #expect(StreamCoordinator.StreamPhase.reconnecting == .reconnecting)
        #expect(StreamCoordinator.StreamPhase.error("x") == .error("x"))
        #expect(StreamCoordinator.StreamPhase.error("x") != .error("y"))
    }

    @Test("Different phases are not equal")
    func differentPhasesNotEqual() {
        #expect(StreamCoordinator.StreamPhase.idle != .playing)
        #expect(StreamCoordinator.StreamPhase.connecting != .playing)
    }
}

// MARK: - StreamEvent Tests

@Suite("StreamEvent — Coverage")
struct StreamEventCoverageTests {

    @Test("All event cases are Sendable")
    func eventsSendable() {
        // Compile-time Sendable conformance check
        let _: StreamEvent = .phaseChanged(.idle)
        let _: StreamEvent = .qualitySelected(StreamQualityInfo(name: "1080p", resolution: "1920x1080", bandwidth: 5_000_000))
        let _: StreamEvent = .qualityChanged(StreamQualityInfo(name: "720p", resolution: "1280x720", bandwidth: 3_000_000))
        let _: StreamEvent = .abrDecision(.maintain)
        let _: StreamEvent = .latencyUpdate(LatencyInfo(current: 2.0, target: 1.5, ewma: 1.8))
        let _: StreamEvent = .bufferUpdate(BufferHealth(currentLevel: 3.0, targetLevel: 2.0, isHealthy: true))
        let _: StreamEvent = .error("test error")
        let _: StreamEvent = .stopped
        // If this compiles, all cases are Sendable ✓
    }
}

// MARK: - Supporting Types Tests

@Suite("Supporting Types — LatencyInfo & BufferHealth")
struct SupportingTypesTests {

    @Test("LatencyInfo stores values correctly")
    func latencyInfo() {
        let info = LatencyInfo(current: 2.5, target: 1.5, ewma: 2.0)
        #expect(info.current == 2.5)
        #expect(info.target == 1.5)
        #expect(info.ewma == 2.0)
    }

    @Test("BufferHealth stores values correctly")
    func bufferHealth() {
        let health = BufferHealth(currentLevel: 4.0, targetLevel: 3.0, isHealthy: true)
        #expect(health.currentLevel == 4.0)
        #expect(health.targetLevel == 3.0)
        #expect(health.isHealthy == true)
    }

    @Test("BufferHealth unhealthy state")
    func bufferHealthUnhealthy() {
        let health = BufferHealth(currentLevel: 0.5, targetLevel: 3.0, isHealthy: false)
        #expect(health.isHealthy == false)
    }
}

// MARK: - PlaybackReconnectionHandler Tests

@Suite("PlaybackReconnectionHandler — Integration")
struct PlaybackReconnectionHandlerTests {

    @Test("Handler starts with zero attempts")
    func initialZeroAttempts() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        let attempt = await handler.currentAttempt
        #expect(attempt == 0)
    }

    @Test("Handler is not reconnecting initially")
    func initialNotReconnecting() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        let reconnecting = await handler.isReconnecting
        #expect(reconnecting == false)
    }

    @Test("Cancel resets handler state")
    func cancelResetsState() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        await handler.cancel()
        let attempt = await handler.currentAttempt
        let reconnecting = await handler.isReconnecting
        #expect(attempt == 0)
        #expect(reconnecting == false)
    }

    @Test("HandleSuccess resets handler")
    func handleSuccessResets() async {
        let handler = PlaybackReconnectionHandler(config: .balanced)
        await handler.handleSuccess()
        let attempt = await handler.currentAttempt
        #expect(attempt == 0)
    }

    @Test("ReconnectionConfig presets have different max retries")
    func presetsDifferentMaxRetries() {
        let aggressive = ReconnectionConfig.aggressive
        let balanced = ReconnectionConfig.balanced
        let conservative = ReconnectionConfig.conservative

        #expect(aggressive.maxRetries > balanced.maxRetries)
        #expect(balanced.maxRetries > conservative.maxRetries)
    }

    @Test("ReconnectionConfig aggressive has smaller base delay")
    func aggressiveSmallerBaseDelay() {
        #expect(ReconnectionConfig.aggressive.baseDelay < ReconnectionConfig.balanced.baseDelay)
        #expect(ReconnectionConfig.balanced.baseDelay < ReconnectionConfig.conservative.baseDelay)
    }
}

// MARK: - Mock Player Engine Tests

@Suite("MockPlayerEngine — Behavior Verification")
struct MockPlayerEngineTests {

    @Test("Mock engine tracks play calls")
    func trackPlayCalls() async throws {
        let engine = MockPlayerEngine()

        try await engine.play(url: testStreamURL)
        #expect(engine.playCallCount == 1)
        #expect(engine.lastPlayURL == testStreamURL)
        #expect(engine.isPlaying == true)

        try await engine.play(url: testStreamURL2)
        #expect(engine.playCallCount == 2)
        #expect(engine.lastPlayURL == testStreamURL2)
    }

    @Test("Mock engine tracks stop/pause/resume")
    func trackLifecycle() async throws {
        let engine = MockPlayerEngine()

        try await engine.play(url: testStreamURL)
        engine.pause()
        #expect(engine.pauseCallCount == 1)
        #expect(engine.isPlaying == false)

        engine.resume()
        #expect(engine.resumeCallCount == 1)
        #expect(engine.isPlaying == true)

        engine.stop()
        #expect(engine.stopCallCount == 1)
        #expect(engine.isPlaying == false)
    }

    @Test("Mock engine tracks seek positions")
    func trackSeek() {
        let engine = MockPlayerEngine()

        engine.seek(to: 10.0)
        engine.seek(to: 25.5)
        engine.seek(to: 0.0)

        #expect(engine.seekPositions == [10.0, 25.5, 0.0])
        #expect(engine.currentTime == 0.0)
    }

    @Test("Mock engine throws when configured")
    func throwsOnPlay() async {
        let engine = MockPlayerEngine()
        engine.shouldThrowOnPlay = true
        engine.playError = PlayerError.engineInitFailed

        await #expect(throws: PlayerError.self) {
            try await engine.play(url: testStreamURL)
        }
    }

    @Test("Mock engine rate and volume")
    func rateAndVolume() {
        let engine = MockPlayerEngine()

        engine.setRate(1.25)
        #expect(engine.rate == 1.25)
        #expect(engine.lastRate == 1.25)

        engine.setVolume(0.5)
        #expect(engine.lastVolume == 0.5)
    }
}

