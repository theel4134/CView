# CView v2 — 프로젝트 정밀 분석 및 개선 로드맵

> **분석 시점**: 2026-04-18 · **빌드 기준**: v2.0.0 (31)
> **대상 커밋**: `455390e (HEAD → main)` · **총 LOC**: 70,675 (Sources)
> 분석 범위: 모듈 구조, 아키텍처, 성능, 보안, 코드 품질, 테스트, 빌드/배포, UX

---

## 0. 한눈에 보는 결론

| 영역 | 평가 | 핵심 액션 |
|---|---|---|
| **모듈 분리** | 양호하지만 `CViewApp` 비대 | App 모듈을 ViewModels/Views로 분할 |
| **동시성 모델** | Swift 6 + Actor + @Observable, 우수 | `@unchecked Sendable` 점진 축소 |
| **성능/CPU** | 빌드 30~31에서 크게 개선 | PowerAware 적용 잔여 위치 7곳 마저 적용 |
| **보안** | ATS 정책 불일치, 코드 서명 ad-hoc만 | ATS 정렬 + Developer ID 서명/공증 |
| **테스트** | Player·Core는 두꺼움, App·Monitoring 빈약 | UI 골든패스/MetricsForwarder 통합 테스트 |
| **유지보수** | 1000줄+ 파일 9개 | 분할 (특히 `MetricsForwarder` 1298줄) |
| **배포** | DMG/notarize/auto-update 없음 | Sparkle + GitHub Release 워크플로 |

---

## 1. 모듈 구조와 의존성

### 1.1 LOC 분포 (`Sources/`)

| 모듈 | 파일 수 | LOC | 비중 | 주된 책임 |
|---|---:|---:|---:|---|
| `CViewApp` | 119 | **40,964** | 58.0% | App entry, ViewModels, Views, Services, Navigation |
| `CViewPlayer` | 42 | 12,302 | 17.4% | VLC/AVPlayer/HLSJS 엔진, ABR, PID, LowLatency, Proxy |
| `CViewCore` | 44 | 6,910 | 9.8% | 도메인 모델, 프로토콜, 디자인토큰, DI, Utilities |
| `CViewNetworking` | 15 | 3,400 | 4.8% | API 클라이언트, 이미지 캐시, WebSocket |
| `CViewChat` | 6 | 2,280 | 3.2% | 채팅 엔진, 파서, WebSocket, 모더레이션 |
| `CViewMonitoring` | 2 | 1,690 | 2.4% | 메트릭 포워더, 성능 모니터 |
| `CViewAuth` | 7 | 1,336 | 1.9% | OAuth, 쿠키, 키체인 |
| `CViewUI` | 5 | 1,091 | 1.5% | 공유 UI 컴포넌트 |
| `CViewPersistence` | 4 | 702 | 1.0% | SwiftData 컨테이너, 모델 |

**의존성 그래프** (DAG 무순환 — 양호)

```
CViewCore ◀── 모두
CViewNetworking ◀── Auth, Chat, Player, UI, Monitoring, App
CViewAuth ◀── App
CViewPersistence ◀── App
CViewChat ◀── App
CViewPlayer ◀── App
CViewUI ◀── App
CViewMonitoring ◀── App
```

### 1.2 발견된 구조적 이슈

| ID | 위치 | 문제 | 권장 |
|---|---|---|---|
| **S-1** | `Sources/CViewApp` 40,964 LOC | App 모듈에 ViewModels/Views/Services가 모두 들어가 단일 모듈로 빌드 → 증분 컴파일 비효율, 책임 흐림 | `CViewAppViewModels` / `CViewAppViews` 라이브러리로 분리 (Views ↔ ViewModel 의존만) |
| **S-2** | `CViewMonitoring` 2 파일 1,690 LOC | `MetricsForwarder.swift` **1298줄** 단일 파일에 로직 응집 | extension 분리 (`+Heartbeat`, `+MultiLive`, `+Connection`, `+Payload`) |
| **S-3** | `CViewApp/Views` 1000줄+ 파일 다수 (`MultiLivePlayerPane` 962, `FollowingView` 796, `MainContentView` 667 …) | SwiftUI body 깊이 + 중첩 modifier로 타입 체커 부하 큼 (실제로 `-warn-long-expression-type-checking=200` 경고 가능) | 컴포넌트 추출 + `@ViewBuilder` 함수화 |
| **S-4** | `CViewCore/Protocols/` (4 파일) | 프로토콜은 있으나 `ServiceContainer`로 등록되는 타입은 일부만 (`ChzzkAPIClient`, `AuthManager`만 등록) → 사실상 강결합 | 모든 ViewModel이 `APIClientProtocol` / `AuthManagerProtocol`로 받도록 리팩토링 (Mock 주입 가능) |

