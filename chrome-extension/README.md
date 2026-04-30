# CView Chzzk Metrics Collector — Chrome Extension (MV3)

Tampermonkey UserScript v3.6.0(`docker/scripts/tampermonkey-chzzk-metrics.user.js`)을 Chrome MV3 확장으로 1:1 포팅한 버전입니다. UserScript는 그대로 유지되며 두 방식은 병렬로 운용 가능합니다.

## 주요 기능

- **Foreground 수집** (`collectorMode: 'foreground-video'`) — 치지직 라이브 페이지 탭에서 HLS.js / video element / m3u8 응답을 후킹하여 실시간 메트릭 수집·전송
- **Background HLS 수집** (`collectorMode: 'background-hls'`) — CView 앱이 보고한 활성 채널을 별도의 페이지 로드 없이 청크리스트 m3u8을 직접 폴링해 메트릭 수집
- **JWT 인증 + 백오프** — `/api/auth/token` 호출, AUTH_BACKOFF_STEPS_MS(5/15/30/60/300s)에 따른 지수 백오프
- **Analytics 연동** (Grafana, 2026-04-29~) — `cv.dododo.app/` 루트의 `/api/health` / `/dashboards` / `/explore` 로 원클릭 진입, 옵션 페이지에서 URL 커스터마이징 (구 Superset 연동은 alias 로 1 릴리스 동안 호환)
- **상태 오버레이** — 치지직 페이지 우하단 미니 패널 (UserScript와 동일 스타일/엔진 배지)
- **팝업 + 옵션 페이지** — `GM_registerMenuCommand` 대체

## 아키텍처

| 컴포넌트 | 위치 | 비고 |
|---|---|---|
| Service worker | `src/background/service-worker.js` | MV3 entry, 모듈 타입 |
| Auth/Metrics | `src/background/auth.js` | JWT 캐시 + 401 invalidation |
| Chzzk fetchers | `src/background/chzzk-fetchers.js` | live-detail / m3u8 (host_permissions로 CORS bypass) |
| BG collector | `src/background/bg-collector.js` | 상태머신 (idle→resolving→collecting→degraded→stopped) |
| FG collector | `src/background/foreground-collector.js` | 탭별 sample 요청 후 sendMetrics |
| Page hooks | `src/content/page-hooks.js` | MAIN world: HLS.js Proxy, fetch/XHR 후킹 |
| Bridge | `src/content/bridge.js` | ISOLATED ↔ MAIN 메시지 중계 |
| Status overlay | `src/content/status-overlay.js` | DOM 패널 |
| Offscreen | `src/offscreen/` | 5초 setInterval (chrome.alarms 30s 최소값 우회) |
| Popup | `src/popup/` | 빠른 토글/현황 |
| Options | `src/options/` | App Secret / Server URL / Debug |
| Shared | `src/shared/{config,storage,m3u8-parser}.js` | 모듈 공통 |

> ⚠️ `m3u8-parser.js`는 `page-hooks.js`에 동일 함수가 인라인 복사되어 있습니다. 변경 시 양쪽 모두 수정 필요.

## 설치 (개발자 모드)

1. Chrome 116+ 에서 `chrome://extensions` 열기
2. 우상단 **개발자 모드** 켜기
3. **압축해제된 확장 프로그램을 로드합니다** → `docker/chrome-extension/` 선택
4. 확장 아이콘 → **설정 / 진단** 또는 우클릭 → **옵션** 으로 이동
5. **App Secret** 입력 → 저장 → **인증 테스트** 로 200 OK 확인

## 권한

| 권한 | 용도 |
|---|---|
| `storage` | App Secret, Server URL, Debug 토글 |
| `alarms` | 60초 주기 app-channels 폴링, foreground tick |
| `notifications` | 인증 실패 등 사용자 알림 (확장 가능) |
| `scripting` | (예약) 동적 스크립트 주입 |
| `offscreen` | 5초 BG HLS 폴링 setInterval 호스팅 |
| `host_permissions` | chzzk.naver.com, api.chzzk.naver.com, *.naver.net, *.pstatic.net, cv.dododo.app(:8443), localhost, 127.0.0.1 |

## 메시지 프로토콜

