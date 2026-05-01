// Chzzk live-detail / m3u8 fetchers (서비스 워커에서 host_permissions 기반으로 직접 호출)
import { CONFIG } from '../shared/config.js';
import { parseM3u8Metrics } from '../shared/m3u8-parser.js';
import { logSampled, debug, log } from '../shared/storage.js';

const _liveDetailCache = new Map(); // channelId → { ts, data }

export function getCachedLiveDetail(channelId) {
  const e = _liveDetailCache.get(channelId);
  if (!e) return null;
  if (Date.now() - e.ts > CONFIG.LIVE_DETAIL_TTL_MS) {
    _liveDetailCache.delete(channelId);
    return null;
  }
  return e.data;
}
export function setCachedLiveDetail(channelId, data) {
  if (!data) return;
  _liveDetailCache.set(channelId, { ts: Date.now(), data });
}
export function invalidateLiveDetail(channelId) {
  if (channelId) _liveDetailCache.delete(channelId);
  else _liveDetailCache.clear();
}

async function fetchTextWithTimeout(url, timeoutMs, headers) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const resp = await fetch(url, { headers: headers || {}, signal: ctrl.signal });
    return { status: resp.status, text: await resp.text() };
  } finally {
    clearTimeout(t);
  }
}

export async function fetchStreamUrl(channelId, useCache = true) {
  if (useCache) {
    const cached = getCachedLiveDetail(channelId);
    if (cached) return cached;
  }
  try {
    const { status, text } = await fetchTextWithTimeout(
      `https://api.chzzk.naver.com/service/v3/channels/${channelId}/live-detail`,
      15000, { 'Accept': 'application/json' });
    if (status !== 200) return null;
    const json = JSON.parse(text);
    const content = json?.content;
    if (!content || content.status !== 'OPEN') return null;
    const playback = JSON.parse(content.livePlaybackJson || '{}');
    const mediaList = playback.media || [];

    let masterUrl = '', mediaId = '';
    let streamInfo = { bitrate: 0, fps: 0, resolution: '', isLowLatency: false };
    for (const m of mediaList) {
      if (m.mediaId === 'LLHLS' || (!masterUrl && m.mediaId === 'HLS')) {
        masterUrl = m.path || ''; mediaId = m.mediaId || '';
        const tracks = m.encodingTrack || [];
        if (tracks.length > 0) {
          const best = tracks.reduce((a, b) => (b.videoBitrate || 0) > (a.videoBitrate || 0) ? b : a, tracks[0]);
          streamInfo.bitrate = best.videoBitrate || best.audioBitrate || 0;
          streamInfo.fps = best.videoFrameRate || 0;
          if (best.videoWidth && best.videoHeight) streamInfo.resolution = `${best.videoWidth}x${best.videoHeight}`;
        }
        if (m.mediaId === 'LLHLS') { streamInfo.isLowLatency = true; break; }
      }
    }
    if (!masterUrl) return null;

    const broadcastInfo = {
      liveTitle: content.liveTitle || '',
      status: content.status || 'UNKNOWN',
      category: content.liveCategoryValue || content.liveCategory?.liveCategoryValue || '',
      viewerCount: content.concurrentUserCount || 0,
      accumulateCount: content.accumulateCount || 0,
      adult: content.adult || false,
      channelName: content.channel?.channelName || '',
      openDate: content.openDate || '',
    };
    if (broadcastInfo.openDate) {
      const t = new Date(broadcastInfo.openDate).getTime();
      if (!isNaN(t)) broadcastInfo.broadcastDuration = Math.floor((Date.now() - t) / 1000);
    }
    const data = { masterUrl, mediaId, streamInfo, broadcastInfo };
    if (useCache) setCachedLiveDetail(channelId, data);
    return data;
  } catch (e) {
    logSampled(`bg-stream-net-${channelId}`, (n) =>
      log(`[BG] 스트림 API 오류: ${channelId} (반복 ${n}회) ${e.message}`));
    return null;
  }
}

export async function fetchChunklistUrl(masterUrl) {
  try {
    const { status, text } = await fetchTextWithTimeout(masterUrl, 15000, { 'Accept': '*/*' });
    if (status !== 200) { log(`[BG] 마스터 m3u8 HTTP ${status}`); return null; }
    if (!text.includes('#EXTM3U')) { log('[BG] 마스터 m3u8 invalid'); return null; }
    if (!text.includes('#EXT-X-STREAM-INF')) { debug('[BG] 마스터=청크리스트'); return masterUrl; }
    const streams = [];
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/#EXT-X-STREAM-INF:.*BANDWIDTH=(\d+)/);
      if (m && lines[i + 1]) streams.push({ bw: parseInt(m[1], 10), url: lines[i + 1].trim() });
    }
    if (streams.length === 0) return null;
    streams.sort((a, b) => b.bw - a.bw);
    let chunkUrl = streams[0].url;
    if (!chunkUrl.startsWith('http')) {
      try { chunkUrl = new URL(chunkUrl, masterUrl).href; }
      catch { chunkUrl = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1) + chunkUrl; }
    }
    return chunkUrl;
  } catch (e) { log('[BG] 마스터 m3u8 오류:', e.message); return null; }
}

export async function fetchChunklistMetrics(chunklistUrl) {
  const fetchStart = Date.now();
  try {
    const { status, text } = await fetchTextWithTimeout(chunklistUrl, 10000, { 'Accept': '*/*' });
    const fetchTime = Date.now() - fetchStart;
    if (status !== 200) { log(`[BG] 청크리스트 HTTP ${status}`); return null; }
    const parsed = parseM3u8Metrics(text, { fetchTimeMs: fetchTime });
    if (!parsed.isChunklist) return null;
    return {
      latency: parsed.latencyMs,
      latencySource: parsed.latencySource,
      isLowLatency: parsed.isLowLatency,
      segmentDuration: parsed.segmentDuration,
      partDuration: parsed.partDuration,
      fetchTime,
    };
  } catch (e) {
    logSampled('bg-chunklist-net', (n) => log(`[BG] 청크리스트 오류 (반복 ${n}회): ${e.message}`));
    return null;
  }
}
