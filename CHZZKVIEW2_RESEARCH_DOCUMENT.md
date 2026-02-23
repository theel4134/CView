# chzzkView2 프로젝트 개발을 위한 정밀 분석 연구 문서

> **문서 버전**: 1.0  
> **작성일**: 2026-02-16  
> **대상**: chzzkView → chzzkView2 마이그레이션  
> **기반 기술**: Swift 6.x / macOS 15+ / SwiftUI

---

## 목차

1. [기존 프로젝트(chzzkView) 현황 분석](#1-기존-프로젝트chzzkview-현황-분석)
2. [핵심 문제점 도출](#2-핵심-문제점-도출)
3. [Swift 6.x 전환 필수 요구사항](#3-swift-6x-전환-필수-요구사항)
4. [chzzkView2 아키텍처 설계 제안](#4-chzzkview2-아키텍처-설계-제안)
5. [모듈 분리 전략](#5-모듈-분리-전략)
6. [동시성(Concurrency) 마이그레이션 가이드](#6-동시성concurrency-마이그레이션-가이드)
7. [데이터 영속화 통합 전략](#7-데이터-영속화-통합-전략)
8. [네트워크 레이어 재설계](#8-네트워크-레이어-재설계)
9. [채팅 시스템 재설계](#9-채팅-시스템-재설계)
10. [스트리밍/플레이어 엔진 재설계](#10-스트리밍플레이어-엔진-재설계)
11. [테스트 전략](#11-테스트-전략)
12. [마이그레이션 로드맵](#12-마이그레이션-로드맵)
13. [부록: 기존 코드 품질 메트릭](#부록-기존-코드-품질-메트릭)

---

## 1. 기존 프로젝트(chzzkView) 현황 분석

### 1.1 프로젝트 개요

| 항목 | 내용 |
|------|------|
| **앱 이름** | chzzkView (치지직 뷰어) |
| **플랫폼** | macOS (macOS 15 Sequoia+, macOS 26 Tahoe 지원) |
| **Swift 버전** | Swift 6.0 (`swift-tools-version:6.0`) |
| **UI 프레임워크** | SwiftUI(메인) + AppKit(NSStatusBar, NSWindow 등) |
| **번들 ID** | com.chzzk.oauth (URL Scheme: `chzzk://`) |
| **총 Swift 소스 파일** | **538개** |
| **Services/ 코드량** | **148,110줄** (270파일) |
| **외부 의존성** | VLCKitSPM (유일한 외부 패키지) |
| **설명** | 네이버 치지직(CHZZK) 라이브 스트리밍 뷰어 — 저지연 HLS, VLC 통합, AI 동기화, 채팅, 통계 |

### 1.2 디렉토리 구조 (간소화)

```
chzzkView/
├── chzzkViewApp.swift              (1,224줄) — 앱 진입점 + AppDelegate
├── ContentView.swift               (987줄)  — 메인 뷰 (25개 @State)
├── DesignTokens.swift              (735줄)  — 8pt Grid 디자인 시스템
├── Item.swift                      — SwiftData 모델 (placeholder)
│
├── Authentication/                  (1 파일)
├── Database/                        (21 파일)  — SQLite 직접 + CoreData
├── Extensions/                      (5 파일)
├── Helpers/                         (3 파일)
├── Models/                          (21 파일)
│
├── Services/                        (270 파일, 148,110줄) — 핵심 비즈니스 로직
│   ├── Core/          (18 파일) — DI, AppEnvironment, ServiceRegistry
│   ├── Auth/          (4 파일)  — 인증 시스템 (레거시)
│   ├── NewAuth/       (6 파일)  — 인증 시스템 (리팩토링)
│   ├── Chat/          (22 파일, 10,821줄) — 채팅 시스템
│   ├── HLS/           (18 파일, 6,708줄)  — HLS 스트리밍
│   ├── Player/        (30 파일, 24,811줄) — 플레이어 엔진
│   ├── Sync/          (13 파일, 10,472줄) — VLC-Web 동기화
│   ├── GPU/           (6 파일, 4,017줄)   — Metal3 GPU 가속
│   ├── Agent/         (16 파일)           — AI Agent 시스템
│   ├── StreamingEngine/ (8 파일)          — 스트리밍 Facade
│   ├── Monitoring/    (15 파일)           — 메트릭/모니터링
│   ├── VOD/           (13 파일)           — VOD 처리
│   └── (기타 15+ 서브디렉토리)
│
├── ViewModels/                      (10 파일, 가장 큰 것: HomeViewModel 1,146줄)
├── Views/                           (~130 파일)
├── Utilities/                       (10 파일)
└── Utils/                           (14 파일)
```

### 1.3 현재 아키텍처 패턴

**MVVM + Coordinator + DI Container (하이브리드)**

```
┌─────────────────────────────────────────────────┐
│                chzzkViewApp                      │
│   @main + AppDelegate (1,224줄 단일 파일)         │
└──────────────────┬──────────────────────────────┘
                   │
     ┌─────────────▼───────────────────┐
     │         ContentView             │
     │   @StateObject: AppEnvironment  │
     │   NavigationSplitView           │
     └─────────────┬───────────────────┘
                   │
     ┌─────────────▼───────────────────┐
     │      AppEnvironment (싱글톤)     │
     │   20+ .shared 싱글톤 직접 바인딩  │
     └─────────────┬───────────────────┘
                   │
     ┌─────────────▼───────────────────┐
     │     AppCoordinator (싱글톤)      │
     │   30+ 서비스 싱글톤 직접 참조     │
     └─────────────┬───────────────────┘
                   │
     ┌─────────────▼───────────────────┐
     │    ServiceRegistry (DI 컨테이너) │
     │     NSLock + @unchecked Sendable│
     │     (실제로는 거의 사용되지 않음)  │
     └─────────────────────────────────┘
```

### 1.4 의존성 현황

| 의존성 유형 | 구현 | 사용 기술 |
|------------|------|----------|
| **외부 패키지** | VLCKitSPM (≥3.6.0) | VLC 미디어 플레이어 |
| **UI** | SwiftUI + AppKit | NavigationSplitView, NSStatusBar |
| **영속화** | CoreData + SQLite 직접 + SwiftData(미사용) + UserDefaults + Keychain | 5가지 혼용 |
| **네트워크** | URLSession | HTTP/2, Keep-Alive |
| **동시성** | async/await + Combine + GCD + Timer | 4가지 혼용 |
| **GPU** | Metal 3 | VideoToolbox, ProMotion 120Hz |
| **인증** | WKWebView 쿠키 + OAuth 하이브리드 | 네이버 로그인 |
| **동기화** | PID 제어 + AI(OpenAI/LLM) | VLC-Web 위치 동기화 |

---

## 2. 핵심 문제점 도출

### 2.1 심각도 Critical (즉시 해결 필요)

#### C1. God Object 안티패턴

| 파일 | 줄 수 | 책임 수 | SRP 위반 |
|------|-------|---------|---------|
| `ChzzkChatService.swift` | **5,326줄** | WebSocket + 인증 + 재연결 + 중재 + 메시지 배치 + 품질 모니터링 | ×6 |
| `SettingsManager.swift` | **3,706줄** | 모든 앱 설정 관리 (100+ @Published) | ×10+ |
| `UnifiedLoginManager.swift` | **2,613줄** | 쿠키 + OAuth + WebView + Keychain + 상태 관리 | ×5 |
| `ChzzkAPI.swift` | **2,335줄** | 모든 API 엔드포인트 + 캐시 + 세션 관리 | ×3 |
| `VLCPlayerEngineIntegration.swift` | **2,545줄** | VLC 래핑 + 캐치업 + 메트릭 + 상태 (40+ 프로퍼티) | ×4 |
| `chzzkViewApp.swift` | **1,224줄** | App + AppDelegate + 윈도우 관리 + 상태바 | ×4 |

**영향**: 유지보수 불가능, 코드 변경 시 의도치 않은 사이드이펙트, 테스트 작성 불가

#### C2. Singleton 과다 사용 (204개)

```
Services/ 내 "static let shared" 검색 결과: 204개소
```

- `AppEnvironment.shared`, `AppCoordinator.shared`, `SettingsManager.shared`, `UnifiedLoginManager.shared` 등
- DI 컨테이너(`ServiceRegistry`)가 존재하지만, **대부분의 코드에서 `.shared` 직접 접근**
- 결과: 전역 상태 의존성 그래프 추적 불가, 테스트 시 Mock 주입 불가

#### C3. 동시성 모델 불일치 (4가지 혼합)

| 패턴 | 사용 횟수 | Swift 6 호환 |
|------|----------|-------------|
| `@MainActor` + `async/await` | 652회 | ✅ 권장 |
| `Combine` (Publisher/Subscriber) | 다수 | ✅ 호환 |
| `DispatchQueue` (main/global/custom) | **396회** | ⚠️ 대체 필요 |
| `Timer.scheduledTimer` | **189회** | ⚠️ 대체 필요 |
| `NotificationCenter` | **153회** | ⚠️ 대체 권장 |

#### C4. `@unchecked Sendable` 남용 (16개소)

```swift
// 현재 — 실제 스레드 안전성 미보장
final class ServiceRegistry: @unchecked Sendable {
    private let lock = NSLock()  // 재진입 데드락 위험
    // ...
}
```

위치 목록:
- `ServiceRegistry`, `ServiceMultiCoreOptimizer` (7개 내부 클래스), `StatsThrottler`, `UnifiedPlayerEngineManager`, `LowLatencyHLSController`, `StreamingNetworkMonitor`, `SyncAgent`, `StreamAgent`, `UnifiedBackgroundTaskScheduler`, `UnifiedResourcePool`

#### C5. 데드락 위험 코드

```swift
// chzzkViewApp.swift L768-L784 — 앱 종료 시
func applicationWillTerminate(_ notification: Notification) {
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        Task { @MainActor in
            await UnifiedLoginManager.shared.logout()
            semaphore.signal()
        }
    }
    semaphore.wait()  // ⚠️ 메인 스레드 블로킹 + async 혼합 = 데드락 가능
}
```

#### C6. `fatalError` 프로덕션 코드 (5개소)

| 위치 | 상황 |
|------|------|
| `ServiceRegistry.resolve()` | 미등록 서비스 사`용 시 앱 크래시 |
| `chzzkViewApp` L902, L922 | SwiftData 초기화 실패 시 복구 불가 |
| `AVPlayerView.init(coder:)` | 인터페이스 빌더(미사용) 호출 시 |
| `IsolatedVLCPlayerManager.init(coder:)` | 동일 |

### 2.2 심각도 High (단기 해결 필요)

#### H1. 테스트 부재

```
538개 소스 파일에 대해 실질적 단위 테스트: 1개 (VLCOptionsMappingTests)
테스트 커버리지: ~0.2%
```

#### H2. 재연결/에러 복구 로직 분산

동일한 "재연결" 기능이 **3곳 이상**에 독립 구현:
- `ChzzkChatReconnectionManager` (채팅 전용)
- `ChzzkChatService` 내부 (자체 재연결 로직)
- `StreamReconnectionManager` (플레이어)
- `PlayerErrorRecoveryManager` (플레이어 에러 복구)
- `EnhancedErrorRecoverySystem` (고급 복구)

→ **경쟁 조건**: 복수의 매니저가 동시에 재연결 시도 시 네트워크 폭주

#### H3. 코드 중복

- `openNewPlayerWindow()` — `AppDelegate`와 `chzzkViewApp` 양쪽에 거의 동일 코드
- `showAboutWindow()` / `openLogViewer()` — 동일한 중복
- `Utilities/` vs `Utils/` — 유사 목적 폴더 2개 병존
- `Database/` vs `Services/Database/` — DB 파일 2곳 분산
- `Auth/` vs `NewAuth/` — 인증 시스템 레거시/신버전 공존
- `unifiedLoginManager`와 `loginManager`가 동일 인스턴스 참조

#### H4. SwiftLint 무력화

`.swiftlint.yml`에서 모든 핵심 규칙 비활성화:
- `line_length`, `file_length`, `type_body_length`, `function_body_length` — disabled
- `cyclomatic_complexity`, `nesting` — disabled
- `force_cast`, `force_try`, `todo` — disabled
- `unused_declaration`, `identifier_name` — disabled

→ 사실상 코드 품질 게이트 없음

#### H5. ContentView 과부하

```swift
// ContentView.swift — 25개 @State 변수
@State private var showingLoginSheet = false
@State private var showSplash = true
@State private var isSearchActive = false
@State private var searchQuery = ""
@State private var showingLogViewer = false
@State private var showSettings = false
// ... 19개 더
```

→ `ViewModel`로 상태 분리 필요

#### H6. `deinit`에서 `@MainActor` 프로퍼티 접근

```swift
// ChzzkChatService — Swift 6에서 컴파일 에러
@MainActor final class ChzzkChatService {
    deinit {
        statusCheckTimer?.invalidate()  // ⚠️ deinit은 임의 스레드에서 호출
    }
}
```

### 2.3 심각도 Medium (중기 개선)

| # | 문제 | 설명 |
|---|------|------|
| M1 | **오버엔지니어링** | AI 동기화(OpenAI + LLM + Agent) — 단순 레이턴시 동기화에 과도한 복잡성 |
| M2 | **프로토콜 미사용** | `ServiceProtocols.swift`에 6개 프로토콜 정의되었으나 4개 미구현 |
| M3 | **@Injected 비효율** | 매 접근마다 `ServiceRegistry.resolve()` + lock 획득 (lazy 캐싱 없음) |
| M4 | **AppEnvironment + AppCoordinator 역할 중복** | 둘 다 서비스 집합체 역할 수행 |
| M5 | **버전 주석 과다** | 코드 내 v12~v32 버전 태그 — VCS로 대체 필요 |
| M6 | **NSLock 재진입 위험** | `ServiceRegistry.resolve()` 내 lock 보유 중 팩토리 호출 시 데드락 |
| M7 | **100ms 폴링 루프** | LowLatencyHLS `Task.sleep(100ms)` 무한 루프 → CPU 부하 |
| M8 | **GPU 파워 하드코딩** | Metal3 GPU 버짓 30W 하드코딩 — 기기별 상이 |

### 2.4 긍정적 요소 (보존 대상)

| # | 항목 | 설명 |
|---|------|------|
| ✅ 1 | `PlayerEngineProtocol` | 잘 설계된 플레이어 추상화 계층 — chzzkView2에서 재사용 |
| ✅ 2 | PID 제어 동기화 | `PrecisionPIDController` (Kp=0.8, Ki=0.1, Kd=0.05) — 산업 수준 알고리즘 |
| ✅ 3 | HLS.js 알고리즘 포팅 | EWMA 이중 평활화, 지수적 캐치업 — 웹 검증 로직 |
| ✅ 4 | 지수 백오프 + 지터 재연결 | 네트워크 모범 사례 적용 |
| ✅ 5 | 8pt Grid 디자인 시스템 | `DesignTokens.swift` — 체계적 디자인 토큰 |
| ✅ 6 | 통합 에러 타입 | `AppError` enum + 도메인별 세분화 + `recoverySuggestion` |
| ✅ 7 | `[weak self]` 일관적 사용 | 대부분의 클로저에서 메모리 누수 방지 |
| ✅ 8 | Metal3 GPU 가속 | 성능 계층 분류, VideoToolbox Zero-Copy, ProMotion 지원 |

---

## 3. Swift 6.x 전환 필수 요구사항

### 3.1 Swift 6 Strict Concurrency Checking

Swift 6는 **complete concurrency checking**이 기본 활성화됩니다. chzzkView2는 처음부터 strict mode로 개발해야 합니다.

```swift
// Package.swift
// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "chzzkView2",
    platforms: [.macOS(.v15)],
    products: [...],
    dependencies: [...],
    targets: [
        .target(
            name: "CViewCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),        // Swift 6 strict mode
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        )
    ]
)
```

### 3.2 주요 Swift 6 변경사항 및 대응

#### 3.2.1 Global Actor Isolation

```swift
// ❌ chzzkView (현재) — DispatchQueue.main 사용
DispatchQueue.main.async {
    self.updateUI()
}

// ✅ chzzkView2 (권장) — @MainActor 격리
@MainActor
func updateUI() {
    // 이미 MainActor에서 실행 보장
}
```

#### 3.2.2 Sendable 준수

```swift
// ❌ chzzkView (현재) — @unchecked Sendable
final class ServiceRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var services: [ObjectIdentifier: Any] = [:]
}

// ✅ chzzkView2 (권장) — actor 사용
actor ServiceContainer {
    private var services: [ObjectIdentifier: Any] = [:]
    
    func register<T>(_ type: T.Type, factory: @Sendable () -> T) {
        services[ObjectIdentifier(type)] = factory()
    }
    
    func resolve<T>(_ type: T.Type) -> T? {
        services[ObjectIdentifier(type)] as? T
    }
}
```

#### 3.2.3 deinit 격리 규칙

```swift
// ❌ chzzkView (현재) — deinit에서 @MainActor 프로퍼티 접근
@MainActor final class ChatService {
    var timer: Timer?
    deinit {
        timer?.invalidate()  // ⚠️ Swift 6 에러
    }
}

// ✅ chzzkView2 (권장) — 명시적 cleanup 메서드
@MainActor final class ChatService {
    var timer: Timer?
    
    func cleanup() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        // Swift 6: deinit에서는 nonisolated 작업만 허용
    }
}
```

#### 3.2.4 Typed Throws (Swift 6.0+)

```swift
// ❌ chzzkView — untyped throws
func fetchStream() async throws -> StreamData { ... }

// ✅ chzzkView2 — typed throws
func fetchStream() async throws(NetworkError) -> StreamData { ... }

enum NetworkError: Error, Sendable {
    case timeout
    case unauthorized
    case serverError(statusCode: Int)
}
```

#### 3.2.5 Noncopyable Types (Swift 6.0+)

```swift
// ✅ 일회용 리소스에 활용
struct WebSocketConnection: ~Copyable {
    private let task: URLSessionWebSocketTask
    
    consuming func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
```

#### 3.2.6 Synchronization 모듈 (Swift 6.0+)

```swift
import Synchronization

// ✅ NSLock 대체
let counter = Atomic<Int>(0)
let state = Mutex<ChatState>(.disconnected)

// ✅ chzzkView2 ServiceContainer에서 사용
final class ServiceContainer: Sendable {
    private let storage = Mutex<[ObjectIdentifier: any Sendable]>([:])
    
    func register<T: Sendable>(_ type: T.Type, instance: T) {
        storage.withLock { $0[ObjectIdentifier(type)] = instance }
    }
    
    func resolve<T: Sendable>(_ type: T.Type) -> T? {
        storage.withLock { $0[ObjectIdentifier(type)] as? T }
    }
}
```

### 3.3 Swift 6.1 새 기능 활용

| 기능 | 적용 영역 |
|------|----------|
| **Nonisolated(unsafe) 제거** | `@unchecked Sendable` 대체 |
| **Task-local values 개선** | 요청 컨텍스트 전파 |
| **Improved diagnostics** | 컴파일 타임 동시성 에러 개선 |
| **InlineArray** | 고정 크기 버퍼 (Metal 렌더링) |
| **Span/RawSpan** | 저수준 메모리 접근 (HLS 파싱) |

---

## 4. chzzkView2 아키텍처 설계 제안

### 4.1 목표 아키텍처: Clean Architecture + Swift Concurrency Native

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                          │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  SwiftUI     │  │  ViewModels  │  │  Navigation  │              │
│  │  Views       │  │  (@Observable│  │  Router      │              │
│  │              │  │   actors)    │  │              │              │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘              │
│         │                 │                                         │
├─────────┼─────────────────┼─────────────────────────────────────────┤
│         │    Domain Layer  │                                        │
│         │                 │                                         │
│  ┌──────▼─────────────────▼───────┐  ┌─────────────────────┐       │
│  │         Use Cases              │  │    Domain Models     │       │
│  │  (stateless, actor-isolated)   │  │  (Sendable structs)  │       │
│  └──────────────┬─────────────────┘  └─────────────────────┘       │
│                 │                                                    │
├─────────────────┼────────────────────────────────────────────────────┤
│                 │     Data Layer                                     │
│                 │                                                    │
│  ┌──────────────▼──────────────┐  ┌────────────────────────┐       │
│  │    Repository Protocols     │  │   Data Sources         │       │
│  │    (async, Sendable)        │  │   - SwiftData          │       │
│  └─────────────────────────────┘  │   - URLSession         │       │
│                                    │   - WebSocket          │       │
│                                    │   - Keychain           │       │
│                                    └────────────────────────┘       │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                     Infrastructure Layer                             │
│                                                                      │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  DI        │  │  Logging     │  │  Analytics   │  │  Metal    │ │
│  │  Container │  │  System      │  │  Engine      │  │  Renderer │ │
│  │  (actor)   │  │  (OSLog)     │  │              │  │           │ │
│  └────────────┘  └──────────────┘  └──────────────┘  └───────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### 4.2 핵심 설계 원칙

| 원칙 | chzzkView (현재) | chzzkView2 (목표) |
|------|-----------------|------------------|
| **Concurrency** | 4가지 혼합 (async/await + GCD + Timer + Combine) | **Swift Concurrency 단일** (actor + async/await + AsyncSequence) |
| **DI** | ServiceRegistry + `.shared` 직접 접근 | **actor 기반 DI Container** + 프로토콜 주입 |
| **State** | 싱글톤 204개 | **SwiftUI `@Observable` + actor-isolated 서비스** |
| **Navigation** | NavigationSplitView + 하드코딩 | **NavigationStack + Type-safe Router** |
| **Data** | CoreData + SQLite + SwiftData + UserDefaults + Keychain (5종 혼용) | **SwiftData 단일** + Keychain(보안) |
| **Error** | `AppError` enum + 도메인별 세분화 | **typed throws** + `Result<T, DomainError>` |
| **Test** | ~0.2% 커버리지 | **>80% 커버리지** (Protocol 기반 Mock) |
| **Lint** | 모든 규칙 비활성화 | **strict SwiftLint + SwiftFormat** |

### 4.3 `@Observable` 매크로 기반 ViewModel (Swift 5.9+)

```swift
// ❌ chzzkView — ObservableObject + @Published 과다
class HomeViewModel: ObservableObject {
    @Published var channels: [ChannelInfo] = []
    @Published var isLoading = false
    @Published var error: Error?
    // ... 50+ @Published
}

// ✅ chzzkView2 — @Observable 매크로
@Observable
@MainActor
final class HomeViewModel {
    var channels: [ChannelInfo] = []
    var isLoading = false
    var error: (any Error)?
    
    private let fetchChannelsUseCase: FetchChannelsUseCase
    
    init(fetchChannelsUseCase: FetchChannelsUseCase) {
        self.fetchChannelsUseCase = fetchChannelsUseCase
    }
    
    func loadChannels() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            channels = try await fetchChannelsUseCase.execute()
        } catch {
            self.error = error
        }
    }
}
```

### 4.4 Type-safe Navigation Router

```swift
// ✅ chzzkView2 — enum 기반 라우팅
enum AppRoute: Hashable {
    case home
    case channel(id: String)
    case player(channelId: String, quality: StreamQuality)
    case chat(channelId: String)
    case settings
    case statistics(channelId: String)
    case vodPlayer(vodId: String)
    case clipPlayer(clipId: String)
}

@Observable
@MainActor
final class AppRouter {
    var path = NavigationPath()
    var presentedSheet: AppSheet?
    var presentedAlert: AppAlert?
    
    func navigate(to route: AppRoute) {
        path.append(route)
    }
    
    func pop() {
        path.removeLast()
    }
    
    func popToRoot() {
        path.removeLast(path.count)
    }
}
```

---

## 5. 모듈 분리 전략

### 5.1 Swift Package 기반 모듈화

```
CView_v2/
├── Package.swift
├── App/                           ← 앱 타겟 (UI + 조합)
│   └── Sources/
│       ├── CViewApp.swift
│       ├── AppRouter.swift
│       └── DependencyContainer.swift
│
├── Modules/
│   ├── CViewCore/                 ← 핵심 도메인 모델 + 유틸리티
│   │   └── Sources/
│   │       ├── Models/
│   │       ├── Protocols/
│   │       ├── Extensions/
│   │       └── DesignTokens/
│   │
│   ├── CViewNetworking/          ← 네트워크 레이어
│   │   └── Sources/
│   │       ├── ChzzkAPIClient.swift
│   │       ├── APIEndpoint.swift
│   │       ├── NetworkMonitor.swift
│   │       └── WebSocketClient.swift
│   │
│   ├── CViewChat/                ← 채팅 시스템
│   │   └── Sources/
│   │       ├── ChatEngine.swift
│   │       ├── ChatMessageParser.swift
│   │       ├── ChatReconnectionPolicy.swift
│   │       └── ChatModeration.swift
│   │
│   ├── CViewPlayer/              ← 플레이어 엔진
│   │   └── Sources/
│   │       ├── PlayerEngine/
│   │       ├── HLSEngine/
│   │       ├── VLCAdapter/
│   │       ├── SyncEngine/
│   │       └── ABRController/
│   │
│   ├── CViewAuth/                ← 인증 시스템
│   │   └── Sources/
│   │       ├── AuthManager.swift
│   │       ├── KeychainService.swift
│   │       ├── OAuthFlow.swift
│   │       └── CookieManager.swift
│   │
│   ├── CViewPersistence/        ← 데이터 영속화
│   │   └── Sources/
│   │       ├── SwiftDataStore.swift
│   │       ├── Models/
│   │       └── Migrations/
│   │
│   ├── CViewUI/                  ← 공유 UI 컴포넌트
│   │   └── Sources/
│   │       ├── Components/
│   │       ├── DesignSystem/
│   │       └── Styles/
│   │
│   └── CViewMonitoring/         ← 모니터링/메트릭
│       └── Sources/
│           ├── PerformanceMonitor.swift
│           ├── MetalRenderer.swift
│           └── AnalyticsEngine.swift
│
└── Tests/
    ├── CViewCoreTests/
    ├── CViewNetworkingTests/
    ├── CViewChatTests/
    ├── CViewPlayerTests/
    ├── CViewAuthTests/
    └── CViewPersistenceTests/
```

### 5.2 의존성 그래프

```
CViewApp
  ├── CViewCore
  ├── CViewUI          → CViewCore
  ├── CViewNetworking  → CViewCore
  ├── CViewChat        → CViewCore, CViewNetworking
  ├── CViewPlayer      → CViewCore, CViewNetworking
  ├── CViewAuth        → CViewCore, CViewNetworking
  ├── CViewPersistence → CViewCore
  └── CViewMonitoring  → CViewCore
```

**규칙**: 순환 의존성 금지. `CViewCore`는 다른 모듈에 의존하지 않음.

### 5.3 기존 코드 재배치 매핑

| chzzkView 파일/폴더 | → chzzkView2 모듈 |
|---------------------|-------------------|
| `Services/Chat/` (22파일, 10,821줄) | → `CViewChat` (5-8파일로 축소) |
| `Services/HLS/` + `Services/Player/` (48파일, 31,519줄) | → `CViewPlayer` (15-20파일) |
| `Services/Auth/` + `Services/NewAuth/` (10파일) | → `CViewAuth` (4-5파일) |
| `Services/Core/` (18파일) | → `CViewCore` + `App/` |
| `Models/` (21파일) | → `CViewCore/Models/` |
| `Database/` + `Services/Database/` (26파일) | → `CViewPersistence` (5-8파일) |
| `Views/` (~130파일) | → `App/Views/` + `CViewUI/` |
| `Services/GPU/` + `Utils/` (20파일) | → `CViewMonitoring` |
| `Services/Sync/` (13파일, 10,472줄) | → `CViewPlayer/SyncEngine/` (3-5파일로 축소) |
| `Services/Agent/` (16파일) | ⚠️ 제거 또는 대폭 축소 (오버엔지니어링) |

---

## 6. 동시성(Concurrency) 마이그레이션 가이드

### 6.1 패턴별 전환 가이드

#### Pattern 1: `DispatchQueue.main.async` → `@MainActor`

```swift
// ❌ 현재 (396개소)
DispatchQueue.main.async {
    self.isLoading = false
}

// ✅ chzzkView2
@MainActor
func updateLoadingState() {
    isLoading = false
}

// 또는 다른 actor에서 호출 시:
await MainActor.run {
    isLoading = false
}
```

#### Pattern 2: `Timer.scheduledTimer` → `AsyncTimerSequence`

```swift
// ❌ 현재 (189개소)
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    self?.checkStatus()
}

// ✅ chzzkView2 — Swift 6 Clock API
func startStatusCheck() async {
    for await _ in AsyncTimerSequence(interval: .seconds(5), clock: .continuous) {
        guard !Task.isCancelled else { break }
        await checkStatus()
    }
}

// 또는 간단한 버전:
func startStatusCheck() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        await checkStatus()
    }
}
```

#### Pattern 3: `NotificationCenter` → `AsyncStream`

```swift
// ❌ 현재 (153개소)
NotificationCenter.default.addObserver(self, selector: #selector(handleLogin),
                                       name: .loginStateChanged, object: nil)

// ✅ chzzkView2 — typed AsyncStream
extension AuthManager {
    var loginStateChanges: AsyncStream<LoginState> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await state in self.$loginState.values {
                    continuation.yield(state)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// 사용:
for await state in authManager.loginStateChanges {
    handleLoginState(state)
}
```

#### Pattern 4: `Combine Publisher` → `AsyncSequence`

```swift
// ❌ 현재 — Combine 기반 설정 감시
settingsManager.$playerQuality
    .receive(on: DispatchQueue.main)
    .sink { [weak self] quality in
        self?.updateQuality(quality)
    }
    .store(in: &cancellables)

// ✅ chzzkView2 — @Observable + AsyncSequence
@Observable
final class SettingsStore {
    var playerQuality: StreamQuality = .auto
}

// SwiftUI에서 자동 반응 (Combine 불필요):
struct PlayerView: View {
    @State var settings: SettingsStore
    
    var body: some View {
        PlayerContainerView()
            .onChange(of: settings.playerQuality) { _, newQuality in
                updateQuality(newQuality)
            }
    }
}
```

#### Pattern 5: `NSLock` / `DispatchQueue(label:)` → `actor` / `Mutex`

```swift
// ❌ 현재
final class ImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    
    func get(_ key: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }
}

// ✅ chzzkView2 — 옵션 A: actor
actor ImageCache {
    private var cache: [String: NSImage] = [:]
    
    func get(_ key: String) -> NSImage? {
        cache[key]
    }
    
    func set(_ key: String, image: NSImage) {
        cache[key] = image
    }
}

// ✅ chzzkView2 — 옵션 B: Mutex (동기 접근 필요 시)
import Synchronization

final class ImageCache: Sendable {
    private let cache = Mutex<[String: NSImage]>([:])
    
    func get(_ key: String) -> NSImage? {
        cache.withLock { $0[key] }
    }
}
```

### 6.2 WebSocket 동시성 모델

```swift
// ✅ chzzkView2 — actor 기반 WebSocket 관리
actor WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var messageStream: AsyncStream<ChatMessage>?
    
    enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }
    
    private(set) var state: State = .disconnected
    
    func connect(to url: URL) async throws {
        state = .connecting
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        state = .connected
    }
    
    var messages: AsyncStream<ChatMessage> {
        AsyncStream { continuation in
            Task {
                while let task = self.task {
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            if let parsed = ChatMessageParser.parse(text) {
                                continuation.yield(parsed)
                            }
                        case .data(let data):
                            if let parsed = ChatMessageParser.parse(data) {
                                continuation.yield(parsed)
                            }
                        @unknown default:
                            break
                        }
                    } catch {
                        continuation.finish()
                        break
                    }
                }
            }
        }
    }
}
```

---

## 7. 데이터 영속화 통합 전략

### 7.1 현재 상태 (5종 혼용)

| 기술 | 용도 | 문제 |
|------|------|------|
| CoreData (`NSPersistentContainer`) | 메인 DB | SwiftData와 중복 |
| SwiftData (`@Model`) | placeholder | 실제 미사용 |
| SQLite 직접 | 인증DB, 검색캐시, 클립DB, 팔로잉DB, 통계DB | 6개 개별 DB 파일 |
| UserDefaults | 설정값 (100+ 항목) | God Object 내 분산 |
| Keychain | 인증 토큰 | 유지 |

### 7.2 chzzkView2 통합 전략

```swift
// ✅ SwiftData 단일 사용 (macOS 15+)
import SwiftData

// 도메인 모델 정의
@Model
final class Channel {
    @Attribute(.unique) var channelId: String
    var name: String
    var imageURL: URL?
    var followerCount: Int
    var isLive: Bool
    var lastUpdated: Date
    
    @Relationship(deleteRule: .cascade)
    var statistics: [StreamStatistic]
    
    @Relationship(deleteRule: .cascade)
    var chatHistory: [ChatHistoryEntry]
    
    init(channelId: String, name: String) {
        self.channelId = channelId
        self.name = name
        self.lastUpdated = .now
    }
}

@Model
final class StreamStatistic {
    var timestamp: Date
    var viewerCount: Int
    var duration: TimeInterval
    var averageLatency: Double
    
    var channel: Channel?
}

@Model
final class UserSettings {
    @Attribute(.unique) var key: String
    var value: Data  // Codable → JSON Data
    var updatedAt: Date
}

// 설정 관리 — SwiftData + Codable 래퍼
@Observable
@MainActor
final class SettingsStore {
    private let modelContext: ModelContext
    
    // 카테고리별 분리
    var player: PlayerSettings
    var chat: ChatSettings
    var general: GeneralSettings
    var appearance: AppearanceSettings
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.player = Self.load(from: modelContext)
        self.chat = Self.load(from: modelContext)
        self.general = Self.load(from: modelContext)
        self.appearance = Self.load(from: modelContext)
    }
}

// 카테고리별 설정 (각각 독립 Codable 구조체)
struct PlayerSettings: Codable, Sendable {
    var quality: StreamQuality = .auto
    var lowLatencyMode: Bool = true
    var catchupRate: Double = 1.05
    var bufferDuration: TimeInterval = 2.0
    var preferredEngine: PlayerEngineType = .vlc
}

struct ChatSettings: Codable, Sendable {
    var fontSize: CGFloat = 14
    var showTimestamp: Bool = true
    var maxMessages: Int = 1000
    var emoticonEnabled: Bool = true
}
```

### 7.3 마이그레이션 경로

```swift
// 기존 UserDefaults → SwiftData 마이그레이션
actor SettingsMigrator {
    func migrate(to modelContext: ModelContext) async {
        let defaults = UserDefaults.standard
        
        // 기존 설정 읽기
        if let quality = defaults.string(forKey: "playerQuality") {
            // SwiftData로 저장
        }
        
        // 마이그레이션 완료 플래그
        defaults.set(true, forKey: "settings_migrated_v2")
    }
}
```

---

## 8. 네트워크 레이어 재설계

### 8.1 현재 문제

- `ChzzkAPI.swift` 단일 파일 2,335줄에 모든 API 호출
- 세션 관리, 캐시, 검색이 하나의 클래스에 혼재
- 에러 처리가 호출부마다 개별 처리

### 8.2 chzzkView2 네트워크 설계

```swift
// ✅ 엔드포인트 정의 (Type-safe)
enum ChzzkEndpoint: Sendable {
    case liveDetail(channelId: String)
    case channelInfo(channelId: String)
    case following(size: Int, page: Int)
    case search(keyword: String, type: SearchType, offset: Int)
    case chatAccessToken(chatChannelId: String)
    case liveStatus(channelId: String)
    case vodList(channelId: String, page: Int)
    case clipList(channelId: String, page: Int)
    
    var path: String {
        switch self {
        case .liveDetail(let id): "/service/v3/channels/\(id)/live-detail"
        case .channelInfo(let id): "/service/v1/channels/\(id)"
        case .following(let size, let page): "/service/v1/channels/followings?size=\(size)&page=\(page)"
        case .search(let keyword, let type, let offset): "/service/v1/search/\(type.rawValue)s?keyword=\(keyword)&offset=\(offset)&size=20"
        case .chatAccessToken(let id): "/polling/v3/channels/\(id)/access-token"
        case .liveStatus(let id): "/polling/v1/channels/\(id)/live-status"
        case .vodList(let id, let page): "/service/v3/channels/\(id)/videos?page=\(page)"
        case .clipList(let id, let page): "/service/v1/channels/\(id)/clips?page=\(page)"
        }
    }
    
    var method: HTTPMethod { .get }
    var requiresAuth: Bool {
        switch self {
        case .following, .chatAccessToken: true
        default: false
        }
    }
}

// ✅ API 클라이언트 (actor 기반)
actor ChzzkAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.chzzk.naver.com")!
    private let authProvider: AuthTokenProvider
    private let cache: ResponseCache
    
    init(authProvider: AuthTokenProvider, cache: ResponseCache = .init()) {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            "Accept": "application/json"
        ]
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.authProvider = authProvider
        self.cache = cache
    }
    
    func request<T: Decodable & Sendable>(
        _ endpoint: ChzzkEndpoint,
        as type: T.Type,
        cachePolicy: CachePolicy = .returnCacheElseLoad
    ) async throws(APIError) -> T {
        let url = baseURL.appending(path: endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        
        if endpoint.requiresAuth {
            guard let cookies = await authProvider.cookies else {
                throw .unauthorized
            }
            request.allHTTPHeaderFields?.merge(
                HTTPCookie.requestHeaderFields(with: cookies),
                uniquingKeysWith: { $1 }
            )
        }
        
        // 캐시 확인
        if case .returnCacheElseLoad = cachePolicy,
           let cached: T = await cache.get(for: endpoint) {
            return cached
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }
            
            let decoded = try JSONDecoder.chzzk.decode(
                ChzzkResponse<T>.self, from: data
            )
            
            guard let content = decoded.content else {
                throw APIError.emptyContent
            }
            
            await cache.set(content, for: endpoint)
            return content
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
}

// ✅ typed throws 에러
enum APIError: Error, Sendable {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyContent
    case decodingFailed(Error)
    case network(Error)
    case rateLimited(retryAfter: TimeInterval)
}

// ✅ 캐시
actor ResponseCache {
    private var storage: [String: CacheEntry] = [:]
    
    struct CacheEntry {
        let data: any Sendable
        let expiry: Date
    }
    
    func get<T: Sendable>(for endpoint: ChzzkEndpoint) -> T? {
        let key = endpoint.path
        guard let entry = storage[key],
              entry.expiry > .now,
              let value = entry.data as? T else {
            return nil
        }
        return value
    }
    
    func set<T: Sendable>(_ value: T, for endpoint: ChzzkEndpoint, ttl: TimeInterval = 60) {
        storage[endpoint.path] = CacheEntry(data: value, expiry: .now + ttl)
    }
}
```

---

## 9. 채팅 시스템 재설계

### 9.1 현재 문제 요약

- `ChzzkChatService.swift` 5,326줄 God Object (6+ 책임)
- 재연결 로직 2곳 중복
- WebSocket 구현 2곳 중복 (`ChzzkChatService` 내부 + `ChzzkChatWebSocketService`)
- `@objc NotificationCenter` + Combine + delegate 혼합
- `deinit`에서 `@MainActor` 프로퍼티 접근

### 9.2 chzzkView2 채팅 아키텍처

```swift
// ✅ 책임 분리된 채팅 모듈 구조

// 1. WebSocket 클라이언트 (actor)
actor ChatWebSocket {
    private var task: URLSessionWebSocketTask?
    private(set) var state: ConnectionState = .disconnected
    
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected(serverIndex: Int)
        case disconnecting
    }
    
    func connect(chatChannelId: String, accessToken: String) async throws(ChatError) {
        let serverIndex = Int.random(in: 1...5)
        let url = URL(string: "wss://kr-ss\(serverIndex).chat.naver.com/chat")!
        
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        state = .connected(serverIndex: serverIndex)
        
        // CONNECT 명령 전송
        try await sendConnect(accessToken: accessToken, chatChannelId: chatChannelId)
    }
    
    var incomingMessages: AsyncThrowingStream<WebSocketMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                while let task, state.isConnected {
                    do {
                        let message = try await task.receive()
                        continuation.yield(message)
                    } catch {
                        continuation.finish(throwing: error)
                        break
                    }
                }
                continuation.finish()
            }
        }
    }
    
    func send(_ command: ChatCommand) async throws {
        let data = try JSONEncoder().encode(command)
        try await task?.send(.data(data))
    }
    
    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .disconnected
    }
}

