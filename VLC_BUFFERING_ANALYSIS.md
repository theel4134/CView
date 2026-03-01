# VLC 플레이어 잦은 버퍼링 문제 — 연구 분석 및 개선 방안

> 작성일: 2026-02-27  
> 대상: CView v2.0 — VLC 엔진 (VLCKit 4.0)  
> 환경: macOS 26.4, Apple Silicon (M1 Max), Chzzk 라이브 스트리밍

---

## 1. 현상 요약

VLC 엔진으로 Chzzk 라이브 스트리밍 재생 시 다음과 같은 버퍼링 현상이 관찰됨:

| 증상 | 빈도 | 심각도 |
|------|------|--------|
| 재생 시작 후 검은 화면 (비디오 미출력) | 높음 | 치명적 |
| 재생 중 짧은 정지 (0.5~2초) | 중간 | 높음 |
| 오디오만 나오고 비디오 정지 | 낮음 | 높음 |
| 장시간 재생 후 점진적 끊김 증가 | 중간 | 중간 |
| 품질 전환 후 버퍼링 발생 | 높음 | 중간 |

---

## 2. 근본 원인 분석

### 2.1 이미 해결된 원인 (수정 완료)

#### ❶ LocalStreamProxy PCR Late 문제 (치명적 — 해결됨)
```
VLC 내부 로그: ES_OUT_SET_(GROUP_)PCR is called X ms late
→ pts_delay: 1000ms → 5987ms 무한 증가 → buffer deadlock → 검은 화면
```

- **원인**: `LocalStreamProxy`가 CDN 세그먼트를 localhost로 중계하면서 추가 레이턴시 발생
- VLC의 PCR(Program Clock Reference)이 도착 시각보다 늦게 처리됨
- VLC가 `pts_delay`를 반복적으로 증가시켜 버퍼가 무한히 커지다가 deadlock
- **수정**: VLC 엔진 사용 시 LocalStreamProxy 완전 우회 → CDN 직접 연결
  - VLC는 자체 HTTP 클라이언트 + adaptive demux 내장 → Content-Type 불일치 영향 없음
  - **파일**: `StreamCoordinator.swift` — `playerEngine is VLCPlayerEngine` 체크 추가

#### ❷ 캐싱값 과도하게 낮음 (높음 — 해결됨)
- **원인**: lowLatency 프로파일의 `networkCaching=350ms`, `liveCaching=150ms`는 HLS 세그먼트 구간(2~4초) 대비 턱없이 부족
- 세그먼트 경계에서 다음 세그먼트 도착 전에 버퍼 고갈 → 끊김
- **수정**: normal(2000/1500ms), lowLatency(1200/800ms)로 상향

#### ❸ clock-jitter 과도 제한 (높음 — 해결됨)
- **원인**: `clock-jitter=1000ms`는 CDN 네트워크 지연 변동(PTS 지터) 흡수 불충분
- PTS 불일치 → 프레임 드롭 → 화면 끊김
- **수정**: normal=5000ms, lowLatency=3000ms로 완화

#### ❹ VLC 자체 ABR에 의한 해상도 저하 (중간 — 해결됨)
- **원인**: 마스터 매니페스트 URL을 VLC에 전달 → VLC 자체 ABR이 네트워크 상태에 따라 480p/720p 선택
- **수정**: `resolveHighestQualityVariant()` 메서드 추가 → 1080p variant URL을 직접 VLC에 전달

#### ❺ 기타 해결된 문제
| 문제 | 원인 | 수정 |
|------|------|------|
| `audio-resampler=soxr` | VLCKit 4.0 비표준 옵션 → 오디오 글리치 | 제거 |
| `adaptive-logic=predictive` | 화질 전환 중 끊김 유발 | 제거 |
| `deinterlace=-1` (자동) | Progressive 소스에 불필요 → CPU 낭비 | `deinterlace=0` |
| `prefetch-buffer-size` | VLC HLS demux 비표준 옵션 | 제거 |

---

### 2.2 잠재적 원인 (미해결 — 개선 필요)

#### ❶ 1080p 고정 + 대역폭 부족 시 ABR fallback 부재
```
현재 흐름:
마스터 매니페스트 파싱 → 1080p variant URL → VLC에 직접 전달 → 고정 재생
                                                                    ↓
                                    대역폭 부족 시 → 버퍼 고갈 → 버퍼링 ❌
```
- 1080p variant URL을 직접 전달하면 VLC의 자체 ABR이 비활성화됨
- 네트워크 상태가 나빠져도 화질 전환 불가 → 버퍼링 반복
- **영향**: 와이파이 불안정, 대역폭 제한 환경에서 심각