- **page → bridge → SW** : `window.postMessage({__cview:'cview-page-hook', type, payload})` → `chrome.runtime.sendMessage({kind:'page-event', type, payload, channelId})`
- **SW → bridge → page** : `chrome.tabs.sendMessage({target:'page', type:'sample-request'})` → `window.postMessage({__cview:'cview-bridge', type:'sample-request', reqId})`
- **SW → overlay** : `chrome.tabs.sendMessage({target:'overlay', type:'status-update', payload})`
- **offscreen → SW** : `chrome.runtime.sendMessage({kind:'offscreen-bg-tick'})`

## 알려진 제약

- Chrome MV3 service worker는 idle 시 종료될 수 있음 → BG 수집 활성 시 offscreen document가 열려 있으므로 SW도 함께 wake 유지됨
- 아이콘은 placeholder (CV 텍스트). 배포 전 교체 필요
- Chrome Web Store 배포 미설정 — `unpacked` 또는 `.crx` 만 지원

## UserScript와의 차이

| 항목 | UserScript | Chrome Extension |
|---|---|---|
| 메뉴 | `GM_registerMenuCommand` | popup + options |
| 알림 | `GM_notification` | `chrome.notifications` |
| 저장소 | `GM_setValue/getValue` | `chrome.storage.local` |
| CORS bypass | `GM_xmlhttpRequest` | `host_permissions` |
| BG 폴링 | UserScript는 페이지 컨텍스트 setInterval | offscreen document setInterval |
| 페이지 후킹 | `unsafeWindow` | content_scripts world: MAIN |

## 디버깅

- **Service worker 콘솔**: `chrome://extensions` → 본 확장 → "service worker" 링크 클릭
- **Offscreen 콘솔**: 동일 페이지 → "offscreen" 링크
- **Page hooks 콘솔**: 치지직 라이브 페이지 DevTools (필터 `[CView Metrics`)
- 팝업의 **진단 정보** 또는 옵션 페이지의 진단 패널에서 현재 상태 dump

## Analytics 연동 (Grafana, 2026-04-29~)

운영 서버는 API(`https://cv.dododo.app:8443`)와 Analytics 대시보드(`https://cv.dododo.app/`, Grafana)가 다른 포트로 reverse-proxy 됩니다. 확장은 두 endpoint를 별도로 추적합니다.

> **2026-04-29 마이그레이션**: 기존 Superset(`/superset/*`)은 Grafana 루트(`/`)로 교체 중입니다. `popup-superset-*` 메시지와 `buildStatus().superset` 필드는 1 릴리스 동안 alias 로 유지됩니다. 새 코드는 `popup-analytics-*` / `buildStatus().analytics` 를 사용하세요.

| 위치 | 동작 |
|------|------|
| Popup → Analytics 카드 | `/api/health` 결과 + 대시보드 / Explore 원클릭 진입 |
| Options → Analytics 섹션 | URL 커스터마이징, Health 체크, 빠른 진입 |
| `popup-analytics-health` SW 메시지 (alias: `popup-superset-health`) | `${ANALYTICS_URL}/api/health` GET (4s timeout, Grafana JSON `database:ok` 또는 plain `OK` 허용) |
| `popup-open-analytics` SW 메시지 (alias: `popup-open-superset`) | `target: 'dashboards' \| 'explore'` 새 탭 열기 |
| `buildStatus().analytics` (alias: `buildStatus().superset`) | `{ url, dashboardUrl, exploreUrl, sqllabUrl, lastHealth, lastStatus, lastCheckedAt, lastError }` |

기본값은 Server URL의 호스트(`cv.dododo.app`)에서 자동 도출되며, 다른 포트(예: `:8443`)는 Analytics URL 산출 시 제거됩니다 (`deriveAnalyticsUrl`). 사용자가 옵션 페이지에서 직접 입력하면 자동 도출보다 우선합니다. `chrome.storage.onChanged` 리스너가 SW 재시작 없이 즉시 반영합니다.

storage key 는 `analyticsUrl` 입니다. 기존 `supersetUrl` 만 저장된 경우 SW/Options 부팅 시 host 만 추출하여 `analyticsUrl` 로 1회 migration 후 정리됩니다.

호스트 허용목록은 `cv.dododo.app`, `localhost`, `127.0.0.1` 로 Server URL과 동일합니다 (`SERVER_URL_ALLOWED_HOSTS`).
