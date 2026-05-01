// CView Chzzk Metrics — offscreen document
// chrome.alarms 최소 30s 제약을 우회하기 위해 5초 setInterval로 SW를 깨우는 역할.

import { CONFIG } from '../shared/config.js';

setInterval(() => {
  chrome.runtime.sendMessage({ kind: 'offscreen-bg-tick' }).catch(() => {});
}, CONFIG.BG_HLS_POLL_INTERVAL);

console.log('[CView Offscreen] 5s tick 시작');
