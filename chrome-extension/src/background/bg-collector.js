// CView Chzzk Metrics — background HLS collector (서비스 워커 컨텍스트)
//
// chrome.alarms는 최소 30s라서 5s 폴링에 부적합 → offscreen document에서
// setInterval(5s)로 tick 메시지를 보내고, 본 모듈은 그 메시지에 반응한다.

import { CONFIG } from '../shared/config.js';
import { log, debug, jitter, resetLogSample } from '../shared/storage.js';
import { sendMetrics } from './auth.js';
import {
  fetchStreamUrl, fetchChunklistUrl, fetchChunklistMetrics, invalidateLiveDetail,
} from './chzzk-fetchers.js';

const _bgCollectors = new Map(); // channelId → { state, lastBroadcastRefresh }

export function getBgCollectorState() { return _bgCollectors; }
export function getBgCollectorSummary() {
  const list = [];
  for (const [id, c] of _bgCollectors) {
    list.push({
      channelId: id,
      channelName: c.state.channelName,
      phase: c.state.phase,
      bgActive: c.state.phase === 'collecting',
      metricsSent: c.state.metricsSent,
      lastLatency: c.state.lastLatency,
      lastError: c.state.lastError,
      failCount: c.state.failCount,
    });
  }
  return list;
}

function setPhase(state, next) {
  if (state.phase === next) return;
  state.phase = next;
  state.phaseChangedAt = Date.now();
  debug(`[BG] ${state.channelName}: phase → ${next}`);
}
function recordFailure(state, reason) {
  state.failCount++;
  state.lastError = reason;
  state.lastAttemptAt = Date.now();
  const skipUnits = Math.min(11, state.failCount);
  const waitMs = skipUnits * CONFIG.BG_HLS_POLL_INTERVAL + jitter(CONFIG.JITTER_MAX_MS);
  state.backoffUntil = Date.now() + waitMs;
  setPhase(state, 'degraded');
}

export function startBgCollector(channelId, channelName) {
  if (_bgCollectors.has(channelId)) return;
  const state = {
    channelName, masterUrl: '', chunklistUrl: '',
    broadcastInfo: {}, streamInfo: {},
    metricsSent: 0, lastLatency: 0, lastLatencySource: '',
    busy: false, failCount: 0, lastError: '',
    startedAt: Date.now(), lastAttemptAt: 0, lastSuccessAt: 0,
    backoffUntil: 0, phase: 'idle', phaseChangedAt: Date.now(),
  };
  _bgCollectors.set(channelId, { state, lastBroadcastRefresh: 0 });
  log(`🔄 백그라운드 HLS 수집 시작: ${channelName}`);
  // 즉시 1틱
  initAndTick(channelId).catch(e => log(`[BG] init 오류:`, e.message));
}

export function stopBgCollector(channelId) {
  const bg = _bgCollectors.get(channelId);
  if (!bg) return;
  bg.state.phase = 'stopped';
  log(`⏹ 백그라운드 수집 중단: ${bg.state.channelName} (${bg.state.metricsSent}건)`);
  _bgCollectors.delete(channelId);
}
export function stopAllBgCollectors() {
  for (const [id] of _bgCollectors) stopBgCollector(id);
}

async function initAndTick(channelId) {
  const bg = _bgCollectors.get(channelId);
  if (!bg) return;
  bg.state.lastAttemptAt = Date.now();
  setPhase(bg.state, 'resolving');
  const stream = await fetchStreamUrl(channelId);
  if (!stream) { recordFailure(bg.state, '스트림 URL 없음'); return; }
  bg.state.masterUrl = stream.masterUrl;
  bg.state.streamInfo = stream.streamInfo;
  bg.state.broadcastInfo = stream.broadcastInfo;
  if (stream.broadcastInfo.channelName) bg.state.channelName = stream.broadcastInfo.channelName;
  log(`[BG] ${bg.state.channelName}: 마스터 URL 획득 (${stream.mediaId})`);
  const chunkUrl = await fetchChunklistUrl(stream.masterUrl);
  if (chunkUrl) bg.state.chunklistUrl = chunkUrl;
  await tickAll([channelId]);
}

export async function tickAll(channelIds) {
  const ids = channelIds || [..._bgCollectors.keys()];
  await Promise.all(ids.map(id => bgTick(id)));
}

