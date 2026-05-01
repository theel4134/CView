// CView Chzzk Metrics — status overlay (ISOLATED, document_idle)
// SW의 broadcast 'status-update'를 받아 화면 우하단 미니 패널을 갱신.

(() => {
  'use strict';

  const STATUS_UI_ID = 'cview-metrics-status';
  let _lastHtml = '';
  let _hidden = false;

  function escapeHtml(s) {
    if (typeof s !== 'string') return '';
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function engineTheme(engine) {
    const s = String(engine || '').trim().toLowerCase();
    let label = 'unknown';
    if (s.startsWith('vlc')) return { icon: '🟠', color: '#fb923c', bg: 'rgba(251,146,60,0.15)', label: 'VLC' };
    if (s.startsWith('av')) return { icon: '🔵', color: '#60a5fa', bg: 'rgba(96,165,250,0.15)', label: 'AVPlayer' };
    if (s.includes('hls')) return { icon: '🟢', color: '#34d399', bg: 'rgba(52,211,153,0.15)', label: 'HLS.js' };
    if (s.includes('background')) return { icon: '🟣', color: '#a78bfa', bg: 'rgba(167,139,250,0.15)', label: 'BG-HLS' };
    return { icon: '⚪', color: '#9ca3af', bg: 'rgba(156,163,175,0.15)', label: engine || '?' };
  }

  function engineBadge(engine) {
    const t = engineTheme(engine);
    return `<span style="display:inline-block;padding:1px 6px;border-radius:8px;font-size:10px;font-weight:600;color:${t.color};background:${t.bg};border:1px solid ${t.color}40;margin-left:4px;vertical-align:middle">${t.icon} ${escapeHtml(t.label)}</span>`;
  }

  function ensureEl() {
    let el = document.getElementById(STATUS_UI_ID);
    if (!el) {
      el = document.createElement('div');
      el.id = STATUS_UI_ID;
      Object.assign(el.style, {
        position: 'fixed', bottom: '12px', right: '12px', zIndex: '999999',
        background: 'rgba(0,0,0,0.85)', color: '#e5e7eb',
        padding: '8px 12px', borderRadius: '8px',
        fontSize: '11px', fontFamily: 'monospace', lineHeight: '1.6',
        pointerEvents: 'none', border: '1px solid rgba(255,255,255,0.1)',
        opacity: '0.9', maxWidth: '320px',
      });
      document.body && document.body.appendChild(el);
    }
    return el;
  }

  function render(state) {
    const el = ensureEl();
    if (!el) return;
    let html = '';
    const apps = state.apps || [];
    if (apps.length > 0) {
      html += `<div style="color:#60a5fa;margin-bottom:3px">📱 앱 재생 (${apps.length})</div>`;
      for (const a of apps) {
        const dot = a.isCurrent && a.foregroundActive ? '🟢' : a.bgActive ? '🔵' : '⚪';
        html += `${dot} ${escapeHtml(a.channelName || a.channelId)}`;
        if (a.engine) html += engineBadge(a.engine);
        if (a.bgActive) {
          const lat = a.lastLatency > 0 ? ` ${(a.lastLatency / 1000).toFixed(1)}s` : '';
          html += ` <span style="color:#34d399">BG:${a.metricsSent || 0}건${lat}</span>`;
          if (a.lastError) html += ` <span style="color:#f87171">${escapeHtml(a.lastError)}</span>`;
        }
        html += '<br>';
      }
    }
    if (state.isDashboard && state.bgCount > 0) {
      html += `<div style="color:#34d399;margin-top:3px">🔄 백그라운드 HLS (${state.bgCount}채널) | ${state.bgTotalSent}건</div>`;
    }
    if (state.isChzzk && state.foregroundChannelId) {
      const dot = state.foregroundActive ? '🟢' : '⚪';
      const ch = escapeHtml(state.foregroundChannelName || state.foregroundChannelId);
      const lat = state.foregroundLatencyMs > 0 ? ` ${(state.foregroundLatencyMs / 1000).toFixed(1)}s` : '';
      html += `${dot} 웹 수집 <b>${ch}</b> | ${state.foregroundSent || 0}건${lat}`;
    }
    if (state.lastError) html += `<br><span style="color:#f87171">${escapeHtml(state.lastError)}</span>`;
    if (!html) html = `⚪ CView Metrics 대기 중`;

    if (html !== _lastHtml) {
      el.innerHTML = html;
      _lastHtml = html;
    }
    el.style.display = _hidden ? 'none' : '';
  }

  chrome.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.target !== 'overlay') return;
    if (msg.type === 'status-update') render(msg.payload || {});
    if (msg.type === 'overlay-hide') { _hidden = true; ensureEl().style.display = 'none'; }
    if (msg.type === 'overlay-show') { _hidden = false; }
  });

  // 첫 로드 시 SW에 현재 상태 요청
  chrome.runtime.sendMessage({ kind: 'overlay-request-status' }).catch(() => {});
})();
