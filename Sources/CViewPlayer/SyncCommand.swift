// MARK: - SyncCommand.swift
// [P1-2 / 2026-04-25]
// docs/chzzk-browser-sync-latency-research-swift6-2026-04-25.md §9·§12
//
// PDT 정밀 동기화 제어 루프의 출력 단을 값 타입(`SyncCommand`)과 actuator
// 프로토콜(`PlaybackActuator`)로 분리하기 위한 정의.
//
// 도입 의도:
// - 현재 `LowLatencyController` 는 결정 결과를 3개의 분리된 콜백
//   (`onRateChange`, `onSeekRequired`, `onWebSyncSnap`) 으로 노출하고 있어
//   엔진별 actuator(VLC / AVPlayer / HLSJS) 가 어떤 명령이 들어왔는지
//   3곳에서 분기 추적해야 한다.
// - `SyncCommand` 는 단일 case 합성으로 명령 의미를 일원화하고,
//   `PlaybackActuator` 는 엔진별 적용 차이를 흡수하는 프로토콜이다.
//
// **하위 호환**: 본 도입은 추가-only 다.
// - 기존 콜백 경로는 그대로 동작한다.
// - actuator 가 등록된 경우에 한해 동일 결정에 대해 명령이 추가 발행된다.
// - 점진 마이그레이션을 거쳐 향후 콜백 경로를 정리할 수 있다.

import Foundation

/// 동기화 결정 결과를 표현하는 값 타입.
///
/// 의미:
/// - `.hold`           : 샘플 신뢰 불가 / 락 상태. rate 강제 1.0 + seek 금지.
/// - `.rate(Double)`   : 재생 속도만 변경 (1.0 포함, 1.0 이면 lock).
/// - `.snap(toDriftMs:)`: PDT 기반 정밀 seek. 양수=앱이 웹보다 뒤짐 → 앞으로 이동.
/// - `.fallbackSeek(targetSeconds:)`: PDT 비활성/미등록 시 절대 시간 기준 seek.
public enum SyncCommand: Sendable, Equatable {
    case hold(reason: String)
    case rate(Double)
    case snap(toDriftMs: Double)
    case fallbackSeek(targetSeconds: TimeInterval)
}

/// 엔진별(또는 테스트용) 동기화 명령 적용기.
///
/// 단일 메서드 프로토콜이며 actor / @MainActor 에서 모두 채택 가능.
/// `apply(_:)` 가 throw 하지 않는 이유는 동기화 루프가 실패를 무시하고 다음
/// 샘플에서 재시도해야 하기 때문이다(루프 자체가 실패 복구 메커니즘).
public protocol PlaybackActuator: Sendable {
    func apply(_ command: SyncCommand) async
}
