# CView v2 — 최적화 & 튜닝 로드맵 계획서 (2026-04-30)

> **Phase 1 P0 진행 결과 (2026-04-30 완료):**
> N-1, FS-1, H-1, H-2, M-1/M-2 ─ 코드 검증 결과 이미 적용됨. 추가 작업 불필요.
> P-1/P-2 ─ LowLatencyController.snapshot 확장 + PerformanceMonitor.Metrics 6개 필드 추가 + PerformanceOverlayView 5개 신규 행 (PHSE/RATE/PID/OSC/SEEK).
> L-1 ─ `Sources/CViewApp/Views/LiveResponsiveBreakpoints.swift` 신규 (`LiveBreakpoint` enum, 860/1080/1320pt). LiveStreamView 사이드 채팅 클램프에 적용.
> CL-1 ─ Phase 1 분해: `Sources/CViewApp/Views/Clips/SpotlightClipCard.swift`, `ClipPreviewInspector.swift` 추출. PopularClipsView.swift 2784 → 2212 LOC (-20%).
> 전체 빌드: `xcodebuild -scheme CView_v2 -configuration Debug build` 통과.

> 본 문서는 2026-04-18 ~ 2026-04-30 사이 진행된 **전 메뉴 재설계** 와
> 플레이어/메트릭/퍼시스턴스 변경을 횡단 분석하여,
> "남아있는 성능·안정성·UX 부채" 를 우선순위로 정리한 실행 계획서다.
>
> 입력 자료
> - `docs/home-final-lightweight-design-source-2026-04-28.md`
> - `docs/live-menu-final-design-source-2026-04-28.md`
> - `docs/category-menu-redesign-candidates-2026-04-28.md`
> - `docs/search-menu-redesign-development-plan-2026-04-29.md`
> - `docs/clip-menu-precision-redesign-source-2026-04-30.md`
> - `docs/clip-menu-distinctive-design-development-plan-2026-04-30.md`
> - `docs/settings-menu-redesign-candidates-2026-04-28.md`
> - `docs/metrics-menu-redesign-candidates-2026-04-28.md`
> - `docs/superset-replacement-{recommendation,live-server}-development-plan-2026-04-29.md`
> - `docs/optimization-audit-2026-04-19.md`, `gpu-optimization-tuning-2026-04-23.md`
> - `docs/home-frame-drop-analysis-2026-04-24.md`, `ui-animation-optimization-plan.md`
> - `docs/vlc-cpu-optimization-research.md`, `latency-buffering-analysis.md`
> - 27 Apr 이후 변경된 Swift 파일 64개 (Views/HomeV2, Statistics, Dashboard,
>   FollowingView+Redesign2026, ClipPlayerView, ClipFilmstripDock, PopularClipCards,
>   SearchViews, SettingsWorkspace, CommandPaletteView, MultiLive*, MLNetwork*,
>   VLCPlayerEngine+{Playback,Features}, LowLatencyController, StreamCoordinator,
>   ABRController, MetricsAPIClient, DataStore, SettingsModels+UISettings 등)

---

## 0. 변경 요약 — "어떤 것이 바뀌었나"

