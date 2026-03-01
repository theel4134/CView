# VLCKit 4.0 macOS Video Output Module 종합 분석 보고서

> **연구 목적**: VLCKit 4.0의 vout 모듈이 프레임을 어떻게 처리하며, 4개 동시 스트림에서 UI 프리징을 유발하는 근본 원인을 규명
> **분석 방법**: VLCKit.xcframework 바이너리 역공학 (nm, strings, objdump) + VLC 소스코드 (code.videolan.org) 교차 검증
> **분석 대상**: VLCKit 4.0 xcframework (vlckit-spm, macos-arm64_x86_64)

---

## 질문 1: VLCKit 4.0이 기본 사용하는 vout 모듈은?

### 결론: `samplebufferdisplay` (AVSampleBufferDisplayLayer 기반)

**근거:**

VLCKit 4.0 바이너리에 컴파일된 vout 모듈 목록 (`strings` + `nm` 확인):

| 모듈명 | 우선순위 | 설명 |
|--------|----------|------|
| **samplebufferdisplay** | **600 (최고)** | AVSampleBufferDisplayLayer 기반, Apple 추천 경로 |
| caopengllayer | 300 | CGL/OpenGL 기반 CAOpenGLLayer, **deprecated API** |
| macosx | 미확인 | 레거시 NSOpenGLView 기반 |
| vdummy | - | 더미 (표시 없음) |
| vmem | - | 메모리 버퍼 출력 |
| flaschen | - | 네트워크 LED 디스플레이용 |

VLC의 모듈 선택 시스템은 **우선순위가 높은 모듈을 먼저 시도**한다. `samplebufferdisplay`는 `set_callback_display(Open, 600)`으로 등록되어 있어, `caopengllayer`(300)보다 항상 우선 선택된다.

**VLCSampleBufferDisplay의 Open 함수 조건:**
```c
static int Open(vout_display_t *vd, video_format_t *fmt, vlc_video_context *context) {
    // force-darwin-legacy-display가 true이면 이 모듈을 건너뜀
    if (var_InheritBool(vd, "force-darwin-legacy-display"))
        return VLC_EGENERIC;
    // 360도 콘텐츠는 지원하지 않음
    if (!vd->obj.force && fmt->projection_mode != PROJECTION_MODE_RECTANGULAR)
        return VLC_EGENERIC;
    // window 타입이 VLC_WINDOW_TYPE_NSOBJECT여야 함
    if (vd->cfg->window->type != VLC_WINDOW_TYPE_NSOBJECT)
        return VLC_EGENERIC;
    // ... (정상 초기화)
}
```

**현재 앱에서의 선택 과정:**
- `player.drawable = NSView` → VLCKit 내부에서 `libvlc_media_player_set_nsobject` 호출
- window type = `VLC_WINDOW_TYPE_NSOBJECT` 설정
- `:vout=` 옵션을 설정하지 않음 → 우선순위 순서대로 시도
- **결과: samplebufferdisplay(600)가 자동 선택**

---

## 질문 2: 대안 vout 모듈을 강제할 수 있는가?

### 결론: 가능하나, 실용적 대안은 제한적

**방법 1: `:vout=` 미디어 옵션**
```swift
media.addOption(":vout=caopengllayer")  // CGL/OpenGL 기반
media.addOption(":vout=macosx")         // 레거시 NSOpenGLView
```

**방법 2: `force-darwin-legacy-display` 변수**
```swift
media.addOption(":force-darwin-legacy-display")  // samplebufferdisplay 비활성화 → caopengllayer 폴백
```

**각 대안의 평가:**

| 옵션 | 스레딩 모델 | 문제점 |
|------|------------|--------|
| `caopengllayer` | drawInCGLContext (CA 렌더 스레드) | **OpenGL deprecated** (macOS 10.14+), CGL API 사용 |
| `macosx` | NSOpenGLView | 가장 오래된 경로, 성능 최악 |
| `vmem` | 콜백 기반 | 직접 렌더링 파이프라인 구현 필요 |

