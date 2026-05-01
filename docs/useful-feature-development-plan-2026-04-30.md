# CView 유용 기능 정밀 개발 계획서

> 작성일: 2026-04-30  
> 범위: macOS Swift 6 앱, WidgetKit 확장, Chrome MV3 metrics collector, `server-dev/mirror` Grafana/metrics 서버  
> 산출물 성격: 코드 변경 전 개발 계획서. 현재 구현을 보존하면서 붙일 수 있는 기능을 우선순위화한다.

---

## 1. 결론

현재 CView는 단순 Chzzk 뷰어가 아니라 **저지연 재생, 멀티라이브, 멀티채팅, 클립 탐색, 위젯, 메트릭 서버**를 이미 갖춘 macOS 시청 워크스페이스다. 따라서 새 기능은 화면을 더 늘리는 방향보다 다음 5개 축으로 묶는 것이 효율적이다.

1. **시스템 통합**: Command Palette, Deep Link, Widget을 App Intents/Shortcuts/Spotlight까지 연결한다.
2. **시청 연속성**: 라이브/멀티/채팅/클립/검색 상태를 세션 단위로 복원한다.
3. **재생 안정성 가시화**: LowLatency/ABR/Proxy/Engine 상태를 사용자가 이해 가능한 "품질 가드레일"로 노출한다.
4. **Moment/Clip 흐름**: 라이브 중 순간 마커, 로컬 녹화, 클립 큐, Watch Later를 하나의 미디어 워크플로로 합친다.
5. **운영 관측성**: Grafana provisioning/alerts와 앱 내 Metrics Dashboard를 같은 계약으로 묶는다.

가장 먼저 할 일은 **App Intents + Session Continuity + Playback Guardrail**이다. 세 기능은 기존 구조 위에 얹을 수 있고, 홈/라이브/검색/위젯/메트릭을 동시에 더 유용하게 만든다.

---

## 2. 현재 프로젝트 앵커

