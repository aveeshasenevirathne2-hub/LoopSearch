'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const APP_VERSION = '1.0.3';
const MAX_HISTORY_ITEMS = 12;

const DEFAULT_SETTINGS = {
  hotkey: 'Ctrl+Shift+Space',
  defaultMode: 'box', // box | freehand | tap | text
  searchEngine: 'googleLens', // googleLens | perplexity | bing | aiExplain
  theme: 'dark', // dark | light | system
  visualStylePreset: 'crystal', // crystal | aurora | minimal | stealth
  glowTheme: 'apple', // apple | arctic | violet | ember
  glowIntensity: 'balanced', // subtle | balanced | vivid
  motionFeel: 'crisp', // crisp | lush
  openInBrowserFallback: false,
  launchAtLogin: false,
  autoCopyOcrText: false,
  showTrayHintBadge: true,
  onboardingCompleted: false,
  searchCount: 0,
  feedbackPromptDismissed: false,
  lastFeedbackPromptCount: 0
};

const HOTKEY_PRESETS = [
  { id: 'Ctrl+Shift+Space', label: 'Ctrl + Shift + Space' },
  { id: 'Alt+Shift+S', label: 'Alt + Shift + S' },
  { id: 'Ctrl+Alt+L', label: 'Ctrl + Alt + L' },
  { id: 'Ctrl+Shift+S', label: 'Ctrl + Shift + S' }
];

const SPECIAL_KEY_MAP = {
  ' ': 'Space',
  spacebar: 'Space',
  space: 'Space',
  escape: 'Escape',
  esc: 'Escape',
  enter: 'Return',
  return: 'Return',
  tab: 'Tab',
  backspace: 'Backspace',
  delete: 'Delete',
  insert: 'Insert',
  home: 'Home',
  end: 'End',
  pageup: 'PageUp',
  pagedown: 'PageDown',
  arrowup: 'Up',
  arrowdown: 'Down',
  arrowleft: 'Left',
  arrowright: 'Right',
  up: 'Up',
  down: 'Down',
  left: 'Left',
  right: 'Right'
};

function normalizeHotkeyString(raw) {
  if (!raw || typeof raw !== 'string') return DEFAULT_SETTINGS.hotkey;
  const parts = raw
    .split('+')
    .map((p) => p.trim())
    .filter(Boolean);

  const modifiers = new Set();
  let mainKey = null;

  for (const part of parts) {
    const low = part.toLowerCase();
    if (low === 'ctrl' || low === 'control' || low === 'cmdorctrl' || low === 'commandorcontrol') {
      modifiers.add('Ctrl');
    } else if (low === 'cmd' || low === 'command' || low === 'meta' || low === 'super' || low === 'win') {
      modifiers.add(process.platform === 'darwin' ? 'Cmd' : 'Super');
    } else if (low === 'alt' || low === 'option') {
      modifiers.add('Alt');
    } else if (low === 'shift') {
      modifiers.add('Shift');
    } else if (/^f([1-9]|1[0-2])$/i.test(part)) {
      mainKey = part.toUpperCase();
    } else {
      const mapped = SPECIAL_KEY_MAP[low] || (part.length === 1 ? part.toUpperCase() : part);
      mainKey = mapped;
    }
  }

  if (!mainKey || modifiers.size === 0) return DEFAULT_SETTINGS.hotkey;

  const orderedMods = ['Ctrl', 'Alt', 'Shift', 'Cmd', 'Super'].filter((m) => modifiers.has(m));
  return [...orderedMods, mainKey].join('+');
}

function toElectronAccelerator(normalizedHotkey, platform = process.platform) {
  const norm = normalizeHotkeyString(normalizedHotkey);
  return norm
    .split('+')
    .map((part) => {
      if (part === 'Ctrl') return platform === 'darwin' ? 'Control' : 'Control';
      if (part === 'Cmd') return 'Command';
      if (part === 'Super') return 'Super';
      if (part === 'Alt') return 'Alt';
      if (part === 'Shift') return 'Shift';
      return part;
    })
    .join('+');
}

