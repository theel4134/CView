# 치지직 웹 플레이어 재생 위치 동기화 연구 문서

> 작성일: 2026-02-20  
> 대상 프로젝트: CView_v2  
> 목표: 네이티브 앱의 라이브 재생 위치를 치지직 웹 플레이어(hls.js)와 동일하게 맞추기

---

## 1. 문제 정의

사용자가 치지직 웹사이트와 CView_v2 앱을 동시에 시청할 때 재생 위치(라이브 엣지와의 갭)가 다르게 나타난다.

| 구분 | 재생 엔진 | 기본 레이턴시 | 
|---|---|---|
| 치지직 웹 | hls.js | **6~9초** (3 × targetDuration) |
| CView_v2 | VLC (libvlc) | **8~20초** (network-caching + 버퍼) |

이 차이는 두 플레이어의 **버퍼 전략**이 근본적으로 다르기 때문이다.

---

## 2. 치지직 HLS 스트림 구조 분석

### 2-1. 마스터 플레이리스트 구조

```
치지직 CDN: https://ex-nlive-streaming.navercdn.com/...
```

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="avc1.640032,mp4a.40.2",NAME="1080p"
chunklist_1080p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=60,CODECS="avc1.64001f,mp4a.40.2",NAME="720p"
chunklist_720p.m3u8
...
```

### 2-2. 미디어 플레이리스트 구조 (핵심)

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:12345678

#EXT-X-PROGRAM-DATE-TIME:2026-02-20T12:00:00.000+09:00   ← 핵심 태그
#EXTINF:2.000,
segment_12345678.ts

#EXTINF:2.000,
segment_12345679.ts

#EXTINF:2.000,
segment_12345680.ts   ← 라이브 엣지 세그먼트
```

### 2-3. `#EXT-X-PROGRAM-DATE-TIME` (PDT) 태그의 역할

**PDT 태그는 세그먼트의 시작 시각을 UTC로 명시한다.** 이것이 웹 플레이어와 동기화하는 핵심 메커니즘이다.

```
세그먼트 N 시작 UTC시각 = PDT + Σ(이전 세그먼트 duration)
라이브 엣지 UTC = PDT(마지막 세그먼트) + 마지막 세그먼트 duration
실제 레이턴시 = UTC.now() - 라이브 엣지 UTC
```

> ✅ **현재 CView_v2의 `HLSManifestParser`는 이미 `programDateTime`을 파싱한다.**  
> (`MediaPlaylist.Segment.programDateTime: Date?` 필드 존재)

---

## 3. 웹 플레이어(hls.js) 동작 방식

### 3-1. 기본 레이턴시 계산

hls.js는 항상 **라이브 엣지로부터 `targetLatency`만큼 뒤에서 재생**한다:

```
targetLatency = max(holdBack, 3 × targetDuration)
```

치지직의 `targetDuration = 2초`이므로:

```
기본 targetLatency = 3 × 2초 = 6초
```

**즉, 웹 플레이어는 실제 방송 시각보다 항상 6초 뒤를 재생한다.**

### 3-2. Low-Latency 모드 (일부 스트림)

치지직이 LL-HLS(`#EXT-X-PART-INF`)를 지원하는 경우:

```
LL-HLS targetLatency = 3 × partTargetDuration (≈ 0.5~1.5초)
```

현재 치지직 대부분 스트림은 표준 HLS를 사용한다.

---

## 4. 현재 CView_v2의 레이턴시 측정 방식 분석

### 4-1. 현재 방식 (VLC 버퍼 기반)

```swift
// StreamCoordinator.swift - startLowLatencySync()
await controller.startSync { [weak self] in
    let duration = engine.duration   // VLC가 다운로드한 버퍼의 끝
    let current = engine.currentTime // 현재 재생 위치
    let latency = duration - current // 버퍼 내 남은 시간
    return latency
}
```

### 4-2. 문제점

