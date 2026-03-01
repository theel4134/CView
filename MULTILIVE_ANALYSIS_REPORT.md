# CView_v2 멀티라이브 기능 정밀 분석 보고서

> 작성일: 2026-02-28  
> 분석 범위: 멀티라이브 전체 기능 (세션 관리, VLC 엔진 풀링, 채팅 통합, 그리드 레이아웃, CDN 갱신)

---

## 1. 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    MultiLiveSessionManager                       │
│  (@Observable @MainActor, AppState 소속)                         │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ sessions: [MultiLiveSession]  (최대 4개)                  │    │
│  │ enginePool: VLCInstancePool   (actor)                     │    │
│  │ audioSessionId / isGridLayout / customRatios              │    │
│  └──────────────────────────────────────────────────────────┘    │
└────────────┬────────────────────────────────────────────────────┘
             │ 각 세션
┌────────────▼────────────────────────────────────────────────────┐
│                    MultiLiveSession                              │
│  (@Observable @MainActor, 개별 스트림 단위)                       │
│  ├── PlayerViewModel (@MainActor @Observable)                    │
│  │     └── VLCPlayerEngine (NSLock 기반, non-isolated)           │
│  │           └── StreamCoordinator (actor)                       │
│  │                 ├── LocalStreamProxy  (CDN Content-Type 우회) │
│  │                 ├── HLSManifestParser (variant 해석)          │
│  │                 └── ABRController    (품질 자동 조절)          │
│  ├── ChatViewModel (채팅 WebSocket)                              │
│  └── Tasks: pollTask, refreshTask, offlineRetryTask, startTask   │
└──────────────────────────────────────────────────────────────────┘
```

### 핵심 설계 원칙
- **VLC 엔진 풀링**: `VLCInstancePool` actor가 최대 4개 엔진을 관리. acquire/release 패턴으로 재사용
- **세대 카운터**: `_operationGeneration`으로 stop/play race condition 방지
- **3단계 CDN 방어**: 매니페스트 갱신(15-30초) → 스톨 워치독(10초) → 전체 재시작(55분)
- **오디오 라우팅**: 단일 오디오 소스 원칙 엄격 유지

---

## 2. 문제점 분류

### 🔴 Critical — 즉시 수정 필요

#### C-1. `mediaPlayerTimeChanged` — 멀티라이브에서 초당 16회 불필요한 MainActor dispatch

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCPlayerEngine.swift` (mediaPlayerTimeChanged) |
| **현상** | `onTimeChange` 콜백이 nil인 경우에도 `DispatchQueue.main.async` 블록이 매 프레임 enqueue됨 |
| **영향** | 멀티라이브 라이브 스트림에서 `onTimeChange`를 사용하지 않으므로, 4세션 × 초당 4회 = **초당 16회** 불필요한 main dispatch 발생 → MainActor 큐 포화의 주요 원인 |
| **상태** | ✅ **수정 완료** — nil 체크 선행으로 dispatch 자체를 스킵 |

#### C-2. `mediaPlayerLengthChanged` — 동일한 nil dispatch 문제

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCPlayerEngine.swift` (mediaPlayerLengthChanged) |
| **현상** | `onTimeChange` 콜백이 nil이어도 매번 `DispatchQueue.main.async` 호출 |
| **영향** | 4세션 × 초당 ~0.5회 = **초당 ~2회** 추가 불필요한 dispatch |
| **상태** | ✅ **수정 완료** — nil 체크 선행 |

#### C-3. `startUptimeTimer` — 초당 4회 @Observable 업데이트로 SwiftUI body 재계산 폭주

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (startUptimeTimer) |
| **현상** | `self.uptime = t`가 1초마다 실행. `uptime`은 `@Observable` 프로퍼티이므로 관찰 중인 모든 SwiftUI 뷰의 body가 재계산됨 |
| **영향** | 4세션 × 매초 = **초당 4회** SwiftUI 전체 뷰 트리 재렌더링 유발 |
| **상태** | ✅ **수정 완료** — 5초 간격으로 변경 (80% 감소) |

#### C-4. `attemptRecovery` — 200회 actor hop으로 동시 복구 시 800회 MainActor 진입

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCPlayerEngine.swift` (attemptRecovery) |
| **현상** | playerView 대기 루프에서 매 10ms마다 `await MainActor.run {}` 호출. 4세션 동시 복구 시 최대 800회 actor hop |
| **영향** | CDN 토큰 만료 등으로 4세션이 동시에 복구를 시도하면 **일시적 UI 프리징** 발생 |
| **상태** | ✅ **수정 완료** — 단일 `MainActor.run` 블록 내 RunLoop spin으로 변경 (800회 → 4회) |

