'use strict';

const { contextBridge, ipcRenderer } = require('electron');
const jsQR = require('jsqr');

function decodeQrSync(rgbaData, width, height) {
  try {
    const arr = rgbaData instanceof Uint8ClampedArray ? rgbaData : new Uint8ClampedArray(rgbaData);
    const code = jsQR(arr, width, height, { inversionAttempts: 'attemptBoth' });
    return code && code.data ? code.data : null;
  } catch {
    return null;
  }
}

function subscribe(channel, callback) {
  if (typeof callback !== 'function') return () => {};
  const listener = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld('loopSearch', {
  platform: process.platform,

  // Settings & AI key
  getSettings: () => ipcRenderer.invoke('settings:get'),
  updateSettings: (patch) => ipcRenderer.invoke('settings:update', patch),
  getHotkeyPresets: () => ipcRenderer.invoke('settings:presets'),
  setGeminiApiKey: (apiKey) => ipcRenderer.invoke('settings:set-gemini-key', apiKey),
  onSettingsChanged: (cb) => subscribe('settings:changed', cb),

  // Firebase Google Auth
  getAuthState: () => ipcRenderer.invoke('auth:get'),
  signInWithGoogle: () => ipcRenderer.invoke('auth:sign-in'),
  signOut: () => ipcRenderer.invoke('auth:sign-out'),
  onAuthChanged: (cb) => subscribe('auth:changed', cb),

  // History
  getHistory: () => ipcRenderer.invoke('history:get'),
  addHistoryItem: (item) => ipcRenderer.invoke('history:add', item),
  clearHistory: () => ipcRenderer.invoke('history:clear'),

  // Window & App flow
  openWindow: (name) => ipcRenderer.invoke('window:open', name),
  closeWindow: () => ipcRenderer.invoke('window:close'),
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  startOverlay: (options) => ipcRenderer.invoke('overlay:start', options || {}),
  closeOverlay: () => ipcRenderer.invoke('overlay:close'),
  onOverlayInit: (cb) => subscribe('overlay:init', cb),
  onPinnedInit: (cb) => subscribe('pinned:init', cb),
  onToastInit: (cb) => subscribe('toast:init', cb),
  showToast: (message, kind) => ipcRenderer.invoke('toast:show', { message, kind }),

  // Vision, Lens, OCR, Gemini AI
  decodeQr: (rgbaData, width, height) => decodeQrSync(rgbaData, width, height),
  uploadToGoogleLens: (jpegBase64) => ipcRenderer.invoke('lens:upload', jpegBase64),
  runOcr: (pngBase64) => ipcRenderer.invoke('vision:ocr', pngBase64),
  callGemini: (payload) => ipcRenderer.invoke('ai:gemini', payload),
  getLensThemeScript: (enableDark) => ipcRenderer.invoke('lens:dark-script', enableDark),
  recordSearchSuccess: () => ipcRenderer.invoke('telemetry:search-success'),

  // Pinned & Clipboard & Save
  pinCapture: (payload) => ipcRenderer.invoke('pinned:create', payload),
  clearAllPinned: () => ipcRenderer.invoke('pinned:clear-all'),
  copyText: (text) => ipcRenderer.invoke('clipboard:write-text', text),
  copyImageDataUrl: (dataUrl) => ipcRenderer.invoke('clipboard:write-image', dataUrl),
  saveCapturePng: (pngBase64) => ipcRenderer.invoke('capture:save-png', pngBase64),

  // External & Updates & Feedback
  openExternal: (url) => ipcRenderer.invoke('app:open-external', url),
  checkForUpdates: () => ipcRenderer.invoke('app:check-updates'),
  getUpdateState: () => ipcRenderer.invoke('app:get-update-state'),
  onUpdateAvailable: (cb) => subscribe('app:update-available', cb),
  openFeedbackIssue: (payload) => ipcRenderer.invoke('app:open-feedback', payload),
  getAppInfo: () => ipcRenderer.invoke('app:info')
});