#### ❷ HLS 세그먼트 경계 갭
```
세그먼트 1 ──────┐     ┌────── 세그먼트 2
                 │ GAP │
                 └─────┘
                   ↑ 이 구간에서 버퍼 고갈
```
- Chzzk HLS 세그먼트 길이: 약 2~4초
- 세그먼트 전환 시 다음 세그먼트 HTTP 요청 → 응답까지 지연 (100~500ms)
- `network-caching=2000ms`로 대부분 커버 가능하나, CDN 응답 지연 시 부족할 수 있음

#### ❸ CDN 서버 전환 / 토큰 만료
- Chzzk CDN(`ex-nlive-streaming.navercdn.com`)은 엣지 서버를 주기적으로 전환
- 라이브 URL에 포함된 토큰은 시간 경과 후 만료 가능
- TCP 재접속 → TLS handshake → HTTP 요청 = 약 300~1000ms 추가 지연
- `http-reconnect=1` 옵션이 있지만, 재접속 중 버퍼 고갈 가능

#### ❹ VLC 내부 버퍼 소진 감지 지연
- VLC `media.statistics`는 2초 주기로 수집 → 버퍼 상태 변화 감지가 최대 2초 늦음
- 버퍼가 0에 도달한 후에야 BUFFERING 상태 전환 → 이미 끊김 발생
- 사전 예방적(proactive) 버퍼 관리 부재

#### ❺ 멀티라이브 환경 리소스 경쟁
- 4개 VLC 인스턴스 동시 재생 시:
  - CPU 스레드 경쟁 → 디코딩 지연 → 프레임 드롭
  - VideoToolbox 세션 제한 (macOS: 최대 16개)
  - 네트워크 대역폭 분산 → 개별 스트림 대역폭 부족
- 백그라운드 탭은 `avcodec-threads=2`로 제한하지만, 전환 시 즉시 반영 안 됨

#### ❻ TCP/HTTP 연결 최적화 미흡
- VLC 기본 HTTP 설정은 Keep-Alive를 사용하지만, CDN 서버가 연결을 끊을 수 있음
- HTTP/2 멀티플렉싱 미지원 → 세그먼트마다 새 연결 가능성
- DNS 확인 지연 → CDN 엣지 서버 전환 시 추가 지연

---

## 3. 개선 방안

### 방안 1: 적응형 버퍼링 전략 (우선순위: 최상)

**개요**: 네트워크 상태와 버퍼 건강도에 따라 VLC 캐싱 값을 동적으로 조정

```
정상 재생 (healthScore > 0.8)
  └→ network-caching = 2000ms (기본)
  
버퍼 약세 (healthScore 0.5~0.8)
  └→ network-caching = 3000ms (1.5배 증가)
  └→ 다음 복구 시도에 자동 적용
  
버퍼 위기 (healthScore < 0.5)
  └→ network-caching = 4000ms (2배 증가)
  └→ 720p 임시 전환 고려
```

**구현 위치**: `VLCPlayerEngine.captureVLCMetrics()` 내부

```swift
// healthScore 기반 적응형 캐싱
if metrics.healthScore < 0.5 {
    streamingProfile = // 임시적으로 캐싱 증가된 프로파일
} else if metrics.healthScore > 0.8 {
    streamingProfile = .normal // 원복
}
```

**기대 효과**: 네트워크 불안정 시 자동 버퍼 확대 → 끊김 80% 감소  
**리스크**: 캐싱 증가 → 지연시간 증가 (라이브 스트림 3~4초 뒤처짐)  
**구현 난이도**: 중간 (VLCPlayerEngine 내부 수정)

---

### 방안 2: 1080p + ABR 하이브리드 (우선순위: 높음)

**개요**: 기본 1080p 유지하되, 대역폭 부족 시 임시 720p 전환 → 버퍼 복구 후 1080p 복귀

```
1080p 재생 중
  │
  ├─ 대역폭 충분 → 1080p 유지 ✅
  │
  └─ 대역폭 부족 감지 (3회 연속 drop > 5%)
       └→ 720p 임시 전환
            └→ 15초 후 대역폭 재측정
                 ├─ 충분 → 1080p 복귀
                 └─ 부족 → 720p 유지
```

**구현 위치**: `StreamCoordinator` — 새 메서드 `adaptiveQualityMonitor()`

```swift
// VLC 메트릭 콜백에서 drop ratio 감시
if metrics.dropRatio > 0.05 && consecutiveDropCount >= 3 {
    // 임시 720p 전환
    switchQualityByBandwidth(720p_variant.bandwidth)
    scheduleQualityRecovery(delay: 15)
}
```

**기대 효과**: 1080p 기본 유지 + 네트워크 불안정 시 자동 대응  
**리스크**: 화질 전환 시 짧은 끊김 (VLC stop→play 패턴), 사용자 경험 저하  
**구현 난이도**: 높음 (StreamCoordinator + VLCPlayerEngine 연동)

---

### 방안 3: 선제적 버퍼 감시 시스템 (우선순위: 높음)

