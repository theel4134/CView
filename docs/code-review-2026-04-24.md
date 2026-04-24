# CView_v2 전체 코드 리뷰

**날짜**: 2026-04-24
**검토 범위**: 전체 소스 (AppState, ChatViewModel, PlayerViewModel, MultiLiveManager, AppRouter, ServiceContainer, AppDependencies, AppLifecycle, AppState+Auth, AppError 등)

---

## 총평

전반적으로 Swift 6 Concurrency를 올바르게 적용한 고품질 코드베이스입니다. 모듈 분리, 성능 최적화, 방어적 프로그래밍이 잘 이루어져 있습니다. 아래는 개선이 필요한 구체적인 사항들입니다.

---

## 강점

### 1. Swift 6 Concurrency 준수
`@Observable`, `@MainActor`, actor isolation, `Sendable`, `nonisolated` 사용이 일관적으로 올바릅니다. Swift 6 strict concurrency를 실제로 지키는 코드베이스는 흔하지 않습니다.

### 2. 모듈 의존성 그래프가 명확함
`CViewCore` → 상위 모듈들의 단방향 흐름, 순환 의존성 없음.

```
CViewCore → CViewNetworking → CViewAuth
                            → CViewChat
                            → CViewPlayer (+ VLCKitSPM)
                            → CViewUI
                            → CViewMonitoring
                            → CViewPersistence
모두 → CViewApp (executable)
```

### 3. 성능 최적화가 정교함
- `ChatMessageBuffer` 링 버퍼로 O(1) append/eviction
- 적응형 drip flush (33ms/66ms/100ms burst multiplier)
- `@ObservationIgnored`로 고빈도 변경 속성의 SwiftUI 추적 차단
- `PowerAwareInterval` / `PowerAwareTaskPriority` 배터리 인식 스케줄링
- GPU render tier (active/visible/hidden) 창 가림 시 Metal 합성 정지

### 4. 방어적 멀티라이브 세션 관리
`addingChannelIds`, `removingSessionIds` 가드 셋으로 concurrent 중복 추가/제거 방지. `await` 이후 상태 재확인 패턴(ISSUE-4 fix)이 일관적.

### 5. 에러 타입 계층 구조
`AppError → NetworkError / APIError / AuthError / ChatError / PersistenceError / PlayerError` 계층이 `LocalizedError` 준수와 함께 잘 설계됨.

### 6. Extension 기반 책임 분리
`AppState` 본체는 상태 컨테이너 역할에 집중하고, `AppState+Auth`, `AppState+Metrics`, `AppLifecycle`, `AppDependencies`로 책임이 명확히 분리됨.

---

## 개선 필요 사항

### [Critical] 1. Dead Code: `feedMetricsToCoordinator()`

**파일**: `Sources/CViewApp/ViewModels/MultiLiveManager.swift:897-949`

`feedMetricsToCoordinator()`는 `private` 메서드이지만 어디서도 호출되지 않습니다.
`startBandwidthCoordination()` 내부에서 `collectMetricsSnapshot()` 방식으로 대체되었으나 이전 코드가 제거되지 않았습니다. 52줄의 dead code입니다.

```swift
// 제거 대상
private func feedMetricsToCoordinator() { ... } // L897-949
```

---

### [High] 2. `ServiceContainer.require()`가 Optional 반환

**파일**: `Sources/CViewCore/DI/ServiceContainer.swift:48`

메서드 이름이 `require`임에도 `T?`를 반환합니다. "필수" 의미와 반환 타입이 모순이며, 호출자가 여전히 옵셔널을 처리해야 합니다.

```swift
// 현재 (잘못된 계약)
public func require<T: Sendable>(_ type: T.Type, ...) -> T?

// 개선안 A: resolve와 동일하게 유지, 명칭 변경
public func resolveAsserted<T: Sendable>(_ type: T.Type) -> T?

// 개선안 B: 실패 시 throw
public func require<T: Sendable>(_ type: T.Type) throws -> T
```

