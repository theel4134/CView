// CView Chzzk Metrics — page-hooks (MAIN world, document_start)
//
// 페이지 컨텍스트에서 직접 실행되어 HLS.js / fetch / XHR을 후킹.
// chrome.* API 접근 불가 — 데이터는 window.postMessage로 ISOLATED bridge에
// 전달하고, bridge가 다시 chrome.runtime.sendMessage로 SW에 중계한다.
//
// 본 파일은 ES module이 아닌 일반 스크립트로 로드된다 (manifest world: MAIN).
//
// parseM3u8Metrics는 src/shared/m3u8-parser.js와 동일 — 두 곳 모두 변경 필요.

(() => {
  'use strict';

  const TAG = 'cview-page-hook';
  const LOG_PREFIX = '[CView Metrics/page]';
  const log = (...a) => console.log(`%c${LOG_PREFIX}`, 'color:#818cf8;font-weight:bold', ...a);

  // 외부에서 주입된 설정 — 일단 default. bridge가 'config-update'로 갱신.
  const RUNTIME = {
    MIN_VALID_LATENCY_MS: 100,
    MAX_VALID_LATENCY_MS: 30000,
    DEBUG: false,
    WEB_POSITION_INTERVAL_VISIBLE_MS: 1000,
    WEB_POSITION_INTERVAL_HIDDEN_MS: 5000,
    WEB_POSITION_BURST_COUNT: 3,
    WEB_POSITION_BURST_GAP_MS: 250,
  };

  function post(type, payload) {
    try {
      window.postMessage({ __cview: TAG, type, payload }, '*');
    } catch (_) {}
  }

  // ── shared parseM3u8Metrics (인라인 복사) ─────────────────
  function parseM3u8Metrics(content, opts) {
    const now = (opts && typeof opts.now === 'number') ? opts.now : Date.now();
    const fetchTime = (opts && typeof opts.fetchTimeMs === 'number') ? opts.fetchTimeMs : 0;
    const result = {
      isMaster: false, isChunklist: false, isLowLatency: false,
      segmentDuration: 0, partDuration: 0, programDateTimeEdgeMs: 0,
      latencyMs: 0, latencySource: '', streamInfo: {},
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
      ms >= RUNTIME.MIN_VALID_LATENCY_MS && ms <= RUNTIME.MAX_VALID_LATENCY_MS;

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
          let pm, partsAccumMs = 0;
          while ((pm = partRe.exec(afterLast)) !== null) {
            const d = parseFloat(pm[1]);
            if (!isNaN(d) && d > 0) partsAccumMs += d * 1000;
          }
          if (partsAccumMs > 0) { edgeMs = pdtMs + partsAccumMs; pdtSource = 'program-date-time-part'; }
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

    if (!result.latencyMs && result.segmentDuration > 0) {
      let estMs, estSource;
      if (result.isLowLatency && result.partDuration > 0) {
        estMs = Math.round(result.segmentDuration * 1000 + fetchTime);
        estSource = 'llhls-estimate';
      } else {
        estMs = Math.round(result.segmentDuration * 2 * 1000 + fetchTime);
        estSource = 'hls-estimate';
      }
      if (estMs <= RUNTIME.MAX_VALID_LATENCY_MS) {
        result.latencyMs = estMs;
        result.latencySource = estSource;
      }
    }

    return result;
  }

  // ── 상태 ────────────────────────────────────────────────
  let _hlsInstance = null;
  let _lastChunklistContent = '';
  let _lastChunklistTime = 0;
  let _lastProgramDateTime = 0;
  let _lastPDTCaptureTime = 0;
  let _hlsStreamInfo = { isLowLatency: false, bitrate: 0, fps: 0 };

  // ── HLS.js 인스턴스 캡처 ───────────────────────────────
  (function hookHls() {
    let _origHls;
    let _hooked = false;
    try {
      Object.defineProperty(window, 'Hls', {
        configurable: true,
        enumerable: true,
        get() { return _origHls; },
        set(NewHls) {
          if (_hooked || !NewHls || typeof NewHls !== 'function') {
            _origHls = NewHls;
            return;
          }
          _hooked = true;
          const ProxiedHls = new Proxy(NewHls, {
            construct(target, args) {
              const instance = Reflect.construct(target, args);
              log('HLS.js 인스턴스 캡처됨');
              _hlsInstance = instance;
              post('hls-instance', { captured: true });
              return instance;
            },
          });
          for (const key of Object.getOwnPropertyNames(NewHls)) {
            if (key === 'prototype' || key === 'length' || key === 'name') continue;
            try { Object.defineProperty(ProxiedHls, key, Object.getOwnPropertyDescriptor(NewHls, key)); } catch {}
          }
          ProxiedHls.prototype = NewHls.prototype;
          _origHls = ProxiedHls;
        },
      });
    } catch (e) {
      console.warn(LOG_PREFIX, 'Hls 후킹 실패:', e.message);
    }
  })();

  // ── fetch / XHR 인터셉트 ──────────────────────────────
  (function hookNetwork() {
    try {
      const origFetch = window.fetch;
      if (typeof origFetch === 'function') {
        window.fetch = function (input, init) {
          const url = typeof input === 'string' ? input : (input?.url || '');
          const promise = origFetch.apply(this, arguments);
          if (url.includes('.m3u8')) {
            promise.then(resp => {
              resp.clone().text().then(text => processM3u8Response(url, text)).catch(() => {});
            }).catch(() => {});
          }
          return promise;
        };
      }
      const XHR = window.XMLHttpRequest;
      if (XHR && XHR.prototype) {
        const origOpen = XHR.prototype.open;
        const origSend = XHR.prototype.send;
        XHR.prototype.open = function (method, url) {
          this._cview_url = url;
          return origOpen.apply(this, arguments);
        };
        XHR.prototype.send = function () {
          if (this._cview_url && this._cview_url.includes('.m3u8')) {
            this.addEventListener('load', function () {
              if (this.responseType === '' || this.responseType === 'text') {
                processM3u8Response(this._cview_url, this.responseText);
              }
            });
          }
          return origSend.apply(this, arguments);
        };
      }
    } catch (e) {
      console.warn(LOG_PREFIX, 'fetch/XHR 인터셉트 실패:', e.message);
    }
  })();

  function processM3u8Response(url, content) {
    if (!content) return;
    const parsed = parseM3u8Metrics(content);
    if (parsed.isMaster) {
      if (parsed.streamInfo.bitrate) _hlsStreamInfo.bitrate = parsed.streamInfo.bitrate;
      if (parsed.streamInfo.resolution) _hlsStreamInfo.resolution = parsed.streamInfo.resolution;
      if (parsed.streamInfo.fps) _hlsStreamInfo.fps = parsed.streamInfo.fps;
      post('master-m3u8', _hlsStreamInfo);
      return;
    }
    if (!parsed.isChunklist) return;
    _lastChunklistContent = content;
    _lastChunklistTime = Date.now();
    if (parsed.isLowLatency) _hlsStreamInfo.isLowLatency = true;
    if (parsed.programDateTimeEdgeMs > 0) {
      _lastProgramDateTime = parsed.programDateTimeEdgeMs;
      _lastPDTCaptureTime = Date.now();
    }
    post('chunklist', {
      capturedAt: _lastChunklistTime,
      latencyMs: parsed.latencyMs,
      latencySource: parsed.latencySource,
      isLowLatency: parsed.isLowLatency,
      segmentDuration: parsed.segmentDuration,
      partDuration: parsed.partDuration,
      programDateTimeEdgeMs: parsed.programDateTimeEdgeMs,
    });
  }

  // ── SPA navigation 감시 ───────────────────────────────
  (function watchNav() {
    let lastPath = location.pathname;
    const check = () => {
      if (location.pathname !== lastPath) {
        lastPath = location.pathname;
        post('navigation', { pathname: lastPath });
      }
    };
    window.addEventListener('popstate', check);
    const origPush = history.pushState;
    const origReplace = history.replaceState;
    history.pushState = function () { origPush.apply(this, arguments); check(); };
    history.replaceState = function () { origReplace.apply(this, arguments); check(); };
  })();

  // ── 비디오/HLS 메트릭 sampler — bridge가 요청 시 응답 ────
  function sampleVideoMetrics() {
    const video = document.querySelector('video');
    if (!video) return null;
    const m = {
      currentTime: typeof video.currentTime === 'number' ? +video.currentTime.toFixed(3) : undefined,
      duration: Number.isFinite(video.duration) ? +video.duration.toFixed(3) : undefined,
      paused: !!video.paused,
      readyState: video.readyState,
      networkState: video.networkState,
      playbackRate: video.playbackRate || 1.0,
    };
    try {
      if (video.buffered && video.buffered.length > 0) {
        m.bufferHealth = Math.max(0, +(video.buffered.end(video.buffered.length - 1) - video.currentTime).toFixed(2));
      }
    } catch (_) {}
    const q = video.getVideoPlaybackQuality?.();
    if (q) m.droppedFrames = q.droppedVideoFrames || 0;
    if (video.videoWidth && video.videoHeight) m.resolution = `${video.videoWidth}x${video.videoHeight}`;

    const hls = _hlsInstance;
    if (hls) {
      if (typeof hls.latency === 'number' && hls.latency > 0) {
        const ms = Math.round(hls.latency * 1000);
        if (ms >= RUNTIME.MIN_VALID_LATENCY_MS && ms <= RUNTIME.MAX_VALID_LATENCY_MS) {
          m.hlsJsLatencyMs = ms;
        }
      }
      if (hls.bandwidthEstimate > 0) m.bandwidth = Math.round(hls.bandwidthEstimate);
      const lvl = hls.levels?.[hls.currentLevel];
      if (lvl) {
        if (lvl.bitrate) m.bitrate = lvl.bitrate;
        if (lvl.width && lvl.height) m.resolution = `${lvl.width}x${lvl.height}`;
        const fpsStr = lvl.attrs?.['FRAME-RATE'];
        if (fpsStr) m.fps = parseFloat(fpsStr);
      }
      if (typeof hls.targetLatency === 'number') m.targetLatency = Math.round(hls.targetLatency * 1000);
      // hls.playingDate: 현재 재생 위치의 절대 시각 (Date) — webPDT 1순위 (문서 §4.1)
      if (hls.playingDate instanceof Date) {
        const t = hls.playingDate.getTime();
        if (Number.isFinite(t) && t > 0) m.hlsPlayingDateMs = t;
      }
    }
    m.streamInfo = { ..._hlsStreamInfo };
    m.lastChunklistAgeMs = _lastChunklistTime ? Date.now() - _lastChunklistTime : -1;
    m.lastProgramDateTime = _lastProgramDateTime || 0;
    m.lastPDTCaptureAgeMs = _lastPDTCaptureTime ? Date.now() - _lastPDTCaptureTime : -1;
    return m;
  }

  // bridge → page 메시지 수신 (요청-응답)
  window.addEventListener('message', (ev) => {
    if (ev.source !== window) return;
    const data = ev.data;
    if (!data || data.__cview !== 'cview-bridge') return;
    if (data.type === 'sample-request') {
      const sample = sampleVideoMetrics();
      post('sample-response', { reqId: data.reqId, sample });
    } else if (data.type === 'config-update') {
      Object.assign(RUNTIME, data.payload || {});
    }
  });

  // ── web-position push loop (문서 §4.3 / §7) ──
  // page-driven 1이유: SW chrome.alarms는 최소 주기 30s라 밀집도 수집 불가.
  // visibility hidden이면 5s, visible 복귀 직후 burst 3회.
  function buildWebPositionPayload(sample) {
    if (!sample) return null;
    const video = document.querySelector('video');
    if (!video) return null;

    let bufferedEnd = 0;
    try {
      if (video.buffered && video.buffered.length > 0) {
        bufferedEnd = +video.buffered.end(video.buffered.length - 1).toFixed(3);
      }
    } catch (_) {}

    // currentPdtMs 우선순위: hls.playingDate > chunklist edge - bufferHealth
    let currentPdtMs = 0;
    let hasPdt = false;
    if (sample.hlsPlayingDateMs && sample.hlsPlayingDateMs > 0) {
      currentPdtMs = sample.hlsPlayingDateMs;
      hasPdt = true;
    } else if (_lastProgramDateTime > 0 && Number.isFinite(sample.bufferHealth)) {
      // edge는 live edge의 PDT, 현재 재생 위치는 edge - bufferHealth
      currentPdtMs = Math.round(_lastProgramDateTime - (sample.bufferHealth * 1000));
      hasPdt = currentPdtMs > 0;
    }

    // latency: 초 단위 (서버가 seconds 입력 기대)
    let latencySec = 0;
    if (sample.hlsJsLatencyMs && sample.hlsJsLatencyMs > 0) {
      latencySec = +(sample.hlsJsLatencyMs / 1000).toFixed(3);
    } else if (hasPdt && currentPdtMs > 0) {
      const est = (Date.now() - currentPdtMs) / 1000;
      if (est > 0 && est < 60) latencySec = +est.toFixed(3);
    }

    return {
      currentTime: sample.currentTime,
      duration: sample.duration,
      bufferedEnd,
      bufferLength: sample.bufferHealth,
      latency: latencySec,
      currentPdtMs,
      hasPdt,
      paused: sample.paused,
      timestamp: Date.now(),
      // 디버그용
      playbackRate: sample.playbackRate,
      visibilityState: document.visibilityState,
    };
  }

  let _pushTimer = null;
  let _lastEmitMs = 0;
  function pushOnce() {
    const sample = sampleVideoMetrics();
    const payload = buildWebPositionPayload(sample);
    if (!payload) return;
    _lastEmitMs = Date.now();
    post('web-position-sample', payload);
  }
  function scheduleNext() {
    clearTimeout(_pushTimer);
    const interval = document.visibilityState === 'visible'
      ? RUNTIME.WEB_POSITION_INTERVAL_VISIBLE_MS
      : RUNTIME.WEB_POSITION_INTERVAL_HIDDEN_MS;
    _pushTimer = setTimeout(() => { pushOnce(); scheduleNext(); }, interval);
  }
  function startPushLoop() {
    if (_pushTimer) return;
    pushOnce();
    scheduleNext();
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      // burst: 즉시 + N-1회
      const n = Math.max(1, RUNTIME.WEB_POSITION_BURST_COUNT | 0);
      for (let i = 0; i < n; i++) {
        setTimeout(pushOnce, i * RUNTIME.WEB_POSITION_BURST_GAP_MS);
      }
    }
    clearTimeout(_pushTimer);
    scheduleNext();
  });
  // 비디오 메타데이터 준비됨 때 시작
  function tryStart() {
    const v = document.querySelector('video');
    if (v) { startPushLoop(); return; }
    setTimeout(tryStart, 1000);
  }
  tryStart();

  // 초기 ready 통지
  post('ready', { url: location.href });
  log('page-hooks 로드 완료');
})();