| 영역 | 현재 구현 근거 | 계획에 주는 의미 |
|---|---|---|
| 앱 쉘 | `MainContentView`는 `NavigationSplitView` + 사이드바 route로 홈/라이브/카테고리/검색/클립/메트릭/설정을 직접 분기한다. `home.useV2`가 기본 홈을 선택한다. (`Sources/CViewApp/Views/MainContentView.swift:83`, `:120`) | 새 기능은 top-level route를 늘리기보다 기존 route 내부 액션으로 넣는다. |
| 라우팅 | `AppRoute.search(query:)`, `pendingSearchQuery`, `pendingWatchChannelId`, `navigateToWatch(channelId:)`가 이미 있다. (`Sources/CViewApp/Navigation/AppRouter.swift:11`, `:71`, `:75`, `:216`) | App Intents/Widget/Deep Link가 사용할 단일 라우팅 계약을 만들기 좋다. |
| 홈 | 홈 v2는 command bar, hero, following live, continue watching, favorites, recommendation, top channels, compact insights 구조다. (`Sources/CViewApp/Views/HomeV2/HomeView_v2.swift:4`) | 홈에는 "요약 + 다음 행동"만 두고, 무거운 기능은 deep link/action으로 연결한다. |
| 라이브 허브 | `FollowingHubMode`는 `탐색/시청/멀티`, 하단 sheet와 chat dock 상태를 가진다. (`Sources/CViewApp/ViewModels/FollowingViewState.swift:7`, `:54`, `:69`, `:125`) | 세션 복원과 mode preset을 제품 기능으로 승격할 수 있다. |
| 검색 | 검색 결과 row에서 멀티라이브/멀티채팅 추가, 채널 상세, 링크 복사가 이미 가능하다. (`Sources/CViewApp/Views/SearchViews.swift:113`) | 검색은 "찾기"가 아니라 "바로 실행" 허브로 확장한다. |
| 클립 | 클립 메뉴는 trending/channel, queue/watch later, channel URL resolver, embed fallback + VLC 전환을 갖는다. (`Sources/CViewApp/Views/PopularClipsView.swift:35`, `:108`; `Sources/CViewApp/ViewModels/ClipPlayerViewModel.swift:99`) | 라이브 순간 마커와 클립 큐를 연결하면 미디어 워크플로가 완성된다. |
| 녹화 | `StreamRecordingService`는 HLS 세그먼트 기반 녹화와 AES-128-CBC 복호화를 지원한다. (`Sources/CViewPlayer/StreamRecordingService.swift:31`) | "Moment Marker"는 새 엔진이 아니라 기존 녹화 서비스 위의 UX/메타데이터 기능으로 시작한다. |
| 재생 파이프라인 | `StreamCoordinator`가 API -> manifest -> ABR -> player -> sync를 오케스트레이션하고, 독립 `LocalStreamProxy`와 watchdog을 가진다. (`Sources/CViewPlayer/StreamCoordinator.swift:11`, `:80`, `:132`) | 안정성 기능은 여기의 snapshot/event를 더 잘 수집하고 화면화하는 방식이 적합하다. |
| 저지연 | `LowLatencyController.webSync`는 6초 타겟, PID, drift phase, oscillation telemetry를 이미 포함한다. (`Sources/CViewPlayer/LowLatencyController.swift:54`, `:108`, `:123`) | "웹과 맞추기/최저 지연/안정 우선" preset을 실제 컨트롤러 설정으로 연결한다. |
| ABR | `ABRController`는 dual EWMA, buffer-aware context, multiLive profile, max bitrate cap을 가진다. (`Sources/CViewPlayer/ABRController.swift:11`, `:48`, `:113`, `:147`) | 멀티라이브 대역폭 예산/품질 가드레일을 사용자에게 설명할 수 있다. |
| Segment proxy | 세그먼트 chunk forward, TTFB, fetch sample 기록이 있다. (`Sources/CViewPlayer/LocalStreamProxy+SegmentStream.swift:4`, `:36`, `:137`) | 품질 저하 원인을 "CDN TTFB/segment fetch/buffer"로 분해할 수 있다. |
| 메트릭 | 앱은 JWT, device id, cache, `/api/auth/token`, health check, direct port routing을 처리한다. (`Sources/CViewNetworking/MetricsAPIClient.swift:7`, `:25`, `:101`) | 서버 계약을 기능 개발 전에 명시하고, 운영 대시보드와 앱 상태를 동기화한다. |
| 실시간 메트릭 | `MetricsWebSocketClient`는 AsyncStream, subscribe/unsubscribe, 무한 재연결을 가진다. (`Sources/CViewNetworking/MetricsWebSocketClient.swift:7`, `:49`, `:86`, `:165`) | live health/alert surface에 바로 연결할 수 있다. |
| 위젯 | 4개 WidgetKit 위젯과 AppIntent 기반 단일 채널 위젯이 있다. (`CViewWidgets/CViewWidgetsBundle.swift:8`, `CViewWidgets/Widgets/SingleChannelWidget.swift:16`) | 위젯을 "보기"에서 "동작 진입점"으로 확장할 수 있다. |
| 브라우저 collector | Chrome MV3 확장은 foreground/background HLS 수집, JWT, Grafana deep link, offscreen tick을 갖는다. (`chrome-extension/README.md:5`, `:83`) | 웹-앱 drift 비교와 analytics health를 제품 기능으로 더 노출할 수 있다. |

---

## 3. 외부 검색 근거