function formatHotkeyDisplay(normalizedHotkey) {
  return normalizeHotkeyString(normalizedHotkey).split('+').join(' + ');
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

class EncryptedVault {
  constructor(vaultPath, machineSeed = null) {
    this.vaultPath = vaultPath;
    this.machineSeed =
      machineSeed ||
      `${os.hostname()}|${os.platform()}|${os.arch()}|loopsearch-vault-v1`;
    this._key = null;
  }

  _getKey() {
    if (!this._key) {
      this._key = crypto.scryptSync(this.machineSeed, 'loopsearch-aes-gcm-salt', 32);
    }
    return this._key;
  }

  _readAll() {
    try {
      if (!fs.existsSync(this.vaultPath)) return {};
      const raw = JSON.parse(fs.readFileSync(this.vaultPath, 'utf8'));
      const decipher = crypto.createDecipheriv(
        'aes-256-gcm',
        this._getKey(),
        Buffer.from(raw.iv, 'base64')
      );
      decipher.setAuthTag(Buffer.from(raw.tag, 'base64'));
      const plain = Buffer.concat([
        decipher.update(Buffer.from(raw.data, 'base64')),
        decipher.final()
      ]);
      return JSON.parse(plain.toString('utf8'));
    } catch {
      return {};
    }
  }

  _writeAll(obj) {
    ensureDir(path.dirname(this.vaultPath));
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this._getKey(), iv);
    const jsonBuf = Buffer.from(JSON.stringify(obj), 'utf8');
    const encrypted = Buffer.concat([cipher.update(jsonBuf), cipher.final()]);
    const payload = {
      v: 1,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      data: encrypted.toString('base64')
    };
    const tmpPath = `${this.vaultPath}.tmp`;
    fs.writeFileSync(tmpPath, JSON.stringify(payload), { mode: 0o600 });
    fs.renameSync(tmpPath, this.vaultPath);
  }

  get(key, fallback = null) {
    const all = this._readAll();
    return Object.prototype.hasOwnProperty.call(all, key) ? all[key] : fallback;
  }

  set(key, value) {
    const all = this._readAll();
    if (value === null || value === undefined || value === '') {
      delete all[key];
    } else {
      all[key] = value;
    }
    this._writeAll(all);
  }
}

class SettingsStore {
  constructor(userDataDir, machineSeed = null) {
    this.userDataDir = userDataDir;
    this.settingsPath = path.join(userDataDir, 'settings.json');
    this.historyPath = path.join(userDataDir, 'history.json');
    this.vault = new EncryptedVault(path.join(userDataDir, 'vault.enc.json'), machineSeed);
    this._state = null;
  }

  load() {
    let saved = {};
    try {
      if (fs.existsSync(this.settingsPath)) {
        saved = JSON.parse(fs.readFileSync(this.settingsPath, 'utf8'));
      }
    } catch {
      saved = {};
    }
    this._state = { ...DEFAULT_SETTINGS, ...saved };
    this._state.hotkey = normalizeHotkeyString(this._state.hotkey);
    return this.getPublicSettings();
  }

  getPublicSettings() {
    if (!this._state) this.load();
    const apiKey = this.getGeminiApiKey();
    return {
      ...this._state,
      hotkeyDisplay: formatHotkeyDisplay(this._state.hotkey),
      appVersion: APP_VERSION,
      hasGeminiApiKey: Boolean(apiKey && apiKey.trim().length > 0),
      maskedGeminiApiKey: apiKey
        ? apiKey.length > 8
          ? `${apiKey.slice(0, 4)}••••••${apiKey.slice(-4)}`
          : '••••••••'
        : ''
    };
  }

  update(patch) {
    if (!this._state) this.load();
    const next = { ...this._state };
    for (const [k, v] of Object.entries(patch || {})) {
      if (!Object.prototype.hasOwnProperty.call(DEFAULT_SETTINGS, k)) continue;
      if (k === 'hotkey') {
        next.hotkey = normalizeHotkeyString(v);
      } else {
        next[k] = v;
      }
    }
    this._state = next;
    ensureDir(this.userDataDir);
    fs.writeFileSync(this.settingsPath, JSON.stringify(this._state, null, 2));
    return this.getPublicSettings();
  }

  incrementSearchCount() {
    const curr = this.getPublicSettings().searchCount || 0;
    const updated = this.update({ searchCount: curr + 1 });
    return {
      settings: updated,
      shouldPromptForFeedback:
        !updated.feedbackPromptDismissed &&
        updated.searchCount >= 5 &&
        updated.searchCount - (updated.lastFeedbackPromptCount || 0) >= 12
    };
  }

  getGeminiApiKey() {
    return this.vault.get('geminiApiKey', '');
  }

  setGeminiApiKey(key) {
    this.vault.set('geminiApiKey', (key || '').trim());
    return this.getPublicSettings();
  }

  getHistory() {
    try {
      if (!fs.existsSync(this.historyPath)) return [];
      const parsed = JSON.parse(fs.readFileSync(this.historyPath, 'utf8'));
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  addHistoryItem(item) {
    const items = this.getHistory();
    const next = [
      {
        id: item.id || crypto.randomUUID(),
        createdAt: item.createdAt || new Date().toISOString(),
        mode: item.mode || 'box',
        query: item.query || '',
        ocrText: item.ocrText || '',
        lensUrl: item.lensUrl || '',
        thumbnailDataUrl: item.thumbnailDataUrl || ''
      },
      ...items.filter((x) => x.id !== item.id)
    ].slice(0, MAX_HISTORY_ITEMS);
    ensureDir(this.userDataDir);
    fs.writeFileSync(this.historyPath, JSON.stringify(next));
    return next;
  }

  clearHistory() {
    ensureDir(this.userDataDir);
    fs.writeFileSync(this.historyPath, JSON.stringify([]));
    return [];
  }
}

module.exports = {
  APP_VERSION,
  DEFAULT_SETTINGS,
  HOTKEY_PRESETS,
  MAX_HISTORY_ITEMS,
  normalizeHotkeyString,
  toElectronAccelerator,
  formatHotkeyDisplay,
  EncryptedVault,
  SettingsStore
};