| 영역 | 핵심 변경 | 핵심 문서 |
|---|---|---|
| **Home** | 분석 대시보드 → **Light Command Home** (탐색·재생·멀티 추가의 3개 액션 허브). Superset 임베드/멀티 프리셋/슬라이더 제거 | home-final-lightweight-design-source |
| **Live/MultiLive** | 좌측 채널 셸프 제거 → **하단 Following Sheet (collapsed/peek/expanded)**, 단일 채팅 도크 → 멀티 채팅 도크 통합 + 현재 채널 필터, 상단 모드 바(탐색/시청/멀티) | live-menu-final-design-source |
| **Category** | 단순 그리드 → **Command Grid + Split Explorer (≥1180pt)**, 카테고리 핀/유형 필터 sticky | category-menu-redesign-candidates |
| **Search** | 4탭 분리 → **Search Command Hub** (전체 탭, 명령 바, 우측 인스펙터), `searchSessionId` 도입 | search-menu-redesign-development-plan |
| **Clips** | 좌측 사이드바 카드월 → **Clip Reel Desk 2.0** (중앙 스테이지 + 우 인스펙터 + 하단 필름스트립 도크), 3k LOC 단일 파일 분해 | clip-menu-precision-redesign-source / -distinctive- |
| **Metrics** | 단일 세로 대시보드 → **Metrics Command Center + Channel Inspector + Ops Timeline** | metrics-menu-redesign-candidates |
| **Settings** | 길어진 사이드바 → **Settings Command Center**, 공통 토글 상단 노출 | settings-menu-redesign-candidates |
| **Player(VLC)** | Phase A~E 적용 — Reduce Motion(MotionSafe), 블러/스캔라인 경량화, `:avcodec-skip-frame=2`, 윈도 occlusion → layer hidden, Low Power 시 contentsScale 0.625× | gpu-optimization-tuning, vlc-cpu-optimization-research |
| **저지연/ABR** | `LowLatencyController` PID(Kp 0.5/Ki 0.05/Kd 0.03), EWMA α=0.15, target 6s. `MultiLiveBandwidthCoordinator` EMA cap | latency-buffering-analysis |
| **Persistence/Net** | DataStore PLIST+JSON, 응답 캐시 PowerAware, MetricsAPI `/stats/overview`+`/health`+legacy fallback, MetricsWebSocketClient + 30s polling fallback | optimization-audit, superset-replacement-* |
| **Server BI** | Superset → **Grafana OSS (1차) + Metabase (2차)** 로 대체 권고, 추천/라이브 서버 분리 | superset-replacement-* |
| **App Shell** | `MenuTransitionGate`, `CommandPalette` (`/`), MultiLive **자식 프로세스 격리** + 2초 liveness | (코드 변경) |

---

## 1. 영역별 잔여 이슈 (재설계가 만든 신규 부채)

### A) Home & Dashboard
| ID | 이슈 | 파일 / 라인 | 심각도 |
|---|---|---|---|
| H-1 | `HomeSectionAppear` 가 explicit `withAnimation` 사용 → `MenuTransitionGate` 우회, 메뉴 → 홈 진입 1~2 프레임 드롭 | `Sources/CViewApp/Views/HomeV2/HomeView_v2.swift`, `HomeV2Effects.swift` | **P0** |
| H-2 | 카드별 45초 썸네일 루프 다수 활성 → `LiveThumbnailView.RefreshPolicy` 가 일부 `.periodic` 잔존 | HomeV2Components / Discover/Top 그리드 | **P0** |
| H-3 | `onAppear` 누적 작업 (refresh + storage load + recommend + prefetch 동시) | `HomeViewModel.loadServerStats()` | P1 |
| H-4 | `HomeThumbnailPrefetcher.detached()` 가 빠른 메뉴 전환 시 cancel/merge 없이 누적 | `Services/HomeThumbnailPrefetcher.swift` | P1 |
| H-5 | Superset/Grafana 연결 캐시 TTL 부재 → 진입마다 헬스체크 | Home v2 Insight Dock | P1 |
| H-6 | 일부 hover shadow radius 애니메이션 → GPU blur 재계산 | HomeV2Components hero/recommended | P2 |