// 2. 메시지 파서 (stateless, Sendable)
struct ChatMessageParser: Sendable {
    static func parse(_ message: WebSocketMessage) -> ChatEvent? {
        switch message {
        case .string(let text):
            return parseJSON(text)
        case .data(let data):
            return parseJSON(data)
        @unknown default:
            return nil
        }
    }
    
    private static func parseJSON(_ text: String) -> ChatEvent? {
        guard let data = text.data(using: .utf8) else { return nil }
        return parseJSON(data)
    }
    
    private static func parseJSON(_ data: Data) -> ChatEvent? {
        try? JSONDecoder().decode(ChatEvent.self, from: data)
    }
}

// 3. 재연결 정책 (Value type, Sendable)
struct ReconnectionPolicy: Sendable {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitterFactor: Double
    
    static let `default` = ReconnectionPolicy(
        maxRetries: 5,
        baseDelay: 1.0,
        maxDelay: 45.0,
        jitterFactor: 0.3
    )
    
    func delay(for attempt: Int) -> TimeInterval {
        let exponential = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
        let jitter = exponential * jitterFactor * Double.random(in: -1...1)
        return max(0.5, exponential + jitter)
    }
}

// 4. 채팅 엔진 (통합 코디네이터, actor)
actor ChatEngine {
    private let webSocket: ChatWebSocket
    private let apiClient: ChzzkAPIClient
    private let reconnectionPolicy: ReconnectionPolicy
    
    private(set) var messages: [ChatMessage] = []
    private var reconnectAttempt = 0
    private var seenMessageKeys: Set<String> = []
    
    static let maxMessages = 1000
    static let maxSeenKeys = 5000
    
    init(
        webSocket: ChatWebSocket = ChatWebSocket(),
        apiClient: ChzzkAPIClient,
        reconnectionPolicy: ReconnectionPolicy = .default
    ) {
        self.webSocket = webSocket
        self.apiClient = apiClient
        self.reconnectionPolicy = reconnectionPolicy
    }
    
    func connect(to channelId: String) async throws {
        let token = try await apiClient.request(
            .chatAccessToken(chatChannelId: channelId),
            as: ChatAccessToken.self
        )
        
        try await webSocket.connect(
            chatChannelId: channelId,
            accessToken: token.accessToken
        )
        
        reconnectAttempt = 0
        await startMessageLoop()
    }
    
    private func startMessageLoop() async {
        for await message in webSocket.incomingMessages {
            if let event = ChatMessageParser.parse(message) {
                handleEvent(event)
            }
        } cancelledWith: { [weak self] in
            // 연결 끊김 → 재연결
            Task { await self?.attemptReconnect() }
        }
    }
    
    private func attemptReconnect() async {
        guard reconnectAttempt < reconnectionPolicy.maxRetries else { return }
        
        let delay = reconnectionPolicy.delay(for: reconnectAttempt)
        reconnectAttempt += 1
        
        try? await Task.sleep(for: .seconds(delay))
        // 재연결 시도...
    }
    
    private func handleEvent(_ event: ChatEvent) {
        switch event.type {
        case .message(let msg):
            guard !seenMessageKeys.contains(msg.id) else { return }
            seenMessageKeys.insert(msg.id)
            trimSeenKeys()
            
            messages.append(msg)
            trimMessages()
            
        case .donation(let donation):
            messages.append(donation.asMessage())
            
        case .systemMessage(let sys):
            messages.append(sys.asMessage())
            
        case .ping:
            Task { try? await webSocket.send(.pong) }
        }
    }
    
    private func trimMessages() {
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }
    
    private func trimSeenKeys() {
        if seenMessageKeys.count > Self.maxSeenKeys {
            seenMessageKeys.removeAll()
        }
    }
}

