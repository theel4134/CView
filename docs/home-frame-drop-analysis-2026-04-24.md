# CView_v2 메인 홈 화면 프레임 드랍 정밀 분석 및 개선안

작성일: 2026-04-24  
분석 방식: 현재 체크아웃의 SwiftUI 코드 정적 분석  
범위: `HomeView_v2`, `HomeV2Components`, `HomeV2Effects`, `HomeThumbnailPrefetcher`, `MainContentView`, `CViewApp`, `HomeViewModel`, `LiveThumbnailView`, `CachedAsyncImage`

---

## 0. 결론

현재 메인 홈은 `home.useV2 = true`가 기본이며, 실제 홈 진입 경로는 `MainContentView -> HomeView_v2`다. v2 홈은 기존 대시보드형 `HomeView`보다 정보 구조가 좋아졌고, 프레임 드랍을 줄이기 위한 코드도 이미 여러 곳에 들어가 있다.

이미 적용된 좋은 완화책:

- 메뉴 전환 직후 글로벌 implicit spring 주입을 막는 `MenuTransitionGate`
- `HomeView_v2`의 sticky command bar와 `.refreshable` 제거
- 추천/룩업 결과 캐싱과 단일 signature 기반 onChange
- 홈 이미지/썸네일 prefetch
- `TimelineView` 제거, shadow radius 고정 등 홈 전용 효과 최적화

다만 메뉴 이동, 홈 진입, 홈에서 다른 메뉴로 이동할 때 프레임 드랍이 남을 수 있는 핵심 원인은 아직 있다.

| 우선순위 | 원인 | 증상 |
|---|---|---|
| P0 | `HomeView_v2.onAppear`가 뷰 마운트 직후 자동 갱신, 저장소 로드, 추천 재계산, prefetch를 동시에 시작 | 홈 진입 첫 1~2프레임 stutter |
| P0 | `HomeSectionAppear`는 명시적 `withAnimation`이라 `MenuTransitionGate`의 글로벌 transaction 차단을 우회 | 메뉴 전환 직후 섹션 6~7개가 stagger animation |
| P0 | 홈 카드마다 `LiveThumbnailView`가 45초 갱신 loop를 가진 task를 생성 | 카드 수가 늘수록 task/이미지 상태 갱신 증가 |
| P1 | `HomeThumbnailPrefetcher`가 detached prefetch를 취소/병합하지 않음 | 빠른 메뉴 이동/새로고침/데이터 변경 시 prefetch 중첩 |
| P1 | Hero/Recommended 카드 일부가 여전히 shadow radius를 hover 상태에 따라 바꿈 | hover 또는 메뉴 복귀 후 GPU blur 재계산 |
| P1 | Sidebar selection의 `matchedGeometryEffect`와 row animation이 detail mount와 동시에 실행 | 사이드바 클릭 순간 indicator animation + detail mount 충돌 |
| P2 | 성능 모니터의 `TimelineView(.animation)`은 표시 중 매 프레임 실행 | 모니터를 켠 상태에서 측정 자체가 부하를 만든다 |

따라서 개선 방향은 "더 빠른 애니메이션"이 아니라 **메뉴 전환 첫 프레임에 실행되는 일을 줄이고, explicit animation / image task / prefetch를 전환 안정화 이후로 미루는 것**이다.

---

## 1. 현재 홈 구현 구조

### 1.1 현재 기본 홈은 HomeView_v2

`MainContentView`는 `@AppStorage("home.useV2")`로 홈 v2 사용 여부를 결정하고, 기본값은 `true`다.

