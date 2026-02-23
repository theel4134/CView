# CView v2 — 기술 구현 문서 (최종 현황 분석)

> 작성일: 2026년 2월 21일  
> 플랫폼: macOS (Swift 5.10 + SwiftUI + VLCKit-SPM)  
> 대상: 치지직(CHZZK) 비공식 클라이언트 앱

---

## 목차

1. [아키텍처 개요](#1-아키텍처-개요)
2. [모듈별 구현 현황](#2-모듈별-구현-현황)
   - 2.1 CViewApp — 진입점·AppState
   - 2.2 CViewAuth — 인증 시스템
   - 2.3 CViewNetworking — API 클라이언트
   - 2.4 CViewPlayer — 스트림 재생 엔진
   - 2.5 CViewChat — 채팅 엔진
   - 2.6 CViewUI — 이모티콘 렌더링
   - 2.7 CViewPersistence — 데이터 영속성
   - 2.8 CViewMonitoring — 성능·메트릭
3. [주요 기능 구현 상세](#3-주요-기능-구현-상세)
   - 3.1 라이브 스트림 재생
   - 3.2 채팅 시스템
   - 3.3 이모티콘 시스템
   - 3.4 멀티라이브
   - 3.5 저지연(LL-HLS) 동기화
4. [해결된 버그 이력](#4-해결된-버그-이력)
5. [현재 알려진 문제점](#5-현재-알려진-문제점)
6. [성능 최적화 이력](#6-성능-최적화-이력)
7. [기술 부채 및 개선 과제](#7-기술-부채-및-개선-과제)

---

## 1. 아키텍처 개요

### 전체 구조

```
CView_v2
├── Sources/
│   ├── CViewApp/          진입점, AppState, ViewModels, Views
│   ├── CViewAuth/         인증 (쿠키 + OAuth 하이브리드)
│   ├── CViewChat/         WebSocket 채팅 엔진
│   ├── CViewCore/         공유 모델, 프로토콜, 유틸리티
│   ├── CViewMonitoring/   성능 모니터, 메트릭 포워더
│   ├── CViewNetworking/   API 클라이언트, 캐시, 이미지
│   ├── CViewPersistence/  SwiftData 기반 영속성
│   ├── CViewPlayer/       VLC 재생 엔진, LL-HLS 동기화
│   └── CViewUI/           이모티콘 피커, 공유 UI 컴포넌트
└── Package.swift          SPM (VLCKit-SPM 의존성)
```

### 설계 원칙

| 원칙 | 적용 방식 |
|------|-----------|
| **단방향 데이터 흐름** | `@Observable AppState` → View 단방향 바인딩 |
| **Structured Concurrency** | `actor`, `async/await`, `Task`, `withTaskGroup` |
| **의존성 역전** | `PlayerEngineProtocol`, `APIClientProtocol` 인터페이스 |
| **모듈 격리** | SPM 로컬 패키지 9개로 컴파일 단위 분리 |
| **Soft Auth** | 쿠키 있으면 자동 첨부, `requiresAuth=true`일 때만 강제 |

### 멀티윈도우 구조

```
WindowGroup (메인)      ─── MainContentView → NavigationStack
WindowGroup (플레이어)  ─── LiveStreamView (isDetachedWindow = true)
WindowGroup (통계)      ─── StatisticsView
WindowGroup (채팅)      ─── ChatWindowWrapper
WindowGroup (멀티채팅)  ─── MultiChatView
Settings Scene         ─── SettingsView
MenuBarExtra           ─── MenuBarView
```

---

## 2. 모듈별 구현 현황

### 2.1 CViewApp — 진입점·AppState

**파일:** `CViewApp.swift` (607줄), `AppRouter.swift`, `PlayerViewModel.swift`, `ChatViewModel.swift`, `HomeViewModel.swift`, `MultiLiveSession.swift`

#### AppState (`@Observable @MainActor`)

앱 전역 상태를 단일 객체로 통합 관리. 다음 값을 노출:

```swift
class AppState {
    var isInitialized, isLoggedIn: Bool
    var userNickname, userChannelId: String?
    var homeViewModel: HomeViewModel?
    var chatViewModel: ChatViewModel?
    var playerViewModel: PlayerViewModel?
    var settingsStore: SettingsStore
    var multiLiveManager: MultiLiveSessionManager   // ← 탭 전환 시도 유지 (이슈 해결됨)
    let performanceMonitor: PerformanceMonitor
    var metricsForwarder: MetricsForwarder?
    private(set) var detachedChannelIds: Set<String> // 새 창 채널 추적
}
```

**초기화 순서 (4단계 지연 패턴):**
1. ViewModel 즉시 생성 (`HomeViewModel`, `ChatViewModel`, `PlayerViewModel`)
2. `isInitialized = true` → UI 즉시 렌더링
3. `Task.sleep(50ms)` → SwiftUI 첫 프레임 렌더링 대기
4. 백그라운드: `DataStore` 초기화, 로그인 상태 복원, `MetricsForwarder` 설정

#### PlayerViewModel

- **엔진 사전 생성**: `init()`에서 `VLCPlayerEngine()` 즉시 생성 → `VLCVideoView.makeNSView` 시점에 drawable 즉시 바인딩
- **streamPhase**: `.idle → .connecting → .buffering → .playing / .error`
- **멀티윈도우 지원**: `detachedChannelIds`로 새 창 재생 중인 채널 추적, `onDisappear` 시 새 창 재생 중이면 스트림 유지

**문제점:**
- PlayerViewModel이 AppState에 싱글톤으로 존재 → 멀티라이브에서 각 세션이 별도 PlayerViewModel 사용 불가 (멀티라이브는 MultiLiveSession 별도 사용)

---

### 2.2 CViewAuth — 인증 시스템

**파일:** `AuthManager.swift`, `CookieManager.swift`, `KeychainService.swift`, `ChzzkOAuthService.swift`, `LoginWebView.swift`, `OAuthLoginWebView.swift`

#### 인증 방식 (하이브리드)

```
쿠키 기반 (NID_AUT + NID_SES)   ← 주 방식 (WKWebView 로그인)
OAuth 토큰 기반                  ← 보완적 방식 (치지직 공식 OAuth)
```

#### Soft Auth 메커니즘

```swift
// ChzzkAPIClient.swift 요청 처리 로직
if let cookies = await authProvider?.cookies, !cookies.isEmpty {
    // 쿠키 있으면 requiresAuth 여부와 무관하게 항상 첨부
    attachCookies(to: &request, cookies: cookies)
} else if endpoint.requiresAuth {
    // requiresAuth=true이고 쿠키도 없을 때만 에러
    throw APIError.unauthorized
}
```

**중요:** `emoticonDeploy` 엔드포인트는 `requiresAuth = false`이지만 쿠키가 있으면 구독팩도 포함해서 반환 → 비로그인도 기본 이모티콘, 로그인 시 구독팩 자동 포함

#### 인증 상태 관리

- `AuthState`: `.loggedOut`, `.loggedIn(userId:, nickname:)`
- AsyncStream 멀티캐스트: 여러 옵저버가 동시에 상태 변화 구독 가능
- Keychain에 OAuth 토큰 영속 저장

**문제점:**
- 쿠키 세션 만료 시 자동 재로그인 미지원 (수동 재로그인 필요)
- OAuth 리프레시 토큰 갱신 로직 구현되어 있으나 실제 치지직 OAuth 환경에서 검증 미완

---

### 2.3 CViewNetworking — API 클라이언트

**파일:** `ChzzkAPIClient.swift`, `APIEndpoint.swift`, `APIResponse.swift`, `ResponseCache.swift`, `ImageCacheService.swift`, `LiveThumbnailService.swift`

#### 엔드포인트 대응 정리

| 기능 | 엔드포인트 | 인증 |
|------|-----------|------|
| 채널 정보 | `/service/v1/channels/{id}` | 없음 |
| 라이브 상세 | `/service/v3/channels/{id}/live-detail` | Soft |
| 라이브 상태 | `/polling/v1/channels/{id}/live-status` | 없음 |
| 팔로잉 목록 | `/service/v1/channels/followings` | **필수** |
| 채팅 액세스 토큰 | `/polling/v3/channels/{id}/access-token` | Soft |
| 이모티콘 배포 | `/service/v1/channels/{id}/emoticon-deploy` | Soft |
| 이모티콘 팩 상세 | `/service/v1/emoticon-packs/{packId}` | 없음 |
| 사용자 이모티콘 | `/service/v2/emoticons` | **필수** |
| 기본 이모티콘팩 | `/service/v1/emoticons` | — (404, 미사용) |
| 사용자 상태 | `/service/v1/users/me` | **필수** |

#### 캐시 정책

```swift
enum CachePolicy {
    case reloadIgnoringCache       // 라이브 상태, 채팅 토큰
    case returnCacheElseLoad(ttl:) // 채널 정보(300s), 기타(60s)
}
```

**`ResponseCache`**: 메모리 기반 TTL 캐시. URLSession 기본 캐시와 별도 운영.

#### 중요 메서드

```swift
// 이모티콘 관련
func basicEmoticonPacks(channelId: String) async -> [EmoticonPack]
    // emoticonDeploy 래퍼 — 비로그인=기본팩, 로그인=기본+구독팩

func resolveEmoticonPacks(_ packs: [EmoticonPack]) async -> (emoMap: [String:String], packs: [EmoticonPack])
    // withTaskGroup으로 빈 팩 상세 조회를 병렬 실행
```

**문제점:**
- `/service/v1/emoticons` 404 → 기본 이모티콘팩 직접 조회 불가 (에피소드 현재는 `emoticonDeploy`로 우회)
- API 응답 구조 변경에 대한 방어 코드 미흡 (옵셔널 처리 일부 누락)

---

### 2.4 CViewPlayer — 스트림 재생 엔진

**파일:** `VLCPlayerEngine.swift`, `VLCVideoView.swift`, `StreamCoordinator.swift`, `LowLatencyController.swift`, `PDTLatencyProvider.swift`, `LocalStreamProxy.swift`, `HLSManifestParser.swift`, `ABRController.swift`

#### 재생 파이프라인

```
liveDetail API → livePlaybackJSON 파싱 → HLS URL 추출
                                               ↓
LocalStreamProxy.needsProxy() 판단
├── CDN 호스트 → localhost 프록시로 우회 (Content-Type 버그 대응)
└── 정상 CDN → 직접 연결
                ↓
VLCPlayerEngine.play(url:) [MainActor]
├── player.setVideoView(playerView)
├── player.media = VLCMedia(url:)
└── player.play()
```

#### CDN Content-Type 버그

- **현상:** `ex-nlive-streaming.navercdn.com`이 fMP4(HLS-CMAF)를 `video/MP2T`로 잘못 응답
- **결과:** VLC adaptive demux 파싱 실패 → 재생 불가
- **해결:** `LocalStreamProxy` — localhost HTTP 서버를 통해 Content-Type 헤더를 `video/mp4`로 교체 후 VLC에 전달

#### VLCVideoView (NSViewRepresentable)

```
NSView (container)
└── VLCPlayerEngine.playerView (VLCKitSPM.VLCVideoView 서브뷰)
    └── Auto Layout으로 container 전체 채움
```

- **엔진 교체 지원:** `updateNSView`에서 `coordinator.boundEngine`을 비교해 동일 엔진이면 재삽입 스킵
- `makeNSView` 시점에 drawable 연결 → `play()` 전 `setVideoView` 재확인으로 vout 초기화 보장

#### VLCStreamingProfile

| 프로파일 | networkCaching | liveCaching | 용도 |
|----------|---------------|-------------|------|
| `.normal` | 1500ms | 1000ms | 일반 재생 |
| `.lowLatency` | 400ms | 200ms | 라이브 저지연 |
| `.multiLiveBackground` | 800ms | 500ms | 멀티라이브 탭 백그라운드 |

---

### 2.5 CViewChat — 채팅 엔진

**파일:** `ChatEngine.swift`, `WebSocketService.swift`, `ChatMessageParser.swift`, `ChatModerationService.swift`, `ReconnectionPolicy.swift`

#### 채팅 서버 연결

```
chatChannelId UTF-8 바이트 합 % 9 + 1 = 서버 번호(1~9)
→ wss://kr-ss{N}.chat.naver.com/chat
```

#### 메시지 타입 처리

| 타입 | 설명 |
|------|------|
| `CHAT` | 일반 텍스트 채팅 |
| `DONATION` | 후원 메시지 |
| `SUBSCRIPTION` | 구독 알림 |
| `EMOTICON` | `{:id:}` 형식 이모티콘 |
| `SYSTEM_MESSAGE` | 입장/퇴장 등 시스템 |
| `PIN` | 핀 메시지 |

#### 재연결 전략 (`ReconnectionPolicy`)

- Exponential backoff: 1, 2, 4, 8 ... 최대 60초
- 최대 재시도 횟수 설정 가능
- `isManualDisconnect` 플래그로 의도적 종료 시 재연결 억제

#### ChatViewModel

- `@Observable @MainActor`
- 자동 스크롤 / 수동 스크롤 감지 (`scrolledToBottom`)
- 메시지 버퍼 최대 500개
- 키워드 필터링: 포함/제외 키워드, 사용자 차단 목록

**문제점:**
- 채팅 전송 시 `extraToken` 없으면 SEND 권한 부재 → 에러 처리만 있고 사용자 안내 미흡
- 이모티콘 포함 메시지 전송 시 `emojis` dict 구성 로직이 ChatPanelView에 분산

---

### 2.6 CViewUI — 이모티콘 렌더링

**파일:** `EmoticonViews.swift`, `EmoticonPickerView.swift`, `CachedAsyncImage.swift`

#### `{:id:}` 파싱 파이프라인

```
ChatMessage.content (String)
    ↓ ChatContentRenderer
텍스트를 토큰으로 분리: Text | Emoticon({:id:})
    ↓ EmoticonView
channelEmoticons[id] → URL → CachedAsyncImage → NSImageView
```

#### EmoticonPickerView

- ChatPanelView 하단에 토글로 표시
- `emoticonPacks` 배열 기반 탭 뷰
- 이모티콘 탭 → `ChatPanelView`에서 텍스트필드에 `{:id:}` 삽입

#### CachedAsyncImage

- `ImageCacheService.shared` 메모리+디스크 캐시 활용
- placeholder: 회색 라운드렉트 (애니메이션 없음)

---

### 2.7 CViewPersistence — 데이터 영속성

**파일:** `DataStore.swift`, `SettingsStore.swift`, `PersistectedChannel.swift`, `WatchHistory.swift`

#### 저장 데이터

| 데이터 | 저장 방식 | 설명 |
|--------|-----------|------|
| 즐겨찾기 채널 | SwiftData | `PersistedChannel` |
| 시청 기록 | SwiftData | `WatchHistory` |
| 앱 설정 | UserDefaults (`@AppStorage`) | `SettingsStore` |

#### SettingsStore

```swift
struct PlayerSettings { volumeLevel, lowLatencyMode, catchupRate, audioOnlyMode }
struct ChatSettings { fontSize, showBadge, maxMessages, filterKeywords, blockedUsers }
struct AppSettings { theme, notificationsEnabled, autoRefreshInterval }
```

---

### 2.8 CViewMonitoring — 성능·메트릭

**파일:** `PerformanceMonitor.swift`, `MetricsForwarder.swift`, `MetricsAPIClient.swift`, `MetricsWebSocketClient.swift`

#### PerformanceMonitor

- CPU 사용률, 메모리 사용량, FPS 측정 (0.5초 간격)
- `PerformanceOverlayView`로 화면 우상단 표시 (디버그 전용)

#### MetricsForwarder

- 시청 채널 활성화/비활성화 이벤트를 외부 서버로 전송
- `isEnabled = false`이면 전송 스킵 (사용자 설정)
- `activateChannel()` / `deactivateCurrentChannel()`

---

## 3. 주요 기능 구현 상세

### 3.1 라이브 스트림 재생

#### 현재 로딩 순서 (최적화 후)

```
startStreamAndChat() 호출
    │
    ├─ [await] liveDetail API          (~400ms, 블로킹 필요)
    │    └─ URL 파싱 완료
    │
    ├─ [Task] playerVM.startStream()   (80ms sleep 후 VLC play, 비동기)
    │    └─ isLoadingStream = false ←── 즉시 로딩 오버레이 해제
    │
    ├─ [Task] metricsForwarder.activateChannel()   (fire-and-forget)
    ├─ [Task] recordWatch()                         (fire-and-forget)
    │
    └─ [Task] 채팅 준비 (백그라운드, 영상과 완전 병렬)
          ├─ [동시] chatAccessToken
          ├─ [동시] userStatus
          └─ [동시] basicEmoticonPacks
               └─ resolveEmoticonPacks (withTaskGroup, 팩 병렬)
                    └─ chatVM.connect()
```

#### VLC vout 초기화 보장 메커니즘

1. `PlayerViewModel.init()`에서 `VLCPlayerEngine()` 사전 생성
2. `VLCVideoView.makeNSView`에서 `engine.playerView`를 container에 서브뷰 즉시 삽입
3. `play()` 직전 `MainActor`에서 `player.setVideoView(playerView)` 재확인
4. 80ms sleep으로 SwiftUI 레이아웃 패스 완료 대기

---

### 3.2 채팅 시스템

#### 채팅 연결 흐름

```
chatAccessToken API → ChatEngine.Configuration 생성
    → WebSocketService 연결
    → CONNECT 핸드셰이크 (NID 쿠키 + UID)
    → OPEN_CHANNEL 요청
    → 메시지 수신 루프 시작
    → 자동 재연결 (네트워크 단절 시)
```

#### 채팅 전송 조건

- 로그인 상태 (`isLoggedIn = true`)
- `extraToken` 보유 (SEND 권한 부여)
- WebSocket 연결 상태

#### 키워드 필터링

- `포함 키워드`: 해당 키워드가 있는 메시지만 표시
- `제외 키워드`: 해당 키워드가 있는 메시지 숨김
- `차단 사용자`: 특정 UID의 메시지 완전 숨김

---

### 3.3 이모티콘 시스템

#### 이모티콘 로딩 전략

```
basicEmoticonPacks(channelId:)
    ├─ emoticonDeploy(channelId:) 호출 (Soft Auth)
    │    ├─ 쿠키 없음: 채널 기본 이모티콘 팩만
    │    └─ 쿠키 있음: 기본 + 구독팩 + 개인화팩 포함
    └─ 빈 팩은 withTaskGroup으로 상세 조회 병렬 실행
```

#### 이모티콘 팩 구조

```swift
EmoticonPack {
    emoticonPackId: String
    emoticonPackName: String
    emoticons: [Emoticon]?   // nil이면 상세 API 호출 필요
}

Emoticon {
    emoticonId: String       // {: 와 :} 사이 ID
    emoticonName: String
    imageURL: URL?
}
```

#### 알려진 제약

- `/service/v1/emoticons` — 404 (치지직 서버에 해당 경로 없음)
- 이모티콘 이미지 캐시 만료 주기: 앱 실행 중 영구 (세션 종료 시 초기화)

---

### 3.4 멀티라이브

#### 세션 수명 주기

```
addSession(channelId:) → MultiLiveSession(channelId:)
    → sessions.append()
    → selectedSessionId = session.id
    → [SwiftUI .task] session.start(using:appState:) 호출
         → liveDetail API
         → [await] playerVM.startStream()
         → loadState = .playing  ← 즉시 (채팅 준비와 무관)
         → [Task] 채팅 준비 (백그라운드)
         → startPolling() (60초 간격 오프라인 감지)
```

#### 탭 전환 시 상태 유지 (버그 해결됨)

- **원인:** `MultiLiveView`의 `@State private var manager` → View 재생성 시 새 인스턴스
- **해결:** `AppState.multiLiveManager`로 이전 → `let manager = appState.multiLiveManager` 공유

#### 탭 전환 시 세션 유지 (버그 해결됨)

- **원인:** `.onDisappear { Task { await manager.stopAll() } }`
- **해결:** `.onDisappear`의 `stopAll()` 제거 → 탭 전환 시 세션 그대로 유지

#### 백그라운드 세션 처리

- `setBackgroundMode(true)`: VLC streamingProfile → `.multiLiveBackground` (CPU 절약)
- 포그라운드 복귀 시 `.lowLatency` 복원

#### 최대 세션 수

```swift
static let maxSessions = 4  // 2×2 그리드 레이아웃 기준
```

---

### 3.5 저지연(LL-HLS) 동기화

#### 동기화 방식

```
PDT(Program Date Time) 기반 (Method A, 우선)
    ├─ 마스터 플레이리스트 fetch → 미디어 플레이리스트 URL 추출
    ├─ PDTLatencyProvider: HLS 세그먼트의 #EXT-X-PROGRAM-DATE-TIME으로 실제 레이턴시 계산
    └─ LowLatencyController.startSync()에 레이턴시 콜백 주입

VLC 버퍼 기반 (Fallback, Method B)
    └─ duration - currentTime ≈ 버퍼 크기 ≈ 레이턴시 근사
```

#### PID 제어기

```swift
// LowLatencyController Default 설정
targetLatency: 3.0초
maxPlaybackRate: 1.15  (레이턴시 클 때 15% 빠르게 재생)
minPlaybackRate: 0.9   (레이턴시 작을 때 10% 느리게 재생)
pidKp: 0.8, pidKi: 0.1, pidKd: 0.05
```

#### 최적화 이력 (현재 적용됨)

```swift
// 이전: startStream() 전체를 블로킹 (최대 6초)
await startLowLatencySync()

// 현재: fire-and-forget (play() 즉시 반환)
Task { [weak self] in await self?.startLowLatencySync() }
```

---

## 4. 해결된 버그 이력

| # | 증상 | 원인 | 해결 |
|---|------|------|------|
| 1 | 이모티콘 피커 비어있음 | `emoticonDeploy requiresAuth=true` → 미로그인 시 unauthorized | Soft Auth로 변경 |
| 2 | `/service/v1/emoticons` 404 | 해당 경로 치지직에 없음 | `emoticonDeploy` 기반 `basicEmoticonPacks(channelId:)`로 대체 |
| 3 | 멀티라이브 탭 전환 시 채널 목록 초기화 | `MultiLiveView`의 `@State var manager` → 재생성 로직 | `AppState.multiLiveManager`로 이전 |
| 4 | 멀티라이브 탭 복귀 시 빈 목록 | `.onDisappear`에서 `stopAll()` 호출 → `sessions.removeAll()` | `stopAll()` 제거 |
| 5 | 라이브 로딩 화면 6초 이상 표시 | `startLowLatencySync()` PDT 안정화 6초 루프가 `startStream()` 블로킹 | `Task { }` fire-and-forget으로 분리 |
| 6 | VLC 검은 화면 | `play()` 이전 drawable 미설정 (타이밍 경쟁) | `makeNSView` 즉시 삽입 + `play()` 직전 `setVideoView(playerView)` 재확인 |
| 7 | 채팅 연결 후 닉네임 미설정 | `userStatus` 2회 호출 (uid용 + nickname용), 기존 1회용 nil 처리 | 단일 `userStatus` 호출로 uid + nickname 동시 처리 |

---

## 5. 현재 알려진 문제점

### 5.1 인증 / 보안

| 문제 | 심각도 | 상세 |
|------|--------|------|
| 쿠키 만료 시 자동 재로그인 없음 | 중 | 세션 만료 시 로딩 실패 후 수동 재로그인 필요 |
| OAuth 리프레시 검증 미완 | 낮 | 실운영 OAuth 환경 테스트 부재 |
| 쿠키 저장소 암호화 | 낮 | Keychain 저장이 아닌 WKWebView 쿠키 저장소 사용 |

### 5.2 플레이어

| 문제 | 심각도 | 상세 |
|------|--------|------|
| VLC DEBUG 로깅 항상 활성 | 낮 | `#if DEBUG`로 감쌌으나 `/tmp/vlc_internal.log` 매 실행마다 생성 |
| 15초 후 진단 코드 상시 실행 | 낮 | `play()` 내 `Task { sleep(15s) ... }` 릴리즈 시 불필요 |
| 다중 Player 창 볼륨 동기화 없음 | 중 | 메인 창과 분리 창의 볼륨이 독립적으로 동작 |
| LocalStreamProxy 포트 충돌 가능 | 낮 | 고정 포트 사용 시 이미 사용 중인 포트 충돌 위험 |

### 5.3 채팅

| 문제 | 심각도 | 상세 |
|------|--------|------|
| 채팅 전송 불가 시 사용자 안내 없음 | 중 | `extraToken` 없으면 silently fail |
| 이모티콘 포함 전송 로직 분산 | 낮 | `emojis` dict 구성이 View 레이어에 있음 |
| 채팅 스크롤 성능 | 낮 | 500개 초과 시 오래된 메시지 제거 로직 있으나 List 리렌더링 비용 검증 미완 |

### 5.4 멀티라이브

| 문제 | 심각도 | 상세 |
|------|--------|------|
| `MultiLiveView.swift` 1445줄 | 중 | 단일 파일에 모든 UI 컴포넌트 포함, 유지보수 어려움 |
| 4개 세션 동시 재생 시 CPU/메모리 | 중 | 백그라운드 프로파일로 완화하나 실기기 실측 미완 |
| 팔로잉 채널 새로고침 상태 표시 버그 | 낮 | 새로고침 아이콘 rotationEffect 로직 중복 |

### 5.5 이모티콘

| 문제 | 심각도 | 상세 |
|------|--------|------|
| 이모티콘 캐시 세션 종료 시 초기화 | 낮 | 앱 재실행 시 재다운로드 필요 |
| 이모티콘 팩 로딩 실패 시 재시도 없음 | 낮 | `try?`로 무시 후 빈 맵 반환 |
| 기본 이모티콘팩 직접 경로 없음 | 중 | `/service/v1/emoticons` 404 → `emoticonDeploy` 우회 시 channelId 필요 (채팅 전용 뷰에서 문제 없음) |

---

## 6. 성능 최적화 이력

### 6.1 API 병렬화

**이전 (완전 직렬):**
```
chatToken(300ms) → userStatus(200ms) → basicEmoticonPacks(500ms)
→ resolveEmoticonPacks(팩N × 200ms 순차) = 총 1000ms+
```

**현재 (병렬):**
```
┌─ chatToken(300ms)
├─ userStatus(200ms)        → 동시에 실행
└─ basicEmoticonPacks(500ms)
        └─ resolveEmoticonPacks: withTaskGroup (팩 N개 동시)
= max(300, 200, 500ms) ≈ 500ms
```

**개선율:** 약 50~70% 단축

### 6.2 로딩 오버레이 해제 시점

| 시점 | 이전 | 현재 |
|------|------|------|
| `isLoadingStream = false` | 채팅 connect 완료 후 | VLC Task 발사 직후 |
| `loadState = .playing` (멀티라이브) | 채팅 connect 완료 후 | `startStream()` 완료 직후 |
| PDT 동기화 차단 | startStream() 블로킹 6초 | fire-and-forget |
| 체감 첫 화면 표시 시간 | **6~8초** | **1.5~2.5초** |

### 6.3 `resolveEmoticonPacks` 병렬화

```swift
// 이전: 순차
for pack in packs {
    if let detail = try? await emoticonPack(packId: pack.emoticonPackId) { ... }
}

// 현재: withTaskGroup 병렬
await withTaskGroup(of: EmoticonPack?.self) { group in
    for pack in packs {
        group.addTask { try? await self.emoticonPack(packId: pack.emoticonPackId) }
    }
    ...
}
```

### 6.4 VLC sleep 단축

- `Task.sleep(200ms)` → `Task.sleep(80ms)` (play() 내부 setVideoView 명시 호출로 drawable 보장)

---

## 7. 기술 부채 및 개선 과제

### 우선순위 높음

1. **`MultiLiveView.swift` 분리** (1445줄)
   - `MLPlayerPane`, `MLSidebar`, `MLAddChannelSheet` 등 별도 파일로 분리 권장

2. **릴리즈 빌드 정리**
   - VLC DEBUG 로그 (`/tmp/vlc_internal.log`) 제거
   - `play()` 내 15초 후 진단 코드 제거 또는 `#if DEBUG` 격리

3. **쿠키 만료 자동 처리**
   - API 401 응답 시 자동 재로그인 플로우 구현 필요

### 우선순위 보통

4. **이모티콘 캐시 영속화**
   - 이미지 URL → 로컬 파일 캐시, 앱 재실행 시 재다운로드 방지

5. **채팅 전송 불가 UX 개선**
   - extraToken 없을 시 "로그인 후 채팅 가능" 명확한 UI 표시

6. **멀티라이브 세션 수 설정화**
   - `maxSessions = 4` 하드코딩 → 설정에서 조정 가능하게

7. **ABRController 활성화**
   - `ABRController.swift` 구현됨, StreamCoordinator에서 권장 화질 반영 미완

### 우선순위 낮음

8. **VOD/클립 기능 검증**
   - `ClipPlayerView`, `VODPlayerView`가 구현되어 있으나 실제 시청 경험 점검 미완

9. **백그라운드 업데이트 서비스**
   - `BackgroundUpdateService`가 구조만 존재, 팔로잉 신규 라이브 알림 실도작 검증 필요

10. **단위 테스트 범위 확대**
    - `Tests/` 하위 5개 테스트 타겟 존재하나 실제 커버리지 미측정

---

## 부록: 의존성

| 라이브러리 | 버전 | 용도 |
|-----------|------|------|
| VLCKit-SPM | GitHub 최신 | HLS 스트림 재생 |
| SwiftData | Apple 내장 | 채널/시청기록 영속 |
| Swift Concurrency | 내장 | actor, async/await |

**외부 API:**
- 치지직 비공식 API (`api.chzzk.naver.com`)
- 치지직 채팅 WebSocket (`kr-ss{N}.chat.naver.com`)
- 치지직 OAuth 2.0 (`chzzk.naver.com/oauth2/...`)

---

*이 문서는 현재 구현 상태를 기준으로 작성되었습니다. API 변경 또는 기능 추가 시 갱신이 필요합니다.*
