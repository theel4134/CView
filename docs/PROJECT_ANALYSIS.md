# CView v2 — 프로젝트 정밀 분석 문서

> **분석 일자**: 2025년 7월 (최종 갱신)  
> **프로젝트**: CView v2 (chzzkView 차세대 재설계)  
> **플랫폼**: macOS 15+ (네이티브 SwiftUI)  
> **언어**: Swift 6 (Strict Concurrency)  
> **외부 의존성**: VLCKitSPM (1개)

---

## 1. 프로젝트 개요

CView v2는 네이버 **치지직(Chzzk)** 라이브 스트리밍 플랫폼 전용 macOS 데스크탑 뷰어입니다.  
웹 브라우저 대비 저지연 재생, 멀티라이브 동시 시청, 고급 플레이어 제어, 실시간 성능 모니터링 등  
전문 시청자를 위한 기능을 제공합니다.

### 핵심 수치

| 항목 | 수치 |
|------|------|
| **총 소스 코드** | 59,368 줄 (Swift) |
| **테스트 코드** | 5,552 줄 |
| **서버 코드** | 14,294 줄 (Python/Nginx/YAML) |
| **모듈 수** | 9개 라이브러리 + 1개 실행 타겟 |
| **Swift 파일** | 224개 |
| **View 파일** | 90개 |
| **ViewModel** | 14개 |
| **외부 의존성** | 1개 (VLCKitSPM) |

---

## 2. 모듈 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                    CViewApp (35,636줄)               │
│            메인 앱 · 뷰 · 뷰모델 · 네비게이션          │
└──────┬──────┬──────┬──────┬──────┬──────┬──────┬────┘
       │      │      │      │      │      │      │
  ┌────▼──┐ ┌─▼───┐ ┌▼────┐ ┌▼────┐ ┌▼───┐ ┌▼──┐ ┌▼─────────┐
  │Player │ │Chat │ │Auth │ │Pers.│ │Net │ │UI │ │Monitoring│
  │8,594줄│ │2,071│ │1,290│ │ 648 │ │3,122│ │1,044│ │  1,009   │
  └───┬───┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └─┬──┘ └────┬────┘
      │        │       │       │       │      │         │
  ┌───▼────────▼───────▼───────▼───────▼──────▼─────────▼──┐
  │                  CViewCore (5,954줄)                     │
  │         도메인 모델 · 프로토콜 · 유틸리티 · 디자인 시스템       │
  └─────────────────────────────────────────────────────────┘
```

### 모듈별 상세

| 모듈 | 파일 수 | 코드 줄 | 역할 | 주요 클래스 |
|------|--------|---------|------|-----------|
| **CViewApp** | 88 | 35,485 | 앱 쉘, UI, 라우팅, 뷰모델 | `AppState`, `AppRouter`, `PlayerViewModel`, `MultiLiveManager` |
| **CViewCore** | 32 | 5,976 | 도메인 모델, 프로토콜, DI | `DesignTokens`, `ServiceContainer`, `PlayerEngineProtocol` |
| **CViewPlayer** | 20 | 8,695 | 재생 엔진, HLS, 스트림 제어 | `VLCPlayerEngine`, `AVPlayerEngine`, `StreamCoordinator` |
| **CViewNetworking** | 13 | 3,097 | API 통신, 캐시, 메트릭 | `ChzzkAPIClient`, `MetricsAPIClient`, `ImageCacheService` |
| **CViewChat** | 6 | 2,071 | 채팅 엔진, WebSocket | `ChatEngine`, `ChatMessageParser`, `WebSocketService` |
| **CViewAuth** | 7 | 1,290 | 인증, OAuth, 키체인 | `AuthManager`, `ChzzkOAuthService`, `KeychainService` |
| **CViewUI** | 5 | 1,044 | 공유 UI 컴포넌트 | `CachedAsyncImage`, `EmoticonPickerView`, `TimelineSlider` |
| **CViewMonitoring** | 2 | 1,009 | 성능 모니터링, 메트릭 전송 | `PerformanceMonitor`, `MetricsForwarder` |
| **CViewPersistence** | 4 | 648 | SwiftData 영속성 | `DataStore`, `SettingsStore` |

---

## 3. 아키텍처 설계 원칙

### 3.1 Actor 기반 동시성 모델

모든 서비스 레이어가 **Swift Actor**로 구현되어 데이터 경쟁을 컴파일 타임에 방지합니다.

```
Actor 클래스:
├── ChzzkAPIClient (actor)         — API 통신
├── DataStore (@ModelActor)        — 데이터 영속성
├── ChatEngine (actor)             — 채팅 엔진
├── StreamCoordinator (actor)      — 스트림 오케스트레이션
├── PerformanceMonitor (actor)     — 성능 수집
├── MetricsForwarder (actor)       — 메트릭 전송
├── ServiceContainer (actor)       — DI 컨테이너
├── MultiLiveEnginePool (actor)    — 엔진 풀 관리
└── LowLatencyController (actor)   — 저지연 제어

