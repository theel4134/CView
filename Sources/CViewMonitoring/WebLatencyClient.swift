// MARK: - WebLatencyClient.swift
// CViewMonitoring - PDT 기반 웹/앱 정밀 동기화 비교 클라이언트 (P0 / 2026-04-25)
//
// 목적
// ──────────────────────────────────────────────────────────────────────────
// `MetricsForwarder` 가 사용하는 `cviewSyncStatus` 보다 정밀한 비교 채널.
// 서버 `handle_pdt_comparison()` 은 웹/앱 모두의 EXT-X-PROGRAM-DATE-TIME 을
// 치지직 서버 시간 기준으로 정규화해 driftMs 를 ±50ms 정밀도로 산출한다.
//
// 본 actor 는 P0 에서 "측정 기준 단일화" 만 담당한다:
//   1. 채널 ID 를 등록하면 일정 주기로 `pdtComparison` 을 폴링.
//   2. 응답을 신선도(`isPrecisionEligible`) 와 함께 `latestSample()` 로 노출.
//   3. 직접 playback rate 나 seek 을 호출하지 않는다 — 후속 P1
//      `WebSyncController actor` 가 이 샘플을 입력으로 받아 결정한다.
//
// 따라서 본 클라이언트는 부작용이 없다(read-only). MetricsForwarder 의 rate
// 보정은 별도 토글(`rateControlEnabled`)로 비활성화되어 정책 단일 소유권을
// 보장한다.

import Foundation
import CViewCore
import CViewNetworking

/// PDT 비교 응답 스냅샷 — 호출 측이 `actor` 외부에서 안전하게 들고 다닐 수 있도록
/// `Sendable` 값 타입으로 압축한다. 신선도(`isFresh`) 와 정밀 제어 가능 여부
/// (`isPrecisionEligible`) 를 응답 시점에 미리 계산해 둔다.
public struct PDTComparisonSnapshot: Sendable, Equatable {
    public let channelId: String
    public let driftMs: Double?
    public let webLatencyMs: Double?
    public let appLatencyMs: Double?
    public let syncPrecision: String?
    public let webHasPdt: Bool
    public let appHasPdt: Bool
    /// 응답 시각(서버 ms) 기준 web 샘플 나이.
    public let webAgeMs: Int64?
    public let appAgeMs: Int64?
    /// `webHasPdt && appHasPdt && 양쪽 5s 이내` 일 때 true.
    public let isPrecisionEligible: Bool
    /// 클라이언트가 응답을 수신해 캐시한 `ContinuousClock` 시점.
    public let receivedAt: ContinuousClock.Instant
}

extension PDTComparisonSnapshot {
    static func from(_ response: PDTComparisonResponse, channelId: String, receivedAt: ContinuousClock.Instant) -> PDTComparisonSnapshot? {
        guard response.success else { return nil }
        let cmp = response.comparison
        let meta = response.metadata
        let nowMs = meta?.serverTimeMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        let webAge: Int64? = (meta?.webLastUpdated).map { nowMs - $0 }
        let appAge: Int64? = (meta?.appLastUpdated).map { nowMs - $0 }
        return PDTComparisonSnapshot(
            channelId: channelId,
            driftMs: cmp?.driftMs,
            webLatencyMs: cmp?.webLatencyMs,
            appLatencyMs: cmp?.appLatencyMs,
            syncPrecision: cmp?.syncPrecision,
            webHasPdt: meta?.webHasPdt ?? false,
            appHasPdt: meta?.appHasPdt ?? false,
            webAgeMs: webAge,
            appAgeMs: appAge,
            isPrecisionEligible: response.isPrecisionEligible(now: nowMs),
            receivedAt: receivedAt
        )
    }
}

/// `/api/sync/pdt-comparison/{channelId}` 폴링 클라이언트.
///
/// 한 번에 하나의 채널만 폴링한다. 채널이 바뀌면 기존 폴링은 자동 취소.
/// 응답을 직접 소비하려면 `latestSample()` 또는 `samples()` (AsyncStream) 사용.
public actor WebLatencyClient {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// 폴링 간격. 문서 §4.3 권장(1~2초). 기본 1.5s.
        public var pollInterval: Duration
        /// 5초 이상 오래된 샘플은 stale — `isPrecisionEligible == false` 가 된다.
        public var staleThresholdMs: Int64
        /// 네트워크 실패 후 재시도 간격(지수 백오프 상한).
        public var maxBackoff: Duration

        public static let `default` = Configuration(
            pollInterval: .milliseconds(1500),
            staleThresholdMs: 5_000,
            maxBackoff: .seconds(10)
        )

        public init(pollInterval: Duration, staleThresholdMs: Int64, maxBackoff: Duration) {
            self.pollInterval = pollInterval
            self.staleThresholdMs = staleThresholdMs
            self.maxBackoff = maxBackoff
        }
    }

    // MARK: - Stored state

    private let apiClient: MetricsAPIClient
    private var configuration: Configuration
    private var pollTask: Task<Void, Never>?
    private var activeChannelId: String?
    private var latest: PDTComparisonSnapshot?
    private var continuations: [UUID: AsyncStream<PDTComparisonSnapshot>.Continuation] = [:]

    private let clock = ContinuousClock()

    // MARK: - Init

    public init(apiClient: MetricsAPIClient, configuration: Configuration = .default) {
        self.apiClient = apiClient
        self.configuration = configuration
    }

    // MARK: - Public API

    /// 폴링 대상 채널을 설정한다. nil 이면 폴링 중지.
    /// 같은 채널을 다시 지정해도 재시작하지 않는다.
    public func setChannel(_ channelId: String?) {
        if channelId == activeChannelId { return }
        pollTask?.cancel()
        pollTask = nil
        latest = nil
        activeChannelId = channelId
        guard let id = channelId else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop(channelId: id)
        }
    }

    /// 현재 활성 채널 ID.
    public var currentChannelId: String? { activeChannelId }

    /// 가장 최근 수신된 스냅샷. 없거나 stale 일 수 있으므로 호출 측이
    /// `isPrecisionEligible` / `receivedAt` 을 함께 검사해야 한다.
    public func latestSample() -> PDTComparisonSnapshot? { latest }

    /// 새 스냅샷이 도착할 때마다 yield 하는 AsyncStream.
    /// 호출 측이 stream 을 끝까지 소비하지 않으면 자동 정리된다.
    public func samples() -> AsyncStream<PDTComparisonSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in await self?.removeContinuation(id) }
            }
        }
    }

    /// 폴링 설정 갱신 — 즉시 적용된다(다음 sleep 부터).
    public func updateConfiguration(_ config: Configuration) {
        configuration = config
    }

    // MARK: - Private

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit(_ snapshot: PDTComparisonSnapshot) {
        latest = snapshot
        for cont in continuations.values {
            cont.yield(snapshot)
        }
    }

    private func pollLoop(channelId: String) async {
        var backoff = configuration.pollInterval
        while !Task.isCancelled {
            // 채널이 도중에 바뀌면 즉시 종료
            if activeChannelId != channelId { return }
            do {
                let response = try await apiClient.pdtComparison(channelId: channelId)
                if let snapshot = PDTComparisonSnapshot.from(
                    response,
                    channelId: channelId,
                    receivedAt: clock.now
                ) {
                    emit(snapshot)
                }
                backoff = configuration.pollInterval
            } catch is CancellationError {
                return
            } catch {
                // 일시적 실패 — 조용히 백오프. (호출 측이 알 필요 없음)
                backoff = min(configuration.maxBackoff, backoff * 2)
            }
            try? await Task.sleep(for: backoff)
        }
    }
}