**caopengllayer의 스레딩 분석 (소스 코드 기반):**
```objc
// caopengllayer.m의 Open 함수 — dispatch_SYNC(메인 큐) 호출 (블로킹!)
static int Open(vout_display_t *vd, ...) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // view.render 블록 설정 — 이 블록이 drawInCGLContext에서 호출됨
        layer.render = ^(NSSize displaySize) {
            vout_display_opengl_Display(sys->vgl);  // OpenGL 렌더링
        };
    });
}

// PictureRender — VLC 렌더 스레드에서 호출
static void PictureRender(vout_display_t *vd, picture_t *pic, ...) {
    vlc_gl_MakeCurrent(sys->gl);     // CGL 컨텍스트 잠금
    vout_display_opengl_Prepare(...); // OpenGL 텍스처 업로드
    vlc_gl_ReleaseCurrent(sys->gl);
    [layer markReady];  // atomic_store → CA가 다음 display cycle에서 그림
}

// PictureDisplay — VLC 렌더 스레드에서 호출
static void PictureDisplay(vout_display_t *vd, picture_t *pic) {
    [layer displayFromVout];  // → [super display] → [CATransaction flush]
}

// drawInCGLContext — CoreAnimation 렌더 스레드에서 호출
- (void)drawInCGLContext:(CGLContextObj)glContext ... {
    if (self.render != nil)
        self.render(newSize);  // → vout_display_opengl_Display → GL → 화면
}
```

**핵심 차이**: `caopengllayer`는 `drawInCGLContext`가 CA 렌더 스레드에서 호출되므로 GL 렌더링 자체는 메인 스레드를 사용하지 않는다. 그러나 **deprecated OpenGL API**를 사용하며, Apple Silicon에서는 Metal로 번역되는 오버헤드가 발생한다.

**권장**: 현재의 `samplebufferdisplay`가 최선의 선택이다. 이유는 질문 3에서 설명.

---

## 질문 3: VLCSampleBufferDisplay.prepareDisplay는 매 프레임마다 메인 큐로 dispatch하는가?

### 결론: **아니오** — 초기 1회 셋업만 메인 큐, 프레임 렌더링은 VLC 스레드에서 직접 수행

**⚠️ 이전 바이너리 역공학 분석의 오해 정정:**

이전에 `objdump` 디스어셈블리에서 `prepareDisplay` 내부에 `dispatch_async(dispatch_get_main_queue())` 호출을 발견했으나, 이는 **매 프레임 dispatch가 아니라 1회성 뷰 초기화**였다.

**VLCSampleBufferDisplay.m 소스 코드 (code.videolan.org/videolan/vlc에서 확인):**

```objc
// ====== prepareDisplay: 1회성 초기화 ======
- (void)prepareDisplay {
    @synchronized(_displayLayer) {
        if (_displayLayer)    // ← 이미 초기화됨?
            return;           // ← 즉시 리턴! 메인 큐 dispatch 없음!
    }

    VLCSampleBufferDisplay *sys = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 최초 1회만 실행됨:
        // - VLCSampleBufferDisplayView 생성
        // - AVSampleBufferDisplayLayer 생성
        // - window에 subview 추가
        // - displayLayer 프로퍼티 설정
    });
}

// ====== RenderPicture: 매 프레임 호출 — 메인 큐 아님! ======
static void RenderPicture(vout_display_t *vd, picture_t *pic, vlc_tick_t date) {
    VLCSampleBufferDisplay *sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    // 1. CVPixelBuffer 추출 (zero-copy IOSurface 참조)
    CVPixelBufferRef pixelBuffer = cvpxpic_get_ref(dst);

    // 2. CMSampleBuffer 생성
    CMSampleBufferCreateReadyWithImageBuffer(..., pixelBuffer, ..., &sampleBuffer);

    // 3. ★ AVSampleBufferDisplayLayer에 직접 enqueue — 현재 (VLC) 스레드에서! ★
    @synchronized(sys.displayLayer) {
        [sys.displayLayer enqueueSampleBuffer:sampleBuffer];
    }
}

// ====== Prepare: 매 프레임 진입점 ======
static void Prepare(vout_display_t *vd, picture_t *pic,
                    const vlc_render_subpicture *subpicture, vlc_tick_t date) {
    PrepareDisplay(vd);    // → [sys prepareDisplay] → 이미 초기화됨 → 즉시 리턴
    if (pic) {
        RenderPicture(vd, pic, date);   // ★ VLC 렌더 스레드에서 실행
    }
    RenderSubpicture(vd, subpicture);   // 자막이 변경된 경우에만 main dispatch
}
```