### B) Live & MultiLive
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| L-1 | 860 / 1080 / 1320pt 반응형 분기점이 코드에 일관되지 않음 (스테이지 우선 규칙 미강제) | `MainContentView.swift`, `MultiLiveView.swift`, `MLSplitVideoChat.swift` | **P0** |
| L-2 | 하단 Following Sheet collapsed/peek/expanded 상태 영속 미구현 (재시작 시 reset) | `FollowingView+Redesign2026.swift` | P1 |
| L-3 | 멀티 채팅 도크 + 4세션 + 현재 채널 필터 동시 활성 시 메시지 처리 CPU spike | `ChatViewModel+Processing.swift` (3s 통계 갱신) | P1 |
| L-4 | `MultiLiveBandwidthCoordinator` 동시 다운그레이드가 동기적 stall 로 체감 | `MultiLiveBandwidthCoordinator.swift` | P1 |
| L-5 | 단일 채팅 → 멀티 도크 마이그레이션 후 남아있는 dead UI (`ChatPanelView`, `ChatOnlyView` 노출 경로) | `ChatPanelView.swift`, `ChatOnlyView.swift` | P2 |

### C) Player Engine (VLC + AVPlayer + LowLatency + ABR)
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| P-1 | PID 평가 5초 고정 (audit 미적용) | `LowLatencyController.swift:292` | **P0** |
| P-2 | PID overshoot 시 buffer drain → 사용자 stutter, 임계값(catchUp 1.0s/slowDown 0.8s) 검증 텔레메트리 없음 | `LowLatencyController.swift` | **P0** |
| P-3 | `:avcodec-skip-frame=2` Phase C — 저모션·고비트 신scenes 에서 banding 가능 | `VLCPlayerEngine+Playback.swift` | P1 |
| P-4 | Thermal `.hot` 시 minimalTimePeriod 2ms — 외부 부하시 jitter 가능 | `VLCPlayerEngine+Features.swift` | P1 |
| P-5 | AVPlayer ↔ VLC 엔진 전환 정책이 `MultiLiveEnginePool` 내부에만 존재, 진단 표면 없음 | `MultiLiveEnginePool.swift`, `PlayerEngineBadge.swift` | P2 |
| P-6 | Phase E (LPM) contentsScale 0.625× 가 비선택 세션에만 — 선택 세션은 LPM에서도 1.0× | `MultiLivePlayerPane.swift` | P2 |

### D) Following / Search / Category / Clip
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| FS-1 | `AppRoute.search(query:)` 경로 정의는 있으나 `AppRouter.navigate()` 가 query 파라미터 미전달 → 홈/팔레트에서 검색 carry-through 불가 | `Navigation/AppRouter.swift`, `SearchViewModel.swift` | **P0** |
| FS-2 | Clip 검색이 사실은 "상위 채널 클립 + 로컬 필터" — UX는 글로벌 검색처럼 표시 | `SearchViewModel.swift`, `SearchResultRows.swift` | P1 |
| FS-3 | `searchSessionId` token 미구현 → race 시 stale 결과 노출 가능 | `SearchViewModel.swift` | P1 |
| C-1 | Category Split Explorer 의 width breakpoint 토글이 idempotent 하지 않음 (전환시 black flash 가능) | `CategoryBrowseView.swift` | P1 |
| C-2 | 카테고리 핀 토글이 설정 패널 안에만 존재, Grid 에서 직접 핀 불가 | `CategoryBrowseView.swift` | P2 |
| CL-1 | `PopularClipsView.swift` 단일 파일 ~3k LOC, 컴포넌트 분해 미수행 → 빌드 타임/유지보수 부채 | `PopularClipsView.swift` | **P0** |
| CL-2 | `ClipPreviewInspector` 코드 존재 (~L1722) 하나 UI 미연결 — Reel Desk 2.0 우 인스펙터 미가용 | `PopularClipsView.swift`, `ClipPlayerView.swift` | P1 |
| CL-3 | `ClipFilmstripDock` 20+ 클립 노출시 레이아웃 계산 stutter (debounce 부재) | `ClipFilmstripDock.swift` | P1 |
| CL-4 | "Watch Later" 가 UID만 영속 — 재시작 시 재 fetch 미수행, 실질 데이터 손실 | `DataStore.swift`, `ClipPlayerViewModel.swift` | P1 |

