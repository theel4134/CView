// CView Chzzk Metrics — auth module (service worker)
import { CONFIG, AUTH_BACKOFF_STEPS_MS } from '../shared/config.js';
import { getStored, STORAGE_KEYS, log, debug } from '../shared/storage.js';

const state = {
  jwt: null,
  expiry: 0,
  failCount: 0,
  backoffUntil: 0,
  inFlight: null,
  serverUrl: CONFIG.SERVER_URL,
  lastError: '',
};

export function setServerUrl(url) {
  if (!url) return;
  if (state.serverUrl !== url) {
    state.serverUrl = url;
    state.jwt = null; state.expiry = 0;
    state.failCount = 0; state.backoffUntil = 0;
  }
}
export function getServerUrl() { return state.serverUrl; }
export function getAuthDiagnostics() {
  return {
    hasToken: !!state.jwt,
    expiry: state.expiry,
    failCount: state.failCount,
    backoffUntil: state.backoffUntil,
    serverUrl: state.serverUrl,
    lastError: state.lastError,
  };
}
export function resetAuth() {
  state.jwt = null; state.expiry = 0;
  state.failCount = 0; state.backoffUntil = 0;
  state.lastError = '';
}

export async function authenticate() {
  const nowSec = Date.now() / 1000;
  if (state.jwt && state.expiry > nowSec + 300) return state.jwt;
  if (state.backoffUntil > Date.now()) {
    debug(`auth backoff ${Math.ceil((state.backoffUntil - Date.now()) / 1000)}s 잔여`);
    return null;
  }
  if (state.inFlight) return state.inFlight;

  const appSecret = await getStored(STORAGE_KEYS.APP_SECRET, '');
  if (!appSecret) { state.lastError = 'App Secret 미설정'; return null; }

  const recordFailure = (reason) => {
    state.failCount++;
    const idx = Math.min(state.failCount - 1, AUTH_BACKOFF_STEPS_MS.length - 1);
    const waitMs = AUTH_BACKOFF_STEPS_MS[idx];
    state.backoffUntil = Date.now() + waitMs;
    state.lastError = `${reason} (backoff ${Math.round(waitMs / 1000)}s)`;
  };

  state.inFlight = (async () => {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 15000);
      const resp = await fetch(`${state.serverUrl}${CONFIG.API_AUTH}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ device_id: CONFIG.DEVICE_ID, app_secret: appSecret }),
        signal: ctrl.signal,
      }).finally(() => clearTimeout(t));
      const body = await resp.json().catch(() => ({}));
      if (resp.status === 200 && body.token) {
        state.jwt = body.token;
        state.expiry = nowSec + (body.expires_in || 86400);
        state.failCount = 0;
        state.backoffUntil = 0;
        state.lastError = '';
        log('인증 성공');
        return state.jwt;
      }
      recordFailure(`인증 실패: ${body.error || resp.status}`);
      return null;
    } catch (e) {
      recordFailure(`인증 ${e.name === 'AbortError' ? '타임아웃' : '네트워크 오류'}: ${e.message || ''}`);
      return null;
    }
  })().finally(() => { state.inFlight = null; });

  return state.inFlight;
}

/** 서버에 메트릭 전송. 401이면 토큰 리셋 후 false 반환. */
export async function sendMetrics(metrics) {
  const token = await authenticate();
  if (!token) return { ok: false, reason: 'no-token' };
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 10000);
    const resp = await fetch(`${state.serverUrl}${CONFIG.API_METRICS}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
      body: JSON.stringify(metrics),
      signal: ctrl.signal,
    }).finally(() => clearTimeout(t));
    if (resp.status === 200) return { ok: true };
    if (resp.status === 401) { state.jwt = null; state.expiry = 0; }
    state.lastError = `전송 실패: ${resp.status}`;
    return { ok: false, status: resp.status };
  } catch (e) {
    state.lastError = `네트워크: ${e.message || e.name}`;
    return { ok: false, reason: e.name };
  }
}

/**
 * /api/web-position 전송 (무인증).
 * 서버 sync.py가 currentPdtMs/hasPdt로 chzzk-pdt 기반 latency를 재계산.
 * 문서 §7 웹 수집기 요구사항.
 */
export async function sendWebPosition(payload) {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 5000);
    const resp = await fetch(`${state.serverUrl}${CONFIG.API_WEB_POSITION}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
      keepalive: true,
    }).finally(() => clearTimeout(t));
    if (resp.status === 200) return { ok: true };
    return { ok: false, status: resp.status };
  } catch (e) {
    return { ok: false, reason: e.name };
  }
}

/** 앱 채널 조회 (무인증) */
export async function fetchAppChannels() {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 15000);
    const resp = await fetch(`${state.serverUrl}${CONFIG.API_APP_CHANNELS}`, {
      headers: { 'Accept': 'application/json' }, signal: ctrl.signal,
    }).finally(() => clearTimeout(t));
    const body = await resp.json().catch(() => ({}));
    if (body.success && Array.isArray(body.data)) return body.data;
  } catch (_) {}
  return [];
}
