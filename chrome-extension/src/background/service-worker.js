// CView Chzzk Metrics — service worker entry (MV3, type:module)
//
// 책임:
//   • content/bridge로부터 page-event 수신 → foreground collector에 전달
//   • offscreen document를 통한 BG HLS 5초 폴링 오케스트레이션
//   • app-channels 폴링 (chrome.alarms 60s) → 매칭되는 채널 BG 수집 시작
//   • popup/options에 진단 정보 제공
//   • 상태 broadcast → status overlay 갱신

import { CONFIG, deriveAnalyticsUrl } from '../shared/config.js';
import {
  STORAGE_KEYS, getStored, setDebugFlag, log, debug, jitter,
} from '../shared/storage.js';
import {
  authenticate, sendMetrics, fetchAppChannels, setServerUrl, getServerUrl,
  getAuthDiagnostics, resetAuth,
} from './auth.js';
import {
  startBgCollector, stopBgCollector, stopAllBgCollectors,
  tickAll, getBgCollectorSummary,
} from './bg-collector.js';
import {
  ensureTab, dropTab, handlePageEvent, collectAndSend,
  getForegroundSummary, getForegroundForChannel,
} from './foreground-collector.js';

const ALARM_APP_POLL = 'cview-app-channel-poll';
const ALARM_FG_TICK = 'cview-fg-tick';
const OFFSCREEN_PATH = 'src/offscreen/offscreen.html';

let _offscreenStarting = null;

async function ensureOffscreen() {
  try {
    const existing = await chrome.offscreen.hasDocument?.();
    if (existing) return;
  } catch (_) {}
  if (_offscreenStarting) return _offscreenStarting;
  _offscreenStarting = chrome.offscreen.createDocument({
    url: OFFSCREEN_PATH,
    reasons: ['WORKERS'],
    justification: 'background HLS m3u8 polling at 5s interval',
  }).catch((e) => debug('offscreen create:', e?.message))
    .finally(() => { _offscreenStarting = null; });
  return _offscreenStarting;
}

async function closeOffscreenIfIdle() {
  if (getBgCollectorSummary().length > 0) return;
  try { await chrome.offscreen.closeDocument(); } catch (_) {}
}

async function startBg(channelId, channelName) {
  startBgCollector(channelId, channelName);
  await ensureOffscreen();
  // 첫 tick은 startBgCollector가 자체 실행
}

async function stopBg(channelId) {
  stopBgCollector(channelId);
  await closeOffscreenIfIdle();
}

// ── Analytics(=Grafana) 통합 상태 ────────────────────
// 2026-04-29: Superset → Grafana 전환. summary 는 superset/analytics 둘다 노출하여
// popup/options 의 기존 필드를 깨지 않는다.
const _analytics = {
  url: CONFIG.ANALYTICS_URL,
  lastHealth: null,        // 'ok' | 'fail' | null
  lastStatus: 0,           // 마지막 HTTP status code
  lastCheckedAt: 0,        // epoch ms
  lastError: '',
  inFlight: null,
};

function getAnalyticsUrl() { return _analytics.url; }
function setAnalyticsUrl(url) {
  if (!url || _analytics.url === url) return;
  _analytics.url = url;
  _analytics.lastHealth = null;
  _analytics.lastStatus = 0;
  _analytics.lastError = '';
}
function getAnalyticsSummary() {
  return {
    url: _analytics.url,
    dashboardUrl: `${_analytics.url}${CONFIG.ANALYTICS_DASHBOARD_PATH}`,
    exploreUrl: `${_analytics.url}${CONFIG.ANALYTICS_EXPLORE_PATH}`,
    // 구 popup/options 호환용 alias
    sqllabUrl: `${_analytics.url}${CONFIG.ANALYTICS_EXPLORE_PATH}`,
    lastHealth: _analytics.lastHealth,
    lastStatus: _analytics.lastStatus,
    lastCheckedAt: _analytics.lastCheckedAt,
    lastError: _analytics.lastError,
  };
}