---

### [High] 3. 에코 필터링에 `hashValue` 사용

**파일**: `Sources/CViewApp/ViewModels/ChatViewModel.swift:439`

```swift
// 현재
let echoKey = "\(localMessage.userId)_\(localMessage.content.hashValue)"
```

`hashValue`는 해시 충돌 가능성이 있어 다른 사용자의 정상 메시지가 잘못 필터링될 수 있습니다.
내용이 완전히 다른 두 메시지가 같은 해시를 가질 수 있습니다.

```swift
// 개선안: content 직접 사용
let echoKey = "\(localMessage.userId)_\(localMessage.content)"
```

---

### [High] 4. `updateEstimatedPaneSizes()` 스크린 해상도 하드코딩

**파일**: `Sources/CViewApp/ViewModels/MultiLiveManager.swift:958-959`

```swift
// 현재
let screenW = 1920 // 기본 추정
let screenH = 1080
```

4K/Retina 디스플레이에서 대역폭 코디네이터의 패인 크기 추정이 부정확합니다.

```swift
// 개선안
let screenSize = NSApp.mainWindow?.frame.size
    ?? NSScreen.main?.frame.size
    ?? CGSize(width: 1920, height: 1080)
let screenW = Int(screenSize.width)
let screenH = Int(screenSize.height)
```

---

### [Medium] 5. Observer 목록 하드코딩 — 누락 위험

**파일**: `Sources/CViewApp/AppLifecycle.swift:137-151`

`removeAllObservers()`에 옵저버를 배열로 나열하는 방식은 새 옵저버 추가 시 정리 목록에서 빠뜨리기 쉽습니다.

```swift
// 현재 — 새 옵저버 추가 시 이 목록도 함께 수정해야 함 (누락 위험)
[appActiveObserver, appResignObserver, sessionExpiryObserver, ...].compactMap { $0 }.forEach { ... }

// 개선안: 등록 시점에 배열로 누적
private var lifecycleObservers: [NSObjectProtocol] = []

// 등록 시
let obs = nc.addObserver(forName: ..., object: nil, queue: .main) { ... }
lifecycleObservers.append(obs)

// 해제 시
lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
lifecycleObservers.removeAll()
```

---

### [Medium] 6. `restartMultiLiveSessionsForProxyChange()` 순차 재시작

**파일**: `Sources/CViewApp/AppLifecycle.swift:159-169`

```swift
// 현재 — 4세션 × 2~5초 = 최대 20초 순차 대기
for session in targets {
    await session.refreshStream(using: api, appState: self)
}
```

각 `refreshStream`이 네트워크 요청을 포함하므로 세션이 많을수록 지연이 선형 증가합니다.

```swift
// 개선안: TaskGroup으로 병렬화
await withTaskGroup(of: Void.self) { group in
    for session in targets {
        group.addTask { await session.refreshStream(using: api, appState: self) }
    }
}
```

---

### [Medium] 7. `PlayerViewModel` 엔진 타입캐스트 남발

**파일**: `Sources/CViewApp/ViewModels/PlayerViewModel.swift` 전반

`as? VLCPlayerEngine`, `as? AVPlayerEngine`, `as? HLSJSPlayerEngine` 패턴이 파일 전체에 7번 이상 반복됩니다.
이는 `PlayerEngineProtocol`에 누락된 메서드가 있다는 신호입니다.

```swift
// PlayerEngineProtocol에 추가 검토 대상:
protocol PlayerEngineProtocol {
    func setGPURenderTier(_ tier: SessionTier)      // 현재 누락
    var forceHighestQuality: Bool { get set }        // 현재 누락
    func nudgeQualityCeiling(reason: String)         // 현재 누락
    func setSharpPixelScaling(_ enabled: Bool)       // 현재 누락
    // ...
}
```

프로토콜을 통해 디스패치하면 대부분의 `as?` 캐스트를 제거할 수 있습니다.

---

### [Medium] 8. 초기화 순서를 `sleep` magic number로 조율