// 5. 채팅 ViewModel (UI 바인딩)
@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var connectionState: ChatWebSocket.ConnectionState = .disconnected
    var error: ChatError?
    
    private let engine: ChatEngine
    private var observationTask: Task<Void, Never>?
    
    init(engine: ChatEngine) {
        self.engine = engine
    }
    
    func connect(channelId: String) {
        observationTask = Task {
            do {
                try await engine.connect(to: channelId)
            } catch {
                self.error = error as? ChatError
            }
        }
    }
    
    func disconnect() {
        observationTask?.cancel()
    }
}
```

### 9.3 채팅 모듈 파일 구조

```
CViewChat/
├── Sources/
│   ├── Engine/
│   │   ├── ChatEngine.swift          (~200줄)
│   │   ├── ChatWebSocket.swift       (~150줄)
│   │   └── ChatMessageParser.swift   (~100줄)
│   ├── Models/
│   │   ├── ChatMessage.swift         (~80줄)
│   │   ├── ChatEvent.swift           (~60줄)
│   │   ├── ChatCommand.swift         (~50줄)
│   │   └── ChatError.swift           (~30줄)
│   ├── Policies/
│   │   ├── ReconnectionPolicy.swift  (~40줄)
│   │   └── ModerationPolicy.swift    (~60줄)
│   └── ViewModel/
│       └── ChatViewModel.swift       (~100줄)
└── Tests/
    ├── ChatEngineTests.swift
    ├── ChatMessageParserTests.swift
    ├── ReconnectionPolicyTests.swift
    └── Mocks/
        ├── MockWebSocket.swift
        └── MockAPIClient.swift
