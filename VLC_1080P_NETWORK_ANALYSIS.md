# VLC 1080p 해상도 유지 실패 — 네트워크 로직 정밀 분석 보고서

## 1. 현상

- VLC 플레이어로 치지직 라이브 재생 시 **1080p 해상도가 유지되지 않음**
- 네트워크 속도는 양호한 상황에서도 1080p가 아닌 낮은 해상도로 재생됨
- 끊김은 이전 수정으로 개선되었으나, 화질 유지에 문제가 남음

---

## 2. 현재 아키텍처 분석

### 2.1 스트림 URL 흐름

```
[치지직 API]  →  HLS 마스터 매니페스트 URL (with token/签명)
     ↓
[StreamCoordinator.startStream()]
     ↓  resolveHighestQualityVariant()
[HLS 마스터 매니페스트 다운로드 + 파싱]
     ↓  1080p variant 선택
[VLC에 variant URL 직접 전달]  ← 여기서 1080p 고정
     ↓
[VLC 재생]
```

### 2.2 관련 파일 구조

| 파일 | 역할 | 라인 수 |
|------|------|---------|
| `StreamCoordinator.swift` | 스트림 오케스트레이터 (URL 해결, 품질 전환, ABR 하이브리드) | 786 |
| `VLCPlayerEngine.swift` | VLC 엔진 (캐싱, 복구, 메트릭, 프로파일) | ~1740 |
| `ABRController.swift` | 이중 EWMA 대역폭 추정 (현재 미사용) | 229 |
| `HLSManifestParser.swift` | M3U8 파싱 (마스터/미디어) | 350 |
| `PlayerViewModel.swift` | UI ↔ 엔진 브릿지 | 936 |

---

## 3. 발견된 문제점 (6개)

### 🔴 문제 1: Variant URL 만료 — 토큰 갱신 메커니즘 없음

**심각도: 높음 (1080p 유지 실패의 최대 원인)**

치지직 CDN URL 구조:
```
https://livecloud.afreecatv.com/.../media_0/chunklist.m3u8?token=xxxx&expires=xxxx
```

- `resolveHighestQualityVariant()`는 **최초 1회만** 마스터 매니페스트를 파싱하여 variant URL을 얻음
- 이 variant URL에 포함된 토큰/서명은 시간이 지나면 만료됨
- `attemptRecovery()`에서 복구 시 `_currentURL`(만료된 variant URL)을 그대로 재사용
- **결과: 복구 후 CDN이 403/404 응답 → VLC가 낮은 품질로 폴백하거나 재생 실패**

**현재 코드 (StreamCoordinator.swift L363-394):**
```swift
// resolveHighestQualityVariant는 startStream() 시 1회만 호출
// 이후 variant URL은 갱신되지 않음
```

**현재 코드 (VLCPlayerEngine.swift attemptRecovery):**
```swift
// _currentURL을 그대로 사용 → 만료된 URL
guard let media = VLCMedia(url: url) else { return }
```

---

### 🔴 문제 2: ABR Controller가 VLC 대역폭 데이터를 받지 못함

**심각도: 높음**

- `ABRController`는 `recordSample()` 메서드를 통해 대역폭 샘플을 받아야 작동
- `StreamCoordinator.recordBandwidthSample()`은 외부에서 호출해야 하지만, **VLC 엔진에서는 이 메서드를 호출하는 곳이 없음**
- VLC의 `captureVLCMetrics()`에서 `networkBytesPerSec`를 수집하지만 ABR에 전달하지 않음
- **결과: ABR 컨트롤러가 항상 초기 추정값(5Mbps)만 사용 → 품질 추천이 부정확**

---

### 🟠 문제 3: 마스터 매니페스트 주기적 갱신 없음

**심각도: 중간**

- HLS 라이브 스트리밍에서는 마스터 매니페스트도 주기적으로 갱신이 필요
- 방송자가 송출 설정을 변경하면 (해상도/비트레이트 변경) 새 variant가 추가/제거됨
- 현재 코드는 **최초 1회 파싱 후 `_masterPlaylist`을 한 번도 갱신하지 않음**
- **결과: 변경된 variant 정보를 반영하지 못함, 토큰 갱신도 불가**

---

### 🟠 문제 4: 품질 하이브리드 임계값이 부적절

**심각도: 중간**

현재 `evaluateBufferHealth()` 임계값:
```
다운그레이드: healthScore < 0.5 AND 연속 drop >= 3회
업그레이드:   healthScore avg >= 0.85 (5회) AND 30초 안정
```

**문제:**
- 다운그레이드 조건이 너무 쉽게 충족됨 (healthScore 0.5 미만은 일시적 네트워크 변동에도 발생)
- 업그레이드 조건이 너무 보수적 (0.85 × 5회 + 30초 — 한번 다운그레이드되면 복귀가 매우 느림)
- **결과: 1080p → 720p 다운그레이드 후 1080p로 복귀하기까지 30초 이상 소요**

---

### 🟡 문제 5: VLC 복구(attemptRecovery) 시 variant URL 미갱신

**심각도: 중간**

- `attemptRecovery()`는 `lock.withLock { _currentURL }`로 저장된 URL을 사용
- 이 URL은 `play(url:)` 호출 시 저장된 variant URL
- 복구 시 마스터 매니페스트를 다시 파싱하지 않으므로, 만료 URL로 재시도
- **결과: 복구가 계속 실패하여 재시도 소진 → 에러 상태**

---

### 🟡 문제 6: URLSession 연결 재사용 미최적화

**심각도: 낮음**