async function checkAnalyticsHealth() {
  if (_analytics.inFlight) return _analytics.inFlight;
  const target = `${_analytics.url}${CONFIG.ANALYTICS_HEALTH_PATH}`;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), CONFIG.ANALYTICS_HEALTH_TIMEOUT_MS);
  _analytics.inFlight = (async () => {
    try {
      const resp = await fetch(target, {
        method: 'GET',
        credentials: 'omit',
        cache: 'no-store',
        signal: ctrl.signal,
      });
      _analytics.lastStatus = resp.status;
      _analytics.lastCheckedAt = Date.now();
      // Grafana /api/health: { "database":"ok", "version":"...", ... }
      // Superset 호환: plain "OK" 또는 { STATUS:"OK" }.
      if (resp.ok) {
        const raw = (await resp.text().catch(() => '')).trim();
        const upper = raw.toUpperCase();
        let healthy = upper === 'OK' || raw === '';
        if (!healthy) {
          try {
            const j = JSON.parse(raw);
            const dbOk = String(j?.database ?? '').toLowerCase() === 'ok';
            const statusOk = String(j?.STATUS ?? j?.status ?? '').toUpperCase();
            healthy = dbOk || statusOk === 'OK' || statusOk === 'UP' || statusOk === 'HEALTHY';
          } catch { /* not JSON */ }
        }
        if (healthy) {
          _analytics.lastHealth = 'ok';
          _analytics.lastError = '';
          return getAnalyticsSummary();
        }
        _analytics.lastHealth = 'fail';
        _analytics.lastError = `unexpected body: ${raw.slice(0, 60)}`;
        return getAnalyticsSummary();
      }
      _analytics.lastHealth = 'fail';
      _analytics.lastError = `HTTP ${resp.status}`;
      return getAnalyticsSummary();
    } catch (e) {
      _analytics.lastHealth = 'fail';
      _analytics.lastStatus = 0;
      _analytics.lastCheckedAt = Date.now();
      _analytics.lastError = e?.name === 'AbortError' ? 'timeout' : (e?.message || 'network error');
      return getAnalyticsSummary();
    } finally {
      clearTimeout(t);
      _analytics.inFlight = null;
    }
  })();
  return _analytics.inFlight;
}

// ── 초기 설정 로드 ────────────────────────────────────
async function loadInitialSettings() {
  const dbg = await getStored(STORAGE_KEYS.DEBUG, false);
  setDebugFlag(dbg);
  const url = await getStored(STORAGE_KEYS.SERVER_URL, CONFIG.SERVER_URL);
  if (url) setServerUrl(url);
  // 2026-04-29: analyticsUrl 우선, 없으면 구 supersetUrl 에서 host 만 추출하여 migration.
  let stored = await getStored(STORAGE_KEYS.ANALYTICS_URL, '');
  if (!stored) {
    const legacy = await getStored(STORAGE_KEYS.SUPERSET_URL, '');
    if (legacy) {
      try {
        const u = new URL(legacy);
        stored = `${u.protocol}//${u.host}`;
      } catch { stored = ''; }
    }
  }
  setAnalyticsUrl(stored || deriveAnalyticsUrl(url || CONFIG.SERVER_URL));
}

// chrome.storage 변경 감지 → 즉시 반영 (옵션 페이지 저장 시)
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local') return;
  if (changes[STORAGE_KEYS.ANALYTICS_URL]) {
    const next = changes[STORAGE_KEYS.ANALYTICS_URL].newValue;
    setAnalyticsUrl(next || deriveAnalyticsUrl(getServerUrl()));
  }
  // 구 supersetUrl 변경도 1릴리스 동안은 받아준다.
  if (changes[STORAGE_KEYS.SUPERSET_URL]) {
    const next = changes[STORAGE_KEYS.SUPERSET_URL].newValue;
    if (next) {
      try {
        const u = new URL(next);
        setAnalyticsUrl(`${u.protocol}//${u.host}`);
      } catch { /* ignore */ }
    }
  }
  if (changes[STORAGE_KEYS.SERVER_URL]) {
    const next = changes[STORAGE_KEYS.SERVER_URL].newValue;
    if (next) setServerUrl(next);
    // 사용자가 Analytics URL 을 직접 설정하지 않았다면 서버 URL 변경에 따라 derive
    getStored(STORAGE_KEYS.ANALYTICS_URL, '').then((v) => {
      if (!v) setAnalyticsUrl(deriveAnalyticsUrl(next || CONFIG.SERVER_URL));
    });
  }
});