| Source | 핵심 관찰 | CView 적용 |
|---|---|---|
| Apple HIG - Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars | macOS toolbar는 자주 쓰는 명령, 탐색, 검색을 담되 overflow와 메뉴바 command를 함께 고려해야 한다. | Command Palette와 toolbar/action을 같은 명령 모델로 통합한다. |
| Apple HIG - Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars | Sidebar는 여러 peer 영역을 동시에 접근시키는 구조지만, 공간이 제한되면 더 compact한 제어가 필요하다. | 현재 sidebar route는 유지하고, 내부 화면은 mode bar/sheet/dock 중심으로 압축한다. |
| Apple WidgetKit: https://developer.apple.com/documentation/WidgetKit/ | Widget은 앱 밖에서 glanceable 정보와 focused interaction을 제공하고 timeline 기반 갱신으로 에너지 효율을 유지한다. | 위젯 refresh interval, deep link, AppIntent action을 계획에 포함한다. |
| Apple App Shortcuts: https://developer.apple.com/documentation/appintents/app-shortcuts | 핵심 기능은 App Intents로 노출하면 Shortcuts/Spotlight/Siri에서 설치 직후 발견 가능하다. | `OpenLive`, `AddToMultiLive`, `SwitchLiveMode`, `OpenMetrics` intents를 만든다. |
| Apple Low-Latency HLS: https://developer.apple.com/documentation/http-live-streaming/enabling-low-latency-http-live-streaming-hls | LL-HLS는 partial segments, delta updates, blocking reload, preload hints, rendition reports로 지연을 줄인다. | manifest feature detection과 proxy/ABR telemetry를 가드레일에 포함한다. |
| Apple `preferredForwardBufferDuration`: https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration | 낮은 forward buffer는 stall 위험을 키우고, 높은 buffer는 리소스 사용을 늘린다. | 안정/저지연 preset을 단순 "낮게"가 아니라 상황별 목표로 설계한다. |
| Apple PiP: https://developer.apple.com/documentation/AVKit/AVPictureInPictureController | PiP 가능 여부를 runtime에서 확인하고 지원 상태에 맞춰 UI를 제공해야 한다. | VLC/AVPlayer engine 차이를 진단 UI와 PiP fallback 정책에 반영한다. |
| hls.js API: https://github.com/video-dev/hls.js/blob/master/docs/API.md | `liveSyncDurationCount`, `targetLatency`, `liveSyncOnStallIncrease`, `liveMaxLatency*` 같은 latency knobs가 stall과 직접 연결된다. | `LowLatencyController.webSync`와 브라우저 collector 비교값을 같은 용어로 매핑한다. |
| Twitch Clips: https://dev.twitch.tv/docs/api/clips/ | 클립 생성은 비동기이고, 약 90초 capture window에서 5~60초 클립을 선택하는 UX가 일반적이다. | Chzzk API 제약과 별개로 "Moment Marker -> 후보 구간 -> 클립/녹화/북마크" 워크플로를 설계한다. |
| Twitch EventSub WebSocket: https://dev.twitch.tv/docs/eventsub/websocket-reference/ | WebSocket event는 message id, keepalive, reconnect, revocation을 명시한다. | CView metrics/chat event stream도 dedupe id, keepalive age, reconnect reason을 UI에 보여준다. |
| YouTube LiveChat `streamList`: https://developers.google.com/youtube/v3/live/docs/liveChatMessages/streamList | live chat은 server-streaming 방식이 polling보다 저지연/효율적이다. | 멀티채팅은 polling형 보조 루프보다 stream 상태와 backpressure를 명시한다. |
| Grafana provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/ | data source/dashboard를 파일로 provisioning하고 UID 기반 URL을 재사용할 수 있다. | `server-dev/mirror/grafana`를 배포 가능한 dashboard-as-code로 고정한다. |
| Grafana Alerting provisioning: https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/ | alert rule/contact point/policy를 파일, Terraform, HTTP API로 관리할 수 있다. | latency spike, WS fallback, collector offline을 alert rule로 만든다. |

---

## 4. 기능 후보와 개발 계획

### F1. System Action Layer

**목표**  
앱 내부 Command Palette, 위젯 deep link, URL scheme, Shortcuts/Spotlight를 하나의 action registry로 통합한다.

**왜 유용한가**  
사용자는 "라이브 열기", "멀티라이브에 추가", "멀티 모드 전환", "메트릭 열기"를 앱 내부 메뉴를 거치지 않고 실행할 수 있다. 현재 `CommandPaletteView`, `AppRouter.pendingSearchQuery`, `pendingWatchChannelId`, Widget deep link가 이미 흩어져 있으므로 통합 비용이 낮다.

**구현 범위**

| 작업 | 대상 |
|---|---|
| `CViewAction` enum 도입: `openLive`, `openChannel`, `addMultiLive`, `addMultiChat`, `switchLiveMode`, `openClip`, `openMetrics`, `search` | `Sources/CViewApp/Navigation`, 신규 `Sources/CViewApp/Actions` |
| `CommandPaletteView` 명령 생성 로직을 `CViewActionRegistry`로 이동 | `CommandPaletteView.swift` |
| URL scheme 확장: `cview://search?q=`, `cview://clip?id=`, `cview://metrics`, `cview://live?channelId=&mode=watch` | `DeepLinkRouter.swift` |
| App Intents 추가: `OpenLiveIntent`, `AddToMultiLiveIntent`, `SwitchLiveModeIntent`, `OpenMetricsIntent` | 신규 `Sources/CViewApp/Intents` |
| Widget Link를 새 deep link 계약으로 정리 | `CViewWidgets/Providers/WidgetCommon.swift` |

**수용 기준**

- Spotlight/Shortcuts에서 특정 채널 라이브 열기 가능.
- Widget tap이 `FollowingView`의 `watch` mode로 바로 들어간다.
- Command Palette와 AppIntent가 같은 action validation을 사용한다.
- route/action 단위 테스트가 `DeepLinkRouter`와 `AppRouter`를 함께 검증한다.

---

### F2. Live Session Continuity

**목표**  
앱을 재실행하거나 메뉴를 왕복해도 사용자의 시청 맥락이 유지되게 한다.

**현재 기반**  
`FollowingViewState`는 hub mode, sheet state, chat dock focus, following display mode, sheet filter를 갖고 일부는 `UserDefaults`에 저장한다. `AppRouter`는 마지막 sidebar item을 복원한다. 다만 현재 설계상 hub mode/sheet state는 재시작 시 항상 `explore/peek`로 리셋된다.