### 프레임 렌더링 스레드 흐름 (정상 재생 시)

```
VLC Render Thread (메인 스레드 아님!)
├─ Prepare() 호출
│   ├─ PrepareDisplay() → prepareDisplay → displayLayer 존재 → 즉시 리턴 (0 cost)
│   ├─ RenderPicture()
│   │   ├─ cvpxpic_get_ref() → IOSurface-backed CVPixelBuffer 획득
│   │   ├─ CMSampleBufferCreateReadyWithImageBuffer()
│   │   └─ [displayLayer enqueueSampleBuffer:] ← 스레드-안전, 메인 큐 아님!
│   └─ RenderSubpicture() → 자막 변경 없으면 no-op
└─ Display() → 빈 함수 (pacing용 콜백)
```

**Apple 문서 확인**: `AVSampleBufferDisplayLayer.enqueueSampleBuffer(_:)`는 **어떤 스레드에서든 호출 가능**하다고 문서화되어 있다. 내부적으로 비동기 큐에 넣고, CoreAnimation 렌더 서버(별도 프로세스)에서 GPU 합성한다.

### 메인 큐로 dispatch되는 유일한 경우

| 시점 | 함수 | 빈도 |
|------|------|------|
| 최초 표시 준비 | `prepareDisplay` → `dispatch_async(main)` | **1회** |
| 자막 변경 시 | `RenderSubpicture` → `dispatch_async(main)` | 자막 있을 때만 |
| 종료 시 | `close` → `dispatch_async(main)` → `removeFromSuperview` | **1회** |

---

## 질문 4: `canDrawSubviewsIntoLayer = true`가 미치는 영향

### 결론: AVSampleBufferDisplayLayer에는 직접적 영향이 적으나, 제거를 권장

**현재 설정 (VLCLayerHostView):**
```swift
class VLCLayerHostView: NSView {
    init() {
        wantsLayer = true
        canDrawSubviewsIntoLayer = true   // ← 문제의 설정
        layerContentsRedrawPolicy = .never
        layer.drawsAsynchronously = true
    }
}
```

**canDrawSubviewsIntoLayer의 동작:**
- AppKit에게 모든 서브뷰의 `drawRect:` 콘텐츠를 부모 뷰의 레이어에 통합 렌더링하라고 지시
- **목적**: 레이어 수를 줄여 CoreAnimation 합성 비용을 절약
- **문제**: `drawRect:` 기반 렌더링에만 영향 — AVSampleBufferDisplayLayer는 `drawRect:`를 사용하지 않음

**영향 분석:**

| 측면 | 영향 |
|------|------|
| AVSampleBufferDisplayLayer의 `enqueueSampleBuffer` | ❌ 영향 없음 (GPU 기반 별도 렌더링 경로) |
| CoreAnimation 레이어 트리 관리 | ⚠️ 레이어 통합 시도로 불필요한 오버헤드 가능 |
| VLCSampleBufferDisplayView (NSView) | ⚠️ `drawRect:` 호출 시 부모 레이어에 통합 시도 |
| VLCSampleBufferSubpictureView (자막) | ⚠️ 자막의 `drawRect:` 콘텐츠가 부모에 통합됨 |

