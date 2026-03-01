# CView v2 종합 리서치 보고서

> **프로젝트**: CView v2 — macOS용 치지직(chzzk.naver.com) 라이브 스트리밍 뷰어  
> **분석 기준일**: 2025년  
> **코드 규모**: Swift 파일 113개 / 36,231 LOC (소스) + 806 LOC (테스트)  
> **기술 스택**: Swift 6 · macOS 15+ · SwiftUI + AppKit · SwiftData · VLCKit SPM 3.6.0 · AVFoundation

---

## 목차

1. [아키텍처 분석](#1-아키텍처-분석)
2. [기능 인벤토리](#2-기능-인벤토리)
3. [코드 품질 심층 분석](#3-코드-품질-심층-분석)
4. [성능 최적화 현황 및 제안](#4-성능-최적화-현황-및-제안)
5. [신규 기능 제안](#5-신규-기능-제안)
6. [UX/UI 개선 제안](#6-uxui-개선-제안)
7. [안정성 및 보안](#7-안정성-및-보안)
8. [기술 부채 및 리팩토링 제안](#8-기술-부채-및-리팩토링-제안)

---

## 1. 아키텍처 분석

### 1.1 모듈 아키텍처

CView v2는 **8개 라이브러리 + 1개 실행 타겟**으로 구성된 SPM 멀티 모듈 아키텍처를 채택합니다.

```
┌──────────────────────────────────────────────┐
│                  CViewApp                     │  ← 실행 타겟 (진입점)
│  (Views, ViewModels, Services, Navigation)    │
├──────────┬───────────┬───────────┬───────────┤
│ CViewUI  │ CViewAuth │CViewMonit.│ CViewPers.│  ← Feature 모듈
│ (공통UI) │ (인증)     │ (모니터링) │ (영속성)   │
├──────────┴───────────┴───────────┴───────────┤
│      CViewPlayer     │      CViewChat        │  ← Domain 모듈
│  (VLC/AV 재생 엔진)   │  (WebSocket 채팅)     │
├──────────────────────┴───────────────────────┤
│              CViewNetworking                  │  ← Infrastructure 모듈
│  (API 클라이언트, 캐시, 이미지)                 │
├──────────────────────────────────────────────┤
│                CViewCore                      │  ← Foundation 모듈
│  (모델, 프로토콜, DI, 유틸리티, 디자인 시스템)    │
└──────────────────────────────────────────────┘
```

**의존성 흐름** (Package.swift):
- `CViewCore` → 외부 의존 없음 (순수 Swift)
- `CViewNetworking` → CViewCore
- `CViewAuth` → CViewCore
- `CViewChat` → CViewCore
- `CViewPlayer` → CViewCore, CViewNetworking, vlckit-spm
- `CViewPersistence` → CViewCore (SwiftData)
- `CViewMonitoring` → CViewCore, CViewNetworking (IOKit 링크)
- `CViewUI` → CViewCore
- `CViewApp` → 전체 모듈 의존

**외부 의존성**: vlckit-spm 3.6.0 (단 1개) — 극도로 절제된 외부 의존성 정책

### 1.2 동시성 모델

Swift 6의 `.swiftLanguageMode(.v6)`를 전 모듈에 적용하며, **Strict Concurrency** 체크를 통과합니다.

| 패턴 | 적용 대상 | 근거 |
|------|-----------|------|
| `actor` | ChzzkAPIClient, ChatEngine, DataStore, StreamCoordinator, AuthManager, WebSocketService, ABRController, LowLatencyController, PerformanceMonitor, MetricsForwarder, ReconnectionPolicy 등 | 상태 보호 (data race 방지) |
| `@MainActor` | ViewModels (PlayerVM, ChatVM, HomeVM), SettingsStore, PiPController, BackgroundUpdateService | UI 바인딩 안전성 |
| `@Observable` | 모든 ViewModel, AppState, AppRouter | SwiftUI 반응형 (ObservableObject 대비 미세 갱신) |
| `@unchecked Sendable` | VLCPlayerEngine, AVPlayerEngine | VLCKit/AVFoundation 콜백 브리징 (NSLock 수동 보호) |
| `AsyncStream` | ChatEngine.events(), StreamCoordinator.events(), PerformanceMonitor, WebSocketService | 이벤트 기반 비동기 스트림 |
| `@ModelActor` | DataStore | SwiftData 전용 actor isolation |
| `Task.detached` | LocalStreamProxy, 스크린샷 저장 등 | MainActor hop 회피 |

### 1.3 DI(의존성 주입) 패턴

**ServiceContainer** (CViewCore/DI/) 기반 경량 DI:
- 프로토콜 기반 추상화: `PlayerEngineProtocol`, `APIClientProtocol`, `AuthManagerProtocol`
- `AppState` (@Observable)가 앱 수준 싱글톤 역할 (apiClient, authManager, playerVM, chatVM, homeVM, dataStore, settingsStore, metricsForwarder, performanceMonitor 보유)
- SwiftUI `@Environment(AppState.self)` + `@Environment(AppRouter.self)`로 뷰에 주입

### 1.4 네비게이션 아키텍처

`AppRouter` (@Observable): 타입 안전 네비게이션

```swift
enum AppRoute: Hashable {
    case home, live(channelId: String), search, following, settings,
         channelDetail(channelId: String), chatOnly(channelId: String),
         vod(channelId: String), clip(clipId: String, channelId: String),
         popularClips, multiChat
}
enum SidebarItem: Hashable {
    case home, following, category, search, clips, multiChat, multiLive, recentFavorites, settings
}
```

`MainContentView` → `NavigationSplitView` (사이드바 + 디테일) → `NavigationStack(path:)`

### 1.5 플레이어 아키텍처

**Dual-Engine 전략**:

```
                    PlayerViewModel
                    ┌─────────────────┐
                    │ @Observable     │
                    │ @MainActor      │
                    │                 │
                    │ preferredEngine │
                    │ streamPhase     │
                    │ latencyInfo     │
                    └───────┬─────────┘
                            │
                    StreamCoordinator (actor)
                    ┌───────┴─────────┐
                    │ ABRController   │
                    │ LowLatencyCtrl  │
                    │ PDTLatencyProv  │
                    │ PlaybackReconn  │
                    │ HLSManifestPrs │
                    │ LocalStreamPrxy│
                    └───────┬─────────┘
                            │
              ┌─────────────┴─────────────┐
        VLCPlayerEngine              AVPlayerEngine
        (저지연 특화)                 (안정성 특화)
        - VideoToolbox HW 디코딩     - AVPlayer + KVO
        - VLC 자체 HLS 파싱          - NWPathMonitor 연동
        - NSLock 기반 스레드 안전     - AccessLog 비트레이트 추적
        - 스트리밍 프로파일 전환       - LiveCatchup 프리셋
        - 스톨 워치독 (45초)          - 스톨 워치독 (45초)
```

**핵심 패턴**:
- `LocalStreamProxy` (StreamCoordinator.swift): 치지직 CDN의 Content-Type 버그(fMP4 → video/MP2T) 해결을 위한 로컬 HTTP 프록시
- `PDTLatencyProvider`: HLS `#EXT-X-PROGRAM-DATE-TIME` 파싱으로 실제 레이턴시 계산
- `ABRController`: Dual EWMA (fast α=0.5, slow α=0.1) + Hysteresis (up=1.2x, down=0.8x)
- `LowLatencyController`: PID 제어기 (Kp=0.8, Ki=0.1, Kd=0.05) 기반 재생 속도 조절

---

## 2. 기능 인벤토리

### 2.1 핵심 기능 매트릭스

| 기능 카테고리 | 기능 | 구현 파일 | LOC | 완성도 |
|------------|------|----------|-----|--------|
| **라이브 재생** | VLC/AVPlayer 듀얼 엔진 | VLCPlayerEngine.swift, AVPlayerEngine.swift | 1,513 | ★★★★★ |
| | 적응형 비트레이트 (ABR) | ABRController.swift | 229 | ★★★★☆ |
| | 저지연 동기화 (PID) | LowLatencyController.swift | 253 | ★★★★★ |
| | PDT 기반 레이턴시 측정 | PDTLatencyProvider.swift | ~150 | ★★★★☆ |
| | CDN 프록시 (Content-Type Fix) | StreamCoordinator.swift | 594 | ★★★★★ |
| | PiP (자체 구현) | PiPController.swift | 385 | ★★★★☆ |
| | 재연결 핸들러 | PlaybackReconnectionHandler.swift | ~120 | ★★★★☆ |
| | 스크린샷 | PlayerViewModel.swift | ~30 | ★★★☆☆ |
| **채팅** | WebSocket 실시간 채팅 | ChatEngine.swift, WebSocketService.swift | 766 | ★★★★★ |
| | 프로토콜 파싱 (치지직 전용) | ChatMessageParser.swift | 657 | ★★★★★ |
| | 채팅 필터/차단 | ChatModerationService.swift | ~200 | ★★★★☆ |
| | 재연결 정책 (backoff+jitter) | ReconnectionPolicy.swift | 206 | ★★★★★ |
| | 이모티콘 지원 | ChatViewModel.swift (이모티콘 팩) | ~80 | ★★★★☆ |
| | 채팅 전송 | ChatEngine.sendMessage() | ~50 | ★★★★☆ |
| **인증** | 네이버 NID 쿠키 로그인 | LoginWebView.swift, CookieManager.swift | ~300 | ★★★★☆ |
| | OAuth 2.0 로그인 | ChzzkOAuthService.swift, OAuthLoginWebView.swift | ~450 | ★★★★☆ |
| | 하이브리드 인증 (쿠키+OAuth) | AuthManager.swift | 240 | ★★★★★ |
| | Keychain 토큰 저장 | KeychainService.swift | ~100 | ★★★★☆ |
| **탐색** | 실시간 인기 라이브 | HomeView.swift, HomeViewModel.swift | 2,613 | ★★★★★ |
| | 팔로잉 채널 | FollowingView (HomeView 내) | ~200 | ★★★★☆ |
| | 채널 검색 (채널/라이브/VOD) | SearchViews.swift | 698 | ★★★★☆ |
| | 카테고리 탐색 (게임/스포츠/기타) | CategoryBrowseView.swift | 646 | ★★★★☆ |
| | 인기 클립 | PopularClipsView.swift | 903 | ★★★★☆ |
| | 채널 상세 (정보/VOD/클립) | ChannelInfoView.swift | 1,545 | ★★★★★ |
| **멀티 뷰** | 멀티라이브 (2~4채널 동시) | MultiLiveView, MultiLivePlayerPane | ~1,700 | ★★★★☆ |
| | 멀티챗 | MultiChatView.swift | ~400 | ★★★★☆ |
| **VOD/클립** | VOD 재생 | VODPlayerView.swift, VODPlayerViewModel.swift | ~800 | ★★★★☆ |
| | 클립 재생 | ClipPlayerView.swift | 682 | ★★★★☆ |
| **통계/모니터링** | 대시보드 (시청자/카테고리/분포) | DashboardCharts.swift, DashboardStatCard.swift | ~700 | ★★★★☆ |
| | 실시간 성능 모니터 | PerformanceMonitor.swift, StatisticsView.swift | ~900 | ★★★★★ |
| | GPU/CPU/메모리 메트릭 | PerformanceMonitor.swift (IOKit) | ~200 | ★★★★☆ |
| | 메트릭 서버 전송 | MetricsForwarder.swift, MetricsAPIClient.swift | ~400 | ★★★★☆ |
| **영속성** | SwiftData 저장소 | DataStore.swift | ~350 | ★★★★☆ |
| | 설정 관리 (6개 카테고리) | SettingsStore.swift | 99 | ★★★★★ |
| | 시청 기록 추적 | DataStore (WatchHistory) | ~80 | ★★★★☆ |
| | 홈 데이터 캐싱 | HomeViewModel (DataStore 캐시) | ~60 | ★★★★☆ |
| **시스템** | 메뉴바 | MenuBarView.swift | ~150 | ★★★☆☆ |
| | 알림 (스트리머 온라인) | NotificationService.swift | ~130 | ★★★★☆ |
| | 백그라운드 업데이트 | BackgroundUpdateService.swift | ~120 | ★★★★☆ |
| | 에러 복구 UI | ErrorRecoveryView.swift | 293 | ★★★★☆ |
| | 자동 새 창 (분리 재생) | CViewApp.swift (WindowGroup) | ~200 | ★★★★☆ |

### 2.2 독자적 기술 하이라이트

1. **LocalStreamProxy** (StreamCoordinator.swift L120~): 치지직 CDN이 fMP4 세그먼트를 `video/MP2T`로 서빙하는 버그 → 로컬 HTTP 프록시가 Content-Type을 수정. AVPlayer에서만 필요 (VLC는 Content-Type 무시).

2. **PID 레이턴시 컨트롤러** (LowLatencyController.swift): 산업 제어 이론의 PID 알고리즘을 라이브 스트리밍 동기화에 적용. 비례(P)·적분(I)·미분(D) 세 게인으로 재생 속도를 미세 조정해 목표 레이턴시 유지.

3. **God Object 해체** (ChatEngine.swift 주석): `ChzzkChatService` 5,326줄 → ChatEngine(428줄), ChatMessageParser(657줄), WebSocketService(338줄), ReconnectionPolicy(206줄), ChatModerationService(~200줄)로 분리. 총 5개 모듈, 각 500줄 미만.

4. **듀얼 EWMA ABR** (ABRController.swift): 빠른 응답(α=0.5)과 안정적 추세(α=0.1) 두 가지 대역폭 추정을 유지하고, 보수적으로 min()을 취해 품질 스위칭 안정성 확보.

5. **GPU 모니터링** (PerformanceMonitor.swift): IOKit `IOAccelerator PerformanceStatistics`에서 GPU Utilization, Renderer Utilization, VRAM 사용량을 실시간 수집.

---

## 3. 코드 품질 심층 분석

### 3.1 강점

#### (1) 일관된 Actor 기반 동시성 모델
모든 상태 보유 서비스가 `actor`로 선언되어 data race를 컴파일 타임에 방지합니다. Swift 6 Strict Concurrency를 전면 적용한 점은 앱 클래스 프로젝트로서 매우 선진적입니다.

**근거**: Package.swift 전 타겟 `.swiftLanguageMode(.v6)`, actor 선언 20+ 클래스

#### (2) 프로토콜 기반 추상화
- `PlayerEngineProtocol` → VLCPlayerEngine / AVPlayerEngine 교체 가능
- `APIClientProtocol` → 테스트 시 Mock 주입 가능
- `AuthManagerProtocol` → 인증 전략 교체 가능

**근거**: CViewCore/Protocols/ 디렉토리 3개 프로토콜, 각 엔진이 프로토콜 준수

#### (3) 에러 복구 체계
- `PlaybackReconnectionHandler`: 지수 백오프 (aggressive/balanced/conservative 프리셋)
- `ReconnectionPolicy`: 지수 백오프 + 지터 + 서킷 브레이커
- `ErrorRecoveryView`: 에러를 `AppErrorCategory`로 분류하여 맞춤 복구 가이드 제공
- VLCPlayerEngine: 3회 자동 재시도 + 45초 스톨 워치독

#### (4) @Observable 전면 채택
`ObservableObject` + `@Published` 대신 Swift 5.9의 `@Observable` 매크로를 사용하여:
- 프로퍼티 단위 미세 갱신 (불필요한 뷰 리렌더 감소)
- `objectWillChange` 수동 관리 불필요
- `@Bindable` 연동으로 양방향 바인딩 간결

#### (5) 주석 품질
대부분의 파일이 원본 대비 개선 내용을 한국어 주석으로 기록 (예: "원본: ChzzkChatService 직접 참조 → 개선: ChatEngine 추상화 + @Observable"). 의사결정 이유가 코드에 포함되어 유지보수성 우수.

### 3.2 개선 필요 영역

#### (1) 거대 뷰 파일 (God View 패턴)
| 파일 | LOC | 문제 |
|------|-----|------|
| HomeView.swift | 1,860 | 대시보드 + 팔로잉 + 라이브 목록 + 다수 하위 뷰 혼재 |
| ChannelInfoView.swift | 1,545 | 히어로 배너 + 탭(정보/VOD/클립) + 인라인 모델 |
| SettingsView.swift | 1,323 | 6개 설정 카테고리가 단일 파일 |
| MultiLivePlayerPane.swift | 935 | 패인 레이아웃 + 제어 + 상태 로직 혼합 |
| PopularClipsView.swift | 903 | 트렌딩 + 채널 클립 + 인라인 ViewModel |

**영향**: 코드 검색만으로 수정 지점 파악 어려움, PR 리뷰 시 diff 해석 곤란

**측정**: 1,000줄 초과 View 파일 5개, 800줄 초과 2개 추가

#### (2) 테스트 커버리지 불균형

| 테스트 모듈 | LOC | 대상 모듈 LOC | 비율(추정) |
|------------|-----|-------------|-----------|
| CViewChatTests | 288 | ~2,000 | ~14% |
| CViewPlayerTests | 240 | ~3,000 | ~8% |
| CViewCoreTests | 213 | ~3,500 | ~6% |
| CViewNetworkingTests | 45 | ~3,000 | ~1.5% |
| CViewAuthTests | 20 | ~1,300 | ~1.5% |
| **합계** | **806** | **~36,000** | **~2.2%** |

**심각도**: High — 핵심 비즈니스 로직(API 파싱, 채팅 프로토콜, ABR 알고리즘)의 테스트 부재로 리그레션 위험

#### (3) `@unchecked Sendable` 사용
VLCPlayerEngine, AVPlayerEngine 두 클래스가 `@unchecked Sendable`로 선언:
- VLCKit 콜백이 임의 스레드에서 호출되므로 `NSLock` 수동 보호
- `nonisolated(unsafe)` 정적 프로퍼티 (ChatMessageItem.timeFormatter)

**위험**: 컴파일러 검증을 우회하므로, 향후 프로퍼티 추가 시 lock 누락 가능

#### (4) 인라인 ViewModel / 모델 정의
HomeViewModel.swift 내부에 `LiveChannelItem`, `ViewerHistoryEntry`, `CategoryStat`, `ViewerBucket`, `LatencyHistoryEntry`, `CategoryTypeStat` 등 6+ 모델 정의. ChatViewModel.swift 내부에 `ChatMessageItem` 정의.

**영향**: 모델 재사용성 저하, 모듈 간 경계 모호

### 3.3 코드 메트릭 요약

| 메트릭 | 값 | 평가 |
|--------|-----|------|
| 총 소스 LOC | 36,231 | 중규모 |
| Swift 파일 수 | 113 | 적정 |
| 외부 의존성 | 1 (vlckit-spm) | **우수** |
| 평균 파일 크기 | 321 LOC | 적정 |
| 최대 파일 크기 | 1,860 LOC (HomeView) | 개선 필요 |
| 모듈 수 | 9 (8+1) | **우수** |
| Actor 클래스 수 | 20+ | **우수** |
| 테스트 LOC | 806 | **부족** |
| 테스트:소스 비율 | 1:45 | **매우 부족** |

---

## 4. 성능 최적화 현황 및 제안

### 4.1 현재 적용된 최적화

#### 재생 성능
| 최적화 | 파일 | 상세 |
|--------|------|------|
| VideoToolbox HW 디코딩 | VLCPlayerEngine.swift | `--codec=avcodec --avcodec-hw=any` VLCKit 옵션 |
| 멀티라이브 해상도/비트레이트 제한 | PlayerViewModel.swift L118~148 | AVPlayer `preferredMaximumResolution` + `preferredPeakBitRate`를 paneCount에 반비례 설정 |
| VLC 스트리밍 프로파일 분리 | VLCPlayerEngine.swift | normal(2000ms), lowLatency(1000ms), multiLiveBackground(3000ms) 캐싱 차등 |
| 백그라운드 탭 GPU 절약 | PlayerViewModel.setBackgroundMode() | AVPlayer: layer 숨기기, VLC: multiLiveBackground 프로파일 + 음소거 |
| 오디오 전용 모드 | PlayerViewModel.toggleAudioOnly() | VLC: 비디오 트랙 비활성화(디코딩 절약), AVPlayer: layer 숨기기(GPU 절약) |
| AVPlayerLayerView 최적화 | AVPlayerEngine.swift | `drawsAsynchronously=true`, `isOpaque=true`, `disableActions()` (암묵적 애니메이션 제거) |

#### 네트워크 성능
| 최적화 | 파일 | 상세 |
|--------|------|------|
| ResponseCache (TTL + LRU) | ResponseCache.swift | 최대 200항목, 만료 시 oldest 25% 제거 |
| 지수 백오프 재시도 | ChzzkAPIClient.swift | configurable maxRetries + Retry-After 헤더 준수 |
| 팔로잉 병렬 조회 | HomeViewModel.swift L690~730 | 최대 8개 동시 API 요청 (rate limit 보호) |
| 캐시 주기적 정리 | ChzzkAPIClient.swift | 5분 간격 만료 항목 정리 |
| 홈 데이터 캐싱 | HomeViewModel.swift | SwiftData에 liveChannels/allStatChannels/following 캐시 → 재실행 시 즉시 표시 |

#### UI 성능
| 최적화 | 파일 | 상세 |
|--------|------|------|
| 채팅 버퍼 제한 | ChatViewModel.trimMessageBuffer() | maxVisibleMessages(500개) 초과 시 오래된 메시지 제거 |
| @Observable 미세 갱신 | 전체 ViewModels | 프로퍼티 단위 갱신으로 불필요한 뷰 리렌더 방지 |
| SettingsStore equality 체크 | SettingsStore.load() | 동일 값 할당 시 @Observable 재평가 방지 (`if val != self.player`) |
| 설정 병렬 로드 | SettingsStore.load() | `async let` 6개 병렬 → actor hop 횟수 최소화 |
| 오디오 모드 SF Symbol 최적화 | LiveStreamView.swift | `.pulse` 이펙트 사용 (`.variableColor.iterative`는 매 프레임 GPU 드로우) |
| 링크 컬러 메모리 최적화 | DesignTokens.swift | `NSColor(dynamicProvider:)` 사용 → NSAppearance 변경 시 자동 적응 |

#### 모니터링/메트릭
| 최적화 | 파일 | 상세 |
|--------|------|------|
| 저지연 동기화 주기 축소 | LowLatencyController.swift | 0.5초 → 2.0초 (CPU 절약) |
| 메트릭 폴링 속도 분리 | HomeViewModel.swift | 활성 시 30초, 비활성 시 120초 간격 |
| 앱 비활성 시 메트릭 완속화 | HomeViewModel.pauseMetricsPolling() | 포그라운드 전환 시 즉시 1회 갱신 후 30초 복구 |

### 4.2 추가 성능 최적화 제안

#### 제안 P1: 채팅 메시지 렌더링 가상화
- **현황**: `ChatViewModel.messages` 배열에 최대 500개 메시지 저장, SwiftUI `List`/`ForEach`로 렌더링
- **문제**: 고트래픽 채팅(초당 50+)에서 SwiftUI 뷰 디프 비용 증가
- **제안**: `LazyVStack` + 윈도우 기반 가상 스크롤 적용, visible range만 `ChatMessageItem` → View 변환
- **복잡도**: Medium | **영향**: High (체감 프레임 드랍 감소)

#### 제안 P2: HLS 매니페스트 프리페칭
- **현황**: StreamCoordinator가 재생 시작 시점에 매니페스트 파싱
- **제안**: 채널 목록 호버 시 매니페스트 미리 파싱 → 재생 시작 시간 0.5~1초 단축
- **복잡도**: Medium | **영향**: Medium (체감 로딩 속도 개선)

#### 제안 P3: 이미지 캐시 디스크 계층 추가
- **현황**: `ImageCacheService`가 존재하나, 메모리 캐시 위주
- **제안**: NSCache(메모리) + 디스크 캐시(URLCache 또는 파일 시스템) 2단계 캐싱
- **복잡도**: Low | **영향**: Medium (앱 재실행 시 이미지 즉시 로드)

#### 제안 P4: VLC 인스턴스 풀링 (멀티라이브)
- **현황**: 멀티라이브에서 창 전환 시 VLCPlayerEngine 신규 생성
- **제안**: 최대 4개 VLC 인스턴스 풀 유지, 활성/비활성 전환만
- **복잡도**: High | **영향**: High (멀티라이브 전환 시 0.5~1초 절약)

---

## 5. 신규 기능 제안

### 5.1 우선순위 High

#### F1: 채팅 하이라이트 리플레이 (타임스탬프 동기화)
- **설명**: VOD 재생 시 해당 시점의 채팅을 동기 표시 (치지직 다시보기 채팅 API 활용)
- **관련 코드**: VODPlayerViewModel.swift + ChatViewModel.swift
- **구현**: VOD 재생 위치(currentTime) 변경 시 해당 구간 채팅 메시지 API 호출 → ChatViewModel에 주입
- **복잡도**: High | **영향**: High (핵심 차별화 기능)

#### F2: 키보드 단축키 커스터마이징
- **설명**: 현재 하드코딩된 키보드 단축키(Space=일시정지, M=음소거, F=풀스크린 등)를 사용자 설정 가능하게
- **관련 코드**: LiveStreamView.swift `.onKeyPress()` 핸들러
- **구현**: SettingsStore에 키맵 추가, KeyboardShortcutManager 도입
- **복잡도**: Medium | **영향**: Medium

#### F3: 스트림 녹화
- **설명**: 현재 재생 중인 스트림의 로컬 녹화 기능
- **관련 코드**: VLCPlayerEngine (VLCKit record API), AVPlayerEngine (AVAssetWriter)
- **구현**: VLC `mediaPlayer.record(toPath:)` + AVPlayer `AVAssetWriter` 파이프라인
- **복잡도**: High | **영향**: High (사용자 요청 빈번 예상)

### 5.2 우선순위 Medium

#### F4: 채널 알림 세분화
- **설명**: 현재 전체 팔로잉 on/off → 채널별 알림 설정 (방송 시작, 카테고리 변경, 제목 변경)
- **관련 코드**: NotificationService.swift, BackgroundUpdateService.swift
- **구현**: DataStore에 채널별 알림 설정 스키마 추가, BackgroundUpdateService 필터링 로직
- **복잡도**: Medium | **영향**: Medium

#### F5: 채팅 TTS (Text-to-Speech)
- **설명**: 도네이션/구독 메시지 음성 읽기
- **관련 코드**: ChatViewModel.swift (도네이션 필터링 이미 구현)
- **구현**: NSSpeechSynthesizer + 도네이션/구독 메시지 필터 → 큐 방식 TTS
- **복잡도**: Low | **영향**: Medium

#### F6: 스트림 지연 레이턴시 그래프 (실시간)
- **설명**: StatisticsView에 PDT 레이턴시의 실시간 라인 차트
- **관련 코드**: PDTLatencyProvider.swift, PerformanceMonitor.swift (latency 이력 300개)
- **구현**: Swift Charts + PerformanceMonitor 이력 데이터 연동
- **복잡도**: Low | **영향**: Medium (개발자/파워유저 대상)

### 5.3 우선순위 Low

#### F7: 다크/라이트 테마 미리보기
- **설명**: 설정의 테마 변경 시 실시간 프리뷰
- **관련 코드**: DesignTokens.swift (이미 dynamicProvider 지원), SettingsView.swift
- **복잡도**: Low | **영향**: Low

#### F8: 채팅 로그 내보내기
- **설명**: CSV/JSON 포맷으로 채팅 로그 파일 저장
- **관련 코드**: ChatViewModel.showExportSheet (이미 플래그 존재)
- **구현**: ChatMessageItem 배열 → Codable JSON 또는 CSV Formatter
- **복잡도**: Low | **영향**: Low (니치 기능)

---

## 6. UX/UI 개선 제안

### 6.1 디자인 시스템 분석

현재 `DesignTokens.swift` (337줄)에 "Minimal Monochrome" 디자인 시스템 정의:

```
색상 체계:
- 기본: backgroundDark (#0A0A0B) / backgroundMid (#111113) / backgroundLight (#1A1A1D)
- 텍스트: textPrimary (97%W) / textSecondary (60%W) / textTertiary (38%W)
- 강조: chzzkGreen (#00FFA3) — 치지직 공식 색상
- 시맨틱: liveIndicator (빨강), donationGold (금색), error/success/warning
- 보조: blue, purple, pink, orange (그래프/뱃지용)

스페이싱: 8pt 그리드 (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32)
레디어스: sm=6, md=10, lg=16
```

### 6.2 개선 제안

#### U1: 스켈레톤 로딩 UI
- **현황**: `ProgressView()`(스피너)로 로딩 표시
- **제안**: 채널 카드, 클립 썸네일 등에 Shimmer 스켈레톤 적용
- **근거**: HomeView 1,860줄 내 `isLoading` 분기에서 ProgressView 사용 다수
- **복잡도**: Low | **영향**: Medium (체감 로딩 속도 개선)

#### U2: 채팅 입력 자동완성 (이모티콘/유저 멘션)
- **현황**: ChatViewModel에 `channelEmoticons` 맵, `emoticonPickerPacks` 이미 구현
- **제안**: `:` 입력 시 이모티콘 자동완성, `@` 입력 시 최근 채팅 유저 멘션 서제스트
- **복잡도**: Medium | **영향**: High (채팅 사용성 대폭 개선)

#### U3: 드래그 앤 드롭 멀티라이브 레이아웃
- **현황**: MultiLiveView에서 고정 그리드 레이아웃 (2x2, 1+2 등)
- **제안**: 패인 드래그로 자유 배치, 비율 조정 가능
- **복잡도**: High | **영향**: Medium

#### U4: 깃허브 스타일 키보드 코맨드 팔레트 (⌘K)
- **현황**: 사이드바 네비게이션 + 검색 뷰 분리
- **제안**: ⌘K로 글로벌 검색/명령 팔레트 → 채널 검색, 설정 접근, 기능 실행
- **복잡도**: Medium | **영향**: High (파워 유저 UX)

#### U5: 반응형 사이드바 축소 모드
- **현황**: NavigationSplitView의 사이드바가 아이콘+텍스트 고정
- **제안**: 좁은 창에서 아이콘 전용 모드 자동 전환
- **복잡도**: Low | **영향**: Low

#### U6: 플레이어 오버레이 개선
- **현황**: PlayerOverlayView에 기본적인 재생 컨트롤
- **제안**: 프로그레스 바(VOD), 볼륨 슬라이더, 품질 선택 드롭다운을 인라인 오버레이로
- **복잡도**: Medium | **영향**: Medium

---

## 7. 안정성 및 보안

### 7.1 안정성 현황

#### 강점

1. **다층 재연결 체계**
   - 재생: `PlaybackReconnectionHandler` (지수 백오프, 프리셋 3종)
   - 채팅: `ReconnectionPolicy` (지수 백오프 + 지터 + 서킷 브레이커)
   - API: `ChzzkAPIClient` (자동 재시도 + 429 Rate Limit 대응)
   - 네트워크: `NetworkMonitor` (NWPathMonitor 기반 연결 감지)

2. **스톨 감지 및 복구**
   - VLCPlayerEngine: 45초 스톨 워치독 → 자동 강제 재시작
   - AVPlayerEngine: 45초 스톨 워치독 + AccessLog 기반 감지
   - 재생 에러 자동 재시도 (VLC: 3회)

3. **세션 만료 처리**
   - ChzzkAPIClient: 401 응답 → `chzzkSessionExpired` NotificationCenter 전송
   - AuthManager: 세션 만료 감지 → 자동 로그아웃 + 사용자 알림
   - OAuth 토큰 자동 갱신 시도

4. **방어적 프로그래밍**
   - VLC vout 초기화: `waitForViewMounted()` (최대 500ms 폴링) → window 미연결 상태 play() 방지
   - `setVideoView()` 호출을 play() 직전에 재바인딩 (VLC drawable 해제 버그 방어)
   - PDTLatencyProvider: 비현실적 레이턴시 필터링 (<0초 또는 >60초)

5. **에러 분류 시스템**
   - `ErrorRecoveryView`: `AppErrorCategory`(network, auth, player, data, unknown)로 분류
   - 카테고리별 맞춤 복구 가이드 UI

#### 잠재 위험

| 위험 | 위치 | 심각도 | 상세 |
|------|------|--------|------|
| VLC 메인 스레드 데드락 | VLCPlayerEngine.swift | Medium | VLC vout 조작이 메인 스레드 필수인데, actor isolation과 충돌 가능. `DispatchQueue.main.async`로 우회 중이나 복잡한 시나리오에서 데드락 가능성 |
| NSLock 순서 비일관 | VLCPlayerEngine.swift | Low | 단일 lock 사용이나, 향후 다중 lock 도입 시 순서 역전 데드락 발생 가능 |
| ChatEngine 이벤트 유실 | ChatEngine.swift | Low | AsyncStream continuation이 단일이라 다중 consumer 불가 (현재 단일 consumer 사용으로 문제 없음) |
| 무한 Task 누수 | LiveStreamView.swift | Low | onDisappear에서 Task 취소하나, 빠른 뷰 전환 시 타이밍 누수 가능 |

### 7.2 보안 현황

#### 구현된 보안 조치

1. **Keychain 토큰 저장** (KeychainService.swift)
   - OAuth access/refresh 토큰을 Keychain에 저장
   - 앱 샌드박스 내 보호

2. **CSRF 보호** (ChzzkOAuthService.swift)
   - OAuth 인증 시 `state` 파라미터로 CSRF 공격 방지
   - 콜백 URL 검증

3. **쿠키 보안** (CookieManager.swift, AuthManager.swift)
   - NID 쿠키를 WebKit HTTP Cookie Store에서 안전하게 관리
   - 로그아웃 시 쿠키 완전 삭제

4. **API 헤더 위장** (ChzzkAPIClient.swift)
   - User-Agent: Chrome 브라우저 위장
   - Referer, Origin: chzzk.naver.com 설정
   - 이는 치지직 API 사용을 위한 필수 조치

5. **앱 샌드박스** (CView_v2.entitlements)
   - macOS 앱 샌드박스 적용
   - 네트워크 접근만 허용

#### 보안 개선 제안

| 제안 | 복잡도 | 영향 |
|------|--------|------|
| **S1**: OAuth token rotation 자동화 — 현재 수동 refresh → 만료 15분 전 자동 갱신 | Low | High |
| **S2**: API 응답 무결성 검증 — JSON 디코딩 시 필드 검증 강화 (방어적 디코딩) | Medium | Medium |
| **S3**: 로그 민감 정보 마스킹 — `privacy: .public` 로그에 토큰/쿠키 노출 방지 점검 | Low | Medium |
| **S4**: Certificate Pinning — 치지직 API 도메인에 대한 SSL 핀닝 | Medium | Low |

---

## 8. 기술 부채 및 리팩토링 제안

### 8.1 기술 부채 목록

| ID | 부채 | 위치 | 심각도 | 설명 |
|----|------|------|--------|------|
| **TD1** | God View 파일 | HomeView(1860L), ChannelInfoView(1545L), SettingsView(1323L) | High | 단일 파일에 다수 하위 뷰, 일부 비즈니스 로직 혼재 |
| **TD2** | 테스트 커버리지 극히 부족 | Tests/ (806L / 36,231L = 2.2%) | High | ABR, 채팅 파싱, API 디코딩, 레이턴시 계산 등 핵심 로직 테스트 부재 |
| **TD3** | 인라인 ViewModel 모델 | HomeViewModel(6+모델), ChatViewModel(ChatMessageItem) | Medium | 모델이 ViewModel 파일 내에 정의되어 재사용성 저하 |
| **TD4** | CViewApp 엔트리포인트 비대 | CViewApp.swift (638L) | Medium | WindowGroup 5개 + 초기화 + 메뉴바 + 서비스 셋업이 단일 파일 |
| **TD5** | 하드코딩된 매직 넘버 | 곳곳 (45초 워치독, 500ms 대기, 30초 폴링 등) | Low | 설정화 또는 상수 추출 미비 |
| **TD6** | fetchFollowingChannels 위치 부적절 | HomeViewModel.swift L670 (extension ChzzkAPIClient) | Medium | ViewModel 파일에 API 클라이언트 확장 정의 → 네트워킹 모듈로 이동 필요 |
| **TD7** | AnyCodable 자체 구현 | ChatMessageParser.swift | Low | 외부 라이브러리 회피는 장점이나, edge case 처리 불완전할 수 있음 |
| **TD8** | nonisolated(unsafe) 사용 | ChatMessageItem.timeFormatter | Low | 정적 DateFormatter read-only이므로 실질적 위험 없으나, 패턴 확산 방지 필요 |

### 8.2 리팩토링 제안

#### R1: God View 분할 (우선순위: High)

**대상**: HomeView.swift (1,860L)

```
HomeView.swift (1,860L)
├── HomeView.swift (~200L)          // 루트 view + TabView/NavigationStack
├── DashboardSection.swift (~300L)  // 대시보드 통계 섹션
├── FollowingSection.swift (~200L)  // 팔로잉 라이브 목록
├── LiveChannelsGrid.swift (~250L)  // 인기 라이브 그리드
├── TopChannelsView.swift (~150L)   // 상위 채널 카드
└── MetricsServerSection.swift (~300L) // 메트릭 서버 상태
```

- **복잡도**: Medium | **영향**: High (유지보수성, PR 리뷰 효율)
- **동일 패턴 적용**: ChannelInfoView → ChannelHeroView + ChannelInfoTab + ChannelVODTab + ChannelClipTab
- **동일 패턴 적용**: SettingsView → PlayerSettingsPane + ChatSettingsPane + GeneralSettingsPane + AppearanceSettingsPane + NetworkSettingsPane + MetricsSettingsPane

#### R2: 테스트 인프라 구축 (우선순위: High)

**1단계** (Low effort, High impact): 순수 로직 단위 테스트

```
// 우선 대상 (외부 의존 없는 순수 함수/actor)
ABRController             → EWMA 계산, 품질 결정 로직
LowLatencyController      → PID 계산, 속도 결정 로직
ChatMessageParser          → JSON → ChatMessage 파싱
ReconnectionPolicy         → 딜레이 계산, 서킷 상태 전이
ResponseCache              → TTL 만료, LRU 퇴출
HLSManifestParser          → 매니페스트 파싱
```

**2단계** (Medium effort): 프로토콜 Mock 기반 통합 테스트

```
MockAPIClient             → APIClientProtocol 준수
MockPlayerEngine          → PlayerEngineProtocol 준수
→ StreamCoordinator 통합 테스트
→ HomeViewModel 데이터 로딩 테스트
→ ChatViewModel 이벤트 처리 테스트
```

**3단계** (High effort): UI 스냅샷 테스트

- **복잡도**: 1단계 Low / 2단계 Medium / 3단계 High
- **영향**: High (리그레션 방지, 리팩토링 안전망)

#### R3: 모델 독립 패키지 분리 (우선순위: Medium)

```
// HomeViewModel.swift에서 추출 → CViewCore/Models/
LiveChannelItem.swift
ViewerHistoryEntry.swift
CategoryStat.swift
ViewerBucket.swift
LatencyHistoryEntry.swift

// ChatViewModel.swift에서 추출 → CViewCore/Models/
ChatMessageItem.swift
```

- **복잡도**: Low | **영향**: Medium (재사용성, 테스트 용이성)

#### R4: AppEntry 분할 (우선순위: Medium)

```
CViewApp.swift (638L)
├── CViewApp.swift (~150L)               // @main + Scene 선언만
├── WindowDefinitions.swift (~200L)      // WindowGroup 정의
├── ServiceInitializer.swift (~150L)     // 서비스 초기화 로직
└── AppMenuCommands.swift (~100L)        // CommandMenu 정의
```

- **복잡도**: Low | **영향**: Medium

#### R5: 매직 넘버 상수화 (우선순위: Low)

```swift
// 현재 (곳곳에 산재)
try await Task.sleep(for: .seconds(45))  // 스톨 워치독
for _ in 0..<50 { ... }                  // 500ms 대기
try await Task.sleep(for: .seconds(30))  // 폴링 간격

// 제안
enum StreamConstants {
    static let stallWatchdogInterval: Duration = .seconds(45)
    static let viewMountTimeout: Duration = .milliseconds(500)
    static let liveStatusPollInterval: Duration = .seconds(30)
    static let metricsActiveInterval: Duration = .seconds(30)
    static let metricsInactiveInterval: Duration = .seconds(120)
}
```

- **복잡도**: Low | **영향**: Low (일관성, 설정 가능성)

#### R6: fetchFollowingChannels 위치 이동 (우선순위: Low)

`HomeViewModel.swift` L670~730의 `extension ChzzkAPIClient`를 `CViewNetworking/ChzzkAPIClient.swift`로 이동.

- **복잡도**: Low | **영향**: Low (모듈 경계 정리)

### 8.3 리팩토링 우선순위 로드맵

```
Phase 1 (즉시): TD2 → R2-1단계 (순수 로직 테스트 작성)
                TD3 → R3 (인라인 모델 추출)
                TD5 → R5 (매직 넘버 상수화)

Phase 2 (1~2주): TD1 → R1 (God View 분할)
                 TD4 → R4 (AppEntry 분할)
                 TD6 → R6 (API 확장 위치 이동)

Phase 3 (2~4주): TD2 → R2-2단계 (Mock 기반 통합 테스트)
                 성능 최적화 P1~P3 적용
```

---

## 부록: 아키텍처 결정 기록 (ADR) 요약

| ADR | 결정 | 근거 (코드 주석에서 추출) |
|-----|------|--------------------------|
| ADR-1 | VLCKit 유일한 외부 의존성 | macOS에서 저지연 HLS 재생에 AVFoundation의 한계 (CDN Content-Type 버그 등) |
| ADR-2 | 듀얼 플레이어 엔진 | VLC: 저지연 특화, AVPlayer: 안정성·HW 가속 최적화 → 사용자 선택 |
| ADR-3 | Actor 전면 채택 | Swift 6 strict concurrency 통과, 미래 호환성 |
| ADR-4 | @Observable > ObservableObject | 프로퍼티 단위 미세 갱신, ObjectWillChange 오버헤드 제거 |
| ADR-5 | NSPanel PiP (AVPictureInPicture 미사용) | macOS AVPiP의 제한적 커스텀 → NSPanel로 완전 제어 |
| ADR-6 | 로컬 프록시 (LocalStreamProxy) | 치지직 CDN의 fMP4 Content-Type 버그를 앱 레벨에서 투명하게 해결 |
| ADR-7 | PID 컨트롤러 레이턴시 동기화 | 단순 seek보다 부드러운 재생 속도 미세 조정으로 UX 향상 |
| ADR-8 | God Object 해체 (ChatService) | 5,326L → 5개 모듈 각 <500L, 단일 책임 원칙 |
| ADR-9 | SwiftData @ModelActor | Core Data 대비 actor isolation 네이티브 지원, Codable 제네릭 저장 |
| ADR-10 | 하이브리드 인증 (쿠키+OAuth) | 치지직 API 일부가 NID 쿠키만 지원, OAuth는 사용자 프로필/채팅 전송용 |

---

## 최종 평가 요약

| 카테고리 | 평가 | 점수 |
|----------|------|------|
| 아키텍처 | 모듈 분리 우수, 의존성 최소, 현대적 동시성 | ★★★★★ |
| 기능 완성도 | 라이브·채팅·VOD·클립·멀티뷰·모니터링 포괄 | ★★★★☆ |
| 코드 품질 | Actor 일관성, 주석 품질 우수, View 크기 개선 필요 | ★★★★☆ |
| 테스트 | 커버리지 2.2%, 심각한 부족 | ★★☆☆☆ |
| 성능 | HW 디코딩, 멀티라이브 최적화, PID 동기화 등 고급 | ★★★★★ |
| 안정성 | 다층 재연결, 스톨 감지, 에러 복구 체계 | ★★★★☆ |
| 보안 | Keychain, CSRF, 샌드박스 적용 | ★★★☆☆ |
| UX/UI | 모노크롬 디자인 시스템, 키보드 단축키 | ★★★★☆ |
| 유지보수성 | 모듈화 우수, God View 부분적 존재 | ★★★★☆ |

**총평**: CView v2는 Swift 6 Strict Concurrency를 전면 활용한 매우 현대적인 macOS 앱으로, 단일 외부 의존성(VLCKit)만으로 라이브 스트리밍에 필요한 전체 스택을 자체 구현한 점이 인상적입니다. PID 레이턴시 제어, 듀얼 EWMA ABR, IOKit GPU 모니터링 등 산업 수준의 기술을 적용했으며, 5,326줄 God Object를 5개 모듈로 분해한 리팩토링 역사가 코드 주석에 잘 기록되어 있습니다. 가장 시급한 개선 사항은 **테스트 커버리지 확충**과 **God View 분할**이며, 이 두 가지가 해결되면 프로덕션 레벨의 안정성을 확보할 수 있습니다.