```

**총: ~870줄** (현재 10,821줄 → **87% 감소**)

---

## 10. 스트리밍/플레이어 엔진 재설계

### 10.1 현재 문제 요약

- Player/ 30파일 24,811줄, HLS/ 18파일 6,708줄
- `UnifiedLivePlayerService`가 11개 싱글톤에 의존
- VLC 어댑터 단일 파일 2,545줄 (40+ 프로퍼티)
- 재연결/복구 로직 3곳 분산
- `@preconcurrency import VLCKitSPM` — Swift Concurrency 비호환

### 10.2 chzzkView2 플레이어 아키텍처

```swift
// ✅ Protocol-Oriented Player Engine

// 핵심 프로토콜
protocol PlayerEngine: Actor {
    var state: PlayerState { get }
    var stateStream: AsyncStream<PlayerState> { get }
    
    func play(url: URL, options: PlaybackOptions) async throws(PlayerError)
    func pause() async
    func stop() async
    func seek(to position: TimeInterval) async throws(PlayerError)
    
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var bufferedDuration: TimeInterval { get }
    var playbackRate: Double { get }
    
    func setRate(_ rate: Double) async
    func setVolume(_ volume: Float) async
}

// 상태 모델 (Value type, Sendable)
struct PlayerState: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case idle
        case loading
        case buffering(progress: Double)
        case playing
        case paused
        case error(PlayerError)
        case ended
    }
    
    var phase: Phase = .idle
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferedDuration: TimeInterval = 0
    var playbackRate: Double = 1.0
    var volume: Float = 1.0
    var latency: TimeInterval?  // 라이브 스트림 전용
    var quality: StreamQuality = .auto
}