### E) Settings / Metrics / Statistics
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| M-1 | `MetricsDashboardView.swift` 가 여전히 단일 세로 스택 — Command Center / Channels / Ops Timeline 분리 미구현 | `Views/Dashboard/MetricsDashboardView.swift` | **P0** |
| M-2 | WebSocket 실시간 vs 30s polling fallback 의 상태 표시 불명확 (사용자가 "지금 보는 값이 실시간인지" 모름) | `MetricsForwardingStatusView.swift`, `MetricsWebSocketClient.swift` | **P0** |
| M-3 | Channel Inspector 테이블 (20+ rows) 에 `.equatable()` / debounced cell refresh 미적용 예상 | (신규 구현 대상) | P1 |
| M-4 | Ops Timeline 이벤트 버퍼 / 임계값 정책 미정의 | (신규 구현 대상) | P2 |
| S-1 | 설정 저장이 키별 즉시 write — 중간 crash 시 부분 적용 (트랜잭션 부재) | `Persistence/DataStore.swift`, `SettingsModels+UISettings.swift` | P1 |
| S-2 | `SettingsModels+UISettings.swift` 로드 시 invalid value 검증 부재 | 동일 | P1 |

### F) Persistence / Networking / Server BI
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| N-1 | 응답 캐시 purge 5분 고정 (audit P-7 미적용) | `ChzzkAPIClient.swift:55` | **P0** |
| N-2 | 홈 자동 새로고침 90초 고정 | `HomeViewModel.swift:385` | P1 |
| N-3 | `LiveThumbnailService` `.utility` 고정 (배터리에서 우선순위 조정 안됨) | `LiveThumbnailService.swift:66` | P1 |
| N-4 | 채팅 통계 3초 고정 | `ChatViewModel+Processing.swift:383` | P1 |
| N-5 | `PerformanceMonitor.start(interval:)` 호출자 인자 그대로 — 내부 PowerAware scaling 없음 | `PerformanceMonitor.swift:114` | P1 |
| BI-1 | docker-compose 가 여전히 Superset 기준 — Grafana provisioning JSON / 대시보드 export 미생성 | `server-dev/`, deploy scripts | P1 |
| BI-2 | App 의 `:9443/superset` 딥링크 잔존 → `:3000/grafana` 전환 필요 (Home insight + Metrics 링크) | Home v2 / Metrics view | P1 |
| BI-3 | 추천/라이브 서버 분리 후 single-point cache (응답 캐시 + WS) reconciliation 정책 부재 | `MetricsAPIClient.swift` | P2 |

### G) App Shell
| ID | 이슈 | 파일 | 심각도 |
|---|---|---|---|
| A-1 | MultiLive 자식 프로세스 crash 시 자동 respawn 없음 — 사용자가 수동 제거 필요 | `MultiLiveProcessLauncher.swift`, `MultiLiveChildScene.swift` | P1 |
| A-2 | 앱 crash 후 세션 (검색/클립 큐/Following 필터) 복원 없음 | `AppState*`, `DataStore.swift` | P1 |
| A-3 | Deep link (`cv://live/...`, `cv://clip/...`) 스펙 비공식, 라우팅 일관성 부족 | `DeepLinkRouter.swift` | P2 |
| A-4 | CommandPalette 가 `SearchViewModel` 으로 query carry-through 미수행 (FS-1 과 동일 원인) | `CommandPaletteView.swift` | P1 |

---

## 2. 우선순위 로드맵

### Phase 1 — P0 즉시 수행 (2~3 주)

