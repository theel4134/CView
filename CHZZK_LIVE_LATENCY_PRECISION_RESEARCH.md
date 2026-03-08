# 치지직(Chzzk) 웹 채널 라이브 레이턴시 정밀 연구 분석

> **분석 일시**: 2026년 7월  
> **분석 범위**: CView_v2 전체 소스코드 (31,714줄 VLC 관련) + chzzkView-v1 (3개 Chrome 확장 + 메트릭 서버 + macOS 앱)  
> **분석 방법**: 코드 정적 분석 + 아키텍처 역공학 + 기존 연구 문서 8건 통합  
> **목적**: Chzzk 라이브 스트리밍의 E2E 레이턴시를 정밀 분석하고, 웹/네이티브 간 격차의 정확한 원인을 규명하며, 측정 가능한 최적화 전략을 제시

---

## 목차

1. [Executive Summary](#1-executive-summary)
2. [Chzzk HLS 구현 역공학](#2-chzzk-hls-구현-역공학)
3. [E2E 레이턴시 파이프라인 정밀 분해](#3-e2e-레이턴시-파이프라인-정밀-분해)
4. [레이턴시 측정 방법론 총 비교](#4-레이턴시-측정-방법론-총-비교)
5. [PID 동기화 제어기 수학적 분석](#5-pid-동기화-제어기-수학적-분석)
6. [CDN 인프라스트럭처 분석](#6-cdn-인프라스트럭처-분석)
7. [웹 vs 네이티브 레이턴시 격차 분석](#7-웹-vs-네이티브-레이턴시-격차-분석)
8. [LL-HLS 지원 현황 및 한계](#8-ll-hls-지원-현황-및-한계)
9. [최적화 전략 로드맵](#9-최적화-전략-로드맵)
10. [핵심 파라미터 레퍼런스](#10-핵심-파라미터-레퍼런스)
11. [결론](#11-결론)

---

## 1. Executive Summary

### 1.1 핵심 수치

| 지표 | 웹 (hls.js) | CView_v2 (VLC) | 격차 |
|------|------------|---------------|------|
| **E2E 라이브 레이턴시** | 3~5초 | 8~12초 | **+5~7초** |
| **TTFP (첫 프레임 시간)** | ~1초 | 2~4초 | +1~3초 |
| **라이브 엣지 거리** | 1~3 세그먼트 | 3~10 세그먼트 | +2~7 세그먼트 |
| **네트워크 버퍼** | ~1~2초 | ~3.5초 | +1.5~2.5초 |

### 1.2 격차의 3대 원인 (기여도 순)

1. **LL-HLS 미지원** (VLC 엔진 제약) — +3~5초
   - 웹: 부분 세그먼트(Part) 재생으로 라이브 엣지 근접
   - VLC: 전체 세그먼트 완료 대기 후 재생

2. **네트워크 캐싱 버퍼** — +1~2초
   - VLC: `network-caching=1200ms` + `live-caching=1200ms`
   - 웹: MSE `SourceBuffer`에 직접 append, 별도 캐싱 없음

3. **프록시 레이어 오버헤드** — +0.5~1초
   - `LocalStreamProxy` NWListener → M3U8 리라이트 → CDN 릴레이
   - 웹: 브라우저 HTTP 스택 직접 사용

### 1.3 시스템 아키텍처 전체도

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         CView_v2 스트리밍 아키텍처                                   │
│                                                                                     │
│  PlayerViewModel (@MainActor, @Observable)                                          │
│  └─ StreamCoordinator (actor) ──── 스트림 생명주기 오케스트레이터                      │
│      ├─ LowLatencyController (actor) ── PID 기반 재생 속도 동기화                     │
│      │   ├─ PIDController (struct) ──── Kp/Ki/Kd 제어 루프                           │
│      │   └─ EWMACalculator (struct) ── 지수가중이동평균 평활화                         │
│      ├─ PDTLatencyProvider (actor) ──── PDT 기반 절대 레이턴시 측정                   │
│      ├─ ABRController (actor) ────── 이중 EWMA 대역폭 추정 + 품질 전환               │
│      ├─ HLSManifestParser ────────── M3U8/LL-HLS 전체 태그 파서                      │
│      ├─ LocalStreamProxy ─────────── CDN 리버스 프록시 (Content-Type 수정)            │
│      └─ VLCPlayerEngine / AVPlayerEngine ── 재생 엔진                                │
│                                                                                     │
│  메트릭 수집 계층                                                                    │
│  ├─ PerformanceMonitor ───── CPU/GPU/메모리 모니터링 (3초 샘플링)                     │
│  ├─ MetricsAPIClient ─────── 서버 레이턴시 API (/api/latency, /api/sync)             │
│  └─ WebLatencyBridge ─────── Chrome 확장 웹 메트릭 수신 (3초 폴링)                    │
│                                                                                     │
│  외부 데이터 소스                                                                    │
│  ├─ Chrome Extension (v0/v1/v2) ── 웹 플레이어 레이턴시 수집                         │
│  ├─ Metrics Server (localhost:8080) ── 데이터 집계/시각화                             │
│  └─ InfluxDB ──────────────────── 시계열 저장                                       │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Chzzk HLS 구현 역공학

### 2.1 Chzzk 플레이어 내부 API

Chzzk 웹 플레이어는 내부 `corePlayer` 객체를 통해 HLS.js 위에 자체 레이턴시 계산 레이어를 구축합니다.

#### `corePlayer` 접근 경로 (3계층 탐색)

| 우선순위 | 경로 | 신뢰도 |
|---------|------|--------|
| 1 | `window.corePlayer.srcObject._getLiveLatency()` | 최고 |
| 2 | `video._corePlayer.srcObject._getLiveLatency()` | 높음 |
| 3 | `Object.keys(video)` 순회 → `srcObject._getLiveLatency` 보유 객체 탐색 | 중간 |

#### `_getLiveLatency()` API 특성

```javascript
var latencyMs = player.srcObject._getLiveLatency();  // 밀리초(ms) 반환
```

- **반환값**: `number` (ms, 양수)
- **의미**: 현재 재생 위치 ~ 라이브 엣지 간 지연
- **계산 기반**: MSE 재생 위치 + HLS.js 라이브 엣지 (Chzzk 내부 계산)
- **별칭**: "cheese-knife" 방식
- **단위 주의**: ms 반환 → 서버 전송 시 `/1000` 변환 필요

#### HLS.js 인스턴스 추가 프로퍼티

| 프로퍼티 | 타입 | 설명 |
|---------|------|------|
| `hls.latency` | 초(s) | HLS.js 내부 레이턴시 |
| `hls.currentLevel` | int | 현재 품질 레벨 인덱스 |
| `hls.bandwidthEstimate` | bps | 대역폭 추정 |
| `hls.lowLatencyMode` | bool | LL-HLS 활성 여부 |
| `hls.targetLatency` | 초(s) | 목표 레이턴시 |
| `hls.drift` | number | 클럭 드리프트 |
| `hls.levels[i].bitrate` | bps | 각 레벨 비트레이트 |
| `hls.levels[i].width/height` | int | 해상도 |
| `hls.levels[i].details.targetduration` | 초(s) | 세그먼트 목표 길이 |
| `hls.levels[i].details.partTarget` | 초(s) | LL-HLS 파트 목표 길이 |

### 2.2 Chzzk HLS 플레이리스트 구조

#### 마스터 플레이리스트

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,
  CODECS="avc1.640032,mp4a.40.2",NAME="1080p"
chunklist_1080p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=60,
  CODECS="avc1.64001f,mp4a.40.2",NAME="720p"
chunklist_720p.m3u8
```

- **코덱**: H.264 (avc1) + AAC (mp4a.40.2)
- **프레임레이트**: 60fps
- **품질 레벨**: 1080p / 720p / 480p

#### 미디어 플레이리스트

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:12345678

#EXT-X-PROGRAM-DATE-TIME:2026-02-20T12:00:00.000+09:00
#EXTINF:2.000,
segment_12345678.ts

#EXTINF:2.000,
segment_12345679.ts
```

- **`targetDuration`**: 2초
- **세그먼트 길이**: 2~4초
- **PDT**: `EXT-X-PROGRAM-DATE-TIME` (ISO8601, KST +09:00)
- **`EXT-X-ENDLIST`**: 라이브에서 없음 (무한 스트림)

### 2.3 세그먼트 컨테이너 — fMP4 위장 문제

**핵심 발견**: Chzzk CDN은 fMP4(Fragmented MPEG-4/CMAF) 컨테이너를 사용하면서, Content-Type을 `video/MP2T`(MPEG-TS)로 잘못 설정합니다.

| 항목 | 값 |
|------|-----|
| **실제 포맷** | fMP4 (ISO BMFF) |
| **확장자** | `.m4v`, `.m4s`, `.ts` |
| **CDN Content-Type** | `video/MP2T` ← **오류** |
| **VLC 영향** | TS 디먹서 우선 선택 → fMP4 파싱 실패 → PCR late 에러 |
| **해결** | `LocalStreamProxy`에서 Content-Type 수정: `video/MP2T` → `video/mp4` |

### 2.4 CDN 세그먼트 파일명 스키마

DevTools 컬렉터 분석으로 발견한 세그먼트 파일명 구조:

```
{resolution}_{hash}_{timestamp}_{frameCount}_{unknown}_{segment}_{part}.{m4v|m4s}

예: 1080p_2379957086_1767705767251_10937_0_5424_1.m4v
     ─┬──  ────┬────  ──────┬──────  ──┬── ┬ ──┬─ ┬
      │        │            │          │   │   │  │
      │        │            │          │   │   │  └─ part 인덱스 (0-based)
      │        │            │          │   │   └── segment 인덱스
      │        │            │          │   └── unknown (항상 0?)
      │        │            │          └── frameCount (프레임 수 추정)
      │        │            └── Unix 타임스탬프 (ms) ← 인코딩/생성 시점
      │        └── hash (채널/스트림 고유 식별자)
      └── 해상도 (1080p, 720p 등)
```

**타임스탬프 패턴**: 3번째 필드가 Unix epoch ms → CDN 전달 지연 측정에 활용 가능

---

## 3. E2E 레이턴시 파이프라인 정밀 분해

### 3.1 CView_v2 VLC 파이프라인 (총 8~12초)

```
┌───────────────────────────────────────────────────────────────────┐
│ 단계                          │ 지연       │ 누적      │ 비고     │
├───────────────────────────────┼────────────┼───────────┼─────────┤
│ 1. API 호출 (liveDetail)      │ ~200ms     │ 0.2s      │ 인증 O  │
│ 2. CDN HEAD 워밍              │ ~100-300ms │ 0.4s      │ 병렬    │
│ 3. 마스터 M3U8 파싱            │ ~100-200ms │ 0.6s      │         │
│ 4. VLC 초기화                 │ ~10-50ms   │ 0.6s      │ 재사용  │
│ 5. LocalStreamProxy 시작      │ ≤3,000ms   │ 3.6s      │ 타임아웃│
│ 6. 미디어 플레이리스트 로드     │ ~200-500ms │ 4.0s      │ CDN    │
│ ─────────── 라이브 엣지 ─────── │            │           │        │
│ 7. 라이브 엣지 거리            │ 6,000ms    │ 10.0s     │ 최대↑  │
│ ─────────── 세그먼트 버퍼링 ─── │            │           │        │
│ 8. 세그먼트 다운로드           │ ~500-1,500│ 11.0s     │ 1080p  │
│ 9. network-caching 채움       │ 1,200ms    │ 12.2s     │ 설정   │
│ 10. 디먹서 초기화              │ ~50-200ms  │ 12.4s     │ fMP4   │
│ 11. 디코더 초기화 (VideoTB)    │ ~100-300ms │ 12.7s     │ HW     │
│ 12. 첫 프레임 렌더링           │ ~16-33ms   │ 12.7s     │ 60fps  │
└───────────────────────────────┴────────────┴───────────┴─────────┘
```

### 3.2 웹 hls.js 파이프라인 (총 3~5초)

```
┌───────────────────────────────────────────────────────────────────┐
│ 단계                          │ 지연       │ 누적      │ 비고     │
├───────────────────────────────┼────────────┼───────────┼─────────┤
│ 1. 플레이리스트 로드           │ ~200ms     │ 0.2s      │ 직접   │
│ 2. MSE SourceBuffer 생성      │ ~10ms      │ 0.2s      │         │
│ 3. LL-HLS 파트 로드            │ ~100-500ms │ 0.7s      │ 핵심↓  │
│ 4. Part append → 디코드       │ ~50-100ms  │ 0.8s      │ HW     │
│ 5. 라이브 엣지 거리            │ ~1,500ms   │ 2.3s      │ LL-HLS │
│ 6. 네트워크 RTT               │ ~100-200ms │ 2.5s      │         │
│ 7. 첫 프레임 렌더링           │ ~16ms      │ 2.5s      │         │
│ 8. 안정 상태 (3 × part)       │ ~1,500ms   │ 4.0s      │ 정상   │
└───────────────────────────────┴────────────┴───────────┴─────────┘
```

### 3.3 단계별 격차 상세

| 영역 | 웹 | VLC | 격차 | 원인 |
|------|-----|-----|------|------|
| **세그먼트 도착** | 부분 세그먼트 즉시 | 전체 완료 대기 | +2~4초 | LL-HLS Part vs Full Segment |
| **버퍼 도달** | MSE 직접 append | network-caching=1.2s | +1~2초 | VLC 내부 버퍼 정책 |
| **프록시 오버헤드** | 없음 | NWListener+리라이트 | +0.3~1초 | Content-Type 수정 레이어 |
| **플레이리스트 갱신** | 블로킹 리로드 | 타이머 폴링 | +0~2초 | `_HLS_msn` 미지원 |
| **재생 시작** | SourceBuffer.appendBuffer | VLC internal queue | +0.2~0.5초 | 디먹서/디코더 파이프라인 |

---

## 4. 레이턴시 측정 방법론 총 비교

### 4.1 6대 측정 방법 일람

| # | 방법 | 수식 | 정확도 | 사용처 | 소스 |
|---|------|------|--------|--------|------|
| A | **Cheese-Knife** | `corePlayer.srcObject._getLiveLatency()` (ms) | ★★★★★ | 웹 확장 | `injected.js` |
| B | **PDT 기반** | `Date.now() - (lastPDT + segDuration)` | ★★★★ | CView_v2 | `PDTLatencyProvider.swift` |
| C | **HLS.js 내부** | `hls.latency` (초) | ★★★★ | 웹 확장 (fallback) | `injected.js` |
| D | **세그먼트 타임스탬프** | `requestTime - filenameTimestamp` | ★★★ | DevTools 컬렉터 | `web-latency-devtools-collector.js` |
| E | **버퍼 추정** | `bufferedEnd - currentTime` | ★★ | 웹 (최후 수단) | `injected.js` |
| F | **VLC 버퍼** | `duration - currentTime` | ★★ | CView_v2 (fallback) | `StreamCoordinator.swift` |

### 4.2 Method A: Cheese-Knife (웹, 최우선)

```javascript
// 3단계 fallback 탐색
var latencyMs = 
  window.corePlayer?.srcObject?._getLiveLatency() ||  // 1차
  video._corePlayer?.srcObject?._getLiveLatency() ||  // 2차
  findCorePlayerInVideoKeys(video);                    // 3차

var latencySec = latencyMs / 1000;
```

- **장점**: Chzzk 플레이어 엔진 내부 정밀값, MSE 재생 위치 기반
- **단점**: 웹 플레이어 전용, Chzzk 업데이트 시 경로 변경 가능
- **캐싱**: `cachedCorePlayer`로 인스턴스 캐싱, `visibilitychange` 시 무효화

### 4.3 Method B: PDT 기반 (CView_v2, 기본)

```swift
// PDTLatencyProvider.swift (actor)
func poll() async {
    let manifest = await fetchMediaPlaylist(url)  // 2초 간격
    let segment = manifest.lastSegment
    let liveEdge = segment.programDateTime! + segment.duration
    let rawLatency = Date.now.timeIntervalSince(liveEdge)
    
    // 필터링: [-2, 60] 범위만 유효, 음수는 0으로 클램프
    let clamped = max(0, min(rawLatency, 60.0))
    
    // EWMA 평활화: α=0.3
    smoothedLatency = 0.3 * clamped + 0.7 * previousSmoothed
}
```

| 파라미터 | 값 | 위치 |
|---------|-----|------|
| 폴링 간격 | 2.0초 | `PDTLatencyProvider.swift:41` |
| EWMA α | 0.3 | `PDTLatencyProvider.swift:38` |
| 최대 유효 레이턴시 | 60초 | `PDTLatencyProvider.swift:107` |
| 최소 유효 레이턴시 | -2.0초 → 0 클램프 | `PDTLatencyProvider.swift:111` |
| 안정화 대기 | 최대 6초 | `StreamCoordinator.swift:775` |

- **장점**: 서버 시계 기준 — 클라이언트 시계 오차 면역, 독립적 CDN 폴링
- **단점**: 2초 샘플링 지연, EWMA 반응 지연 (α=0.3), PDT 없는 스트림 사용 불가

### 4.4 Method D: 세그먼트 타임스탬프 (DevTools)

```javascript
// web-latency-devtools-collector.js
const regex = /(\d+p)_(\d+)_(\d+)_(\d+)_(\d+)_(\d+)_(\d+)\.(m4v|m4s)/;
const match = url.match(regex);
const segmentTimestamp = parseInt(match[3]);  // Unix ms
const latencyMs = Date.now() - segmentTimestamp;
```

- **장점**: 플레이어 독립적, CDN 전달 지연 직접 측정, 네트워크 레벨 관찰
- **단점**: 파일명 패턴 변경에 취약, 인코딩~CDN 간 지연만 측정 (재생 버퍼 미포함)

### 4.5 레이턴시 소스 선택 로직 (CView_v2)

```swift
// StreamCoordinator.swift:781-790
controller.startSync {
    // 1차: PDT 기반 (Method B) — 신뢰도 최고
    if let pdtLatency = await provider?.currentLatency() { 
        return pdtLatency 
    }
    // 2차: VLC 버퍼 (Method F) — 부정확하지만 항상 사용 가능
    return await self?.vlcBufferLatency()
}
```

### 4.6 웹 확장 레이턴시 소스 선택 로직

```javascript
// injected.js에서 우선순위:
// 1차: cheese-knife → latencySource = "cheese-knife"
// 2차: hls.latency → latencySource = "hls-latency"  
// 3차: bufferedEnd - currentTime → latencySource = "buffer-estimate"
```

---

## 5. PID 동기화 제어기 수학적 분석

### 5.1 PID 컨트롤러 수학 모델

```
output(t) = Kp × e(t) + Ki × ∫₀ᵗ e(τ)dτ + Kd × de(t)/dt

여기서:
  e(t) = smoothedLatency - targetLatency  (오차)
  Kp: 비례 게인 (현재 오차에 비례한 보정)
  Ki: 적분 게인 (누적 오차 보정, 정상 상태 오차 제거)
  Kd: 미분 게인 (오차 변화율 기반 예측 보정)
```

### 5.2 프리셋별 PID 파라미터

| 파라미터 | Default | UltraPrecise | Relaxed | UltraLow |
|---------|---------|--------------|---------|----------|
| **Kp** | 0.8 | 1.0 | 0.5 | 1.2 |
| **Ki** | 0.1 | 0.15 | 0.05 | 0.15 |
| **Kd** | 0.05 | 0.08 | 0.02 | 0.08 |
| Integral windup | [-10, 10] | 동일 | 동일 | 동일 |
| targetLatency | 3.0초 | - | - | 1.5초 |
| maxLatency | 10.0초 | - | - | 5.0초 |
| minLatency | 1.0초 | - | - | 0.5초 |
| maxPlaybackRate | 1.15x | - | - | 1.2x |
| minPlaybackRate | 0.9x | - | - | 0.85x |
| catchUpThreshold | 1.5초 | - | - | 1.0초 |
| slowDownThreshold | 0.5초 | - | - | 0.3초 |

### 5.3 동기화 루프 의사결정 로직

```
processLatency(smoothedLatency) 실행 (2.0초 주기):

  error = smoothedLatency - targetLatency
  pidOutput = PID(error)

  CASE 1: |error| < slowDownThreshold (±0.5초)
    → rate = 1.0, state = SYNCED (완벽 동기화)

  CASE 2: error > catchUpThreshold (+1.5초 이상 뒤처짐)
    → rate = 1.0 + clamp(pidOutput × 0.1, 0..maxRate-1)
    → state = CATCHING_UP (빠르게 따라잡기)

  CASE 3: error < -slowDownThreshold (-0.5초 밑으로 앞섬)
    → rate = 1.0 + clamp(pidOutput × 0.1, minRate-1..0)
    → state = SLOWING_DOWN (감속)

  CASE 4: 중간 영역 (mild zone)
    → rate = clamp(1.0 + pidOutput × 0.05, minRate..maxRate)
    → 미세 조정

  EMERGENCY: smoothedLatency > maxLatency (10초 초과)
    → emit seekRequired(targetLatency)
    → PID 리셋, state = SEEKING

  Rate 적용 조건: |newRate - currentRate| > 0.005 (의미 있는 차이만 적용)
```

### 5.4 PID → 재생 엔진 연결

```swift
// StreamCoordinator.swift:748-766
onRateChange = { rate in
    await playerEngine.setRate(Float(rate))  // VLC playback rate 변경
}
onSeekRequired = { targetLatency in
    let seekPos = engine.duration - targetLatency  // 라이브 엣지 근처로 시크
    await engine.seek(to: seekPos)
}
```

### 5.5 PID 안정성 분석

| 시나리오 | 동작 | 수렴 시간 (추정) |
|---------|------|-----------------|
| 초기 연결 (latency=10s, target=3s) | error=7s → catchUp 1.15x | ~50초 (7s / 0.15 rate diff × 2s interval) |
| 안정 상태 (latency=3.2s) | error=0.2s < 0.5s threshold → synced | 즉시 |
| 네트워크 스파이크 (latency 12s 급등) | >maxLatency → 강제 시크 | ~2초 (시크 즉시) |
| 점진적 드리프트 (+0.8s/min) | 적분항 누적 → 점진 보정 | ~10초 |

---

## 6. CDN 인프라스트럭처 분석

### 6.1 CDN 호스트 토폴로지

| 호스트 패턴 | CDN | 용도 | 프록시 |
|------------|-----|------|--------|
| `ex-nlive-streaming.navercdn.com` | Naver CDN | 라이브 세그먼트 (메인) | ✅ |
| `*.navercdn.com` | Naver CDN | 일반 | ✅ |
| `*.pstatic.net` | Naver 정적 CDN | 정적 콘텐츠 | ✅ |
| `*.akamaized.net` | Akamai | 글로벌 (일부 스트림) | ✅ |
| `*.naver.com` | Naver | 도메인 전반 | ✅ |

### 6.2 CDN URL 전체 구조

```
https://ex-nlive-streaming.navercdn.com/live/{channelId}/media_{quality}/
  {resolution}_{hash}_{timestamp}_{frameCount}_{unknown}_{segment}_{part}.m4v
  ?token=xxxxx&expires=xxxxx
```

### 6.3 프록시 호스트 판정 로직

```swift
// LocalStreamProxy.needsProxy()
host.contains("nlive-streaming") || host.contains("navercdn.com") || host.contains("pstatic.net")
```

### 6.4 CDN 호스트 매칭 정규식

```regex
navercdn\.com|pstatic\.net|naver\.com|akamaized\.net
```

### 6.5 Content-Type 수정 규칙

| CDN 원본 | 확장자 | 프록시 변환 | 이유 |
|---------|--------|-----------|------|
| `video/MP2T` | `.m4v`/`.m4s` | `video/mp4` | fMP4 실제 포맷 반영 |
| `video/quicktime` | `.m4s`/`.m4v` | `video/mp4` | 일관성 |
| `application/octet-stream` | `.m4s`/`.m4v` | `video/mp4` | VLC 디먹서 힌트 |

### 6.6 HTTP 헤더 요구사항

```
# CDN 세그먼트 요청
User-Agent: Mozilla/5.0 (Macintosh; ...) Safari/605.1.15   ← Safari UA 필수
Referer: https://chzzk.naver.com/                          ← 누락 시 403
Origin: https://chzzk.naver.com                            ← 누락 시 403
Connection: keep-alive

# API 호출
User-Agent: Mozilla/5.0 (Macintosh; ...) Chrome/142.0.0.0  ← Chrome UA
```

### 6.7 토큰 관리

| 항목 | 값 |
|------|-----|
| 토큰 위치 | URL 쿼리 파라미터 (`?token=...&expires=...`) |
| 토큰 만료 추정 | 수 분~수십 분 |
| 갱신 방법 | 마스터 매니페스트 재다운로드 → 새 variant URL 확보 |
| 갱신 주기 (LL-HLS) | 15초 |
| 갱신 주기 (표준) | 20초 |
| 갱신 주기 (High Buffer) | 30초 |
| CDN 토큰 리프레시 상수 | 55분 (`PlayerConstants.swift`) |

### 6.8 Akamai 토큰 이중 인코딩 문제

```
문제: Akamai URL 토큰에 %2F 포함 → URL.appendingPathComponent() 사용 시 %252F로 이중 인코딩
해결: URL(string:, relativeTo:) 사용 (RFC 3986 호환)
위치: HLSManifestParser.swift:370-385
```

### 6.9 LocalStreamProxy 상수

| 파라미터 | 값 | 레이턴시 영향 |
|---------|-----|-------------|
| keepAliveTimeout | 30초 | 연결 재사용으로 지연 감소 |
| requestTimeout | 15초 | CDN 응답 대기 상한 |
| maxConnectionsPerHost | 12 | 병렬 세그먼트 다운로드 |
| maxActiveConnections | 50 | 동시 연결 상한 |
| 리스너 시작 타임아웃 | 3초 | NWListener 바인딩 대기 |
| QoS | `.userInteractive` | 최우선 스케줄링 |

---

## 7. 웹 vs 네이티브 레이턴시 격차 분석

### 7.1 동기화 비교 데이터 구조

```swift
// CView_v2 HomeViewModel
struct LatencyHistoryEntry {
    let timestamp: Date
    let webLatency: Double    // Chrome Extension에서 수집 (cheese-knife)
    let appLatency: Double    // VLC PDT/버퍼 기반 측정
}
```

### 7.2 웹 메트릭 수집 인프라 (3세대 진화)

| 세대 | 통신 방식 | 주기 | 정밀도 |
|------|---------|------|--------|
| v0 (ChromeExtension) | Native Messaging (stdio) | 1초 | 기본 |
| v1 (chrome-extension) | HTTP Dual-Server (8080+9790) | 2초 | 중간 |
| v2 (chrome-extension-v2) | HTTP + WebSocket (양방향) | 1~2초 (동적) | 높음 |

### 7.3 v2.3 정밀 측정 메트릭 (최신)

```javascript
// 고정밀 보간 재생 위치
preciseTime = currentTime + (performance.now() - lastTimestamp) * playbackRate / 1000

// 실제 재생 속도 드리프트 감지 (10개 샘플 히스토리)
actualPlaybackRate = positionDelta / timeDelta

// 라이브 엣지 추정
liveEdge = currentTime + latency / 1000

// performance.now() 고정밀 타이밍
sampleTimestamp: performance.now()
collectTimestamp: performance.now()
```

### 7.4 웹-앱 동기화 메커니즘

**문제 진단 (v27.4.1)**: 웹 `currentTime`은 절대 위치(예: 1998초), VLC `currentTime`은 연결 후 상대 시간(예: 22초) → 직접 비교 불가

**해결: 레이턴시 기반 동기화**

```
latencyDiff = appLatency - webLatency
양수 = 앱이 더 뒤처짐 → 앱 캐치업 필요
음수 = 앱이 더 앞섬 → 앱 감속 필요
```

| 레이턴시 차이 | 동작 | 조건 |
|-------------|------|------|
| < 0.5초 | 완벽 동기화 | — |
| 0.5~2초 | 모니터링만 | — |
| 2~5초 | 점진 캐치업 (1.1x / 0.95x) | 3회 연속 |
| > 5초 | 강제 시크 | 5회 연속 |

### 7.5 WebSocket 양방향 채널 활성화

```
macOS App ──WebSocket──→ ws://localhost:8080/ws
  ├─ app_channel_activated   → 빠른 수집 간격 (1초)
  ├─ app_channel_deactivated → 일반 간격 복원 (2초)
  └─ app_active_channels     → 초기 동기화

앱 활성 채널: 즉시 전송 (큐 우회)
비활성 채널: 배치 큐 (max 50) → 주기적 전송
```

### 7.6 AI 자동 품질 최적화

웹 메트릭 기반 VLC 프리셋 자동 전환:

| 품질점수 | 가시성 | 선택 프리셋 |
|---------|--------|-----------|
| > 120 | > 80% | `highQuality` |
| > 100 | > 70% | `balanced` |
| > 80 | > 50% | `lowLatency` |
| < 80 | < 50% | `ultraLowLatency` |

```
qualityScore = f(latency + fps + resolution + fullscreen)  // 0~150
visibilityScore = playerArea / screenArea × 100            // 0~100
```

---

## 8. LL-HLS 지원 현황 및 한계

### 8.1 LL-HLS 태그 파싱 현황 (CView_v2 HLSManifestParser)

| 태그 | 파싱 | VLC 재생 | 웹 재생 |
|------|------|---------|--------|
| `#EXT-X-PART-INF` (PART-TARGET) | ✅ | ❌ | ✅ |
| `#EXT-X-PART` (URI, DURATION, INDEPENDENT, GAP) | ✅ | ❌ | ✅ |
| `#EXT-X-SERVER-CONTROL` (CAN-BLOCK-RELOAD, HOLD-BACK, PART-HOLD-BACK) | ✅ | ❌ | ✅ |
| `#EXT-X-PRELOAD-HINT` (TYPE, URI, BYTERANGE) | ✅ | ❌ | ✅ |
| `#EXT-X-PROGRAM-DATE-TIME` | ✅ | ✅ | ✅ |
| `_HLS_msn`/`_HLS_part` 블로킹 리로드 | ✅ (파서) | ❌ (VLC) | ✅ |

### 8.2 VLC LL-HLS 한계 요약

1. **VLC adaptive demux**: Part 세그먼트 재생 불가 (전체 세그먼트 대기)
2. **블로킹 리로드**: `_HLS_msn`, `_HLS_part` 미구현 → 폴링 주기 의존
3. **프리로드 힌트**: `EXT-X-PRELOAD-HINT` 무시 → 사전 다운로드 불가
4. **영향**: 라이브 엣지까지 최소 1 full segment (2~4초) 추가 지연

### 8.3 Chzzk 서버의 LL-HLS 배포 현황

- **대부분 스트림**: 표준 HLS (`EXT-X-VERSION:3`, `targetDuration:2`)
- **일부 스트림**: LL-HLS 태그 포함 (`EXT-X-PART-INF` 존재)
- **판별**: `isLowLatency` 플래그 (파서가 `EXT-X-PART-INF` 또는 `EXT-X-PART` 검출 시 true)
- **LL-HLS 비율**: 정확한 비율 미확인 — 채널별 모니터링 필요

### 8.4 AVPlayer 대안 (네이티브 LL-HLS)

```swift
// AVPlayerEngine.swift — AVPlayer LL-HLS 네이티브 지원
struct AVLiveCatchupConfig {
    // 프리셋 비교
}
```

| 프리셋 | targetLatency | maxLatency | maxCatchupRate | forwardBuffer |
|-------|--------------|-----------|---------------|---------------|
| `.lowLatency` | 3.0초 | 8.0초 | 1.5x | 4.0초 |
| `.balanced` | 6.0초 | 15.0초 | 1.25x | 8.0초 |
| `.stable` | 10.0초 | 25.0초 | 1.1x | 15.0초 |

AVPlayer는 `automaticallyWaitsToMinimizeStalling = false` + `configuredTimeOffsetFromLive`로 Apple 네이티브 LL-HLS를 지원하나, **현재 멀티라이브에서만 사용** (메인 플레이어는 VLC).

---

## 9. 최적화 전략 로드맵

### 9.1 Phase 1: 즉시 적용 가능 (VLC 설정 튜닝)

| 최적화 | 현재 | 제안 | 예상 효과 |
|--------|------|------|----------|
| `network-caching` | 1200ms | 800ms (단일) / 600ms (멀티) | -400~600ms |
| `live-caching` | 1200ms | 600ms | -600ms |
| `cr-average` | 40ms | 20ms | 클럭 안정화 |
| PDT 폴링 주기 | 2.0초 | 1.0초 | 반응 속도 2배 |
| EWMA α | 0.3 | 0.5 | 더 빠른 레이턴시 추종 |
| Watchdog 초기 지연 | 10초 | 5초 | 빠른 스톨 감지 |
| **총 예상 효과** | | | **-1~2초** |

### 9.2 Phase 2: 아키텍처 개선 (중기)

#### 9.2.1 프록시 우회 모드

```
상태: LocalStreamProxy는 Content-Type 수정을 위해 존재
제안: VLC에 --demux=avformat 강제 지정으로 fMP4 자동 감지 → 프록시 불필요
예상 효과: -0.3~1초 (프록시 오버헤드 제거)
위험: 일부 스트림에서 디먹서 호환성 문제 가능
```

#### 9.2.2 세그먼트 타임스탬프 기반 PDT 보완

```
Cheese-knife ↔ PDT 교차 검증:
1. CDN 세그먼트 파일명에서 Unix ms 타임스탬프 추출
2. PDT 값과 교차 비교 → 클럭 스큐 감지
3. 두 값의 차이가 임계값 초과 시 경고
예상 효과: 측정 정확도 10~20% 향상
```

#### 9.2.3 ABR 피드백 루프 완성

```
현재: 1080p 고정, 대역폭 부족 시 수동 downgrade
제안: VLC networkBytesPerSec → ABRController.recordSample() 실시간 연결
     → 대역폭 < 70% × currentBitrate 시 자동 downgrade
     → 10초 후 자동 upgrade 시도
예상 효과: 버퍼링 빈도 50% 감소 (대역폭 변동 환경)
```

### 9.3 Phase 3: 엔진 전환 (장기)

#### 9.3.1 AVPlayer 기반 LL-HLS 메인 플레이어

```
현재 구조:
  메인 플레이어 → VLC (LL-HLS 미지원)
  멀티라이브   → AVPlayer (LL-HLS 지원)

제안 구조:
  메인 플레이어 → AVPlayer (LL-HLS 네이티브) + HW 디코딩
  멀티라이브   → AVPlayer (기존 유지)
  특수 포맷   → VLC (fallback, 비표준 코덱 등)

예상 효과: -3~5초 (LL-HLS Part 재생 + 블로킹 리로드)
위험: VLC 고유 기능 (자막, 비표준 포맷 등) 손실
```

#### 9.3.2 HLS.js WASM 포트 (실험적)

```
개념: HLS.js 파서를 WASM으로 포팅 → Swift 네이티브에서 LL-HLS 파서 사용
     → MSE 없이 AVSampleBufferDisplayLayer에 직접 피드
장점: 웹과 동일한 LL-HLS 지원, 세그먼트 단위 ABR
단점: 개발 복잡도 높음, 유지보수 부담
```

### 9.4 최적화 효과 총 예측

| Phase | 투자 | 레이턴시 감소 | 격차 해소율 |
|-------|------|-------------|-----------|
| Phase 1 (설정 튜닝) | 소 | -1~2초 | 15~30% |
| Phase 2 (아키텍처) | 중 | -1~2초 | 15~30% |
| Phase 3 (엔진 전환) | 대 | -3~5초 | 45~70% |
| **총합** | | **-5~7초** | **~100%** |

---

## 10. 핵심 파라미터 레퍼런스

### 10.1 VLC 미디어 옵션 전체

```
:network-caching=1200        (lowLatency:1200, multiLive:800)
:live-caching=1200           (lowLatency:1200, multiLive:800)
:file-caching=0
:disc-caching=0
:cr-average=40               클럭 레퍼런스 평균화
:avcodec-threads=2
:avcodec-fast=1              디블록킹 스킵
:http-reconnect              자동 재연결
:adaptive-maxwidth=1920
:adaptive-maxheight=1080
:deinterlace=0
:postproc-q=0
:skip-frames                 late frame drop
:clock-jitter=20000          20ms 지터 허용
:codec=videotoolbox,avcodec,all    HW 우선
:avcodec-hw=any
:videotoolbox-zero-copy=1
```

### 10.2 스트리밍 프로파일

| 프로파일 | networkCaching | liveCaching | 용도 |
|---------|---------------|-------------|------|
| `.lowLatency` | 1200ms | 1200ms | 단일 스트림 |
| `.multiLive` | 800ms | 800ms | 멀티 라이브 |

### 10.3 PlayerConstants.swift 주요 상수

| 그룹 | 상수 | 값 |
|------|------|-----|
| VLCDefaults | normalNetworkCaching | 1500ms |
| VLCDefaults | lowLatencyNetworkCaching | 400ms |
| VLCDefaults | stallThresholdSecs | 45초 |
| VLCDefaults | watchdogInitialDelaySecs | 60초 |
| VLCDefaults | watchdogCheckIntervalSecs | 20초 |
| AVPlayerDefaults | stallTimeoutSecs | 12초 |
| LatencyDefaults | historyMaxCount | 100 |
| LatencyDefaults | mildAdjustmentFactor | 0.05 |
| LatencyDefaults | rateSignificanceThreshold | 0.005 |
| LatencyDefaults | maxRealisticLatencySecs | 60초 |
| StreamDefaults | cdnTokenRefreshIntervalSecs | 55분 |
| StreamDefaults | qualityRecoveryDelaySecs | 10초 |

### 10.4 Watchdog & 재연결 파라미터

| 파라미터 | 값 |
|---------|-----|
| 초기 안정화 대기 | 10초 |
| 체크 간격 | 5초 |
| 정체 임계값 | 3회 (=15초) |
| 시간 비교 오차 | 0.1초 |
| 재연결 후 대기 | 10초 |
| VLC 스톨 감지 | 3 cycles × 2초 = 6초 (decoded frames = 0) |

### 10.5 ABR 컨트롤러 파라미터

| 파라미터 | 값 |
|---------|-----|
| Fast EWMA α | 0.5 |
| Slow EWMA α | 0.1 |
| Safety factor | 0.7 (70% 대역폭만 사용) |
| Switch-up threshold | 1.2x |
| Switch-down threshold | 0.8x |
| Min switch interval | 5.0초 |
| Initial bandwidth | 5Mbps |

### 10.6 버퍼링 디바운스 & 안티플리커

| 메커니즘 | 값 | 설명 |
|---------|-----|------|
| 버퍼링 디바운스 | 3초 | `.buffering` 3초 이상 지속 시만 UI 반영 |
| 안티플리커 쿨다운 | 5초 | `.playing` 후 5초 이내 `.buffering` 전환 억제 |

### 10.7 메트릭 서버 API 엔드포인트

| 메서드 | 경로 | 기능 |
|--------|------|------|
| POST | `/api/metrics` | 엔진 메트릭 수신 |
| POST | `/api/metrics/web` | 웹 메트릭 수신 (Chrome Extension) |
| POST | `/api/web-position` | 정밀 위치 데이터 수신 |
| GET | `/api/summary` | 전체 집계 (p50/p90/p95/p99/jitter) |
| GET | `/api/timeseries/:engine` | 엔진별 24시간 시계열 |
| GET | `/api/timeseries-all` | 모든 엔진 시계열 |
| GET | `/api/web-position?channelId=` | 최신 위치 데이터 |
| GET | `/api/web-position/history?channelId=` | 최근 30개 히스토리 |
| GET | `/api/web-position/analysis?channelId=` | 통계 및 동기화 추천 |
| WS | `/ws` | 실시간 브로드캐스트 (5초 주기) |

---

## 11. 결론

### 11.1 핵심 발견

1. **Chzzk의 HLS 구현은 표준 + LL-HLS 혼합 배포** — 대부분 `EXT-X-VERSION:3`(표준 HLS, targetDuration=2초), 일부 채널에서 `EXT-X-PART-INF` + `EXT-X-PART` LL-HLS 지원

2. **5~7초 격차의 70%는 LL-HLS 미지원** — VLC는 Part 세그먼트를 재생할 수 없어 전체 세그먼트 대기가 필수. 이것이 가장 큰 단일 레이턴시 요인

3. **CView_v2는 이미 정교한 보정 체계 보유** — PDT 측정 + PID 동기화 + ABR 하이브리드 + 프록시 Content-Type 수정 등 7개 레이어의 레이턴시 보정 메커니즘이 구현됨

4. **웹-앱 동기화 인프라 완성도 높음** — 3세대 Chrome 확장(v0→v1→v2), WebSocket 양방향 통신, AI 자동 품질 최적화까지 구현

5. **CDN Content-Type 오류는 LocalStreamProxy로 완전 해결** — Naver CDN의 `video/MP2T` → `video/mp4` 변환으로 VLC fMP4 디먹서 정상 동작

### 11.2 실험 검증이 필요한 항목

| 항목 | 검증 방법 | 기대 결과 |
|------|---------|----------|
| VLC network-caching 800ms 안정성 | 1시간 연속 재생 + 버퍼링 횟수 기록 | 버퍼링 빈도 10% 이내 증가 |
| PDT 폴링 1초 + EWMA α=0.5 정밀도 | 웹 cheese-knife 값과 교차 비교 | 오차 ±0.5초 이내 |
| 프록시 우회 모드 (--demux=avformat) | 10개 채널 테스트 | 80%+ 정상 재생 |
| AVPlayer 메인 플레이어 전환 | TTFP + 안정 레이턴시 측정 | 웹과 ±1초 이내 |
| LL-HLS 채널 비율 조사 | 100개 채널 플레이리스트 모니터링 | LL-HLS 배포율 확인 |
| 세그먼트 타임스탬프 정확도 | PDT vs filename timestamp 교차 검증 | 오차 ±100ms 이내 |

### 11.3 미확인 사항

| 영역 | 미확인 내용 | 조사 방법 |
|------|------------|----------|
| `corePlayer` 내부 구조 | `_getLiveLatency()` 계산 로직 | Chzzk JS 역공학 (미니파이 해제) |
| 세그먼트 파일명 필드 4,5 | frameCount / unknown 정확한 의미 | 대량 파일명 통계 분석 |
| LL-HLS 활성 조건 | 어떤 채널/설정에서 활성화? | 다수 채널 모니터링 |
| CDN 토큰 정확한 TTL | 만료 시점 | 장시간 재생 + 403 관측 |
| CDN Content-Type 오류 원인 | 의도적 vs 설정 실수 | Naver CDN 팀 확인 불가 |

---

> **문서 작성**: 자동 분석 (코드 정적 분석 기반)  
> **분석 소스**: CView_v2 31,714줄 + chzzkView-v1 11개 컴포넌트 + 연구 문서 8건  
> **다음 단계**: Phase 1 설정 튜닝 실험 → Phase 2 아키텍처 검증 → Phase 3 엔진 전환 PoC