**권장**: `canDrawSubviewsIntoLayer = false`로 변경. 이유:
1. VLCSampleBufferDisplay가 내부적으로 생성하는 `VLCSampleBufferDisplayView`와 `VLCSampleBufferSubpictureView`는 독립된 레이어를 가져야 효율적
2. AVSampleBufferDisplayLayer는 자체 GPU 합성 경로를 사용하므로 레이어 통합이 불필요
3. 4개 뷰 × 2개 서브뷰(display + spu) = 8개의 레이어 통합 시도가 불필요한 CA 트리 연산을 유발할 수 있음

---

## 질문 5: VideoToolbox zero-copy와 IOSurface 동작

### 결론: 현재 설정이 최적 경로 — 수정 불필요

**현재 앱 설정:**
```swift
media.addOption(":codec=videotoolbox,avcodec,all")
media.addOption(":videotoolbox-zero-copy=1")
```

**zero-copy 데이터 흐름:**
```
HLS/RTMP 네트워크 데이터
    ↓
VideoToolbox 하드웨어 디코더 (GPU/미디어 엔진)
    ↓
CVPixelBuffer (IOSurface-backed, GPU 메모리에 상주)
    ↓ cvpxpic_get_ref() — CPU 복사 없음
CVPixelBuffer → CMSampleBuffer 래핑
    ↓ enqueueSampleBuffer: — CPU 복사 없음
AVSampleBufferDisplayLayer → CoreAnimation 렌더 서버 → GPU 합성 → 디스플레이
```

**핵심**: 전체 파이프라인에서 **CPU 메모리 복사가 0회**. IOSurface는 GPU 메모리를 프로세스 간(앱↔렌더 서버) 공유하는 커널 객체이므로, VideoToolbox → AVSampleBufferDisplayLayer 경로는 Apple 플랫폼에서 가장 효율적인 비디오 표시 경로다.

**VLCSampleBufferDisplay의 CVPX 처리:**
```objc
// converter가 없으면 (VT 디코더 출력이 직접 호환되면) 직접 사용
if (!vlc_video_context_GetPrivate(vctx, VLC_VIDEO_CONTEXT_CVPX)) {
    converter = CreateCVPXConverter(vd, fmt);  // SW 디코딩 시에만 변환기 생성
}

// RenderPicture에서:
CVPixelBufferRef pixelBuffer = cvpxpic_get_ref(dst);  // IOSurface 참조만 획득
// → CMSampleBuffer로 래핑 → enqueueSampleBuffer
```

**`:videotoolbox-zero-copy=1`이 하는 일:**
- VLC의 VideoToolbox 디코더가 CVPixelBuffer를 직접 출력하도록 함
- IOSurface-backed 버퍼를  별도 메모리로 복사하지 않음
- `=0`이면 VLC가 내부적으로 CPU 복사를 수행하여 디코더 참조를 해제함

---

## 질문 6: 메인 스레드 렌더링을 우회하기 위한 모든 가능한 해법

### 핵심 발견: 프레임 렌더링은 이미 메인 스레드를 사용하지 않는다!

이전 분석에서 "120 blocks/sec 메인 큐 포화"가 vout 모듈의 per-frame dispatch 때문이라고 가정했으나, 소스 코드 분석 결과 **이 가정은 틀렸다.** `RenderPicture`의 `enqueueSampleBuffer:`는 VLC 렌더 스레드에서 직접 호출되며 메인 큐를 사용하지 않는다.

### 실제 메인 스레드 부하 원인 (우선순위순)