- [MainContentView.swift L20-L21](../Sources/CViewApp/Views/MainContentView.swift#L20-L21)
- [MainContentView.swift L96-L105](../Sources/CViewApp/Views/MainContentView.swift#L96-L105)
- [MainContentView.swift L150-L156](../Sources/CViewApp/Views/MainContentView.swift#L150-L156)

즉 현재 사용자가 보는 홈은 대부분 `Sources/CViewApp/Views/HomeV2/HomeView_v2.swift`다. 기존 `HomeView`는 fallback으로 남아 있다.

### 1.2 v2 홈의 화면 구성

`HomeView_v2`는 다음 정보 구조를 갖는다.

1. Sticky `HomeCommandBar`
2. 쿠키 로그인 배너
3. 활성 멀티라이브 strip
4. Hero live card
5. 팔로잉 라이브
6. 이어보기 / 즐겨찾기
7. 추천 그리드
8. 인기 채널
9. 접이식 간이 통계

근거:

- [HomeView_v2.swift L152-L248](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L152-L248)
- [HomeView_v2.swift L282-L324](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L282-L324)

기존 홈보다 사용 목적에는 더 맞지만, 한 화면에 카드/썸네일/펄스/그라디언트/추천 계산이 모두 존재한다. 그래서 메뉴 전환 순간에는 SwiftUI diff, layout, image task, explicit animation이 한꺼번에 겹치기 쉽다.

---

## 2. 이미 적용된 프레임 드랍 완화책

### 2.1 글로벌 transaction gate

앱 루트는 implicit animation이 없을 때 `DesignTokens.Animation.contentTransition`을 주입한다. 단, 리사이즈 중이거나 `MenuTransitionGate.isTransitioning`이면 주입하지 않는다.

- [CViewApp.swift L84-L100](../Sources/CViewApp/CViewApp.swift#L84-L100)
- [MenuTransitionGate.swift L1-L17](../Sources/CViewApp/Services/MenuTransitionGate.swift#L1-L17)
- [MenuTransitionGate.swift L30-L41](../Sources/CViewApp/Services/MenuTransitionGate.swift#L30-L41)

`MainContentView`도 사이드바 선택과 navigation path가 바뀔 때 gate를 켠다.

- [MainContentView.swift L83-L91](../Sources/CViewApp/Views/MainContentView.swift#L83-L91)

평가: 방향은 맞다. 메뉴 이동 시 신규 detail root가 마운트되면서 발생하는 implicit animation 폭주를 막는다.

한계: explicit `withAnimation`, view-local `.animation`, `.transition`은 여전히 실행된다. 특히 `HomeSectionAppear`와 카드 hover/펄스 애니메이션은 이 gate만으로는 막히지 않는다.

### 2.2 HomeView_v2의 sticky command bar와 refreshable 제거

`HomeView_v2`는 command bar를 `ScrollView` 밖으로 빼고, `.refreshable`도 제거했다.

- [HomeView_v2.swift L142-L167](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L142-L167)
- [HomeView_v2.swift L243-L248](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L243-L248)

평가: 클릭 hit-test와 scroll observer 비용을 줄이는 좋은 조치다.

### 2.3 추천/룩업 캐싱과 단일 onChange

추천 결과와 live lookup은 state cache로 보관하고, 여러 입력 변화 대신 `currentSignature` 하나로 recompute를 트리거한다.

- [HomeView_v2.swift L77-L90](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L77-L90)
- [HomeView_v2.swift L93-L138](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L93-L138)
- [HomeView_v2.swift L272-L279](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L272-L279)

평가: body 평가 중 추천 계산을 반복하지 않게 만든 점은 좋다.

한계: `recomputeCachesIfNeeded()`가 main actor에서 lookup/set/recommendation/prefetch launch까지 수행한다. 데이터가 큰 경우 메뉴 전환 첫 프레임과 겹칠 수 있다.

### 2.4 이미지 prefetch

`HomeThumbnailPrefetcher`는 홈 카드에 필요한 썸네일과 아바타를 `.utility` detached task로 미리 캐싱한다.

- [HomeThumbnailPrefetcher.swift L1-L34](../Sources/CViewApp/Services/HomeThumbnailPrefetcher.swift#L1-L34)
- [HomeThumbnailPrefetcher.swift L57-L81](../Sources/CViewApp/Services/HomeThumbnailPrefetcher.swift#L57-L81)
- [HomeThumbnailPrefetcher.swift L106-L127](../Sources/CViewApp/Services/HomeThumbnailPrefetcher.swift#L106-L127)

평가: 렌더 패스에서 이미지 디코딩을 줄이려는 방향은 맞다.

한계: prefetch task가 취소/병합되지 않는다. 홈 진입, 데이터 변경, 새로고침이 연속되면 이전 prefetch가 계속 도는 상태에서 새 prefetch가 추가될 수 있다.

---

## 3. 프레임 드랍 원인 후보

### H1. HomeView_v2 진입 직후 작업이 너무 많다

`HomeView_v2.onAppear`는 즉시 다음을 실행한다.

- `viewModel.startAutoRefresh()`
- `scheduleStoreReload()`
- `recomputeCachesIfNeeded()`

근거:

- [HomeView_v2.swift L263-L267](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L263-L267)

`startAutoRefresh()`는 90초 경량 refresh task와 300초 전체 통계 refresh task를 만든다.

- [HomeViewModel.swift L385-L411](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L385-L411)

`recomputeCachesIfNeeded()`는 main actor에서 dictionary 구성, Set 구성, 추천 점수 계산, 이미지 prefetch launch를 수행한다.

- [HomeView_v2.swift L93-L138](../Sources/CViewApp/Views/HomeV2/HomeView_v2.swift#L93-L138)

문제:

- 메뉴 전환은 `NavigationSplitView` detail root를 새로 만들고 layout을 계산한다.
- 같은 타이밍에 홈은 저장소 로드와 추천 캐시 계산을 시작한다.
- 추가로 prefetch가 바로 시작되면 이미지 cache actor, 네트워크, 디스크 작업이 첫 렌더 후속 프레임과 겹친다.

판정: P0. 홈 진입 첫 stutter의 가장 강한 원인 후보다.

### H2. HomeSectionAppear는 명시적 animation이라 gate를 우회한다

`HomeSectionAppear`는 `onAppear`에서 `withAnimation(.easeOut(duration: 0.22).delay(delay))`를 직접 호출한다.

- [HomeV2Effects.swift L31-L49](../Sources/CViewApp/Views/HomeV2/HomeV2Effects.swift#L31-L49)

문제:

- 루트 transaction gate는 implicit animation 주입을 막지만, 여기의 `withAnimation`은 명시적 animation이다.
- 홈 진입 시 최대 7개 섹션이 순차적으로 opacity/offset animation을 시작한다.
- 이 시점은 사이드바 indicator animation, detail layout, image task 시작과 겹친다.

판정: P0. 메뉴 이동 시 "딱 들어갈 때 끊기는" 현상과 잘 맞는다.

### H3. 홈 카드마다 LiveThumbnailView task loop가 생긴다

`LiveThumbnailView`는 `task(id:)`에서 `loadLoop()`를 시작하고, `isLive == true`면 TTL마다 반복 갱신한다.

- [LiveThumbnailView.swift L47-L52](../Sources/CViewApp/Views/Components/LiveThumbnailView.swift#L47-L52)
- [LiveThumbnailView.swift L57-L67](../Sources/CViewApp/Views/Components/LiveThumbnailView.swift#L57-L67)

홈에서는 Hero, 추천 카드, 인기 카드가 모두 `LiveThumbnailView`를 사용한다.

- [HomeV2Components.swift L187-L190](../Sources/CViewApp/Views/HomeV2/HomeV2Components.swift#L187-L190)
- [HomeV2Components.swift L330-L333](../Sources/CViewApp/Views/HomeV2/HomeV2Components.swift#L330-L333)

문제:

- 홈에 보이는 카드 수가 20개 전후가 되면 task loop도 그만큼 생긴다.
- 화면 밖 카드가 SwiftUI에 의해 살아 있는 동안에도 loop가 유지될 수 있다.
- 메뉴 이동 전후 task 취소/재생성, 이미지 fade-in transition, state update가 겹칠 수 있다.

판정: P0. 홈이 미디어 카드 중심으로 커진 현재 구조에서 반드시 줄여야 한다.

### H4. Prefetch task가 취소/병합되지 않는다

`HomeThumbnailPrefetcher.prefetchLive()`와 `prefetchPersisted()`는 매 호출마다 `Task.detached`를 만든다.

- [HomeThumbnailPrefetcher.swift L79-L81](../Sources/CViewApp/Services/HomeThumbnailPrefetcher.swift#L79-L81)
- [HomeThumbnailPrefetcher.swift L98-L101](../Sources/CViewApp/Services/HomeThumbnailPrefetcher.swift#L98-L101)

문제:

- 호출자가 await하지 않는 것은 렌더 차단을 피하는 장점이 있다.
- 하지만 메뉴를 빠르게 왕복하거나 refresh가 겹치면 이전 prefetch를 취소할 방법이 없다.
- `ImageCacheService`가 4동시 gate를 갖고 있어도, task group 자체와 URL 목록 순회/actor hop은 누적된다.

판정: P1. stutter를 악화시키는 2차 원인이다.

### H5. 일부 카드의 shadow radius가 여전히 상태에 따라 변한다

`HomeV2Effects.HomeHoverLift`는 shadow radius를 고정해 둔 반면, Hero/Recommended 카드 자체는 hover에 따라 radius를 바꾼다.

- 고정한 좋은 예: [HomeV2Effects.swift L69-L92](../Sources/CViewApp/Views/HomeV2/HomeV2Effects.swift#L69-L92)
- 남은 위험: [HomeV2Components.swift L245-L251](../Sources/CViewApp/Views/HomeV2/HomeV2Components.swift#L245-L251)
- 남은 위험: [HomeV2Components.swift L414-L431](../Sources/CViewApp/Views/HomeV2/HomeV2Components.swift#L414-L431)

문제:

- shadow radius 변화는 blur kernel 재계산을 유발한다.
- 홈 복귀 직후 마우스가 카드 위에 있거나 sidebar에서 detail로 이동하며 hover 상태가 바뀌면 GPU spike가 날 수 있다.

판정: P1. 호버 중 미세한 frame drop 원인이다.

### H6. Sidebar selection animation이 detail mount와 동시에 돈다

사이드바 row는 selection 배경에 `matchedGeometryEffect`를 쓰고, selected item 변화에 `.animation(DesignTokens.Animation.indicator)`를 적용한다.

- [MainContentView.swift L511-L533](../Sources/CViewApp/Views/MainContentView.swift#L511-L533)

문제:

- 사용자가 메뉴를 클릭하면 sidebar indicator animation과 detail root mount가 같은 run loop에서 발생한다.
- `MenuTransitionGate`는 루트 implicit spring만 막고, row-level `.animation`은 계속 실행된다.

판정: P1. 단독 원인은 아니지만 detail mount 비용과 합쳐질 때 체감 드랍이 커진다.

### H7. 성능 모니터가 켜진 상태에서는 측정 자체가 프레임 작업을 만든다

`HomeMonitorPanel`은 1초 폴링과 `FPSMeasureView`의 `TimelineView(.animation)`을 사용한다.

- [HomeMonitorPanel.swift L273-L297](../Sources/CViewApp/Views/HomeV2/HomeMonitorPanel.swift#L273-L297)
- [HomeMonitorPanel.swift L300-L328](../Sources/CViewApp/Views/HomeV2/HomeMonitorPanel.swift#L300-L328)

문제:

- 모니터가 켜진 상태에서 프레임 드랍을 재면 `TimelineView(.animation)`이 매 프레임 update를 만든다.
- 패널 자체가 `.regularMaterial`, shadow, transition을 가진 overlay다.

판정: P2. 진단 도구로는 유용하지만, 기본값은 꺼야 하고 측정 결과 해석 시 보정이 필요하다.

---

## 4. 개선안

### P0-1. 홈 진입 첫 350ms에는 데이터/이미지 작업을 지연

현재:

```swift
.onAppear {
    viewModel.startAutoRefresh()
    scheduleStoreReload()
    recomputeCachesIfNeeded()
}
```

권장:

1. 첫 프레임에는 static shell만 렌더한다.
2. `MenuTransitionGate`가 해제될 시간 이후에 저장소 reload와 recompute를 실행한다.
3. prefetch는 recompute 직후 바로 하지 말고 추가로 100~200ms debounce한다.

예시:

```swift
@State private var bootTask: Task<Void, Never>?

.onAppear {
    viewModel.startAutoRefresh()
    bootTask?.cancel()
    bootTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return }
        await reloadStore()
        recomputeCachesIfNeeded(prefetch: false)
        scheduleHomePrefetch()
    }
}
.onDisappear {
    viewModel.stopAutoRefresh()
    bootTask?.cancel()
    loadStoreTask?.cancel()
}
```

기대 효과:

- `NavigationSplitView` detail mount와 추천/저장소/prefetch가 분리된다.
- 메뉴 클릭 직후 체감 stutter를 줄일 수 있다.

### P0-2. HomeSectionAppear는 메뉴 전환 중 비활성화

현재 `HomeSectionAppear`는 explicit animation이라 gate를 우회한다.

권장:

- 홈 진입 직후에는 section appear animation을 생략한다.
- 사용자가 홈 안에서 섹션을 켜거나 화면 아래로 스크롤해 새 섹션이 나타날 때만 animation을 허용한다.

구현 방향:

```swift
struct HomeSectionAppear: ViewModifier {
    let index: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (enabled ? 8 : 0))
            .onAppear {
                guard !visible else { return }
                guard enabled, !MenuTransitionGate.isTransitioning else {
                    visible = true
                    return
                }
                withAnimation(.easeOut(duration: 0.18).delay(min(0.02 * Double(index), 0.12))) {
                    visible = true
                }
            }
    }
}
```

추가 권장:

- 기본 홈 진입에서는 animation off.
- refresh로 카드만 바뀔 때도 section-level appear는 재실행하지 않는다.

### P0-3. 홈에서는 썸네일 자동 갱신 루프를 제한

현재 `LiveThumbnailView`는 기본 `isLive = true`이고, 그러면 모든 카드가 45초 loop를 가진다.

권장:

- Hero 1개와 화면 상단 4~6개 카드만 live auto refresh 허용
- 추천/인기 grid의 작은 카드는 `autoRefresh: false` 또는 `isLive: false` 성격의 정적 cached thumbnail 사용
- 화면에 실제로 보이는 영역에 들어왔을 때만 refresh 시작

구현 방향:

```swift
public struct LiveThumbnailView: View {
    var refreshPolicy: RefreshPolicy = .liveLoop

    public enum RefreshPolicy {
        case liveLoop
        case once
        case visibleOnly
    }
}
```

홈 적용:

| 위치 | 권장 정책 |
|---|---|
| Hero card | `.liveLoop` |
| 팔로잉 라이브 상단 6개 | `.visibleOnly` 또는 `.once` |
| 추천 grid | `.once` |
| 인기 grid | `.once` |
| 이어보기/즐겨찾기 아바타 | `CachedAsyncImage` 유지 |

기대 효과:

- 홈 진입 시 task loop 수 감소
- 메뉴 이동 시 task cancel/recreate 비용 감소
- 45초마다 여러 카드가 동시에 fade-in 갱신되는 현상 완화

### P0-4. 홈 prefetch를 debounced + cancellable로 변경

현재 prefetch는 detached fire-and-forget이다.

권장:

- `HomeThumbnailPrefetcher` 내부에 `currentTask`와 generation token을 둔다.
- 새 요청이 오면 이전 prefetch를 취소한다.
- 메뉴 전환 중에는 prefetch를 skip하거나 지연한다.
- live thumbnail prefetch는 top N만 수행하고, 나머지는 avatar만 prefetch한다.

예시:

```swift
@MainActor
enum HomeThumbnailPrefetcher {
    private static var currentTask: Task<Void, Never>?

    static func prefetchLive(channels: [LiveChannelItem], includeLiveThumbnail: Bool = true) {
        currentTask?.cancel()
        let slice = Array(dedupe(channels).prefix(24))
        currentTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await runPrefetch(...)
        }
    }

    static func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

`HomeView_v2.onDisappear`에서 `HomeThumbnailPrefetcher.cancel()` 호출도 추가한다.

### P1-1. Hero/Recommended 카드의 shadow radius를 고정

현재 Hero와 Recommended 카드에는 hover에 따른 radius 변화가 남아 있다.

수정 전:

```swift
.shadow(
    color: hovered ? accent.opacity(...) : .black.opacity(...),
    radius: hovered ? 24 : 14
)
```

수정 후:

```swift
.shadow(
    color: hovered ? DesignTokens.Colors.chzzkGreen.opacity(0.24) : .black.opacity(0.12),
    radius: 14,
    y: hovered ? 8 : 4
)
```

Recommended card도 radius를 8 또는 10으로 고정하고 opacity/y만 바꾼다.

### P1-2. Sidebar selection animation도 menu transition gate와 연동

현재 row-level animation은 선택 변화마다 동작한다.

권장:

```swift
.animation(
    MenuTransitionGate.isTransitioning ? nil : DesignTokens.Animation.indicator,
    value: router.selectedSidebarItem
)
```

또는 sidebar indicator는 즉시 이동시키고, detail 화면 안정화 후 hover/selection animation만 되살린다.

기대 효과:

- 메뉴 클릭 순간 sidebar와 detail이 동시에 spring 계열 animation을 돌리는 문제 감소

### P1-3. 추천 계산을 detached로 이동

현재 `recomputeCachesIfNeeded()`는 main actor 함수다. 추천 score 자체는 UI state 접근 후 snapshot만 만들면 백그라운드에서 계산 가능하다.

권장:

1. main actor에서 candidates/following/favorite/recent/session snapshot만 캡처
2. `Task.detached(priority: PowerAwareTaskPriority.userVisible)`에서 lookup/recommendation 계산
3. 결과만 main actor에 assign
4. prefetch는 assign 이후 debounce

효과:

- allStatChannels가 커졌을 때도 첫 프레임 main actor 점유를 줄인다.

### P1-4. Home monitor는 측정 모드와 일반 모드를 분리

권장:

- 기본 monitor는 1초 system snapshot만 표시
- FPS 측정은 "정밀 측정 시작" 버튼을 눌렀을 때 10초만 실행
- `TimelineView(.animation)`은 항상 켜두지 않는다

예시 UX:

- `모니터`: CPU/MEM/GPU/THREAD 1초 폴링
- `FPS 측정`: 버튼 클릭 후 10초 sampling, 이후 자동 중지

### P2-1. 홈 카드 수를 viewport 기반으로 줄이기

현재 추천은 최대 12개, 이어보기/즐겨찾기도 각각 12개까지 horizontal row에 둔다.

- [HomeV2Components.swift L453-L459](../Sources/CViewApp/Views/HomeV2/HomeV2Components.swift#L453-L459)

권장:

- 첫 렌더는 Hero + 팔로잉 6 + 추천 6 + 인기 6 정도로 제한
- "더 보기" 클릭 후 추가 카드 로드
- horizontal row는 6개까지만 초기 생성, 나머지는 별도 화면으로 이동

---

## 5. 권장 실행 순서

### Step 1. 전환 안정화

가장 먼저 적용할 항목:

1. `HomeView_v2.onAppear`의 `reloadStore/recompute/prefetch` 350~500ms 지연
2. `HomeSectionAppear`가 `MenuTransitionGate.isTransitioning`일 때 animation 없이 즉시 표시
3. Sidebar row animation도 `MenuTransitionGate`와 연동

기대: 메뉴 이동 직후 첫 프레임 드랍 감소

### Step 2. 이미지 task 압축

다음 적용:

1. `LiveThumbnailView`에 refresh policy 추가
2. 홈의 추천/인기 grid는 `.once`
3. Hero만 live loop 유지
4. prefetch cancellable/debounced 처리

기대: 홈 진입 후 0.5~2초 사이의 잔 stutter 감소

### Step 3. GPU hover 비용 정리

다음 적용:

1. Hero/Recommended shadow radius 고정
2. hover scale이 이미지 layout을 건드리지 않도록 card content를 `compositingGroup()`으로 묶기
3. `homeAccentPulse`는 기본 Hero 1개에만 적용하고, 여러 카드에는 사용 금지

기대: 홈에서 마우스를 움직일 때의 미세 끊김 감소

### Step 4. 계측 방식 정리

마지막 적용:

1. FPS monitor를 10초 sampling 버튼 방식으로 변경
2. `os_signpost` 또는 간단한 timestamp log 추가
3. 메뉴 전환별 FPS/drop frame 기록

기대: 개선 전후를 일관되게 비교 가능

---

## 6. 측정 체크리스트

수정 전후 다음 시나리오를 같은 조건에서 비교한다.

| 시나리오 | 관찰 포인트 |
|---|---|
| 앱 실행 후 splash 종료 -> 홈 첫 진입 | 첫 1초 FPS, CPU spike, thumbnail placeholder 지속 시간 |
| 홈 -> 팔로잉 -> 홈 빠른 왕복 | detail mount 시 프레임 드랍 |
| 홈 -> 카테고리 -> 검색 -> 홈 | NavigationSplitView 전환 안정성 |
| 홈에서 새로고침 버튼 클릭 | recompute/prefetch 중 stutter |
| 홈에서 마우스를 Hero/추천 카드 위로 이동 | hover GPU spike |
| monitor off/on 각각 측정 | monitor 자체 부하 분리 |

권장 임계값:

- 메뉴 전환 후 500ms 평균 FPS: 55 이상
- 45 FPS 미만 frame burst: 2프레임 이하
- 홈 진입 후 main thread long frame: 16.7ms 초과 3회 이하
- CPU spike가 있더라도 1초 이내 안정화

---

## 7. 최종 제안 요약

현재 홈 v2는 구조적으로 이미 많이 개선되어 있다. 프레임 드랍은 디자인 자체보다 **전환 순간에 너무 많은 일이 동시에 시작되는 문제**에 가깝다.

가장 효과가 큰 수정은 다음 세 가지다.

1. 홈 마운트 직후 작업을 `MenuTransitionGate` 해제 이후로 지연한다.
2. `HomeSectionAppear` 같은 explicit animation도 메뉴 전환 중에는 비활성화한다.
3. 홈 grid 카드의 `LiveThumbnailView`는 live loop가 아니라 one-shot thumbnail로 바꾼다.

이 세 가지를 먼저 적용하면 메뉴 이동 시 첫 프레임 드랍이 가장 크게 줄어들 가능성이 높다. 이후 prefetch 취소/병합, shadow radius 고정, sidebar indicator gate 연동을 추가하면 홈 화면의 잔 stutter까지 줄일 수 있다.