**기능 설계**

| 하위 기능 | 설명 |
|---|---|
| Workspace Snapshot | `selectedSidebarItem`, `hubMode`, `selectedChannelId`, `multiLiveSessionIds`, `multiChatSessionIds`, `clipQueue`, `searchQuery`를 하나의 snapshot으로 저장 |
| Restore Modes | "항상 탐색으로 시작", "마지막 시청 복원", "멀티 세션만 복원" 3개 정책 제공 |
| Crash-safe session | 저장은 atomic write로 수행하고, 마지막 정상 종료 marker와 비교해 crash 복원 여부를 묻는다 |
| Live Resume Prompt | 오프라인/종료된 채널은 복원에서 제외하고 대체 추천을 보여준다 |

**구현 순서**

1. `WorkspaceSnapshot` 모델과 versioned JSON schema 작성.
2. `DataStore` 또는 별도 `WorkspaceStateStore` actor에 atomic save/load 추가.
3. `AppState` lifecycle에서 foreground/background/terminate 시 저장.
4. `FollowingView`와 `MultiChatSessionManager` 복원 API를 명시화.
5. 설정에 restore policy 추가.

**수용 기준**

- 앱 종료 후 4세션 멀티라이브, 멀티채팅 목록, 마지막 검색어가 복원된다.
- 종료된 라이브는 자동 재생하지 않고 "종료됨" 상태로 표시한다.
- corrupt snapshot은 무시하고 safe default로 시작한다.

---

### F3. Playback Guardrail Center

**목표**  
현재 내부에 숨어 있는 LowLatency/ABR/Proxy/Engine 상태를 사용자가 이해할 수 있는 진단과 preset으로 바꾼다.

**현재 기반**

- `LowLatencyController.webSync`는 웹 동기화용 6초 target latency와 보수적 PID를 갖는다.
- `LatencySnapshot`은 oscillation count, seeks per minute, web phase label, oscillation cap을 포함한다.
- `ABRController`는 buffer-aware context와 multiLive profile, bitrate cap을 가진다.
- `LocalStreamProxy+SegmentStream`은 TTFB와 segment fetch sample을 기록한다.

**기능 설계**

| Preset | 내부 동작 |
|---|---|
| Web Sync | `LowLatencyController.Configuration.webSync`, browser collector drift sample 우선 |
| Lowest Latency | target latency를 낮추되 stall count가 임계값을 넘으면 자동으로 Stability로 승격 |
| Stability | forward buffer/ABR safety를 높이고 `forceHighestQuality`를 자동 해제 |
| Battery Saver | 비선택 멀티 세션 scale/refresh/metric interval을 낮춘다 |
| Manual Lock | 사용자가 선택한 quality variant를 ABR이 override하지 않도록 명시 lock |

**사용자 표면**

- Live stage 상단: `Latency`, `Buffer`, `Quality`, `Proxy`, `Engine` 5개 compact chip.
- Stage Tool Popover: "왜 화질이 내려갔나" reason list.
- Metrics dashboard: 채널별 `targetLatency`, `actualLatency`, `stall/min`, `TTFB p95`, `ABR cap events`.
- Debug export: 최근 5분 playback guardrail log를 JSON으로 저장.

**수용 기준**

- 사용자가 현재 모드와 자동 조치 이유를 한 줄로 이해할 수 있다.
- 30분 라이브 테스트에서 stall 발생 시 preset 전환/ABR 강등/복구 이벤트가 모두 기록된다.
- 멀티라이브 4세션에서 대역폭 cap이 어떤 세션에 적용됐는지 UI에 표시된다.

---

### F4. MultiLive Composer

**목표**  
멀티라이브를 "추가된 타일 목록"이 아니라, 시청 목적별로 조합하고 저장하는 composer로 만든다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Smart Queue Persistence | 현재 `smartQueueChannelIds`를 snapshot에 저장하고, 검색/카테고리/홈에서 같은 queue를 사용 |
| Layout Recipes | `2-up`, `Main+2`, `2x2`, `Focus+Chat`, `PiP` recipe를 명시하고 창 폭별 fallback 정의 |
| Bandwidth Budget View | 세션별 추정 bitrate, cap, downgrade reason을 표시 |
| Audio Focus Rules | 새 세션 추가 시 기존 오디오 mute, 마지막 클릭 세션 solo, 채팅 focus 동기화 |
| Session Health | offline, manifest fail, chat fail, high latency, no metrics를 타일 badge로 표시 |

**구현 대상**