| 항목 | 현재 | 문제 |
|---|---|---|
| `duration` | VLC 버퍼 끝 시각 | ≠ 실제 라이브 엣지 시각 |
| `currentTime` | VLC 재생 커서 | VLC 기본 network-caching으로 지연 |
| `latency` 계산 | `duration - currentTime` | 실제 방송과의 차이 반영 안 됨 |

VLC는 기본적으로 최소 1,500ms(livecaching) 이상의 버퍼를 사전에 다운로드한다.  
따라서 `duration`이 이미 실제 라이브 엣지보다 1~3초 **뒤처진다.**

### 4-3. `LowLatencyController` 목표 레이턴시

```swift
// LowLatencyController.Configuration.default
targetLatency: 3.0,    // ← 설정은 3초지만 측정값이 올바르지 않음
maxLatency: 10.0,
catchUpThreshold: 1.5
```

---

## 5. 웹 플레이어와 동기화하는 3가지 방법

---

### 방법 A: PDT 기반 절대 위치 동기화 ⭐ (권장)

**원리**: 미디어 플레이리스트를 직접 폴링하여 PDT에서 실제 레이턴시를 계산하고, 목표 재생 위치로 seek.

#### 구현 흐름

```
1. 플레이백 시작 후 미디어 플레이리스트 폴링 (2~3초 간격)
2. 마지막 세그먼트의 PDT + duration = 라이브 엣지 UTC 계산
3. 실제 레이턴시 = Date.now - 라이브 엣지 UTC
4. 목표 레이턴시(6초)와 차이 계산 → seek 또는 재생속도 조정
```

#### 핵심 코드 추가 위치

**`HLSManifestParser.swift`** — 이미 PDT 파싱 완료:
```swift
// MediaPlaylist.Segment에 programDateTime: Date? 존재
let liveEdge = playlist.segments.last.map { seg in
    (seg.programDateTime ?? Date()).addingTimeInterval(seg.duration)
}
let actualLatency = Date().timeIntervalSince(liveEdge ?? Date())
```

**`StreamCoordinator.swift`** — `startLowLatencySync()` 수정:
```swift
// 기존: VLC duration 기반
let latency = duration - current

// 개선: PDT 기반 절대 레이턴시
let latency = await computePDTLatency(from: playlistURL) ?? (duration - current)
```

**`LowLatencyController.swift`** — targetLatency를 웹과 맞춤:
```swift
// 웹 hls.js 기본값과 동일하게
public static let webCompatible = Configuration(
    targetLatency: 6.0,  // 3 × 2s targetDuration
    maxLatency: 15.0,
    minLatency: 3.0,
    maxPlaybackRate: 1.08,   // 점진적 catchup
    minPlaybackRate: 0.95,
    catchUpThreshold: 2.0,
    slowDownThreshold: 0.5
)
```

#### 장점 / 단점

| 장점 | 단점 |
|---|---|
| 웹 플레이어와 ±0.5초 이내 정확도 가능 | 주기적 HTTP 폴링 필요 (네트워크 부하 미미) |
| PDT는 서버 기준 UTC → 클라이언트 시계 무관 | VLC seek 시 화면 끊김 가능성 |
| 이미 파싱 인프라 완비 | VLC의 seek 지원이 라이브 스트림에서 제한적 |

---

### 방법 B: VLC livecaching 파라미터 최소화 (빠른 개선)

**원리**: VLC의 `--network-caching`과 `--live-caching` 옵션을 웹 플레이어 수준으로 줄임.

#### 현재 VLC 옵션

```swift
// VLCPlayerEngine.swift - configureMediaOptions()
media.addOptions([
    ":network-caching=1500",   // 1.5초
    ":live-caching=1500",      // 1.5초
    ...
])
```

#### 웹 호환 설정

```swift
// 웹 hls.js 기준 ≈ 6~8초 레이턴시에 맞추기 위한 최소 캐싱
":network-caching=500",    // 0.5초 (hls.js의 기본 fragment 프리페치 수준)
":live-caching=1500",      // 1.5초 (VLC 라이브 안정성 최소값)
":clock-jitter=0",
":clock-synchro=0",
```