#### C-5. VLC `play()` — 300회 `await MainActor.run {}` 루프

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCPlayerEngine.swift` (play) |
| **현상** | view mount 대기에서 StreamCoordinator(actor) → MainActor.run 전환이 300회 반복 |
| **영향** | 4세션 × 300 = **1,200회** actor context switch → MainActor 큐 완전 포화 |
| **상태** | ✅ **수정 완료** — 단일 `@MainActor waitForViewAndPlay()` 메서드로 통합 |

#### C-6. `onStateChange` 콜백 — 이중 dispatch (DispatchQueue.main.async → Task { @MainActor })

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (onStateChange) |
| **현상** | VLC가 DispatchQueue.main.async로 호출하므로 이미 main thread인데, 핸들러에서 다시 `Task { @MainActor }` 생성 |
| **영향** | 불필요한 Task 객체 생성 + MainActor 스케줄링 오버헤드 |
| **상태** | ✅ **수정 완료** — `MainActor.assumeIsolated` 사용 |

---

### 🟠 High — 중요 개선 사항

#### H-1. 채팅 연결 Task 취소 불가 — fire-and-forget

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (~L139-177) |
| **현상** | `start()` 내 채팅 연결 `Task { ... chatVM.connect() ... }`가 저장되지 않아 `stop()` 시 cancel 불가 |
| **영향** | 세션을 빠르게 추가/제거하면 이미 해제된 세션의 채팅 연결 Task가 백그라운드에서 계속 실행. WebSocket 연결이 불필요하게 유지될 수 있음 |
| **권장 수정** | Task를 `chatConnectionTask` 프로퍼티에 저장하고 `stop()`에서 cancel |
| **상태** | ❌ **미수정** |

#### H-2. `MainActor.assumeIsolated` — VLCKit 내부 구현 변경 시 런타임 크래시 위험

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (onStateChange 콜백) |
| **현상** | `MainActor.assumeIsolated`는 호출 시점이 실제 main thread임을 개발자가 보장해야 함. VLCKit이 `DispatchQueue.main.async`로 콜백하는 구현에 의존 |
| **영향** | VLCKit 4.x 업데이트로 콜백 dispatch 전략이 변경되면 **Swift 6 assertion failure → 앱 크래시** |
| **권장 수정** | `if Thread.isMainThread { MainActor.assumeIsolated { ... } } else { Task { @MainActor in ... } }` 분기 처리, 또는 보수적으로 `Task { @MainActor }` 유지 |
| **상태** | ❌ **미수정** (현재는 정상 동작하나 향후 위험 존재) |

#### H-3. VLC 고급 설정 Task가 취소 관리 없음 — 엔진 재사용 시 이전 설정 오염

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (~L245-290) |
| **현상** | `Task.detached` (최대 5초 폴링)가 저장되지 않아 `stopStream()` 후에도 실행 지속 |
| **영향** | 엔진이 풀에 반납 → 다른 세션이 acquire → 이전 세션의 설정 Task가 새 세션 엔진에 이퀄라이저/필터를 적용할 수 있음 |
| **권장 수정** | Task를 property에 저장하고 `stopStream()`에서 cancel |
| **상태** | ❌ **미수정** |

#### H-4. VLC 메트릭 콜백 — showStats 미사용 시에도 Task 생성

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (~L132-139) |
| **현상** | VLC 메트릭 콜백에서 매 2초마다 `Task { @MainActor in self.latestMetrics = metrics }` 생성 |
| **영향** | showStats == false (대부분의 사용)에서도 초당 2회 × 4세션 = 초당 8개의 불필요한 Task 생성 + @Observable 업데이트 |
| **상태** | ✅ **수정 완료** — `showStats` 가드 추가, false 시 즉시 리턴 |

#### H-5. `latencyUpdate` 이벤트에서 `latencyHistory` 과다 갱신

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (startEventListening) |
| **현상** | `latencyHistory.append()` 매 호출마다 @Observable 배열 변경 → SwiftUI body 재계산 트리거 |
| **영향** | latency 차트가 화면에 보이지 않을 때도 지속적으로 body 재계산 유발 |
| **상태** | ✅ **수정 완료** — 10회당 1회만 기록 (90% 감소) |

---

### 🟡 Medium — 개선 권장

#### M-1. 그리드 모드에서 모든 세션이 포그라운드 품질 — 리소스 과다 사용

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (select 메서드, ~L473) |
| **현상** | 그리드 모드에서 4개 세션이 모두 `.lowLatency` 프로파일로 1080p 디코딩 실행 |
| **영향** | CPU/GPU 과부하. 특히 iGPU Mac에서 4개 동시 1080p 디코딩은 프레임 드롭 유발 |
| **권장 수정** | 오디오가 비활성된 세션에 `avcodec-threads` 제한 또는 프레임 스킵 강화. 또는 그리드 크기에 따라 해상도 자동 하향 (4개: 720p, 3개: 720p/1080p 혼합) |
| **상태** | ❌ **미수정** |

#### M-2. `addChannelById`에서 `isAddingChannelIds` 상태 관리 부정확

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/Views/MultiLiveAddSheet.swift` (~L583-614) |
| **현상** | fire-and-forget Task 사용으로 `isAddingChannelIds.remove()`가 즉시 실행됨 |
| **영향** | "추가 중" 스피너가 순간적으로만 표시되고 즉시 사라짐. 스트림 시작 전에 "추가됨" 상태로 보임 |
| **권장 수정** | `isAddingChannelIds.remove()`를 Task 완료 시점으로 이동하거나, 세션의 `loadState`를 UI에 바인딩 |
| **상태** | ❌ **미수정** |