---

## 2. 아키텍처 패턴 분석

### 2.1 핵심 패턴 (긍정적)

- **Swift 6 strict concurrency** (`Package.swift` L8): `.swiftLanguageMode(.v6)` 적용
- **Actor 기반 DI**: `ServiceContainer` ([Sources/CViewCore/DI/ServiceContainer.swift](Sources/CViewCore/DI/ServiceContainer.swift)) — lock-free, 재진입 안전
- **@Observable + @MainActor**: `AppState` ([Sources/CViewApp/AppState.swift](Sources/CViewApp/AppState.swift#L13-L15)) — Combine ObservableObject 대비 변경 폭주 적음
- **Typed errors**: `AppError` 도메인별 분리 ([Sources/CViewCore/Errors/AppError.swift](Sources/CViewCore/Errors/AppError.swift)) — `LocalizedError` + `recoverySuggestion`
- **PlayerEngineProtocol 추상화**: VLC/AVPlayer/HLSJS 3개 엔진을 동일 인터페이스로 ([Sources/CViewCore/Protocols/PlayerEngineProtocol.swift](Sources/CViewCore/Protocols/PlayerEngineProtocol.swift))
- **Power-aware QoS**: 빌드 31에서 도입한 `PowerSourceMonitor` + `PowerAwareTaskPriority` ([Sources/CViewCore/Utilities/PowerSourceMonitor.swift](Sources/CViewCore/Utilities/PowerSourceMonitor.swift))

### 2.2 발견된 아키텍처 이슈

| ID | 위치 | 문제 | 권장 |
|---|---|---|---|
| **A-1** | [AppState.swift](Sources/CViewApp/AppState.swift#L60-L96) | `AppState`가 8개 옵저버 토큰 + 5개 ViewModel + Store + Manager + Service 등 **God Object 경향** | Coordinator 패턴 도입(`PlaybackCoordinator`, `AuthCoordinator`)으로 책임 위임 |
| **A-2** | [CViewApp.swift](Sources/CViewApp/CViewApp.swift#L48-L50) | `@State private var appState = AppState()` → `appState.initialize(...)`를 onAppear에서 호출하는 **2단계 init** | `init`에서 의존성 주입 완료 후 onAppear는 side-effect만 |
| **A-3** | `@unchecked Sendable` **30+ 개소** (Player 모듈 다수) | VLCKit/WebKit/URLProtocol 등 외부 클래스 unchecked 불가피하지만, `LocalStreamProxy`, `PiPController`, `AVPlayerObserverBag` 등은 actor화 또는 Mutex 캡슐화 가능 | 우선순위 높은 3개부터 actor 전환 (LocalStreamProxy → 이미 NSLock 사용 중, actor 비용/이득 측정) |
| **A-4** | `CViewApp.swift` 의존성 생성 ([L34-L42](Sources/CViewApp/CViewApp.swift#L34-L42)) | `ChzzkAPIClient`, `AuthManager`, `MetricsAPIClient`, `MetricsWebSocketClient`를 `init()`에서 직접 생성 (DI 컨테이너 미경유) | `AppDependencies.makeProductionContainer()` 패턴으로 통합 |
| **A-5** | `LocalStreamProxy` (Player 모듈) | HLS 매니페스트 가공을 위해 자체 HTTP 서버를 띄움 — 포트 충돌/방화벽/보안 표면 증가 | 가능하면 `URLProtocol` 인터셉터(`CViewHTTPURLProtocol`) 통일, 사용 빈도 측정 후 한쪽 폐기 |

---

## 3. 성능 / CPU / 메모리

### 3.1 빌드 31까지 적용 완료

- 정수 픽셀 스냅 + onGeometryChange 가드 → 리사이즈 버벅임 해결
- VLC stats timer: 단일 5s→10s, 멀티 10s→15s
- BW 코디네이터: 5s→8s
- **PowerAware QoS** ([PowerSourceMonitor.swift](Sources/CViewCore/Utilities/PowerSourceMonitor.swift)): AC=P-core, Battery=E-core
- VLC `:avcodec-threads`, Quality Lock(1080p60/8M)

### 3.2 잔여 성능 이슈

| ID | 위치 | 문제 | 권장 |
|---|---|---|---|
| **P-1** | [HomeViewModel.swift L156](Sources/CViewApp/ViewModels/HomeViewModel.swift#L156) | `_recomputeStatsTask = Task.detached(priority: .userInitiated)` — 통계 재계산이 배터리에서도 P-core 점유 | `PowerAwareTaskPriority.userVisible` 적용 |
| **P-2** | [FollowingView.swift L202](Sources/CViewApp/Views/FollowingView.swift#L202) | 팔로잉 분류 `.userInitiated` 고정 | `PowerAwareTaskPriority.userVisible` |
| **P-3** | [FollowingView.swift L777, L792](Sources/CViewApp/Views/FollowingView.swift#L777) | 백그라운드 prefetch `.utility` 고정 | `PowerAwareTaskPriority.periodic` |
| **P-4** | [BackgroundUpdateService.swift L135](Sources/CViewApp/Services/BackgroundUpdateService.swift#L135) | 팔로잉 폴링 `.utility` 고정 | `PowerAwareTaskPriority.periodic` + `PowerAwareInterval.scaled()` |
| **P-5** | [AppDependencies.swift L187](Sources/CViewApp/AppDependencies.swift#L187) | DataStore 마이그레이션 `Task.detached(priority: .background)` — 일회성이라 영향 작지만 일관성 ↓ | `PowerAwareTaskPriority.prefetch` |
| **P-6** | [ChatViewModel+Processing.swift L139, L156](Sources/CViewApp/ViewModels/ChatViewModel+Processing.swift#L139) | 채팅 후속 처리 `.background` (유지) — 단, 메인 변환과 분리되어 있음 | 그대로 유지(타당) |
| **P-7** | `LowLatencyController` (PID 평가 주기) | 평가 주기 고정값으로 추정 | `PowerAwareInterval.scaled(_:batteryMultiplier:)` 적용 검토 |
| **P-8** | `ImageCacheService` LRU prune 주기 | 시작 후 3초 1회 ([CViewApp.swift L83](Sources/CViewApp/CViewApp.swift#L83))만, 장기 실행 시 LRU 누적 가능 | `Task.detached(priority: PowerAwareTaskPriority.prefetch)` + 30분 주기 |

### 3.3 잠재적 메모리/누수 핫스팟

- `nonisolated(unsafe) static` 포매터 4건 ([HLSManifestParser.swift L133-L138](Sources/CViewPlayer/HLSManifestParser.swift#L133), [APIResponse.swift L227-L233](Sources/CViewNetworking/APIResponse.swift#L227)) — 안전한 패턴이나 `@MainActor static let`로 격리하면 unsafe 마커 제거 가능
- `FollowingView.swift` L51 `nonisolated(unsafe) static var defaultValue: CGFloat = 0` — **변수**(var)가 unsafe → SwiftUI PreferenceKey 표준 패턴이지만 `MainActor` 제약 가능 검토
- `AppState`의 `_backgroundEntryTime`, `longIdleSuspendTask` 등 옵저버/Task 다수 — `removeAllObservers` ([AppLifecycle.swift L109-L122](Sources/CViewApp/AppLifecycle.swift#L109))에 모두 포함되었는지 정기 점검 필요

---

## 4. 보안 / 네트워크

### 4.1 발견된 이슈

| ID | 위치 | 문제 | 심각도 | 권장 |
|---|---|---|---|---|
| **SEC-1** | [build_release.sh L107-L110](build_release.sh#L107) vs [SupportFiles/Info.plist L36-L40](SupportFiles/Info.plist#L36) | 릴리즈 스크립트는 **`NSAllowsArbitraryLoads=true`** (모든 HTTP 허용), Xcode용은 **`NSAllowsLocalNetworking=true`** (로컬만) — **정책 불일치** | **High** | release 스크립트도 `NSAllowsLocalNetworking` + 도메인별 `NSExceptionDomains` (chzzk/naver) 화이트리스트로 변경 |
| **SEC-2** | [build_release.sh L143-L153](build_release.sh#L143) | ad-hoc 서명만 사용 — 다른 머신에서 Gatekeeper 차단, 공증(notarize) 없음 | **High** | Developer ID 서명 + `xcrun notarytool` 통합 (CI에서) |
| **SEC-3** | [HLSJSVideoView.swift L116](Sources/CViewPlayer/HLSJSVideoView.swift#L116) | `webView.loadHTMLString(html, baseURL: URL(string: "http://localhost"))` — http baseURL은 mixed-content 정책 완화 목적이나, JS bridge에서 임의 origin XHR 가능성 | Medium | baseURL을 `nil` 또는 `bundle://` 검토, CSP `<meta>` 강화 |
| **SEC-4** | `hls.min.js` v1.5.18 (인라인 임베드) | 최신 1.5.x 시리즈 보안 패치 추적 필요 | Low | `npm view hls.js versions`로 정기 점검, `hls.js/SECURITY.md` 모니터 |
| **SEC-5** | [CookieManager.swift L66](Sources/CViewAuth/CookieManager.swift#L66) | ~~`NID_AUT/NID_SES`를 키체인 + `HTTPCookieStorage` 양쪽 저장 — 동기화 실패 시 stale 가능~~ → **재검토(2026-04): 이미 단일 source of truth(키체인) + 단방향 복원 패턴**. 변경 불필요. | — | — |
| **SEC-6** | `LocalStreamProxy` 로컬 HTTP | 로컬 포트 바인딩 → 같은 머신 내 다른 사용자/앱이 접근 가능 | Medium | `127.0.0.1` + 임의 토큰 헤더 검증 + 포트 0(임의) 사용 |

### 4.2 양호한 점

- ✅ Certificate pinning 인프라 존재 ([CertificatePinningDelegate.swift](Sources/CViewNetworking/CertificatePinningDelegate.swift))
- ✅ Hardened Runtime 활성화 (`--options runtime`)
- ✅ JWT 사전 발급 + Authorization 헤더 인증 미들웨어
- ✅ 로깅 마스킹 `LogMask.token(...)` 사용

---

## 5. 코드 품질 / 유지보수

### 5.1 좋은 신호

- **TODO/FIXME/HACK 마커 0건** — 빚 청산 잘 되어 있음 (recent commits에서 "Round 4-9 안정성 개선" 시리즈 확인)
- **OSLog 기반 `AppLogger`** — `privacy: .private/.public` 마킹 일관
- **Deprecated alias 유지** — DesignTokens 토큰 정리 시 `@available(*, deprecated, renamed:)` 점진 마이그레이션
- **Test 모듈 7개 분리** — Player 10, Core 12, Chat 4 ...

### 5.2 발견된 품질 이슈

| ID | 위치 | 문제 | 권장 |
|---|---|---|---|
| **Q-1** | [DesignTokens.swift L40-L62](Sources/CViewCore/DesignSystem/DesignTokens.swift#L40) | Spacing에 `xxxs/nano/mini/xss/xsm/cozy/mdl` 등 **deprecated alias 12개** 잔존 | 프로젝트 grep 후 일괄 치환 → 다음 메이저에서 제거 |
| **Q-2** | `CViewApp/Views`의 거대 파일 (962/834/796 LOC) | SwiftUI 컴파일 타임 폭증 위험, 변경 영향 추적 어려움 | 한 파일 ≤ 400 LOC 가이드라인 (PR 템플릿에 추가) |
| **Q-3** | 일부 actor에 GCD 흔적 (구 이력) | `CookieManager.syncFromWebKitStore` 등 — 이미 `MainActor.run`으로 리팩토링됨 (양호) | 전체 grep `DispatchQueue.global` 정기 검사 |
| **Q-4** | `CViewMonitoringTests` 1 파일 | `MetricsForwarder` 1298줄에 비해 테스트 빈약 → 페이로드 회귀 위험 | `forwardCurrentMetrics` 분기 테스트(VLC/AVP/HLSJS), `safeForJSON` 경계 테스트 추가 |
| **Q-5** | SwiftUI `View` 단위 테스트 0건 | `Tests/CViewAppTests` 자체 미존재 | `ViewInspector` 또는 snapshot test 도입 (최소 5개 핵심 화면) |

---

## 6. 빌드 / 배포

### 6.1 현황

- `swift build -c release -j <P-core>` → SPM executableTarget
- VLCKit.framework rpath 수정 + ad-hoc 서명 + Hardened Runtime
- 빌드 번호 자동 증가 (`.build_number`)
- **Info.plist 두 벌**:
  - `SupportFiles/Info.plist`: Xcode 빌드용 (CFBundleVersion=1, ATS=LocalNetworking)
  - `build_release.sh` 동적 생성: SPM 빌드용 (CFBundleVersion=$BUILD_NUMBER, ATS=ArbitraryLoads)
- ✅ GitHub Actions CI/CD 존재 (commit `29646cf`)

### 6.2 개선 액션

| ID | 항목 | 권장 |
|---|---|---|
| **B-1** | Info.plist 이원화 | 단일 Info.plist + `xcodebuild` 변수 치환 또는 `Configuration.xcconfig` 도입 |
| **B-2** | DMG/공증 자동화 | `create-dmg` + `xcrun notarytool submit --wait` + `stapler staple` |
| **B-3** | Auto-update 부재 | [Sparkle](https://sparkle-project.org/) 통합 (release feed: GitHub Releases) |
| **B-4** | Crash report 부재 | KSCrash 또는 macOS의 `MetricKit` 기반 자체 수집 |
| **B-5** | `swift package resolve` 매번 호출 가능 | `--disable-automatic-resolution` 적용됨 (양호) — `Package.resolved` 커밋 확인 |

---

## 7. 테스트 커버리지

### 7.1 현황

| 모듈 | 테스트 파일 수 | 평가 |
|---|---:|---|
| `CViewCoreTests` | 12 | 양호 — 도메인 모델/유틸리티 |
| `CViewPlayerTests` | 10 | 양호 — StreamCoordinator, ABR, EWMA, PID 등 |
| `CViewChatTests` | 4 | **개선** — 파서 회귀, 재연결 시나리오 추가 |
| `CViewNetworkingTests` | 4 | **개선** — 실제 응답 fixture 다양화 |
| `CViewAuthTests` | 3 | **개선** — OAuth 콜백, 쿠키 만료 시나리오 |
| `CViewPersistenceTests` | 2 | **개선** — 마이그레이션 시나리오 |
| `CViewMonitoringTests` | 1 | **부족** — payload 회귀 시 즉시 알림 |
| `CViewAppTests` | **없음** | **신규 필요** — ViewModel 단위 |

### 7.2 신규 테스트 권장 목록

1. `MetricsForwarderTests`: VLC/AVP/HLSJS 분기, NaN/Infinity 페이로드 방어
2. `ChatMessageParserTests`: 이모티콘/멘션/도네이션/구독 메시지 회귀
3. `MultiLiveManagerTests`: 4세션 동시 시작/종료, BW 분배 알고리즘
4. `AuthManagerTests`: OAuth 토큰 갱신 동시성 (이미 Round 8에서 수정됨)
5. UI 골든패스: `LiveStreamView` mount/unmount, `MultiLivePlayerPane` resize

---

## 8. UX / 접근성

### 8.1 발견된 이슈

| ID | 위치 | 문제 | 권장 |
|---|---|---|---|
| **U-1** | 다국어 | `CFBundleDevelopmentRegion=ko` 단일 — UI 문자열 하드코딩 | `String(localized:)` + `Localizable.xcstrings` 도입 (en 최소) |
| **U-2** | 접근성 | VoiceOver `accessibilityLabel` 사용 빈도 미확인 | 핵심 컨트롤(재생/볼륨/채널 카드) 라벨 점검 |
| **U-3** | 키보드 단축키 | ⌘N(새 창), ⌘⇧T(통계), ⌘⌥N(네트워크), ⌘K(팔레트) 등 정의 ([CViewApp.swift L186-L210](Sources/CViewApp/CViewApp.swift#L186)) | `showKeyboardShortcutsHelp` 시트가 모든 단축키를 일관되게 노출하는지 확인 |
| **U-4** | 디버그 오버레이 | 네트워크 모니터/메트릭 윈도우 분리 | 단일 "개발자 패널" 윈도우로 통합 검토 |

---

## 9. 우선순위별 개선 로드맵

### 🔴 P0 (다음 빌드 32 후보)

1. **PowerAware 적용 잔여 7곳** (P-1~P-5, P-7, P-8) — 한 PR로 일괄
2. **ATS 정책 정렬** (SEC-1) — release script도 `NSAllowsLocalNetworking` + 도메인 화이트리스트
3. **Info.plist 단일화** (B-1) — Xcode/SPM 양쪽 동일 정책 보장

### 🟡 P1 (단기, 빌드 32-35)

4. **`MetricsForwarder` 분할** (S-2) — extension 4개로
5. **`AppState` Coordinator 분리** (A-1) — `PlaybackCoordinator`, `AuthCoordinator`
6. **거대 SwiftUI View 분할** (Q-2) — 962/834/796 LOC 3개 우선
7. **`MetricsForwarderTests` 신규** (Q-4)
8. **로컬 프록시 보안 강화** (SEC-6) — 토큰 헤더 검증

### 🟢 P2 (중기, 1-2개월)

9. **App 모듈 ViewModels/Views 분리** (S-1) — 증분 컴파일 30%+ 개선 기대
10. **Sparkle 통합 + Developer ID 서명/공증** (B-2, B-3, SEC-2)
11. **`AppDependencies` 통합 DI** (A-4) — 모든 서비스 컨테이너 경유
12. **`@unchecked Sendable` 우선 3개 actor 전환** (A-3)
13. **다국어 (en) 최소 지원** (U-1)

### 🔵 P3 (장기, 분기)

14. **HLS.js → AVPlayer 우선** 전환 가능성 평가 (메모리/CPU 비교)
15. **Sparkle delta update** + GitHub Release 자동화
16. **Crash report 수집** (MetricKit)
17. **UI 스냅샷 테스트** + CI 게이팅

---

## 10. 부록

### 10.1 실측 메트릭 요약

```
Total Source LOC:  70,675  (Swift only, exclude Tests)
Largest Files:
  1298  Sources/CViewMonitoring/MetricsForwarder.swift
   962  Sources/CViewApp/Views/MultiLivePlayerPane.swift
   962  Sources/CViewApp/ViewModels/MultiLiveManager.swift
   923  Sources/CViewApp/Views/Dashboard/MetricsDashboardView.swift
   834  Sources/CViewApp/ViewModels/HomeViewModel.swift
   804  Sources/CViewChat/ChatMessageParser.swift
   796  Sources/CViewApp/Views/FollowingView.swift
   771  Sources/CViewApp/Views/PlayerControlsView.swift
   768  Sources/CViewApp/Views/MultiLiveTabBar.swift
   768  Sources/CViewApp/Views/ChatSettingsQualityView.swift
TODO/FIXME/HACK markers: 0
@unchecked Sendable: 30+ (Player, Auth, Networking, Chat)
nonisolated(unsafe): 9 (대부분 ISO8601DateFormatter, 안전 패턴)
```

### 10.2 최근 안정성 작업 이력 (참고)

- Round 3-9 안정성 개선 시리즈 (`f8ac587` ~ `dd0ea21`) — 리소스 누수, OAuth 동시성, WebSocket 정리, force unwrap 제거 완료
- 빌드 25-29: 네트워크 최적화, StreamProxyMode 실시간 반영, Quality Lock(1080p60/8M)
- 빌드 30: 리사이즈 버벅임 + CPU 핫스팟 최적화
- 빌드 31: PowerAware QoS (AC=P-core, Battery=E-core)

---

**문서 작성**: GitHub Copilot · **검토 권장 주기**: 빌드 +5마다 또는 분기 1회