#### 주의사항

- 캐싱을 너무 줄이면 버퍼링(재생 끊김) 발생
- 네트워크 품질에 따라 동적 조정 필요 (ABRController와 연동)
- **단독으로는 완전한 동기화 불가, 방법 A와 함께 사용**

---

### 방법 C: LivePlaybackDetail.start 기반 시간 오프셋

**원리**: API 응답의 `livePlaybackJSON → live.start`(방송 시작 UTC)를 기반으로 스트림 내 절대 위치를 계산.

#### 현재 `LivePlaybackDetail` 구조
```swift
public struct LivePlaybackDetail: Sendable, Codable, Hashable {
    public let start: String?   // 예: "2026-02-20T12:00:00+09:00" — 방송 시작 시각
    public let open: String?    // 예: "2026-02-20T12:00:05+09:00" — CDN 오픈 시각
    public let timeMachine: Bool?  // 타임머신(다시보기) 지원 여부
    public let status: String?
}
```

#### 계산 방식

```
방송 경과 시간 = Date.now - start(UTC)
웹 플레이어 표시 위치 = 방송 경과 시간 - targetLatency(6초)
```

#### 한계

- `start`는 방송 **시작** 시각 → 누적 경과 시간은 계속 증가
- HLS 세그먼트의 실제 스트림 타임라인과 `start` 기준 계산이 항상 일치하지 않음
- 방송 일시정지/재개 시 오차 발생
- **PDT 방식(A)보다 정확도 낮음, 보조 수단으로만 활용**

---

## 6. 권장 구현 로드맵

### Phase 1 — 즉시 개선 (방법 B)

**VLC 옵션 최적화로 기본 레이턴시 단축 (약 2~3일 작업)**

```swift
// VLCPlayerEngine.configureMediaOptions() 수정
":network-caching=800",
":live-caching=1500",
":clock-jitter=0",
":clock-synchro=0",
":drop-late-frames",
":skip-frames",
```

예상 효과: 기본 레이턴시 **18~20초 → 10~12초**

---

### Phase 2 — 핵심 개선 (방법 A + B 결합)

**PDT 기반 정확한 레이턴시 측정 + 목표 동기화 (약 1~2주 작업)**

#### 2-1. `StreamCoordinator`에 PDT 폴링 추가

```swift
// StreamCoordinator.swift에 추가할 메서드
private func pollMediaPlaylistForPDT(variantURL: URL) async {
    // 2초마다 미디어 플레이리스트 fetch
    var request = URLRequest(url: variantURL)
    request.setValue("https://chzzk.naver.com/", forHTTPHeaderField: "Referer")
    
    let (data, _) = try await URLSession.shared.data(for: request)
    let content = String(data: data, encoding: .utf8) ?? ""
    
    let playlist = try await hlsParser.parseMediaPlaylist(content: content, baseURL: variantURL)
    
    // 라이브 엣지 계산
    if let lastSeg = playlist.segments.last,
       let pdt = lastSeg.programDateTime {
        let liveEdgeUTC = pdt.addingTimeInterval(lastSeg.duration)
        let actualLatency = Date().timeIntervalSince(liveEdgeUTC)
        await lowLatencyController?.updateExternalLatency(actualLatency)
    }
}
```

#### 2-2. `LowLatencyController`에 외부 레이턴시 주입

```swift
// LowLatencyController.swift에 추가
public func updateExternalLatency(_ latency: TimeInterval) async {
    // VLC duration 기반 대신 PDT 기반 레이턴시로 교체
    externalLatencyOverride = latency
}
```

#### 2-3. `LowLatencyController.Configuration` 웹 호환 프리셋

