// CView Chzzk Metrics — bridge content script (ISOLATED world)
//
// 역할:
//   • page-hooks(MAIN world)이 보낸 window.postMessage를 chrome.runtime.sendMessage로 SW에 전달
//   • SW가 보낸 chrome.runtime.onMessage(샘플 요청, 설정 업데이트)를 page-hooks에 postMessage로 전달
//   • 채널 ID 추출 등 DOM 접근이 필요한 작업

(() => {
  'use strict';

  const PAGE_TAG = 'cview-page-hook';
  const BRIDGE_TAG = 'cview-bridge';

  function extractChannelId() {
    const m = location.pathname.match(/\/live\/([a-f0-9]{10,})/);
    return m ? m[1] : null;
  }

  // page → bridge → SW
  window.addEventListener('message', (ev) => {
    if (ev.source !== window) return;
    const d = ev.data;
    if (!d || d.__cview !== PAGE_TAG) return;
    chrome.runtime.sendMessage({
      kind: 'page-event',
      type: d.type,
      payload: d.payload,
      channelId: extractChannelId(),
      url: location.href,
    }).catch(() => { /* SW가 닫혀있을 수 있음 */ });
  });

  // SW → bridge → page
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.target !== 'page') return false;
    if (msg.type === 'sample-request') {
      const reqId = Math.random().toString(36).slice(2);
      const handler = (ev) => {
        if (ev.source !== window) return;
        const d = ev.data;
        if (!d || d.__cview !== PAGE_TAG || d.type !== 'sample-response') return;
        if (d.payload?.reqId !== reqId) return;
        window.removeEventListener('message', handler);
        sendResponse({ sample: d.payload.sample });
      };
      window.addEventListener('message', handler);
      window.postMessage({ __cview: BRIDGE_TAG, type: 'sample-request', reqId }, '*');
      // 1초 timeout
      setTimeout(() => {
        try { window.removeEventListener('message', handler); } catch {}
        try { sendResponse({ sample: null, timeout: true }); } catch {}
      }, 1000);
      return true; // async sendResponse
    }
    if (msg.type === 'config-update') {
      window.postMessage({ __cview: BRIDGE_TAG, type: 'config-update', payload: msg.payload }, '*');
      return false;
    }
    return false;
  });

  // 초기 핸드셰이크
  chrome.runtime.sendMessage({
    kind: 'bridge-ready',
    channelId: extractChannelId(),
    url: location.href,
  }).catch(() => {});
})();
