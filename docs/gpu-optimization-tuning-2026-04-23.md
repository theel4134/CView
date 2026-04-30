# GPU 사용률 정밀 튜닝 (2026-04-23)

균형형 정밀 튜닝 — 화질·반응성을 보존하면서 GPU/배터리 부하를 더 줄이기 위한 5단계 패치 모음.
이미 적용된 항목(VLC HW 디코딩, 비선택 세션 contentsScale 0.75×, decoder threads throttle, layer redraw 차단 등)은 손대지 않음.

## 변경 요약

| Phase | 영역 | 파일 | 효과 |
|------|-----|------|-----|
| A | motionSafe 누락 무한 애니메이션 정리 | `Sources/CViewUI/CViewUI.swift`, `Sources/CViewApp/Views/MultiLivePlayerPane.swift` | Reduce Motion 환경에서 LIVE 펄스 / 종료 오버레이 ringAnim CA 합성 정지 |
| B | Stream Ended Overlay GPU 절감 | `Sources/CViewApp/Views/MultiLivePlayerPane.swift` | compact 모드 스캔라인 비활성화, 풀 모드 blur 30→18, scanOffset 애니메이션 motionSafe, 동심원 펄스 compact 시 3→2개 |
| C | VLC 비선택 세션 디코딩/타이머 추가 절감 | `Sources/CViewPlayer/VLCPlayerEngine+Playback.swift` | `:avcodec-skip-frame=1`→`=2` (B + non-ref P 스킵), thermal `.hot` 시 비선택 세션 minimalTimePeriod 1ms→2ms, timeChangeUpdateInterval 5s→10s |
| D | 윈도우 가림 자동 GPU 합성 정지 | `Sources/CViewApp/AppLifecycle.swift`, `Sources/CViewApp/AppState.swift`, `Sources/CViewApp/ViewModels/PlayerViewModel.swift`, `Sources/CViewApp/ViewModels/MultiLiveManager.swift` | 모든 NSWindow 가림 시 단일 라이브/멀티라이브 전 세션 `.hidden` 강등(레이어 isHidden), 노출 시 selectedSessionId 기준 `.active`/`.visible` 복원. 디코딩/오디오는 영향 없음 |
| E | Low Power Mode 추가 다운스케일 | `Sources/CViewPlayer/VLCPlayerEngine.swift`, `Sources/CViewPlayer/AVPlayerLayerView.swift`, `Sources/CViewApp/AppLifecycle.swift` | `ProcessInfo.isLowPowerModeEnabled` 시 `.visible` 비선택 세션 contentsScale 0.75×→0.625× (≈60% 픽셀 감소). `NSProcessInfoPowerStateDidChange` 옵저버로 즉시 재적용 |

## 영향 범위 / 안전성

- **선택 세션 화질 무손상**: Phase C/E 모두 비선택(`.visible`/multiLive non-active) 세션만 추가 강등. 선택 세션은 백킹 풀 스케일 + 정상 timing 유지.
- **반응성 무손상**: Phase D는 가림 상태에서만 동작. 노출 복귀 시 즉시 원복.
- **Reduce Motion 존중**: Phase A/B 의 motionSafe 래핑은 시스템 접근성 토글을 따른다.
- **Quality-lock 모드 호환**: GPU 티어 변경은 compositor 단(contentsScale / isHidden)만 다룸 → `forceHighestQuality` 1080p 고정과 독립.

## 수동 검증 절차

1. **빌드**
   ```bash
   cd /Users/kimsundong/Downloads/work/CView_v2
   xcodebuild -scheme CView_v2 -configuration Debug \
     -derivedDataPath ~/Library/Developer/Xcode/DerivedData/CView_v2_local build
   ```
   결과: `** BUILD SUCCEEDED **` (확인 완료 — 18.2s)

2. **PerformanceOverlay 측정** (메뉴 > 디버그 > 성능 오버레이 토글)
   - 단일 라이브 1080p 재생 중 — 선택 세션 GPU% 기록 (전/후)
   - 멀티라이브 4채널 — 선택/비선택 GPU% 분리 측정 (전/후)
   - 비교 항목: avg GPU%, frame drop, thermalState

3. **Phase D — 윈도우 가림 시나리오**
   - 멀티라이브 4채널 재생 → CView 창을 다른 풀스크린 앱으로 가림 → Activity Monitor `WindowServer` GPU 0~5% 수준 확인
   - 창 노출 복귀 즉시 영상 표시 확인 (검은 프레임 1프레임 가능)

4. **Phase E — Low Power Mode**
   - 시스템 설정 > 배터리 > "저전력 모드" 활성 → 멀티라이브 비선택 셀이 약간 더 부드럽게 스케일됨 (눈으로는 감지 어려움)
   - 비활성화 시 즉시 0.75× 복귀 확인

## 측정 자리 (실측 후 채울 것)

| 시나리오 | GPU% (전) | GPU% (후) | 비고 |
|--------|--------|--------|-----|
| 단일 1080p | __ | __ | Phase A/D 영향 |
| 4ch 멀티라이브 | __ | __ | Phase B/C/D/E 종합 |
| 4ch + 윈도우 가림 | __ | __ | Phase D 단독 |
| 4ch + Low Power | __ | __ | Phase E 단독 |

## 잠재 후속 항목 (이번 패치 범위 외)

- 비선택 세션 디코더 threads를 thermal `.hot` 시 1로 더 낮추기 — 안정성 추가 검증 필요
- 자식 윈도우(`MultiLiveChildScene`)도 메인 occlusion 옵저버 공유 여부 확인 후 동일 적용 가능성