@MainActor 클래스:
├── AppState (@Observable)         — 전역 상태
├── AppRouter (@Observable)        — 네비게이션
├── SettingsStore (@Observable)    — 설정 관리
├── MultiLiveManager (@Observable) — 멀티라이브 매니저
└── PlayerViewModel (@Observable)  — 플레이어 뷰모델
```

### 3.2 @Observable 반응형 상태 관리

SwiftUI의 `@Observable` 매크로를 사용하여 프로퍼티 단위 변경 추적:
- `ObservableObject` + `@Published` 대비 불필요한 뷰 갱신 최소화
- 연쇄 의존성 자동 추적으로 수동 바인딩 불필요

### 3.3 컴포지션 패턴

상속 대신 조합으로 복잡성 관리:

```
StreamCoordinator
├── HLSManifestParser      — M3U8 파싱
├── ABRController           — 적응형 비트레이트
├── LowLatencyController    — 저지연 동기화
└── LocalStreamProxy        — CDN 프록시

ChatEngine
├── ChatMessageParser       — 바이너리 메시지 디코딩
├── WebSocketService        — WebSocket 연결
└── ReconnectionPolicy      — 지수 백오프 재연결
```

### 3.4 의존성 주입 (DI)

`ServiceContainer` Actor가 타입 안전한 DI 컨테이너 역할:
- `ObjectIdentifier` 기반 타입 룩업
- 싱글턴 + 팩토리 패턴 지원
- `Sendable` 제약으로 Actor 경계 안전 보장

---

## 4. 핵심 기능 상세

### 4.1 듀얼 플레이어 엔진

두 가지 재생 엔진을 `PlayerEngineProtocol`로 추상화하여 런타임 전환 지원:

| 기능 | VLC 엔진 | AVPlayer 엔진 |
|------|---------|--------------|
| **코드 줄** | 1,359 | 1,198 |
| **저지연** | liveCaching 프로파일 | configuredTimeOffsetFromLive |
| **화질** | ABR 수동 제어 | preferredPeakBitRate 8Mbps |
| **이퀄라이저** | ✅ (10밴드) | ❌ |
| **영상 필터** | ✅ (밝기/대비/채도/색조/감마) | ❌ |
| **자막** | ✅ | ❌ |
| **전력 소비** | 높음 | 낮음 (하드웨어 디코더) |
| **녹화** | ✅ | ❌ |
| **PiP** | ❌ | ✅ |
| **특성** | 고급 제어, 범용 코덱 | 저전력, macOS 네이티브 통합 |

#### 엔진 전환 흐름
```
사용자 엔진 변경 요청
    ↓
MultiLiveManager.switchEngine()
    ├── session.stop()          — 기존 재생 정지
    ├── detachEngine()          — 엔진 분리
    ├── enginePool.release()    — 풀 반환
    ├── enginePool.acquire()    — 새 엔진 획득
    ├── injectEngine()          — 엔진 주입
    └── session.start()         — 재생 시작