**개요**: 버퍼가 고갈되기 전에 사전 경고 → 선제적 복구

```
현재: 버퍼 0% → BUFFERING 상태 → 끊김 발생 → 복구 시도
개선: 버퍼 30% → 선제 경고 → 즉시 캐싱 증가 or 프레임 드롭 허용 → 끊김 방지
```

**구현**: `VLCLiveMetrics.healthScore` 기반

```swift
// captureVLCMetrics에서 선제적 대응
if metrics.bufferHealth < 0.3 && metrics.bufferHealth > 0 {
    // 아직 재생 중이지만 위험 수준
    logger.warning("⚠ 버퍼 경고: \(Int(metrics.bufferHealth * 100))%")
    enableAggressiveFrameDrop() // 비핵심 프레임 스킵 강화
}
```

**기대 효과**: 버퍼 고갈 전 사전 대응 → 체감 끊김 60% 감소  
**리스크**: 과도한 프레임 드롭 → 영상 품질 일시 저하  
**구현 난이도**: 낮음 (VLCPlayerEngine 내부 수정)

---

### 방안 4: VLC 네트워크 옵션 추가 튜닝 (우선순위: 중간)

**개요**: VLC의 HTTP/네트워크 관련 숨겨진 옵션 활용

```swift
// 현재 미적용 옵션 — 추가 적용 후보

// 1. HTTP 연결 타임아웃 (기본 무한대 → 10초 제한)
media.addOption(":http-timeout=10")

// 2. HTTP 연결 재사용 강화
media.addOption(":http-forward-cookies=1")

// 3. HLS 세그먼트 프리페치
// (VLC 4.0 adaptive module의 내부 프리페치 활성화)
media.addOption(":adaptive-maxbuffer=10")  // 최대 10초 프리페치

// 4. 재접속 시도 횟수
media.addOption(":http-reconnect-max=5")

// 5. 네트워크 MTU 최적화
media.addOption(":mtu=1500")
```

**주의**: 일부 옵션은 VLCKit 4.0에서 지원되지 않을 수 있음 → 개별 테스트 필수

**기대 효과**: HTTP 연결 안정성 향상, 세그먼트 간 갭 감소  
**리스크**: VLC 버전별 옵션 호환성 이슈  
**구현 난이도**: 낮음 (configureMediaOptions에 옵션 추가)

---

### 방안 5: 메트릭 기반 자동 프로파일 전환 (우선순위: 중간)

**개요**: VLC 메트릭을 실시간 분석하여 스트리밍 프로파일을 자동 전환

```
  healthScore 기반 프로파일 자동 전환:

  ┌──────────────────────────────────────┐
  │  Score > 0.9  →  lowLatency 시도     │  ← 최고 성능 시 저지연 경험
  │  Score 0.7~0.9 →  normal 유지        │  ← 기본 안정 구간
  │  Score 0.5~0.7 →  highBuffer 전환    │  ← 캐싱 3000/2000ms
  │  Score < 0.5  →  highBuffer + 720p   │  ← 버퍼 위기 대응
  └──────────────────────────────────────┘
```

**구현 위치**: 새 클래스 `VLCAdaptiveProfileManager`

**기대 효과**: 네트워크 환경에 자동 적응  
**리스크**: 프로파일 전환 시 VLC stop→play 필요 (찢어짐 발생 가능)  
**구현 난이도**: 높음 (새 클래스 + VLCPlayerEngine + PlayerViewModel 연동)

---

### 방안 6: CDN 연결 사전 워밍 (우선순위: 낮음)

**개요**: 스트림 시작 전 CDN 엣지 서버에 미리 연결하여 초기 버퍼링 시간 단축

```swift
// 스트림 시작 전 CDN 연결 워밍
func warmUpCDNConnection(url: URL) async {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"  // 바디 없이 연결만
    request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
    _ = try? await URLSession.shared.data(for: request)
}
```

**기대 효과**: 초기 재생 시작 시간 200~500ms 단축  
**리스크**: 불필요한 네트워크 요청  
**구현 난이도**: 낮음

---

## 4. 우선순위 로드맵

```
Phase 1 (즉시 적용 가능)
├── 방안 4: VLC 네트워크 옵션 추가 (난이도 낮음, 효과 중간)
├── 방안 3: 선제적 버퍼 감시 (난이도 낮음, 효과 높음)
└── 방안 6: CDN 연결 워밍 (난이도 낮음, 효과 낮음)

Phase 2 (단기 개선)
├── 방안 1: 적응형 버퍼링 전략 (난이도 중간, 효과 최상)
└── 방안 2: 1080p + ABR 하이브리드 (난이도 높음, 효과 높음)

Phase 3 (중장기 개선)
└── 방안 5: 메트릭 기반 자동 프로파일 전환 (난이도 높음, 효과 높음)
```