// VLC 엔진 구현 (actor)
actor VLCPlayerEngine: PlayerEngine {
    private var mediaPlayer: VLCMediaPlayer?
    private var _state = PlayerState()
    
    var state: PlayerState { _state }
    
    var stateStream: AsyncStream<PlayerState> {
        AsyncStream { continuation in
            // KVO 기반 상태 변경 감시 → continuation.yield
        }
    }
    
    func play(url: URL, options: PlaybackOptions) async throws(PlayerError) {
        let media = VLCMedia(url: url)
        configureMedia(media, options: options)
        
        mediaPlayer = VLCMediaPlayer(media: media)
        mediaPlayer?.play()
        _state.phase = .playing
    }
    
    private func configureMedia(_ media: VLCMedia, options: PlaybackOptions) {
        // HLS 저지연 옵션
        media.addOption(":network-caching=\(options.networkCaching)")
        media.addOption(":live-caching=\(options.liveCaching)")
        
        if options.lowLatency {
            media.addOption(":http-reconnect")
            media.addOption(":adaptive-use-access")
        }
    }
}

// AVPlayer 엔진 구현 (actor)
actor AVPlayerEngine: PlayerEngine {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    
    // ... 표준 AVPlayer 래핑
}

// 저지연 HLS 컨트롤러 (AsyncStream 기반)
actor LowLatencyController {
    private let engine: any PlayerEngine
    private var targetLatency: TimeInterval = 2.0
    private var monitoringTask: Task<Void, Never>?
    
    struct Metrics: Sendable {
        var currentLatency: TimeInterval
        var targetLatency: TimeInterval
        var playbackRate: Double
        var ewmaFast: Double
        var ewmaSlow: Double
    }
    
    // EWMA 이중 평활화 (HLS.js 알고리즘 포팅 — 기존 검증 로직 보존)
    private var ewmaFast = EWMACalculator(alpha: 0.3)
    private var ewmaSlow = EWMACalculator(alpha: 0.1)
    
    func startMonitoring() -> AsyncStream<Metrics> {
        AsyncStream { continuation in
            monitoringTask = Task {
                while !Task.isCancelled {
                    let metrics = await calculateMetrics()
                    await adjustPlaybackRate(basedOn: metrics)
                    continuation.yield(metrics)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
        }
    }
    
    private func calculateMetrics() async -> Metrics {
        let currentLatency = await engine.duration - await engine.currentTime
        let smoothedFast = ewmaFast.update(currentLatency)
        let smoothedSlow = ewmaSlow.update(currentLatency)
        
        return Metrics(
            currentLatency: currentLatency,
            targetLatency: targetLatency,
            playbackRate: await engine.playbackRate,
            ewmaFast: smoothedFast,
            ewmaSlow: smoothedSlow
        )
    }
    
    private func adjustPlaybackRate(basedOn metrics: Metrics) async {
        let error = metrics.currentLatency - targetLatency
        
        if error > 1.0 {
            // 큰 지연 → 적극적 캐치업
            await engine.setRate(min(1.25, 1.0 + error * 0.1))
        } else if error > 0.3 {
            // 작은 지연 → 완만한 캐치업
            await engine.setRate(1.02 + error * 0.03)
        } else {
            await engine.setRate(1.0)
        }
    }
}

// PID 동기화 엔진 (기존 검증 알고리즘 보존)
struct PIDController: Sendable {
    var kp: Double = 0.8
    var ki: Double = 0.1
    var kd: Double = 0.05
    
    private(set) var integral: Double = 0
    private(set) var previousError: Double = 0
    
    mutating func update(error: Double, deltaTime: Double) -> Double {
        integral += error * deltaTime
        integral = integral.clamped(to: -10...10)  // 적분 윈드업 방지
        
        let derivative = (error - previousError) / deltaTime
        previousError = error
        
        return kp * error + ki * integral + kd * derivative
    }
    
    mutating func reset() {
        integral = 0
        previousError = 0
    }
}
```

### 10.3 플레이어 모듈 파일 구조

```
CViewPlayer/
├── Sources/
│   ├── Engine/
│   │   ├── PlayerEngine.swift            (프로토콜 정의, ~100줄)
│   │   ├── PlayerState.swift             (상태 모델, ~80줄)
│   │   ├── VLCPlayerEngine.swift         (~400줄, 현재 2,545줄에서 축소)
│   │   ├── AVPlayerEngine.swift          (~300줄)
│   │   └── PlayerEngineFactory.swift     (~50줄)
│   ├── HLS/
│   │   ├── LowLatencyController.swift    (~250줄)
│   │   ├── HLSManifestParser.swift       (~200줄)
│   │   ├── EWMACalculator.swift          (~40줄)
│   │   └── ABRController.swift           (~200줄)
│   ├── Sync/
│   │   ├── PIDController.swift           (~80줄)
│   │   ├── SyncCoordinator.swift         (~150줄)
│   │   └── PositionComparator.swift      (~80줄)
│   ├── Recovery/
│   │   ├── ReconnectionManager.swift     (~150줄)
│   │   └── ErrorRecoveryPolicy.swift     (~100줄)
│   ├── Models/
│   │   ├── PlaybackOptions.swift         (~60줄)
│   │   ├── StreamQuality.swift           (~40줄)
│   │   └── PlayerError.swift             (~40줄)
│   └── ViewModel/
│       └── PlayerViewModel.swift         (~200줄)
└── Tests/
    ├── VLCPlayerEngineTests.swift
    ├── LowLatencyControllerTests.swift
    ├── PIDControllerTests.swift
    ├── HLSManifestParserTests.swift
    └── Mocks/
        └── MockPlayerEngine.swift
```

**총: ~2,520줄** (현재 31,519줄 → **92% 감소**)

---

## 11. 테스트 전략

### 11.1 목표 커버리지

| 레이어 | 목표 | 전략 |
|--------|------|------|
| **Domain Models** | 95%+ | 순수 값 타입 → 단순한 단위 테스트 |
| **Use Cases** | 90%+ | Protocol 기반 Mock 주입 |
| **ViewModels** | 85%+ | `@Observable` actor 테스트 |
| **Network** | 80%+ | `URLProtocol` Mock + Endpoint enum 테스트 |
| **Chat Engine** | 90%+ | WebSocket Mock + 재연결 정책 테스트 |
| **Player Engine** | 80%+ | Protocol Mock + 상태 전이 테스트 |
| **UI** | 60%+ | Snapshot 테스트 + 기본 UI 테스트 |

### 11.2 테스트 인프라 설계

```swift
// ✅ Protocol 기반 Mock 생성

// Mock API Client
actor MockAPIClient: APIClientProtocol {
    var stubbedResponses: [String: Any] = [:]
    var requestLog: [ChzzkEndpoint] = []
    
    func request<T: Decodable & Sendable>(
        _ endpoint: ChzzkEndpoint,
        as type: T.Type
    ) async throws(APIError) -> T {
        requestLog.append(endpoint)
        
        guard let response = stubbedResponses[endpoint.path] as? T else {
            throw .emptyContent
        }
        return response
    }
}

// Mock WebSocket
actor MockWebSocket {
    var sentMessages: [ChatCommand] = []
    var messageQueue: [WebSocketMessage] = []
    var shouldFailConnection = false
    
    func connect(chatChannelId: String, accessToken: String) async throws {
        if shouldFailConnection {
            throw ChatError.connectionFailed
        }
    }
    
    func enqueueMessage(_ message: WebSocketMessage) {
        messageQueue.append(message)
    }
}

// ✅ 테스트 예시

@Test("채팅 메시지 파싱 — 일반 메시지")
func testParseNormalChatMessage() {
    let json = """
    {"bdy":[{"uid":"user123","msg":"안녕하세요","msgTypeCode":1}],"cmd":93101}
    """
    let event = ChatMessageParser.parse(.string(json))
    #expect(event?.type == .message)
}

@Test("재연결 정책 — 지수 백오프")
func testReconnectionDelay() {
    let policy = ReconnectionPolicy.default
    
    let delay0 = policy.delay(for: 0)
    let delay1 = policy.delay(for: 1)
    let delay2 = policy.delay(for: 2)
    
    #expect(delay0 >= 0.5 && delay0 <= 2.0)
    #expect(delay1 >= 1.0 && delay1 <= 4.0)
    #expect(delay2 >= 2.0 && delay2 <= 8.0)
}

@Test("PID 컨트롤러 — 수렴 테스트")
func testPIDConvergence() {
    var pid = PIDController()
    var output: Double = 0
    
    for _ in 0..<100 {
        output = pid.update(error: 2.0 - output, deltaTime: 0.1)
    }
    
    #expect(abs(output - 2.0) < 0.1, "PID should converge to target")
}

@Test("HLS 매니페스트 파싱")
func testMasterPlaylistParsing() {
    let m3u8 = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=720x480
    /low/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1280x720
    /mid/index.m3u8
    """
    
    let result = HLSManifestParser.parseMasterPlaylist(m3u8)
    #expect(result.variants.count == 2)
    #expect(result.variants[0].bandwidth == 1280000)
}

@Test("EWMA 이중 평활화")
func testEWMASmoothing() {
    var fast = EWMACalculator(alpha: 0.3)
    var slow = EWMACalculator(alpha: 0.1)
    
    let values = [2.0, 2.5, 1.8, 3.0, 2.2]
    var fastResults: [Double] = []
    var slowResults: [Double] = []
    
    for v in values {
        fastResults.append(fast.update(v))
        slowResults.append(slow.update(v))
    }
    
    // Fast EWMA는 Slow보다 최근 값에 민감해야 함
    #expect(abs(fastResults.last! - 2.2) < abs(slowResults.last! - 2.2))
}
```

### 11.3 Testing 도구 체인

```swift
// Package.swift
.testTarget(
    name: "CViewCoreTests",
    dependencies: ["CViewCore"],
    swiftSettings: [
        .swiftLanguageMode(.v6)
    ]
),
// Swift Testing 프레임워크 사용 (XCTest 대체)
// swift-testing은 Swift 6에 내장
```

---

## 12. 마이그레이션 로드맵

### Phase 0: 기반 설정 (1주)

| # | 작업 | 상세 |
|---|------|------|
| 0.1 | 프로젝트 생성 | Swift Package 기반 멀티 모듈 프로젝트 |
| 0.2 | CI/CD 설정 | GitHub Actions + SwiftLint + SwiftFormat |
| 0.3 | SwiftLint 설정 | strict mode (기존과 반대) |
| 0.4 | 디자인 시스템 | `DesignTokens` 마이그레이션 (기존 코드 재사용) |
| 0.5 | DI Container | actor 기반 `ServiceContainer` 구현 |

### Phase 1: Core 모듈 (2주)

| # | 작업 | 기존 코드 참조 |
|---|------|--------------|
| 1.1 | 도메인 모델 정의 | `Models/AppModels.swift` → Sendable 구조체 |
| 1.2 | API Client | `ChzzkAPI.swift` → actor 기반 분리 |
| 1.3 | Auth 모듈 | `UnifiedLoginManager.swift` → 쿠키+OAuth 통합 |
| 1.4 | Persistence | CoreData/SQLite → SwiftData 통합 |
| 1.5 | 에러 처리 | `ErrorHandler.swift` → typed throws |
| 1.6 | 단위 테스트 | >80% 커버리지 |

### Phase 2: Chat 모듈 (1-2주)

| # | 작업 | 기존 코드 참조 |
|---|------|--------------|
| 2.1 | WebSocket Client | `ChzzkChatService.swift` 내 WS 로직 추출 |
| 2.2 | Message Parser | `ChzzkChatMessageParser.swift` 재사용 |
| 2.3 | Reconnection | 지수 백오프 + 지터 로직 재사용 |
| 2.4 | ChatEngine | actor 기반 통합 엔진 |
| 2.5 | Moderation | `ChatModerationService.swift` 간소화 |
| 2.6 | 단위 테스트 | >90% 커버리지 |

### Phase 3: Player 모듈 (2-3주)

| # | 작업 | 기존 코드 참조 |
|---|------|--------------|
| 3.1 | PlayerEngine 프로토콜 | `PlayerEngineProtocol.swift` 재설계 |
| 3.2 | VLC Engine | `VLCPlayerEngineIntegration.swift` → actor 래핑 |
| 3.3 | AVPlayer Engine | `AVPlayerOptimizer.swift` → actor 래핑 |
| 3.4 | LL-HLS Controller | `LowLatencyHLSController.swift` → AsyncStream |
| 3.5 | HLS Parser | `HLSManifestParser.swift` 재사용 |
| 3.6 | PID Sync | `PrecisionSyncEngine.swift` → 값 타입 추출 |
| 3.7 | ABR Controller | `SmartABRController.swift` 간소화 |
| 3.8 | Error Recovery | 3곳 분산 → 단일 `RecoveryPolicy` |
| 3.9 | 단위 테스트 | >80% 커버리지 |

### Phase 4: UI 레이어 (2-3주)

| # | 작업 | 설명 |
|---|------|------|
| 4.1 | AppRouter | Type-safe NavigationStack 라우팅 |
| 4.2 | HomeView | `HomeViewModel` → `@Observable` |
| 4.3 | ChatView | 채팅 UI + 이모티콘 |
| 4.4 | PlayerView | VLC/AVPlayer 통합 뷰 |
| 4.5 | SettingsView | 카테고리별 분리 (`PlayerSettings`, `ChatSettings` 등) |
| 4.6 | 통계 뷰 | 통계/분석 대시보드 |
| 4.7 | 멀티윈도우 | macOS 윈도우 관리 |

### Phase 5: 고급 기능 (1-2주)

| # | 작업 | 설명 |
|---|------|------|
| 5.1 | Metal 렌더러 | `Metal3AccelerationService` 간소화 마이그레이션 |
| 5.2 | Chrome Extension | 브릿지 재구현 |
| 5.3 | Performance | 최적화 모니터링 통합 |
| 5.4 | 앱 안정성 | 크래시 방지, 메모리 최적화 |

### Phase 6: 통합 테스트 & 릴리스 (1주)

| # | 작업 |
|---|------|
| 6.1 | 통합 테스트 |
| 6.2 | 성능 테스트 (플레이어 레이턴시, 채팅 응답 시간) |
| 6.3 | RC 빌드 |
| 6.4 | 릴리스 |

**총 예상 기간**: 8-12주

---

## 부록: 기존 코드 품질 메트릭

### A. 규모 분석

| 메트릭 | 값 |
|--------|-----|
| 총 Swift 소스 파일 | 538개 |
| Services/ 파일 수 | 270개 |
| Services/ 코드 라인 | 148,110줄 |
| 최대 단일 파일 | ChzzkChatService.swift (5,326줄) |
| 평균 파일 크기 | ~275줄 |
| 1,000줄 이상 파일 | 15개+ |

### B. 동시성 패턴 분포

| 패턴 | 사용 횟수 |
|------|----------|
| `@MainActor` | 652회 |
| `DispatchQueue` | 396회 |
| `Timer` | 189회 |
| `NotificationCenter` | 153회 |
| `static let shared` (Singleton) | 204개 |
| `@unchecked Sendable` | 16개 |
| `fatalError` | 5개 |

### C. God Object 목록

| 클래스 | 줄 수 | 추정 복잡도 |
|--------|-------|------------|
| `ChzzkChatService` | 5,326 | 극심 |
| `SettingsManager` | 3,706 | 극심 |
| `OpenAISyncService` | 2,799 | 높음 |
| `UnifiedLoginManager` | 2,613 | 높음 |
| `VLCPlayerEngineIntegration` | 2,545 | 높음 |
| `ChzzkAPI` | 2,335 | 높음 |
| `LivePlayerCoreOptimizer` | 1,800 | 높음 |
| `UnifiedLivePlayerService` | 1,703 | 높음 |
| `ExternalVLCController` | 1,713 | 높음 |
| `HLSPlayerController` | 1,437 | 중간 |
| `chzzkViewApp` | 1,224 | 중간 |
| `HomeViewModel` | 1,146 | 중간 |

### D. 기존 코드에서 보존할 검증된 알고리즘

| 알고리즘 | 출처 | 상태 |
|---------|------|------|
| EWMA 이중 평활화 (α=0.3/0.1) | HLS.js 포팅 | ✅ 검증됨 |
| 지수적 캐치업 (1.02~1.25×) | HLS.js 포팅 | ✅ 검증됨 (v28.4) |
| PID 동기화 (Kp=0.8, Ki=0.1, Kd=0.05) | 자체 구현 | ✅ 검증됨 |
| 지수 백오프 + 지터 재연결 | 네트워크 모범사례 | ✅ 검증됨 |
| PDT 기반 라이브 엣지 계산 | HLS 스펙 | ✅ 검증됨 |
| ABR 밴드폭 추정 (EWMA) | HLS.js 포팅 | ✅ 검증됨 |
| Metal3 성능 계층 분류 | 자체 구현 | ✅ 검증됨 |
| 8pt Grid 디자인 시스템 | 자체 구현 | ✅ 검증됨 |

### E. chzzkView vs chzzkView2 비교 전망

| 항목 | chzzkView | chzzkView2 (목표) |
|------|----------|-----------------|
| **파일 수** | 538 | ~80-120 |
| **총 코드량** | ~200,000줄 | ~15,000-25,000줄 |
| **God Objects** | 12개 | 0개 |
| **Singleton** | 204개 | 0개 (DI로 대체) |
| **테스트 커버리지** | ~0.2% | >80% |
| **동시성 모델** | 4가지 혼합 | Swift Concurrency 단일 |
| **데이터 저장** | 5가지 혼용 | SwiftData + Keychain |
| **최대 파일 크기** | 5,326줄 | <400줄 |
| **빌드 시간** | 미측정 (예상 10분+) | <2분 (모듈 병렬 빌드) |

---

## 참고 자료

- [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)
- [Swift Concurrency: Update a sample app](https://developer.apple.com/documentation/swift/updating-an-app-to-use-strict-concurrency)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [WWDC24: What's new in Swift](https://developer.apple.com/videos/play/wwdc2024/10136/)
- [HLS.js Latency Controller](https://github.com/video-dev/hls.js/blob/master/src/controller/latency-controller.ts)
- [Clean Architecture for SwiftUI](https://nalexn.github.io/clean-architecture-swiftui/)

---

> **문서 끝**  
> 이 문서는 chzzkView2 개발에 앞서 기존 프로젝트의 기술 부채를 정량적으로 분석하고,  
> Swift 6.x 기반의 현대적 아키텍처로 전환하기 위한 구체적인 설계 제안과 마이그레이션 전략을 제시합니다.
