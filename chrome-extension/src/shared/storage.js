// chrome.storage.local 래퍼 + 로깅 + sampling 헬퍼
import { CONFIG } from './config.js';

const KEYS = {
  APP_SECRET: 'appSecret',
  SERVER_URL: 'serverUrl',
  // 2026-04-29: Analytics dashboard URL (Grafana). 구 supersetUrl 키는 SW 부팅
  // 시 analyticsUrl 로 1회 migration. 다음 릴리스에서 SUPERSET_URL alias 제거 예정.
  ANALYTICS_URL: 'analyticsUrl',
  SUPERSET_URL: 'supersetUrl', // @deprecated, migration 용으로만 read
  DEBUG: 'debug',
  SETUP_DISMISSED: 'setupDismissed',
  SETTINGS_VERSION: 'settingsVersion',
};

export async function getStored(key, def) {
  return new Promise((resolve) => {
    chrome.storage.local.get([key], (items) => resolve(items[key] ?? def));
  });
}

export async function setStored(key, value) {
  return new Promise((resolve) => chrome.storage.local.set({ [key]: value }, resolve));
}

export async function clearStored(keys) {
  return new Promise((resolve) => chrome.storage.local.remove(keys, resolve));
}

export const STORAGE_KEYS = KEYS;

const LOG_PREFIX = '[CView Metrics]';
const STYLE = 'color:#818cf8;font-weight:bold';

export function log(...args) {
  console.log(`%c${LOG_PREFIX}`, STYLE, ...args);
}
let _debugFlag = false;
export function setDebugFlag(v) { _debugFlag = !!v; }
export function debug(...args) {
  if (_debugFlag) console.debug(`%c${LOG_PREFIX}`, 'color:#6b7280', ...args);
}
export function warn(...args) { console.warn(LOG_PREFIX, ...args); }

const _logSampleCounters = new Map();
export function logSampled(key, fn) {
  const c = (_logSampleCounters.get(key) || 0) + 1;
  _logSampleCounters.set(key, c);
  if (c === 1 || c % CONFIG.LOG_SAMPLE_INTERVAL === 0) {
    try { fn(c); } catch (_) {}
  }
}
export function resetLogSample(key) { _logSampleCounters.delete(key); }

export function jitter(maxMs) {
  const m = Math.max(0, Math.min(maxMs | 0, CONFIG.JITTER_MAX_MS));
  return Math.floor(Math.random() * m);
}
