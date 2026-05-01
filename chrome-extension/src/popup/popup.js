// CView Metrics — popup
import { CONFIG } from '../shared/config.js';

const $ = (id) => document.getElementById(id);

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function send(kind, extra) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage({ kind, ...(extra || {}) }, resolve);
  });
}

// Grafana dashboard quick-link 버튼들을 CONFIG.ANALYTICS_DASHBOARDS 로부터 렌더.
// 한 줄 변경으로 dashboard UID 추가/삭제 가능.
function renderAnalyticsQuicklinks() {
  const host = $('analytics-quicklinks');
  if (!host) return;
  const entries = Object.entries(CONFIG.ANALYTICS_DASHBOARDS || {});
  host.innerHTML = entries.map(([key, info]) => {
    const label = `${info.icon || ''} ${info.title || key}`.trim();
    return `<button class="analytics-quicklink" data-target="${escapeHtml(key)}" title="Grafana /d/${escapeHtml(info.uid)}">${escapeHtml(label)}</button>`;
  }).join('');
  host.querySelectorAll('button.analytics-quicklink').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const t = btn.getAttribute('data-target');
      await send('popup-open-analytics', { target: t });
      window.close();
    });
  });
}
renderAnalyticsQuicklinks();

async function refresh() {
  const status = await send('popup-get-status');
  if (!status) return;
  $('ver').textContent = `v${status.version || ''}`;

  // 인증
  const a = status.auth || {};
  const authLine = a.hasToken
    ? `<span style="color:#34d399">✓ 인증됨</span> (만료: ${new Date(a.expiry * 1000).toLocaleTimeString()})`
    : a.lastError ? `<span style="color:#f87171">${escapeHtml(a.lastError)}</span><div style="color:#94a3b8;font-size:10px;margin-top:2px">CView 앱 → 설정 → 메트릭 → App Secret 에서 키 확인</div>`
                  : `<span style="color:#fbbf24">미인증 — App Secret 설정 필요</span><div style="color:#94a3b8;font-size:10px;margin-top:2px">CView 앱 → 설정 → 메트릭 → App Secret 에서 확인</div>`;
  $('auth-line').innerHTML = authLine;

  // 앱/BG 채널
  const apps = status.apps || [];
  if (apps.length === 0) {
    $('bg-summary').innerHTML = `<span class="dot-idle">앱 채널 없음 (${status.bgCount || 0} BG 활성)</span>`;
  } else {
    $('bg-summary').innerHTML = apps.map(c => {
      const dot = c.bgActive ? '<span class="dot-bg">🔵</span>' : '<span class="dot-idle">⚪</span>';
      const lat = c.lastLatency ? ` ${(c.lastLatency / 1000).toFixed(1)}s` : '';
      const err = c.lastError ? `<div class="err">${escapeHtml(c.lastError)}</div>` : '';
      return `<div class="channel">${dot} <b>${escapeHtml(c.channelName || c.channelId)}</b> · ${c.metricsSent}건${lat}${err}</div>`;
    }).join('');
  }

  // FG
  const fg = status.foreground || [];
  if (fg.length === 0) $('fg-list').textContent = '없음';
  else $('fg-list').innerHTML = fg.map(f =>
    `<div class="channel"><span class="dot-active">🟢</span> ${escapeHtml(f.channelName || f.channelId)} · ${f.sent}건${f.lastLatency ? ' ' + (f.lastLatency / 1000).toFixed(1) + 's' : ''}</div>`
  ).join('');

  // Analytics (Grafana). 2026-04-29: 구 필드명 superset 은 service-worker 에서
  // analytics 와 동일 summary 로 alias 되므로 하위 호환됨.
  const sx = status.analytics || status.superset || {};
  const dot = sx.lastHealth === 'ok'
    ? '<span class="dot-active">🟢</span>'
    : sx.lastHealth === 'fail'
      ? '<span class="dot-idle" style="color:#f87171">🔴</span>'
      : '<span class="dot-idle">⚪</span>';
  const stamp = sx.lastCheckedAt
    ? ` · ${new Date(sx.lastCheckedAt).toLocaleTimeString()}`
    : '';
  const detail = sx.lastHealth === 'ok'
    ? 'OK'
    : sx.lastHealth === 'fail'
      ? `<span style="color:#f87171">${escapeHtml(sx.lastError || ('HTTP ' + sx.lastStatus))}</span>`
      : '미확인';
  const host = (() => { try { return new URL(sx.url || '').host; } catch { return sx.url || ''; } })();
  $('superset-line').innerHTML = `${dot} <b>${escapeHtml(host)}</b> · ${detail}${stamp}`;
}

$('open-options').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('open-options-link').addEventListener('click', (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); });
$('btn-test-auth').addEventListener('click', async () => {
  $('btn-test-auth').disabled = true;
  const r = await send('popup-test-auth');
  alert(r?.ok ? '인증 성공' : `인증 실패: ${r?.diag?.lastError || '알 수 없음'}`);
  $('btn-test-auth').disabled = false;
  refresh();
});
$('btn-poll-now').addEventListener('click', async () => { await send('popup-poll-now'); refresh(); });
$('btn-stop-all').addEventListener('click', async () => {
  if (!confirm('모든 백그라운드 수집을 중지할까요?')) return;
  await send('popup-stop-all-bg'); refresh();
});

$('btn-superset-dash').addEventListener('click', async () => {
  await send('popup-open-analytics', { target: 'dashboards' });
  window.close();
});
$('btn-superset-sql').addEventListener('click', async () => {
  await send('popup-open-analytics', { target: 'explore' });
  window.close();
});
$('btn-superset-health').addEventListener('click', async () => {
  $('btn-superset-health').disabled = true;
  await send('popup-analytics-health');
  $('btn-superset-health').disabled = false;
  refresh();
});

refresh();
setInterval(refresh, 2000);