```

### 4.2 멀티라이브 시스템

최대 4채널 동시 시청을 지원하는 멀티라이브 아키텍처:

```
MultiLiveManager (오케스트레이터)
├── sessions: [MultiLiveSession]     — 최대 4개 세션
├── enginePool: MultiLiveEnginePool  — VLC/AVPlayer 엔진 풀
├── gridLayoutMode                   — 프리셋/커스텀 레이아웃
├── audioSessionId                   — 오디오 라우팅 타겟
└── layoutRatios                     — 커스텀 분할 비율

MultiLiveSession (개별 세션)
├── playerViewModel: PlayerViewModel — 독립 플레이어
├── chatViewModel: ChatViewModel     — 독립 채팅
├── loadState: SessionLoadState      — 상태 머신
├── latestMetrics                    — VLC 메트릭
├── latestAVMetrics                  — AVPlayer 메트릭
└── metricsForwarder                 — 서버 전송
```

#### 엔진 풀 관리
```
MultiLiveEnginePool (actor)
├── idleEngines: [Type: [Engine]]    — 유휴 엔진 캐시
├── activeCount: [Type: Int]         — 활성 엔진 카운트
├── warmup(count:, type:)            — 프리로드
├── acquire(type:)                   — 할당 (유휴 → 재사용)
└── release(_:)                      — 반환 (정리 후 풀 복귀)
```

#### 레이아웃 모드
- **프리셋**: 1, 2(좌우), 3(1+2), 4(2×2) 자동 배치
- **커스텀**: 드래그로 분할 비율 조정
- **오디오 라우팅**: 단일 소스 / 멀티 오디오 모드

### 4.3 채팅 시스템

치지직 채팅 서버와 WebSocket으로 실시간 통신:

```
ChatEngine (actor)
    ↓ WebSocket (wss://kr-ss[1-9].chat.naver.com)
    ↓ 서버 선택: chatChannelId UTF-8 바이트 합 % 9 → 서버 ID
    ↓ 바이너리 메시지 수신
    ↓
ChatMessageParser
    ↓ 디코딩 → ChatMessage 구조체
    ↓
AsyncStream<ChatEngineEvent>
    ↓ 이벤트 스트림 구독
    ↓
ChatViewModel (@MainActor)
    ↓ UI 바인딩
    ↓
ChatPanelView (SwiftUI)
```

#### 주요 기능
- **이모티콘**: 기본 팩 프리로드 + 채널별 커스텀 이모티콘
- **자동완성**: `ChatAutocompleteView`로 이모티콘/유저 자동완성
- **사용자 관리**: 차단, 프로필 조회
- **재연결**: 지수 백오프 정책 (`ReconnectionPolicy`)
- **멀티 채팅**: 여러 채널 채팅 동시 표시 (`MultiChatSessionManager`)

### 4.4 스트림 재생 파이프라인

```
사용자 채널 선택
    ↓
ChzzkAPIClient.liveDetail()          — 방송 정보 조회
    ↓
LivePlayback → HLS URL 추출
    ↓
HLSManifestParser.parse()           — M3U8 마스터 플레이리스트 파싱
    ↓ Variant 목록 (해상도/비트레이트)
    ↓
ABRController.recommend()           — 최적 화질 선택
    ↓
LocalStreamProxy.start()            — 로컬 리버스 프록시 기동
    ↓ CDN Content-Type 보정 (fMP4 ↔ MPEG-TS)
    ↓
PlayerEngine.play(url:)             — VLC 또는 AVPlayer 재생
    ↓
LowLatencyController.adjust()      — PID 기반 재생 속도 조정
    ↓ 목표 지연 유지 (1.5s ~ 6s)
    ↓
PerformanceMonitor.collect()        — FPS/CPU/GPU/네트워크 수집
    ↓
MetricsForwarder.send()             — 서버 메트릭 전송
```

### 4.5 저지연 제어 (PID 컨트롤러)

실시간 재생 속도를 PID 알고리즘으로 자동 조정하여 목표 지연 유지:

```
error = targetLatency - currentLatency
rate = baseRate + Kp×error + Ki×∫error + Kd×(Δerror/Δt)
rate = clamp(rate, minRate, maxRate)
```

| 프리셋 | 목표 지연 | 최대 속도 | 최소 속도 | 용도 |
|--------|----------|----------|----------|------|
| **webSync** | 6.0s | 1.15x | 0.90x | 브라우저 동기화 |
| **standard** | 3.0s | 1.15x | 0.90x | 균형 모드 |
| **ultraLow** | 1.5s | 1.20x | 0.85x | 최저 지연 |
| **custom** | 사용자 정의 | 사용자 정의 | 사용자 정의 | 고급 설정 |

**EWMA 스무딩**: 지연 추정의 노이즈/지터 제거로 안정적 속도 조정

### 4.6 로컬 스트림 프록시

CDN 서버의 `Content-Type` 오류를 수정하는 로컬 HTTP 리버스 프록시:

```
문제: navercdn.com이 fMP4 세그먼트를 video/MP2T로 응답
     → VLC가 MPEG-TS로 파싱 시도 → transport_error_indicator 경고

해결: Network.framework 기반 로컬 HTTP 서버
     → CDN 응답 인터셉트 → Content-Type 헤더 보정 → 플레이어에 전달

특징:
├── 스트림별 독립 인스턴스 (멀티라이브 간섭 방지)
├── CDN 인증 실패(403) 감지
├── 최대 연결 수 제한 (DoS 방지)
└── Mutex 기반 스레드 안전성
```

### 4.7 성능 모니터링

실시간 시스템 메트릭 수집 및 서버 전송:

```
PerformanceMonitor (actor)
├── 렌더링: FPS, 드롭된 프레임
├── 시스템: 메모리(MB), CPU(%), GPU(%)
├── GPU: 렌더러 사용률, VRAM(MB) — Metal/IOKit
├── 네트워크: 수신 바이트, 실시간 속도
└── 재생: 버퍼 상태, 지연(ms), 해상도, 입력 비트레이트

MetricsForwarder (actor)
├── VLC/AVPlayer 메트릭 이중 입력
├── cv.dododo.app 서버 전송
├── 킵얼라이브 핑
└── 서버 동기화 추천 수신 (CViewSyncRecommendation)
```

---

## 5. 앱 윈도우 구성

| 윈도우 | ID | 기본 크기 | 최소 크기 | 용도 |
|--------|-----|----------|----------|------|
| **메인** | - | 1200×800 | 900×600 | 메인 앱 (팔로잉/홈/검색) |
| **플레이어** | player-window | 960×600 | - | 분리된 채널 재생 |
| **통계** | statistics-window | 700×500 | - | 성능 통계 대시보드 |
| **채팅** | chat-window | 360×600 | - | 독립 채팅 뷰어 |
| **멀티채팅** | multi-chat-window | 700×550 | - | 멀티채널 채팅 |
| **설정** | Settings | SwiftUI 기본 | - | 앱 설정 |
| **메뉴바** | MenuBarExtra | - | - | macOS 메뉴바 아이콘 |

---

## 6. 네비게이션 구조

### 6.1 사이드바 메뉴

```
┌─────────────────────┐
│ 🏠 홈               │ → 인기 방송, 추천
│ ❤️ 라이브            │ → 팔로잉 채널, 멀티라이브
│ 📦 카테고리          │ → 게임/카테고리 브라우즈
│ 🔍 검색             │ → 채널/방송 검색
│ 🎬 인기 클립         │ → 인기 클립 모음
│ 🕐 최근/즐겨찾기     │ → 시청 기록, 즐겨찾기
│ 📊 메트릭           │ → 성능 대시보드
│ ⚙️ 설정             │ → 앱 설정
└─────────────────────┘
```

### 6.2 라우팅 시스템

`AppRouter` (@Observable)가 타입 안전한 네비게이션 관리:

```swift
enum AppRoute: Hashable {
    case home
    case live(channelId: String)
    case search(query: String?)
    case following
    case channelDetail(channelId: String)
    case chatOnly(channelId: String)
    case vod(videoNo: Int)
    case clip(clipUID: String)
    case popularClips
    case multiLive
}
```

**시트 라우트**: `login`, `channelInfo`, `qualitySelector`, `chatSettings`  
**키보드 단축키**: ⌘N(새 창), ⌘T(통계), ⌘R(새로고침), ⌘S(스크린샷), ⌘F(전체화면), ⌘K(명령 팔레트)

---

## 7. 설정 체계

9개 카테고리로 분류된 설정 시스템:

### 7.1 플레이어 설정 (PlayerSettings)

| 그룹 | 항목 |
|------|------|
| **재생** | 화질, 선호 엔진(VLC/AVPlayer), 저지연 모드, 캐치업 속도, 버퍼 크기, 음량, 자동재생 |
| **이퀄라이저** | 프리셋, 프리앰프, 10밴드 주파수 |
| **영상 보정** | 밝기, 대비, 채도, 색조, 감마 |
| **오디오** | 스테레오 모드, 믹스 모드, 오디오 딜레이 |
| **화면 비율** | 16:9, 4:3, 원본 등 |
| **지연 제어** | PID 게인(Kp/Ki/Kd), EWMA 파라미터, 프리셋 선택 |

### 7.2 기타 설정

| 카테고리 | 주요 항목 |
|---------|----------|
| **ChatSettings** | 폰트 크기, 이모티콘 표시, 타임스탬프, 필터 |
| **GeneralSettings** | 시작 동작, 알림, 업데이트 확인 |
| **AppearanceSettings** | 테마(다크/라이트/시스템), 사이드바 스타일 |
| **NetworkSettings** | 프록시, 타임아웃, 최대 재시도 |
| **MetricsSettings** | 메트릭 전송 활성화, 서버 URL, 전송 주기 |
| **KeyboardShortcutSettings** | 커스텀 단축키 매핑 |
| **ChannelNotificationSettings** | 채널별 알림 설정 |
| **MultiLiveSettings** | 최대 동시 세션 수, 레이아웃 기본값 |

### 7.3 저장 전략

- **병렬 로드**: 9개 카테고리 동시 로드 (Task 병렬 실행)
- **동등성 검사**: 값 변경 시에만 @Observable 프로퍼티 업데이트
- **디바운스 저장**: 채널 알림은 500ms 디바운스로 빈번한 쓰기 방지
- **SwiftData 백엔드**: SQLite 기반 영속성

---

## 8. 네트워킹 레이어

### 8.1 API 클라이언트

```
ChzzkAPIClient (actor)
├── baseURL: https://api.chzzk.naver.com
├── SSL Certificate Pinning
├── User-Agent 스푸핑 (Chrome)
├── 응답 캐시 (TTL 기반, 5분 퍼지)
├── 자동 재시도 (최대 3회)
├── 401 세션 만료 알림
└── GZIP/Deflate/Brotli 압축
```

### 8.2 메트릭 API

```
MetricsAPIClient
├── cv.dododo.app 서버 통신
├── VLC/AVPlayer 메트릭 전송
└── 동기화 추천 수신

MetricsWebSocketClient
├── 실시간 메트릭 WebSocket
└── 양방향 동기화 데이터
```

### 8.3 이미지 캐시

```
ImageCacheService
├── 메모리 캐시 (LRU)
├── 디스크 캐시
├── 프리페치 지원
└── 주기적 정리 (앱 시작 3초 후)
```

---

## 9. 인증 시스템

```
AuthManager
├── OAuth 2.0 로그인 (ChzzkOAuthService)
│   └── 네이버 OAuth → 치지직 토큰
├── 쿠키 기반 로그인 (CookieManager)
│   └── 네이버 쿠키 추출 → API 인증
├── 키체인 저장 (KeychainService)
│   └── 토큰 안전 보관
└── 세션 관리
    ├── 자동 갱신
    ├── 401 감지 → 로그아웃
    └── 프로필 로드 (닉네임, 채널 ID)
```

---

## 10. 디자인 시스템

### 10.1 스페이싱 (8pt 그리드)

```
xxs: 2pt   xs: 4pt   sm: 8pt    md: 12pt
lg: 16pt   xl: 24pt  xxl: 32pt  xxxl: 48pt
section: 64pt         page: 80pt
```

### 10.2 타이포그래피

```
display: 34pt     title: 26pt      headline: 20pt
subhead: 16pt     body: 14pt       caption: 13pt
footnote: 12pt    micro: 10pt
+ Bold/Semibold/Medium 변형 17종
+ Monospace 변형 3종
```

### 10.3 디자인 테마

- **Dark Glass 미학**: 딥 차콜 베이스 + 글래스모피즘
- **치지직 그린 액센트**: 브랜드 컬러 통합
- **레티나 최적화**: 2x 픽셀 밀도 기준 설계

---

## 11. 서버 인프라

### 11.1 구성

```
server-dev/mirror/
├── docker-compose.yml              — 컨테이너 오케스트레이션
├── nginx-ssl/                      — Nginx SSL 리버스 프록시
│   ├── nginx.conf
│   └── entrypoint.sh
├── chzzk-collector/                — Python 메트릭 수집 서버
│   ├── server.py                   — 메인 서버
│   ├── config.py                   — 설정
│   ├── models.py                   — 데이터 모델
│   ├── background.py               — 백그라운드 작업
│   ├── metric_processing.py        — 메트릭 처리
│   ├── ai_sync_service.py          — AI 동기화 서비스
│   ├── chzzk_api.py                — 치지직 API 래퍼
│   ├── ssl_manager.py              — SSL 인증서 관리
│   ├── influxdb_utils.py           — InfluxDB 유틸리티
│   └── handlers/                   — API 핸들러
│       ├── sync.py                 — 동기화
│       ├── metrics.py              — 메트릭 수신
│       ├── collectors.py           — 수집기 관리
│       ├── influx_api.py           — InfluxDB API
│       ├── ai_sync.py              — AI 동기화
│       ├── live.py                 — 라이브 상태
│       ├── channels.py             — 채널 정보
│       └── vlc.py                  — VLC 메트릭
└── cview-stats-web/                — 통계 웹 대시보드
```

### 11.2 데이터 흐름

```
CView 앱 → MetricsForwarder → HTTPS → Nginx SSL Proxy
                                           ↓
                                    chzzk-collector (Python)
                                           ↓
                                    InfluxDB (시계열 DB)
                                           ↓
                                    cview-stats-web (대시보드)
```

---

## 12. 앱 초기화 시퀀스

```
앱 시작
    ↓
① 즉시 설정 (0ms)
   ├── ServiceContainer 등록
   ├── API 클라이언트 생성
   ├── AuthManager 생성
   └── 메트릭 클라이언트 생성
    ↓
② 뷰모델 초기화 (즉시)
   ├── HomeViewModel
   ├── ChatViewModel
   ├── PlayerViewModel
   └── MultiLiveManager 설정
    ↓
③ UI 준비 완료 (isInitialized = true)
   └── ProgressView → 메인 화면 전환
    ↓
④ 백그라운드 초기화 (지연 실행)
   ├── 100ms: DataStore + SwiftData
   ├── 200ms: 인증 + 프로필 로드
   ├── 300ms: 메트릭 설정
   ├── 500ms: 이모티콘 프리로드
   └── AsyncStream: 라이브 채널 로드
    ↓
⑤ 이미지 캐시 정리 (3초 후)
```

**설계 철학**: UI를 먼저 표시하고 데이터를 점진적 로드하여 체감 속도 최적화

---

## 13. 코드 품질 지표

### 13.1 상위 대형 파일

> **리팩토링 완료** (2025.07): 700줄 초과 파일 전수 분할 완료. 현재 최대 파일 687줄.

| 파일 | 줄 수 | 역할 |
|------|------|------|
| PlayerControlsView.swift | 687 | 플레이어 컨트롤 UI |
| ClipPlayerView.swift | 685 | 클립 재생 뷰 |
| StatisticsDetailViews.swift | 680 | 통계 상세 뷰 |
| GeneralSettingsTab.swift | 675 | 일반 설정 탭 |
| ChatMessageParser.swift | 673 | 채팅 메시지 파서 |
| ChatSettingsQualityView.swift | 665 | 채팅/화질 설정 뷰 |
| PopularClipsView.swift | 650 | 인기 클립 뷰 |
| HomeViewModel.swift | 645 | 홈 뷰모델 |
| CategoryBrowseView.swift | 642 | 카테고리 탐색 뷰 |
| MetricsForwarder.swift | 623 | 메트릭 전송 액터 |

### 13.2 Swift 6 엄격 동시성

- **Swift Language Mode**: v6 (가장 엄격한 동시성 검사)
- **Sendable 준수**: 모든 Actor 간 전달 타입에 Sendable 적용
- **@MainActor 격리**: UI 관련 모든 상태에 적용
- **데이터 경쟁 방지**: 컴파일 타임 보장

### 13.3 빌드 최적화

```swift
// Debug: 느린 컴파일 감지 (200ms 임계값)
-Xfrontend -warn-long-function-bodies=200
-Xfrontend -warn-long-expression-type-checking=200
```

---

## 14. 테스트 구조

```
Tests/ (5,552줄)
├── CViewCoreTests/         — 도메인 모델 테스트
├── CViewNetworkingTests/   — API 클라이언트 테스트
├── CViewChatTests/         — 채팅 엔진 테스트
├── CViewPlayerTests/       — 플레이어 테스트
└── CViewAuthTests/         — 인증 테스트
```

---

## 15. 주요 기술적 특징 요약

| 기술 | 적용 위치 | 효과 |
|------|----------|------|
| **PID 컨트롤러** | LowLatencyController | 부드러운 저지연 재생 속도 조정 |
| **EWMA** | ABRController, LowLatencyController | 대역폭/지연 추정의 노이즈 제거 |
| **로컬 리버스 프록시** | LocalStreamProxy | CDN Content-Type 오류 투명하게 수정 |
| **엔진 풀링** | MultiLiveEnginePool | 멀티라이브 엔진 재사용으로 생성 오버헤드 감소 |
| **Certificate Pinning** | ChzzkAPIClient | SSL/TLS MITM 공격 방지 |
| **지수 백오프** | ReconnectionPolicy | 네트워크 장애 시 점진적 재연결 |
| **AsyncStream** | ChatEngine | 이벤트 드리븐 비동기 채팅 메시지 스트리밍 |
| **SwiftData** | DataStore | 타입 안전 SQLite 영속성 |
| **Metal/IOKit** | PerformanceMonitor | GPU 사용률 직접 조회 |
| **HLS 매니페스트 파싱** | HLSManifestParser | M3U8 직접 파싱으로 화질/variant 제어 |
| **App Nap 방지** | AppState.playbackActivity | 스트리밍 중 macOS 절전 방지 |
| **글래스모피즘 UI** | DesignTokens | macOS 네이티브 느낌의 현대적 UI |

---

*이 문서는 CView v2 프로젝트의 소스 코드 정밀 분석을 기반으로 자동 생성되었습니다.*