- `FollowingViewState`
- `MultiLiveManager`
- `MultiLiveSession`
- `MultiLiveGridLayouts`
- `MLMetricsWindowView`
- `MultiLiveBandwidthCoordinator`

**수용 기준**

- 사용자가 검색 결과 4개를 queue에 담고 한 번에 `2x2`로 시작할 수 있다.
- 세션별 degrade reason이 "대역폭/버퍼/사용자 lock/서버 오류"로 구분된다.
- 창 폭 860/1080/1320/1600pt에서 레이아웃이 겹치지 않는다.

---

### F5. Moment Marker & Clip Desk

**목표**  
라이브 중 "방금 장면 저장"을 로컬 마커, 녹화, 클립 탐색, Watch Later와 연결한다.

**외부 패턴**  
Twitch Clips는 비동기로 클립을 생성하고 capture window를 둔다. CView는 Chzzk API 제약이 있으므로 플랫폼 클립 생성을 직접 전제로 두지 않고, **로컬 moment marker + recording segment + clip discovery** 흐름부터 만든다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Moment Marker | 현재 채널, program date time, app latency, web drift, chat burst, note를 기록 |
| Replay Candidate | `StreamRecordingService`가 켜져 있으면 marker 앞뒤 N초를 후보 구간으로 표시 |
| Clip Queue Sync | marker에서 관련 채널 클립 검색으로 이동하고, `ClipFilmstripDock` queue에 추가 |
| Watch Later v2 | UID만 저장하지 않고 title, channel, thumbnail, duration, expected url, addedAt을 함께 저장 |
| Moment Export | JSON/CSV export, future server sync optional |

**구현 대상**

- 신규 `MomentMarkerStore`
- `StreamRecordingService`
- `ClipBrowserViewModel`
- `ClipFilmstripDock`
- `PopularClipsView`
- `DataStore`

**수용 기준**

- 라이브 중 단축키 하나로 marker 생성.
- 녹화 중이면 marker 기준 후보 구간이 클립 메뉴에 나타난다.
- 앱 재시작 후 Watch Later와 marker가 thumbnail/title 포함 상태로 복원된다.

---

### F6. Chat Focus & Moderation Toolkit

**목표**  
멀티채팅을 읽기 쉬운 운영 도구로 만든다. 플랫폼 moderator 권한을 대체하지 않고, 앱 로컬 필터/하이라이트/정리 기능을 제공한다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Role/Signal Highlight | 운영자/구독/후원/mention/keyword/emote burst를 색상과 lane으로 구분 |
| Spam Collapse | 동일 메시지/반복 이모티콘/빠른 연속 메시지를 접어서 렌더 비용 감소 |
| Per-channel Backpressure | 4채널 동시 채팅에서 비활성 채널은 render batch interval을 늘린다 |
| Chat Event Timeline | "후원/급증/삭제/연결끊김/재연결" 이벤트를 stage 옆 timeline으로 표시 |
| Local Moderation Rules | 금칙어, 사용자 숨김, 임시 mute를 local profile로 저장 |

**수용 기준**

- 4채널 spam 상황에서 UI thread frame drop이 감소한다.
- 필터 적용 전/후 message rate와 render batch가 Metrics에 남는다.
- local moderation rule은 채널별 override와 global rule을 모두 지원한다.

---

### F7. Observability & Alert-as-Code

**목표**  
앱의 Metrics Dashboard와 Grafana 서버를 같은 운영 모델로 묶는다.

**현재 기반**

- `server-dev/mirror/grafana/dashboards`에 `cview-overview`, `cview-app-player`, `cview-system`, `cview-vlc-quality` JSON이 있다.
- 앱의 `MetricsAPIClient`는 health/JWT/cache를 처리한다.
- `MetricsWebSocketClient`는 channel subscribe와 reconnect loop를 갖는다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Dashboard UID Registry | 앱 deep link와 Grafana JSON UID를 한 파일에서 관리 |
| Alert Rules | latency p95, waitingChannels, collector offline, WS fallback, DB stale alert |
| In-app Alert Inbox | Grafana/metrics server alert를 앱 메트릭 화면과 홈 insight dock에 표시 |
| Health Contract Test | `/api/health`, `/api/stats/overview`, `/api/stats/system`, `/ws` 계약 테스트 |
| Diagnostics Bundle | 앱/extension/server 설정과 최근 로그를 zip으로 묶는 export |

**수용 기준**

- `docker compose up` 후 Grafana datasource/dashboard/alert가 자동 provisioning된다.
- 앱 메트릭 화면에서 현재 값이 WS인지 polling fallback인지 명확히 표시된다.
- server contract test가 CI 또는 로컬 스크립트로 실행 가능하다.

---