| # | 영역 | 작업 | 산출 KPI |
|---|---|---|---|
| 1 | Home | H-1: `HomeSectionAppear` explicit animation 제거 → 트랜지션 gate 종료 후 idle frame 에서 fade-in | 메뉴→홈 stutter 0 frame |
| 2 | Home | H-2: 모든 썸네일 셀의 `RefreshPolicy` 를 `.once` 또는 가시성 게이트형으로 통일 | 홈 idle CPU −5% |
| 3 | Live | L-1: 860/1080/1320pt 반응형 룰 정의 + 스테이지 우선 strategy enforce, snapshot test 추가 | 모든 윈도 폭에서 layout 안정 |
| 4 | Player | P-1/P-2: PID 평가 주기 PowerAware, PerformanceOverlay 에 `bufferOscillationCount` / `seekFrequency` / `pidOutput` 노출 | 베이스라인 측정 가능 |
| 5 | Search | FS-1: `AppRouter.navigate(.search(query:))` 가 query 를 `SearchViewModel.bind(query:sessionId:)` 로 주입 + CommandPalette 연결 (A-4 동시 해결) | Home/Palette → Search 1-step |
| 6 | Metrics | M-1/M-2: `MetricsDashboardView` 를 Overview/Channels/Ops Timeline 3 탭 컨테이너로 분해 + 실시간/폴링 상태 칩 | 첫 화면 스크롤 0 |
| 7 | Clips | CL-1: `PopularClipsView.swift` 를 `Views/Clips/` 디렉토리로 분해 (Hub/Stage/Inspector/Filmstrip/Cards) | 단일 파일 ≤ 600 LOC |
| 8 | Network | N-1: 응답 캐시 purge `PowerAwareInterval.scaled(...)` (audit § 2 일괄 N-1~N-5 적용) | Battery wake-up −30% |

### Phase 2 — P1 중요 (3~4 주)

| # | 영역 | 작업 | 산출 KPI |
|---|---|---|---|
| 9 | Home | H-3/H-4/H-5: `onAppear` 작업 직렬화, prefetch merge+cancel, Superset/Grafana 연결 캐시 TTL 60s | 홈 진입 시 동시 API 4→2, 200ms 단축 |
| 10 | Live | L-2: Following Sheet 상태 영속 (UserDefaults: collapsed/peek/expanded + height) | 재시작 시 복원 |
| 11 | Live | L-3: 채팅 처리 worker 를 background queue + dedupe + render-side debounce | 4세션+spam 시 60 → ≥55 fps |
| 12 | Live | L-4: BandwidthCoordinator hysteresis (다운그레이드 임계 ±10%, 회복 지연 5s) | 동시 stall 50% 감소 |
| 13 | Player | P-3: Phase C `:skip-frame=2` 조건부화 (저모션 카테고리 / 고비트 컨텐츠 시 `=1`) | banding 클레임 0 |
| 14 | Player | P-4: thermal `.hot` 시 외부 부하 감지 후에만 minimalTimePeriod 2ms 적용 | jitter ≤ 1% |
| 15 | Category | C-1: Width breakpoint debounce 200ms + pre-render shadow layer | 860↔1180 전환 무 flash |
| 16 | Clips | CL-2/CL-3: `ClipPreviewInspector` 활성화 (반응형: 좁은 폭에서 sheet fallback), 필름스트립 layout debounce 100ms | 우 인스펙터 사용 가능, dock stutter 0 |
| 17 | Clips | CL-4: Watch Later 영속을 `(uid, channelId, expectedThumbnail)` 트리플 캐싱 + 앱 시작시 lazy refetch | 재시작 후 큐 100% 복원 |
| 18 | Metrics | M-3: Channels 테이블 row `Equatable` 채택 + cell update coalescing 200ms | 50 row 갱신 < 5% CPU |
| 19 | Settings | S-1/S-2: DataStore atomic save (temp file → fsync → rename), 로드 시 `Decodable` validation + safe defaults | crash 후 설정 일관성 100% |
| 20 | Network | N-2~N-5: PowerAware 일괄 적용 (홈 90s, LiveThumbnail priority, ChatStats 3s, PerformanceMonitor) | Battery wake-up 추가 −15% |
| 21 | BI | BI-1/BI-2: docker-compose Grafana 마이그레이션 + provisioning JSON + `:9443` → `:3000` 링크 교체 | 배포 1 명령 완료 |
| 22 | App | A-1: MultiLive 자식 프로세스 auto-respawn (지수 backoff 1s→8s, 최대 3회) | 단일 세션 crash 자동 복구 |
| 23 | App | A-2: 세션 state serialization (검색어/클립 큐/Following 필터) + 시작 시 복원 옵트인 | 재시작 후 작업 연속성 |

