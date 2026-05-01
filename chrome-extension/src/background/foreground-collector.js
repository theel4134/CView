// CView Chzzk Metrics — foreground collector (탭별 web 수집)
// bridge로부터 page-event를 받아 가장 최근 chunklist/stream 정보를 유지하고,
// COLLECT_INTERVAL마다 page-hooks에 sample-request를 보내 video/HLS 메트릭을
// 받아와 합쳐서 sendMetrics()로 전송한다.

import { CONFIG } from '../shared/config.js';
import { sendMetrics, sendWebPosition } from './auth.js';
import { fetchStreamUrl } from './chzzk-fetchers.js';
import { log, debug } from '../shared/storage.js';

const _tabs = new Map(); // tabId → { channelId, channelName, lastChunklist, streamInfo, broadcastInfo, sent, lastLatency, lastError, intervalId }

export function getForegroundSummary() {
  const out = [];
  for (const [tabId, t] of _tabs) {
    out.push({
      tabId,
      channelId: t.channelId,
      channelName: t.channelName,
      sent: t.sent,
      lastLatency: t.lastLatency,
      lastError: t.lastError,
      webPosSent: t.webPosSent || 0,
      webPosLastErr: t.webPosLastErr || '',
      webPosLastTs: t.webPosLastTs || 0,
    });
  }
  return out;
}
export function getForegroundForChannel(channelId) {
  for (const [, t] of _tabs) if (t.channelId === channelId) return t;
  return null;
}

export function ensureTab(tabId, channelId) {
  let t = _tabs.get(tabId);
  if (!t) {
    t = {
      channelId, channelName: '', lastChunklist: null,
      streamInfo: {}, broadcastInfo: {},
      sent: 0, lastLatency: 0, lastError: '',
      webPosSent: 0, webPosLastErr: '', webPosLastTs: 0,
    };
    _tabs.set(tabId, t);
    // 초기 stream info 비동기 조회
    if (channelId) {
      fetchStreamUrl(channelId).then((s) => {
        if (!s) return;
        t.streamInfo = s.streamInfo || {};
        t.broadcastInfo = s.broadcastInfo || {};
        if (s.broadcastInfo?.channelName) t.channelName = s.broadcastInfo.channelName;
      }).catch(() => {});
    }
  } else if (channelId && t.channelId !== channelId) {
    t.channelId = channelId;
    t.lastChunklist = null;
    t.streamInfo = {}; t.broadcastInfo = {};
  }
  return t;
}

export function dropTab(tabId) { _tabs.delete(tabId); }

/** page-event 처리 — bridge에서 SW로 전달된 메시지 */
export function handlePageEvent(tabId, msg) {
  const t = _tabs.get(tabId);
  if (!t) return;
  switch (msg.type) {
    case 'master-m3u8':
      Object.assign(t.streamInfo, msg.payload || {});
      break;
    case 'chunklist':
      t.lastChunklist = { ...msg.payload };
      break;
    case 'navigation': {
      const m = msg.payload?.pathname?.match(/\/live\/([a-f0-9]{10,})/);
      if (m) ensureTab(tabId, m[1]);
      break;
    }
    case 'web-position-sample':
      forwardWebPosition(t, msg.payload).catch(() => {});
      break;
    case 'hls-instance':
    case 'ready':
      // 별도 처리 없음
      break;
  }
}

/**
 * page-hooks에서 push된 web-position payload를
 * 서버 /api/web-position으로 전송. (문서 §7 계약)
 */
async function forwardWebPosition(t, sample) {
  if (!t || !t.channelId || !sample) return;
  // 잘못된 latency는 0으로 다운드레이드 — 서버가 PDT 기반으로 재계산
  const lat = (typeof sample.latency === 'number' && sample.latency > 0) ? sample.latency : 0;
  const payload = {
    channelId: t.channelId,
    channelName: t.channelName || 'unknown',
    currentTime: sample.currentTime || 0,
    duration: sample.duration || 0,
    bufferedEnd: sample.bufferedEnd || 0,
    bufferLength: sample.bufferLength || 0,
    latency: lat,
    currentPdtMs: sample.currentPdtMs || 0,
    hasPdt: !!sample.hasPdt,
    paused: !!sample.paused,
    timestamp: sample.timestamp || Date.now(),
  };
  const r = await sendWebPosition(payload);
  if (r.ok) {
    t.webPosSent++;
    t.webPosLastErr = '';
    t.webPosLastTs = Date.now();
  } else {
    t.webPosLastErr = `${r.reason || r.status || 'fail'}`;
  }
}

/** 주기 collect: bridge를 통해 page-hooks에서 video sample 받아 합치고 전송 */
export async function collectAndSend(tabId) {
  const t = _tabs.get(tabId);
  if (!t || !t.channelId) return;

  let sample = null;
  try {
    const resp = await chrome.tabs.sendMessage(tabId, {
      target: 'page', type: 'sample-request',
    });
    sample = resp?.sample || null;
  } catch (_) {
    return; // 탭이 닫혔거나 bridge 없음
  }

  if (!sample) return;

  // chunklist 기반 latency가 우선, 없으면 hls.js latency
  let latency = t.lastChunklist?.latencyMs || sample.hlsJsLatencyMs || 0;
  let latencySource = t.lastChunklist?.latencySource || (sample.hlsJsLatencyMs ? 'hls-js-latency' : '');
  if (latency < CONFIG.MIN_VALID_LATENCY_MS || latency > CONFIG.MAX_VALID_LATENCY_MS) {
    latency = 0; latencySource = '';
  }

  const metrics = {
    schemaVersion: CONFIG.SCHEMA_VERSION,
    collectorVersion: CONFIG.VERSION,
    collectorMode: 'foreground-video',
    channelId: t.channelId,
    channelName: t.channelName || (sample.streamInfo?.channelName) || undefined,
    source: 'chrome-extension-fg',
    platform: 'web',
    engine: 'HLS.js',
    latency: latency || undefined,
    latencyUnit: 'ms',
    latencySource: latencySource || undefined,
    isLowLatency: t.lastChunklist?.isLowLatency || sample.streamInfo?.isLowLatency || false,
    segmentDuration: t.lastChunklist?.segmentDuration || undefined,
    partDuration: t.lastChunklist?.partDuration || undefined,
    currentTime: sample.currentTime,
    duration: sample.duration,
    paused: sample.paused,
    readyState: sample.readyState,
    networkState: sample.networkState,
    bufferHealth: sample.bufferHealth,
    droppedFrames: sample.droppedFrames,
    playbackRate: sample.playbackRate,
    bitrate: sample.bitrate || t.streamInfo.bitrate || undefined,
    fps: sample.fps || t.streamInfo.fps || undefined,
    resolution: sample.resolution || t.streamInfo.resolution || undefined,
    bandwidth: sample.bandwidth,
    targetLatency: sample.targetLatency,
  };
  const bi = t.broadcastInfo;
  if (bi.liveTitle) metrics.liveTitle = bi.liveTitle;
  if (bi.category) metrics.category = bi.category;
  if (bi.viewerCount != null) metrics.viewerCount = bi.viewerCount;
  if (bi.broadcastDuration != null) metrics.broadcastDuration = bi.broadcastDuration;
  if (bi.status) metrics.status = bi.status;

  const r = await sendMetrics(metrics);
  if (r.ok) {
    t.sent++;
    t.lastLatency = latency;
    t.lastError = '';
    debug(`[FG] ${t.channelName || t.channelId}: 전송 #${t.sent}`);
  } else {
    t.lastError = `${r.reason || r.status || 'fail'}`;
  }
}