### F8. Widget, Menu Bar, Notification Upgrade

**목표**  
현재 위젯을 glanceable 정보에서 "즉시 행동" 표면으로 확장한다.

**현재 기반**

- `FollowingLiveListWidget`, `SingleChannelWidget`, `NowWatchingWidget`, `LiveCountWidget` 4개가 등록되어 있다.
- `SingleChannelWidget`은 AppIntent 기반 configuration을 이미 사용한다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Interactive Widget Actions | macOS 지원 범위 안에서 "멀티라이브에 추가", "열기", "나중에 보기" AppIntent 연결 |
| Menu Bar Mini Hub | live count, now watching, quick switch, mute, screenshot, open metrics |
| Notification Rules | 즐겨찾기 live start, followed category spike, latency degradation, recording stopped |
| Widget Snapshot Quality | 5분 고정 timeline을 live state에 따라 1/5/15분 adaptive로 조정 |

**수용 기준**

- Widget tap/deep link가 F1 action registry를 사용한다.
- 알림은 global on/off, quiet hours, channel/category allowlist를 지원한다.
- 위젯 stale age가 15분을 넘으면 명확히 표시된다.

---

### F9. Discovery Graph

**목표**  
홈/검색/카테고리/클립/최근/즐겨찾기의 추천 데이터를 하나의 discovery graph로 묶는다.

**기능 설계**

| 기능 | 설명 |
|---|---|
| Unified Channel Context | channelId 기준으로 live, category, clips, watch history, favorite, metrics를 합친 context |
| Reasoned Recommendation | "팔로잉", "최근 본 카테고리", "채팅 급증", "클립 인기", "동기화 양호" 같은 추천 사유 표시 |
| Search Session Model | stale search response 방지, all/channel/live/video/clip 결과 session id 통합 |
| Related Clips/Channels | 라이브 시청 중 같은 채널/카테고리 클립과 유사 채널 제안 |

**수용 기준**

- 홈 추천 카드에 최소 1개 이상의 explain reason이 표시된다.
- 검색 결과에서 채널 선택 시 우측 inspector가 live/clips/recent/metrics를 같이 보여준다.
- stale search response를 100% 무시한다.

---

## 5. 우선순위 로드맵

### Phase 0. 계약 정리 (3~5일)

| 작업 | 산출물 |
|---|---|
| `CViewAction`/DeepLink URL 계약 문서화 | `docs/action-routing-contract-2026-05.md` |
| Workspace snapshot schema 작성 | `WorkspaceSnapshot` 모델 초안 |
| Metrics/Grafana UID registry 정리 | `server-dev/mirror/grafana/dashboard-registry.yml` |
| Feature flag 목록 확정 | `SettingsStore` flag plan |

### Phase 1. 빠른 체감 기능 (1~2주)

| 우선순위 | 기능 | 이유 |
|---|---|---|
| P0 | F1 System Action Layer | 기존 route/command/widget을 묶는 고효율 작업 |
| P0 | F2 Live Session Continuity 기본 복원 | 사용자가 매일 체감하는 작업 연속성 |
| P0 | F3 Playback Guardrail compact chips | 저지연/화질 문제를 설명 가능하게 함 |
| P1 | F8 Widget deep link/action 정리 | F1과 같이 처리 가능 |

### Phase 2. 시청 워크스페이스 강화 (2~3주)

| 우선순위 | 기능 | 이유 |
|---|---|---|
| P0 | F4 MultiLive Composer queue + layout recipes | 앱의 핵심 차별점 |
| P0 | F3 preset 자동 전환 + guardrail event log | 품질/안정성 개선 |
| P1 | F6 Chat Focus backpressure + spam collapse | 4채널 멀티채팅 안정성 |
| P1 | F9 Discovery Graph v1 | 홈/검색/카테고리 중복 해소 |

### Phase 3. 미디어 워크플로 (2~3주)

| 우선순위 | 기능 | 이유 |
|---|---|---|
| P0 | F5 Moment Marker | 녹화/클립/시청의 연결점 |
| P1 | Watch Later v2 metadata persistence | 현재 UID-only 한계 제거 |
| P1 | Clip queue + marker + related clips 통합 | 클립 메뉴 사용성 강화 |

### Phase 4. 운영 관측성 (1~2주)

| 우선순위 | 기능 | 이유 |
|---|---|---|
| P0 | F7 Grafana dashboard provisioning validation | 배포 재현성 |
| P0 | Alert-as-code: latency/collector/WS/DB | 장애 조기 감지 |
| P1 | In-app Alert Inbox | 운영 상태를 앱에서 직접 확인 |
| P1 | Diagnostics Bundle | 문제 제보/분석 비용 절감 |