### Phase 3 — P2 강화 (4~6 주)

| # | 영역 | 작업 | 산출 KPI |
|---|---|---|---|
| 24 | Home | "Operations Mode" 토글 (insight dock 기본 ON) — 일반/운영 모드 분리 | 운영자 만족 |
| 25 | Live | L-5: Dead 채팅 패널 (`ChatPanelView`, `ChatOnlyView`) 제거 또는 명시적 deprecation | 코드 LOC −10% |
| 26 | Player | P-5: Engine 전환 정책을 진단 패널에 노출 (왜 VLC 인지, 왜 AVPlayer 인지) | UX 투명성 |
| 27 | Player | P-6: 선택 세션도 LPM 시 contentsScale 0.875× 옵션 (사용자 토글) | 추가 −8% GPU |
| 28 | Category | C-2: Grid 카드 컨텍스트 메뉴에서 카테고리 핀 토글 | 핀 사용률 ↑ |
| 29 | Search | FS-2: Clip 검색 UX 명시 ("이 채널의 클립" 라벨링) + Top 채널 커버리지 확장 | 사용자 기대 일치 |
| 30 | Search | FS-3: `searchSessionId` token + 응답 stale 무시 로직 | race 무시 100% |
| 31 | Metrics | M-4: Ops Timeline 이벤트 (latency spike, WS fallback, recovery, DB issue) — severity badge + ring buffer 200 events | 운영 가시성 |
| 32 | BI | BI-3: 응답 캐시 + WS reconciliation (revision counter / ETag) | stale UI 0 |
| 33 | App | A-3: Deep link 스펙 문서화 + `DeepLinkRouter` 통합 라우팅 테이블 | 외부 통합 가능 |

---

## 3. 구체 튜닝 타깃

### 3.1 성능 KPI

| 지표 | 현재 | 목표 | 튜닝 포인트 |
|---|---|---|---|
| 홈 메뉴 진입 frame drop | 1~2 frame | < 1 frame | H-1, H-3 |
| 홈 동시 썸네일 task | 20+ | ≤ 8 | H-2, H-4 |
| 멀티라이브 4세션 idle CPU | 35~50% | < 30% | Phase C/D/E 검증 + L-3 |
| Latency 루프 oscillation | ±0.3s | ±0.15s | P-1/P-2, PID Kp 0.5→0.4, Ki 0.05→0.03 |
| 채팅 100 메시지 렌더 | 45 fps | ≥ 55 fps | L-3 |
| Category split layout 전환 | jank/black | smooth | C-1 |

### 3.2 메모리 KPI

| 컴포넌트 | 현재 추정 | 목표 | 튜닝 |
|---|---|---|---|
| Home scene + cache | ~80MB | < 60MB | 썸네일 캐시 cap 축소 |
| 멀티라이브 4세션 + 채팅 | ~250MB | < 180MB | 비선택 세션 layer pool dealloc |
| Metrics overview + 50 row 테이블 | ~40MB | < 25MB | M-3 lazy row |
| Clip Reel Desk (200 클립) | ~120MB | < 80MB | CL-1/CL-3 페이지네이션 |

### 3.3 네트워크 KPI

