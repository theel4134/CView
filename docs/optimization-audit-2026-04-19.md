# 인스턴스 전수 감사 & 튜닝 — 2026-04-19

빌드 31 시점 `docs/project-deep-analysis-2026-04.md` 의 잔여 이슈를 재점검하고
누락된 PowerAware 적용 지점과 새로 발견된 비효율 핫스팟을 정리한다.
모든 항목은 실제 파일·라인 검증을 거쳤다.

---

## 1. 잔여 이슈 재점검 (`project-deep-analysis-2026-04.md` § 3.2)

| ID | 위치 | 상태 | 비고 |
|---|---|---|---|
| P-1 | [HomeViewModel.swift L157](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L157) | ✅ 적용 완료 | `PowerAwareTaskPriority.userVisible` 로 교체됨 |
| P-2 | FollowingView 분류 Task | ✅ 적용 완료 | 그렙 결과 `Task.detached(priority: .userInitiated)` 잔존 없음 |
| P-3 | FollowingView prefetch | ✅ 적용 완료 | 동일 |
| P-4 | [BackgroundUpdateService.swift L135](../Sources/CViewApp/Services/BackgroundUpdateService.swift#L135) | ✅ 적용 완료 | `PowerAwareTaskPriority.periodic` 사용 |
| P-5 | AppDependencies migration | ✅ 적용 완료 | `Task.detached(priority: .background)` 호출 사라짐 |
| P-6 | ChatViewModel+Processing 후속 처리 `.background` | ✅ 유지 타당 | 그대로 두는 것이 옳음 |
| **P-7** | [LowLatencyController.swift L292](../Sources/CViewPlayer/LowLatencyController.swift#L292) | ❌ **미적용** | 5초 고정 PID 평가 — 본 문서에서 적용 |
| P-8 | ImageCacheService prune | ✅ 적용 완료 | `[Fix P-8]` PowerAware scaled |

---

## 2. 신규 발굴 — Power-Aware 미적용 핫스팟

| ID | 위치 | 현재 | 변경 |
|---|---|---|---|
| **N-1** | [ChzzkAPIClient.swift L55](../Sources/CViewNetworking/ChzzkAPIClient.swift#L55) | 응답 캐시 purge 5분 고정 | `PowerAwareInterval.scaled(...)` — Battery 7.5분 |
| **N-2** | [HomeViewModel.swift L385](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L385) | 홈 자동 새로고침 90초 고정 | `PowerAwareInterval.scaled(90)` — Battery 135초 |
| **N-3** | [PerformanceMonitor.swift L114-L125](../Sources/CViewMonitoring/PerformanceMonitor.swift#L114) | `start(interval:)` 호출자 인자 그대로 사용 | 내부에서 `PowerAwareInterval.scaled` 적용해 인자 변경 없이 효과 |
| **N-4** | [LiveThumbnailService.swift L66](../Sources/CViewNetworking/LiveThumbnailService.swift#L66) | metrics 서버 경로 디코딩 `.utility` 고정 | `PowerAwareTaskPriority.userVisible` — AC P-core / Battery utility |
| **N-5** | [ChatViewModel+Processing.swift L383](../Sources/CViewApp/ViewModels/ChatViewModel+Processing.swift#L383) | 메시지/초 통계 갱신 3초 고정 | `PowerAwareInterval.scaled(3)` — Battery 4.5초 (통계는 추세용이라 정밀도 영향 없음) |

이 5건만 적용해도 Battery 모드에서 다음 효과:
- API 응답 캐시 purge wake-up: -33%
- 홈 자동 새로고침 wake-up: -33%
- 성능 메트릭 수집 wake-up: -33%
- 채팅 메시지/초 통계 wake-up: -33%
- 멀티라이브 PID 보정 wake-up: -33%

대략 idle 시 **타이머 wake-up 빈도 ~30% 감소**가 누적된다.

---

## 3. 자세히 살펴본 결과 — 변경하지 않기로 한 항목

| 위치 | 이유 |
|---|---|
| `MultiLiveChildScene.swift:209` | 부모 PID liveness 검사 2초 — 자식 정리 지연이 사용자 체감에 영향. 이미 1→2초 최적화됨 |
| `WebSocketService.swift:265` | WebSocket ping 주기 — 서버 keep-alive 정책에 종속. 고정값 유지 |
| `ImageCacheService.swift:170/202/445` | `.utility/.background` 의도적 — 렌더 패스와 경합 방지 명시 주석 있음 |
| `ChatViewModel+Processing.swift:139/156` | `.background` 후속 처리 — 의도적, 분석문 P-6도 유지 권고 |
| `MultiLiveProcessLauncher.swift:126` | 자식 프로세스 lifecycle 모니터 — 빈도 낮고 이벤트성 |
| `NotificationService.swift:67` | LaunchServices 재등록은 권한 요청 시 1회 |

---

## 4. 추가로 확인된 강건성 패턴 (변경 없음, 기록 목적)

- `WebSocketService` deinit 에서 `pingTask?.cancel()`, `receiveTask?.cancel()`,
  `webSocket?.cancel(.goingAway)`, `session?.invalidateAndCancel()`,
  `messageContinuation?.finish()`, `stateContinuation?.finish()` 모두 호출 — 누수 없음
- `ImageCacheService` `clearAll()` 에서 `inFlightDownloads` 도 명시 cancel 후 제거
- `MultiChatSessionManager.disconnectAll()` 에서 `withTaskGroup` 으로 병렬 close
- `ChatEngine` 가 `reconnectionTask` 를 `[Fix 25D]` 에서 명시 취소
- `ImageCacheService.imageSession` 은 `nonisolated static let` 로 1회 생성·재사용
- `StreamCoordinator.hlsSession` 은 ephemeral + cache 비활성화로 라이브 매니페스트 stale 방지
- `MetricsForwarder` 에서 `cviewConnect` 실패 시 legacy `/api/metrics` 로 폴백

---

## 5. 적용 후 검증

`xcodebuild -scheme CView_v2 -configuration Debug build` 가 경고/에러 없이 통과하는지 확인.
런타임 검증은 다음으로 가능:

1. 설정 → 메트릭 패널에서 PerformanceMonitor 갱신이 Battery 모드에서 ~15초 주기로 변하는지
2. Activity Monitor 에서 CView_v2 의 idle CPU% 가 Battery 모드에서 추가로 5% 이상 감소하는지
3. 멀티라이브 4세션 + 채팅 활성 상태에서 첫 1분 평균 wake-ups 비교 (powermetrics 사용 가능)