### Phase 5. 배포 품질 (1주)

| 작업 | 검증 |
|---|---|
| app/extension/server feature flag 기본값 정리 | 신규 설치/기존 설치 migration |
| Instruments trace | home -> live -> 4 multi -> clip -> metrics |
| Server contract tests | health/stats/ws/grafana provisioning |
| 위젯/DeepLink/AppIntent E2E | cold start/warm start 모두 |

---

## 6. 구현 순서 상세

### Step 1. Action Registry부터 만든다

`CommandPaletteView`에 명령이 직접 쌓이는 구조를 유지하면 App Intents, 위젯, deep link가 다시 중복된다. 먼저 다음 형태의 registry를 만든다.

```swift
enum CViewAction: Sendable, Hashable {
    case openLive(channelId: String, mode: LiveOpenMode)
    case addToMultiLive(channelId: String)
    case addToMultiChat(channelId: String)
    case switchLiveMode(FollowingHubMode)
    case openSearch(query: String?)
    case openClip(clipUID: String)
    case openMetrics(tab: MetricsDashboardTab?)
}
```

이 registry가 `AppRouter`, `CommandPaletteView`, Widget Link, AppIntent에서 공통으로 사용되어야 한다.

### Step 2. State snapshot은 작게 시작한다

처음부터 모든 화면 상태를 저장하지 않는다. v1은 다음만 저장한다.

- sidebar item
- live hub mode
- multi live channel ids
- multi chat channel ids
- search query
- clip queue/watch later metadata
- timestamp/app version/schema version

이후 category filters, settings subpage, metrics selected channel은 v2로 미룬다.

### Step 3. Playback preset은 내부 설정을 숨기지 않는다

사용자에게는 `Web Sync`, `Lowest Latency`, `Stability`, `Battery Saver`로 보이게 하되, hover/detail에는 실제 내부 값을 보여준다.

- target latency
- current latency
- max playback rate
- ABR enabled/locked
- force highest quality
- TTFB p95
- segment fetch p95
- recent stall count

이렇게 해야 문제 상황에서 "앱이 왜 화질을 낮췄는지" 설명 가능하다.

### Step 4. Moment Marker는 플랫폼 API 의존 없이 시작한다

Chzzk의 공식 클립 생성 가능 여부에 계획이 묶이면 기능이 멈춘다. v1은 로컬 marker와 recording metadata만 저장한다. 외부 클립 생성/공유는 v2에서 API 가능성과 정책을 별도로 검증한다.

---

## 7. 데이터 모델 초안

### WorkspaceSnapshot

```swift
struct WorkspaceSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var appVersion: String
    var savedAt: Date
    var selectedSidebar: String
    var live: LiveWorkspaceSnapshot
    var search: SearchSnapshot
    var clips: ClipWorkspaceSnapshot
}
```

### MomentMarker

```swift
struct MomentMarker: Codable, Identifiable, Sendable {
    var id: UUID
    var channelId: String
    var channelName: String
    var createdAt: Date
    var programDateTime: Date?
    var appLatencyMs: Double?
    var webDriftMs: Double?
    var playbackRate: Double
    var qualityLabel: String?
    var note: String?
    var recordingURL: URL?
}
```

### GuardrailEvent

```swift
struct GuardrailEvent: Codable, Identifiable, Sendable {
    enum Kind: String, Codable {
        case latencyModeChanged
        case abrDowngrade
        case abrRecovery
        case stall
        case proxyTTFBHigh
        case wsFallback
        case engineSwitch
    }

    var id: UUID
    var channelId: String
    var kind: Kind
    var severity: Severity
    var message: String
    var metrics: [String: Double]
    var createdAt: Date
}
```

---

## 8. 테스트/검증 계획

| 검증 축 | 시나리오 | 도구 |
|---|---|---|
| Build | Swift 6 strict concurrency, app/widgets build | `xcodebuild -scheme CView_v2 -configuration Debug build` |
| Action routing | URL scheme, AppIntent, CommandPalette가 같은 action을 실행 | unit test + cold/warm open manual test |
| Session restore | 앱 종료/강제종료 후 live/multi/chat/clip/search 복원 | unit test + manual run |
| Playback | 30분 live, 4세션 multilive, network fluctuation | Instruments, app metrics, Grafana |
| Chat | 4채널 고속 채팅, spam collapse on/off | Time Profiler + render counter |
| Widget | snapshot freshness, deep link route, single channel config | Widget previews + on-device |
| Server | `/api/health`, `/api/stats/*`, `/ws`, Grafana dashboard UID | pytest + smoke script |
| Extension | foreground/background collector, auth backoff, analytics URL | Chrome MV3 dev mode test |

