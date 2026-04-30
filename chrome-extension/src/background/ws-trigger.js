// CView Chzzk Metrics — WebSocket trigger
//
// 책임:
//   • `wss://<server>/ws` 에 연결하여 서버 broadcast 를 수신.
//   • `app-channel-active` 이벤트 도착 시 `pollAppChannelsTick()` 을 즉시 호출하여
//     앱 채널 폴링(기본 chrome.alarms 30s 주기)을 기다리지 않고 BG 수집을 트리거한다.
//   • 자동 재연결 (지수 백오프 1s → 30s).
//
// MV3 SW 수명: 활성 WS 가 있으면 Chrome 116+ 에서 SW 가 idle terminate 되지
// 않는다. 서버는 30s heartbeat 프레임을 보내므로 항상 트래픽이 있다.
//
// chrome.alarms 폴링은 fallback 으로 유지되므로, WS 가 끊겨도 최대 30s 안에
// /api/app-channels 폴링이 신규 채널을 잡는다.

import { debug, log } from '../shared/storage.js';

const RECONNECT_MIN_MS = 1000;
const RECONNECT_MAX_MS = 30000;

const state = {
  ws: null,
  url: '',
  reconnectMs: RECONNECT_MIN_MS,
  reconnectTimer: null,
  closingByUs: false,
  onAppChannelActive: null,
  getServerUrl: null,
  startedAt: 0,
  msgCount: 0,
  lastEventAt: 0,
  lastError: '',
};

function deriveWsUrl(serverUrl) {
  if (!serverUrl) return '';
  let u;
  try { u = new URL(serverUrl); } catch { return ''; }
  const proto = u.protocol === 'http:' ? 'ws:' : 'wss:';
  return `${proto}//${u.host}/ws`;
}

function clearReconnect() {
  if (state.reconnectTimer != null) {
    clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
  }
}

function scheduleReconnect() {
  clearReconnect();
  const delay = state.reconnectMs;
  state.reconnectMs = Math.min(state.reconnectMs * 2, RECONNECT_MAX_MS);
  debug(`[ws-trigger] reconnect in ${delay}ms`);
  state.reconnectTimer = setTimeout(() => connect(), delay);
}

function connect() {
  clearReconnect();
  if (!state.getServerUrl) return;
  const serverUrl = state.getServerUrl();
  const url = deriveWsUrl(serverUrl);
  if (!url) {
    state.lastError = 'invalid server url';
    return;
  }

  // 이미 같은 URL 로 OPEN/CONNECTING 이면 재사용
  if (state.ws && state.url === url) {
    const rs = state.ws.readyState;
    if (rs === WebSocket.OPEN || rs === WebSocket.CONNECTING) return;
  }

  // 기존 ws 정리
  if (state.ws) {
    try { state.closingByUs = true; state.ws.close(); } catch (_) {}
    state.ws = null;
  }

  state.url = url;
  let ws;
  try { ws = new WebSocket(url); } catch (e) {
    state.lastError = e?.message || String(e);
    scheduleReconnect();
    return;
  }
  state.ws = ws;
  state.closingByUs = false;
  state.startedAt = Date.now();

  ws.addEventListener('open', () => {
    log(`[ws-trigger] connected: ${url}`);
    state.reconnectMs = RECONNECT_MIN_MS;
    state.lastError = '';
    // 서버 websocket_handler 는 클라이언트 메시지로 채널 구독 필터를 받는다.
    // 우리는 글로벌 broadcast 만 필요하므로 구독을 보내지 않는다.
  });

  ws.addEventListener('message', (ev) => {
    state.msgCount += 1;
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (!msg || typeof msg !== 'object') return;
    if (msg.type === 'app-channel-active') {
      state.lastEventAt = Date.now();
      const ch = msg.data?.channelName || msg.data?.channelId || '?';
      debug(`[ws-trigger] app-channel-active → poll: ${ch}`);
      try { state.onAppChannelActive?.(msg.data); } catch (e) {
        debug(`[ws-trigger] handler err: ${e?.message}`);
      }
    }
  });

  ws.addEventListener('error', (ev) => {
    state.lastError = 'ws error';
    debug('[ws-trigger] error', ev?.message || '');
  });

  ws.addEventListener('close', (ev) => {
    debug(`[ws-trigger] closed code=${ev?.code}`);
    state.ws = null;
    if (!state.closingByUs) scheduleReconnect();
  });
}

export function startWsTrigger({ getServerUrl, onAppChannelActive }) {
  state.getServerUrl = getServerUrl;
  state.onAppChannelActive = onAppChannelActive;
  state.reconnectMs = RECONNECT_MIN_MS;
  connect();
}

export function reconnectWsTrigger() {
  state.reconnectMs = RECONNECT_MIN_MS;
  if (state.ws) {
    try { state.closingByUs = true; state.ws.close(); } catch (_) {}
    state.ws = null;
  }
  connect();
}

export function getWsTriggerSummary() {
  const rs = state.ws?.readyState;
  return {
    connected: rs === WebSocket.OPEN,
    readyState: rs ?? null,
    url: state.url,
    startedAt: state.startedAt,
    msgCount: state.msgCount,
    lastEventAt: state.lastEventAt,
    lastError: state.lastError,
  };
}