| 흐름 | 현재 | 목표 | 튜닝 |
|---|---|---|---|
| 홈 진입 동시 API | 3~4 | 2 (직렬) | H-3 |
| 검색 응답 시간 | 600~800ms | < 400ms | FS-3 + 캐시 |
| Metrics polling | 30s 고정 | adaptive 30~90s, Battery 90s | N-5 |
| Clip prefetch | 8 clips aggressive | scroll velocity 기반 lazy | CL-3 |

### 3.4 PID/ABR 측정 후크 (P0 #4의 산출물)

```text
PerformanceOverlay v2 (Player section)
  • bufferOscillationCount   (per 60s)
  • seekFrequency            (per 60s)
  • pidOutput               (-1.0 ... +1.0)
  • ewmaLatencyError        (s)
  • abrCapEvents            (count)
  • thermalState            (.nominal | .fair | .serious | .critical)
  • lpmActive               (bool)
```

---

## 4. 검증 전략

1. **Build/Lint** — `xcodebuild -scheme CView_v2 -configuration Debug build` 무 경고 / `swiftlint`
2. **Snapshot Test** — Live/Category/Search/Clip/Metrics 각 메뉴, 폭 860/1080/1320/1600 (총 20개 스냅샷)
3. **Performance Trace** — Instruments Time Profiler / SwiftUI / Animation Hitches 30s, 다음 시나리오:
   - 홈 진입 → Live 진입 → 멀티라이브 4세션 → 클립 → 카테고리 → 메트릭
4. **Battery 시나리오** — `pmset` 로 LPM 강제 + powermetrics 30s, Phase 1 #8 적용 전후 wake-up 비교
5. **Crash/Recovery** — MultiLive 자식 프로세스 SIGKILL 후 자동 respawn 확인 (Phase 2 #22)
6. **Latency Telemetry** — 30분 라이브 시청, PID overlay 의 oscillation/seek 분포 수집

---

## 5. 수용 기준 (Done Definition)

- 모든 P0 작업이 KPI 목표를 만족 (재현 가능 측정)
- 모든 P1 작업이 PR + 회귀 테스트 + 변경 로그 문서화 완료
- `optimization-tuning-roadmap-2026-04-30.md` (본 문서) 의 체크리스트가 PR 단위로 inline check
- Metrics 와 Player 의 신규 텔레메트리가 Grafana 대시보드에 노출 (BI-1 완료 이후)

---

## 부록 A. 우선순위 매트릭스 (한눈에)

```
영역      P0                            P1                                 P2
Home      H-1, H-2                     H-3, H-4, H-5                       H-6, Operations Mode
Live      L-1                          L-2, L-3, L-4                       L-5
Player    P-1, P-2                     P-3, P-4                            P-5, P-6
Search    FS-1                         FS-2, FS-3                          —
Category  —                            C-1                                 C-2
Clips     CL-1                         CL-2, CL-3, CL-4                    —
Metrics   M-1, M-2                     M-3                                 M-4
Settings  —                            S-1, S-2                            —
Network   N-1                          N-2..N-5                            —
Server BI —                            BI-1, BI-2                          BI-3
App Shell —                            A-1, A-2, A-4                       A-3
```

## 부록 B. 의존성 / 순서 권고

```
H-1 ─────────┐
H-2 ─────────┤
L-1 ─────────┤── (P0 묶음, 1주차)
P-1/P-2 ─────┤
N-1 ─────────┘
                      ↓
FS-1 → A-4 (Palette 통합)
                      ↓
CL-1 → CL-2 → CL-3 → CL-4 (Clip 컴포넌트화 후 인스펙터/도크 안정화)
                      ↓
M-1 → M-2 → M-3 → M-4 (Metrics 분해 후 Channels 테이블, 마지막에 Ops Timeline)
                      ↓
BI-1 → BI-2 → BI-3 (docker → 링크 → reconciliation)
```

---

*작성: 2026-04-30. 본 로드맵은 4월 재설계 사이클 종료 시점의 스냅샷이며, Phase 1 완료 후 재평가 필요.*