**파일**: `Sources/CViewApp/AppDependencies.swift:59-97`

```swift
try? await Task.sleep(for: .milliseconds(300))  // metrics 연결
try? await Task.sleep(for: .milliseconds(100))  // DataStore 초기화
try? await Task.sleep(for: .milliseconds(200))  // auth 초기화
try? await Task.sleep(for: .milliseconds(500))  // emoticons 프리로드
```

특정 작업이 sleep 시간보다 오래 걸리면 순서가 깨집니다.
명시적 `await` 의존 체인이나 `withTaskGroup`으로 구성하면 더 안전합니다.

---

### [Low] 9. `AppState` God Object

**파일**: `Sources/CViewApp/AppState.swift:16`

Extension으로 잘 분리되어 있으나 클래스 자체가 아래 항목을 모두 소유합니다:
- ViewModel 3개 (homeViewModel, chatViewModel, playerViewModel)
- 서비스 10개 이상 (apiClient, authManager, dataStore, metricsForwarder, ...)
- NSNotification 옵저버 8개
- 이모티콘 캐시
- UI 상태 (showCommandPalette, showKeyboardShortcutsHelp, showAboutPanel)

장기적으로 DI Container 활용 방향으로 개선하면 테스트 용이성이 크게 높아집니다.

---

### [Low] 10. `startStream()` 초장문 줄 포맷팅

**파일**: `Sources/CViewApp/ViewModels/PlayerViewModel.swift:521`

```swift
// 현재 — 약 220자의 단일 줄
let config = StreamCoordinator.Configuration(channelId: channelId, enableLowLatency: !isMultiLive, enableABR: true, lowLatencyConfig: lowLatencyConfig, abrConfig: isMultiLive ? .multiLive : .default, forceHighestQuality: forceMax, streamProxyMode: proxyMode)

// 개선안
let config = StreamCoordinator.Configuration(
    channelId: channelId,
    enableLowLatency: !isMultiLive,
    enableABR: true,
    lowLatencyConfig: lowLatencyConfig,
    abrConfig: isMultiLive ? .multiLive : .default,
    forceHighestQuality: forceMax,
    streamProxyMode: proxyMode
)
```

---

### [Low] 11. `ChatViewModel`의 불필요한 `public` 노출

**파일**: `Sources/CViewApp/ViewModels/ChatViewModel.swift` 전반

`ChatViewModel`이 앱 내부에서만 사용됨에도 거의 모든 속성이 `public`으로 선언됩니다.
라이브러리 모듈이 아니므로 `internal`(기본값)로 충분하며, 캡슐화가 강화됩니다.

---

## 요약표

| 우선순위 | 항목 | 파일 | 줄 |
|---------|------|------|-----|
| **Critical** | `feedMetricsToCoordinator()` dead code 제거 | MultiLiveManager.swift | :897 |
| **High** | `ServiceContainer.require()` 반환 타입 수정 | ServiceContainer.swift | :48 |
| **High** | echo 필터링에 `hashValue` → content 직접 사용 | ChatViewModel.swift | :439 |
| **High** | 패인 크기 추정에 실제 스크린 크기 사용 | MultiLiveManager.swift | :958 |
| **Medium** | Observer 목록 하드코딩 → 배열 누적 방식으로 | AppLifecycle.swift | :137 |
| **Medium** | 세션 재시작 순차 → TaskGroup 병렬화 | AppLifecycle.swift | :159 |
| **Medium** | 엔진 타입캐스트 → 프로토콜 메서드 추가 | PlayerViewModel.swift | 전반 |
| **Medium** | 초기화 순서 sleep → 명시적 await 의존 체인 | AppDependencies.swift | :59 |
| Low | AppState God Object 분리 | AppState.swift | — |
| Low | `startStream()` 초장문 줄 포맷팅 | PlayerViewModel.swift | :521 |
| Low | ChatViewModel public 노출 범위 축소 | ChatViewModel.swift | 전반 |