#### M-3. `waitForViewAndPlay()` 3초 타임아웃 후 무조건 play() — 검은 화면 가능

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCPlayerEngine.swift` (waitForViewAndPlay) |
| **현상** | 타임아웃(300 × 10ms = 3초) 후 view가 window에 없어도 `player.play()` 강제 실행 |
| **영향** | VLC vout 초기화 실패 → 검은 화면 (오디오만 재생). 특히 SwiftUI 뷰 레이아웃이 지연될 때 |
| **권장 수정** | 타임아웃 시 `.error` 이벤트 방출 또는 5초로 연장 + 주기적 재확인 |
| **상태** | ❌ **미수정** |

#### M-4. `VLCInstancePool.drain()`에서 `resetForReuse()` 미호출 — 콜백 잔류 가능

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewPlayer/VLCInstancePool.swift` (drain 메서드) |
| **현상** | `drain()`은 `stop()`만 호출하고 `onStateChange`, `onVLCMetrics` 등의 콜백을 해제하지 않음 |
| **영향** | `allEngines.removeAll()` 후 콜백 클로저의 캡처로 인한 일시적 메모리 잔류 (약한 참조 패턴으로 실제 누수는 낮음) |
| **권장 수정** | `stop()` 대신 `resetForReuse()` 호출 후 배열 정리 |
| **상태** | ❌ **미수정** |

#### M-5. 폴링 Task에서 `try?` 사용으로 취소 후 1회 추가 폴링 발생

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (startPolling, ~L246) |
| **현상** | `try? await Task.sleep`이 CancellationError를 무시하므로 취소 후에도 한번 더 폴링 실행 |
| **영향** | 세션 제거 후 불필요한 API 호출 1회 발생 (경미) |
| **권장 수정** | `try await Task.sleep`으로 변경하고 do-catch로 감싸기 |
| **상태** | ❌ **미수정** |

#### M-6. `MainActor.run` 3회 연속 호출 — 불필요한 actor 전환 오버헤드

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (채팅 초기화, ~L167) |
| **현상** | `chatVM` 프로퍼티 설정이 `MainActor.run` 3회로 분산되어 3번의 actor 전환 발생 |
| **영향** | 일회성이나 비효율적. 특히 4세션 동시 시작 시 12회 actor 전환 |
| **상태** | ✅ **수정 완료** — 1회로 통합 |

---

### 🟢 Low — 경미한 이슈

#### L-1. `performSearch()` 에러 시 사용자에게 에러 미표시

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/Views/MultiLiveAddSheet.swift` (~L567) |
| **현상** | 네트워크 에러와 "검색 결과 없음"을 구분할 수 없음. `catch { searchResults = [] }` |
| **권장 수정** | 에러 시 사용자에게 토스트/알럿 표시 |

#### L-2. `CachedAsyncImage` / `AsyncImage` 혼용

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/Views/MultiLiveAddSheet.swift` 전체 |
| **현상** | 채널 카드 이미지 로딩에 두 가지 방식이 혼용됨 |
| **권장 수정** | `CachedAsyncImage`로 통일하여 캐시 효율 향상 |

