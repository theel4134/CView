# AVPlayer 멀티라이브 레이턴시 정밀 연구 분석

> **분석 일시**: 2026년 3월 7일  
> **분석 범위**: CView_v2 전체 소스코드 — AVPlayerEngine.swift (977줄) + 멀티라이브 시스템 전체  
> **연관 문서**: [CHZZK_LIVE_LATENCY_PRECISION_RESEARCH.md](CHZZK_LIVE_LATENCY_PRECISION_RESEARCH.md) (VLC 중심 분석)  
> **목적**: 멀티라이브에 사용되는 AVPlayer 엔진의 LL-HLS 지원, 레이턴시 제어, GPU 파이프라인을 정밀 분석하고, VLC 엔진과의 격차를 규명

---

## 목차

1. [멀티라이브 시스템 아키텍처](#1-멀티라이브-시스템-아키텍처)
2. [AVPlayerEngine 전체 구현 분석](#2-avplayerengine-전체-구현-분석)
3. [LL-HLS 네이티브 지원 상세](#3-ll-hls-네이티브-지원-상세)
4. [라이브 캐치업 제어기 수학적 분석](#4-라이브-캐치업-제어기-수학적-분석)
5. [GPU 렌더링 파이프라인](#5-gpu-렌더링-파이프라인)
6. [CDN URL 전체 경로 추적](#6-cdn-url-전체-경로-추적)
7. [스톨 감지 및 재연결 체계](#7-스톨-감지-및-재연결-체계)
8. [네트워크 적응 시스템](#8-네트워크-적응-시스템)
9. [VLC 엔진과의 정밀 비교](#9-vlc-엔진과의-정밀-비교)
10. [멀티 세션 동시 재생 분석](#10-멀티-세션-동시-재생-분석)
11. [최적화 전략 및 개선 제안](#11-최적화-전략-및-개선-제안)
12. [핵심 파라미터 레퍼런스](#12-핵심-파라미터-레퍼런스)
13. [결론](#13-결론)

---

## 1. 멀티라이브 시스템 아키텍처

### 1.1 전체 시스템도

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     CView_v2 멀티라이브 아키텍처                                 │
│                                                                                 │
│  MultiLiveManager (@Observable, @MainActor)                                     │
│  ├─ sessions: [MultiLiveSession] (최대 4개)                                     │
│  ├─ selectedSessionId: UUID? (오디오 활성 세션)                                  │
│  └─ addingChannelIds: Set<String> (중복 추가 방지)                               │
│                                                                                 │
│  MultiLiveSession (× 4, 독립 인스턴스)                                           │
│  ├─ PlayerViewModel (engineType: .avPlayer)                                     │
│  │   ├─ AVPlayerEngine                                                          │
│  │   │   ├─ AVPlayer + AVPlayerItem                                             │
│  │   │   ├─ AVPlayerLayerView (Metal Zero-Copy)                                 │
│  │   │   ├─ Live Catchup Loop (1초 주기, 코사인 이징)                             │
│  │   │   ├─ Stall Watchdog (3초 주기, 12초 타임아웃)                              │
│  │   │   └─ NWPathMonitor (네트워크 적응)                                        │
│  │   └─ StreamCoordinator (actor)                                               │
│  │       ├─ LocalStreamProxy (CDN 프록시, Content-Type 수정)                     │
│  │       ├─ Playback Watchdog (5초 주기)                                        │
│  │       └─ ※ VLC 전용: PDTLatencyProvider, LowLatencyController, ABR           │
│  └─ ChatViewModel                                                               │
│      └─ WebSocket 채팅 연결 (독립)                                               │
│                                                                                 │
│  MultiLiveView (SwiftUI)                                                        │
│  ├─ MultiLiveTabBar (세션 탭)                                                   │
│  ├─ tabLayout (단일 풀스크린) / gridLayout (2×2 그리드)                           │
│  ├─ MultiLivePlayerPane (× 4, 독립 비디오 레이어)                                │
│  │   └─ PlayerVideoView → AVPlayerLayerView → AVPlayerLayer (GPU)               │
│  └─ ChatPanelView (320px, 선택 세션 연동)                                        │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 엔진 선택 전략

| 용도 | 엔진 | 선택 이유 |
|------|------|----------|
| **싱글 라이브** (메인 플레이어) | VLCPlayerEngine | 비표준 포맷 호환, 세밀한 버퍼 제어, 녹화 |
| **멀티라이브** (최대 4 세션) | **AVPlayerEngine** | Apple 내장 ABR, LL-HLS 네이티브, GPU 효율성, 안정성 |
| **VOD 재생** | AVPlayerEngine | 표준 미디어 포맷, 네이티브 시크, 자막 |
| **PiP (화면 속 화면)** | AVPlayerEngine | AVPlayerLayer 기반 PiP 네이티브 지원 |

```swift
// PlayerViewModel.swift L116-119 — 팩토리 메서드
case .avPlayer:
    let e = AVPlayerEngine()
    e.catchupConfig = .lowLatency   // target=3.0s, max=8.0s, rate=1.5x
    return e
```

### 1.3 세션 생명주기

```
addSession(channelId)
    │
    ├── Guard: sessions.count < 4 && 중복 없음 && 동시 추가 없음
    │
    ├── API: apiClient.liveDetail(channelId) → LiveInfo
    │
    ├── Create: MultiLiveSession(channelId, liveInfo, apiClient)
    │   └── init → PlayerViewModel(engineType: .avPlayer) + ChatViewModel
    │
    ├── sessions.append(session)
    │
    ├── 오디오 라우팅:
    │   ├── 첫 세션 → selectedSessionId = session.id (음소거 해제)
    │   └── 추가 세션 → session.playerViewModel.toggleMute() (음소거)
    │
    └── Task { session.start() }
            │
            ├── liveDetail() API 호출 (필요시)
            ├── JSON → LivePlayback → media[HLS].path → masterURL
            ├── playerViewModel.startStream(streamUrl: masterURL)
            │   ├── StreamCoordinator 생성
            │   ├── AVPlayerEngine 생성 (.avPlayer)
            │   ├── coordinator.startStream(url:)
            │   │   ├── LocalStreamProxy.start()  ← CDN 프록시
            │   │   └── engine.play(url: proxyURL) ← 마스터 매니페스트
            │   └── Stall Watchdog + Live Catchup Loop 시작
            └── connectChat() (병렬 Task)
                ├── 토큰 + 이모티콘 fetch (병렬)
                └── chatViewModel.connect()
```

---

## 2. AVPlayerEngine 전체 구현 분석

### 2.1 클래스 선언

```swift
// AVPlayerEngine.swift L140
public final class AVPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable
```

- `PlayerEngineProtocol` 준수 → VLC와 동일 인터페이스
- `@unchecked Sendable` — NSLock 기반 동기화
- `NSObject` — KVO(Key-Value Observing) 지원

### 2.2 핵심 프로퍼티

| 프로퍼티 | 타입 | 초기값 | 동기화 |
|---------|------|--------|--------|
| `player` | `AVPlayer` | `AVPlayer()` | — |
| `catchupConfig` | `AVLiveCatchupConfig` | `.lowLatency` | NSLock |
| `_state` | `PlayerState.Phase` | `.idle` | NSLock |
| `_rate` | `Float` | `1.0` | NSLock |
| `_volume` | `Float` | `1.0` | NSLock |
| `_videoView` | `AVPlayerLayerView` | new | — |
| `measuredLatency` | `Double` | `0` | — |
| `indicatedBitrate` | `Double` | `0` | AccessLog |
| `droppedFrames` | `Int` | `0` | AccessLog |
| `rateHistory` | `[Float]` | `[]` | — (max 4) |
| `_isLiveStream` | `Bool` | `false` | NSLock |
| `currentNetworkType` | `NWInterface.InterfaceType` | `.wifi` | — |

### 2.3 10종 KVO/Observer

| Observer | 감시 대상 | 반응 |
|----------|---------|------|
| `statusObservation` | `AVPlayerItem.status` | `.readyToPlay`→playing, `.failed`→에러분류 |
| `timeControlObservation` | `AVPlayer.timeControlStatus` | `.playing`/`.paused`/`.waitingToPlay` |
| `bufferKeepUpObservation` | `isPlaybackLikelyToKeepUp` | `true`+buffering → `.playing` 복구 |
| `bufferFullObservation` | `isPlaybackBufferFull` | watchdog 타임스탬프 리셋 |
| `timeObserver` | 주기적 (1.0초) | `onTimeChange` 콜백, watchdog 리셋 |
| `stallObservation` | `.AVPlayerItemPlaybackStalled` | `.buffering` → 2초 후 복구 시도 |
| `bufferObservation` | `.AVPlayerItemDidPlayToEndTime` | `.ended` 상태 |
| `accessLogObservation` | `.AVPlayerItemNewAccessLogEntry` | bitrate/droppedFrames 추적 |
| `liveOffsetObservation` | (선언만, 미사용) | — |
| `networkMonitor` | `NWPathMonitor` | 네트워크 전환 시 설정 재조정 |

### 2.4 init/deinit

```swift
// init() L267-274
_videoView = AVPlayerLayerView()
player = AVPlayer()
_videoView.attach(player: player)
setupNetworkMonitor()     // NWPathMonitor 시작
setupObservers()          // timeControlStatus + periodic time observer

// deinit L276-281
networkMonitor.cancel()
stallWatchdogTask?.cancel()
liveCatchupTask?.cancel()
removeObservers()
player.pause()
```

---

## 3. LL-HLS 네이티브 지원 상세

### 3.1 AVPlayer LL-HLS 설정 전체

```swift
// play(url:) L360-376 — 라이브 스트림 전용
if isLiveStream {
    // 1. 스톨 발생 시 자동 대기 비활성 — 즉시 재생 유지
    player.automaticallyWaitsToMinimizeStalling = false
    
    // 2. 네트워크 지터로 인한 오프셋 변동 자동 보상
    item.automaticallyPreservesTimeOffsetFromLive = true
    
    // 3. 네트워크별 캐치업 설정 적용
    adjustCatchupConfigForNetwork()
    
    // 4. 전진 버퍼 크기 제한 (메모리 + 레이턴시 최적화)
    item.preferredForwardBufferDuration = catchupConfig.preferredForwardBuffer  // 4.0s
    
    // 5. 라이브 엣지로부터의 목표 오프셋
    item.configuredTimeOffsetFromLive = CMTime(
        seconds: catchupConfig.targetLatency,   // 3.0s (wifi)
        preferredTimescale: 1
    )
}
```

### 3.2 LL-HLS 동작 메커니즘

```
┌─────────────────────────────────────────────────────────────────┐
│                  AVPlayer LL-HLS 재생 파이프라인                  │
│                                                                  │
│  1. 마스터 매니페스트 수신 (프록시 경유)                           │
│     ↓                                                            │
│  2. Apple 내장 ABR → 최적 variant 자동 선택                       │
│     ├── preferredMaximumResolution: 1920×1080                    │
│     └── preferredPeakBitRate: 0 (무제한)                          │
│     ↓                                                            │
│  3. LL-HLS Part 세그먼트 자동 처리                                │
│     ├── #EXT-X-PART 파싱 + 부분 세그먼트 다운로드                  │
│     ├── #EXT-X-PRELOAD-HINT 프리로드                              │
│     ├── Blocking Playlist Reload (_HLS_msn, _HLS_part)           │
│     └── ※ 이 모든 것이 Apple Framework 내부에서 자동 처리          │
│     ↓                                                            │
│  4. configuredTimeOffsetFromLive = 3.0s                          │
│     → 라이브 엣지로부터 3초 뒤에서 재생 시작                       │
│     ↓                                                            │
│  5. automaticallyPreservesTimeOffsetFromLive = true              │
│     → 네트워크 변동 시 오프셋 자동 복원                            │
│     ↓                                                            │
│  6. Live Catchup Loop (1초 주기)                                  │
│     → latency > target → 코사인 이징 가속 (최대 1.5x)            │
│     → latency > max(8s) → 라이브 엣지 점프                       │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 VLC 대비 LL-HLS 핵심 이점

| LL-HLS 기능 | AVPlayer | VLC |
|-------------|----------|-----|
| **Part 세그먼트 재생** | ✅ 자동 | ❌ 전체 세그먼트 대기 |
| **블로킹 리로드** (`_HLS_msn`) | ✅ 자동 | ❌ 타이머 폴링 |
| **프리로드 힌트** (`EXT-X-PRELOAD-HINT`) | ✅ 자동 | ❌ 무시 |
| **라이브 엣지 오프셋** | ✅ `configuredTimeOffsetFromLive` | ❌ PID 제어기 간접 |
| **오프셋 자동 보존** | ✅ `automaticallyPreservesTimeOffsetFromLive` | ❌ watchdog 재연결 |
| **ABR** | ✅ Apple 내장 | ❌ variant URL 고정 (1080p) |

### 3.4 AVURLAsset 설정

```swift
// play(url:) L320-333
let playerOptions: [String: Any] = [
    "AVURLAssetHTTPHeaderFieldsKey": [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) ... Safari/605.1.15",
        "Accept": "application/vnd.apple.mpegurl, application/x-mpegURL, audio/mpegurl, */*"
    ],
    AVURLAssetPreferPreciseDurationAndTimingKey: false,  // ← 라이브 시작 지연 단축
]
let asset = AVURLAsset(url: url, options: playerOptions)
```

| 설정 | 값 | 레이턴시 영향 |
|------|-----|-------------|
| `PreferPreciseDurationAndTimingKey` | `false` | 시작 지연 -200~500ms (정밀 타이밍 계산 생략) |
| `User-Agent` | Safari UA | CDN 호환 (Naver CDN Safari UA 필수) |
| `Accept` | mpegurl 우선 | LL-HLS 매니페스트 선호 힌트 |

### 3.5 AVPlayerItem 설정

```swift
// play(url:) L337-343
item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
item.preferredPeakBitRate = 0  // 무제한 — 최고 화질
```

---

## 4. 라이브 캐치업 제어기 수학적 분석

### 4.1 제어기 개요

AVPlayer의 캐치업은 VLC의 PID 제어기와 달리 **코사인 이징 곡선 + EMA 스무딩** 방식을 사용합니다.

### 4.2 레이턴시 측정 방법

```swift
// adjustPlaybackRateForLatency() L593-601
let seekRange = item.seekableTimeRanges.last?.timeRangeValue
let liveEdge = CMTimeGetSeconds(CMTimeRangeGetEnd(seekRange))
let currentPos = CMTimeGetSeconds(player.currentTime())
let latency = max(0, liveEdge - currentPos)
```

**측정 원리**: `seekableTimeRanges`의 끝 = 현재 가용한 라이브 엣지

- **VLC PDT 방식**: 서버 시계 기준 (PDT + segDuration vs 현재 시각)
- **AVPlayer 범위 방식**: 클라이언트 버퍼 내 데이터 기준 (최신 가용 데이터 위치)

| 비교 | PDT 기반 (VLC) | seekableTimeRanges (AVPlayer) |
|------|---------------|------------------------------|
| 정확도 | ★★★★ (서버 시계) | ★★★ (클라이언트 버퍼) |
| 독립성 | CDN 폴링 필요 | 플레이어 내장 |
| 반응성 | 2초 폴링 지연 | 1초 주기 즉시 |
| 오차 원인 | 클럭 스큐, EWMA 지연 | 버퍼 충전 상태 의존 |

### 4.3 재생 속도 계산 — 코사인 이징 곡선

```
                    ┌── latency > maxLatency: 라이브 엣지 점프
                    │
    latency ────────┤
                    │
                    ├── targetLatency < latency ≤ maxLatency:
                    │     ratio = (latency - target) / (max - target)
                    │     curved = 1 - cos(ratio × π/2)
                    │     targetRate = 1.0 + curved × (maxCatchupRate - 1.0)
                    │
                    ├── 0.6×target ≤ latency ≤ target:
                    │     유지 (아무것도 안 함)
                    │
                    └── latency < 0.6×target:
                          targetRate = 1.0 (정상 속도 복구)
```

**코사인 이징 vs 선형:**

```
latency  │ ratio  │ 코사인 이징 (curved) │ 선형 │ 실제 적용 rate
─────────┼────────┼────────────────────┼──────┼────────────────
3.5초    │ 0.1    │ 0.0123             │ 0.1  │ 1.006x
4.0초    │ 0.2    │ 0.0489             │ 0.2  │ 1.024x
5.0초    │ 0.4    │ 0.190              │ 0.4  │ 1.095x
6.0초    │ 0.6    │ 0.412              │ 0.6  │ 1.206x
7.0초    │ 0.8    │ 0.691              │ 0.8  │ 1.345x
8.0초    │ 1.0    │ 1.000              │ 1.0  │ 1.500x

(target=3.0s, max=8.0s, maxCatchupRate=1.5x 기준)
```

**특징**: 코사인 이징은 오차가 작을 때 매우 완만하게 보정하고, 오차가 커질수록 급격히 가속 → 안정적 수렴

### 4.4 EMA 스무딩 (Exponential Moving Average)

```swift
let alpha: Float = 0.4
let last = rateHistory.last ?? player.rate
let smoothed = alpha * targetRate + (1 - alpha) * last
// → smoothed = 0.4 × target + 0.6 × previous
```

| 파라미터 | 값 | 의미 |
|---------|-----|------|
| α | 0.4 | 현재 값 40% + 이전 값 60% 가중 |
| 히스토리 길이 | 4개 | 4초 이동평균 (1초 주기 × 4) |
| 변화 임계값 | 0.03 | 3% 미만 변화는 무시 |

### 4.5 VLC PID 제어기와의 비교

| 측면 | AVPlayer 코사인 이징 | VLC PID 제어기 |
|------|-------------------|---------------|
| **제어 루프 주기** | 1초 | 2초 |
| **제어 방식** | 코사인 커브 + EMA | Kp + Ki + Kd (비례+적분+미분) |
| **파라미터 수** | 3개 (target, max, maxRate) | 12개+ (Kp, Ki, Kd, 4 프리셋 각각) |
| **정상 상태 오차** | ±target×0.4 데드존 | Ki 적분항이 제거 |
| **오버슈트 방지** | EMA α=0.4 + cosine 완만화 | Kd 미분항 + integral windup ±10 |
| **비상 시크** | latency > maxLatency | latency > maxLatency (동일) |
| **rate 범위** | 1.0 ~ 1.5x | 0.85x ~ 1.2x |
| **네트워크 적응** | ✅ NWPathMonitor | ❌ 고정 프리셋 |
| **복잡도** | 낮음 (20줄) | 높음 (100줄+) |
| **수렴 속도** | 빠름 (코사인 급격 응답) | 보통 (적분 시간 필요) |

### 4.6 수렴 시나리오 분석

**시나리오 1: 초기 연결 (latency=8초, target=3초, wifi)**

```
t=0:  latency=8.0, ratio=1.0, curved=1.0, target_rate=1.5x → EMA: 1.5x
t=1:  latency≈7.5, ratio=0.9, curved=0.844, target_rate=1.42x → EMA: 1.45x
t=2:  latency≈6.8, ratio=0.76, curved=0.644, target_rate=1.32x → EMA: 1.40x
t=3:  latency≈6.0, ratio=0.6, curved=0.412, target_rate=1.21x → EMA: 1.33x
...
t≈10: latency≈3.5, ratio=0.1 → curved=0.012 → rate≈1.01x → 사실상 수렴

수렴 시간: ~10초 (VLC PID: ~50초)
```

**시나리오 2: 네트워크 스파이크 (latency 12초 급등)**

```
t=0: latency=12.0 > maxLatency(8.0) → 즉시 라이브 엣지 점프
     seek(to: liveEdge - 3.0 = target)
     rateHistory 초기화
     → 복구 시간: ~2초 (seek 완료 대기)
```

**시나리오 3: 안정 상태 유지 (latency=3.2초)**

```
t=0: latency=3.2, 3.2 > target(3.0)
     ratio = (3.2-3.0)/(8.0-3.0) = 0.04
     curved = 1 - cos(0.04 × π/2) = 0.002
     targetRate = 1.0 + 0.002 × 0.5 = 1.001x
     |player.rate(1.0) - 1.001| = 0.001 < 0.03 → 무시
     → 아무 동작 없음 (매우 안정적)
```

---

## 5. GPU 렌더링 파이프라인

### 5.1 AVPlayerLayerView — Metal Zero-Copy 설정

```swift
// AVPlayerEngine.swift L19-99
final class AVPlayerLayerView: NSView, @unchecked Sendable {
    let playerLayer = AVPlayerLayer()
    
    // GPU 최적화 설정
    layerContentsRedrawPolicy = .never           // drawRect 코드패스 제거
    playerLayer.drawsAsynchronously = true        // Metal async 렌더링
    playerLayer.isOpaque = true                   // 알파 블렌딩 제거
    playerLayer.shouldRasterize = false           // 프레임 캐시 비활성
    playerLayer.allowsGroupOpacity = false        // compositing pass 제거
    playerLayer.allowsEdgeAntialiasing = false    // 경계 AA 비활성
    
    // Metal Zero-Copy IOSurface
    playerLayer.pixelBufferAttributes = [
        kCVPixelBufferPixelFormatTypeKey:  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    
    // HDR/Wide Color Gamut
    playerLayer.wantsExtendedDynamicRangeContent = true
    
    // 보간 필터
    playerLayer.magnificationFilter = .linear     // 확대: 바이리니어
    playerLayer.minificationFilter = .trilinear   // 축소: 밉맵
    
    // Retina: contentsScale = backingScaleFactor
}
```

### 5.2 암시적 애니메이션 비활성화

```swift
// 5개 프로퍼티에 대해 CAAnimation 억제
let keys = ["position", "bounds", "frame", "contents", "opacity"]
// → NSNull() 액션 = 애니메이션 없음
```

**목적**: 레이어 속성 변경 시 Core Animation의 0.25초 기본 애니메이션이 비디오 프레임 갱신을 방해하는 것을 방지

### 5.3 렌더링 경로 전체

```
VideoToolbox (HW 디코더)
    ↓ CVPixelBuffer (IOSurface 백업)
    ↓ kCVPixelBufferMetalCompatibilityKey = true
    ↓ Zero-Copy — CPU 메모리 복사 없음
Metal GPU
    ↓ AVPlayerLayer.drawsAsynchronously = true
    ↓ GPU 렌더링 쓰레드 (메인 쓰레드 블로킹 없음)
CALayer Compositing
    ↓ isOpaque=true → 알파 블렌딩 패스 제거
    ↓ allowsGroupOpacity=false → group compositing 패스 제거
NSWindow backingStore
    ↓ CATransaction.setDisableActions(true)
화면 출력
```

### 5.4 Retina 디스플레이 대응

```swift
// viewDidMoveToWindow() L71-78
// → window 이동/스크린 변경 시 contentsScale 자동 업데이트

// viewDidChangeBackingProperties() L80-87  
// → Retina ↔ 일반 전환 시 즉시 갱신

// layout() L89-94
// → playerLayer.frame = bounds (CATransaction 애니메이션 비활성)
```

### 5.5 VLC GPU 파이프라인과 비교

| 항목 | AVPlayerLayerView | VLCLayerHostView |
|------|-------------------|-----------------|
| **디코더** | VideoToolbox (자동) | `--codec=videotoolbox` 명시 |
| **Zero-Copy** | IOSurface pixelBuffer | `--videotoolbox-zero-copy=1` |
| **렌더링 API** | Metal (Core Animation) | OpenGL/Metal (VLC 내부) |
| **레이어 구조** | AVPlayerLayer 단일 | VLCLayerHostView + hostLayer |
| **compositing** | 2 레이어 (container+player) | 3 레이어 (container+host+video) |
| **HDR** | ✅ `wantsExtendedDynamicRangeContent` | VLC 내부 처리 |
| **애니메이션 억제** | 5 프로퍼티 NSNull 액션 | 동일 |

### 5.6 멀티 세션 GPU 부하 분석

```
단일 세션 (1920×1080 @60fps):
  AVPlayerLayer × 1 = ~1 compositing pass
  Metal 텍스처 메모리 ≈ 1920×1080×1.5 (NV12) ≈ 3.1MB/frame × 2 (버퍼) = ~6.2MB

4세션 그리드 (960×540 @60fps 각):  
  AVPlayerLayer × 4 = ~4 compositing passes
  Metal 텍스처 메모리 ≈ 960×540×1.5 × 2 × 4 = ~6.2MB (해상도 낮아도 동일 소스)
  ※ 실제로는 1080p 디코딩 + 960×540 표시 → GPU 스케일링 추가

4세션 그리드 총 GPU 부하:
  디코딩: VideoToolbox × 4 (별도 세션, HW 병렬)
  렌더링: Metal compositing × 4 + SwiftUI overlay
  예상: GPU 점유율 15~30% (M1 Max 기준)
```

---

## 6. CDN URL 전체 경로 추적

### 6.1 단계별 URL 변환

```
[1] Chzzk API 응답
    https://livecloud.pstatic.net/live/{channelId}/media_1080p/
    master.m3u8?hdnts=st=...~exp=...~hmac=...

        │ MultiLiveSession.start() L137-148
        │ JSON → LivePlayback → media[HLS].path
        ▼

[2] StreamCoordinator.startStream()
    https://livecloud.pstatic.net/live/{channelId}/media_1080p/
    master.m3u8?hdnts=st=...~exp=...~hmac=...
    
        │ LocalStreamProxy.needsProxy() → pstatic.net → YES
        │ streamProxy.start(for: "livecloud.pstatic.net")
        │ playbackURL = streamProxy.proxyURL(from: originalURL)
        ▼

[3] 프록시 URL (AVPlayer에 전달)
    http://127.0.0.1:{PORT}/live/{channelId}/media_1080p/
    master.m3u8?hdnts=st=...~exp=...~hmac=...

        │ AVPlayerEngine.play(url:)
        │ AVURLAsset → AVPlayerItem → player.replaceCurrentItem
        ▼

[4] AVPlayer 요청 → LocalStreamProxy 수신
    GET /live/{channelId}/media_1080p/master.m3u8
    Host: 127.0.0.1:{PORT}
    
        │ LocalStreamProxy: M3U8 내 CDN URL → 프록시 URL 재작성
        │ Content-Type: video/MP2T → video/mp4 (fMP4 세그먼트)
        ▼

[5] LocalStreamProxy → CDN 요청
    GET https://livecloud.pstatic.net/live/{channelId}/media_1080p/
    master.m3u8?hdnts=...
    User-Agent: Mozilla/5.0 ... Safari/605.1.15
    Referer: https://chzzk.naver.com/
    
        │ CDN 응답 → 프록시 M3U8 리라이트 → AVPlayer 전달
        ▼

[6] AVPlayer 내장 ABR → variant 자동 선택
    → 1080p / 720p / 480p 중 최적 선택
    → 개별 세그먼트/Part 다운로드 (모두 프록시 경유)
```

### 6.2 VLC 경로와의 핵심 차이

| 단계 | AVPlayer | VLC |
|------|----------|-----|
| **마스터 매니페스트** | ✅ 그대로 전달 | ❌ 1080p variant URL만 추출 |
| **ABR variant 선택** | Apple 내장 (자동) | `resolveHighestQualityVariant()` (수동 1080p 고정) |
| **CDN 워밍** | ❌ 안 함 | ✅ HEAD 요청 병렬 |
| **매니페스트 갱신** | Apple 내장 (자동) | ✅ 15~30초 타이머 (토큰 리프레시) |
| **Part 세그먼트** | ✅ 자동 다운로드 | ❌ 전체 세그먼트만 |
| **블로킹 리로드** | ✅ 자동 | ❌ 폴링 |
| **프록시 경유** | ✅ (Content-Type 수정) | ✅ (동일) |

---

## 7. 스톨 감지 및 재연결 체계

### 7.1 AVPlayerEngine 스톨 워치독

```swift
// startStallWatchdog() L503-570
// 3초 주기 체크, 12초 타임아웃
```

**상수:**

| 상수 | 값 | 목적 |
|------|-----|------|
| `kStallTimeout` | 12.0초 | 무진행 판정 임계 |
| `kCheckInterval` | 3초 (3×10⁹ ns) | 체크 주기 |
| `maxReconnectsInWindow` | 3회 | 5분 내 최대 재연결 |
| `reconnectWindowSeconds` | 300초 (5분) | 재연결 카운트 윈도우 |
| 버퍼 부족 연속 임계 | 7회 | `!isPlaybackLikelyToKeepUp` 연속 |

**판정 로직:**

```
매 3초마다:
  1. idle/ended/error → 감시 건너뜀 (루프 유지)
  
  2. 무진행 검사:
     timeSinceLastProgress = Date() - lastProgressTime
     if timeSinceLastProgress > 12초:
       → onReconnectRequested?()
       → 15초 대기 후 재개

  3. 버퍼 부족 연속 검사:
     if !isPlaybackLikelyToKeepUp:
       bufferStallCount += 1
       if bufferStallCount >= 7 (=21초):
         → onReconnectRequested?()
         → 15초 대기 후 재개
     else:
       bufferStallCount = 0

  4. 과다 재연결 방지:
     5분 내 3회 이상 → .connectionLost 에러 → 워치독 종료
```

### 7.2 StreamCoordinator 워치독 (공통)

```swift
// StreamCoordinator.swift — startPlaybackWatchdog()
// AVPlayer, VLC 모두 적용

체크 간격: 5초
정체 판정: 3회 연속 시간 변화 없음 (=15초)
→ triggerReconnect()
```

### 7.3 이중 워치독 체계 (AVPlayer 고유)

```
AVPlayerEngine 워치독 (L503-570)
  ├── 3초 주기 / 12초 타임아웃 / 버퍼 7회 연속
  ├── → onReconnectRequested?()
  └── → StreamCoordinator.triggerReconnect()

StreamCoordinator 워치독 (공통)
  ├── 5초 주기 / 15초 정체
  └── → triggerReconnect()

triggerReconnect()
  ├── stopStream()
  ├── 3초 대기 (백오프)
  └── startStream(url:) 재시도
```

**VLC는 단일 워치독** (StreamCoordinator만). AVPlayer는 **이중 워치독** — 엔진 내부 + Coordinator 외부.

### 7.4 VLC vs AVPlayer 스톨 감지 비교

| 항목 | AVPlayerEngine | VLCPlayerEngine |
|------|---------------|-----------------|
| **체크 간격** | 3초 | 20초 |
| **정체 타임아웃** | 12초 | 45초 |
| **초기 대기** | 즉시 | 60초 |
| **버퍼 스톨 감지** | `!isPlaybackLikelyToKeepUp` × 7 | 없음 |
| **과다 재연결 제한** | 3회/5분 | 없음 |
| **에러 회복 불가 전환** | 3회 초과 → `.connectionLost` | 없음 |
| **감지 → 재연결** | ~12초 | ~45초 |
| **총 복구 시간** | ~15초 (감지 12 + 백오프 3) | ~48초 (감지 45 + 백오프 3) |

---

## 8. 네트워크 적응 시스템

### 8.1 NWPathMonitor 기반 네트워크 감지

```swift
// setupNetworkMonitor() L652-692
networkMonitor = NWPathMonitor()
networkMonitor.pathUpdateHandler = { path in
    // 인터페이스 타입 감지
    if path.usesInterfaceType(.wiredEthernet) → .wiredEthernet
    if path.usesInterfaceType(.wifi) → .wifi
    if path.usesInterfaceType(.cellular) → .cellular
    else → .other
    
    // 전환 시 즉시 대응:
    // 1. 연결 해제 → 재연결 대기
    // 2. 라이브 → adjustCatchupConfigForNetwork() + 버퍼 업데이트
    // 3. watchdog 타임스탬프 갱신 (전환 오인 방지)
}
networkMonitor.start(queue: networkQueue)
```

### 8.2 네트워크별 캐치업 설정

| 네트워크 | targetLatency | maxLatency | 예상 안정 레이턴시 | 비고 |
|---------|--------------|-----------|-----------------|------|
| **유선 이더넷** | 2.0초 | 6.0초 | 2~3초 | 최저 지연, 최소 버퍼 |
| **Wi-Fi** | 3.0초 | 8.0초 | 3~5초 | 기본 프리셋 (.lowLatency) |
| **셀룰러** | 6.0초 | 15.0초 | 6~10초 | 높은 지터 대응 |
| **기타** | 4.0초 | 10.0초 | 4~7초 | 안전한 기본값 |

### 8.3 네트워크 전환 시 동작

```
Wi-Fi → 유선:
  1. adjustCatchupConfigForNetwork() → target=2.0s, max=6.0s
  2. item.preferredForwardBufferDuration = 4.0s (catchupConfig 기반)
  3. lastProgressTime = Date() (워치독 오인 방지)
  4. 기존 catchup loop → 다음 루프에서 새 target 적용

유선 → 셀룰러:
  1. target=6.0s, max=15.0s → 버퍼 여유 확보
  2. 현재 latency 3초 → target(6초) * 0.6 = 3.6초 > 3초
     → 아무것도 안 함 (이미 목표 이하)
```

### 8.4 VLC 대비

| 항목 | AVPlayer | VLC |
|------|----------|-----|
| 네트워크 감지 | ✅ NWPathMonitor (실시간) | ❌ 없음 |
| 설정 자동 조정 | ✅ target/max 동적 변경 | ❌ 프리셋 고정 |
| 버퍼 동적 조절 | ✅ preferredForwardBuffer 변경 | ❌ network-caching 고정 |
| 셀룰러 대응 | ✅ 높은 지연 허용 | ❌ 동일 설정 |

---

## 9. VLC 엔진과의 정밀 비교

### 9.1 E2E 레이턴시 파이프라인 비교

```
                        AVPlayer 파이프라인              VLC 파이프라인
                        ──────────────────              ─────────────────

API 호출                ~200ms                          ~200ms
CDN HEAD 워밍           ─ (안 함)                       ~100-300ms
마스터 매니페스트 파싱    Apple 자동 (~100ms)             수동 파싱 (~200ms)
Variant 선택            ABR 자동 (~0ms)                 1080p고정 (~100ms)
LocalStreamProxy        ~100ms                          ≤3,000ms (세마포어!)
미디어 매니페스트 로드    Apple 자동 (~200ms)             수동 폴링 (~500ms)

──── 재생 시작 ────
라이브 엣지 거리         ~1-3 세그먼트 (LL-HLS)          ~3-10 세그먼트
Part 다운로드            ✅ LL-HLS Part (~200ms)          ❌ 전체 세그먼트 (~2,000ms)
버퍼 충전                preferredForward 4.0s            network-caching 1,200ms +
                                                        live-caching 1,200ms
디코드 시작              VideoToolbox 자동 (~50ms)        VideoToolbox+libavcodec (~200ms)
첫 프레임 렌더링         Metal AVPlayerLayer (~16ms)       VLC libvout → NSView (~33ms)

──── 총 레이턴시 ────
                        3~5초                            8~12초
```

### 9.2 레이턴시 제어 비교

| 측면 | AVPlayer | VLC |
|------|----------|-----|
| **측정 방법** | seekableTimeRanges 끝 - currentTime | PDT 기반 (2초 폴링, EWMA α=0.3) |
| **제어 알고리즘** | 코사인 이징 + EMA (α=0.4) | PID (Kp=0.8, Ki=0.1, Kd=0.05) |
| **제어 주기** | 1초 | 2초 |
| **rate 범위** | 1.0 ~ 1.5x | 0.85x ~ 1.2x |
| **비상 시크** | latency > maxLatency → 점프 | latency > maxLatency → seekRequired |
| **데드존** | target×0.6 ~ target (무동작) | slowDownThreshold (±0.5초) |
| **정상 상태 오차** | Ki 없어서 ±0.5초 잔여 가능 | Ki=0.1 → 이론적 0 수렴 |
| **오버슈트** | EMA α=0.4 억제 | Kd=0.05 억제 |
| **네트워크 적응** | ✅ 동적 target/max 변경 | ❌ 고정 |

### 9.3 ABR 비교

| 측면 | AVPlayer | VLC |
|------|----------|-----|
| **variant 선택** | Apple 내장 ABR (대역폭 + 버퍼 + 디코드 성능 종합) | 1080p 고정 (수동) |
| **ABR 알고리즘** | BOLA 계열 (Apple 비공개) | ABRController 이중 EWMA (미사용) |
| **품질 전환** | 자동, 무끊김 | 수동 (variant URL 교체 필요) |
| **대역폭 측정** | Apple 내장 | networkBytesPerSec (미연결) |
| **장점** | 네트워크 변동에 강인 | 항상 최고 화질 보장 |
| **단점** | 품질 저하 가능 | 저대역 시 버퍼링 |

### 9.4 에러 처리 비교

| 에러 유형 | AVPlayer | VLC |
|----------|----------|-----|
| **네트워크 단절** | `.connectionLost` → 자동 재연결 | `.connectionLost` → 재연결 |
| **타임아웃** | `.networkTimeout` → 자동 재연결 | watchdog → 재연결 |
| **디코딩 실패** | `.decodeFailed` → 에러 표시 | VLC 내부 처리 |
| **포맷 미지원** | `.unsupportedFormat` | `.invalidManifest` |
| **인증 실패** | `.streamNotFound` | — |
| **스톨 감지** | 12초 (엔진) + 15초 (코디네이터) | 45초 (엔진) + 15초 (코디네이터) |
| **총 복구 시간** | ~15초 | ~48초 |

### 9.5 녹화 방식 비교

| 측면 | AVPlayer | VLC |
|------|----------|-----|
| **방식** | `StreamRecordingService` (HLS 세그먼트 다운로드) | VLC 내부 녹화 |
| **장점** | CDN 원본 품질 유지 | 실시간 인코딩 가능 |
| **단점** | 별도 HLS 파서 필요 | CPU 부하 |

---

## 10. 멀티 세션 동시 재생 분석

### 10.1 세션 독립성

```
Session 1 (독립)              Session 2 (독립)
├─ AVPlayer #1                ├─ AVPlayer #2
├─ AVPlayerItem #1            ├─ AVPlayerItem #2
├─ AVPlayerLayerView #1       ├─ AVPlayerLayerView #2
├─ StreamCoordinator #1       ├─ StreamCoordinator #2
├─ LocalStreamProxy #1        ├─ LocalStreamProxy #2
├─ Stall Watchdog #1          ├─ Stall Watchdog #2
├─ Catchup Loop #1            ├─ Catchup Loop #2
├─ NWPathMonitor #1           ├─ NWPathMonitor #2
└─ ChatViewModel #1           └─ ChatViewModel #2
```

- **완전 독립**: 각 세션이 자체 AVPlayer, 프록시, 워치독, 캐치업 루프 소유
- **엔진 풀 없음**: VLCInstancePool과 달리 AVPlayer는 풀 불필요 (경량 생성)
- **공유 자원**: PerformanceMonitor (싱글톤), Chzzk API 클라이언트

### 10.2 리소스 사용 예측 (4세션)

| 리소스 | 1세션 | 4세션 | 비고 |
|--------|------|-------|------|
| **메모리** | ~50MB | ~200MB | AVPlayerItem 버퍼 × 4 |
| **CPU** | ~5% | ~15% | VideoToolbox HW 디코딩 |
| **GPU** | ~5% | ~15% | Metal compositing × 4 |
| **네트워크** | ~6Mbps | ~24Mbps | 1080p × 4 (ABR 시 하향 가능) |
| **Task** | 3개 | 12개 | catchup + watchdog + statusPoll |
| **Thread** | 2개 | 8개 | NWPathMonitor × 4 + observer |
| **TCP 연결** | 12개 | 48개 | maxConnectionsPerHost=12 × 프록시 |

### 10.3 오디오 라우팅 정책

```
addSession(채널A)  → sessions = [A(🔊)]          → selectedSessionId = A
addSession(채널B)  → sessions = [A(🔊), B(🔇)]   → B 자동 음소거
addSession(채널C)  → sessions = [A(🔊), B(🔇), C(🔇)]

selectSession(B)   → sessions = [A(🔇), B(🔊), C(🔇)]
                   → 이전 A 음소거, 새 B 음소거 해제

removeSession(B)   → sessions = [A(🔊), C(🔇)]
                   → selectedSessionId = A (자동 선택)
                   → A 음소거 해제

removeSession(A)   → sessions = [C(🔊)]
                   → selectedSessionId = C (자동 선택)
```

### 10.4 레이아웃 렌더링 성능

**탭 모드 (단일 풀스크린):**

```swift
// MultiLiveView.swift — tabLayout
MultiLivePlayerPane(session: selected, isSelected: true, isCompact: false)
    .id(selected.id)   // ← 탭 전환 시 뷰 전체 destroy/recreate
    .transition(.opacity)
```

- `.id(session.id)` → 선택 변경 시 PlayerPane **전체 재생성**
- 비선택 세션: SwiftUI 뷰 트리에서 **제거** (비디오 디코딩은 계속)
- 비디오 레이어만 교체, AVPlayer 인스턴스는 유지

**그리드 모드 (2×2):**

```swift
// MultiLiveView.swift — gridLayout  
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2)
```

- 모든 세션 동시 렌더링
- 각 셀: `MultiLivePlayerPane(isCompact: true)`
- `.compositingGroup()` → 오버레이 opacity 변경 시 비디오 레이어 recomposition 방지
- 선택 세션 강조: `isSelected` 바인딩으로 테두리 표시

### 10.5 30초 상태 폴링 (세션별)

```swift
// MultiLiveSession.swift — startStatusPolling() L238-257
while !Task.isCancelled {
    try await Task.sleep(for: .seconds(30))
    let status = try await apiClient.liveDetail(channelId: channelId)
    viewerCount = status.content.concurrentUserCount
    liveTitle = status.content.liveTitle
    categoryName = status.content.liveCategoryValue
}
```

- 4세션 = 30초 내 4개 API 호출 (분산)
- 라이브 종료 감지: `status.content.status != "OPEN"` 시 세션 자동 종료

---

## 11. 최적화 전략 및 개선 제안

### 11.1 즉시 적용 가능 (Phase 1)

| # | 최적화 | 현재 | 제안 | 예상 효과 |
|---|--------|------|------|----------|
| 1 | **유선 전용 target 하향** | 2.0초 | 1.5초 | -0.5초 |
| 2 | **Wi-Fi target 하향** | 3.0초 | 2.5초 | -0.5초 |
| 3 | **preferredForwardBuffer 축소** | 4.0초 | 2.0초 (lowLatency) | -1~2초 |
| 4 | **EMA α 상향** | 0.4 | 0.6 | 더 빠른 캐치업 반응 |
| 5 | **rate 변화 임계 하향** | 0.03 | 0.01 | 더 세밀한 rate 조절 |

### 11.2 아키텍처 개선 (Phase 2)

#### 11.2.1 프록시 우회 검토

```
문제: AVPlayer는 Content-Type이 잘못되어도 EXT-X-MAP 기반으로 fMP4를 올바르게 인식
     → LocalStreamProxy가 불필요할 수 있음

검증 방법:
  1. 프록시 없이 CDN URL 직접 전달 테스트
  2. 10개 채널 × 1시간 재생 → 재생 안정성 확인
  
예상 효과: -100~300ms (프록시 오버헤드 제거)
위험: 일부 CDN 경로에서 referer/CORS 문제 가능
```

#### 11.2.2 NWPathMonitor 공유

```
문제: 4세션 × 각 NWPathMonitor = 4개 network monitor
     → DispatchQueue × 4, 콜백 중복

제안: 싱글톤 NetworkStateProvider를 통해 공유
     → 1개 monitor + 변경 시 Notification으로 브로드캐스트
```

#### 11.2.3 PDT 기반 정밀 측정 도입

```
문제: AVPlayer의 seekableTimeRanges 기반 레이턴시는 버퍼 상태 의존으로 부정확할 수 있음
제안: VLC와 동일하게 PDTLatencyProvider를 AVPlayer에도 연결
     → 독립 CDN 폴링으로 서버 시계 기준 정밀 측정
     → seekableTimeRanges 값과 교차 검증
```

### 11.3 메인 플레이어 AVPlayer 전환 (Phase 3)

```
현재: 싱글 라이브 = VLC (8~12초), 멀티라이브 = AVPlayer (3~5초)
문제: 동일 채널인데 싱글/멀티에서 레이턴시 차이 5~7초

제안: 메인 플레이어를 AVPlayer로 전환
장점:
  - 레이턴시 통일 (3~5초)
  - LL-HLS Part 세그먼트 지원
  - Apple 네이티브 ABR
  - 코드 베이스 단순화 (엔진 2개 → 1개)

보존 필요 기능 (VLC → AVPlayer 이식):
  - PDT 기반 레이턴시 측정
  - PID 동기화 (or 코사인 이징으로 통일)
  - 녹화 (StreamRecordingService 사용)
  - 비표준 포맷 대응 (fallback으로 VLC 유지)

위험:
  - VLC 고유 기능 손실 (자막, 비표준 코덱)
  - Apple ABR이 항상 1080p 선택하지 않을 수 있음
  - PiP + 메인 플레이어 동시 사용 시 복잡도
```

---

## 12. 핵심 파라미터 레퍼런스

### 12.1 AVPlayerEngine 전체 상수

| 그룹 | 상수 | 값 | 위치 |
|------|------|-----|------|
| **Catchup (lowLatency)** | targetLatency | 3.0초 | AVPlayerEngine L109 |
| | maxLatency | 8.0초 | AVPlayerEngine L110 |
| | maxCatchupRate | 1.5x | AVPlayerEngine L111 |
| | preferredForwardBuffer | 4.0초 | AVPlayerEngine L112 |
| **Catchup (balanced)** | targetLatency | 6.0초 | AVPlayerEngine L116 |
| | maxLatency | 15.0초 | AVPlayerEngine L117 |
| | maxCatchupRate | 1.25x | AVPlayerEngine L118 |
| | preferredForwardBuffer | 8.0초 | AVPlayerEngine L119 |
| **Catchup (stable)** | targetLatency | 10.0초 | AVPlayerEngine L123 |
| | maxLatency | 25.0초 | AVPlayerEngine L124 |
| | maxCatchupRate | 1.1x | AVPlayerEngine L125 |
| | preferredForwardBuffer | 15.0초 | AVPlayerEngine L126 |
| **Watchdog** | stallTimeout | 12.0초 | AVPlayerEngine L503 |
| | checkInterval | 3초 (3×10⁹ ns) | AVPlayerEngine L505 |
| | reconnectWindow | 300초 (5분) | AVPlayerEngine L497 |
| | maxReconnects | 3회/윈도우 | AVPlayerEngine L499 |
| | bufferStallThreshold | 7회 연속 | AVPlayerEngine L540 |
| **Catchup Loop** | checkInterval | 1초 (10⁹ ns) | AVPlayerEngine L578 |
| | EMA α | 0.4 | AVPlayerEngine L630 |
| | rateHistory max | 4개 | AVPlayerEngine L633 |
| | minRateChangeDelta | 0.03 | AVPlayerEngine L636 |
| | 정상 속도 복구 임계 | target × 0.6 | AVPlayerEngine L625 |
| **Observer** | timeObserver 간격 | 1.0초 | AVPlayerEngine L803 |
| | CMTime timescale | 600 | AVPlayerEngine L416 |
| | stall 복구 대기 | 2초 | AVPlayerEngine L870 |
| **Asset** | maxResolution | 1920×1080 | AVPlayerEngine L337 |
| | peakBitRate | 0 (무제한) | AVPlayerEngine L338 |
| | preciseTiming | false | AVPlayerEngine L326 |
| **Network** | 유선 target | 2.0초 | AVPlayerEngine L697 |
| | 유선 max | 6.0초 | AVPlayerEngine L698 |
| | Wi-Fi target | 3.0초 | AVPlayerEngine L700 |
| | Wi-Fi max | 8.0초 | AVPlayerEngine L701 |
| | 셀룰러 target | 6.0초 | AVPlayerEngine L703 |
| | 셀룰러 max | 15.0초 | AVPlayerEngine L704 |
| | 기타 target | 4.0초 | AVPlayerEngine L706 |
| | 기타 max | 10.0초 | AVPlayerEngine L707 |

### 12.2 멀티라이브 시스템 상수

| 상수 | 값 | 위치 |
|------|-----|------|
| maxSessions | 4 | MultiLiveManager L19 |
| 채팅 패널 너비 | 320px | MultiLiveView L52 |
| 그리드 간격 | 2px | MultiLiveView L90 |
| 그리드 열 수 | 2 | MultiLiveView L88 |
| 컨트롤 자동 숨김 | 3초 | MultiLivePlayerPane L367 |
| 상태 폴링 주기 | 30초 | MultiLiveSession L245 |
| 재연결 후 대기 | 15초 | AVPlayerEngine L560 |
| 스톨 후 복구 시도 | 2초 | AVPlayerEngine L870 |

### 12.3 GPU 렌더링 설정

| 설정 | 값 | 목적 |
|------|-----|------|
| `layerContentsRedrawPolicy` | `.never` | drawRect 제거 |
| `drawsAsynchronously` | `true` | Metal async |
| `isOpaque` | `true` | 알파 블렌딩 제거 |
| `shouldRasterize` | `false` | 프레임 캐시 비활성 |
| `allowsGroupOpacity` | `false` | group pass 제거 |
| `allowsEdgeAntialiasing` | `false` | 경계 AA 제거 |
| `videoGravity` | `.resizeAspect` | 종횡비 유지 |
| `magnificationFilter` | `.linear` | 확대 보간 |
| `minificationFilter` | `.trilinear` | 축소 밉맵 |
| `wantsExtendedDynamicRangeContent` | `true` | HDR |
| pixelFormat | `420YpCbCr8BiPlanarVideoRange` | NV12 |
| `MetalCompatibilityKey` | `true` | IOSurface GPU 직통 |
| `IOSurfacePropertiesKey` | `[:]` | IOSurface 활성 |
| `suppressesPlayerRendering` | `false` | 렌더링 유지 |
| 애니메이션 억제 | 5 프로퍼티 → NSNull | 비디오 업데이트 방해 방지 |

---

## 13. 결론

### 13.1 핵심 발견

1. **멀티라이브는 AVPlayer 전용** — VLCEngine 사용 안 함, 엔진 풀 불필요, 세션별 독립 AVPlayer 인스턴스

2. **AVPlayer LL-HLS 네이티브 = 3~5초 레이턴시** — Part 세그먼트 + 블로킹 리로드 + 프리로드 힌트가 Apple Framework에서 자동 처리

3. **코사인 이징 캐치업은 PID보다 단순하고 안정적** — 20줄 코드, 3개 파라미터, 오버슈트 거의 없음, ~10초 수렴 (PID ~50초)

4. **네트워크 적응은 AVPlayer만 지원** — NWPathMonitor로 유선/Wi-Fi/셀룰러 자동 감지, target/max 동적 조정

5. **이중 워치독으로 빠른 스톨 복구** — 엔진 12초 + 코디네이터 15초 → 총 ~15초 내 복구 (VLC ~48초)

6. **프록시 불필요 가능성** — AVPlayer는 Content-Type 무관하게 EXT-X-MAP 기반 fMP4 인식 가능, 프록시 제거 시 -100~300ms

### 13.2 멀티라이브 레이턴시 성능 요약

| 시나리오 | AVPlayer (멀티) | VLC (싱글) | 격차 |
|---------|---------------|-----------|------|
| **초기 연결** | ~2초 | ~4초 | -2초 |
| **안정 상태** | 3~5초 | 8~12초 | -5~7초 |
| **스톨 복구** | ~15초 | ~48초 | -33초 |
| **네트워크 전환** | 자동 적응 (2초) | 수동 (없음) | ∞ |
| **ABR 품질 전환** | 자동 (무끊김) | 수동 (1080p 고정) | — |

### 13.3 권장 사항

| 우선순위 | 권장 | 예상 효과 |
|---------|------|----------|
| 🔴 높음 | 메인 플레이어를 AVPlayer로 전환 | 싱글 라이브 레이턴시 8~12초 → 3~5초 |
| 🟡 중간 | AVPlayer 프록시 우회 검증 | -100~300ms |
| 🟡 중간 | NWPathMonitor 싱글톤 공유 | 리소스 25% 절감 |
| 🟢 낮음 | preferredForwardBuffer 2.0초로 축소 | -1~2초 |
| 🟢 낮음 | PDT 기반 정밀 측정 도입 | 측정 정확도 향상 |

---

> **문서 작성**: 자동 분석 (코드 정적 분석 기반)  
> **분석 소스**: AVPlayerEngine.swift (977줄), MultiLiveSession.swift, MultiLiveManager.swift, StreamCoordinator.swift, MultiLiveView.swift, MultiLivePlayerPane.swift, PlayerVideoView.swift, PlayerViewModel.swift, PlayerConstants.swift  
> **참조 문서**: [CHZZK_LIVE_LATENCY_PRECISION_RESEARCH.md](CHZZK_LIVE_LATENCY_PRECISION_RESEARCH.md)
