// CView Metrics — options
// 2026-04-29: Superset → Grafana(Analytics) 전환. HTML id 는 호환을 위해 superset-* 유지,
// storage key 와 사용자 표시 문구는 analytics 로 일반화.
import { CONFIG, normalizeServerUrl, normalizeAnalyticsUrl, deriveAnalyticsUrl } from '../shared/config.js';

const $ = (id) => document.getElementById(id);
const KEY_SECRET = 'appSecret';
const KEY_URL = 'serverUrl';
const KEY_ANALYTICS = 'analyticsUrl';
const KEY_LEGACY_SUPERSET = 'supersetUrl'; // @deprecated, migration 대상
const KEY_DEBUG = 'debug';

function setStatus(msg, isErr) {
  const s = $('status');
  s.textContent = msg;
  s.style.color = isErr ? '#f87171' : '#34d399';
  if (msg) setTimeout(() => { if (s.textContent === msg) s.textContent = ''; }, 3000);
}

function setAnalyticsStatus(msg, isErr) {
  const s = $('superset-status');
  if (!s) return;
  s.textContent = msg;
  s.style.color = isErr ? '#f87171' : '#34d399';
  if (msg) setTimeout(() => { if (s.textContent === msg) s.textContent = ''; }, 4000);
}

async function load() {
  $('ver').textContent = CONFIG.VERSION;
  const items = await chrome.storage.local.get([
    KEY_SECRET, KEY_URL, KEY_ANALYTICS, KEY_LEGACY_SUPERSET, KEY_DEBUG,
  ]);
  $('app-secret').value = items[KEY_SECRET] || '';
  $('server-url').value = items[KEY_URL] || CONFIG.SERVER_URL;

  // 기존 supersetUrl 만 있는 경우 host 만 유지하여 analyticsUrl 로 1회 migration.
  let initialAnalytics = items[KEY_ANALYTICS] || '';
  if (!initialAnalytics && items[KEY_LEGACY_SUPERSET]) {
    try {
      const u = new URL(items[KEY_LEGACY_SUPERSET]);
      initialAnalytics = `${u.protocol}//${u.host}`;
    } catch { /* ignore */ }
  }
  $('superset-url').value = initialAnalytics;
  $('superset-url').placeholder = `자동 도출 (${deriveAnalyticsUrl(items[KEY_URL] || CONFIG.SERVER_URL)})`;
  $('debug').checked = !!items[KEY_DEBUG];
}

$('btn-save').addEventListener('click', async () => {
  const secret = $('app-secret').value.trim();
  const urlInput = $('server-url').value.trim();
  const url = urlInput ? normalizeServerUrl(urlInput) : CONFIG.SERVER_URL;
  if (urlInput && !url) { setStatus('잘못된 Server URL (호스트 허용목록/HTTPS 확인)', true); return; }
  const analyticsInput = $('superset-url').value.trim();
  let analyticsUrl = '';
  if (analyticsInput) {
    const norm = normalizeAnalyticsUrl(analyticsInput);
    if (!norm) { setStatus('잘못된 Analytics URL (호스트 허용목록/HTTPS 확인)', true); return; }
    analyticsUrl = norm;
  }
  await chrome.storage.local.set({
    [KEY_SECRET]: secret,
    [KEY_URL]: url,
    [KEY_ANALYTICS]: analyticsUrl,
    [KEY_DEBUG]: $('debug').checked,
  });
  // 구 supersetUrl 이 있으면 함께 정리.
  await chrome.storage.local.remove(KEY_LEGACY_SUPERSET);
  setStatus('저장됨');
  $('superset-url').placeholder = `자동 도출 (${deriveAnalyticsUrl(url)})`;
});

$('btn-test').addEventListener('click', async () => {
  setStatus('테스트 중…');
  const r = await new Promise(res => chrome.runtime.sendMessage({ kind: 'popup-test-auth' }, res));
  if (r?.ok) setStatus('인증 성공');
  else setStatus(`실패: ${r?.diag?.lastError || '알 수 없음'}`, true);
});

$('btn-superset-health').addEventListener('click', async () => {
  setAnalyticsStatus('체크 중…');
  const r = await new Promise(res => chrome.runtime.sendMessage({ kind: 'popup-analytics-health' }, res));
  const s = r?.analytics || r?.superset;
  if (r?.ok && s) {
    setAnalyticsStatus(`OK (${s.url})`);
  } else {
    setAnalyticsStatus(`실패: ${s?.lastError || s?.lastStatus || '알 수 없음'}`, true);
  }
});

$('btn-superset-open').addEventListener('click', () => {
  chrome.runtime.sendMessage({ kind: 'popup-open-analytics', target: 'dashboards' });
});
$('btn-superset-sqllab').addEventListener('click', () => {
  chrome.runtime.sendMessage({ kind: 'popup-open-analytics', target: 'explore' });
});

$('btn-reset').addEventListener('click', async () => {
  if (!confirm('모든 설정을 초기화할까요? (App Secret, Server URL, Analytics URL, Debug)')) return;
  await chrome.storage.local.clear();
  await load();
  setStatus('초기화됨');
});

$('btn-diag').addEventListener('click', async () => {
  const status = await new Promise(res => chrome.runtime.sendMessage({ kind: 'popup-get-status' }, res));
  $('diag').textContent = JSON.stringify(status, null, 2);
});

load();
