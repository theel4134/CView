# CView 앱 ↔ 웹 라이브 스트리밍 레이턴시 동기화 연구문서

> **작성일**: 2025-07  
> **대상 플랫폼**: CView_v2 (macOS 네이티브) / 웹 (hls.js 기반)  
> **목표**: 앱과 웹에서 동일한 라이브 스트림을 재생할 때, 영상 위치(재생 시점)가 동일선상에 놓이도록 하는 동기화 로직 설계

---

## 목차

1. [문제 정의](#1-문제-정의)
2. [현재 앱 아키텍처 분석](#2-현재-앱-아키텍처-분석)
3. [웹 플레이어(hls.js) 아키텍처 분석](#3-웹-플레이어hlsjs-아키텍처-분석)
4. [핵심 파라미터 비교](#4-핵심-파라미터-비교)
5. [레이턴시 차이 원인 분석](#5-레이턴시-차이-원인-분석)
6. [동기화 전략 설계](#6-동기화-전략-설계)
7. [구현 방안](#7-구현-방안)
8. [예상 결과 및 한계](#8-예상-결과-및-한계)
9. [결론 및 권장사항](#9-결론-및-권장사항)

---

## 1. 문제 정의

### 1.1 현상

동일한 치지직(Chzzk) 라이브 스트림을 CView 앱과 웹 브라우저에서 동시 시청할 때, **영상 재생 시점이 수 초 이상 차이**가 발생한다. 이는 각 플레이어가 서로 다른 레이턴시 타겟과 동기화 전략을 사용하기 때문이다.

### 1.2 목표

| 항목 | 목표 |
|------|------|
| 재생 시점 차이 | ±0.5초 이내 |
| 기준 시각 | `#EXT-X-PROGRAM-DATE-TIME` (PDT) 절대 시각 |
| 적용 범위 | VLCPlayerEngine (1차), AVPlayerEngine (2차) |

### 1.3 제약 조건

- 서버 측(CDN / 인코더) 변경 불가 — 클라이언트만 제어
- 치지직 HLS 스트림은 표준 HLS (LL-HLS 아님) — 세그먼트 단위 2~6초
- VLCKit 4.0의 HLS 구현은 LL-HLS 파트 로딩 미지원

---

## 2. 현재 앱 아키텍처 분석

### 2.1 레이턴시 제어 체인

```
CDN → LocalStreamProxy → VLCPlayerEngine → LowLatencyController → 재생 출력
         ↓                      ↓                    ↓
    M3U8 캐싱(0.3s TTL)   VLC 내부 버퍼링     PID 기반 재생속도 조절
    Content-Type 보정      (프로파일별)        (0.90x ~ 1.15x)
```

### 2.2 LowLatencyController (PID 기반 동기화)

**위치**: `Sources/CViewPlayer/LowLatencyController.swift`

PID(Proportional-Integral-Derivative) 제어기를 사용하여 재생 속도를 연속적으로 미세 조정한다.

#### 프리셋 파라미터

| 파라미터 | default | ultraLow |
|----------|---------|----------|
| **targetLatency** | 3.0초 | 1.5초 |
| Kp (비례) | 0.8 | 1.0 |
| Ki (적분) | 0.12 | 0.15 |
| Kd (미분) | 0.06 | 0.08 |
| maxRate | 1.15x | 1.20x |
| minRate | 0.90x | 0.85x |
| catchUpThreshold | 1.2초 | 1.0초 |
| slowDownThreshold | 0.5초 | 0.3초 |
| EWMA alpha | 0.3 | 0.3 |
| 모니터 간격 | 2.0초 | 2.0초 |

#### 레이턴시 측정 방식

```
latency = now() - (lastSegment.PDT + lastSegment.duration) - currentPlaybackTime
```

- `PDTLatencyProvider`가 2초 간격으로 M3U8에서 `#EXT-X-PROGRAM-DATE-TIME` 파싱
- EWMA(지수가중이동평균, α=0.3)으로 평활화
- 유효 범위: -2초 ~ 60초 (범위 밖 15회 연속 시 자동 중단)

#### 재생 속도 결정 로직

```
error = measuredLatency - targetLatency
pidOutput = Kp × error + Ki × ∫error + Kd × Δerror/Δt
rateAdjustment = pidOutput × 0.1
newRate = clamp(1.0 + rateAdjustment, minRate, maxRate)
```

### 2.3 VLC 스트리밍 프로파일

| 파라미터 | ultraLow | lowLatency | multiLive |
|----------|----------|------------|-----------|
| networkCaching | 300ms | 500ms | 1000ms |
| liveCaching | 300ms | 500ms | 1000ms |
| crAverage | 20ms | 30ms | 30ms |
| clockJitter | 0µs | 5000µs | 10000µs |
| decoderThreads | 4 | 4 | 1 |
| dropLateFrames | ✓ | ✓ | ✓ |
| clock-synchro | 0 | 0 | 0 |

**핵심**: `clock-synchro=0`은 VLC의 내부 클럭 동기화를 비활성화하여 레이턴시를 줄인다. 대신 LowLatencyController가 외부에서 동기화를 담당한다.

### 2.4 AVPlayer 캐치업 설정

| 프리셋 | targetLatency | maxLatency | maxCatchupRate | forwardBuffer |
|--------|---------------|------------|----------------|---------------|
| ultraLow | 2.0초 | 5.0초 | 1.5x | 2.0초 |
| lowLatency | 3.0초 | 8.0초 | 1.3x | 3.0초 |
| balanced | 5.0초 | 12.0초 | 1.2x | 7.0초 |
| stable | 8.0초 | 20.0초 | 1.1x | 12.0초 |

### 2.5 프록시 계층 지연

`LocalStreamProxy`는 추가 지연을 발생시킨다:

- M3U8 캐싱 TTL: **0.3초** (중복 요청 제거 목적)
- TCP loopback 왕복: ~0.1ms (무시 가능)
- Content-Type 재작성: 무시 가능
- **총 프록시 지연**: ~0.3초 (M3U8 캐시 히트 시)

### 2.6 매니페스트 갱신 주기

| 프로파일 | 갱신 주기 |
|----------|-----------|
| ultraLow | 8초 |
| lowLatency | 10초 |
| multiLive | 20초 |

갱신 간격이 길수록 새 세그먼트 발견이 늦어져 레이턴시가 증가할 수 있다.

---

## 3. 웹 플레이어(hls.js) 아키텍처 분석

### 3.1 동기화 메커니즘 개요

hls.js는 앱과 **근본적으로 다른 접근**을 사용한다:

| 구분 | CView 앱 (VLC) | hls.js (웹) |
|------|----------------|-------------|
| **동기화 방식** | PID 기반 연속 속도 조절 | Seek 기반 (기본), 선택적 속도 조절 |
| **기본 동작** | 항상 속도 조절 활성 | 속도 조절 비활성 (`maxLiveSyncPlaybackRate=1`) |
| **지연 초과 대응** | 점진적 속도 증가 | 라이브 엣지로 즉시 Seek |
| **레이턴시 측정** | PDT 기반 EWMA | PDT + drift 계산 |

### 3.2 핵심 설정 파라미터

#### 라이브 동기화

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `lowLatencyMode` | `true` | LL-HLS 파트 로딩 활성화, `PART-HOLD-BACK`에서 시작 |
| `liveSyncDurationCount` | `3` | 라이브 엣지 대비 지연 = `3 × EXT-X-TARGETDURATION` |
| `liveSyncDuration` | `undefined` | 초 단위 직접 지정 (설정 시 count보다 우선) |
| `liveMaxLatencyDurationCount` | `Infinity` | 초과 시 Seek — 기본값 Infinity = 비활성 |
| `liveMaxLatencyDuration` | `undefined` | 초 단위 직접 지정 |
| `maxLiveSyncPlaybackRate` | `1` | 속도 조절 배율 상한 (**기본 1 = 비활성**) |
| `liveSyncOnStallIncrease` | `1` | 스톨 발생 시 targetLatency 증가량 (초) |
| `liveSyncMode` | `'edge'` | `'edge'` = 즉시 Seek, `'buffered'` = 버퍼 내 Seek |

#### 버퍼

| 파라미터 | 기본값 |
|----------|--------|
| `maxBufferLength` | 30초 |
| `maxMaxBufferLength` | 600초 |
| `maxBufferSize` | 60MB |
| `backBufferLength` | Infinity |

#### ABR (적응 비트레이트)

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `abrEwmaFastLive` | 3.0 | 빠른 대역폭 추정 (짧은 윈도우) |
| `abrEwmaSlowLive` | 9.0 | 느린 대역폭 추정 (긴 윈도우) |
| `abrBandWidthFactor` | 0.95 | 다운그레이드 안전 계수 |
| `abrBandWidthUpFactor` | 0.7 | 업그레이드 안전 계수 |

#### 스톨 감지

| 파라미터 | 기본값 |
|----------|--------|
| `highBufferWatchdogPeriod` | 3초 |
| `detectStallWithCurrentTimeMs` | 1250ms |
| `maxStarvationDelay` | 4초 |
| `maxLoadingDelay` | 4초 |

### 3.3 타겟 레이턴시 계산

hls.js의 실제 타겟 레이턴시는 다음과 같이 결정된다:

```javascript
// 기본 계산 (liveSyncDuration 미설정 시)
targetLatency = liveSyncDurationCount × TARGETDURATION + (liveSyncOnStallIncrease × stallCount)

// 예: TARGETDURATION=2초, stallCount=0
targetLatency = 3 × 2 + 0 = 6.0초

// 예: TARGETDURATION=4초, stallCount=0  
targetLatency = 3 × 4 + 0 = 12.0초
```

**LL-HLS 모드** (`lowLatencyMode=true`이고 서버가 LL-HLS 지원 시):
```javascript
targetLatency = PART-HOLD-BACK  // 서버가 지정한 값 (통상 1~3초)
```

### 3.4 실제 치지직 웹 플레이어 동작 (추정)

치지직 웹 플레이어는 hls.js를 커스터마이징하여 사용하며, 다음 설정을 사용할 가능성이 높다:

```javascript
{
  lowLatencyMode: false,       // 치지직은 표준 HLS
  liveSyncDurationCount: 3,    // 기본값 유지
  // TARGETDURATION = 2초 (치지직 표준)
  // → targetLatency ≈ 6.0초
}
```

> **주의**: 치지직 웹의 실제 설정은 리버스 엔지니어링 없이는 정확히 알 수 없다. 위는 hls.js 기본값 기반 추정이다.

---

## 4. 핵심 파라미터 비교

### 4.1 레이턴시 타겟 비교

| 구분 | CView (default) | CView (ultraLow) | hls.js (기본) | hls.js (LL-HLS) |
|------|-----------------|-------------------|---------------|------------------|
| **타겟 레이턴시** | 3.0초 | 1.5초 | ~6.0초* | PART-HOLD-BACK |
| **최대 레이턴시** | 없음 (PID 수렴) | 없음 | Infinity | Infinity |
| **초과 시 동작** | 속도 점진 조절 | 속도 점진 조절 | 없음 (기본) | 없음 (기본) |

*\* `TARGETDURATION=2초` 가정*

### 4.2 동기화 메커니즘 비교

```
                    CView 앱                          hls.js (웹)
                    ────────                          ──────────
시작 시점:    라이브 엣지 - 버퍼           라이브 엣지 - liveSyncDurationCount × targetDuration

정상 재생:    PID 제어로 연속 조절           1.0x 고정 (기본)
              (0.90x ~ 1.15x)              또는 1.0x ~ maxLiveSyncPlaybackRate

지연 증가:    PID error 증가 →              liveMaxLatencyDuration 초과 시
              자동 속도 증가                  라이브 엣지로 Seek

지연 감소:    PID error 감소 →              자동 (drift 보정)
              자동 속도 감소

스톨 발생:    pauseForBuffering() →          targetLatency += liveSyncOnStallIncrease
              rate=1.0, 복구 후 재개          (스톨마다 1초씩 타겟 증가)
```

### 4.3 버퍼 전략 비교

| 구분 | CView (VLC lowLatency) | hls.js (기본) |
|------|------------------------|---------------|
| 네트워크 캐시 | 500ms | — |
| 라이브 캐시 | 500ms | — |
| 최대 버퍼 | VLC 내부 관리 | 30초 |
| Forward 버퍼 | 프로파일별 | maxBufferLength |

### 4.4 ABR 비교

| 구분 | CView 앱 | hls.js |
|------|----------|--------|
| EWMA Fast | α=0.5 | 3.0 (half-life) |
| EWMA Slow | α=0.1 | 9.0 (half-life) |
| 안전 계수 (↓) | 0.7 | 0.95 |
| 안전 계수 (↑) | — | 0.7 |
| 최소 전환 간격 | 5초 | — |
| 초기 대역폭 | 5Mbps | — |

---

## 5. 레이턴시 차이 원인 분석

### 5.1 주요 원인 (큰 영향 순)

#### ① 타겟 레이턴시 차이 (~3초 격차)

가장 큰 원인. 앱은 **3.0초**를 목표로 하지만, 웹은 **~6.0초**(표준 HLS 기준)를 목표로 한다.

```
앱 재생 시점:  ├─────3초────→ 라이브 엣지
웹 재생 시점:  ├──────────6초──────────→ 라이브 엣지
차이:                    ~3초
```

#### ② 동기화 전략 차이

- **앱**: PID가 지속적으로 속도를 조절하여 타겟에 수렴 → 타겟 근처에서 안정적으로 유지
- **웹(기본)**: 속도 조절 없음(`maxLiveSyncPlaybackRate=1`) → 자연 drift에 의해 점진적으로 뒤처짐 → `liveMaxLatencyDuration` 도달 시 Seek로 점프

#### ③ 프록시 계층 지연 (~0.3초)

앱의 `LocalStreamProxy` M3U8 캐싱이 0.3초 TTL을 사용. 웹은 브라우저가 CDN에 직접 요청.

#### ④ 매니페스트 갱신 주기 차이

- **앱**: 10초 간격 (lowLatency 프로파일)
- **hls.js**: `EXT-X-TARGETDURATION`의 절반 간격 (표준 HLS), 또는 `PART-TARGET`의 배수 (LL-HLS)

갱신이 느리면 새 세그먼트 발견이 지연되어 재생이 뒤처진다.

#### ⑤ 스톨 회복 전략 차이

- **앱**: 스톨 중 rate=1.0으로 고정, 복구 후 PID 재개 (동일 타겟 유지)
- **웹**: 스톨마다 `targetLatency += 1초` (보수적으로 타겟 후퇴)

### 5.2 레이턴시 시나리오별 예상 차이

| 시나리오 | 앱 레이턴시 | 웹 레이턴시 | 차이 |
|----------|-------------|-------------|------|
| 안정적 네트워크 | ~3.0초 | ~6.0초 | ~3.0초 |
| 1회 스톨 후 | ~3.0초 | ~7.0초 | ~4.0초 |
| 3회 스톨 후 | ~3.0초 | ~9.0초 | ~6.0초 |
| ultraLow 프로파일 | ~1.5초 | ~6.0초 | ~4.5초 |

---

## 6. 동기화 전략 설계

### 6.1 전략 A: 앱을 웹 기준으로 맞추기 (앱 레이턴시 증가)

#### 개념

앱의 타겟 레이턴시를 hls.js의 기본값과 동일하게 설정한다.

```
새 타겟 = liveSyncDurationCount × TARGETDURATION
       = 3 × 2초 = 6.0초
```

#### 구현

```swift
// LowLatencyController.Configuration 새 프리셋 추가
static let webSync = Configuration(
    targetLatency: 6.0,       // hls.js 기본과 동일
    maxPlaybackRate: 1.15,    // PID 유지
    minPlaybackRate: 0.90,
    catchUpThreshold: 2.0,
    slowDownThreshold: 1.0,
    kp: 0.5,                  // 느슨한 제어 (타겟이 여유 있으므로)
    ki: 0.08,
    kd: 0.04
)
```

#### 장단점

| 장점 | 단점 |
|------|------|
| 구현 간단 (파라미터 변경만) | 앱의 저지연 이점 상실 |
| 안정적 재생 | 사용자 체감 지연 증가 (~6초) |
| 웹과 근사한 시점 | 정확한 PDT 동기화 아님 |

### 6.2 전략 B: 웹을 앱 기준으로 맞추기 (웹 레이턴시 감소) — 웹 커스텀 플레이어 운영 시

#### 개념

hls.js 설정을 앱과 동일한 타겟으로 조정한다.

```javascript
const hls = new Hls({
  liveSyncDuration: 3.0,              // 앱의 targetLatency와 동일
  liveMaxLatencyDuration: 8.0,        // 초과 시 Seek
  maxLiveSyncPlaybackRate: 1.15,      // 앱의 maxRate와 동일
  liveSyncOnStallIncrease: 0.5,       // 스톨 후 타겟 증가 최소화
});
```

#### 장단점

| 장점 | 단점 |
|------|------|
| 앱의 저지연 유지 | 웹 플레이어 커스터마이징 필요 |
| 양쪽 동일 타겟 | 웹 환경에서 불안정할 수 있음 |
| hls.js 내장 기능 활용 | 치지직 공식 웹은 제어 불가 |

### 6.3 전략 C: PDT 절대 시각 기반 동기화 (권장)

#### 개념

양 플레이어 모두 `#EXT-X-PROGRAM-DATE-TIME`(PDT)을 기준점으로 사용하여, **절대 시각 기준 동일한 오프셋**에서 재생한다.

```
라이브 인코더 시각:  T₀ (PDT)
앱 재생 시각:        T₀ + offset
웹 재생 시각:        T₀ + offset
─────────────────────────────────
offset = 합의된 공통 타겟 레이턴시
```

#### 핵심 알고리즘

```
1. 공통 타겟 레이턴시 결정:
   commonTarget = max(앱_최소_안정_레이턴시, 웹_최소_안정_레이턴시)
   → 실측 기반으로 4.0 ~ 5.0초 권장

2. PDT 기반 현재 레이턴시 계산 (양쪽 동일 공식):
   latency = now() - playingDate
   여기서 playingDate = 현재 재생 중인 프레임의 PDT 시각

3. 오차 계산:
   error = latency - commonTarget

4. 보정:
   앱: PID 기반 rate 조절 (기존 로직 활용)
   웹: maxLiveSyncPlaybackRate > 1 설정 + hls.js 내장 catchup
```

#### 상세 설계

```
┌──────────────┐     PDT 파싱     ┌─────────────────┐
│  HLS 세그먼트  │ ──────────────→ │  PDTLatencyProvider │
│  (CDN)        │                 │  latency 계산      │
└──────────────┘                 └────────┬──────────┘
                                          │
                                   latency값
                                          │
                    ┌─────────────────────┤
                    │                     │
              ┌─────▼────────┐    ┌──────▼──────────┐
              │ 앱 (VLC)      │    │ 웹 (hls.js)      │
              │               │    │                   │
              │ PID 제어       │    │ PDT latency 계산  │
              │ rate 조절      │    │ hls.latency       │
              │ target=4.5초  │    │ liveSyncDuration   │
              │               │    │   = 4.5초          │
              └───────────────┘    └───────────────────┘
```

#### 구현 요구사항

**앱 측**:
1. `LowLatencyController`에 "webSync" 프리셋 추가 (targetLatency = 공통값)
2. PDTLatencyProvider 측정 정밀도 검증 (±0.5초 이내)
3. EWMA 평활화 파라미터 유지 (급격한 변동 방지)

**웹 측** (커스텀 플레이어 운용 시):
1. `liveSyncDuration` = 공통 타겟값
2. `maxLiveSyncPlaybackRate` = 1.1 (보수적 속도 조절)
3. `liveMaxLatencyDuration` = 공통 타겟 + 3초 (Seek 트리거)
4. `hls.playingDate` API로 PDT 기반 레이턴시 모니터링

#### 장단점

| 장점 | 단점 |
|------|------|
| 절대 시각 기준 → 가장 정확 | PDT 정밀도에 의존 |
| 양쪽 독립 구현 가능 | 공통 타겟 결정에 실측 필요 |
| 기존 PID 로직 재활용 | CDN 캐시 차이로 ±0.5초 오차 |
| 스케일러블 (다중 클라이언트) | VLC의 PDT 접근성 제한적 |

### 6.4 전략 D: 하이브리드 접근 (최적)

전략 C를 기반으로, 앱과 웹 각각의 강점을 살린 실용적 접근.

#### 설계 원칙

1. **공통 기준점**: PDT 절대 시각
2. **앱**: 기존 PID를 유지하되, 타겟을 조절 가능하게 확장
3. **웹**: hls.js 내장 기능만 활용 (추가 로직 최소화)
4. **타겟 공유**: 서버를 통해 "공통 타겟 레이턴시" 값을 양쪽에 전달 가능

```
┌─────────┐   최적 타겟 계산    ┌────────────────┐
│ 공통 설정 │ ←────────────── │ 네트워크 상태 판단 │
│ server   │                  │ (CDN RTT 등)     │
└────┬─────┘                  └────────────────┘
     │ targetLatency = N초
     │
     ├──────────────► 앱: LowLatencyController.targetLatency = N
     │
     └──────────────► 웹: hls.liveSyncDuration = N
```

---

## 7. 구현 방안

### 7.1 Phase 1: 앱 측 조정 (즉시 적용 가능)

#### 7.1.1 LowLatencyController에 webSync 프리셋 추가

```swift
// Sources/CViewPlayer/LowLatencyController.swift

public static let webSync = Configuration(
    targetLatency: 5.0,        // 웹 기본(~6초)보다 약간 적극적
    maxPlaybackRate: 1.10,     // 부드러운 조절
    minPlaybackRate: 0.93,
    catchUpThreshold: 1.5,     // 타겟+1.5초부터 가속 시작
    slowDownThreshold: 0.8,    // 타겟-0.8초부터 감속 시작
    kp: 0.6,
    ki: 0.10,
    kd: 0.05,
    ewmaAlpha: 0.3,
    syncMonitorInterval: 2.0,
    rateChangeDelta: 0.005
)
```

#### 7.1.2 StreamCoordinator에 동기화 모드 선택 추가

```swift
// Sources/CViewPlayer/StreamCoordinator.swift

enum SyncMode {
    case lowLatency      // 기존: targetLatency = 3.0초
    case ultraLowLatency // 기존: targetLatency = 1.5초
    case webSync         // 신규: targetLatency = 5.0초
    case custom(seconds: TimeInterval)  // 사용자 지정
}
```

#### 7.1.3 VLC 매니페스트 갱신 주기 단축

웹과의 세그먼트 발견 시점 차이를 줄이기 위해:

```swift
// VLCStreamingProfile 확장
case webSync  // manifestRefreshInterval = TARGETDURATION (보통 2초)
```

현재 10초 → 2초로 단축하면 새 세그먼트 발견이 최대 8초 빨라진다.

### 7.2 Phase 2: PDT 기반 절대 동기화 (정밀 제어)

#### 7.2.1 PDTLatencyProvider 정밀도 개선

```swift
// 현재: M3U8의 마지막 세그먼트 PDT 사용
// 개선: VLC 재생 위치의 실제 PDT 추적

// VLC의 재생 시간 → PDT 매핑
func playingDate(at playbackTime: TimeInterval) -> Date? {
    // M3U8 세그먼트 목록에서 playbackTime에 해당하는 세그먼트 찾기
    // 해당 세그먼트의 PDT + (playbackTime - segmentStartTime) 반환
}

// 정밀 레이턴시 = now() - playingDate(at: currentTime)
```

#### 7.2.2 앱-웹 동기화 검증 인터페이스

개발/디버그 용도로 양쪽 레이턴시를 실시간 비교하는 도구:

```
앱 OSD 표시:
  PDT Latency: 4.8s | Target: 5.0s | Rate: 1.02x | Δweb: +0.3s

웹 콘솔 표시:
  hls.latency: 5.1s | target: 5.0s | drift: +0.02s/min
```

### 7.3 Phase 3: 동적 타겟 조절 (고급)

네트워크 상태에 따라 공통 타겟을 동적으로 조절:

```
if (stallCount > 2 in last 60s) {
    commonTarget += 1.0   // 안정성 우선
} else if (stableFor > 120s && commonTarget > minTarget) {
    commonTarget -= 0.5   // 점진적 레이턴시 감소
}
```

---

## 8. 예상 결과 및 한계

### 8.1 예상 동기화 정밀도

| 전략 | 예상 시점 차이 | 구현 난이도 |
|------|----------------|-------------|
| A (앱→웹) | ±1.0초 | 낮음 |
| B (웹→앱) | ±1.0초 | 중간 (웹 제어 필요) |
| C (PDT 기반) | ±0.5초 | 중간 |
| D (하이브리드) | ±0.5초 | 중간~높음 |

### 8.2 근본적 한계

#### ① CDN 엣지 캐시 차이

같은 스트림이라도 앱과 웹이 서로 다른 CDN 엣지 서버에서 세그먼트를 받으면, 세그먼트 가용 시점이 다를 수 있다.

```
CDN 엣지 A (앱):     세그먼트 N 도착 → T₁
CDN 엣지 B (브라우저): 세그먼트 N 도착 → T₁ + 0.3초
→ 불가피한 0.3초 차이
```

#### ② 디코딩 파이프라인 차이

```
VLC:    네트워크 → demux → VideoToolbox HW decode → Metal render → 화면
웹:     네트워크 → MSE → 브라우저 내부 decode → Canvas/Video → 화면

각 파이프라인의 고유 지연이 다르며, 이는 제어 불가
```

#### ③ 클럭 정밀도

- PDT는 세그먼트 단위 (보통 2~6초 간격)
- 세그먼트 내부 프레임 단위 PDT는 없음 → 최대 1세그먼트 길이만큼 오차 가능

#### ④ VLC 한계

- VLCKit 4.0은 "현재 재생 프레임의 PDT"를 직접 제공하는 API 없음
- M3U8 파싱으로 간접 계산해야 함 → 추정치
- 재생 위치(`player.time`)와 세그먼트 PDT 매핑에 불확실성 존재

### 8.3 달성 불가능한 수준

- **프레임 단위 동기화** (±33ms): HLS 프로토콜 특성상 불가. WebRTC 등 다른 프로토콜 필요
- **0ms 차이**: CDN, 디코더, 렌더러 차이로 물리적 불가
- **스톨 없는 저지연**: 네트워크 불안정 시 버퍼/레이턴시 트레이드오프 불가피

---

## 9. 결론 및 권장사항

### 9.1 권장 구현 순서

```
Phase 1 (단기, 1~2일)
├─ LowLatencyController에 webSync 프리셋 추가 (targetLatency = 5.0초)
├─ StreamCoordinator에 SyncMode 선택 기능 추가
├─ UI에서 동기화 모드 전환 옵션 제공
└─ 매니페스트 갱신 주기 단축 (10초 → TARGETDURATION)

Phase 2 (중기, 3~5일)
├─ PDTLatencyProvider 정밀도 개선
├─ 앱-웹 레이턴시 실시간 비교 디버그 OSD
├─ 실측 기반 공통 타겟 최적화
└─ hls.js 커스텀 설정 문서화

Phase 3 (장기, 선택)
├─ 동적 타겟 조절 로직
├─ 서버 기반 공통 타겟 배포
└─ 다중 클라이언트 동기화 프레임워크
```

### 9.2 핵심 결론

1. **가장 큰 차이 원인은 타겟 레이턴시 차이** (앱 3초 vs 웹 ~6초). 타겟을 통일하면 차이의 대부분이 해소된다.

2. **PDT 기반 절대 시각**이 가장 신뢰할 수 있는 동기화 기준점이다. 앱(PDTLatencyProvider)과 웹(hls.playingDate) 모두 이를 지원한다.

3. **앱의 PID 기반 연속 조절**은 웹의 Seek 기반 대비 부드럽고 정밀하다. 이 장점을 유지하면서 타겟만 조절하는 것이 최선이다.

4. **실현 가능한 동기화 정밀도는 ±0.5초**이다. CDN, 디코더, 렌더러의 고유 지연 차이로 이보다 정밀한 동기화는 HLS 프로토콜에서 사실상 불가능하다.

5. **Phase 1만으로도 의미 있는 개선**이 기대된다. `targetLatency`를 5.0초로 조정하고 매니페스트 갱신 주기를 단축하면, 별도 웹 수정 없이 ±1초 이내로 근접할 수 있다.

---

### 부록: 참조 파일

| 파일 | 역할 |
|------|------|
| `Sources/CViewPlayer/LowLatencyController.swift` | PID 기반 레이턴시 동기화 |
| `Sources/CViewPlayer/StreamCoordinator.swift` | 스트림 오케스트레이션 |
| `Sources/CViewPlayer/VLCPlayerEngine.swift` | VLC 재생 엔진 |
| `Sources/CViewPlayer/AVPlayerEngine.swift` | AVPlayer 재생 엔진 |
| `Sources/CViewPlayer/LocalStreamProxy.swift` | CDN 프록시 |
| `Sources/CViewPlayer/ABRController.swift` | 적응 비트레이트 |
| `Sources/CViewPlayer/PDTLatencyProvider.swift` | PDT 기반 레이턴시 계산 |
| `Sources/CViewPlayer/HLSManifestParser.swift` | M3U8 파싱 |
| `Sources/CViewPlayer/PlaybackReconnectionHandler.swift` | 재연결 로직 |
