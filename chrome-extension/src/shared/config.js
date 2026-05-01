// CView Chzzk Metrics — Chrome Extension MV3
// Shared config — used by service worker, page hooks, popup/options
// Loaded via importScripts/import in worker, or as <script> in page hooks (inlined manually).
//
// NOTE: page-hooks.js runs in MAIN world without ES module support and inlines a
// copy of CONFIG via the bridge. Keep this file the source of truth for SW.

export const CONFIG = {
  VERSION: '3.7.4',
  SCHEMA_VERSION: 2,
  SETTINGS_VERSION: 1,

  // 서버 기본값
  SERVER_URL: 'https://cv.dododo.app:8443',
  API_METRICS: '/api/metrics/web',
  API_AUTH: '/api/auth/token',
  API_APP_CHANNELS: '/api/app-channels',
  API_WEB_POSITION: '/api/web-position',
  DEVICE_ID: 'chrome-extension-chzzk-collector',

  // Analytics dashboard (Grafana). API 서버와 동일 호스트의 443 포트에서 reverse-proxy 됨
  // (cv.dododo.app:8443 → API, cv.dododo.app/ → Analytics)
  // 2026-04-29: Superset 을 Grafana 로 교체 중. 구 상수 (`SUPERSET_*`) 은
  // 1개 릴리스 동안 하위 호환 alias 로 유지만, 샠 경로는 ANALYTICS_* 를 사용.
  ANALYTICS_URL: 'https://cv.dododo.app',
  ANALYTICS_HEALTH_PATH: '/api/health', // Grafana health endpoint
  ANALYTICS_DASHBOARD_PATH: '/dashboards',
  ANALYTICS_EXPLORE_PATH: '/explore',
  ANALYTICS_HEALTH_TIMEOUT_MS: 4000,
  // Grafana 대시보드 UID 매핑 (서버 grafana/dashboards/*.json 의 uid 필드와 1:1)
  // popup quick-link 및 deeplink (`/d/<uid>`) 에 사용. 키 순서가 popup 버튼 순서.
  ANALYTICS_DASHBOARDS: {
    overview:    { uid: 'cview-overview',   title: '개요',     icon: '📊' },
    'app-player':{ uid: 'cview-app-player', title: '앱 재생',  icon: '🎬' },
    'vlc-quality':{uid: 'cview-vlc-quality',title: 'VLC 품질', icon: '📡' },
    system:      { uid: 'cview-system',     title: '시스템',   icon: '🖥️' },
  },

  // 레거시 Superset alias (deprecated 2026-04-29, 다음 릴리스에 제거)
  SUPERSET_URL: 'https://cv.dododo.app',
  SUPERSET_HEALTH_PATH: '/api/health',
  SUPERSET_DASHBOARD_PATH: '/dashboards',
  SUPERSET_SQLLAB_PATH: '/explore',
  SUPERSET_HEALTH_TIMEOUT_MS: 4000,

  // 주기
  COLLECT_INTERVAL: 3000,
  CHZZK_API_INTERVAL: 30000,
  APP_CHANNEL_POLL_INTERVAL: 10000,
  BG_HLS_POLL_INTERVAL: 5000,
  BG_BROADCAST_INTERVAL: 30000,
  // /api/web-position push 주기 (page-driven, 문서 §4.3 / §7)
  WEB_POSITION_INTERVAL_VISIBLE_MS: 1000,
  WEB_POSITION_INTERVAL_HIDDEN_MS: 5000,
  WEB_POSITION_BURST_COUNT: 3,
  WEB_POSITION_BURST_GAP_MS: 250,

  // 한계
  MIN_VALID_LATENCY_MS: 100,
  MAX_VALID_LATENCY_MS: 30000,
  BG_MAX_CONSECUTIVE_FAILS: 36,
  BG_MAX_NO_SUCCESS_MS: 5 * 60 * 1000,
  LIVE_DETAIL_TTL_MS: 30 * 1000,
  JITTER_MAX_MS: 1000,
  LOG_SAMPLE_INTERVAL: 10,

  INTERVAL_BOUNDS: {
    COLLECT_INTERVAL: { min: 1000, max: 60000 },
    APP_CHANNEL_POLL_INTERVAL: { min: 5000, max: 300000 },
    BG_HLS_POLL_INTERVAL: { min: 3000, max: 60000 },
  },
};

export const SERVER_URL_ALLOWED_HOSTS = new Set([
  'cv.dododo.app',
  'localhost',
  '127.0.0.1',
]);

export const AUTH_BACKOFF_STEPS_MS = [5000, 15000, 30000, 60000, 300000];

/** 사용자 입력 서버 URL을 검증·정규화. 잘못된 값은 null. */
export function normalizeServerUrl(input) {
  if (typeof input !== 'string') return null;
  const trimmed = input.trim();
  if (!trimmed) return null;
  let u;
  try { u = new URL(trimmed); } catch { return null; }
  const isLocal = u.hostname === 'localhost' || u.hostname === '127.0.0.1';
  if (u.protocol !== 'https:' && !(isLocal && u.protocol === 'http:')) return null;
  if (!SERVER_URL_ALLOWED_HOSTS.has(u.hostname)) return null;
  return `${u.protocol}//${u.host}`;
}

/**
 * API SERVER_URL(`https://cv.dododo.app:8443`)을 기반으로 Analytics(=Grafana) base URL을 도출한다.
 *  - 호스트가 cv.dododo.app 이면 포트 없는 root → `https://cv.dododo.app`
 *  - localhost/127.0.0.1 이면 동일 오리지의 root
 * 2026-04-29: 이전에는 `/superset` 경로를 붙였으나, 운영 nginx 가 root 를
 * Grafana 로 교체하므로 경로를 붙이지 않는다.
 * 잘못된 URL 은 CONFIG.ANALYTICS_URL fallback.
 */
export function deriveAnalyticsUrl(serverUrl) {
  if (!serverUrl) return CONFIG.ANALYTICS_URL;
  let u;
  try { u = new URL(serverUrl); } catch { return CONFIG.ANALYTICS_URL; }
  if (u.hostname === 'cv.dododo.app') {
    return `${u.protocol}//${u.hostname}`;
  }
  return `${u.protocol}//${u.host}`;
}

/** @deprecated 2026-04-29 → deriveAnalyticsUrl. 구 호출자 호환용. */
export function deriveSupersetUrl(serverUrl) {
  return deriveAnalyticsUrl(serverUrl);
}

/** 사용자 입력 Analytics URL 검증·정규화. */
export function normalizeAnalyticsUrl(input) {
  if (typeof input !== 'string') return null;
  const trimmed = input.trim().replace(/\/+$/, '');
  if (!trimmed) return null;
  let u;
  try { u = new URL(trimmed); } catch { return null; }
  const isLocal = u.hostname === 'localhost' || u.hostname === '127.0.0.1';
  if (u.protocol !== 'https:' && !(isLocal && u.protocol === 'http:')) return null;
  if (!SERVER_URL_ALLOWED_HOSTS.has(u.hostname)) return null;
  return `${u.protocol}//${u.host}${u.pathname.replace(/\/+$/, '')}`;
}

/** @deprecated 2026-04-29 → normalizeAnalyticsUrl. */
export function normalizeSupersetUrl(input) {
  return normalizeAnalyticsUrl(input);
}