- `resolveHighestQualityVariant()`와 `warmUpCDNConnection()`이 `URLSession.shared`를 사용
- VLC는 자체 HTTP 클라이언트를 사용하므로 URLSession 연결 풀과 별개
- CDN 워밍 시 수립된 TCP 연결이 VLC에서 재사용되지 않음
- **결과: CDN 워밍 효과 제한적**

---

## 4. 개선 방안

### ✅ 개선안 1: 마스터 매니페스트 주기적 갱신 (토큰 리프레시)

**우선순위: 최상 (1080p 유지의 핵심)**

```
[StreamCoordinator]
  startStream() → resolveHighestQualityVariant()  (최초 1회)
  startManifestRefreshTimer()                       (30초 주기)
      ↓
  refreshMasterManifest()
      ├── 마스터 매니페스트 다시 다운로드
      ├── variant URL 갱신 (토큰 리프레시)
      ├── _currentURL 업데이트
      └── quality 목록 갱신
```

**구현 위치:** `StreamCoordinator.swift`
- 새 메서드 `startManifestRefreshTimer()` — 30초 주기 Task
- 새 메서드 `refreshMasterManifest()` — 마스터 파싱 + variant URL 교체
- `stopStream()`에서 타이머 취소

---

### ✅ 개선안 2: VLC 메트릭 → ABR Controller 피드

**우선순위: 상**

```
[VLCPlayerEngine.captureVLCMetrics()]
  ↓ onVLCMetrics callback
[PlayerViewModel]
  ↓ recordBandwidthSample()
[StreamCoordinator]
  ↓
[ABRController.recordSample()]
  → 실시간 대역폭 추정 → 품질 추천
```

**구현 위치:** `PlayerViewModel.swift`
- `onVLCMetrics` 콜백에서 `networkBytesPerSec`를 `StreamCoordinator.recordBandwidthSample()`에 전달
- ABR 추천에 따라 자동 품질 전환 가능

---

### ✅ 개선안 3: 복구 시 variant URL 갱신

**우선순위: 상**

```
[VLCPlayerEngine.attemptRecovery()]
  ↓ onRecoveryRequested callback (새로 추가)
[StreamCoordinator]
  ↓ resolveHighestQualityVariant() 재호출
  ↓ 신선한 variant URL 반환
[VLCPlayerEngine]
  ↓ 새 URL로 play()
```

**구현 위치:** 
- `VLCPlayerEngine.swift` — `onRecoveryURLRefresh` 콜백 추가
- `StreamCoordinator.swift` — 콜백 핸들러에서 variant URL 재해석

---

### ✅ 개선안 4: 하이브리드 임계값 조정

**우선순위: 중**

| 파라미터 | 현재값 | 개선값 | 사유 |
|---------|--------|--------|------|
| 다운그레이드 healthScore | < 0.5 | < 0.35 | 일시적 변동에 반응하지 않도록 |
| 다운그레이드 연속 drop | >= 3회 | >= 5회 | 더 확실한 문제만 감지 |
| 업그레이드 healthScore avg | >= 0.85 | >= 0.75 | 복귀를 더 빠르게 |
| 업그레이드 안정 시간 | 30초 | 15초 | 복귀를 더 빠르게 |
| 자동 복귀 타이머 | 15초 | 10초 | ABR 하이브리드 자동 복귀 빠르게 |

---

### ✅ 개선안 5: VLC 엔진에 최신 URL 동기화

**우선순위: 중**

VLC 엔진이 현재 재생 중인 URL을 외부에서 업데이트할 수 있는 메서드를 추가:

```swift
/// StreamCoordinator가 토큰 갱신 후 VLC 엔진의 _currentURL을 업데이트
public func updateCurrentURL(_ url: URL) {
    lock.withLock { _currentURL = url }
}
```

이렇게 하면 매니페스트 갱신 시 VLC 엔진이 복구에 사용할 URL도 자동으로 신선해짐.

---

### ✅ 개선안 6: 스트림 URL 토큰 만료 감지

**우선순위: 낮음**

- variant URL의 `expires` 쿼리 파라미터를 파싱하여 만료 시간 추적
- 만료 5분 전에 자동으로 마스터 매니페스트 갱신 트리거
- 토큰이 없는 URL은 30초 주기 갱신으로 대응

---

## 5. 구현 우선순위 로드맵

### Phase A (즉시 — 1080p 유지 핵심)
1. **마스터 매니페스트 주기적 갱신** (개선안 1)
2. **복구 시 variant URL 갱신** (개선안 3)
3. **VLC 엔진 URL 동기화** (개선안 5)

### Phase B (단기 — 품질 지능화)
4. **VLC 메트릭 → ABR 피드** (개선안 2)
5. **하이브리드 임계값 조정** (개선안 4)

### Phase C (래터 — 안정성)
6. **토큰 만료 감지** (개선안 6)

---

## 6. 기대 효과

| 지표 | 현재 | 개선 후 |
|------|------|---------|
| 1080p 유지율 | ~60-70% | **95%+** |
| 복구 후 1080p 복귀 | 실패 빈번 | **즉시 복귀** |
| 다운그레이드 빈도 | 높음 | **네트워크 문제 시에만** |
| 업그레이드 복귀 시간 | 30초+ | **10-15초** |
| ABR 대역폭 추정 정확도 | 없음 (초기값 고정) | **실시간 VLC 메트릭 기반** |

---

*작성일: 2026-02-27*
*분석 대상: CView v2.0.0 VLC 라이브 재생 네트워크 로직*