---

## 9. 리스크와 차단 조건

| 리스크 | 영향 | 대응 |
|---|---|---|
| Chzzk 비공식 API 변경 | 검색/클립/라이브 상세 실패 | endpoint wrapper와 fallback UI를 먼저 정리 |
| AppIntent가 app target/module 경계를 건드림 | 빌드 복잡도 증가 | Action registry를 순수 Swift 모델로 분리 |
| 세션 복원이 자동 재생으로 오해될 수 있음 | 사용자 경험/리소스 문제 | restore policy와 "복원 전 확인" 옵션 제공 |
| Lowest latency preset이 stall을 유발 | 품질 불만 | oscillation guard로 자동 Stability 전환 |
| Moment recording의 저작권/정책 이슈 | 배포 리스크 | 로컬 개인 사용/정책 고지, 공유/업로드는 별도 opt-in |
| Grafana provisioning과 UI 수정 충돌 | 운영 대시보드 유실 | dashboard-as-code를 source of truth로 고정 |
| Chrome MV3 offscreen 제한 변화 | collector 불안정 | UserScript 병행 운용과 server-side health alert 유지 |

---

## 10. 최종 백로그

| ID | 우선순위 | 작업 | 주요 파일 |
|---|---|---|---|
| ACT-1 | P0 | `CViewAction`/`CViewActionRegistry` 도입 | `Sources/CViewApp/Actions/*` |
| ACT-2 | P0 | DeepLinkRouter URL 계약 확장 | `DeepLinkRouter.swift`, tests |
| ACT-3 | P0 | App Intents 4종 추가 | `Sources/CViewApp/Intents/*` |
| SES-1 | P0 | `WorkspaceSnapshot` v1 저장/복원 | `AppState`, `DataStore` |
| SES-2 | P1 | crash-safe restore prompt | `MainContentView`, settings |
| PLY-1 | P0 | Playback guardrail chips | `LiveStreamView`, `FollowingView+Redesign2026` |
| PLY-2 | P0 | Guardrail event log | `LowLatencyController`, `ABRController`, `LocalStreamProxy` |
| PLY-3 | P1 | Preset auto-switch 정책 | `SettingsStore`, `StreamCoordinator` |
| MLV-1 | P0 | Smart queue persistence | `FollowingViewState`, `MultiLiveManager` |
| MLV-2 | P0 | Layout recipes + width fallback | `MultiLiveGridLayouts`, `LiveResponsiveBreakpoints` |
| MLV-3 | P1 | Bandwidth budget UI | `MLMetricsWindowView`, `MultiLiveBandwidthCoordinator` |
| MOM-1 | P0 | Moment marker store/model | 신규 `MomentMarkerStore` |
| MOM-2 | P1 | Recording marker integration | `StreamRecordingService`, `MLToolsTab` |
| CLP-1 | P1 | Watch Later v2 metadata | `PopularClipsView`, `DataStore` |
| CHT-1 | P1 | Chat spam collapse/backpressure | `ChatViewModel+Processing`, `MergedChatView` |
| OBS-1 | P0 | Grafana UID registry + provisioning validation | `server-dev/mirror/grafana`, scripts |
| OBS-2 | P0 | Alert-as-code | `server-dev/mirror/grafana/alerting` |
| WDG-1 | P1 | Widget deep link/action 정리 | `CViewWidgets/Providers` |
| WDG-2 | P2 | Menu Bar mini hub | `MenuBarView` |
| DSC-1 | P1 | Unified channel context | `HomeRecommendationEngine`, `SearchViewModel` |

---

## 11. 추천 시작 순서

1. `ACT-1` -> `ACT-2` -> `ACT-3`: 액션 계약을 먼저 고정한다.
2. `SES-1`: 액션/라우팅 위에 세션 복원을 붙인다.
3. `PLY-1` -> `PLY-2`: 재생 문제를 설명 가능한 상태로 만든다.
4. `MLV-1` -> `MLV-2`: 멀티라이브의 핵심 체감 기능을 완성한다.
5. `MOM-1`: 녹화/클립/Watch Later를 묶는 기반을 만든다.
6. `OBS-1` -> `OBS-2`: 서버 운영 상태를 배포 가능한 계약으로 고정한다.

이 순서가 좋은 이유는 간단하다. `Action Registry`와 `Workspace Snapshot`은 뒤에 나오는 Widget, Moment, MultiLive, Metrics 기능이 모두 공유할 기반이고, `Playback Guardrail`은 기존 저지연/ABR/프록시 작업의 효과를 사용자와 운영자가 확인하게 해준다.
