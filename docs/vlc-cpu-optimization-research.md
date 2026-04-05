# VLC 디코딩 CPU 사용률 최적화 연구 분석

> 작성일: 2025-07-15  
> 대상: CView_v2 — VLCKit 4.0 기반 HLS 라이브 스트리밍 플레이어  
> 환경: Apple M1 Max (10코어), macOS 26.5, VLC 4.0.0-dev (`b98c94076b`)

---

## 목차

1. [현황 분석](#1-현황-분석)
2. [CPU 프로파일링 결과](#2-cpu-프로파일링-결과)
3. [현재 VLC 미디어 옵션 정리](#3-현재-vlc-미디어-옵션-정리)
4. [최적화 방안](#4-최적화-방안)
   - 4.1 [avcodec-skiploopfilter — 디블로킹 필터 스킵](#41-avcodec-skiploopfilter--디블로킹-필터-스킵)
   - 4.2 [avcodec-skip-frame — 프레임 타입별 디코딩 스킵](#42-avcodec-skip-frame--프레임-타입별-디코딩-스킵)
   - 4.3 [디코더 스레드 최적화](#43-디코더-스레드-최적화)
   - 4.4 [해상도 기반 CPU 절감](#44-해상도-기반-cpu-절감)
   - 4.5 [프리패치 버퍼 크기 튜닝](#45-프리패치-버퍼-크기-튜닝)
   - 4.6 [클럭 복구 파라미터 최적화](#46-클럭-복구-파라미터-최적화)
   - 4.7 [VLCLayerHostView 렌더링 경로 최적화](#47-vlclayerhostview-렌더링-경로-최적화)
   - 4.8 [통계 수집 타이머 주기 조정](#48-통계-수집-타이머-주기-조정)
   - 4.9 [비활성 세션 비디오 트랙 비활성화](#49-비활성-세션-비디오-트랙-비활성화)
   - 4.10 [AVPlayer 엔진 대체 전략](#410-avplayer-엔진-대체-전략)
5. [멀티라이브 특화 최적화](#5-멀티라이브-특화-최적화)
6. [실행 우선순위 매트릭스](#6-실행-우선순위-매트릭스)
7. [위험도 분석](#7-위험도-분석)

---

## 1. 현황 분석

### 1.1 아키텍처 개요

```
CDN (치지직 HLS) 
  → LocalStreamProxy (HTTP 리버스 프록시, M3U8 캐싱)
    → VLCKit 4.0 (HLS 디먹싱 → VideoToolbox HW 디코딩 → VLCSampleBufferDisplay 렌더링)
      → VLCLayerHostView (NSView, Metal 서브레이어)
        → SwiftUI PlayerView
```

### 1.2 스트리밍 프로파일

| 프로파일 | 용도 | 네트워크 캐시 | 디코더 스레드 | 해상도 제한 |
|---------|------|-------------|-------------|-----------|
| **ultraLow** | 최저지연 (유선) | 300ms | min(CPU코어, 4) | 1920×1080 |
| **lowLatency** | 저지연 기본 | 500ms | min(CPU코어, 4) | 1920×1080 |
| **multiLive** | 멀티라이브 | 1000ms | 1 | 1280×720 (비선택) / 1920×1080 (선택) |

### 1.3 하드웨어 디코딩 상태

- **VideoToolbox**: 런타임 프로파일링에서 `VTDecompressionSessionDecodeFrameWithOptions` 확인 → **활성**
- **비디오 출력**: `VLCSampleBufferDisplay` (Metal 기반 `AVSampleBufferDisplayLayer`)
- **코덱 우선순위**: `:codec=videotoolbox,avcodec` — HW 우선, SW 폴백

---

## 2. CPU 프로파일링 결과

### 2.1 단일 스트림 재생 시 (1080p HLS 라이브)

| 구성 요소 | CPU 비중 | 주요 핫스팟 |
|----------|---------|-----------|
| **VLC 내부** | ~60% | `video_output.c`, `decoder.c`, `VLCSampleBufferDisplay.m` (라인 884, 1037) |
| **SwiftUI** | ~35% | 레이아웃 계산, 접근성 트리 |
| **앱 코드** | ~5% | `LocalStreamProxy`, `ChatEngine` (미미) |

### 2.2 총 CPU 사용률

- **유휴 상태** (스트림 없음): 20-27%
- **단일 스트림 재생**: 22-35%
- **멀티라이브** (4스트림): 측정 필요 (예상 50-70%)

### 2.3 핵심 발견

1. **VideoToolbox가 이미 활성** — H.264 디코딩 자체는 GPU에서 수행됨
2. **VLC CPU 소비의 주체는 디코딩이 아닌 비디오 출력 파이프라인** — `video_output.c`, `VLCSampleBufferDisplay.m`
3. VLC 내부 `decoder.c`의 CPU 사용은 HW 디코딩 오케스트레이션 (프레임 수신, 타임스탬프 관리, 큐잉)
4. SwiftUI 레이아웃/접근성이 예상 이상의 CPU를 소비 (별도 최적화 영역)

---

## 3. 현재 VLC 미디어 옵션 정리

`VLCPlayerEngine+Playback.swift` → `applyMediaOptions(_:profile:)` 기준:

### 3.1 캐싱/버퍼

| 옵션 | ultraLow | lowLatency | multiLive | 설명 |
|-----|---------|-----------|----------|-----|
| `network-caching` | 300 | 500 | 1000 | 네트워크 버퍼 (ms) |
| `live-caching` | 300 | 500 | 1000 | 라이브 캐싱 (ms) |
| `file-caching` | 0 | 0 | 0 | 파일 캐시 비활성 |
| `disc-caching` | 0 | 0 | 0 | 디스크 캐시 비활성 |
| `prefetch-buffer-size` | 393216 | 393216 | 786432 | 프리패치 버퍼 (바이트) |

### 3.2 디코딩

| 옵션 | ultraLow | lowLatency | multiLive | 설명 |
|-----|---------|-----------|----------|-----|
| `codec` | videotoolbox,avcodec | 동일 | 동일 | HW 우선 |
| `avcodec-hw` | videotoolbox | 동일 | 동일 | HW 가속 지정 |
| `avcodec-threads` | 4 | 4 | 1 | 디코더 스레드 |
| `avcodec-fast` | 1 | 1 | 1 | 비표준 고속 디코딩 |
| `avcodec-hurry-up` | 1 | 1 | 1 | 지연 시 프레임 스킵 |
| `avcodec-skip-idct` | — | — | 4 (전체) | IDCT 스킵 (multiLive) |
| `drop-late-frames` | 1 | 1 | 1 | 늦은 프레임 드롭 |
| `skip-frames` | 1 | 1 | 1 | 참조 안 되는 프레임 스킵 |

### 3.3 후처리/동기화

| 옵션 | 값 | 설명 |
|-----|---|-----|
| `deinterlace` | 0 | 디인터레이스 비활성 |
| `postproc-q` | 0 | 후처리 비활성 |
| `clock-synchro` | 0 | 클럭 동기화 비활성 |
| `clock-jitter` | 0/5000/10000 µs | 프로파일별 클럭 지터 허용 |
| `cr-average` | 20/30/30 ms | 클럭 복구 평균화 기간 |

### 3.4 미설정 주요 옵션 (최적화 후보)

| 옵션 | 현재 | 잠재적 값 | 기대 효과 |
|-----|-----|---------|---------|
| **`avcodec-skiploopfilter`** | 미설정 (0=None) | 3 또는 4 | **디블로킹 필터 CPU 절감** |
| **`avcodec-skip-frame`** | 미설정 (0=Default) | 1 (B프레임) | **B프레임 디코딩 스킵** |
| `avcodec-dr` | 미설정 (기본 활성) | 확인 필요 | Direct Rendering |
| `avcodec-corrupted` | 미설정 (기본 활성) | — | 깨진 프레임 표시 여부 |

---

## 4. 최적화 방안

### 4.1 avcodec-skiploopfilter — 디블로킹 필터 스킵

#### 개요
H.264 디코딩의 루프 필터(디블로킹 필터)는 매크로블록 경계의 블록화 현상을 제거하는 후처리 단계다. HD 스트림에서 상당한 CPU를 소비하며, 스킵 시 눈에 띄는 화질 차이가 최소화될 수 있다.

#### VLC 옵션 스펙
```
avcodec-skiploopfilter {0, 1, 2, 3, 4}
  0 = None (기본값, 모든 프레임에 적용)
  1 = Non-ref (참조되지 않는 프레임만 스킵)
  2 = Bidir (양방향 프레임 스킵)
  3 = Non-key (키프레임 외 모두 스킵)
  4 = All (전체 프레임 스킵)
```

#### 적용 방안

| 시나리오 | 권장 값 | 근거 |
|---------|--------|-----|
| **단일 스트림** (ultra/low) | `1` (Non-ref) | 화질 영향 최소, 참조 안 되는 프레임만 스킵 |
| **멀티라이브** (multiLive) | `3` (Non-key) 또는 `4` (All) | 이미 720p+skip-idct=4 적용 중, 화질보다 성능 우선 |

#### 예상 효과
- **CPU 절감**: HW 디코딩 환경에서 5-15% (루프필터가 SW에서 실행되는 경우)
- **주의**: VideoToolbox HW 디코딩 시 루프필터도 HW에서 처리될 수 있음 → **실제 측정 필수**
- H.264 high profile의 경우 루프필터 CPU 비중이 더 큼

#### 구현 코드
```swift
// applyMediaOptions() 에 추가
if profile == .multiLive {
    media.addOption(":avcodec-skiploopfilter=3")  // Non-key 스킵
} else {
    media.addOption(":avcodec-skiploopfilter=1")  // Non-ref만 스킵
}
```

#### 검증 포인트
- [ ] `skiploopfilter=1` 적용 후 단일 스트림 CPU delta 측정
- [ ] `skiploopfilter=3` 적용 후 멀티라이브 CPU delta 측정
- [ ] VideoToolbox 활성 시 실제로 SW 루프필터가 동작하는지 확인 (효과 없을 수 있음)
- [ ] 블록화 아티팩트 시각적 평가 (특히 빠른 움직임 장면)

---

### 4.2 avcodec-skip-frame — 프레임 타입별 디코딩 스킵

#### 개요
디코더에게 특정 프레임 타입의 디코딩 자체를 건너뛰도록 지시한다. `skip-frames`(늦은 프레임 드롭)와 다르게, 아예 디코딩하지 않으므로 CPU 절감이 크지만, 프레임 손실이 눈에 보인다.

#### VLC 옵션 스펙
```
avcodec-skip-frame {-1, 0, 1, 2, 3, 4}
  -1 = None (아무것도 스킵 안 함)
   0 = Default (코덱 기본 동작)
   1 = B-frames (B프레임 스킵)
   2 = P-frames (P프레임 스킵)
   3 = B+P frames
   4 = All frames (모든 프레임 스킵)
```

#### 적용 방안

| 시나리오 | 권장 값 | 근거 |
|---------|--------|-----|
| **단일 스트림** | `0` (Default) | B프레임 스킵 시 눈에 띄는 끊김, 부적절 |
| **멀티라이브 비선택 세션** | `1` (B-frames) | 그리드에서 작게 표시되므로 B프레임 누락 체감 적음 |

#### 예상 효과
- **CPU 절감**: B프레임 스킵 시 디코더 부하 ~20-30% 감소 (B프레임 비율에 따라)
- **화질 영향**: 움직임 부드러움 감소 (FPS 저하 느낌)
- **주의**: 치지직 라이브 인코딩 프로파일이 B프레임을 사용하는지 확인 필요 (LL-HLS는 일반적으로 B프레임 비활성)

#### 핵심 검토: LL-HLS와 B프레임
치지직의 LL-HLS 스트림이 B프레임을 사용하지 않는다면, 이 옵션은 **효과가 없다**. 저지연 HLS 인코딩은 일반적으로 `bframes=0`으로 설정되므로, 적용 전 실제 스트림의 B프레임 존재 여부를 VLC 통계 또는 ffprobe로 확인해야 한다.

```bash
# 스트림 B프레임 확인 (ffprobe)
ffprobe -select_streams v:0 -show_frames -show_entries frame=pict_type \
  "http://localhost:PORT/proxy_url" 2>/dev/null | grep pict_type | sort | uniq -c
```

---

### 4.3 디코더 스레드 최적화

#### 현재 설정
- `ultraLow` / `lowLatency`: `min(processorCount, 4)` = M1 Max에서 **4**
- `multiLive`: **1**

#### 분석

**VideoToolbox 활성 시 avcodec-threads의 역할**

VideoToolbox가 활성화되면 실제 H.264/HEVC 디코딩은 GPU의 전용 미디어 엔진에서 수행된다. `avcodec-threads`는 **sw fallback 시의 스레드 수**이며, HW 디코딩 경로에서는 직접적인 영향이 제한적이다.

그러나 VLC 4.0의 내부 파이프라인에서:
1. demux 스레드: HLS 세그먼트 다운로드/파싱
2. decoder 스레드: VideoToolbox에 프레임 전달 + 디코딩 결과 수신
3. vout 스레드: `VLCSampleBufferDisplay`로 프레임 전달

이 중 `avcodec-threads`는 (2)에 영향을 미치지만, VideoToolbox 모듈은 자체적으로 비동기 처리하므로 실질적 효과는 미미할 수 있다.

#### 권장 사항
- **현행 유지** (변경 불필요): HW 디코딩 시 스레드 수는 VLC 파이프라인 오버헤드에만 영향
- multiLive의 1스레드 설정은 **적절** — 다수 세션 간 스레드 경합 방지

#### 조건부 실험
```swift
// 실험: multiLive 스레드를 0(auto)으로 변경하여 VLC가 최적값 선택하도록
// 현재 1 → 0 변경 시 VLC 내부 휴리스틱이 코어 수 기반으로 결정
// 멀티라이브 4세션 × auto 스레드 → CPU 스파이크 가능성 있으므로 신중히 테스트
```

---

### 4.4 해상도 기반 CPU 절감

#### 현재 설정

| 프로파일 | 선택 세션 | 비선택 세션 |
|---------|----------|-----------|
| ultraLow/lowLatency | 1920×1080 | — |
| multiLive | 1920×1080 | 1280×720 |

#### 최적화 방안

**방안 A: 멀티라이브 비선택 세션 해상도 추가 하향**

```
1280×720 → 854×480
```

- **기대 효과**: 픽셀 수 64% 감소 → 디코딩/렌더링 부하 비례 감소
- **적용 조건**: 그리드 셀 크기가 480p 이하일 때 (4분할 이상)
- **위험**: 선택 전환 시 해상도 업스위칭 지연 (HLS manifest 재요청)

```swift
// 동적 해상도 결정 — 그리드 셀 크기 기반
func adaptiveMaxHeight(isSelected: Bool, cellHeight: CGFloat? = nil) -> Int {
    switch self {
    case .ultraLow, .lowLatency: return 1080
    case .multiLive:
        if isSelected { return 1080 }
        if let h = cellHeight, h < 360 { return 480 }  // 작은 셀은 480p
        return 720
    }
}
```

**방안 B: 단일 스트림 해상도 동적 제한**

CPU 부하 임계 시 자동으로 720p로 하향:
- 현재 `StreamCoordinator`의 ABR이 대역폭 기반 화질 조절을 수행 중
- CPU 기반 화질 하향 로직 추가 가능 (단, 사용자 경험 저하 고려)

---

### 4.5 프리패치 버퍼 크기 튜닝

#### 현재 설정
- `ultraLow` / `lowLatency`: 393,216 bytes (384KB)
- `multiLive`: 786,432 bytes (768KB)

#### 분석

프리패치 버퍼는 VLC의 demux 레이어에서 데이터를 미리 읽어두는 메모리 영역이다. 크기가 클수록:
- **장점**: 네트워크 지터 흡수, 리버퍼링 감소
- **단점**: 메모리 사용 증가, 초기 재생 지연 약간 증가

CPU 사용률에 대한 **직접적 영향은 미미**하다. 프리패치 자체는 I/O 바운드 작업이며, CPU 바운드가 아니다.

#### 권장 사항
- **현행 유지**: CPU 최적화 관점에서 우선순위 낮음
- 메모리 최적화가 필요한 경우 multiLive의 768KB → 512KB 축소 고려

---

### 4.6 클럭 복구 파라미터 최적화

#### 현재 설정

| 파라미터 | ultraLow | lowLatency | multiLive |
|---------|---------|-----------|----------|
| `cr-average` | 20ms | 30ms | 30ms |
| `clock-jitter` | 0µs | 5000µs | 10000µs |
| `clock-synchro` | 0 | 0 | 0 |

#### 분석

클럭 복구는 VLC의 타이밍 서브시스템으로, A/V 동기화를 위한 PTS/DTS 보정을 담당한다. CPU 프로파일링에서 클럭 관련 코드의 CPU 점유율은 **무시할 수준**이었다.

- `cr-average`를 줄이면 클럭 보정이 더 민감해지지만, CPU 변화 없음
- `clock-jitter`를 늘리면 드롭 프레임 감소 가능하지만, 동기화 정밀도 저하

#### 권장 사항
- **현행 유지**: CPU 최적화 효과 없음, 현재 설정이 A/V 동기화에 적절

---

### 4.7 VLCLayerHostView 렌더링 경로 최적화

#### 현재 구성

```swift
// VLCLayerHostView 설정
wantsLayer = true
canDrawSubviewsIntoLayer = false
layerContentsRedrawPolicy = .never
layer.isOpaque = true
layer.drawsAsynchronously = false    // GPU 이중 합성 방지
layer.allowsGroupOpacity = false
// 모든 CALayer 암시적 애니메이션 비활성화
layer.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), ...]
```

#### 분석

현재 설정은 이미 잘 최적화되어 있다:
- `drawsAsynchronously = false`: VLC Metal 서브레이어와의 이중 합성 방지 ✓
- `allowsGroupOpacity = false`: 불필요한 오프스크린 렌더 패스 방지 ✓
- `layerContentsRedrawPolicy = .never`: 불필요한 재드로잉 방지 ✓
- CALayer 액션 비활성화: 암시적 애니메이션 CPU 오버헤드 제거 ✓

#### 추가 최적화 후보

**A. `canDrawSubviewsIntoLayer = true` 고려**

현재 `false`인데, VLC가 자체 서브레이어를 추가하므로 `true`로 변경 시 VLC 렌더링에 간섭할 수 있다. **변경하면 안 됨**.

**B. 멀티라이브 비활성 세션의 프레임 레이트 제한**

VLC 자체에는 vout 프레임 레이트 제한 옵션이 없지만, `CVDisplayLink` 기반 렌더링을 사용하므로 디스플레이 주사율에 동기화된다. 비활성 세션은 어차피 화면에 보이지 않으면 렌더링 부하가 자동으로 줄어든다.

#### 권장 사항
- **현행 유지**: 이미 최적 설정
- 멀티라이브 비활성 세션이 뷰 히어라키에 남아 있을 경우, 비디오 트랙 비활성화(4.9)가 더 효과적

---

### 4.8 통계 수집 타이머 주기 조정

#### 현재 설정
- 일반 스트림: 3초 간격
- 멀티라이브: 10초 간격

#### 분석

`collectMetrics()`는 `VLCMedia.Statistics`에서 delta 기반으로 프레임/오디오/네트워크 통계를 수집한다. VLC statistics API 호출 자체는 경량이지만:

- 3초 타이머가 `Task.sleep` 기반 → GCD 오버헤드 최소
- 수집 로직이 `@MainActor`에서 실행 → 메인 스레드 점유 미미

#### 권장 사항
- **현행 유지**: CPU 영향 무시할 수준
- 멀티라이브 10초는 이미 절충된 값

---

### 4.9 비활성 세션 비디오 트랙 비활성화

#### 개요

멀티라이브에서 사용자가 볼 수 없는 세션(최소화, 스크롤 아웃 등)의 비디오 디코딩을 완전히 중단하는 방안이다.

#### 현재 구현

`VLCPlayerEngine+Features.swift`에 이미 `setVideoTrackEnabled(_:)` / `setTimeUpdateMode(background:)` 메서드가 구현되어 있다:

```swift
// 이미 구현됨:
func setVideoTrackEnabled(_ enabled: Bool)     // 비디오 트랙 선택/해제
func setTimeUpdateMode(background: Bool)       // 백그라운드 시 오디오도 해제
```

#### 최적화 방안

**완전 비가시 세션 감지 + 자동 비활성화:**

```swift
// 개념 코드 — 뷰 가시성 기반 자동 트랙 관리
func onVisibilityChanged(isVisible: Bool) {
    if isVisible {
        engine.setVideoTrackEnabled(true)
    } else {
        engine.setVideoTrackEnabled(false)  // 비디오 디코딩 중단
        // 오디오는 유지 (비가시여도 소리는 들릴 수 있음)
    }
}
```

#### 예상 효과
- **CPU 절감**: 비가시 세션 1개당 VideoToolbox 디코딩 + vout 렌더링 완전 제거
- **가장 효과적인 멀티라이브 최적화** — 디코딩 자체를 중단하므로 모든 CPU 비용 제거
- **위험**: 재활성화 시 키프레임 대기 → 0.5-2초 블랙 스크린

---

### 4.10 AVPlayer 엔진 대체 전략

#### 현재 상태

프로젝트에 `AVPlayerEngine`이 이미 구현되어 있으며, `MultiLiveEnginePool`이 VLC/AVPlayer를 타입별로 관리한다.

#### 장점
- **macOS 네이티브 최적화**: AVFoundation은 Apple의 미디어 파이프라인에 깊이 통합
- **효율적 HW 디코딩**: VideoToolbox를 직접 사용하지 않고 AVFoundation이 최적 경로 선택
- **전력 효율**: 시스템 수준 전력 관리 통합
- **HLS 네이티브 지원**: Apple의 HLS 구현은 LL-HLS 최적화 포함

#### 단점
- **제어 제한**: VLC만큼 세밀한 디코딩 옵션 불가
- **LL-HLS 구현 차이**: Apple의 LL-HLS와 치지직 CDN 호환성 검증 필요
- **LocalStreamProxy 통합**: 현재 VLC 전용으로 최적화된 프록시와의 호환성

#### 권장 사항
- **멀티라이브 비선택 세션에 AVPlayer 사용 검토**: CPU 효율이 높을 가능성
- **LL-HLS 호환성 검증 후** 단계적 전환 고려
- 현재는 VLC 최적화에 집중하고, 장기 과제로 AVPlayer 전환 평가

---

## 5. 멀티라이브 특화 최적화

멀티라이브는 동시에 여러 스트림을 재생하므로, 최적화 효과가 세션 수에 비례하여 증폭된다.

### 5.1 현재 멀티라이브 설정 (요약)

| 항목 | 설정 |
|-----|-----|
| 디코더 스레드 | 1 |
| 해상도 (비선택) | 1280×720 |
| 해상도 (선택) | 1920×1080 |
| skip-idct | 4 (전체) |
| 네트워크 캐시 | 1000ms |
| 통계 수집 | 10초 |
| 프리패치 버퍼 | 768KB |

### 5.2 추가 적용 가능한 옵션 조합

```swift
// 멀티라이브 비선택 세션 — 최대 CPU 절감 프로필
if profile == .multiLive && !isSelectedSession {
    media.addOption(":avcodec-skiploopfilter=4")  // 전체 루프필터 스킵
    media.addOption(":avcodec-skip-frame=1")      // B프레임 스킵
    media.addOption(":avcodec-skip-idct=4")       // 전체 IDCT 스킵
    // 해상도: 854×480 (셀 크기 < 360pt 시)
}
```

### 5.3 엔진 풀 워밍업 최적화

현재 `MultiLiveEnginePool`의 `warmup()`이 미리 엔진을 생성하는데, 초기 생성 시의 VLC 인스턴스 초기화 비용(~100-200ms)을 분산하여 전환 시 스파이크를 방지한다. 이는 CPU **피크** 최적화에 기여한다.

---

## 6. 실행 우선순위 매트릭스

| 우선순위 | 방안 | 예상 CPU 절감 | 구현 난이도 | 화질 영향 | 비고 |
|---------|-----|-------------|-----------|---------|-----|
| 🟢 **1** | 4.9 비활성 세션 비디오 트랙 비활성화 | **높음** (세션당 전체 제거) | 낮음 | 재활성화 지연 | 기존 API 활용 |
| 🟢 **2** | 4.1 skiploopfilter (멀티라이브) | **중간** (5-15%) | 매우 낮음 | 블록화 약간 | 1줄 추가 |
| 🟡 **3** | 4.4 해상도 하향 (비선택→480p) | **중간** (픽셀 64%↓) | 낮음 | 해상도 저하 | 조건부 적용 |
| 🟡 **4** | 4.1 skiploopfilter (단일) | **낮-중** (VT 의존) | 매우 낮음 | 미미 | 측정 후 결정 |
| 🟡 **5** | 4.2 skip-frame=1 (비선택) | **낮-중** (B프레임 의존) | 매우 낮음 | FPS 저하 | B프레임 존재 확인 필요 |
| 🔵 **6** | 4.10 AVPlayer 대체 | **높음** (잠재적) | 높음 | 검증 필요 | 장기 과제 |
| ⚪ **7** | 4.3 스레드 튜닝 | **미미** | 낮음 | 없음 | HW 디코딩 시 효과 제한 |
| ⚪ **8** | 4.5-4.8 기타 | **없음~미미** | 낮음 | 없음 | 현행 유지 |

---

## 7. 위험도 분석

### 7.1 VideoToolbox와의 상호작용 불확실성

가장 중요한 변수는 **VLC의 avcodec 옵션들이 VideoToolbox HW 디코딩 경로에서 실제로 적용되는지** 여부다.

- `skiploopfilter`: VideoToolbox가 디코딩을 수행하면, 루프필터도 HW에서 처리될 가능성이 높아 이 옵션이 무시될 수 있다
- `skip-idct`: 마찬가지로 HW 디코딩 시 IDCT는 GPU 내부에서 수행
- `skip-frame`: 디코더 레벨에서 프레임을 건너뛰는 것은 HW/SW 무관하게 동작할 수 있으나, VLC의 VideoToolbox 모듈 구현에 따라 다름

**⚠️ 핵심 결론**: `avcodec-*` 계열 옵션들은 본래 FFmpeg(libavcodec)의 SW 디코딩 옵션이다. VLC의 VideoToolbox 모듈(`modules/codec/videotoolbox/decoder.c`)이 이들을 어떻게 처리하는지는 VLC 소스 코드 분석 또는 실측 없이는 확정할 수 없다. **모든 방안은 반드시 실측 검증이 필요하다.**

### 7.2 스트림 호환성

- 치지직 CDN의 HLS 스트림 인코딩 프로파일(B프레임 유무, Profile/Level)에 따라 각 옵션의 효과가 달라짐
- 인코딩 설정이 서버측에서 변경되면 최적화 효과가 변동될 수 있음

### 7.3 VLCKit 버전 종속성

- 현재 사용 중인 VLCKit 4.0.0-dev는 공식 릴리즈가 아닌 개발 빌드
- `rursache/VLCKitSPM` (revision `94ca521`)은 서드파티 SPM 래퍼
- VLCKit 업데이트 시 옵션 동작이 변경될 수 있음

### 7.4 리그레션 위험

| 변경 | 리그레션 위험 | 복구 방법 |
|-----|-------------|---------|
| skiploopfilter | 낮음 (값 0으로 복원) | 옵션 제거 |
| skip-frame | 중간 (시각적 끊김) | 옵션 제거 |
| 해상도 하향 | 낮음 (해상도 값 복원) | 상수 변경 |
| 비디오 트랙 비활성화 | 중간 (재활성화 타이밍) | 로직 제거 |
| AVPlayer 전환 | 높음 (전체 재검증) | VLC 폴백 |

---

## 부록: 참고 자료

- VLC avcodec 모듈 문서: https://wiki.videolan.org/Documentation:Modules/avcodec/
- VLCKit SPM: https://github.com/rursache/VLCKitSPM (revision 94ca521)
- VLC 4.0.0-dev 소스: commit `b98c94076b`
- 프로파일링 도구: macOS `sample` (3초 샘플링, PID 74874)
- 현재 코드 위치:
  - `Sources/CViewPlayer/VLCPlayerEngine.swift` — VLCLayerHostView, VLCStreamingProfile
  - `Sources/CViewPlayer/VLCPlayerEngine+Playback.swift` — applyMediaOptions()
  - `Sources/CViewPlayer/VLCPlayerEngine+Features.swift` — 통계/재사용/트랙 관리
  - `Sources/CViewPlayer/MultiLiveEnginePool.swift` — 엔진 풀
  - `Sources/CViewPlayer/PlayerConstants.swift` — 상수