---

## 5. 현재 시스템 아키텍처 요약

### 5.1 VLC 재생 흐름
```
PlayerViewModel.startStream()
  └→ StreamCoordinator.startStream(url:)
       ├── VLC 엔진 감지
       ├── resolveHighestQualityVariant(from:)
       │    ├── 마스터 매니페스트 fetch
       │    ├── M3U8 파싱 → variant 목록
       │    └── 1080p variant URL 선택
       ├── VLCPlayerEngine.play(url: 1080p_variant_url)
       │    ├── VLCMedia 생성
       │    ├── configureMediaOptions() ← 캐싱/코덱/네트워크 옵션
       │    ├── player.drawable 설정
       │    └── player.play()
       └── loadManifestInfo() (UI 품질 목록용)
```

### 5.2 VLC 캐싱 설정 (현재)
| 프로파일 | network-caching | live-caching | clock-jitter | 용도 |
|----------|----------------|--------------|-------------|------|
| normal | 2000ms | 1500ms | 5000ms | 기본 안정 재생 |
| lowLatency | 1200ms | 800ms | 3000ms | 저지연 요청 시 |
| multiLiveBackground | 1500ms | 1000ms | 5000ms | 멀티라이브 백그라운드 탭 |

### 5.3 복구 메커니즘 (현재)
```
버퍼링/끊김 감지 경로:

1. 스톨 워치독 (10초 주기)
   ├── PLAYING 상태에서 재생 위치 30초 미변화 → attemptRecovery(.stall)
   └── BUFFERING 상태 60초 고착 → attemptRecovery(.bufferingStall)

2. VLC delegate
   ├── .error → attemptRecovery(.error)
   └── .stopped (비정상) → attemptRecovery(.stopped)

3. attemptRecovery() 통합 복구
   ├── 지수 백오프: baseDelay × 2^(연속실패수), 최대 15초
   ├── maxRetries: 3회
   ├── recoveryCooldown: 5초 (중복 방지)
   └── 안정 재생 30초 후 카운터 리셋
```

---

## 6. 측정 및 모니터링 지표

### 버퍼링 개선 효과 측정을 위한 핵심 KPI

| 지표 | 현재 수집 여부 | 설명 |
|------|-------------|------|
| `healthScore` | ✅ VLCLiveMetrics | 종합 건강 점수 (0~1) |
| `dropRatio` | ✅ VLCLiveMetrics | 프레임 드롭 비율 |
| `bufferHealth` | ✅ VLCLiveMetrics | 버퍼 건강도 (0~1) |
| `fps` | ✅ VLCLiveMetrics | 초당 프레임 |
| `networkBytesPerSec` | ✅ VLCLiveMetrics | 네트워크 throughput |
| TTFP (Time To First Picture) | ❌ 미수집 | 재생 시작 → 첫 프레임 출력 시간 |
| 버퍼링 빈도 | ❌ 미수집 | 시간당 버퍼링 횟수 |
| 버퍼링 총 시간 | ❌ 미수집 | 세션 내 총 버퍼링 시간 |
| 복구 성공률 | ❌ 미수집 | attemptRecovery 성공/실패 비율 |

### 추가 수집 권장 메트릭

```swift
// PlayerViewModel 또는 StreamCoordinator에 추가
struct BufferingMetrics {
    var bufferingCount: Int = 0          // 버퍼링 발생 횟수
    var totalBufferingDuration: TimeInterval = 0  // 총 버퍼링 시간
    var lastBufferingTime: Date?         // 마지막 버퍼링 시각
    var recoverySuccessCount: Int = 0    // 복구 성공 횟수
    var recoveryFailCount: Int = 0       // 복구 실패 횟수
    var timeToFirstPicture: TimeInterval?  // 첫 프레임 출력 시간
}
```

---

## 7. 결론

### 버퍼링의 근본 원인 3가지

1. **VLC 내부 버퍼 관리의 정적 특성**  
   → `network-caching`/`live-caching`이 고정값이라 네트워크 변동에 대응 불가

2. **1080p 고정 재생 + ABR 부재**  
   → 대역폭 부족 시 화질 전환 없이 버퍼 고갈

3. **HLS 세그먼트 경계의 구조적 갭**  
   → TCP 연결 + HTTP 요청 → 응답까지의 지연이 캐싱 범위를 초과

### 최우선 개선 항목

1. **선제적 버퍼 감시** (방안 3) — 구현 난이도 낮음, 즉시 적용 가능
2. **적응형 버퍼링 전략** (방안 1) — 가장 효과적, 중간 난이도
3. **1080p + ABR 하이브리드** (방안 2) — 근본적 해결, 높은 난이도

이 3가지를 순차적으로 구현하면 **체감 버퍼링을 현재 대비 70~90% 감소**시킬 수 있을 것으로 예상됩니다.
