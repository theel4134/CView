# CView_v2 영상 재생 시스템 종합 기술 문서

> 최종 업데이트: 2026-02-27

---

## 목차

1. [아키텍처 개요](#1-아키텍처-개요)
2. [핵심 프로토콜 및 모델 (CViewCore)](#2-핵심-프로토콜-및-모델-cviewcore)
3. [플레이어 엔진 (CViewPlayer)](#3-플레이어-엔진-cviewplayer)
   - 3.1 VLCPlayerEngine
   - 3.2 AVPlayerEngine
4. [스트림 관리 컴포넌트](#4-스트림-관리-컴포넌트)
   - 4.1 StreamCoordinator (오케스트레이터)
   - 4.2 ABRController (적응형 비트레이트)
   - 4.3 HLSManifestParser (매니페스트 파싱)
   - 4.4 HLSPrefetchService (프리페치)
   - 4.5 LocalStreamProxy (로컬 프록시)
   - 4.6 LowLatencyController (저지연 제어)
   - 4.7 PDTLatencyProvider (레이턴시 측정)
   - 4.8 PlaybackReconnectionHandler (재연결)
   - 4.9 StreamRecordingService (녹화)
5. [PiP (Picture-in-Picture)](#5-pip-picture-in-picture)
6. [비디오 렌더링 뷰](#6-비디오-렌더링-뷰)
7. [ViewModel 계층](#7-viewmodel-계층)
   - 7.1 PlayerViewModel (라이브)
   - 7.2 VODPlayerViewModel (VOD)
   - 7.3 ClipPlayerViewModel (클립)
8. [UI View 계층](#8-ui-view-계층)
9. [멀티라이브 시스템](#9-멀티라이브-시스템)
10. [전체 재생 파이프라인](#10-전체-재생-파이프라인)
11. [설계 결정 요약](#11-설계-결정-요약)
12. [상수 및 기본값](#12-상수-및-기본값)

---

## 1. 아키텍처 개요

CView_v2의 영상 재생 시스템은 **모듈러 SPM 패키지** 구조로 설계되어 있으며, 핵심 모듈은 다음과 같다:

```
┌─────────────────────────────────────────────────────────┐
│                    CViewApp (Views/ViewModels)           │
│  LiveStreamView ─ PlayerControlsView ─ MultiLiveView    │
│  PlayerViewModel ─ VODPlayerViewModel ─ ClipPlayerVM     │
├─────────────────────────────────────────────────────────┤
│                    CViewPlayer (엔진 계층)                │
│  VLCPlayerEngine ─ AVPlayerEngine ─ StreamCoordinator   │
│  ABRController ─ HLSManifestParser ─ LocalStreamProxy   │
│  LowLatencyController ─ PiPController ─ VLCInstancePool │
│  PlaybackReconnectionHandler ─ StreamRecordingService    │
├─────────────────────────────────────────────────────────┤
│                    CViewCore (프로토콜/모델)              │
│  PlayerEngineProtocol ─ PlayerState ─ PlayerModels      │
│  VLCPlayerMetrics ─ PlayerConstants                      │
└─────────────────────────────────────────────────────────┘
```

**두 가지 플레이어 엔진**을 추상화 프로토콜로 통합:
- **VLCPlayerEngine** — VLCKit 4.0 기반, 저지연 라이브 스트리밍 기본 엔진
- **AVPlayerEngine** — AVFoundation 기반, 안정성 우선 대안 엔진

---

## 2. 핵심 프로토콜 및 모델 (CViewCore)

### 2.1 PlayerEngineProtocol

> 파일: `Sources/CViewCore/Protocols/PlayerEngineProtocol.swift` (~110 lines)

모든 플레이어 엔진이 준수하는 통합 인터페이스.

```swift
protocol PlayerEngineProtocol: AnyObject, Sendable {
    // 상태
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var rate: Float { get }
    var videoView: NSView { get }
    var isRecording: Bool { get }
    var isInErrorState: Bool { get }
    
    // 재생 제어
    func play(url: URL) async throws
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
    func setRate(_ rate: Float)
    func setVolume(_ volume: Float)       // 0.0 ~ 1.0
    
    // 녹화
    func startRecording(to url: URL) async throws
    func stopRecording()
    
    // 복구
    func resetRetries()
    
    // 트랙 이벤트 콜백
    var onTrackEvent: (@Sendable (TrackEvent) -> Void)? { get set }
}
```

**관련 타입:**

| 타입 | 설명 |
|------|------|
| `PlayerTrackType` | `.audio`, `.video`, `.text`, `.unknown` |
| `TrackEventKind` | `.added`, `.removed`, `.updated`, `.selected(unselectedId:)` |
| `TrackEvent` | `trackId`, `trackType`, `kind` |
| `PlayerEngineFactory` | 엔진 생성 팩토리 프로토콜 |

### 2.2 PlayerState / PlayerModels

> 파일: `Sources/CViewCore/Models/PlayerModels.swift` (~130 lines)

```swift
struct PlayerState {
    var phase: Phase
    var currentTime: TimeInterval
    var duration: TimeInterval
    var bufferedDuration: TimeInterval
    var playbackRate: Float
    var volume: Float
    var latency: TimeInterval
    var quality: String
    
    enum Phase {
        case idle
        case loading
        case buffering(progress: Double)
        case playing
        case paused
        case error(PlayerError)
        case ended
    }
}
```

**PlayerError** (12가지):
| 에러 | 설명 |
|------|------|
| `.streamNotFound` | 스트림을 찾을 수 없음 |
| `.networkTimeout` | 네트워크 타임아웃 |
| `.decodingFailed` | 디코딩 실패 |
| `.engineInitFailed` | 엔진 초기화 실패 |
| `.unsupportedFormat` | 지원하지 않는 형식 |
| `.hlsParsingFailed` | HLS 파싱 실패 |
| `.invalidManifest` | 잘못된 매니페스트 |
| `.connectionLost` | 연결 끊김 |
| `.authRequired` | 인증 필요 |
| `.recordingFailed` | 녹화 실패 |

**PlaybackOptions:**
```swift
struct PlaybackOptions {
    var quality: String?
    var lowLatencyMode: Bool
    var networkCaching: Int
    var liveCaching: Int
    
    // 프리셋
    static let ultraLowLatency = ...
    static let balanced = ...
    static let stable = ...
}
```

**PlayerEngineType:**
```swift
enum PlayerEngineType {
    case vlc       // "VLC (저지연)"
    case avPlayer  // "AVPlayer (안정)"
}
```

### 2.3 VLCPlayerMetrics

> 파일: `Sources/CViewCore/Models/VLCPlayerMetrics.swift` (~125 lines)

2초 주기로 수집되는 VLC 엔진 성능 메트릭 스냅샷:

```swift
struct VLCLiveMetrics: Sendable {
    // 비디오
    let fps: Float
    let droppedFramesDelta: Int
    let decodedFramesDelta: Int
    
    // 네트워크
    let networkBytesPerSec: Int
    let inputBitrateKbps: Double
    let demuxBitrateKbps: Double
    
    // 해상도
    let resolution: String
    let videoWidth: Int
    let videoHeight: Int
    
    // 재생
    let playbackRate: Float
    let bufferHealth: Double
    
    // 오디오
    let lostAudioBuffersDelta: Int
    
    // VLCKit 4.0 전용
    let latePicturesDelta: Int
    let demuxCorruptedDelta: Int
    let demuxDiscontinuityDelta: Int
    
    // 계산 프로퍼티
    var dropRatio: Double { ... }
    var healthScore: Double { ... }  // 가중 평균 0.0~1.0
}
```

**healthScore 가중치:**
| 요소 | 가중치 |
|------|--------|
| FPS (30fps 기준) | 30% |
| Buffer Health | 25% |
| Drop Ratio (반전) | 20% |
| Audio Loss (반전) | 10% |
| Late Pictures (반전) | 10% |
| Demux Issues (반전) | 5% |

---

## 3. 플레이어 엔진 (CViewPlayer)

### 3.1 VLCPlayerEngine

> 파일: `Sources/CViewPlayer/VLCPlayerEngine.swift` (2,024 lines)

VLCKit 4.0 기반 메인 재생 엔진. 저지연 라이브 스트리밍에 최적화.

#### 3.1.1 스트리밍 프로파일

```swift
enum VLCStreamingProfile {
    case normal           // 일반 재생
    case lowLatency       // 저지연 모드
    case multiLiveBackground  // 멀티라이브 배경 탭
    case highBuffer       // 불안정 네트워크 대응
}
```

| 파라미터 | normal | lowLatency | multiLiveBG | highBuffer |
|----------|--------|------------|-------------|------------|
| networkCaching | 2500ms | 1500ms | 2000ms | 5000ms |
| liveCaching | 2000ms | 1200ms | 1500ms | 3000ms |
| adaptiveLiveDelay | 3s | 2s | 4s | 5s |
| metricsInterval | 2s | 2s | 10s | 5s |
| stallThreshold | 45s | 30s | 45s | 60s |
| avcodecThreads | 4 | 2 | 2 | 4 |
| frameSkip | false | true | true | false |

#### 3.1.2 VLC 미디어 옵션 구성

`configureMediaOptions(_:)` 메서드에서 VLC 미디어에 적용하는 주요 옵션:

```
--network-caching={ms}
--live-caching={ms}
--adaptive-livedelay={s}
--cr-average={ms}
--adaptive-maxbuffer={ms}
--avcodec-threads={n}
--avcodec-skiploopfilter={n}
```

#### 3.1.3 재생 제어 흐름

```
play(url:) async throws
    ├ 세대 카운터 증가 (_operationGeneration)
    ├ VLCMedia 생성
    ├ configureMediaOptions() → VLC 옵션 설정
    ├ MainActor: player.drawable = videoView
    ├ player.play(media)
    ├ startStallWatchdog()      — 20초 주기, 재생 위치 무변화 감시
    ├ startLiveSyncDriftMonitor() — 60초 주기, 라이브 drift 보정
    └ startMetricsTimer()        — 프로파일별 2~10초 주기 메트릭 수집
```

#### 3.1.4 스톨 감지 및 복구

**스톨 워치독** (20초 주기):
- `_lastPositionMillis` / `_lastPositionDate`로 재생 위치 변화 추적
- `stallThreshold` (프로파일별 30~60초) 초과 시 `attemptRecovery()` 호출

**통합 복구 경로** `attemptRecovery(url:reason:)`:
```
쿨다운 체크 (5초 이내 재시도 방지)
    → 남은 재시도 횟수 확인 (기본 3회)
    → 지수 백오프 대기
    → onRecoveryURLRefresh 콜백으로 URL 갱신 시도
    → 미디어 재생성 + play()
```

**라이브 Drift 모니터** (60초 주기):
- `duration - currentTime` 기반 drift 감지
- 2회 연속 drift 발견 시 seek 점프로 보정

#### 3.1.5 자동 프로파일 전환

`evaluateProfileSwitch()` — healthScore 기반:
| healthScore 범위 | 전환 대상 |
|------------------|-----------|
| > 0.9 | `lowLatency` (적극적 저지연) |
| 0.7 ~ 0.9 | `normal` (균형) |
| < 0.7 | `highBuffer` (안정성 우선) |

#### 3.1.6 VLC 4.0 고급 기능

**이퀄라이저:**
```swift
func equalizerPresets() -> [(index: Int, name: String)]
func setEqualizerPreset(_ index: Int)
func setEqualizerPresetByName(_ name: String)
func setEqualizerPreAmp(_ value: Float)
func setEqualizerBand(index: Int, value: Float)
func equalizerBandCount() -> Int
func equalizerBandFrequencies() -> [Float]
func equalizerBandValues() -> [Float]
func resetEqualizer()
```

**비디오 필터 (조정):**
```swift
func setVideoAdjustEnabled(_ enabled: Bool)
func setVideoBrightness(_ value: Float)   // 0.0 ~ 2.0
func setVideoContrast(_ value: Float)     // 0.0 ~ 2.0
func setVideoSaturation(_ value: Float)   // 0.0 ~ 3.0
func setVideoHue(_ value: Float)          // -180 ~ 180
func setVideoGamma(_ value: Float)        // 0.01 ~ 10.0
func resetVideoAdjust()
```

**화면 비율:**
```swift
func setAspectRatio(_ ratio: String?)           // "16:9", "4:3", nil(기본)
func setCropRatio(numerator: Int, denominator: Int)
func setScaleFactor(_ factor: Float)
```

**자막:**
```swift
func textTracks() -> [(id: Int, name: String)]
func selectTextTrack(_ id: Int)
func deselectAllTextTracks()
func addSubtitleFile(url: URL)
func setSubtitleDelay(_ delay: TimeInterval)
func setSubtitleFontScale(_ scale: Float)
```

**오디오 고급:**
```swift
func setAudioStereoMode(_ mode: Int)
func setAudioMixMode(_ mode: Int)
func setAudioDelay(_ delay: TimeInterval)
func applyAdvancedSettings(_ settings: PlayerAdvancedSettings)
func applyLowLatencyConfig()  // 미디어 재생성으로 즉시 반영
```

#### 3.1.7 스레드 안전성

- `NSLock` 기반 동기화 (`lock.withLock { }`)
- `@unchecked Sendable` 선언
- 세대 카운터 (`_operationGeneration`)로 stop/play 레이스 조건 방지
- VLC delegate 콜백은 `@MainActor`로 dispatch

#### 3.1.8 멀티라이브 지원

```swift
func resetForReuse()        // 풀 반납 시 상태 초기화
func setVideoTrackEnabled(_ enabled: Bool)  // 배경 탭 비디오 비활성화
func refreshDrawable()      // drawable 재설정
func setMuted(_ muted: Bool)
func setTimeUpdateMode(background: Bool)    // 배경 시 시간 업데이트 주기 감소
```

---

### 3.2 AVPlayerEngine

> 파일: `Sources/CViewPlayer/AVPlayerEngine.swift` (915 lines)

AVFoundation 기반 안정성 우선 대안 엔진.

#### 3.2.1 구조

```swift
class AVPlayerEngine: NSObject, PlayerEngineProtocol, @unchecked Sendable {
    let player: AVPlayer
    var catchupConfig: AVLiveCatchupConfig
    var _videoView: AVPlayerLayerView    // AVPlayerLayer 호스팅 NSView
}
```

**AVPlayerLayerView** (NSView):
- AVPlayerLayer를 backing layer로 사용
- Retina 대응 (`contentsScale = backingScaleFactor`)
- Trilinear 필터링 품질

#### 3.2.2 저지연 HLS 설정

```swift
// AVPlayerItem 저지연 프로퍼티
item.automaticallyPreservesTimeOffsetFromLive = true
item.configuredTimeOffsetFromLive = targetLatency
item.preferredForwardBufferDuration = preferredForwardBuffer
item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
```

**캐치업 구성 프리셋:**

| 프리셋 | targetLatency | maxLatency | maxCatchupRate | forwardBuffer |
|--------|---------------|------------|----------------|---------------|
| `.lowLatency` | 3s | 8s | 1.5x | 6s |
| `.balanced` | 6s | 15s | 1.25x | 10s |
| `.stable` | 10s | 25s | 1.1x | 15s |

#### 3.2.3 네트워크 적응

`NWPathMonitor` 기반 네트워크 유형 감지:
| 네트워크 | 적용 프리셋 |
|----------|-------------|
| WiFi | `.lowLatency` |
| Cellular | `.balanced` |
| Wired Ethernet | `.lowLatency` |
| 기타 | `.balanced` |

#### 3.2.4 라이브 캐치업 메커니즘

```
accessLog → 현재 latency 측정
    → maxLatency 초과 시:
        rate = min(1.0 + (latency - target) * 0.1, maxCatchupRate)
        점진적 가속
    → latency 안정화 시:
        rate = 1.0 복귀
```

#### 3.2.5 스톨 워치독

- 3초 주기 체크 (VLC의 20초보다 빠름)
- 12초 이상 무진행 시 `seekToLive()` + 복구 시도

#### 3.2.6 에러 분류

`classifyError(_:)` — AVFoundation 에러 코드 → PlayerError 매핑:
| AVError 코드 | PlayerError |
|--------------|-------------|
| `fileNotFound`, `assetNotPlayable` | `.streamNotFound` |
| `mediaServicesWereReset` | `.engineInitFailed` |
| `decoderNotFound` | `.decodingFailed` |
| `serverIncorrectlyConfigured` | `.invalidManifest` |
| 기타 | `.connectionLost` |

#### 3.2.7 추가 기능

```swift
func setVideoLayerVisible(_ visible: Bool)   // 멀티라이브 배경 탭 GPU 합성 제거
func setFillMode(_ mode: AVLayerVideoGravity) // .resizeAspect / .resizeAspectFill
```

---

## 4. 스트림 관리 컴포넌트

### 4.1 StreamCoordinator

> 파일: `Sources/CViewPlayer/StreamCoordinator.swift` (901 lines)

스트림 생명주기 **오케스트레이터**. 모든 컴포넌트를 조합하여 재생을 관리.

#### 스트림 페이즈

```swift
enum StreamPhase {
    case idle
    case connecting
    case buffering
    case playing
    case paused
    case error(String)
    case reconnecting
}
```

#### 내부 컴포넌트 구성

```
StreamCoordinator
    ├ playerEngine: PlayerEngineProtocol
    ├ abrController: ABRController
    ├ lowLatencyController: LowLatencyController
    ├ pdtLatencyProvider: PDTLatencyProvider
    ├ reconnectionHandler: PlaybackReconnectionHandler
    ├ hlsParser: HLSManifestParser
    └ _masterPlaylist: MasterPlaylist?
```

#### 이벤트 스트림 (AsyncStream)

```swift
enum StreamEvent {
    case phaseChanged(StreamPhase)
    case qualitySelected(StreamQualityInfo)
    case qualityChanged(StreamQualityInfo)
    case abrDecision(ABRDecision)
    case latencyUpdate(LatencyInfo)
    case bufferUpdate(BufferHealth)
    case error(PlayerError)
    case stopped
}
```

#### 핵심 흐름

```swift
// 1. 스트림 시작
func startStream(url: URL) async throws
    → loadManifestInfo(url:)     // HLS master playlist 파싱 후 캐싱
    → selectInitialQuality()     // ABR 기반 초기 variant 선택
    → playerEngine.play(variantURL)
    → startLowLatencySync()      // PDT + PID 제어

// 2. 품질 전환
func switchQualityByBandwidth(_ quality: StreamQualityInfo)  // 수동
func evaluateQualityAdaptation()                              // ABR 자동

// 3. 저지연 동기화
func startLowLatencySync()
    → pdtLatencyProvider.start(mediaPlaylistURL:)
    → lowLatencyController.startSync(latencyProvider:)

// 4. 재연결
func triggerReconnect(reason: String)
    → reconnectionHandler.startReconnecting(onAttempt:onExhausted:)

// 5. 종료
func stopStream()
    → 모든 controller.stop() → playerEngine.stop()
```

### 4.2 ABRController (적응형 비트레이트)

> 파일: `Sources/CViewPlayer/ABRController.swift` (229 lines)

**Dual EWMA** 알고리즘 기반 대역폭 추정 및 품질 결정.

```swift
actor ABRController {
    // EWMA 파라미터
    var shortEWMA: Double     // alpha = 0.3 (빠른 반응)
    var longEWMA: Double      // alpha = 0.1 (안정)
    
    func recordBandwidthSample(bytesLoaded: Int, duration: TimeInterval)
    func evaluateQuality(currentBandwidth: Double, variants: [Variant]) -> ABRDecision
}
```

**결정 로직:**

```
safeEstimate = min(shortEWMA, longEWMA) × safetyFactor(0.7)

상향 전환: safeEstimate > currentBandwidth × switchUpFactor(1.2)
하향 전환: safeEstimate < currentBandwidth × switchDownFactor(0.8)
유지:      그 외

+ minSwitchInterval(5s)로 급격한 전환 방지
```

```swift
enum ABRDecision {
    case maintain
    case switchUp(to: Variant, reason: String)
    case switchDown(to: Variant, reason: String)
}
```

### 4.3 HLSManifestParser

> 파일: `Sources/CViewPlayer/HLSManifestParser.swift` (~360 lines)

HLS M3U8 매니페스트 파싱.

**파싱 대상:**

```swift
struct MasterPlaylist {
    var variants: [Variant]
    var sessionData: [String: String]
}

struct Variant {
    let bandwidth: Int
    let resolution: CGSize?
    let codecs: String?
    let frameRate: Float?
    let name: String?
    let uri: URL
    var qualityLabel: String { /* 계산 */ }
}

struct MediaPlaylist {
    var segments: [Segment]
    var targetDuration: TimeInterval
    var mediaSequence: Int
    var isEndList: Bool
    var pdtDates: [Date]
    var programDateTimeStartIndex: Int?
}

struct Segment {
    let uri: URL
    let duration: TimeInterval
    let title: String?
    let sequence: Int
    let programDateTime: Date?
}
```

**파싱 태그:**
- `#EXT-X-STREAM-INF` — BANDWIDTH, RESOLUTION, CODECS, FRAME-RATE, NAME
- `#EXTINF` — 세그먼트 duration
- `#EXT-X-PROGRAM-DATE-TIME` — ISO8601 타임스탬프
- `#EXT-X-ENDLIST` — VOD 종료 표시

### 4.4 HLSPrefetchService

> 파일: `Sources/CViewPlayer/HLSPrefetchService.swift` (~195 lines)

채널 호버 시 HLS master playlist를 미리 가져와 스트림 시작 시간 ~400ms 절약.

```swift
actor HLSPrefetchService {
    struct PrefetchedStream {
        let liveInfo: LiveDetail
        let streamURL: URL
        let channelName: String
        let liveTitle: String
        let fetchedAt: Date     // 60초 TTL
    }
    
    func prefetch(channelId: String, using apiClient: ChzzkAPIClient)
    func consumePrefetchedStream(channelId: String) -> PrefetchedStream?
    func invalidate(channelId: String)
    func invalidateAll()
}
```

### 4.5 LocalStreamProxy

> 파일: `Sources/CViewPlayer/LocalStreamProxy.swift` (422 lines)

로컬 HTTP 프록시 서버. 치지직 CDN의 인증 요구사항(User-Agent, Referer 헤더)을 충족.

```
[VLC/AVPlayer] → http://127.0.0.1:{port}/... → [LocalStreamProxy]
                                                    ├ 원본 URL 복원
                                                    ├ User-Agent: Safari UA 주입
                                                    ├ Referer: chzzk.naver.com 주입
                                                    └ upstream CDN 요청 → 응답 릴레이
```

**구현:**
- `NWListener` 기반 (Network.framework)
- 랜덤 포트 바인딩
- `proxyURL(for:) -> URL` — 원본 HLS URL을 로컬 프록시 URL로 변환
- Keep-Alive: 30초 타임아웃
- 최대 연결: 호스트당 12개

### 4.6 LowLatencyController

> 파일: `Sources/CViewPlayer/LowLatencyController.swift` (~250 lines)

PID 제어기 기반 실시간 저지연 동기화.

```swift
actor LowLatencyController {
    var targetLatency: TimeInterval = 3.0   // 기본 목표
    let minRate: Float = 0.9
    let maxRate: Float = 1.15
    
    // PID 계수
    let Kp: Double = 0.15
    let Ki: Double = 0.01
    let Kd: Double = 0.05
    
    func startSync(latencyProvider: () async -> TimeInterval?)
    func stopSync()
    
    // 콜백
    var onRateAdjust: ((Float) -> Void)?
    var onLatencyUpdate: ((TimeInterval) -> Void)?
}
```

**PID 제어 동작:**
```
3초 주기 실행:
    error = measuredLatency - targetLatency
    
    |error| < 0.5초 → mildAdjustmentFactor(0.05) 적용 (과도 조정 방지)
    
    output = Kp × error + Ki × integral + Kd × derivative
    newRate = clamp(1.0 + output, minRate, maxRate)
```

### 4.7 PDTLatencyProvider

> 파일: `Sources/CViewPlayer/PDTLatencyProvider.swift` (~140 lines)

HLS `#EXT-X-PROGRAM-DATE-TIME` 기반 실제 레이턴시 측정.

```swift
actor PDTLatencyProvider {
    func start(mediaPlaylistURL: URL)
    func currentLatency() -> TimeInterval?
    func stop()
    var isReady: Bool
}
```

**측정 원리:**
```
10초 주기 미디어 플레이리스트 재파싱
    → 마지막 세그먼트의 PDT timestamp 확인
    → latency = Date.now - lastSegmentPDT
```

### 4.8 PlaybackReconnectionHandler

> 파일: `Sources/CViewPlayer/PlaybackReconnectionHandler.swift` (~170 lines)

지수 백오프 재연결 전략.

```swift
actor PlaybackReconnectionHandler {
    struct Config {
        let maxAttempts: Int = 5
        let initialDelay: TimeInterval = 2.0
        let maxDelay: TimeInterval = 30.0
        let backoffMultiplier: Double = 2.0
        let jitterRange: ClosedRange<Double> = 0.8...1.2
    }
    
    func startReconnecting(onAttempt:, onExhausted:)
    func handleSuccess()
}
```

**지연 계산:**
```
delay = min(initialDelay × backoffMultiplier^attempt, maxDelay) × jitter
jitter = random(0.8 ~ 1.2)    // thundering herd 방지
```

### 4.9 StreamRecordingService

> 파일: `Sources/CViewPlayer/StreamRecordingService.swift` (~200 lines)

HLS 세그먼트 기반 녹화 (엔진 독립적).

```swift
actor StreamRecordingService {
    enum RecordingState {
        case idle
        case recording
        case stopping
        case error(String)
    }
    
    func startRecording(playlistURL: URL, to outputURL: URL)
    func stopRecording()
}
```

**녹화 방식:**
```
2초 주기 미디어 플레이리스트 폴링
    → 미다운로드 세그먼트 필터링
    → 세그먼트 HTTP 다운로드
    → MPEG-TS 파일에 순차 연결(append)

기본 저장 경로: ~/Movies/CView/{channelName}_{timestamp}.ts
```

---

## 5. PiP (Picture-in-Picture)

> 파일: `Sources/CViewPlayer/PiPController.swift` (~400 lines)

AVKit `AVPictureInPictureController` 대신 **NSPanel 기반 커스텀 PiP** 구현 (VLC 호환성).

```swift
class PiPController: ObservableObject {
    static let shared = PiPController()     // 싱글톤
    
    @Published var isActive: Bool
    @Published var isMuted: Bool
    var pipWindow: NSPanel?
    
    // 콜백
    var onToggleMute: (() -> Void)?
    var onReturnToMain: (() -> Void)?
    
    func togglePiP(vlcEngine: VLCPlayerEngine?, avEngine: AVPlayerEngine?, title: String?)
    func enterPiP(vlcEngine:, avEngine:, title:)
    func exitPiP()
}
```

**PiP 윈도우 속성:**
- `isFloatingPanel = true`
- `level = .floating` (항상 위)
- `styleMask = [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]`

**PiP 호버 컨트롤 (`PiPHoverControlsView`):**
- 음소거/해제 버튼
- 메인 윈도우로 돌아가기 버튼
- 마우스 호버 시에만 표시

---

## 6. 비디오 렌더링 뷰

### 6.1 PlayerVideoView (통합)

> 파일: `Sources/CViewPlayer/PlayerVideoView.swift` (~200 lines)

```swift
struct PlayerVideoView: NSViewRepresentable {
    let videoView: NSView?
    let fill: Bool      // aspect-fill vs aspect-fit
}
```

**PlayerContainerView** (NSView):
- GPU 최적화: `layerContentsRedrawPolicy = .never`
- 모든 CA 암묵적 애니메이션 비활성화
- 크래시 방지: `isLayingOut` 플래그로 layout() 중 subview 교체 시 다음 RunLoop으로 지연

### 6.2 VLCVideoView (VLC 전용)

> 파일: `Sources/CViewPlayer/VLCVideoView.swift` (~130 lines)

멀티라이브 최적화용 VLC 전용 뷰. `VLCLayerHostView` 직접 관리.

### 6.3 AVVideoView (AVPlayer 전용)

> 파일: `Sources/CViewPlayer/AVVideoView.swift` (~95 lines)

AVPlayerLayer 호스팅 전용 뷰. `setFillMode(_:)` 지원.

---

## 7. ViewModel 계층

### 7.1 PlayerViewModel (라이브 스트림)

> 파일: `Sources/CViewApp/ViewModels/PlayerViewModel.swift` (995 lines)

라이브 스트림 재생의 핵심 ViewModel.

```swift
@Observable @MainActor
class PlayerViewModel {
    // 재생 상태
    var streamPhase: StreamPhase
    var currentQuality: StreamQualityInfo?
    var availableQualities: [StreamQualityInfo]
    var latencyInfo: LatencyInfo?
    var latencyHistory: [LatencyDataPoint]
    var bufferHealth: BufferHealth?
    var playbackRate: Float
    var volume: Float
    var isMuted: Bool
    var isFullscreen: Bool
    var isAudioOnly: Bool
    var showControls: Bool
    var errorMessage: String?
    
    // 스트림 정보
    var isLiveStream: Bool
    var isRecording: Bool
    var recordingDuration: TimeInterval
    var recordingURL: URL?
    var channelName: String
    var liveTitle: String
    var viewerCount: Int
    var uptime: TimeInterval
    var currentChannelId: String?
    
    // VLC 고급 설정
    var isEqualizerEnabled: Bool
    var equalizerPresetName: String?
    var equalizerPreAmp: Float
    var equalizerBands: [Float]
    var isVideoAdjustEnabled: Bool
    // ... 비디오 필터, 화면비, 오디오, 자막 관련 프로퍼티
    
    // 엔진 관리
    var currentEngineType: PlayerEngineType
    var preferredEngineType: PlayerEngineType
    var playerEngine: (any PlayerEngineProtocol)?
    var streamCoordinator: StreamCoordinator?
    var isPreallocated: Bool
}
```

#### 핵심 메서드

```swift
// 스트림 시작/종료
func startStream(channelId:, streamUrl:, channelName:, liveTitle:) async
func stopStream() async

// 재생 제어
func togglePlayPause() async
func setVolume(_ volume: Float)
func toggleMute()
func switchQuality(_ quality: StreamQualityInfo) async
func toggleFullscreen()
func setPlaybackRate(_ rate: Float)
func showControlsTemporarily()

// 모드 전환
func setBackgroundMode(_ isBackground: Bool)    // 멀티라이브 배경 탭
func toggleAudioOnly()                           // 오디오 전용 모드

// 스크린샷
func takeScreenshot()    // VLC captureSnapshot → ~/Pictures/CView Screenshots/

// 녹화
func startRecording(to url: URL) async
func stopRecording()
func toggleRecording() async
func startRecordingWithSavePanel()

// VLC 고급 설정
func applyEqualizerPreset(_ index: Int)
func setEqualizerPreAmp(_ value: Float)
func setEqualizerBand(index: Int, value: Float)
func disableEqualizer()
// ... 비디오 필터, 화면비, 오디오, 자막 전체 메서드

// 멀티라이브 지원
func applyMultiLiveConstraints(paneCount: Int)
func setVLCMetricsCallback(_ callback:)

// 이벤트 처리
func handleStreamEvent(_ event: StreamEvent)
```

#### 스트림 시작 상세 흐름

```
startStream()
    ├ 엔진 생성 (isPreallocated이면 재사용)
    ├ StreamCoordinator 생성 (엔진 + ABR + HLS파서 + 재연결핸들러)
    ├ 엔진 설정:
    │   ├ VLC onStateChange 콜백 → streamPhase 업데이트
    │   ├ VLC onVLCMetrics 콜백 → MetricsForwarder + ABR 피드
    │   └ VLC onQualityAdaptationRequest 콜백
    ├ VLC 고급 설정 자동 적용 (저장된 설정)
    ├ 이벤트 리스닝 Task 시작
    ├ waitForViewMounted() — 최대 2초 UIView 마운트 대기
    └ coordinator.startStream(url:)
```

### 7.2 VODPlayerViewModel

> 파일: `Sources/CViewApp/ViewModels/VODPlayerViewModel.swift` (~220 lines)

AVPlayerEngine 전용 VOD 재생 ViewModel.

```swift
@Observable @MainActor
class VODPlayerViewModel {
    func startVOD(videoNo: Int) async
    func togglePlayPause()
    func seek(to time: TimeInterval)
    func seekRelative(_ delta: TimeInterval)
    func setSpeed(_ speed: PlaybackSpeed)
    func setVolume(_ volume: Float)
    func toggleMute()
    func adjustVolume(_ delta: Float)
    func toggleFullscreen()
    func stop()
    
    enum PlaybackSpeed: Float, CaseIterable {
        case x0_25 = 0.25
        case x0_5 = 0.5
        case x0_75 = 0.75
        case x1 = 1.0
        case x1_25 = 1.25
        case x1_5 = 1.5
        case x1_75 = 1.75
        case x2 = 2.0
    }
}
```

### 7.3 ClipPlayerViewModel

> 파일: `Sources/CViewApp/ViewModels/ClipPlayerViewModel.swift` (~280 lines)

VLCPlayerEngine 기반 클립 재생 ViewModel. Embed WebView → VLC 전환 전략.

```swift
@Observable @MainActor
class ClipPlayerViewModel {
    var embedFallbackURL: URL?     // ABR_HLS 클립 embed URL
    
    func startClip(config: ClipPlaybackConfig)           // VLC 직접 재생
    func startClip(from clipInfo: ClipInfo)               // embed 먼저 → 배경 VLC 탐색
    func switchToVLCPlayer(streamURL: URL, clipUID: String)  // embed → VLC 전환
    func syncWebKitCookies()                              // WKWebView 쿠키 동기화
}
```

**클립 재생 전략:**
```
1. clipInfo 수신
2. embed URL로 WebView 즉시 표시 (사용자 대기 시간 제거)
3. 백그라운드에서 inkey API → 직접 스트림 URL 탐색
4. 성공 시: VLC로 전환 (고품질, 더 많은 컨트롤)
5. 실패 시: embed WebView 유지 (graceful fallback)
```

---

## 8. UI View 계층

### 8.1 LiveStreamView

> 파일: `Sources/CViewApp/Views/LiveStreamView.swift` (647 lines)

라이브 스트림 메인 뷰. HSplitView로 플레이어 + 채팅 구성.

**기능:**
- 스트림 + 채팅 동시 시작 (`startStreamAndChat()`)
- HLS 프리페치 캐시 우선 활용
- 키보드 단축키 (ShortcutAction × KeyBinding 매칭)
- PiP 토글
- 성능 오버레이 (`PerformanceOverlayView`)
- 실시간 상태 폴링 (30초 주기) — 시청자 수, 방송 종료 감지
- 시청 기록 (`DataStore.startWatchRecord/endWatchRecord`)
- 메트릭 피드 (1초 주기) — latency/bufferHealth → PerformanceMonitor

**키보드 단축키 (ShortcutAction):**
| 액션 | 설명 |
|------|------|
| `togglePlay` | 재생/일시정지 |
| `toggleMute` | 음소거 토글 |
| `toggleFullscreen` | 전체화면 토글 |
| `toggleChat` | 채팅 패널 토글 |
| `togglePiP` | PiP 토글 |
| `screenshot` | 스크린샷 |
| `volumeUp` | 볼륨 증가 |
| `volumeDown` | 볼륨 감소 |

### 8.2 PlayerControlsView

> 파일: `Sources/CViewApp/Views/PlayerControlsView.swift` (659 lines)

플레이어 오버레이 컨트롤 모음.

**구성:**
```
PlayerOverlayView
    ├ Top: StreamInfoBar (채널명, 방송제목, 시청자수, 업타임)
    ├ Middle: (투명, 클릭 영역)
    └ Bottom:
        ├ PlayerProgressSection
        │   ├ 라이브: LIVE 뱃지
        │   └ VOD: 시크 프로그래스 바 (드래그 + 호버 타임 툴팁)
        └ PlayerControlsBar
            ├ 재생/일시정지 버튼
            ├ 볼륨 (호버 슬라이더)
            ├ 품질 선택 (QualitySelector 팝업)
            ├ 고급 설정
            ├ 오디오 전용
            ├ 재생 속도
            ├ 새 창
            ├ PiP
            ├ 스크린샷
            ├ 녹화 (RecordButton — 펄싱 빨간 점)
            └ 전체화면
```

**커스텀 컴포넌트:**
- `PlayerButton` — 호버 효과 원형 버튼
- `RecordButton` — 녹화 중 펄싱 빨간 점 + 경과시간
- `LiveBadge` — 펄싱 빨간 원 + "LIVE"
- `InfoBadge` — 글래스모피즘 뱃지 (품질, 레이턴시, 재생 속도)

### 8.3 MultiLivePlayerPane

> 파일: `Sources/CViewApp/Views/MultiLivePlayerPane.swift` (1,923 lines)

멀티라이브 세션별 플레이어 렌더링. 탭 모드 + 그리드 모드 지원.

**주요 구조체:**
| 구조체 | 역할 |
|--------|------|
| `MLPlayerPane` | 탭 모드 메인 뷰 (세션 + 채팅) |
| `MLGridLayout` | 그리드 레이아웃 |
| `MLGridCell` | 그리드 셀 (exclusively 제스처) |
| `MLGridControlOverlay` | 그리드 오버레이 (재생/정지, 고급설정, PiP) |
| `MLVideoArea` | 탭 모드 비디오 영역 |
| `MLControlOverlay` | 탭 모드 오버레이 (전체 컨트롤) |
| `MLStatsOverlay` | 통계 오버레이 |
| `MLQualityPopover` | 품질 선택 팝오버 |

---

## 9. 멀티라이브 시스템

### 9.1 VLCInstancePool

> 파일: `Sources/CViewPlayer/VLCInstancePool.swift` (~160 lines)

멀티라이브용 VLCPlayerEngine 인스턴스 풀링.

```swift
actor VLCInstancePool {
    let maxPoolSize: Int = 4
    
    func acquire() -> VLCPlayerEngine?     // 유휴 재사용 or 신규 생성
    func release(_ engine: VLCPlayerEngine) // resetForReuse() + 유휴 전환
    func warmup(count: Int)                // 미리 인스턴스 생성
    func drain()                           // 전부 해제
    func reducePool(keepCount: Int)        // 메모리 압박 시 유휴 축소
}
```

### 9.2 멀티라이브 배경 탭 최적화

배경 탭에서 리소스 절약을 위해 적용하는 조치:
```
setBackgroundMode(true):
    ├ 비디오 트랙 비활성화 (GPU 디코딩 중단)
    ├ 음소거
    ├ 메트릭 수집 주기 증가 (2s → 10s)
    ├ 시간 업데이트 주기 감소
    └ VLC 프로파일 → .multiLiveBackground
```

---

## 10. 전체 재생 파이프라인

```
┌─ 사용자 채널 선택 ─────────────────────────────────────────────┐
│                                                                │
│  LiveStreamView.startStreamAndChat()                           │
│      │                                                         │
│      ├─ HLSPrefetchService 캐시 확인                            │
│      │   └─ 미스 시: ChzzkAPIClient.liveDetail() API 호출       │
│      │                                                         │
│      ├─ livePlaybackJSON 파싱 → HLS master playlist URL 추출    │
│      │                                                         │
│      └─ PlayerViewModel.startStream()                          │
│          │                                                     │
│          ├─ [엔진 생성]                                         │
│          │   ├─ VLCPlayerEngine (기본, 저지연)                   │
│          │   └─ AVPlayerEngine (대안, 안정성)                    │
│          │                                                     │
│          ├─ [StreamCoordinator 생성]                             │
│          │   ├─ ABRController                                  │
│          │   ├─ LowLatencyController + PDTLatencyProvider       │
│          │   ├─ PlaybackReconnectionHandler                    │
│          │   └─ HLSManifestParser                              │
│          │                                                     │
│          ├─ coordinator.startStream(url:)                       │
│          │   │                                                 │
│          │   ├─ HLS Master Playlist fetch & parse              │
│          │   │   └─ Variant 목록 추출 (bandwidth, resolution)   │
│          │   │                                                 │
│          │   ├─ ABR 초기 품질 선택                               │
│          │   │   └─ Dual EWMA × 안전계수(0.7)                   │
│          │   │                                                 │
│          │   ├─ LocalStreamProxy.proxyURL(for:)                │
│          │   │   └─ User-Agent/Referer 헤더 주입                │
│          │   │                                                 │
│          │   ├─ playerEngine.play(variantURL)                   │
│          │   │   ├─ VLC: Media생성 → 옵션설정 → drawable → play │
│          │   │   └─ AVP: Item생성 → 저지연HLS → play            │
│          │   │                                                 │
│          │   └─ startLowLatencySync()                          │
│          │       ├─ PDT Provider: 10초 주기 playlist 재파싱     │
│          │       └─ PID Controller: 3초 주기 속도 조절          │
│          │                                                     │
│          └─ [지속 모니터링]                                      │
│              ├─ VLC 메트릭 타이머 (2~10초)                      │
│              │   └─ healthScore → 프로파일 자동 전환             │
│              ├─ 스톨 워치독 (VLC:20초, AVP:3초)                  │
│              │   └─ attemptRecovery()                          │
│              ├─ 라이브 drift 모니터 (60초)                      │
│              │   └─ seek 보정                                  │
│              ├─ ABR 대역폭 샘플 피드                             │
│              │   └─ 품질 적응 결정                               │
│              └─ 재연결 핸들러                                    │
│                  └─ 지수 백오프 (최대 5회, 2~30초)               │
│                                                                │
├─ [렌더링]                                                       │
│   VLC: VLCLayerHostView → PlayerContainerView                  │
│   AVP: AVPlayerLayerView → PlayerContainerView                 │
│   → PlayerVideoView (SwiftUI NSViewRepresentable)              │
│                                                                │
└─ [UI 오버레이]                                                   │
    PlayerOverlayView / MLControlOverlay                         │
    ├─ 재생/일시정지, 볼륨, 품질 선택                               │
    ├─ 고급 설정 (EQ, 비디오필터, 자막, 오디오)                     │
    ├─ PiP, 전체화면, 스크린샷, 녹화                               │
    └─ 키보드 단축키 (ShortcutAction)                              │
```

---

## 11. 설계 결정 요약

| 영역 | 결정 | 이유 |
|------|------|------|
| **엔진 추상화** | `PlayerEngineProtocol` 통합 인터페이스 | VLC/AVPlayer 런타임 교체 가능 |
| **기본 엔진** | VLC (저지연 우선) | 치지직 라이브의 낮은 레이턴시 요구 |
| **PiP** | NSPanel 커스텀 구현 | AVKit PiP는 VLCKit과 호환 불가 |
| **녹화** | HLS 세그먼트 다운로드 → MPEG-TS | 엔진 독립적, 재인코딩 불필요 |
| **렌더링 최적화** | CA 애니메이션 전면 비활성화 | 비디오 렌더링 성능 극대화 |
| **크래시 방지** | 세대 카운터 + isLayingOut 플래그 | stop/play 레이스, layout 재진입 방지 |
| **멀티라이브** | VLCInstancePool (max 4) | 엔진 생성 비용 절약, 메모리 관리 |
| **저지연** | PDT 실측 + PID 속도 조절 이중 전략 | 정확한 레이턴시 보정 |
| **대역폭 추정** | Dual EWMA | 빠른 반응 + 안정성 균형 |
| **복구** | 통합 attemptRecovery() | ERROR/STOPPED/스톨 단일 경로 |
| **스레드 안전** | VLC: NSLock, Controller: actor | VLCKit delegate 특성 반영 |
| **CDN 인증** | LocalStreamProxy 헤더 주입 | VLC/AVPlayer가 직접 헤더 설정 불가 |
| **클립 재생** | embed WebView → VLC 전환 전략 | 즉시 표시 + 고품질 전환 |

---

## 12. 상수 및 기본값

> 파일: `Sources/CViewPlayer/PlayerConstants.swift` (~100 lines)

### ABR 기본값
| 상수 | 값 |
|------|-----|
| minBandwidthBps | 500,000 (500Kbps) |
| maxBandwidthBps | 50,000,000 (50Mbps) |
| initialEstimate | 5,000,000 (5Mbps) |
| safetyFactor | 0.7 |
| switchUpFactor | 1.2 |
| switchDownFactor | 0.8 |
| minSwitchInterval | 5초 |

### VLC 기본값
| 상수 | 값 |
|------|-----|
| normalNetworkCaching | 1,500ms |
| lowLatencyNetworkCaching | 400ms |
| stallThreshold | 45초 |
| watchdogInterval | 20초 |

### AVPlayer 기본값
| 상수 | 값 |
|------|-----|
| stallTimeout | 12초 |
| stallCheckInterval | 3초 |
| preferredTimescale | 600 |

### 레이턴시 기본값
| 상수 | 값 |
|------|-----|
| historyMaxCount | 100 |
| mildAdjustmentFactor | 0.05 |
| maxRealisticLatency | 60초 |

### 프록시 기본값
| 상수 | 값 |
|------|-----|
| keepAliveTimeout | 30초 |
| maxConnectionsPerHost | 12 |
| maxReceiveLength | 65,536 bytes |

### 멀티라이브 기본값
| 상수 | 값 |
|------|-----|
| minHeight | 360px |
| maxBitrate | 8Mbps |

---

## 파일 인덱스

| 파일 | 위치 | 라인수 | 역할 |
|------|------|--------|------|
| PlayerEngineProtocol.swift | CViewCore/Protocols/ | ~110 | 엔진 통합 인터페이스 |
| PlayerModels.swift | CViewCore/Models/ | ~130 | 상태/에러/옵션 모델 |
| VLCPlayerMetrics.swift | CViewCore/Models/ | ~125 | VLC 메트릭 스냅샷 |
| VLCPlayerEngine.swift | CViewPlayer/ | 2,024 | VLC 엔진 (메인) |
| AVPlayerEngine.swift | CViewPlayer/ | 915 | AVPlayer 엔진 (대안) |
| ABRController.swift | CViewPlayer/ | 229 | 적응형 비트레이트 |
| HLSManifestParser.swift | CViewPlayer/ | ~360 | HLS 매니페스트 파싱 |
| HLSPrefetchService.swift | CViewPlayer/ | ~195 | HLS 프리페치 |
| LocalStreamProxy.swift | CViewPlayer/ | 422 | 로컬 HTTP 프록시 |
| LowLatencyController.swift | CViewPlayer/ | ~250 | PID 저지연 제어 |
| PDTLatencyProvider.swift | CViewPlayer/ | ~140 | PDT 레이턴시 측정 |
| PlaybackReconnectionHandler.swift | CViewPlayer/ | ~170 | 지수 백오프 재연결 |
| StreamCoordinator.swift | CViewPlayer/ | 901 | 스트림 오케스트레이터 |
| StreamRecordingService.swift | CViewPlayer/ | ~200 | HLS 녹화 |
| VLCInstancePool.swift | CViewPlayer/ | ~160 | VLC 인스턴스 풀링 |
| VODStreamResolver.swift | CViewPlayer/ | ~150 | VOD/Clip URL 해석 |
| PiPController.swift | CViewPlayer/ | ~400 | PiP (NSPanel) |
| PlayerVideoView.swift | CViewPlayer/ | ~200 | 통합 비디오 뷰 |
| VLCVideoView.swift | CViewPlayer/ | ~130 | VLC 전용 뷰 |
| AVVideoView.swift | CViewPlayer/ | ~95 | AVPlayer 전용 뷰 |
| PlayerConstants.swift | CViewPlayer/ | ~100 | 상수 정의 |
| PlayerViewModel.swift | CViewApp/ViewModels/ | 995 | 라이브 VM |
| VODPlayerViewModel.swift | CViewApp/ViewModels/ | ~220 | VOD VM |
| ClipPlayerViewModel.swift | CViewApp/ViewModels/ | ~280 | 클립 VM |
| LiveStreamView.swift | CViewApp/Views/ | 647 | 라이브 메인 뷰 |
| PlayerControlsView.swift | CViewApp/Views/ | 659 | 플레이어 컨트롤 |
| MultiLivePlayerPane.swift | CViewApp/Views/ | 1,923 | 멀티라이브 뷰 |

---

> **총 코드량**: 약 10,500+ lines (재생 시스템 관련 코드만)