#### 원인 1: VLCKit의 timeChangeUpdateTimer (NSTimer)
```
// VLCMediaPlayer 내부 (바이너리 분석으로 확인):
- NSTimer (_timeChangeUpdateTimer) → main run loop에서 반복 실행
- 4개 플레이어 × timer interval마다 → 메인 스레드 콜백
```
- VLCKit 4.0의 `VLCMediaPlayer`는 내부적으로 `NSTimer`를 사용하여 시간 변경을 폴링
- 이 타이머는 **메인 런 루프**에서 실행됨
- 4개 플레이어 = 4개의 독립적인 `NSTimer`가 메인 스레드를 반복 점유

#### 원인 2: VLCMediaPlayerDelegate 콜백의 메인 큐 dispatch

**현재 VLCPlayerEngine.swift 코드:**
```swift
// mediaPlayerStateChanged — 모든 상태 변경 시 메인 큐 dispatch
public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
    // ... 상태 처리 ...
    DispatchQueue.main.async { [weak self] in
        self?.onStateChange?(phase)  // 메인 큐 dispatch
    }
}

// mediaPlayerTimeChanged — 이미 최적화됨 ✅
public func mediaPlayerTimeChanged(_ aNotification: Notification) {
    // ✅ 콜백이 nil이면 dispatch 자체를 생략
    guard let callback = onTimeChange else { return }
    DispatchQueue.main.async { callback(ct, dur) }
}
```

현재 코드에서 multiLive 시나리오에서 `onTimeChange = nil`로 설정하여 시간 콜백의 메인 dispatch를 이미 제거한 것은 올바른 최적화다. 그러나 **VLCKit 내부의 NSTimer**는 여전히 메인 스레드에서 실행된다.

#### 원인 3: CoreAnimation 4개 AVSampleBufferDisplayLayer 합성

- 4개의 독립적인 AVSampleBufferDisplayLayer가 각각 30fps로 화면을 갱신
- CoreAnimation 렌더 서버가 매 프레임마다 4개 레이어를 합성
- CA 트랜잭션 커밋이 메인 스레드에서 발생할 수 있음
- `canDrawSubviewsIntoLayer = true`가 불필요한 레이어 플래트닝을 유발

#### 원인 4: VLCKit의 KVO/NSNotification 채널

바이너리에서 발견된 알림 이름들:
```
VLCMediaPlayerTimeChangedNotification
VLCMediaPlayerStateChangedNotification
VLCMediaPlayerVolumeChangedNotification
VLCMediaPlayerTitleSelectionChangedNotification
VLCMediaPlayerTitleListChangedNotification
VLCMediaPlayerChapterChangedNotification
VLCMediaPlayerSnapshotTakenNotification
```
- 이 NSNotification들은 메인 스레드에서 post될 가능성이 높음
- NotificationCenter.default의 관찰자가 메인 스레드에서 호출됨

### 해법 목록

| 해법 | 효과 | 난이도 | 위험도 |
|------|------|--------|--------|
| **A. canDrawSubviewsIntoLayer 제거** | CA 트리 연산 감소 | 낮음 | 낮음 |
| **B. VLCMediaPlayer.timeChangeUpdateInterval 조정** | 타이머 빈도 감소 | 낮음 | 낮음 |
| **C. 비활성 스트림 자막 비활성화** | SPU 메인 dispatch 제거 | 낮음 | 없음 |
| **D. delegate를 nil 설정 (비활성 스트림)** | 모든 delegate 콜백 차단 | 중간 | 중간 |
| **E. VLCVideoLayer (CALayer) 사용** | 뷰 계층 단순화 | 중간 | 중간 |
| **F. libvlc_video_set_callbacks (vmem)** | 완전한 커스텀 렌더링 | 높음 | 높음 |

#### 해법 A: canDrawSubviewsIntoLayer 제거 (즉시 적용 가능)

```swift
// 변경 전 (현재)
canDrawSubviewsIntoLayer = true

// 변경 후
canDrawSubviewsIntoLayer = false
```

