# 치지직(Chzzk) 라이브 스트리밍 레이턴시 종합 연구 보고서

> **분석 날짜**: 2026년  
> **분석 범위**: CView_v2 (8개 연구문서 + 소스코드), chzzkView-v1 (10개 연구문서 + 소스코드 + 인프라)  
> **목적**: 두 워크스페이스에 산재한 레이턴시 관련 모든 연구·코드를 집약하여 단일 참조 문서로 정리

---

## 목차

1. [기존 연구 결과 요약](#1-기존-연구-결과-요약)
2. [레이턴시 측정 방법 (코드 기반)](#2-레이턴시-측정-방법-코드-기반)
3. [핵심 레이턴시 데이터 포인트 및 벤치마크](#3-핵심-레이턴시-데이터-포인트-및-벤치마크)
4. [기술 아키텍처 상세](#4-기술-아키텍처-상세)
5. [미연구 영역 및 갭 분석](#5-미연구-영역-및-갭-분석)

---

## 1. 기존 연구 결과 요약

### 1.1 핵심 발견: VLC vs 웹 레이턴시 격차

| 항목 | 웹 (hls.js) | CView VLC | 차이 |
|------|-------------|-----------|------|
| **총 라이브 지연** | 3–5초 | 8–12초 | +5–7초 |
| **TTFP (첫 프레임)** | ~1초 | 2–4초 | +1–3초 |
| **타겟 레이턴시** | 6초 (3×targetDuration) | 8–20초 (설정 의존) | — |

**출처**: `VLC_LATENCY_ANALYSIS.md`, `LIVE_POSITION_SYNC_RESEARCH.md`

### 1.2 VLC 레이턴시 파이프라인 분석 (총 8–12초)

```
API 호출        ~200ms
CDN HEAD        ~100–300ms
매니페스트 파싱   ~100–200ms
VLC 초기화       ~10–50ms
플레이리스트 로드  ~200–500ms
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
라이브 엣지 거리   6,000ms ← 최대 기여자
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
세그먼트 다운로드   ~500–1,500ms
디먹서 초기화      ~50–200ms
디코더 초기화      ~100–300ms
첫 프레임 렌더링   ~16–33ms
```

**출처**: `VLC_LATENCY_ANALYSIS.md`

### 1.3 레이턴시 최적화 8대 제안

| # | 제안 | 절감 예상 | 상태 |
|---|------|-----------|------|
| 1 | adaptive-livedelay 6→3 | ~3초 | ✅ 적용 (normal: 3s, lowLatency: 2s) |
| 2 | network-caching 3500→2000 | ~1.5초 | ✅ 적용 (normal: 2500ms, lowLatency: 1500ms) |
| 3 | live-caching 2500→1500 | ~1초 | ✅ 적용 (normal: 2000ms, lowLatency: 1200ms) |
| 4 | clock-jitter 최적화 | — | ✅ 적용 |
| 5 | 세그먼트 프리페치 | — | 🔄 부분 구현 (HLSPrefetchService) |
| 6 | PDT 기반 동기화 | — | ✅ 구현 (PDTLatencyProvider + LowLatencyController) |
| 7 | 프레임 드롭 활성화 | — | ✅ lowLatency 프로파일 적용 |
| 8 | 재생 속도 기반 캐치업 | — | ✅ PID 제어기 구현 |

**출처**: `VLC_LATENCY_ANALYSIS.md`, `VIDEO_PLAYBACK_ARCHITECTURE.md`

### 1.4 LocalStreamProxy 이슈 (해결됨)

- **문제**: CDN이 fMP4에 대해 `Content-Type: video/MP2T` 를 반환 → VLC가 잘못된 MPEG2TS 디먹서 선택 → 재생 실패
- **원인**: 치지직 CDN 버그 (CMAF fMP4 세그먼트에 TS Content-Type)
- **해결**: LocalStreamProxy가 4가지 기능 수행:
  1. Content-Type 수정 (video/mp4로 교체)
  2. M3U8 URL 리라이트
  3. HTTP 헤더 인젝션 (Referer, User-Agent)
  4. 인증 쿠키 포워딩
- **추가 이슈**: VLC `:http-referrer` 버그 (#24622) — HLS 청크 요청에 전파 안 됨
- **PCR Late 문제** (해결됨): 프록시 경유 시 타이밍 정보 손상 → pts_delay 무한 증가

**출처**: `VLC_DIRECT_PLAYBACK_RESEARCH.md`, `VLC_BUFFERING_ANALYSIS.md`

### 1.5 1080p 안정성 문제 (60–70% → 95%+ 목표)

6대 문제:
1. **Variant URL 토큰 만료** (최대 원인) — CDN 인증 토큰이 일정 시간 후 만료
2. ABRController에 VLC 대역폭 데이터 미전달
3. 매니페스트 자동 갱신 없음
4. 화질 전환 임계값 부적절
5. 복구 시 만료된 URL 사용
6. URLSession을 VLC가 재사용하지 않음

**출처**: `VLC_1080P_NETWORK_ANALYSIS.md`

### 1.6 멀티라이브 이슈 요약 (9/16 해결, 56%)

- 모든 Critical(6건) 해결, High(3건) 미해결
- **3-tier CDN 방어**: 매니페스트 갱신(15–30초) → 스톨 워치독(10초) → 완전 재시작(55분)
- **VLCInstancePool**: Actor 기반, max 4 엔진 관리
- **핵심 미해결**: 메모리 압력 응답, 그리드 화질 자동 조정, 키보드 단축키

**출처**: `MULTILIVE_ANALYSIS_REPORT.md`

### 1.7 렌더링 파이프라인 분석

- **기본 vout**: `samplebufferdisplay` (AVSampleBufferDisplayLayer, 우선순위 600)
- **중요 교정**: 프레임별 메인 큐 디스패치는 **발생하지 않음**
- **실제 병목**: VLCKit NSTimer → 메인 스레드 delegate 콜백
- **VideoToolbox**: Zero-copy 디코딩 (GPU → IOSurface → CMSampleBuffer → AVSampleBufferDisplayLayer)

**출처**: `VLC_VOUT_MODULE_RESEARCH.md`

### 1.8 웹-앱 동기화 연구 (chzzkView-v1)

- **문제**: 웹 currentTime은 절대값(예: 1998초), VLC currentTime은 상대값(예: 22초) → ~1976초 차이
- **해결**: 절대 위치 비교 대신 **레이턴시(라이브 엣지로부터의 거리)** 비교
  - 웹 레이턴시 = `bufferedEnd - currentTime`
  - 앱 레이턴시 = `estimatedLatency`
  - `latencyDiff = appLatency - webLatency` (양수 = 앱이 뒤처짐)
- **동기화 조건**:
  | 범위 | 상태 | 동작 |
  |------|------|------|
  | <0.5초 | 완벽 | 유지 |
  | 0.5–2초 | 허용 | 관찰 |
  | 2–5초 | 보정 필요 | 점진적 캐치업 (1.1x/0.95x, 3회 연속) |
  | >5초 | 강제 | 시크 (5회 연속 확인) |

**출처**: `SYNC_LATENCY_V27.4.1.md`

### 1.9 싱크 유지 관리 시스템 (SyncMaintenanceManager)

- **유지 모드**: 연속 5회 동기화 성공 시 자동 진입
- **드리프트 예측 엔진**: 최근 20개 샘플 → 선형 회귀 → 5초 후 예측 → 0.8초 초과 시 선제적 보정
- **버퍼링 억제**: 버퍼 25% 이하 시 싱크 조정 중단 → 1.0x 고정 → 회복 후 재개
- **적응형 허용 오차**: `baseTolerance × qualityMultiplier × networkFactor`
  - 기본: 0.5초, 최소(Excellent): 0.3초, 최대(Poor): 1.5초
- **유지 모드 재생 속도**: 0.98x–1.02x (미세 조정)
- **기대 효과**:
  | 항목 | 개선 전 | 개선 후 |
  |------|---------|---------|
  | 동기화 성공률 | ~70% | ~95% |
  | 싱크 유지 시간 | 10–30초 | 60초+ |
  | 재생 속도 변동 | 0.95x–1.5x | 0.98x–1.02x |

**출처**: `SYNC_MAINTENANCE_v20.md`

---

## 2. 레이턴시 측정 방법 (코드 기반)

### 2.1 Method A: PDT 기반 절대 레이턴시 (CView_v2 — 권장)

**파일**: `Sources/CViewPlayer/PDTLatencyProvider.swift` (145줄)

```
공식: rawLatency = Date.now() - (lastSegment.PDT + lastSegment.duration)
```

- **구현**: Actor, 2초 폴링 주기
- **EWMA 스무딩**: alpha=0.3
- **범위 필터**: 0초 이상, 60초 미만
- **의존**: HLSManifestParser가 #EXT-X-PROGRAM-DATE-TIME 태그 파싱
- **HTTP 헤더**: Safari User-Agent, Chzzk Referer, 캐시 비활성화

**통합 위치**: `StreamCoordinator.startLowLatencySync()` (line 741)
- 미디어 플레이리스트 URL 해석 → PDTLatencyProvider 생성 → 초기 안정화 대기(최대 6초) → LowLatencyController에 Provider 클로저 전달
- PDT 실패 시 VLC 버퍼 latency (`duration - currentTime`) 폴백

### 2.2 Method B: PID 제어 기반 재생 속도 조정 (CView_v2)

**파일**: `Sources/CViewPlayer/LowLatencyController.swift` (~270줄)

```
PID 출력 = Kp × error + Ki × integral + Kd × derivative
rate = 1.0 + clamp(PID 출력, -0.1, 0.15)
```

| 파라미터 | default | ultraLow |
|----------|---------|----------|
| targetLatency | 3.0초 | 1.5초 |
| maxLatency | 10.0초 | 5.0초 |
| maxPlaybackRate | 1.15x | 1.2x |
| Kp | 0.8 | 1.2 |
| Ki | 0.1 | 0.15 |
| Kd | 0.05 | 0.1 |

- **SyncState**: idle → catchingUp (1.15x) → synced (1.0x) → slowingDown (0.9x) → seekRequired (시크)
- **폴링**: 2초 간격
- **시크 조건**: latency > maxLatency
- **콜백**: onRateChange, onSeekRequired

### 2.3 Method C: VLC 버퍼 기반 레이턴시 (CView_v2 — 폴백)

```
latency = playerEngine.duration - playerEngine.currentTime
```

- **문제점**: VLC의 duration/currentTime이 절대 시간이 아닌 상대 값이므로 정확도 낮음
- **용도**: PDT 사용 불가 시 폴백

### 2.4 웹 측 레이턴시 측정 — cheese-knife (chzzkView-v1)

**파일**: `chrome-extension-v2/injected.js` (v2.3)

3단계 우선순위:
1. **cheese-knife** (최우선): `corePlayer.srcObject._getLiveLatency()` — Chzzk 내부 API 직접 접근 (ms 단위)
2. **HLS.js**: `hls.latency` (초 단위 → ms 변환)
3. **버퍼 추정**: `bufferedEnd - currentTime` (초 → ms 변환, 60초 미만 필터)

### 2.5 웹 정밀 위치 추적 (chzzkView-v1 — v2.3)

**파일**: `chrome-extension-v2/injected.js`

```javascript
sample = {
    timestamp: performance.now(),
    currentTime: video.currentTime,
    playbackRate: video.playbackRate,
    bufferedEnd: video.buffered.end(last),
    actualPlaybackRate: posDiff / timeDiff,  // 실측 재생 속도
    playbackDrift: actual - nominal           // 드리프트
}
```

- 위치 샘플 히스토리: 최근 10개 유지
- 네트워크 지연 추정 (EWMA)

### 2.6 HLS 세그먼트 파일명 타임스탬프 파싱 (chzzkView-v1)

**파일**: `metrics-server/web-latency-devtools-collector.js`

```
파일명 패턴: {resolution}_{hash}_{timestamp}_{frameCount}_{unknown}_{segment}_{part}.m4v
```

- Chrome DevTools Protocol로 네트워크 요청 가로채기
- `timestamp` 필드 = Unix ms → `latency = Date.now() - timestamp`
- LL-HLS 매개변수 분석: `_HLS_msn`, `_HLS_part`

### 2.7 웹 포지션 스토어 (chzzkView-v1)

**파일**: `metrics-server/web-position-store.js` (v2.0)

- 채널별 최근 30개 엔트리 저장
- 필드: currentTime, preciseTime, duration, bufferLength, latency, liveEdge, playbackRate, actualPlaybackRate, 네트워크 타이밍
- EWMA 네트워크 지연 (0.7/0.3 가중)
- 분석 결과: `stable`, `unstable`, `high_latency`, `low_latency`

### 2.8 VLC 플레이어 프로파일 기반 캐싱 (CView_v2)

**파일**: `Sources/CViewPlayer/VLCPlayerEngine.swift`

| 프로파일 | networkCaching | liveCaching | adaptiveLiveDelay | stallThreshold | frameSkip |
|----------|---------------|-------------|-------------------|----------------|-----------|
| normal | 2500ms | 2000ms | 3초 | 45초 | false |
| lowLatency | 1500ms | 1200ms | 2초 | 30초 | true |
| multiLiveBG | 2000ms | 1500ms | 4초 | 45초 | true |
| highBuffer | 5000ms | 3000ms | 5초 | 60초 | false |

자동 전환 기준:
- healthScore > 0.9 → lowLatency
- 0.7–0.9 → normal
- < 0.7 → highBuffer

### 2.9 PerformanceMonitor (CView_v2)

**파일**: `Sources/CViewMonitoring/PerformanceMonitor.swift`

- `updateLatency(_ ms: Double)` — 외부에서 레이턴시 업데이트
- `MetricsSnapshot.latencyMs` — 현재 레이턴시 (ms)

### 2.10 MetricsForwarder (CView_v2)

**파일**: `Sources/CViewMonitoring/MetricsForwarder.swift`

- `AppLatencyPayload` → `apiClient.sendAppLatency()` — 레이턴시를 서버로 전송
- latencySource: "native"

---

## 3. 핵심 레이턴시 데이터 포인트 및 벤치마크

### 3.1 Chzzk HLS 특성

| 항목 | 값 | 출처 |
|------|-----|------|
| HLS targetDuration | 2초 | LIVE_POSITION_SYNC_RESEARCH |
| 세그먼트 길이 | 2–4초 | VLC_LATENCY_ANALYSIS |
| 포맷 | fMP4 (CMAF) | VLC_DIRECT_PLAYBACK_RESEARCH |
| PDT 태그 | `#EXT-X-PROGRAM-DATE-TIME` 지원 | HLSManifestParser.swift |
| CDN 도메인 | `ex-nlive-streaming.navercdn.com` | VLC_LATENCY_ANALYSIS |
| CDN Content-Type 버그 | `video/MP2T` (fMP4에 대해) | VLC_DIRECT_PLAYBACK_RESEARCH |

### 3.2 웹 레이턴시 벤치마크

| 항목 | 값 | 출처 |
|------|-----|------|
| hls.js targetLatency | 6초 (3×2s) | LIVE_POSITION_SYNC_RESEARCH |
| 웹 총 라이브 지연 | 3–5초 | VLC_LATENCY_ANALYSIS |
| cheese-knife API 레이턴시 | 직접 접근 (ms) | injected.js |
| 웹 버퍼 레이턴시 | `bufferedEnd - currentTime` | injected.js |

### 3.3 VLC/CView 레이턴시 벤치마크

| 항목 | 값 | 출처 |
|------|-----|------|
| VLC 총 라이브 지연 | 8–12초 | VLC_LATENCY_ANALYSIS |
| TTFP (Time To First Picture) | 2–4초 | VLC_LATENCY_ANALYSIS |
| 라이브 엣지 거리 (최대 기여자) | ~6,000ms | VLC_LATENCY_ANALYSIS |
| adaptive-livedelay (normal) | 3초 | VIDEO_PLAYBACK_ARCHITECTURE |
| adaptive-livedelay (lowLatency) | 2초 | VIDEO_PLAYBACK_ARCHITECTURE |
| networkCaching (normal) | 2500ms | VIDEO_PLAYBACK_ARCHITECTURE |
| networkCaching (lowLatency) | 1500ms | VIDEO_PLAYBACK_ARCHITECTURE |
| liveCaching (normal) | 2000ms | VIDEO_PLAYBACK_ARCHITECTURE |
| liveCaching (lowLatency) | 1200ms | VIDEO_PLAYBACK_ARCHITECTURE |

### 3.4 PID 제어 파라미터

| 항목 | default | ultraLow | 출처 |
|------|---------|----------|------|
| targetLatency | 3.0초 | 1.5초 | LowLatencyController.swift |
| maxLatency | 10.0초 | 5.0초 | LowLatencyController.swift |
| maxPlaybackRate | 1.15x | 1.2x | LowLatencyController.swift |
| minPlaybackRate | 0.9x | — | LowLatencyController.swift |
| PID Kp | 0.8 | 1.2 | LowLatencyController.swift |
| PID Ki | 0.1 | 0.15 | LowLatencyController.swift |
| PID Kd | 0.05 | 0.1 | LowLatencyController.swift |
| EWMA alpha | 0.3 | — | PDTLatencyProvider.swift |

### 3.5 동기화 임계값

| 항목 | 값 | 출처 |
|------|-----|------|
| 완벽 동기화 | <0.5초 | SYNC_LATENCY_V27.4.1 |
| 허용 범위 | 0.5–2.0초 | SYNC_LATENCY_V27.4.1 |
| 점진적 캐치업 | 2.0–5.0초 | SYNC_LATENCY_V27.4.1 |
| 강제 시크 | >5.0초 (5회 연속) | SYNC_LATENCY_V27.4.1 |
| 레이턴시 증가 경고 | 500ms | LATENCY_MONITORING doc |
| 유지 모드 기본 허용 오차 | 0.5초 | SYNC_MAINTENANCE_v20 |
| 유지 모드 최소 허용 오차 | 0.3초 | SYNC_MAINTENANCE_v20 |
| 유지 모드 최대 허용 오차 | 1.5초 | SYNC_MAINTENANCE_v20 |
| 드리프트 선제 보정 임계 | 0.8초 | SYNC_MAINTENANCE_v20 |
| 유지 모드 진입 조건 | 연속 5회 성공 | SYNC_MAINTENANCE_v20 |

### 3.6 모니터링 인터벌

| 항목 | 값 | 출처 |
|------|-----|------|
| PDT 폴링 | 2.0초 | PDTLatencyProvider.swift |
| 동기화 체크 | 2.0초 | LowLatencyController.swift |
| 스톨 워치독 | 20초 | VIDEO_PLAYBACK_ARCHITECTURE |
| 라이브 드리프트 모니터 | 60초 | VIDEO_PLAYBACK_ARCHITECTURE |
| CDN 토큰 선제 갱신 | 55분 | MULTILIVE_ANALYSIS_REPORT |
| 대시보드 timeseries 버킷 | 60초 | web-latency-dashboard/server.js |
| 대시보드 데이터 보존 | 24시간 | web-latency-dashboard/server.js |
| 드리프트 예측 샘플 수 | 20개 | SYNC_MAINTENANCE_v20 |
| 유지 모드 모니터링 | 1초 | SYNC_MAINTENANCE_v20 |

---

## 4. 기술 아키텍처 상세

### 4.1 CView_v2 전체 아키텍처

```
   ┌─────────────────────────────────────────────┐
   │               CViewApp Layer                 │
   │   MultiLiveView ─ MultiLiveAddSheet          │
   │   MultiLiveTabBar ─ MLPlayerPane             │
   │        ↓                                     │
   │   MultiLiveSessionManager (max 4 sessions)   │
   │   → MultiLiveSession (모델 + 상태)             │
   │        ↓                                     │
   │   PlayerViewModel → StreamCoordinator         │
   └──────────────────┬──────────────────────────┘
                      ↓
   ┌─────────────────────────────────────────────┐
   │             CViewPlayer Layer                │
   │                                              │
   │   StreamCoordinator (핵심 조율자)              │
   │   ├─ LocalStreamProxy (Content-Type 수정)     │
   │   ├─ HLSManifestParser (PDT 파싱)             │
   │   ├─ PDTLatencyProvider (절대 레이턴시)         │
   │   ├─ LowLatencyController (PID 속도 제어)      │
   │   ├─ ABRController (화질 전환)                 │
   │   ├─ HLSPrefetchService (세그먼트 프리페치)     │
   │   └─ VLCPlayerEngine (VLCKit 4.0)             │
   │       ├─ VLCStreamingProfile (프로파일)        │
   │       ├─ VLCMediaPlayer + VLCLayerHostView     │
   │       └─ Stall Detection + Recovery           │
   │                                              │
   │   VLCInstancePool (Actor, max 4 엔진)          │
   └──────────────────┬──────────────────────────┘
                      ↓
   ┌─────────────────────────────────────────────┐
   │           CViewMonitoring Layer              │
   │   PerformanceMonitor (latencyMs)             │
   │   MetricsForwarder (서버 전송)                │
   └─────────────────────────────────────────────┘
```

### 4.2 HLS 세그먼트 흐름

```
Chzzk CDN (ex-nlive-streaming.navercdn.com)
    ↓ HLS Master Playlist (.m3u8)
    ↓
LocalStreamProxy (NWListener, localhost:port)
    ├─ Content-Type: video/MP2T → video/mp4  (수정)
    ├─ M3U8 URL 리라이트                      (프록시 경유)
    ├─ HTTP 헤더 인젝션                        (Referer, UA)
    └─ 인증 쿠키 포워딩                         (NID_AUT, NID_SES)
    ↓
HLSManifestParser
    ├─ Master → Variant 목록 (해상도/대역폭)
    └─ Media → Segment 목록 (#EXT-X-PROGRAM-DATE-TIME 파싱)
    ↓
VLCPlayerEngine (VLCKit 4.0)
    ├─ VLCMedia(url:) + configureMediaOptions
    ├─ player.drawable = VLCLayerHostView
    └─ VideoToolbox HW 디코딩 → AVSampleBufferDisplayLayer
```

### 4.3 PDT 기반 레이턴시 측정 플로우

```
PDTLatencyProvider (Actor, 2초 폴링)
    ↓ HTTP GET 미디어 플레이리스트
    ↓
HLSManifestParser.parseMediaPlaylist()
    ↓ #EXT-X-PROGRAM-DATE-TIME → Segment.programDateTime
    ↓
liveEdge = lastSegment.PDT + lastSegment.duration
rawLatency = Date.now() - liveEdge
    ↓ EWMA (alpha=0.3) 스무딩
    ↓ 범위 필터 (0초 < latency < 60초)
    ↓
LowLatencyController.processLatency()
    ↓ EWMA → 히스토리 → PID 제어
    ↓
rate = 1.0 + clamp(PID_output, -0.1, 0.15)
    ↓
VLCPlayerEngine.setRate(rate)
```

### 4.4 chzzkView-v1 메트릭 수집 인프라

```
┌───────────────────────────────────────┐
│          Chrome Extension v2.3        │
│   injected.js (페이지 컨텍스트)         │
│   ├─ cheese-knife (_getLiveLatency)   │
│   ├─ hls.js latency                  │
│   ├─ 버퍼 추정 (bufferedEnd-currentTime)│
│   ├─ 정밀 위치 추적 (performance.now)   │
│   └─ 플레이어 화면 위치 수집             │
└───────────┬───────────────────────────┘
            ↓ HTTP POST
┌───────────────────────────────────────┐
│        Metrics Server (port 8080)     │
│   web-position-store.js (v2.0)       │
│   └─ 채널별 30개 히스토리 저장          │
│   web-latency-devtools-collector.js   │
│   └─ HLS 세그먼트 파일명 타임스탬프 파싱  │
└───────────┬───────────────────────────┘
            ↓
┌───────────────────────────────────────┐
│   web-latency-dashboard (Express+WS)  │
│   server.js (24h 보존, 1분 버킷)       │
│   public/index.html (Chart.js 대시보드) │
│   ├─ 엔진별 비교 (p50/p95 막대그래프)   │
│   ├─ 24h 시계열 (라인 차트)             │
│   ├─ p50, p90, p95, p99, jitter 통계  │
│   └─ WebSocket 실시간 업데이트           │
└───────────┬───────────────────────────┘
            ↓
┌───────────────────────────────────────┐
│   macOS App (chzzkView-v1)            │
│   ChromeExtensionBridge              │
│   WebLatencyBridge (3초 폴링)          │
│   InfluxDBForwarder (InfluxDB 저장)    │
│   AI Agent (품질 자동 최적화)            │
│   SyncMaintenanceManager (싱크 유지)    │
│   VLCWebPositionComparator (위치 비교)  │
└───────────────────────────────────────┘
```

### 4.5 chzzkView-v1 코드 규모

| 범주 | 파일 수 | 코드 줄 | 핵심 파일 |
|------|---------|---------|-----------|
| VLC 핵심 렌더링 | 7 | 3,306 | VLCPlayerView.swift (1,039) |
| 엔진 어댑터 | 2 | 2,907 | VLCPlayerEngineIntegration.swift (1,997) |
| 외부 VLC 동기화 | 4 | 3,613 | ExternalVLCController.swift (1,713) |
| HLS/레이턴시 최적화 | 4 | 2,173 | HLSPlayerController.swift (1,375) |
| 플레이어 인프라 | 11 | 8,252 | LivePlayerCoreOptimizer.swift (1,800) |
| **전체 VLC 관련** | **30** | **31,714** | — |
| **전체 프로젝트** | **516** | **305,404** | — |

**출처**: `VLC_CODE_ANALYSIS_REPORT.md`

### 4.6 chzzkView-v1 발견된 Critical 이슈 3건

1. **C-1**: NSEvent 모니터 메모리 누수 — `addLocalMonitorForEvents` 반환값 미저장, `onDisappear`에서 미제거 → 핸들러 누적
2. **C-2**: Notification 채널 불일치 — `vlcTogglePlayback`/`vlcSeekToLive` 발송하지만 Coordinator에 구독 없음 → 키보드 재생제어 미동작
3. **C-3**: VLC 옵션 충돌 — `VLCPlayerView`는 프레임 드롭 비활성화, `VLCPlayerEngineIntegration`은 활성화 → 엔진별 일관성 없는 재생 특성

**출처**: `VLC_CODE_ANALYSIS_REPORT.md`

### 4.7 PDT 테스트 스트림 생성기

**파일**: `scripts/generate_pdt_test_stream.sh`

- FFmpeg 기반 PDT 포함 HLS 테스트 스트림 생성
- 옵션: `-hls_flags program_date_time` → `#EXT-X-PROGRAM-DATE-TIME` 태그 자동 삽입
- targetDuration=2초, 세그먼트 10개 유지
- Python HTTP 서버 (포트 8088)
- 용도: PDTLatencyProvider 테스트, VLC PDT 동기화 검증

---

## 5. 미연구 영역 및 갭 분석

### 5.1 측정 관련 갭

| 영역 | 현재 상태 | 필요 사항 |
|------|----------|-----------|
| **LL-HLS (Low-Latency HLS)** | HLSManifestParser가 PartialSegment/ServerControl/PreloadHint 파싱 지원 | LL-HLS 부분 세그먼트 실제 사용 여부 미확인, Chzzk 서버의 LL-HLS 지원 상태 미조사 |
| **E2E 레이턴시** | 앱 측(PDT→렌더링)만 측정 | 인코더→CDN 구간의 레이턴시 측정 불가 (치지직 서버 접근 필요) |
| **치지직 내부 API** | cheese-knife `_getLiveLatency()` 사용 | API 반환값의 정확한 정의 (무엇 기준인지) 미확인 |
| **멀티 CDN 경로** | 단일 CDN 도메인만 확인 | CDN 에지 서버 선택 로직, 리전별 레이턴시 차이, CDN 홉 수 미조사 |
| **렌더링 레이턴시** | VLC vout 모듈 분석 완료 | **디코더 출력 → 화면 vsync** 구간의 정밀 측정 없음 |

### 5.2 아키텍처 관련 갭

| 영역 | 현재 상태 | 필요 사항 |
|------|----------|-----------|
| **AVPlayer 레이턴시** | AVPlayerEngine 존재 (915줄) | AVPlayer 기반 레이턴시 측정/비교 데이터 없음 |
| **VLCKit 3.6 vs 4.0** | CView_v2=VLCKit 4.0, chzzkView-v1=VLCKit 3.6 | 두 버전 간 레이턴시 차이 미측정 |
| **PDT 안정화 시간** | 최대 6초 대기 | 실측 안정화 소요 시간 데이터 없음 |
| **PID 튜닝** | default/ultraLow 두 프리셋 | 실제 스트림에서의 PID 응답 특성 (오버슈트, 정착 시간) 미측정 |
| **메모리 영향** | 멀티라이브 4세션 | GPU 메모리 / 시스템 메모리 사용량 vs 레이턴시 상관관계 미분석 |

### 5.3 인프라 관련 갭

| 영역 | 현재 상태 | 필요 사항 |
|------|----------|-----------|
| **InfluxDB 실사용** | 코드 존재 (InfluxDBForwarder) | 실제 운용 데이터 / 장기 트렌드 분석 결과 없음 |
| **Chrome Extension v2.3** | 코드 분석 완료 | Safari Extension 대응 코드 미확인 (gitignored) |
| **AI Agent 최적화** | 품질 자동 프리셋 선택 구현 | AI 최적화 효과 정량적 검증 데이터 없음 |
| **Docker 메트릭 서버** | docker-compose.yml 존재 | 실제 배포/운용 상태 미확인 |

### 5.4 CView_v2 미읽은 코드 파일 (잠재적 추가 정보)

| 파일 | 예상 내용 |
|------|-----------|
| `ABRController.swift` | 화질 전환과 레이턴시 트레이드오프 |
| `HLSPrefetchService.swift` | 세그먼트 프리페치로 TTFP 단축 |
| `VLCPlayerEngine.swift` (전체) | stall detection, 프로파일 전환, 메트릭 수집 상세 |
| `LocalStreamProxy.swift` (전체) | 프록시 레이턴시 오버헤드 상세 |
| `CVIEW_TECHNICAL_DOCUMENT.md` | 추가 아키텍처 정보 가능 |
| `CVIEW_V2_COMPREHENSIVE_RESEARCH_REPORT.md` | 추가 연구 데이터 가능 |

### 5.5 핵심 미해결 질문

1. **치지직이 LL-HLS를 지원하는가?** — HLSManifestParser는 파싱 지원하지만 실제 LL-HLS 매니페스트 수신 여부 미확인
2. **VLC 4.0에서 PDT 직접 접근이 가능한가?** — 현재는 별도 HTTP 폴링으로 PDT를 가져오는데, VLC가 내부적으로 PDT를 노출하는지 미조사
3. **adaptive-livedelay=2 이하가 안정적인가?** — lowLatency 프로파일에서 2초를 사용하지만, 1초 이하로 줄였을 때의 안정성 미검증
4. **프록시 경유 레이턴시 오버헤드는 얼마인가?** — LocalStreamProxy의 추가 지연 시간 정밀 측정 없음
5. **cheese-knife `_getLiveLatency()`의 기준점은?** — 인코딩 시점인지 CDN 인제스트 시점인지 정의 미확인

---

## 부록 A: 문서 출처 인덱스

### CView_v2 연구 문서
| 문서 | 주요 내용 |
|------|-----------|
| `LIVE_POSITION_SYNC_RESEARCH.md` | 웹-앱 동기화, PDT 접근법, 3가지 동기화 방법 |
| `VLC_LATENCY_ANALYSIS.md` | 전체 파이프라인 타이밍, 8대 최적화 제안 |
| `VLC_BUFFERING_ANALYSIS.md` | PCR Late 해결, 미해결 이슈 목록 |
| `VLC_DIRECT_PLAYBACK_RESEARCH.md` | CDN Content-Type 버그, 프록시 아키텍처 |
| `VLC_1080P_NETWORK_ANALYSIS.md` | 1080p 유지 6대 문제 |
| `VLC_VOUT_MODULE_RESEARCH.md` | 렌더링 파이프라인, vout 모듈 분석 |
| `VIDEO_PLAYBACK_ARCHITECTURE.md` | 프로파일 시스템, 스톨 복구, 자동 전환 |
| `MULTILIVE_ANALYSIS_REPORT.md` | 멀티라이브 16개 이슈, 아키텍처 개선안 |

### chzzkView-v1 연구 문서
| 문서 | 주요 내용 |
|------|-----------|
| `docs/SYNC_LATENCY_V27.4.1.md` | 웹-앱 레이턴시 비교 동기화 |
| `docs/SYNC_MAINTENANCE_v20.md` | 싱크 유지 관리자, 드리프트 예측, 버퍼링 억제 |
| `docs/LATENCY_MONITORING_WITH_POSITION_SYNC.md` | AI Agent 레이턴시 모니터링, 위치 기반 최적화 |
| `docs/STREAMING_OPTIMIZATION_PLAN.md` | 3단계 최적화 전략 |
| `docs/EXTERNAL_VLC_SYNC_GUIDE.md` | 외부 VLC HTTP 인터페이스 동기화 |
| `docs/VLC_CODE_ANALYSIS_REPORT.md` | 30파일/31,714줄 VLC 코드 분석, Critical 3건 |
| `docs/WEB_METRICS_IMPLEMENTATION_SUMMARY.md` | 웹 메트릭 통합 구현 완료 내역 |
| `docs/WEB_METRICS_INTEGRATION.md` | 크롬 확장 ↔ 앱 메트릭 연동 가이드 |
| `docs/PROJECT_RESEARCH_REPORT.md` | 전체 프로젝트 종합 분석 (516파일, 305,404줄) |

### 소스 코드 (레이턴시 핵심)
| 파일 | 역할 |
|------|------|
| `CView_v2/Sources/CViewPlayer/PDTLatencyProvider.swift` | PDT 절대 레이턴시 Actor |
| `CView_v2/Sources/CViewPlayer/LowLatencyController.swift` | PID 제어 + EWMA 속도 조정 Actor |
| `CView_v2/Sources/CViewPlayer/StreamCoordinator.swift` | PDT+PID 통합 조율 |
| `CView_v2/Sources/CViewPlayer/HLSManifestParser.swift` | PDT 파싱 + LL-HLS 지원 |
| `chzzkView-v1/chrome-extension-v2/injected.js` | cheese-knife + HLS.js + 버퍼 레이턴시 |
| `chzzkView-v1/metrics-server/web-latency-devtools-collector.js` | 세그먼트 파일명 타임스탬프 |
| `chzzkView-v1/metrics-server/web-position-store.js` | 웹 위치 스토어 + EWMA |
| `chzzkView-v1/web-latency-dashboard/server.js` | Express+WS 대시보드 서버 |
| `chzzkView-v1/scripts/generate_pdt_test_stream.sh` | PDT 테스트 스트림 생성기 |
