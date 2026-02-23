// MARK: - CViewCore/Utilities/AsyncTimerSequence.swift
// AsyncSequence 기반 타이머 — Timer.scheduledTimer 대체

import Foundation

/// 비동기 타이머 시퀀스 — Swift Concurrency 네이티브
public struct AsyncTimerSequence: AsyncSequence, Sendable {
    public typealias Element = Date

    private let interval: Duration
    private let tolerance: Duration?

    public init(interval: Duration, tolerance: Duration? = nil) {
        self.interval = interval
        self.tolerance = tolerance
    }

    /// Convenience init from TimeInterval (seconds)
    public init(interval: TimeInterval, tolerance: TimeInterval? = nil) {
        self.interval = .seconds(interval)
        self.tolerance = tolerance.map { .seconds($0) }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(interval: interval, tolerance: tolerance)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let interval: Duration
        private let tolerance: Duration?

        init(interval: Duration, tolerance: Duration? = nil) {
            self.interval = interval
            self.tolerance = tolerance
        }

        public mutating func next() async -> Date? {
            guard !Task.isCancelled else { return nil }
            do {
                if let tolerance {
                    try await Task.sleep(for: interval, tolerance: tolerance)
                } else {
                    try await Task.sleep(for: interval)
                }
                guard !Task.isCancelled else { return nil }
                return Date.now
            } catch {
                return nil
            }
        }
    }
}

// MARK: - Convenience

extension AsyncTimerSequence {
    /// 초 단위 타이머 (tolerance = interval × 20% — OS 타이머 병합으로 CPU 절약)
    public static func seconds(_ seconds: Double) -> AsyncTimerSequence {
        let ms = Int(seconds * 1000)
        let toleranceMs = Swift.max(50, Int(Double(ms) * 0.20))
        return AsyncTimerSequence(
            interval: .milliseconds(ms),
            tolerance: .milliseconds(toleranceMs)
        )
    }

    /// 밀리초 단위 타이머 (tolerance = ms × 10%)
    public static func milliseconds(_ ms: Int) -> AsyncTimerSequence {
        let toleranceMs = Swift.max(10, ms / 10)
        return AsyncTimerSequence(
            interval: .milliseconds(ms),
            tolerance: .milliseconds(toleranceMs)
        )
    }
}
