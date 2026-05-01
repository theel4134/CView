// 공통 m3u8 parser — UserScript의 parseM3u8Metrics와 동일.
// page-hooks (MAIN world)는 ES module을 못 쓰므로 동일 함수가 인라인 복사되어 있음.
// 변경 시 src/content/page-hooks.js 의 parseM3u8Metrics와 동기화 필요.

import { CONFIG } from './config.js';

/**
 * @param {string} content m3u8 본문
 * @param {{ now?: number, fetchTimeMs?: number }} [opts]
 * @returns {{
 *   isMaster: boolean, isChunklist: boolean, isLowLatency: boolean,
 *   segmentDuration: number, partDuration: number,
 *   programDateTimeEdgeMs: number, latencyMs: number, latencySource: string,
 *   streamInfo: { bitrate?: number, resolution?: string, fps?: number },
 * }}
 */
export function parseM3u8Metrics(content, opts) {
  const now = (opts && typeof opts.now === 'number') ? opts.now : Date.now();
  const fetchTime = (opts && typeof opts.fetchTimeMs === 'number') ? opts.fetchTimeMs : 0;
  const result = {
    isMaster: false,
    isChunklist: false,
    isLowLatency: false,
    segmentDuration: 0,
    partDuration: 0,
    programDateTimeEdgeMs: 0,
    latencyMs: 0,
    latencySource: '',
    streamInfo: {},
  };
  if (!content || typeof content !== 'string') return result;

  if (content.includes('#EXT-X-STREAM-INF')) {
    result.isMaster = true;
    const bw = content.match(/BANDWIDTH=(\d+)/);
    if (bw) result.streamInfo.bitrate = parseInt(bw[1], 10);
    const res = content.match(/RESOLUTION=(\d+x\d+)/);
    if (res) result.streamInfo.resolution = res[1];
    const fps = content.match(/FRAME-RATE=([\d.]+)/);
    if (fps) result.streamInfo.fps = parseFloat(fps[1]);
    return result;
  }

  if (!content.includes('#EXTINF')) return result;
  result.isChunklist = true;

  if (content.includes('#EXT-X-PART:') || content.includes('#EXT-X-SERVER-CONTROL:')) {
    result.isLowLatency = true;
  }

  const td = content.match(/#EXT-X-TARGETDURATION:(\d+)/);
  if (td) result.segmentDuration = parseInt(td[1], 10);
  const pt = content.match(/PART-TARGET=([\d.]+)/);
  if (pt) result.partDuration = parseFloat(pt[1]);

  const inRange = (ms) =>
    ms >= CONFIG.MIN_VALID_LATENCY_MS && ms <= CONFIG.MAX_VALID_LATENCY_MS;

  // 1순위: 13자리 timestamp 파일명
  const tsPattern = /_(\d{13})_/g;
  let tsMatch, latestTs = 0;
  while ((tsMatch = tsPattern.exec(content)) !== null) {
    const ts = parseInt(tsMatch[1], 10);
    if (ts > latestTs) latestTs = ts;
  }
  if (latestTs > 0) {
    const latMs = now - latestTs;
    if (inRange(latMs)) {
      result.latencyMs = Math.round(latMs);
      result.latencySource = 'hls-segment-timestamp';
    }
  }

  // 2순위: PROGRAM-DATE-TIME (LL-HLS는 part 누적)
  const pdtMatches = [...content.matchAll(/#EXT-X-PROGRAM-DATE-TIME:(.+)/g)];
  if (pdtMatches.length > 0) {
    const lastPDTStr = pdtMatches[pdtMatches.length - 1][1].trim();
    const pdtMs = new Date(lastPDTStr).getTime();
    if (!isNaN(pdtMs) && pdtMs > 0) {
      const afterLast = content.slice(content.lastIndexOf('#EXT-X-PROGRAM-DATE-TIME'));
      const extinfMatch = afterLast.match(/#EXTINF:([\d.]+)/);
      const segDurMs = extinfMatch ? parseFloat(extinfMatch[1]) * 1000 : 0;
      let edgeMs = pdtMs + segDurMs;
      let pdtSource = 'program-date-time-segment';

      if (result.isLowLatency) {
        const partRe = /#EXT-X-PART:[^\n]*?DURATION=([\d.]+)/g;
        let partMatch, partsAccumMs = 0;
        while ((partMatch = partRe.exec(afterLast)) !== null) {
          const d = parseFloat(partMatch[1]);
          if (!isNaN(d) && d > 0) partsAccumMs += d * 1000;
        }
        if (partsAccumMs > 0) {
          edgeMs = pdtMs + partsAccumMs;
          pdtSource = 'program-date-time-part';
        }
      }

      result.programDateTimeEdgeMs = edgeMs;

      if (!result.latencyMs) {
        const latMs = now - edgeMs;
        if (inRange(latMs)) {
          result.latencyMs = Math.round(latMs);
          result.latencySource = pdtSource;
        }
      }
    }
  }

  // 3순위: target duration estimate
  if (!result.latencyMs && result.segmentDuration > 0) {
    let estMs;
    let estSource;
    if (result.isLowLatency && result.partDuration > 0) {
      estMs = Math.round(result.segmentDuration * 1000 + fetchTime);
      estSource = 'llhls-estimate';
    } else {
      estMs = Math.round(result.segmentDuration * 2 * 1000 + fetchTime);
      estSource = 'hls-estimate';
    }
    if (estMs <= CONFIG.MAX_VALID_LATENCY_MS) {
      result.latencyMs = estMs;
      result.latencySource = estSource;
    }
  }

  return result;
}