// ── App channels 폴링 ─────────────────────────────────
const _knownAppChannels = new Map(); // channelId → { channelName, lastSeen }
async function pollAppChannelsTick() {
  const list = await fetchAppChannels();
  const seen = new Set();
  for (const ch of list) {
    if (!ch.channelId) continue;
    seen.add(ch.channelId);
    const known = _knownAppChannels.get(ch.channelId);
    _knownAppChannels.set(ch.channelId, { channelName: ch.channelName || ch.channelId, lastSeen: Date.now() });
    if (!known) {
      debug(`앱 채널 감지: ${ch.channelName} (${ch.channelId})`);
      // 자동 BG 수집 시작
      startBg(ch.channelId, ch.channelName || ch.channelId).catch(() => {});
    }
  }
  // 앱이 더 이상 보고하지 않는 채널은 종료
  for (const [id] of _knownAppChannels) {
    if (!seen.has(id)) {
      _knownAppChannels.delete(id);
      stopBg(id).catch(() => {});
    }
  }
  broadcastStatus();
}

// ── Status broadcast ─────────────────────────────────
function buildStatus() {
  const apps = [];
  for (const [id, info] of _knownAppChannels) {
    const bg = getBgCollectorSummary().find(b => b.channelId === id);
    const fg = getForegroundForChannel(id);
    apps.push({
      channelId: id,
      channelName: info.channelName,
      bgActive: !!bg && bg.bgActive,
      foregroundActive: !!fg,
      metricsSent: bg?.metricsSent || 0,
      lastLatency: bg?.lastLatency || 0,
      lastError: bg?.lastError || '',
      engine: bg ? 'Background HLS' : (fg ? 'HLS.js' : ''),
    });
  }
  return {
    apps,
    bgCount: getBgCollectorSummary().length,
    bgTotalSent: getBgCollectorSummary().reduce((s, b) => s + (b.metricsSent || 0), 0),
    foreground: getForegroundSummary(),
    auth: getAuthDiagnostics(),
    // 2026-04-29: 구 popup/options 호환을 위해 superset alias 동시 노출.
    analytics: getAnalyticsSummary(),
    superset: getAnalyticsSummary(),
    version: CONFIG.VERSION,
    isChzzk: true, isDashboard: true, // overlay에서 자체 구분 가능
  };
}
function broadcastStatus() {
  const status = buildStatus();
  // 모든 chzzk/dashboard 탭에 broadcast
  chrome.tabs.query({}, (tabs) => {
    for (const t of tabs) {
      if (!t.id || !t.url) continue;
      if (!/chzzk\.naver\.com|cv\.dododo\.app/.test(t.url)) continue;
      chrome.tabs.sendMessage(t.id, { target: 'overlay', type: 'status-update', payload: status })
        .catch(() => {});
    }
  });
}

// ── Foreground tick orchestration ─────────────────────
const _fgTabIntervalsActive = new Set();
async function fgTickAll() {
  // 모든 등록 탭에 collect 호출
  const tasks = [];
  for (const tabId of _fgTabIntervalsActive) {
    tasks.push(collectAndSend(tabId).catch(() => {}));
  }
  await Promise.all(tasks);
  if (tasks.length > 0) broadcastStatus();
}

// ── chrome event handlers ────────────────────────────
chrome.runtime.onInstalled.addListener(async () => {
  log(`설치/업데이트: v${CONFIG.VERSION}`);
  await loadInitialSettings();
  await chrome.alarms.create(ALARM_APP_POLL, { periodInMinutes: Math.max(0.5, CONFIG.APP_CHANNEL_POLL_INTERVAL / 60000) });
  await chrome.alarms.create(ALARM_FG_TICK, { periodInMinutes: Math.max(0.5, CONFIG.COLLECT_INTERVAL / 60000) });
});

chrome.runtime.onStartup.addListener(async () => {
  await loadInitialSettings();
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === ALARM_APP_POLL) {
    pollAppChannelsTick().catch((e) => debug('appPoll err', e.message));
  } else if (alarm.name === ALARM_FG_TICK) {
    fgTickAll().catch(() => {});
  }
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local') return;
  if (changes[STORAGE_KEYS.DEBUG]) setDebugFlag(!!changes[STORAGE_KEYS.DEBUG].newValue);
  if (changes[STORAGE_KEYS.SERVER_URL]) {
    const u = changes[STORAGE_KEYS.SERVER_URL].newValue;
    if (u) { setServerUrl(u); resetAuth(); }
  }
  if (changes[STORAGE_KEYS.APP_SECRET]) resetAuth();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  _fgTabIntervalsActive.delete(tabId);
  dropTab(tabId);
});

chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (!tab?.url) return;
  if (/chzzk\.naver\.com\/live\//.test(tab.url)) {
    const m = tab.url.match(/\/live\/([a-f0-9]{10,})/);
    if (m) {
      ensureTab(tabId, m[1]);
      _fgTabIntervalsActive.add(tabId);
    }
  } else {
    _fgTabIntervalsActive.delete(tabId);
    dropTab(tabId);
  }
});

// ── 메시지 라우터 ───────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg) return false;
  // 1) bridge → SW page event
  if (msg.kind === 'page-event' && sender.tab?.id != null) {
    const tabId = sender.tab.id;
    if (msg.channelId) ensureTab(tabId, msg.channelId);
    handlePageEvent(tabId, msg);
    return false;
  }
  if (msg.kind === 'bridge-ready' && sender.tab?.id != null) {
    if (msg.channelId) {
      ensureTab(sender.tab.id, msg.channelId);
      _fgTabIntervalsActive.add(sender.tab.id);
    }
    sendResponse?.({ ok: true });
    return false;
  }
  // 2) overlay → SW request status
  if (msg.kind === 'overlay-request-status' && sender.tab?.id != null) {
    chrome.tabs.sendMessage(sender.tab.id, { target: 'overlay', type: 'status-update', payload: buildStatus() })
      .catch(() => {});
    return false;
  }
  // 3) offscreen → SW: bg tick trigger
  if (msg.kind === 'offscreen-bg-tick') {
    tickAll().then(() => broadcastStatus()).catch(() => {});
    sendResponse?.({ ok: true });
    return true;
  }
  // 4) popup/options 명령
  if (msg.kind === 'popup-get-status') {
    sendResponse(buildStatus());
    return false;
  }
  if (msg.kind === 'popup-test-auth') {
    authenticate().then(t => sendResponse({ ok: !!t, diag: getAuthDiagnostics() }));
    return true;
  }
  if (msg.kind === 'popup-stop-all-bg') {
    stopAllBgCollectors();
    closeOffscreenIfIdle().then(() => sendResponse?.({ ok: true }));
    return true;
  }
  if (msg.kind === 'popup-poll-now') {
    pollAppChannelsTick().then(() => sendResponse?.({ ok: true }));
    return true;
  }
  // 5) Analytics(=Grafana) 헬스 체크. 구 `popup-superset-health` 메시지는 1개 릴리스
  // 동안 alias 로 유지한다.
  if (msg.kind === 'popup-analytics-health' || msg.kind === 'popup-superset-health') {
    checkAnalyticsHealth().then(summary => sendResponse?.({
      ok: summary.lastHealth === 'ok',
      analytics: summary,
      superset: summary, // alias
    }));
    return true;
  }
  if (msg.kind === 'popup-open-analytics' || msg.kind === 'popup-open-superset') {
    // 우선순위:
    //   1) msg.uid: Grafana dashboard UID 직접 지정 (`/d/<uid>`)
    //   2) msg.target ∈ ANALYTICS_DASHBOARDS 키: 매핑 → `/d/<uid>`
    //   3) msg.target === 'sqllab' | 'explore' → /explore
    //   4) msg.target === 'dashboards' → /dashboards (목록)
    //   5) fallback → root /
    let target;
    if (typeof msg.uid === 'string' && /^[A-Za-z0-9_-]+$/.test(msg.uid)) {
      target = `${_analytics.url}/d/${msg.uid}`;
    } else if (msg.target && CONFIG.ANALYTICS_DASHBOARDS?.[msg.target]) {
      target = `${_analytics.url}/d/${CONFIG.ANALYTICS_DASHBOARDS[msg.target].uid}`;
    } else if (msg.target === 'sqllab' || msg.target === 'explore') {
      target = `${_analytics.url}${CONFIG.ANALYTICS_EXPLORE_PATH}`;
    } else if (msg.target === 'dashboards') {
      target = `${_analytics.url}${CONFIG.ANALYTICS_DASHBOARD_PATH}`;
    } else {
      target = `${_analytics.url}/`;
    }
    chrome.tabs.create({ url: target }).then(() => sendResponse?.({ ok: true }))
      .catch((e) => sendResponse?.({ ok: false, error: e?.message }));
    return true;
  }
  return false;
});

// 서비스 워커 wake 시 즉시 설정 로드
loadInitialSettings();