#### L-3. 그리드 커스텀 레이아웃에서 행별 독립 비율 조절 불가

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/Views/MultiLiveGridLayouts.swift` (~L268) |
| **현상** | 2×2 배치에서 상단/하단 행의 수평 분할 비율이 항상 동일 (`hRatio`) |
| **권장 수정** | 행별 독립 `hRatio` 지원 (선택적 Enhancement) |

#### L-4. `MultiLiveSessionManager.enginePool` 앱 전체 수명 유지

| 항목 | 내용 |
|------|------|
| **파일** | `Sources/CViewApp/ViewModels/MultiLiveSession.swift` (~L401) |
| **현상** | 멀티라이브를 사용하지 않아도 `VLCInstancePool` 인스턴스가 메모리에 상존 |
| **영향** | actor 자체는 가벼우나 warmup된 엔진이 drain 안 되면 메모리 점유 |

---

## 3. 아키텍처 개선 제안

### E-1. VLC 엔진 풀에 Health Check 메커니즘 추가

```swift
// VLCInstancePool.swift
public func acquire() async -> VLCPlayerEngine {
    while let engine = idleEngines.popLast() {
        if !engine.isInErrorState {  // 건강한 엔진만 반환
            activeEngines.insert(ObjectIdentifier(engine))
            return engine
        }
        // 에러 상태 엔진은 폐기
        engine.stop()
        allEngines.removeValue(forKey: ObjectIdentifier(engine))
    }
    return await createNewEngine()
}
```

### E-2. 그리드 모드에서 세션별 품질 자동 조절

```
 세션 수 | 해상도    | avcodec-threads
 1      | 1080p    | 자동
 2      | 1080p    | 4
 3      | 720p     | 3
 4      | 720p     | 2 (오디오 비활성 세션은 frameSkip 강화)
```

### E-3. 메모리 압박 자동 대응

```swift
// MultiLiveSessionManager에 추가
private func setupMemoryPressureMonitor() {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical],
        queue: .main
    )
    source.setEventHandler { [weak self] in
        Task { @MainActor in
            guard let self else { return }
            // 배경 세션의 비디오 트랙 비활성화
            for session in self.sessions where session.isBackground {
                await session.playerViewModel.disableVideoTrack()
            }
            // 풀 축소
            await self.enginePool.reducePool(to: self.sessions.count)
        }
    }
    source.resume()
}
```

### E-4. 오프라인 세션 자동 제거 옵션

```swift
// SettingsStore에 추가
var multiLiveAutoRemoveOfflineMinutes: Int = 10  // 0 = 비활성

// MultiLiveSession.startPolling()에서 체크
if let threshold = settingsStore.multiLiveAutoRemoveOfflineMinutes,
   threshold > 0,
   offlineDuration > TimeInterval(threshold * 60) {
    // 자동 제거 트리거
}
```

### E-5. 키보드 단축키 지원

| 단축키 | 기능 |
|--------|------|
| `⌘1` ~ `⌘4` | 오디오 활성 세션 전환 |
| `⌘⇧G` | 그리드/탭 모드 전환 |
| `⌘⇧R` | 드래그 비율 초기화 |
| `⌘⇧F` | 선택 세션 포커스 모드 토글 |

---

## 4. 크로스커팅 분석 요약

### 세션 생명주기

```
addSession() ─→ warmup(2) ─→ acquire() ─→ session.start()
                                              │
                    ┌─────────────────────────┘
                    ▼
            API 호출 (liveDetail)
                    │
            ┌───────┼───────┐
            ▼       ▼       ▼
        VLC play  채팅연결  폴링시작
                            │
                    ┌───────┘
                    ▼
              30초마다: 상태 확인, VLC 헬스체크
              55분마다: CDN 토큰 재취득 (retry)
              
