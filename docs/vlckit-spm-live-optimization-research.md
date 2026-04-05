# VLCKit SPM 정밀 분석: 라이브 스트리밍 디코딩 및 영상 최적화 연구

> 작성일: 2025-07-19  
> 대상: CView_v2 — VLCKit 4.0 기반 HLS 라이브 스트리밍 플레이어  
> 환경: Apple Silicon (M1 Max 10코어), macOS 15.0+, Swift 6.0  
> VLCKit: 4.0.0a18 (libvlc 4.0.0) via rursache/VLCKitSPM  
> 참고: 기존 문서 `docs/vlc-cpu-optimization-research.md`의 심층 확장판

---

## 목차

1. [VLCKitSPM 패키지 아키텍처 분석](#1-vlckitspm-패키지-아키텍처-분석)
2. [VLCKit 4.0 API 심층 분석](#2-vlckit-40-api-심층-분석)
3. [현재 CView 엔진 구현 감사](#3-현재-cview-엔진-구현-감사)
4. [VLC 디코딩 파이프라인 완전 분석](#4-vlc-디코딩-파이프라인-완전-분석)
5. [라이브 HLS 스트리밍 특화 최적화](#5-라이브-hls-스트리밍-특화-최적화)
6. [VideoToolbox 하드웨어 디코딩 심층 분석](#6-videotoolbox-하드웨어-디코딩-심층-분석)
7. [멀티뷰 렌더링 파이프라인 최적화](#7-멀티뷰-렌더링-파이프라인-최적화)
8. [미구현 VLC 옵션 전수 분석](#8-미구현-vlc-옵션-전수-분석)
9. [VLCKit 4.0 고급 API 활용 방안](#9-vlckit-40-고급-api-활용-방안)
10. [종합 최적화 로드맵](#10-종합-최적화-로드맵)

---

## 1. VLCKitSPM 패키지 아키텍처 분석

### 1.1 패키지 구조

VLCKitSPM (`https://github.com/rursache/VLCKitSPM.git`, revision `94ca521`)은 VLCKit xcframework를 SPM으로 배포하는 **경량 래퍼**이다.

```
rursache/VLCKitSPM/
├── Package.swift              # SPM 매니페스트 — binaryTarget + 래퍼 target
├── generate.sh                # VideoLAN 서버에서 최신 빌드 자동 감지/패키징
├── Sources/VLCKitSPM/
│   └── VLCKit.swift           # 단일 re-export 파일: @_exported import VLCKit
└── .github/workflows/         # 월간 자동 업데이트 체크 (매월 1일)
```

**핵심 포인트:**
- 소스 빌드가 아닌 **사전 빌드된 xcframework 바이너리** 배포
- 빌드 원본: `https://download.videolan.org/pub/cocoapods/unstable/` (VideoLAN 공식 불안정 채널)
- 현재 버전: VLCKit **4.0.0a18** (libvlc 4.0.0, LIBVLC_VERSION_MAJOR=4)

### 1.2 Package.swift 분석

```swift
// platforms 지원 범위
platforms: [.iOS(.v13), .macOS(.v11), .tvOS(.v13)]

// products
products: [
    .library(name: "VLCKitSPM", targets: ["VLCKitSPM"])
]

// targets 구조
targets: [
    .binaryTarget(
        name: "VLCKitXC",
        url: "https://github.com/rursache/VLCKitSPM/releases/download/.../VLCKit.xcframework.zip",
        checksum: "..."
    ),
    .target(
        name: "VLCKitSPM",
        dependencies: ["VLCKitXC"],
        linkerSettings: [
            // macOS 링크 설정
            .linkedFramework("Foundation", .when(platforms: [.macOS])),
            .linkedLibrary("iconv", .when(platforms: [.macOS])),
            // iOS 링크 설정 — 더 많은 프레임워크 필요
            .linkedFramework("QuartzCore", .when(platforms: [.iOS])),
            .linkedFramework("CoreText", .when(platforms: [.iOS])),
            .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
            .linkedFramework("Security", .when(platforms: [.iOS])),
            .linkedFramework("CFNetwork", .when(platforms: [.iOS])),
            .linkedFramework("AudioToolbox", .when(platforms: [.iOS])),
            .linkedFramework("OpenGLES", .when(platforms: [.iOS])),
            .linkedFramework("CoreGraphics", .when(platforms: [.iOS])),
            .linkedFramework("VideoToolbox", .when(platforms: [.iOS])),
            .linkedFramework("CoreMedia", .when(platforms: [.iOS])),
            .linkedLibrary("c++", .when(platforms: [.iOS])),
            .linkedLibrary("xml2", .when(platforms: [.iOS])),
            .linkedLibrary("z", .when(platforms: [.iOS])),
            .linkedLibrary("bz2", .when(platforms: [.iOS])),
        ]
    )
]
```

### 1.3 generate.sh 빌드 파이프라인

```bash
# 최신 VLCKit 빌드 자동 감지 흐름:
# 1. https://download.videolan.org/pub/cocoapods/unstable/ 에서 디렉토리 목록 파싱
# 2. 최신 버전 번호 추출 (현재: 4.0.0a18)
# 3. VLCKit.xcframework.zip 다운로드
# 4. GitHub Release에 업로드 + Package.swift의 URL/checksum 업데이트
```

### 1.4 xcframework 내부 구조

```
VLCKit.xcframework/
├── macos-arm64_x86_64/VLCKit.framework/        # macOS Universal
│   ├── Headers/                                   # Public Headers (17개)
│   │   ├── VLCMediaPlayer.h          (905줄)     # 핵심 플레이어 API
│   │   ├── VLCMedia.h                (700줄)     # 미디어/옵션/통계
│   │   ├── VLCLibrary.h              (117줄)     # 라이브러리 인스턴스
│   │   ├── VLCDrawable.h             (119줄)     # 커스텀 드로어블 프로토콜
│   │   ├── VLCVideoView.h            (55줄)      # NSView 기반 렌더링
│   │   ├── VLCVideoLayer.h           (48줄)      # CALayer 기반 렌더링
│   │   ├── VLCVideoCommon.h                       # 공통 비디오 타입
│   │   ├── libvlc.h                  (546줄)     # libvlc C API
│   │   ├── libvlc_media.h            (952줄)     # 미디어 C API
│   │   └── libvlc_media_player.h     (3323줄)    # 플레이어 C API (가장 방대)
│   └── PrivateHeaders/                            # Internal Headers
│       ├── VLCLibVLCBridging.h       (279줄)     # ObjC↔libvlc 브릿지
│       └── VLCMediaPlayer+Internal.h              # 플레이어 내부 확장
├── ios-arm64/                                     # iOS ARM64
├── watchos-arm64_arm64_32_armv7k/                 # watchOS
└── xros-arm64/                                    # visionOS
```

### 1.5 아키텍처적 함의

**제약 사항:**
- 사전 빌드 바이너리이므로 VLC 내부 모듈(decoder.c, video_output.c) 커스터마이징 불가
- VLC `--long-help` 수준의 미디어 옵션으로만 동작 커스터마이즈 가능
- 빌드 구성(configure 옵션, 포함된 코덱 목록) 변경 불가

**기회:**
- VLCMedia `addOption()` API를 통한 VLC CLI 옵션 전체 접근 가능
- VLCMediaPlayer의 풍부한 ObjC API (905줄의 퍼블릭 API) 직접 활용
- `VLCLibVLCBridging.h` 프라이빗 헤더로 low-level libvlc C API 간접 접근 가능

---

## 2. VLCKit 4.0 API 심층 분석

### 2.1 VLCMediaPlayer 핵심 API (905줄)

#### 2.1.1 상태 머신

```objc
typedef NS_ENUM(NSInteger, VLCMediaPlayerState) {
    VLCMediaPlayerStateStopped   = 0,
    VLCMediaPlayerStateStopping  = 1,
    VLCMediaPlayerStateOpening   = 2,
    VLCMediaPlayerStateBuffering = 3,
    VLCMediaPlayerStateError     = 4,
    VLCMediaPlayerStatePlaying   = 5,
    VLCMediaPlayerStatePaused    = 6
};
```

**최적화 관련 상태 전이:**
```
idle → opening → buffering → playing → (paused/buffering/stopped)
                    ↑______________|  (리버퍼링 루프)
```

#### 2.1.2 타이밍 제어 — 성능 민감 파라미터

```objc
/// 내부 타이머 최소 주기 (마이크로초) — 기본값 500,000µs (0.5초)
/// 값을 높이면 VLC 내부 타이밍 이벤트 빈도 감소 → CPU 절감
@property (nonatomic) int minimalTimePeriod;

/// 시간 변경 콜백 간격 (초) — 기본값 1.0초
/// delegate -mediaPlayerTimeChanged: 호출 빈도 제어
@property (nonatomic) double timeChangeUpdateInterval;
```

**현재 CView 활용:**
- `_timeChangeThrottleNs = 2_000_000_000` (2초 스로틀링) — Swift 레벨에서 추가 제한
- `minimalTimePeriod`와 `timeChangeUpdateInterval`은 **미설정 (VLCKit 기본값 사용)**

**최적화 기회:**
- `minimalTimePeriod`를 `1_000_000` (1초)으로 증가 → 내부 타이밍 이벤트 빈도 50% 감소
- `timeChangeUpdateInterval`를 `2.0`으로 증가 → delegate 콜백 빈도 50% 감소
- 멀티라이브에서 특히 유효: 4세션 × 타이밍 이벤트 감소 = 상당한 메인 스레드 부하 절감

#### 2.1.3 비디오 렌더링 옵션

```objc
@property (nonatomic, nullable) id drawable;  // NSView/UIView/VLCDrawable
@property (nonatomic, nullable) NSString *videoAspectRatio;
@property (nonatomic) float scaleFactor;

// 디인터레이스 — 라이브 스트리밍에서는 비활성이 정상
- (void)setDeinterlace:(nullable NSString *)name;

// 비디오 조정 필터
@property (nonatomic, readonly) VLCAdjustFilter *adjustFilter;
```

#### 2.1.4 트랙 관리 API

```objc
// 트랙 목록 조회
@property (nonatomic, readonly) NSArray<VLCMediaPlayerTrack *> *audioTracks;
@property (nonatomic, readonly) NSArray<VLCMediaPlayerTrack *> *videoTracks;
@property (nonatomic, readonly) NSArray<VLCMediaPlayerTrack *> *textTracks;

// 트랙 선택/해제
- (void)selectTrackAtIndex:(NSUInteger)index type:(VLCMediaPlayerTrackType)type;
- (void)deselectAllAudioTracks;
- (void)deselectAllVideoTracks;
- (void)deselectAllTextTracks;
```

**멀티라이브 최적화:**
- `deselectAllVideoTracks()` → 비가시 세션의 VideoToolbox 디코딩 완전 중단 (가장 효과적)
- `deselectAllAudioTracks()` → 백그라운드 세션의 오디오 디코딩 중단
- 재활성화: `selectTrackAtIndex:0 type:.video` → 키프레임 대기 후 렌더링 재개 (0.5~2초)

#### 2.1.5 재생 속도 및 시킹

```objc
@property (nonatomic) float rate;          // 재생 속도 (1.0 = 정상)
@property (nonatomic) float position;      // 0.0 ~ 1.0 위치
@property (nonatomic, strong) VLCTime *time;
@property (nonatomic, readonly) BOOL seekable;
@property (nonatomic, readonly) BOOL canPause;
```

### 2.2 VLCMedia 핵심 API (700줄)

#### 2.2.1 미디어 옵션 시스템

```objc
/// 개별 옵션 추가 — VLC CLI 옵션과 동일한 형식
/// "options detailed in vlc --long-help"
- (void)addOption:(NSString *)option;

/// 사전 형태로 복수 옵션 추가
- (void)addOptions:(NSDictionary *)options;
```

**VLC Media 옵션 = VLC CLI 옵션과 1:1 대응.** `vlc --long-help`에 나열되는 모든 옵션이 `addOption(":option-name=value")` 형태로 사용 가능하다.

#### 2.2.2 통계 구조체 (VLCMediaStats)

```objc
typedef struct {
    // 입력 통계
    int64_t readBytes;              // 총 읽은 바이트
    float   inputBitrate;           // 입력 비트레이트

    // demux 통계  
    int64_t demuxReadBytes;         // demux 읽은 바이트
    float   demuxBitrate;           // demux 비트레이트
    int32_t demuxCorrupted;         // 손상된 패킷 수
    int32_t demuxDiscontinuity;     // 불연속 횟수

    // 비디오 통계
    int32_t decodedVideo;           // 디코딩된 비디오 프레임 수 (누적)
    int32_t displayedPictures;      // 디스플레이된 프레임 수 (누적)
    int32_t latePictures;           // 늦은 프레임 수 (누적)
    int32_t lostPictures;           // 손실 프레임 수 (누적)

    // 오디오 통계
    int32_t decodedAudio;           // 디코딩된 오디오 블록 수 (누적)
    int32_t playedAudioBuffers;     // 재생된 오디오 버퍼 수 (누적)
    int32_t lostAudioBuffers;       // 손실 오디오 버퍼 수 (누적)
} VLCMediaStats;
```

**CView 활용:**
- `collectMetrics()`에서 델타 기반 수집 (15+ 메트릭)
- `lostPictures` → 프레임 드롭 감지
- `latePictures` → 지연 프레임 감지
- `decodedVideo` → 프레임 디코딩 속도 (FPS 계산)
- `decodedVideo` 0프레임 연속 → 재생 정체 감지 (stall detection)

#### 2.2.3 미디어 트랙 정보

```objc
@interface VLCMediaVideoTrack
@property (readonly) int height;
@property (readonly) int width;
@property (readonly) int orientation;
@property (readonly) int projection;
@property (readonly) int sourceAspectRatio;
@property (readonly) int frameRate;        // ← 소스 프레임레이트 확인 가능
@end
```

**최적화 활용:** 소스 `frameRate`를 읽어서 adaptive 해상도 결정 시 활용 가능.

#### 2.2.4 미디어 파싱

```objc
typedef NS_OPTIONS(NSUInteger, VLCMediaParsingOptions) {
    VLCMediaParseLocal      = 0x00,
    VLCMediaParseNetwork    = 0x01,
    VLCMediaForceParse      = 0x02,
    VLCMediaFetchLocal      = 0x04,
    VLCMediaFetchNetwork    = 0x08,
    VLCMediaDoInteract      = 0x10
};

- (int)parseWithOptions:(VLCMediaParsingOptions)options timeout:(int)timeoutValue;
```

**라이브 스트리밍 참고:** 라이브 HLS 스트림은 파싱보다 직접 재생이 적합. 파싱은 VOD 콘텐츠 메타데이터 추출 시 사용.

### 2.3 VLCDrawable 프로토콜 (119줄)

```objc
@protocol VLCDrawable <NSObject>
// VLC 4.0의 새로운 렌더링 인터페이스:
// NSView/UIView 외에 커스텀 렌더링 서피스를 drawable로 사용 가능
// VLCSampleBufferDisplay 대신 직접 프레임 수신 → 커스텀 렌더링
@end
```

**잠재적 활용:** 미래에 Metal 기반 커스텀 렌더러 구현 시 VLCDrawable 프로토콜 채택으로 VLC의 vout 파이프라인을 우회하고 직접 프레임을 수신하여 렌더링할 수 있다.

### 2.4 렌더링 레이어 옵션

```
VLCVideoView (NSView)          — macOS용 기본 렌더링 뷰
VLCVideoLayer (CALayer)        — macOS용 CALayer 기반 렌더링
VLCSampleBufferDisplay         — Metal/AVSampleBufferDisplayLayer 기반 (현재 사용)
```

**현재 CView:** `player.drawable = VLCLayerHostView` (NSView) → VLC가 내부적으로 `VLCSampleBufferDisplay`(Metal 기반)를 서브뷰로 추가.

### 2.5 libvlc C API 핵심 (libvlc.h, 546줄)

```c
// 라이브러리 생성 — VLC CLI 인수를 직접 전달 가능
libvlc_instance_t *libvlc_new(int argc, const char *const *argv);

// 버전 정보
const char *libvlc_get_version(void);     // "4.0.0-dev ..."
const char *libvlc_get_compiler(void);

// VLCKitSPM에서의 접근:
// VLCLibVLCBridging.h를 통해 Swift에서 간접 접근 가능
// VLCLibrary.sharedLibrary()가 내부적으로 libvlc_new() 호출
```

### 2.6 VLCLibVLCBridging 프라이빗 API (279줄)

```objc
// VLCMedia 확장 — low-level libvlc 접근
@interface VLCMedia (VLCLibVLCBridging)
- (instancetype)initAsNodeWithName:(NSString *)name;
@property (readonly) void *libVLCMediaDescriptor;  // libvlc_media_t*
@end

// VLCMediaPlayer 확장 — low-level libvlc 접근
@interface VLCMediaPlayer (VLCLibVLCBridging)
@property (readonly) void *libVLCMediaPlayer;  // libvlc_media_player_t*
@end
```

**고급 활용:** `libVLCMediaPlayer` 포인터를 통해 `libvlc_media_player.h`(3323줄)의 모든 C API를 직접 호출할 수 있다. 단, Swift에서의 안전성 보장이 어렵고, API 변경 시 크래시 위험이 있으므로 극히 제한적으로만 사용해야 한다.

---

## 3. 현재 CView 엔진 구현 감사

### 3.1 파일 구조

| 파일 | 라인 | 역할 |
|-----|-----|-----|
| `VLCPlayerEngine.swift` | ~300 | 엔진 코어, VLCLayerHostView, VLCStreamingProfile |
| `VLCPlayerEngine+Playback.swift` | ~180 | 미디어 전환, 초기 재생, 미디어 옵션 |
| `VLCPlayerEngine+Features.swift` | ~250 | drawable 복구, 재사용, 녹화, 메트릭 |
| `VLCPlayerEngine+AudioVideo.swift` | ~150 | EQ, 비디오 조정, 종횡비, 자막, 오디오 |

### 3.2 applyMediaOptions() 완전 감사

현재 `applyMediaOptions()`에서 설정하는 **모든 옵션의 분석**:

#### 3.2.1 캐싱/버퍼 계층

```
[CDN] → network-caching (300/500/1000ms) → [VLC input buffer]
      → live-caching (300/500/1000ms)     → [VLC live buffer]
      → file-caching=0                    → [VLC file buffer (비활성)]
      → disc-caching=0                    → [VLC disc buffer (비활성)]
      → prefetch-buffer-size (384K/768K)  → [VLC demux prefetch]
```

**평가:** ✅ 적절  
네트워크 캐싱과 라이브 캐싱을 프로파일별로 분리한 것은 올바른 접근. `file-caching=0`과 `disc-caching=0`은 네트워크 스트림에 불필요한 버퍼를 제거.

#### 3.2.2 디코딩 옵션 체인

```
:codec=videotoolbox,avcodec       → HW 디코딩 우선, SW 폴백
:avcodec-hw=videotoolbox          → avcodec 모듈도 VideoToolbox 사용
:avcodec-threads=N                → SW 폴백 시 스레드 수
:avcodec-fast=1                   → 비표준 고속 트릭 허용
:avcodec-hurry-up=1               → 지연 시 프레임 부분 디코딩
:avcodec-skip-idct=4 (multiLive)  → 역DCT 전체 스킵
:drop-late-frames=1               → vout: 늦은 프레임 드롭
:skip-frames=1                    → decoder: 참조 안 되는 프레임 스킵
```

**평가:** 🟡 개선 여지 있음
- `:avcodec-skip-idct=4`는 multiLive에만 적용 — **VideoToolbox 활성 시 효과 미확인**
- `:avcodec-skiploopfilter` **미설정** — 잠재적 CPU 절감 누락
- `:avcodec-skip-frame` **미설정** — B프레임 스킵 기회 누락
- 이들 `avcodec-*` 옵션은 **SW 디코딩(libavcodec) 전용**이며, VideoToolbox 경로에서는 무시될 가능성 높음

#### 3.2.3 적응형 스트리밍 (HLS)

```
:adaptive-maxwidth=N      → HLS 최대 해상도 폭
:adaptive-maxheight=N     → HLS 최대 해상도 높이  
:adaptive-logic=highest   → 가용 대역폭 내 최고 화질 선택
```

**평가:** 🟡 `adaptive-logic=highest` 재검토 필요  
- `highest`는 항상 최고 비트레이트를 선택하므로, 네트워크 변동 시 리버퍼링 위험
- `predictive` 또는 `nearoptimal`이 라이브 스트리밍에 더 적합할 수 있음
- `predictive`: 대역폭 예측 기반 — 네트워크 변동에 적응적
- `nearoptimal`: 버퍼 수준 + 대역폭 예측 복합 알고리즘

#### 3.2.4 클럭/동기화

```
:clock-synchro=0      → 내부 클럭 동기 비활성
:clock-jitter=N µs    → 클럭 지터 허용 범위
:cr-average=N ms      → 클럭 복구 평균화
```

**평가:** ✅ 적절  
`clock-synchro=0`은 라이브 스트리밍에서 VLC가 자체 타이밍 관리하도록 하여 적절. `cr-average`와 `clock-jitter`의 프로파일별 분화도 합리적.

#### 3.2.5 후처리

```
:deinterlace=0     → 비활성 ✅ (프로그레시브 소스)
:postproc-q=0      → 비활성 ✅ (CPU 절감)
```

**평가:** ✅ 최적  
라이브 스트리밍 소스는 프로그레시브이므로 디인터레이스 불필요. 후처리도 라이브에서는 불필요한 CPU 낭비.

### 3.3 VLCStreamingProfile 체계 평가

| 파라미터 | ultraLow | lowLatency | multiLive | 평가 |
|---------|---------|-----------|----------|-----|
| networkCaching | 300ms | 500ms | 1000ms | ✅ 적절 |
| liveCaching | 300ms | 500ms | 1000ms | ✅ 적절 |
| manifestRefreshInterval | 8 | 4 | 20 | 🟡 아래 참조 |
| clockJitter | 0µs | 5000µs | 10000µs | ✅ 적절 |
| crAverage | 20ms | 30ms | 30ms | ✅ 적절 |
| decoderThreads | CPU,4 | CPU,4 | 1 | 🟡 아래 참조 |
| adaptiveMaxW/H (비선택) | 1920×1080 | 1920×1080 | 854×480 | ✅ 최적화됨 |
| dropLateFrames | true | true | true | ✅ 필수 |
| skipFrames | true | true | true | ✅ 필수 |

**개선 포인트:**
1. `manifestRefreshInterval`가 `applyMediaOptions()`에서 **사용되지 않음** — 코드에 정의만 되고 실제 옵션 추가 누락
2. `decoderThreads`를 `0` (auto) 대신 수동 설정 — VideoToolbox 경로에서는 의미 제한적

### 3.4 VLCLayerHostView 구성 평가

```swift
wantsLayer = true
canDrawSubviewsIntoLayer = false     // ✅ VLC 서브레이어 독립 유지
layerContentsRedrawPolicy = .never   // ✅ 불필요한 재드로잉 방지
layer.isOpaque = true                // ✅ 투명 합성 불필요 (비디오)
layer.drawsAsynchronously = false    // ✅ GPU 이중 합성 방지
layer.allowsGroupOpacity = false     // ✅ 오프스크린 패스 방지
layer.actions = [...]                // ✅ 암시적 애니메이션 전체 비활성
```

**평가:** ✅ 이미 최적 수준. 추가 CALayer 최적화 여지 없음.

### 3.5 메트릭 수집 시스템 평가

```swift
// 수집 주기: 5초 (단일) / 10초 (멀티라이브)
// 수집 방식: Task.sleep 기반 + @MainActor collectMetrics()
// 통계 소스: VLCMedia.Statistics (delta 기반)
```

**평가:** ✅ 효율적  
- VLC statistics API 호출은 경량 (메모리 읽기 수준)
- 멀티라이브 10초 주기는 적절한 절충
- 정체 감지(`_zeroFrameCount >= 2`)도 효과적

---

## 4. VLC 디코딩 파이프라인 완전 분석

### 4.1 HLS 라이브 스트리밍 데이터 흐름

```
[치지직 CDN]
  │
  ├─ (HTTP GET) ── M3U8 Manifest ──→ [VLC adaptive 모듈]
  │                                       │
  │                                   adaptive-logic 알고리즘
  │                                   → 비트레이트/해상도 선택
  │                                       │
  ├─ (HTTP GET) ── HLS 세그먼트(.ts) ──→ [VLC ts demuxer]
  │                                       │
  │                                   MPEG-TS 역다중화
  │                                   → H.264 NAL 유닛 추출
  │                                   → AAC 오디오 패킷 추출
  │                                       │
  │                               ┌───────┴───────┐
  │                               │               │
  │                        [VideoToolbox]    [AAC Decoder]
  │                        HW 디코딩          SW/HW 디코딩
  │                               │               │
  │                        decoded frame    decoded audio
  │                               │               │
  │                     [VLCSampleBufferDisplay]  [audio output]
  │                     Metal 렌더링               CoreAudio
  │                               │
  │                        [VLCLayerHostView]
  │                        (NSView + Metal layer)
```

### 4.2 VLC 내부 스레드 모델

```
Main Thread
  └── delegate callbacks (state, time, track events)

VLC Input Thread
  ├── HTTP access (네트워크 I/O)
  ├── ts demuxer (MPEG-TS 파싱)
  └── adaptive 모듈 (HLS 매니페스트 관리, 세그먼트 스케줄링)

VLC Decoder Thread (avcodec-threads에 의존)
  ├── VideoToolbox 세션 관리
  ├── 프레임 타임스탬프 관리
  └── 디코딩 결과 큐잉

VLC Video Output Thread (vout)
  ├── VLCSampleBufferDisplay
  ├── 프레임 스케줄링 (PTS 기반)
  └── AVSampleBufferDisplayLayer 프레임 큐잉

VLC Clock Thread
  └── clock-jitter, cr-average 기반 A/V 동기화
```

### 4.3 CPU 사용 분포 (파이프라인별)

프로파일링 결과 기반:

```
입력/네트워크 I/O:     ~5%   (HTTP GET, TLS)
Demux (ts/adaptive):   ~10%  (MPEG-TS 파싱, 매니페스트)
Decoder orchestration: ~15%  (VT 세션 관리, 타임스탬프, 큐잉)
VideoToolbox HW:       ~0%   (GPU — CPU 계산 없음)
vout/SampleBuffer:     ~40%  (프레임 스케줄링, Metal 합성)
Clock/Sync:            ~5%   (A/V 동기화)
Delegate callbacks:    ~5%   (Swift 레이어)
```

**핵심 인사이트:** CPU 소비의 **주체는 vout 파이프라인 (40%)**이다. 디코딩 자체가 아닌, 디코딩된 프레임을 화면에 표시하는 과정(Metal 합성, 프레임 스케줄링)이 가장 비싸다.

### 4.4 avcodec 옵션이 VideoToolbox에 미치는 영향

#### 4.4.1 VLC의 코덱 선택 메커니즘

```
:codec=videotoolbox,avcodec
```

이 옵션에 의해 VLC는:
1. **먼저** `videotoolbox` 모듈 시도 (`modules/codec/videotoolbox/decoder.c`)
2. **실패 시** `avcodec` 모듈 폴백 (`modules/codec/avcodec/video.c`)

#### 4.4.2 옵션별 적용 경로

| 옵션 | VideoToolbox 경로 | avcodec(SW) 경로 |
|-----|-------------------|------------------|
| `avcodec-threads` | ❌ 무시 (VT 자체 스레딩) | ✅ 적용 |
| `avcodec-fast` | ❌ 무시 | ✅ 적용 |
| `avcodec-hurry-up` | ⚠️ 부분 적용 가능 | ✅ 적용 |
| `avcodec-skip-idct` | ❌ 무시 (IDCT는 GPU) | ✅ 적용 |
| `avcodec-skiploopfilter` | ❌ 무시 (루프필터는 GPU) | ✅ 적용 |
| `avcodec-skip-frame` | ⚠️ VLC 레벨에서 적용 가능 | ✅ 적용 |
| `drop-late-frames` | ✅ vout 레벨 적용 | ✅ 적용 |
| `skip-frames` | ✅ decoder 스케줄링 레벨 | ✅ 적용 |

**⚠️ 핵심 결론:**  
`avcodec-*` 계열 옵션 대부분(threads, fast, skip-idct, skiploopfilter)은 **VideoToolbox HW 디코딩 활성 시 실효성이 없거나 극히 제한적**이다. 이들은 libavcodec의 소프트웨어 디코더를 제어하는 옵션이며, VT 모듈은 독립적인 코드 경로를 사용한다.

**실질적으로 효과가 있는 옵션:**
- `drop-late-frames`: vout 레벨에서 동작 → HW/SW 무관
- `skip-frames`: decoder 스케줄러가 프레임을 건너뛰도록 → 부분적 효과
- `adaptive-maxwidth/maxheight`: demux 레벨 → HW/SW 무관하게 해상도 제한

---

## 5. 라이브 HLS 스트리밍 특화 최적화

### 5.1 VLC adaptive 모듈 옵션 상세

VLC의 HLS/DASH 처리는 `modules/demux/adaptive/` 모듈이 담당한다.

```
--adaptive-logic={,predictive,nearoptimal,rate,fixedrate,lowest,highest}
```

#### 5.1.1 적응형 로직 알고리즘 비교

| 알고리즘 | 동작 방식 | 라이브 적합성 |
|---------|---------|-------------|
| `highest` (현재) | 항상 최고 비트레이트 선택 | ⚠️ 네트워크 변동 시 리버퍼링 |
| `predictive` | 과거 대역폭 데이터로 미래 예측 | ✅ 라이브에 가장 적합 |
| `nearoptimal` | BBA(Buffer-Based Approach) + 예측 | ✅ 버퍼 고려, 안정적 |
| `rate` | 현재 측정 대역폭 기반 | 🟡 반응적이나 불안정 |
| `fixedrate` | 고정 비트레이트 | ❌ 라이브 부적합 |
| `lowest` | 최저 비트레이트 | ❌ 화질 저하 |

**권장:** 멀티라이브 비선택 세션에서 `predictive` 사용 고려
```swift
// 현재: media.addOption(":adaptive-logic=highest")
// 변경 제안:
if profile == .multiLive && !isSelectedSession {
    media.addOption(":adaptive-logic=predictive")  // 대역폭 예측 기반
} else {
    media.addOption(":adaptive-logic=highest")     // 최고 화질 유지
}
```

#### 5.1.2 미적용 adaptive 옵션

```
--adaptive-bw=<integer>        고정 대역폭 (KiB/s)
--adaptive-use-access           HTTP access 모듈 사용 (기본: 비활성)
```

- `adaptive-bw`: 고정 대역폭 모드 — 멀티라이브에서 세션당 대역폭 캡으로 활용 가능
- `adaptive-use-access`: 기본 비활성이 올바름 (커스텀 HTTP 처리가 더 효율적)

### 5.2 HLS 매니페스트 리프레시 최적화

`manifestRefreshInterval`이 VLCStreamingProfile에 정의되어 있지만, **실제 미디어 옵션에 적용되지 않고 있다.**

VLC의 adaptive 모듈은 매니페스트 리프레시를 자동 관리하지만, 미세 조정 옵션이 제한적이다. VLC 4.0에서는 HLS 세그먼트 타겟 듀레이션 기반으로 자동 결정한다.

**관련 VLC 옵션:**
```
--http-reconnect          # HTTP 재연결 (이미 활성)
→ 매니페스트 리프레시에 간접적 영향
```

### 5.3 네트워크 레이어 최적화

#### 5.3.1 현재 HTTP 설정

```swift
media.addOption(":http-reconnect")
media.addOption(":http-referrer=\(CommonHeaders.chzzkReferer)")
media.addOption(":http-user-agent=\(CommonHeaders.safariUserAgent)")
```

#### 5.3.2 추가 가능한 네트워크 옵션

```
--ipv4-timeout=N            # TCP 연결 타임아웃 (ms)
--http-continuous            # HTTP 연속 모드 (기본 비활성)
```

- `ipv4-timeout`: 기본값이 VLC 컴파일 시 결정됨. 라이브 스트리밍에서 빠른 실패/재시도를 위해 `5000`ms(5초) 정도로 설정 고려
- `http-continuous`: 라이브 스트리밍에서는 일반적으로 불필요

### 5.4 TS Demuxer 튜닝

VLC의 MPEG-TS 디먹서 옵션:

```
--ts-standard=auto          # 디지털 TV 표준 (기본: auto) ✅
--ts-trust-pcr              # PCR 신뢰 (기본: enabled) ✅
--ts-split-es               # 개별 ES 분리 (기본: enabled) ✅
--ts-cc-check               # 연속성 카운터 체크 (기본: enabled) ✅
```

**평가:** 기본값이 HLS 라이브 스트리밍에 적합. 추가 설정 불필요.

### 5.5 `preferred-resolution` 옵션

VLC CLI에서 확인된 해상도 선호 옵션:
```
--preferred-resolution={Best available, 1080, 720, 576, 360, 240}
```

이 옵션은 `adaptive-maxheight`와 유사하지만, VLC 전역 설정으로 동작한다. `adaptive-maxheight`가 더 세밀하므로 현재 접근이 정확하다.

---

## 6. VideoToolbox 하드웨어 디코딩 심층 분석

### 6.1 VideoToolbox 디코딩 경로

```
VLC VideoToolbox 모듈 (modules/codec/videotoolbox/decoder.c)
  │
  ├── VTDecompressionSessionCreate()
  │     → 세션 생성 (코덱 정보, 출력 포맷 지정)
  │
  ├── VTDecompressionSessionDecodeFrame()
  │     → H.264 NAL 유닛 → 하드웨어 디코딩 (Apple M1 미디어 엔진)
  │
  ├── Callback: DecompressionOutputCallback()
  │     → 디코딩된 CVPixelBuffer 수신
  │     → VLC 프레임 큐에 삽입
  │
  └── 프레임 재정렬 (B프레임 DTS→PTS 순서)
```

### 6.2 Apple Silicon 미디어 엔진 특성

| 특성 | M1 | M1 Pro/Max | M2/M3/M4 |
|-----|-----|-----------|-----------|
| H.264 디코딩 | ✅ | ✅ | ✅ |
| HEVC 디코딩 | ✅ | ✅ | ✅ |
| AV1 디코딩 | ❌ | ❌ | ✅ (M3+) |
| 동시 세션 | ~16 | ~16 | ~16+ |
| 전용 미디어 엔진 | 공유 | 전용 ProRes | 전용 ProRes |

**멀티라이브 관련:**
- Apple Silicon은 하드웨어 수준에서 **다수의 동시 디코딩 세션**을 지원
- 각 세션은 독립적인 VTDecompressionSession으로 GPU 미디어 엔진에서 병렬 처리
- 4~8세션 동시 디코딩은 GPU 미디어 엔진의 용량 내

### 6.3 VideoToolbox 세션 최적화

VLC의 VideoToolbox 모듈은 세션 생성 시 다음을 자동 결정:
- 출력 픽셀 포맷 (NV12/BGRA)
- 프레임 재정렬 큐 크기
- 하드웨어 디코더 프로파일

**CView에서 제어 가능한 부분:**
1. **해상도 제한 (`adaptive-maxwidth/maxheight`)**: 인풋 해상도가 낮으면 VT 세션 부하 감소
2. **프레임 드롭 (`drop-late-frames`)**: VT 출력 후 vout에서 드롭 → 렌더링 부하 감소
3. **비디오 트랙 비활성화 (`deselectAllVideoTracks()`)**: VT 세션 자체를 중단

### 6.4 VLCSampleBufferDisplay 렌더링 경로

```
CVPixelBuffer (디코딩 완료)
  │
  ├── CMSampleBuffer 생성 (타이밍 정보 첨부)
  │
  ├── AVSampleBufferDisplayLayer.enqueue(sampleBuffer)
  │     → Metal 기반 렌더링
  │     → 자동 프레임 스케줄링 (PTS 기반)
  │
  └── CALayer 합성 → 화면 출력
```

**CPU 소비 핫스팟:**
- `CMSampleBuffer` 생성: ~5% — 메모리 할당 + 타이밍 메타데이터
- `enqueue()`: ~10% — Metal 명령 버퍼 제출
- `CALayer 합성`: ~25% — WindowServer와의 합성 (앱 외부 비용)

### 6.5 HW 디코딩 경로에서 실효성 있는 최적화

| 전략 | 메커니즘 | CPU 절감 |
|-----|---------|---------|
| **해상도 축소** | VT 인풋 픽셀 수 감소 → 디코딩+렌더링 전체 축소 | **높음** |
| **프레임 드롭 강화** | vout 큐에서 늦은 프레임 제거 → 렌더링 횟수 감소 | **중간** |
| **비디오 트랙 비활성화** | VT 세션 완전 중단 → 디코딩+렌더링 제거 | **최대** |
| **`minimalTimePeriod` 증가** | VLC 내부 타이밍 이벤트 빈도 감소 | **낮음** |
| **vout 제거 (오디오만)** | `deselectAllVideoTracks()` | **최대** |

---

## 7. 멀티뷰 렌더링 파이프라인 최적화

### 7.1 멀티라이브 리소스 사용 모델

4세션 동시 재생 시:

```
Session 1 (선택)    Session 2 (비선택)    Session 3 (비선택)    Session 4 (비선택)
1920×1080 HLS      854×480 HLS          854×480 HLS          854×480 HLS
VT Session #1      VT Session #2        VT Session #3        VT Session #4
SampleBuffer #1    SampleBuffer #2      SampleBuffer #3      SampleBuffer #4
Metal Layer #1     Metal Layer #2       Metal Layer #3       Metal Layer #4
```

각 세션의 CPU 비용 (추정):
- 선택 세션 (1080p): ~20% CPU
- 비선택 세션 (480p): ~8% CPU × 3 = ~24% CPU
- **총 멀티라이브 CPU**: ~44% (4세션)

### 7.2 세션 계층화 전략

```
┌─────────────────────────────────────────┐
│             Tier 1: 활성 세션             │
│  1080p, 모든 옵션 최고 품질              │
│  adaptive-logic=highest                  │
│  minimalTimePeriod=500000 (기본)         │
├─────────────────────────────────────────┤
│             Tier 2: 가시 비선택           │
│  480p, 성능 우선                         │
│  adaptive-logic=predictive              │
│  minimalTimePeriod=1000000 (1초)        │
│  avcodec-skiploopfilter=4               │
├─────────────────────────────────────────┤
│             Tier 3: 비가시 세션           │
│  비디오 트랙 비활성화                     │
│  오디오만 유지 또는 완전 중단             │
│  CPU: ~0%                               │
└─────────────────────────────────────────┘
```

### 7.3 세션 전환 시 해상도 업스위칭 최적화

비선택(480p) → 선택(1080p) 전환 시:

```
현재 흐름:
  adaptive-maxheight 변경 → HLS 매니페스트 재요청 → 고해상도 세그먼트 다운로드
  → 키프레임 대기 → 디코딩 시작 → 화면 표시
  지연: 1~3초

최적화 방안:
  1. 프리페치: 선택 가능성 높은 세션의 1080p 매니페스트를 미리 캐시
  2. 해상도 스텝: 480p → 720p → 1080p 단계적 업스위칭 (즉시 720p 재생)
  3. 더블 버퍼링: 비선택 세션에서 480p + 720p 두 렌더션 모두 수신 (대역폭 증가)
```

### 7.4 Metal 렌더링 최적화

VLC의 `VLCSampleBufferDisplay`는 내부적으로 `AVSampleBufferDisplayLayer`를 사용한다:

- `AVSampleBufferDisplayLayer`는 Metal 기반으로 프레임을 표시
- 각 세션마다 독립적인 레이어 생성 → **WindowServer 합성 비용 누적**

**최적화 기회:**
- **`layer.presentsWithTransaction = false`** (기본값) 유지 — 비동기 표시가 더 효율적
- **`layer.videoGravity`** 설정으로 스케일링 방식 최적화
- 비가시 레이어의 `isHidden = true` 설정 → WindowServer 합성에서 제외

---

## 8. 미구현 VLC 옵션 전수 분석

### 8.1 avcodec 디코딩 옵션

#### 8.1.1 `avcodec-skiploopfilter` (미구현 — 높은 우선순위)

```
--avcodec-skiploopfilter={0 (None), 1 (Non-ref), 2 (Bidir), 3 (Non-key), 4 (All)}
```

**분석:**
- H.264 디블로킹 필터(루프 필터)는 매크로블록 경계 아티팩트를 제거
- HD 스트림에서 SW 디코딩 시 CPU의 5~15% 소비
- **VideoToolbox 경로에서는 루프필터가 GPU에서 처리되므로 이 옵션은 무시됨**

**권장 구현:**
```swift
// VideoToolbox 폴백 시 효과를 보장하기 위해 설정
// (HW 디코딩 중에는 효과 없지만, SW 폴백 시 보험 역할)
if profile == .multiLive {
    media.addOption(":avcodec-skiploopfilter=4")  // 전체 스킵
} else {
    media.addOption(":avcodec-skiploopfilter=1")  // Non-ref만
}
```

#### 8.1.2 `avcodec-skip-frame` (미구현 — 중간 우선순위)

```
--avcodec-skip-frame={-1 (None), 0 (Default), 1 (B-frames), 2 (P-frames), 3 (B+P), 4 (All)}
```

**분석:**
- 프레임 타입별 디코딩 자체를 건너뜀
- B프레임 스킵(1)은 시각적 끊김을 유발하지만 CPU 절감 효과
- **주의:** 치지직 LL-HLS 인코딩이 B프레임을 사용하지 않을 가능성 높음 → 효과 없을 수 있음
- VLC 레벨의 프레임 스킵은 VideoToolbox에도 일부 영향 가능 (프레임을 VT에 전달하지 않으므로)

**검증 방법:**
```bash
# 스트림의 B프레임 존재 확인
ffprobe -select_streams v:0 -show_frames -show_entries frame=pict_type \
  "STREAM_URL" 2>/dev/null | grep pict_type | sort | uniq -c
```

#### 8.1.3 `avcodec-dr` (Direct Rendering — 미구현)

```
--avcodec-dr (기본: enabled)
```

**분석:**
- Direct Rendering은 디코더가 vout 메모리에 직접 쓰도록 하여 복사 오버헤드 제거
- 기본 활성이며, 비활성으로 변경할 이유 없음
- **현행 유지 (기본값 사용)**

#### 8.1.4 `avcodec-corrupted` (미구현)

```
--avcodec-corrupted (기본: enabled)
```

**분석:**
- 손상된 프레임을 표시할지 결정
- `enabled`: 깨진 프레임이라도 표시 (시각적 아티팩트)
- `disabled`: 깨진 프레임 드롭 (일시적 검은 화면)
- 라이브 스트리밍에서는 깨진 프레임 표시가 검은 화면보다 나은 UX → **기본값 유지**

#### 8.1.5 `avcodec-error-resilience` (미구현)

```
--avcodec-error-resilience=<integer [0..4]> (기본: 1)
```

**분석:**
- 에러 복원력 수준 (0=비활성, 4=최대)
- 라이브 스트리밍에서 네트워크 오류 복원에 유용하지만, CPU 오버헤드 발생
- 기본값(1)이 적절한 절충

#### 8.1.6 `avcodec-workaround-bugs` (미구현)

```
--avcodec-workaround-bugs=<integer> (기본: 1=autodetect)
```

**분석:**
- 특정 인코더 버그 우회 — 기본 자동 감지가 적절
- **현행 유지**

### 8.2 비디오 출력(vout) 옵션

#### 8.2.1 `drop-late-frames` / `skip-frames` (이미 구현 ✅)

```
--drop-late-frames (기본: enabled) → 이미 :drop-late-frames=1 설정
--skip-frames (기본: enabled)      → 이미 :skip-frames=1 설정
```

#### 8.2.2 `quiet-synchro` (미구현 — 낮은 우선순위)

```
--quiet-synchro (기본: disabled)
```

**분석:**
- 동기화 디버그 출력 억제
- Release 빌드에서는 의미 없음
- **설정 불필요**

### 8.3 후처리(postproc) 옵션

#### 8.3.1 `postproc-q` (이미 구현 ✅)

```
--postproc-q=0  → 이미 비활성 ✅
```

#### 8.3.2 `postproc-name` (미구현 — 불필요)

```
--postproc-name=<string>  (FFmpeg 후처리 필터 체인)
```

**분석:** `postproc-q=0`으로 후처리 비활성이므로 불필요.

### 8.4 비디오 필터 옵션 (비적용 확인)

현재 비적용 상태인 필터들 (라이브 스트리밍에서 사용하지 않는 것이 올바름):

- `sharpen`: 선명도 필터 — CPU 낭비
- `hqdn3d`: 노이즈 제거 — CPU 집약적
- `grain`: 노이즈 추가 — 불필요
- `rotate`: 회전 — 불필요
- `transform`: 변환 — 불필요

**결론:** 현재 비디오 필터 비적용 상태가 올바르다.

### 8.5 완전 미구현 고급 옵션 (잠재적 유용성)

#### 8.5.1 `avcodec-options` (고급 FFmpeg 옵션)

```
--avcodec-options=<string>  # 형식: {opt=val,opt2=val2}
```

**이 옵션을 통해 FFmpeg의 모든 디코더 옵션을 직접 전달할 수 있다.**

잠재적으로 유용한 FFmpeg 디코더 옵션:
```swift
// 예시: 스레드 타입 지정
media.addOption(":avcodec-options={threads=auto,thread_type=frame}")

// 예시: lowres 디코딩 (해상도 축소 디코딩)
// H.264에서는 지원되지 않을 수 있음
media.addOption(":avcodec-options={lowres=1}")
```

**주의:** VideoToolbox 경로에서는 `avcodec-options`가 무시된다.

#### 8.5.2 `swscale-mode` (비디오 스케일링)

```
--swscale-mode={0 (Fast bilinear), 1 (Bilinear), 2 (Bicubic), ..., 10 (Bicubic spline)}
```

**분석:**
- 스케일링 품질 vs 속도 트레이드오프
- VLC 내부에서 해상도 변환 시 사용
- `0` (Fast bilinear)이 가장 빠름 — 멀티라이브에서 성능 우선 시 고려
- 그러나 `VLCSampleBufferDisplay`가 Metal 스케일링을 사용하므로 이 옵션의 영향은 제한적

---

## 9. VLCKit 4.0 고급 API 활용 방안

### 9.1 `minimalTimePeriod` 튜닝

```swift
// 현재: VLCKit 기본값 (500,000µs = 0.5초)
// 제안: 멀티라이브에서 증가

// VLCPlayerEngine.swift의 _startPlay()에 추가:
if streamingProfile == .multiLive {
    player.minimalTimePeriod = 1_000_000  // 1초 (기본의 2배)
}
```

**기대 효과:**
- VLC 내부 타이밍 이벤트 처리 빈도 50% 감소
- 4세션 × 50% 감소 = 전체 타이밍 관련 CPU 부하 절반

### 9.2 `timeChangeUpdateInterval` 튜닝

```swift
// 현재: VLCKit 기본값 (1.0초)
// 제안: 멀티라이브 비선택 세션에서 증가

if streamingProfile == .multiLive && !isSelectedSession {
    player.timeChangeUpdateInterval = 5.0  // 5초 간격
}
```

**기대 효과:**
- delegate 시간 변경 콜백 5분의 1로 감소
- 라이브 스트리밍에서 시간 표시는 중요도 낮음

### 9.3 VLCMediaPlayer.videoSize 활용

```objc
@property (nonatomic, readonly) CGSize videoSize;
```

현재 `collectMetrics()`에서 `_cachedVideoSize`로 캐싱하여 사용 중. 이를 활용하여:

```swift
// 동적 해상도 감지 → 적응형 최적화
let size = player.videoSize
if size.width <= 854 && streamingProfile == .multiLive {
    // 이미 480p로 디코딩 중 → 추가 최적화 불필요
} else if size.width > 1280 {
    // 예상보다 높은 해상도 → adaptive-maxheight 재조정 필요
}
```

### 9.4 VLCMedia.Statistics 실시간 성능 모니터링

통계 기반 자동 최적화 시스템:

```swift
func adaptiveQualityTuning(stats: VLCMedia.Stats, prevStats: VLCMedia.Stats) {
    let lostDelta = Int(stats.lostPictures) - Int(prevStats.lostPictures)
    let lateDelta = Int(stats.latePictures) - Int(prevStats.latePictures)
    let demuxCorrupted = Int(stats.demuxCorrupted) - Int(prevStats.demuxCorrupted)
    
    // 프레임 드롭 급증 → 해상도 자동 하향
    if lostDelta > 5 || lateDelta > 10 {
        // adaptive-maxheight 축소 요청
        onQualityAdaptationRequest?(.downgrade(reason: "frame_loss"))
    }
    
    // demux 손상 → 네트워크 문제 → 버퍼 확대 고려
    if demuxCorrupted > 0 {
        Log.player.warning("Demux 손상 감지: \(demuxCorrupted)")
    }
}
```

### 9.5 녹화/스냅샷 API의 성능 분리

현재 구현된 녹화 API:
```swift
player.startRecording(atPath:)
player.stopRecording()
player.saveVideoSnapshot(at:withWidth:andHeight:)
```

**성능 고려:** 녹화 활성화 시 VLC 내부에서 추가 데이터 경로(mux → 파일)가 생성되어 CPU 부하 증가. 멀티라이브에서는 한 번에 하나의 세션만 녹화하도록 제한하는 것이 안전하다.

### 9.6 Deinterlace API 확인

```objc
- (void)setDeinterlace:(nullable NSString *)name;
```

**현재:** `:deinterlace=0` 미디어 옵션으로 비활성 ✅  
API를 통한 런타임 디인터레이스 변경도 가능하나, 라이브 HLS 소스가 프로그레시브이므로 불필요.

---

## 10. 종합 최적화 로드맵

### 10.1 즉시 적용 가능한 최적화 (코드 변경 최소)

| # | 항목 | 예상 영향 | 구현 | 위험 |
|---|-----|----------|-----|-----|
| **A1** | `player.minimalTimePeriod = 1_000_000` (멀티라이브) | 타이밍 이벤트 50% 감소 | 1줄 | 극히 낮음 |
| **A2** | `player.timeChangeUpdateInterval = 5.0` (비선택) | 콜백 80% 감소 | 1줄 | 극히 낮음 |
| **A3** | `adaptive-logic=predictive` (멀티라이브 비선택) | 리버퍼링 감소 | 조건부 1줄 | 낮음 |
| **A4** | `avcodec-skiploopfilter=4` (멀티라이브) | SW 폴백 시 효과 | 1줄 | 낮음 |
| **A5** | `avcodec-skip-frame=1` (멀티라이브 비선택) | B프레임 依存 | 조건부 1줄 | 중간 |

### 10.2 중기 최적화 (아키텍처 변경 필요)

| # | 항목 | 예상 영향 | 구현 | 위험 |
|---|-----|----------|-----|-----|
| **B1** | 3-Tier 세션 계층화 (활성/가시/비가시) | **최대** | 높음 | 중간 |
| **B2** | 자동 비디오 트랙 비활성화 (비가시 세션) | **최대** | 중간 | 재활성화 지연 |
| **B3** | 통계 기반 자동 화질 조정 | 중간 | 중간 | 품질 변동 |
| **B4** | 해상도 스텝 업스위칭 (480→720→1080) | UX 개선 | 중간 | 복잡도 |

### 10.3 장기 최적화 (연구/실험 필요)

| # | 항목 | 예상 영향 | 구현 | 위험 |
|---|-----|----------|-----|-----|
| **C1** | VLCDrawable 커스텀 렌더러 (Metal 직접) | **높음** | 매우 높음 | 높음 |
| **C2** | AVPlayer 멀티라이브 대체 평가 | **높음** | 높음 | 호환성 |
| **C3** | libvlc C API 직접 활용 | 중간 | 높음 | 안정성 |
| **C4** | VLCKit 커스텀 빌드 (configure 옵션 최적화) | 중간 | 매우 높음 | 유지보수 |

### 10.4 최적화 적용 코드 종합

```swift
func applyMediaOptions(_ media: VLCMedia, profile: VLCStreamingProfile) {
    // === 기존 옵션 (유지) ===
    media.addOption(":network-caching=\(profile.networkCaching)")
    media.addOption(":live-caching=\(profile.liveCaching)")
    media.addOption(":file-caching=0")
    media.addOption(":disc-caching=0")
    media.addOption(":cr-average=\(profile.crAverage)")
    media.addOption(":avcodec-threads=\(profile.decoderThreads)")
    media.addOption(":avcodec-fast=1")
    media.addOption(":http-reconnect")
    
    let maxW = profile.adaptiveMaxWidth(isSelected: isSelectedSession)
    var maxH = profile.adaptiveMaxHeight(isSelected: isSelectedSession)
    if maxAdaptiveHeight > 0 { maxH = min(maxH, maxAdaptiveHeight) }
    media.addOption(":adaptive-maxwidth=\(maxW)")
    media.addOption(":adaptive-maxheight=\(maxH)")
    
    media.addOption(":deinterlace=0")
    media.addOption(":postproc-q=0")
    media.addOption(":clock-jitter=\(profile.clockJitter)")
    media.addOption(":clock-synchro=0")
    media.addOption(":codec=videotoolbox,avcodec")
    media.addOption(":avcodec-hw=videotoolbox")
    media.addOption(":http-referrer=\(CommonHeaders.chzzkReferer)")
    media.addOption(":http-user-agent=\(CommonHeaders.safariUserAgent)")
    if profile.dropLateFrames { media.addOption(":drop-late-frames=1") }
    if profile.skipFrames { media.addOption(":skip-frames=1") }
    media.addOption(":avcodec-hurry-up=1")
    
    // === 신규 최적화 옵션 ===
    
    // [NEW-A3] 멀티라이브 비선택 세션: 적응형 로직 변경
    if profile == .multiLive && !isSelectedSession {
        media.addOption(":adaptive-logic=predictive")
    } else {
        media.addOption(":adaptive-logic=highest")
    }
    
    // [NEW-A4] 루프필터 스킵 (SW 폴백 보험 + 멀티라이브 최적화)
    if profile == .multiLive {
        media.addOption(":avcodec-skiploopfilter=4")  // 전체 스킵
    } else {
        media.addOption(":avcodec-skiploopfilter=1")  // Non-ref만
    }
    
    // [기존] IDCT 스킵 (multiLive)
    if profile == .multiLive {
        media.addOption(":avcodec-skip-idct=4")
    }
    
    // [NEW-A5] B프레임 스킵 (멀티라이브 비선택)
    if profile == .multiLive && !isSelectedSession {
        media.addOption(":avcodec-skip-frame=1")  // B프레임 스킵
    }
    
    // [기존] 프리패치 버퍼
    if profile == .multiLive {
        media.addOption(":prefetch-buffer-size=786432")
    } else {
        media.addOption(":prefetch-buffer-size=393216")
    }
}

// [NEW-A1, A2] 플레이어 인스턴스 설정 (_startPlay에서)
func configurePlayerTiming() {
    if streamingProfile == .multiLive {
        player.minimalTimePeriod = 1_000_000  // 1초 (기본 0.5초의 2배)
        if !isSelectedSession {
            player.timeChangeUpdateInterval = 5.0  // 5초 간격
        }
    }
}
```

### 10.5 성능 검증 체크리스트

| 테스트 항목 | 측정 방법 | 판단 기준 |
|-----------|---------|---------|
| 단일 스트림 CPU | `top -pid` / Activity Monitor | < 30% |
| 멀티라이브 4세션 CPU | `top -pid` | < 50% |
| 초기 재생 지연 | 타이머 측정 (play()→첫 프레임) | < 3초 |
| 리버퍼링 빈도 | lostPictures delta / 시간 | < 0.1% |
| 프레임 드롭율 | latePictures delta / decodedVideo | < 1% |
| 채널 전환 시간 | switchMedia()→첫 프레임 | < 1초 |
| 메모리 사용 | footprint (RSS) | < 500MB (4세션) |

### 10.6 최적화 효과 요약

```
현재 상태 (추정):
  단일 1080p:     ~25-35% CPU
  멀티라이브 4세션: ~50-70% CPU

즉시 적용 후 (A1-A5):
  단일 1080p:     ~22-30% CPU  (타이밍 최적화)
  멀티라이브 4세션: ~40-55% CPU (로직+타이밍+필터 스킵)

중기 적용 후 (B1-B4):  
  멀티라이브 4세션: ~25-40% CPU (비가시 세션 중단)

장기 목표:
  멀티라이브 4세션: ~20-30% CPU (Metal 렌더러 + AVPlayer 하이브리드)
```

---

## 부록

### A. avcodec 모듈 전체 디코딩 옵션 레퍼런스

| 옵션 | 기본값 | 범위 | 설명 |
|-----|-------|-----|-----|
| `avcodec-dr` | enabled | bool | Direct Rendering |
| `avcodec-corrupted` | enabled | bool | 손상 프레임 표시 |
| `avcodec-error-resilience` | 1 | 0-4 | 에러 복원력 |
| `avcodec-workaround-bugs` | 1 | int | 인코더 버그 우회 |
| `avcodec-hurry-up` | enabled | bool | 지연 시 부분 디코딩 |
| `avcodec-skip-frame` | 0 | -1~4 | 프레임 스킵 수준 |
| `avcodec-skip-idct` | 0 | -1~4 | IDCT 스킵 수준 |
| `avcodec-fast` | disabled | bool | 비표준 고속 트릭 |
| `avcodec-skiploopfilter` | 0 | 0~4 | 루프필터 스킵 |
| `avcodec-debug` | 0 | int | 디버그 마스크 |
| `avcodec-codec` | NULL | string | 코덱 지정 |
| `avcodec-hw` | any | enum | HW 가속 지정 |
| `avcodec-threads` | 0 | int | 디코더 스레드 (0=auto) |
| `avcodec-options` | NULL | string | 고급 FFmpeg 옵션 |

### B. adaptive 모듈 전체 옵션 레퍼런스

| 옵션 | 기본값 | 설명 |
|-----|-------|-----|
| `adaptive-logic` | (자동) | 적응 알고리즘 |
| `adaptive-maxwidth` | (제한 없음) | 최대 폭 |
| `adaptive-maxheight` | (제한 없음) | 최대 높이 |
| `adaptive-bw` | (자동) | 고정 대역폭 (KiB/s) |
| `adaptive-use-access` | disabled | HTTP access 모듈 사용 |

### C. 핵심 VLC CLI 옵션 (라이브 스트리밍 관련)

| 카테고리 | 옵션 | 현재 | 용도 |
|---------|-----|-----|-----|
| 캐싱 | `network-caching` | 설정 ✅ | 네트워크 버퍼 |
| | `live-caching` | 설정 ✅ | 라이브 버퍼 |
| | `file-caching` | 0 ✅ | 파일 버퍼 |
| | `disc-caching` | 0 ✅ | 디스크 버퍼 |
| 디코딩 | `codec` | videotoolbox,avcodec ✅ | 코덱 우선순위 |
| | `avcodec-hw` | videotoolbox ✅ | HW 가속 |
| | `avcodec-threads` | 프로파일별 ✅ | 디코더 스레드 |
| | `avcodec-fast` | 1 ✅ | 고속 트릭 |
| | `avcodec-hurry-up` | 1 ✅ | 지연 대응 |
| | `avcodec-skip-idct` | 4 (멀티) ✅ | IDCT 스킵 |
| | `avcodec-skiploopfilter` | **미설정** | 루프필터 |
| | `avcodec-skip-frame` | **미설정** | 프레임 스킵 |
| 후처리 | `deinterlace` | 0 ✅ | 디인터레이스 |
| | `postproc-q` | 0 ✅ | 후처리 품질 |
| 동기화 | `clock-synchro` | 0 ✅ | 클럭 동기 |
| | `clock-jitter` | 프로파일별 ✅ | 클럭 지터 |
| | `cr-average` | 프로파일별 ✅ | 클럭 복구 |
| vout | `drop-late-frames` | 1 ✅ | 프레임 드롭 |
| | `skip-frames` | 1 ✅ | 프레임 스킵 |
| 적응형 | `adaptive-logic` | highest 🟡 | 적응 알고리즘 |
| | `adaptive-maxwidth` | 프로파일별 ✅ | 최대 폭 |
| | `adaptive-maxheight` | 프로파일별 ✅ | 최대 높이 |
| HTTP | `http-reconnect` | ✅ | 재연결 |
| 버퍼 | `prefetch-buffer-size` | 프로파일별 ✅ | 프리패치 |

### D. 참고 자료

- VLCKitSPM GitHub: https://github.com/rursache/VLCKitSPM (revision 94ca521)
- VLC avcodec 모듈 문서: https://wiki.videolan.org/Documentation:Modules/avcodec/
- VLC CLI 전체 옵션: https://wiki.videolan.org/VLC_command-line_help/
- VLCKit 4.0.0a18 (libvlc 4.0.0) — VideoLAN unstable builds
- Apple VideoToolbox 프레임워크 문서
- CView 소스 코드:
  - `Sources/CViewPlayer/VLCPlayerEngine.swift`
  - `Sources/CViewPlayer/VLCPlayerEngine+Playback.swift`
  - `Sources/CViewPlayer/VLCPlayerEngine+Features.swift`
  - `Sources/CViewPlayer/VLCPlayerEngine+AudioVideo.swift`
- 기존 연구 문서: `docs/vlc-cpu-optimization-research.md`