async function bgTick(chId) {
  const bg = _bgCollectors.get(chId);
  if (!bg) return;
  if (bg.state.busy) return;
  if (Date.now() < bg.state.backoffUntil) return;
  bg.state.busy = true;
  bg.state.lastAttemptAt = Date.now();

  try {
    if (!bg.state.chunklistUrl) {
      setPhase(bg.state, 'resolving');
      const stream = await fetchStreamUrl(chId);
      if (!stream) { recordFailure(bg.state, '스트림 오프라인'); return; }
      bg.state.masterUrl = stream.masterUrl;
      bg.state.streamInfo = stream.streamInfo;
      bg.state.broadcastInfo = stream.broadcastInfo;
      const chunkUrl = await fetchChunklistUrl(stream.masterUrl);
      if (chunkUrl) bg.state.chunklistUrl = chunkUrl;
      else { recordFailure(bg.state, '청크리스트 URL 실패'); return; }
    }

    const m = await fetchChunklistMetrics(bg.state.chunklistUrl);
    if (!m) { bg.state.chunklistUrl = ''; recordFailure(bg.state, '청크리스트 메트릭 실패'); return; }

    bg.state.failCount = 0;
    bg.state.lastError = '';
    bg.state.lastSuccessAt = Date.now();
    bg.state.backoffUntil = 0;
    bg.state.lastLatency = m.latency;
    bg.state.lastLatencySource = m.latencySource;
    setPhase(bg.state, 'collecting');
    resetLogSample(`bg-stream-net-${chId}`);

    const metrics = {
      schemaVersion: CONFIG.SCHEMA_VERSION,
      collectorVersion: CONFIG.VERSION,
      collectorMode: 'background-hls',
      channelId: chId,
      channelName: bg.state.channelName,
      source: 'chrome-extension-bg',
      platform: 'web',
      engine: 'Background HLS',
      latency: m.latency || undefined,
      latencyUnit: 'ms',
      latencySource: m.latencySource || undefined,
      isLowLatency: m.isLowLatency || bg.state.streamInfo.isLowLatency,
      segmentDuration: m.segmentDuration || undefined,
      partDuration: m.partDuration || undefined,
      resolution: bg.state.streamInfo.resolution || undefined,
      bitrate: bg.state.streamInfo.bitrate || undefined,
      fps: bg.state.streamInfo.fps || undefined,
    };
    const bi = bg.state.broadcastInfo;
    if (bi.liveTitle) metrics.liveTitle = bi.liveTitle;
    if (bi.category) metrics.category = bi.category;
    if (bi.viewerCount != null) metrics.viewerCount = bi.viewerCount;
    if (bi.accumulateCount != null) metrics.accumulateCount = bi.accumulateCount;
    if (bi.broadcastDuration != null) metrics.broadcastDuration = bi.broadcastDuration;
    if (bi.adult != null) metrics.adult = bi.adult;
    if (bi.status) metrics.status = bi.status;

    const r = await sendMetrics(metrics);
    if (r.ok) {
      bg.state.metricsSent++;
      debug(`[BG] ${bg.state.channelName}: 전송 #${bg.state.metricsSent}`);
    } else {
      recordFailure(bg.state, '메트릭 전송 실패');
    }
  } catch (e) {
    log(`[BG] ${chId} bgTick 오류:`, e.message);
    recordFailure(bg.state, e.message);
  } finally {
    bg.state.busy = false;
  }

  // 자동 중단 조건
  if (bg.state.failCount >= CONFIG.BG_MAX_CONSECUTIVE_FAILS) {
    log(`[BG] ${bg.state.channelName}: 연속 실패 → 자동 중단`);
    stopBgCollector(chId); return;
  }
  const noSuccessRef = bg.state.lastSuccessAt || bg.state.startedAt;
  if (Date.now() - noSuccessRef > CONFIG.BG_MAX_NO_SUCCESS_MS) {
    log(`[BG] ${bg.state.channelName}: 무성공 → 자동 중단`);
    stopBgCollector(chId);
  }

  // BG_BROADCAST_INTERVAL마다 broadcast info 갱신
  if (Date.now() - bg.lastBroadcastRefresh > CONFIG.BG_BROADCAST_INTERVAL) {
    bg.lastBroadcastRefresh = Date.now();
    invalidateLiveDetail(chId);
    fetchStreamUrl(chId, false).then(stream => {
      if (!stream) { stopBgCollector(chId); return; }
      bg.state.broadcastInfo = stream.broadcastInfo;
      bg.state.streamInfo = stream.streamInfo;
      if (stream.broadcastInfo.channelName) bg.state.channelName = stream.broadcastInfo.channelName;
      if (stream.masterUrl !== bg.state.masterUrl) {
        bg.state.masterUrl = stream.masterUrl;
        bg.state.chunklistUrl = '';
      }
    }).catch(() => {});
  }
}