**이유**: VLCSampleBufferDisplay가 내부적으로 `VLCSampleBufferDisplayView`(AVSampleBufferDisplayLayer 포함)와 `VLCSampleBufferSubpictureView`를 서브뷰로 추가한다. `canDrawSubviewsIntoLayer = true`는 이 서브뷰들의 렌더링을 부모 레이어에 통합하려 시도하지만, AVSampleBufferDisplayLayer는 이 메커니즘과 무관한 GPU 기반 렌더링을 사용하므로 불필요한 CA 트리 계산만 유발한다.

#### 해법 B: timeChangeUpdateInterval 조정

```swift
// VLCMediaPlayer의 시간 변경 업데이트 간격을 늘려 타이머 빈도 감소
player.timeChangeUpdateInterval = 1.0  // 기본값보다 길게 (예: 1초)
```

**이유**: VLCKit 4.0의 `VLCMediaPlayer`는 `_timeChangeUpdateTimer`(NSTimer)를 사용하여 주기적으로 시간을 갱신한다. 멀티라이브에서 시간 표시가 불필요한 스트림은 이 간격을 최대한 늘리거나, `onTimeChange = nil`과 함께 사용하면 내부 타이머의 메인 스레드 부하도 줄일 수 있다.

#### 해법 C: 자막 비활성화

```swift
// 멀티라이브 배경 스트림:
media.addOption(":no-spu")  // 자막 처리 완전 비활성화
```

**이유**: VLCSampleBufferDisplay의 `RenderSubpicture`는 자막이 변경될 때마다 `dispatch_async(dispatch_get_main_queue())`를 호출한다:
```objc
static void RenderSubpicture(vout_display_t *vd, const vlc_render_subpicture *spu) {
    if (!IsSubpictureDrawNeeded(vd, spu)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [sys.spuView drawSubpicture:sys.subpicture]; // drawRect → 메인 스레드
    });
}
```
라이브 스트림에서 자막이 있는 경우 (채팅 오버레이 등), 이 dispatch가 빈번하게 발생한다.

#### 해법 D: 비활성 스트림의 delegate 비활성화

```swift
// 멀티라이브에서 포커스되지 않은 스트림:
player.delegate = nil  // 모든 VLCMediaPlayerDelegate 콜백 차단
// 필요 시 다시 설정
player.delegate = self
```

**주의**: 상태 변경을 감지하지 못하므로, 에러 복구 로직이 작동하지 않을 수 있다. 대안으로 `mediaPlayerTimeChanged`만 선택적으로 무시하는 현재 방식(`onTimeChange = nil`)이 더 안전하다.

#### 해법 E: VLCVideoLayer (CALayer) 직접 사용

```swift
// NSView 대신 CALayer를 직접 drawable로 사용
let videoLayer = VLCVideoLayer()
hostView.layer?.addSublayer(videoLayer)
player.drawable = videoLayer  // 또는 player.setVideoLayer(videoLayer)
```

**가능한 이점**:
- NSView 계층 제거 → 뷰 이벤트 처리 오버헤드 감소
- CALayer는 NSView보다 경량

**불확실성**: VLCKit 4.0에서 `VLCVideoLayer`가 drawable로 설정될 때 내부적으로 같은 `samplebufferdisplay` 모듈을 사용하는지 추가 확인 필요. VLCVideoLayer.h는 CALayer 서브클래스이며, `hasVideo`와 `fillScreen` 프로퍼티만 노출한다.

---

## 질문 7: 메인 스레드 부하를 줄이기 위한 VLC 4.0 미디어 옵션

### 현재 설정 분석 및 권장 사항