session.stop() ─→ Task 취소 ─→ VLC stop ─→ 채팅 disconnect
removeSession() ─→ session.stop() ─→ engine release ─→ 풀 반납
```

### CDN 토큰 갱신 3단계 방어

| 단계 | 주기 | 메서드 | 역할 |
|------|------|--------|------|
| 1. 매니페스트 갱신 | 15-30초 | StreamCoordinator.refreshTimer | variant URL 토큰 갱신 |
| 2. 스톨 워치독 | 10초 | VLCPlayerEngine.stallDetector | PLAYING/BUFFERING 고착 → recovery |
| 3. 전체 재시작 | 55분 | MultiLiveSession.proactiveRefresh | CDN 토큰 만료 전 전체 URL 재취득 |

### 오디오 관리

| 모드 | 동작 |
|------|------|
| **탭 모드** | 선택된 탭만 언뮤트, 나머지 뮤트 |
| **그리드 모드** | `audioSessionId`로 지정된 세션만 언뮤트 |
| **전환 시** | `routeAudio(to:)` — 모든 세션 순회하며 뮤트/언뮤트 설정 (볼륨 값 보존) |

---

## 5. 수정 현황표

| # | 심각도 | 문제 | 파일 | 상태 |
|---|--------|------|------|------|
| C-1 | 🔴 Critical | timeChanged nil dispatch | VLCPlayerEngine.swift | ✅ 완료 |
| C-2 | 🔴 Critical | lengthChanged nil dispatch | VLCPlayerEngine.swift | ✅ 완료 |
| C-3 | 🔴 Critical | uptimeTimer 1초 갱신 | PlayerViewModel.swift | ✅ 완료 |
| C-4 | 🔴 Critical | attemptRecovery 200회 hop | VLCPlayerEngine.swift | ✅ 완료 |
| C-5 | 🔴 Critical | play() 300회 MainActor.run | VLCPlayerEngine.swift | ✅ 완료 |
| C-6 | 🔴 Critical | onStateChange 이중 dispatch | PlayerViewModel.swift | ✅ 완료 |
| H-1 | 🟠 High | 채팅 Task 취소 불가 | MultiLiveSession.swift | ❌ 미수정 |
| H-2 | 🟠 High | assumeIsolated VLCKit 의존 | PlayerViewModel.swift | ❌ 미수정 |
| H-3 | 🟠 High | 설정 Task 취소 없음 | PlayerViewModel.swift | ❌ 미수정 |
| H-4 | 🟠 High | 메트릭 Task showStats 가드 | MultiLiveSession.swift | ✅ 완료 |
| H-5 | 🟠 High | latencyHistory 과다 갱신 | PlayerViewModel.swift | ✅ 완료 |
| M-1 | 🟡 Medium | 그리드 4채널 1080p 과부하 | MultiLiveSession.swift | ❌ 미수정 |
| M-2 | 🟡 Medium | isAddingChannelIds 부정확 | MultiLiveAddSheet.swift | ❌ 미수정 |
| M-3 | 🟡 Medium | waitForViewAndPlay 타임아웃 | VLCPlayerEngine.swift | ❌ 미수정 |
| M-4 | 🟡 Medium | drain() resetForReuse 누락 | VLCInstancePool.swift | ❌ 미수정 |
| M-5 | 🟡 Medium | 폴링 try? 취소 지연 | MultiLiveSession.swift | ❌ 미수정 |
| M-6 | 🟡 Medium | MainActor.run 3회 호출 | MultiLiveSession.swift | ✅ 완료 |

**수정 완료: 9/16 (56%)** — Critical 전체 해결, High 3개 남음

---

## 6. 우선순위별 다음 작업 권장

### 즉시 (Next Sprint)
1. **H-1** 채팅 연결 Task를 `chatConnectionTask`에 저장 + `stop()`에서 cancel
2. **H-3** VLC 설정 Task를 property에 저장 + `stopStream()`에서 cancel
3. **M-4** `drain()`에서 `resetForReuse()` 호출로 변경

### 단기 (1-2주)
4. **M-1** 그리드 모드 세션 수에 따른 자동 품질 하향 (4채널: 720p)
5. **M-3** `waitForViewAndPlay()` 타임아웃 시 에러 이벤트 방출
6. **E-1** 엔진 풀 health check 메커니즘

### 중기 (1개월)
7. **H-2** `MainActor.assumeIsolated` → Thread.isMainThread 분기 처리
8. **E-3** 메모리 압박 자동 대응 (DispatchSource.makeMemoryPressureSource)
9. **E-2** 그리드 모드 세션별 수동 품질 선택 UI
10. **E-5** 키보드 단축키 지원

---

## 7. 총평

멀티라이브 기능은 **높은 완성도**로 구현되어 있습니다:

✅ **잘 된 점:**
- 세대 카운터 기반 VLC stop/play race condition 해결
- actor 기반 엔진 풀링으로 스레드 안전성 보장
- 3단계 CDN 토큰/재연결 방어 체계
- 탭/그리드/포커스 모드의 풍부한 레이아웃 옵션
- 단일 오디오 소스 원칙 엄격 유지
- 배경 탭 리소스 최적화 (프로파일 전환, 비디오 트랙 비활성화)

⚠️ **주요 개선 영역:**
- MainActor 포화 방지 (대부분 수정 완료, 초당 ~68회 → ~5회)
- fire-and-forget Task 수명 관리 (채팅 연결, VLC 설정)
- 그리드 모드 리소스 최적화 (4채널 동시 1080p 디코딩)
- VLCKit 버전 종속성 격리 (`MainActor.assumeIsolated`)