```swift
public static let chzzkWebCompatible = Configuration(
    targetLatency: 6.0,      // hls.js 기본값 (3 × 2s segmentDuration)
    maxLatency: 15.0,
    minLatency: 4.0,
    maxPlaybackRate: 1.08,   // 부드러운 catchup (hls.js maxLiveSyncPlaybackRate)
    minPlaybackRate: 0.95,
    catchUpThreshold: 2.0,
    slowDownThreshold: 1.0,
    pidKp: 0.5,              // 과도응답 방지
    pidKi: 0.05,
    pidKd: 0.02
)
```

---

### Phase 3 — 정밀 동기화 (선택적)

**사용자가 설정에서 "웹 동기화 모드" 선택 가능하게 구현**

```
설정 > 플레이어 > 레이턴시 모드
  ● 자동 (VLC 기본)
  ● 웹 동기화 (± 1초, 치지직 웹 기준)  ← Phase 3
  ● 초저지연 (LL-HLS, 실험적)
```

---

## 7. 치지직 특이사항 및 제약

### 7-1. CDN 레이턴시

```
인코더 → 치지직 서버 → NAVER CDN → 클라이언트
          (약 1~2초)     (약 0.5~1초)  (재생 버퍼)
```

웹 플레이어 기준 하한선은 **약 4~5초** (CDN+인코딩 지연).  
이보다 낮게 설정하면 버퍼링이 빈번하게 발생한다.

### 7-2. Content-Type 버그 (이미 해결)

`navercdn.com`이 fMP4 세그먼트를 `video/MP2T`로 반환하는 버그 →  
현재 `LocalStreamProxy`로 Content-Type을 교정 중.

### 7-3. VLC live stream seek 제한

VLC가 HLS 라이브 스트림에서 뒤로 seek할 경우 일부 세그먼트가 이미 CDN에서 만료될 수 있다 (기본 유지 시간 30~60초). 앞으로 seek(즉, 더 빠르게 재생)하는 방식이 안전하다.

### 7-4. PDT 태그 존재 여부

치지직 스트림에서 PDT 태그가 없는 경우 방법 C(`live.start`)를 fallback으로 사용한다.

---

## 8. 정확도 기대치

| 방법 | 예상 정확도 | 구현 난이도 |
|---|---|---|
| 현재 (VLC 기본) | ±8~15초 | - |
| 방법 B만 (옵션 최적화) | ±4~8초 | 낮음 |
| 방법 A + B | **±0.5~2초** | 중간 |
| 방법 A + B + Phase 3 | **±0.5초** | 높음 |

---

## 9. 참고 자료

- [HLS 규격 (RFC 8216)](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.6) — `EXT-X-PROGRAM-DATE-TIME`
- [hls.js 소스 — latency 계산](https://github.com/video-dev/hls.js/blob/master/src/controller/latency-controller.ts)
- [Apple HLS Authoring Spec](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices) — Live playlist requirements
- `CView_v2/Sources/CViewPlayer/HLSManifestParser.swift` — 기존 PDT 파싱 코드
- `CView_v2/Sources/CViewPlayer/LowLatencyController.swift` — PID + EWMA 레이턴시 제어
- `CView_v2/Sources/CViewPlayer/StreamCoordinator.swift` — 스트림 오케스트레이터

---

## 10. 요약

> **웹 플레이어와 재생 위치를 맞추는 핵심은 `#EXT-X-PROGRAM-DATE-TIME` 태그를 활용한 절대 레이턴시 측정이다.**

현재 CView_v2는 VLC의 내부 버퍼 크기(`duration - currentTime`)를 레이턴시로 사용하므로 실제 라이브 엣지와의 차이를 정확히 반영하지 못한다. `HLSManifestParser`가 이미 PDT를 파싱하므로, `StreamCoordinator`에 미디어 플레이리스트 폴링 로직과 `LowLatencyController`의 `targetLatency = 6.0`(웹 기본값) 설정만 추가하면 웹 플레이어와 **±1~2초** 수준의 동기화가 가능하다.