| 카테고리 | 현재 설정 | 권장 변경 | 이유 |
|----------|----------|----------|------|
| **비디오 코덱** | `:codec=videotoolbox,avcodec,all` | 유지 ✅ | VT 우선이 최선 |
| **Zero-copy** | `:videotoolbox-zero-copy=1` | 유지 ✅ | CPU 복사 방지 |
| **프레임 드롭** | `:drop-late-frames=1` | 유지 ✅ | 늦은 프레임 스킵 |
| **프레임 스킵** | `:skip-frames=1` | 유지 ✅ | 디코딩 부하 감소 |
| **루프 필터** | `:avcodec-skiploopfilter=2` (normal)~`4` (bg) | 유지 ✅ | SW 폴백 시 성능 |
| **스레드** | `:avcodec-threads=0`~`3` | 유지 ✅ | 프로필별 적절 |
| **자막** | (설정 없음) | `:no-spu` 추가 ⭐ | 메인 큐 dispatch 제거 |
| **시간 업데이트** | (기본값) | `timeChangeUpdateInterval` 증가 ⭐ | 타이머 빈도 감소 |
| **vout** | (설정 없음 → samplebufferdisplay) | 유지 ✅ | 최적 모듈 |

### 멀티라이브 배경 스트림에 추가 권장되는 옵션

```swift
// 1. 자막 처리 비활성화 — RenderSubpicture의 메인 큐 dispatch 제거
media.addOption(":no-spu")

// 2. OSD 비활성화 — 추가적인 메인 큐 드로잉 방지
media.addOption(":no-osd")

// 3. 비디오 필터 비활성화 — GPU/CPU 후처리 부하 제거
media.addOption(":no-video-filter")

// 4. 스냅샷 비활성화 — 불필요한 메모리 할당 방지
media.addOption(":no-snapshot-preview")
```

---

## 종합 결론

### 핵심 발견 (이전 분석 정정)

| 항목 | 이전 가설 | 실제 동작 (소스 검증) |
|------|----------|---------------------|
| 프레임 렌더링 | 매 프레임 메인 큐 dispatch | **VLC 스레드에서 직접 enqueueSampleBuffer** |
| prepareDisplay | 매 프레임 호출마다 메인 큐 | **1회 초기화 후 즉시 리턴 (no-op)** |
| 120 blocks/sec 원인 | vout의 per-frame dispatch | **VLCKit delegate + NSTimer + CA 합성** |
| 최적 vout 모듈 | caopengllayer가 대안 | **samplebufferdisplay가 최선 (GPU zero-copy 경로)** |

### 메인 스레드 부하의 실제 구성 (추정)

```
메인 스레드 부하 분해:
├─ VLCMediaPlayer 내부 NSTimer × 4        : ~15-20% (시간 폴링)
├─ VLCMediaPlayerDelegate 콜백 dispatch × 4 : ~10-15% (상태/시간/길이)
├─ CoreAnimation 레이어 합성 × 4             : ~20-30% (4개 AVSampleBufferDisplayLayer)
├─ CA 트랜잭션 커밋                          : ~10-15%
├─ VLCKit NSNotification post               : ~5-10%
├─ 자막 렌더링 dispatch (있는 경우)           : ~5-15%
└─ AppKit 뷰 이벤트 처리                     : ~5-10%
```

### 우선순위별 최적화 액션

1. **즉시 적용**: `canDrawSubviewsIntoLayer = false` + `:no-spu` + `:no-osd`
2. **단기**: `timeChangeUpdateInterval` 증가 + 비활성 스트림 delegate 최소화
3. **중기**: `VLCVideoLayer` (CALayer) 기반 drawable 전환 테스트
4. **장기**: `libvlc_video_set_callbacks` (vmem) 기반 Metal 렌더링 파이프라인 (최대 유연성, 최대 개발비용)

### 실험 권장 사항

메인 스레드 병목의 정확한 비율을 확인하려면 **Instruments의 Time Profiler**를 사용하여:
1. 4-stream 재생 중 메인 스레드의 호출 스택 샘플링
2. `dispatch_async` 블록의 출처 추적
3. CoreAnimation 커밋 빈도 측정 (`CA::Transaction::commit()`)
4. NSTimer 콜백 빈도 측정

이를 통해 위 추정 비율을 실측값으로 대체하고, 가장 효과적인 최적화 대상을 정량적으로 선정할 수 있다.
