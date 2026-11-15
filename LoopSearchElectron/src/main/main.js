'use strict';

const fs = require('fs');
const path = require('path');
const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  globalShortcut,
  desktopCapturer,
  screen,
  ipcMain,
  clipboard,
  nativeImage,
  dialog,
  shell,
  session,
  nativeTheme,
  powerMonitor
} = require('electron');

const {
  APP_VERSION,
  HOTKEY_PRESETS,
  SettingsStore,
  toElectronAccelerator,
  formatHotkeyDisplay
} = require('./settings');
const {
  FirebaseAuthService,
  formatOsVersion
} = require('./firebaseAuth');
const {
  MOBILE_SAFARI_UA,
  GITHUB_URLS,
  uploadToGoogleLens,
  buildLensDarkThemeInjectionScript,
  runWindowsOcr,
  callGeminiVision,
  checkForUpdates,
  buildFeedbackIssueUrl
} = require('./lensAndAi');

const BUILD_DIR = path.join(__dirname, '../../build');
const RENDERER_DIR = path.join(__dirname, '../renderer');
const PRELOAD_PATH = path.join(__dirname, 'preload.js');

const cliArgs = process.argv.slice(2);
const uiCheckArg = cliArgs.find((a) => a.startsWith('--ui-check-dir='));
const UI_CHECK_DIR = uiCheckArg ? uiCheckArg.slice('--ui-check-dir='.length) : null;

let store;
let authService;
let tray = null;
let overlayWin = null;
let toastWin = null;
let toastTimer = null;
const windows = {
  onboarding: null,
  settings: null,
  howToUse: null,
  about: null,
  feedback: null
};
const pinnedWindows = new Set();
let isCapturing = false;
let isQuitting = false;
let registeredAccelerator = null;
let latestUpdateState = null;

if (process.platform === 'win32') {
  app.setAppUserModelId('com.loopsearch.windows');
}
app.commandLine.appendSwitch('enable-features', 'CalculateNativeWinOcclusion');
app.commandLine.appendSwitch('disable-renderer-backgrounding', 'false');

const gotSingleLock = UI_CHECK_DIR ? true : app.requestSingleInstanceLock();
if (!gotSingleLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (authService) {
      authService.recordResumeHeartbeat({ minIntervalMs: 60 * 1000 }).catch(() => {});
    }
    if (overlayWin && !overlayWin.isDestroyed()) {
      overlayWin.focus();
      return;
    }
    if (windows.onboarding && !windows.onboarding.isDestroyed()) {
      windows.onboarding.show();
      windows.onboarding.focus();
      return;
    }
    openManagedWindow('settings');
  });
}

function getLensSession() {
  const s = session.fromPartition('persist:lens');
  s.setUserAgent(MOBILE_SAFARI_UA);
  return s;
}

function broadcastAll(channel, payload) {
  for (const win of BrowserWindow.getAllWindows()) {
    if (!win.isDestroyed()) {
      win.webContents.send(channel, payload);
    }
  }
}

function resolveEffectiveTheme(settings) {
  if (settings.theme === 'light') return 'light';
  if (settings.theme === 'dark') return 'dark';
  return nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
}

function decorateSettings(settings) {
  return {
    ...settings,
    effectiveTheme: resolveEffectiveTheme(settings),
    osVersion: formatOsVersion(),
    githubRepoUrl: GITHUB_URLS.repo,
    xProfileUrl: GITHUB_URLS.xProfile,
    geminiKeyPortalUrl: GITHUB_URLS.geminiKeyPortal
  };
}

function createFramelessGlassWindow({
  width,
  height,
  title,
  htmlFile,
  resizable = false,
  alwaysOnTop = false,
  onReady = null
}) {
  const iconPath = path.join(BUILD_DIR, process.platform === 'win32' ? 'AppIcon.ico' : 'AppIcon.png');
  const win = new BrowserWindow({
    width,
    height,
    title,
    icon: fs.existsSync(iconPath) ? iconPath : undefined,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    hasShadow: false,
    resizable,
    maximizable: false,
    minimizable: !alwaysOnTop,
    alwaysOnTop,
    skipTaskbar: false,
    show: false,
    webPreferences: {
      preload: PRELOAD_PATH,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  win.loadFile(path.join(RENDERER_DIR, htmlFile));
  win.once('ready-to-show', () => {
    win.show();
    win.focus();
    if (onReady) onReady(win);
  });
  return win;
}

function openManagedWindow(name) {
  const specs = {
    onboarding: { width: 580, height: 760, title: 'Welcome to LoopSearch', htmlFile: 'onboarding.html' },
    settings: { width: 572, height: 702, title: 'LoopSearch Studio', htmlFile: 'settings.html' },
    howToUse: { width: 564, height: 644, title: 'How to Use LoopSearch', htmlFile: 'how-to-use.html' },
    about: { width: 420, height: 392, title: 'About LoopSearch', htmlFile: 'about.html' },
    feedback: { width: 496, height: 492, title: 'Rate & Suggest Feature', htmlFile: 'feedback.html' }
  };
  const spec = specs[name];
  if (!spec) return null;

  const existing = windows[name];
  if (existing && !existing.isDestroyed()) {
    if (existing.isMinimized()) existing.restore();
    existing.show();
    existing.focus();
    return existing;
  }

  const win = createFramelessGlassWindow(spec);
  windows[name] = win;
  win.on('closed', () => {
    if (windows[name] === win) windows[name] = null;
  });
  return win;
}

function showToast(message, kind = 'info') {
  if (!message) return;
  const cursor = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(cursor);
  const wa = display.workArea;
  const width = Math.max(240, Math.min(520, 96 + message.length * 7.2));
  const height = 56;
  const x = Math.round(wa.x + (wa.width - width) / 2);
  const y = Math.round(wa.y + wa.height - height - 24);

  if (toastTimer) {
    clearTimeout(toastTimer);
    toastTimer = null;
  }

  if (toastWin && !toastWin.isDestroyed()) {
    toastWin.setBounds({ x, y, width, height });
    toastWin.webContents.send('toast:init', {
      message,
      kind,
      settings: decorateSettings(store.getPublicSettings())
    });
    toastWin.showInactive();
  } else {
    toastWin = new BrowserWindow({
      x,
      y,
      width,
      height,
      frame: false,
      transparent: true,
      backgroundColor: '#00000000',
      alwaysOnTop: true,
      skipTaskbar: true,
      focusable: false,
      resizable: false,
      hasShadow: false,
      show: false,
      webPreferences: {
        preload: PRELOAD_PATH,
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false
      }
    });
    toastWin.setIgnoreMouseEvents(true);
    toastWin.setAlwaysOnTop(true, 'screen-saver');
    toastWin.loadFile(path.join(RENDERER_DIR, 'toast.html'));
    toastWin.webContents.once('did-finish-load', () => {
      if (!toastWin || toastWin.isDestroyed()) return;
      toastWin.webContents.send('toast:init', {
        message,
        kind,
        settings: decorateSettings(store.getPublicSettings())
      });
    });
    toastWin.once('ready-to-show', () => {
      if (!toastWin || toastWin.isDestroyed()) return;
      toastWin.showInactive();
    });
    toastWin.on('closed', () => {
      toastWin = null;
    });
  }

  toastTimer = setTimeout(() => {
    if (toastWin && !toastWin.isDestroyed()) {
      toastWin.hide();
    }
  }, 2800);
}

function createPinnedWindow({ pngBase64, width, height, title }) {
  const cursor = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(cursor);
  const wa = display.workArea;
  const aspect = height > 0 ? width / height : 1.4;
  let winW = Math.max(190, Math.min(440, Math.round(width || 300)));
  let winH = Math.round(winW / Math.max(0.4, Math.min(2.8, aspect))) + 16;
  if (winH > 380) {
    winH = 380;
    winW = Math.max(190, Math.min(440, Math.round((winH - 16) * aspect)));
  }

  const offset = (pinnedWindows.size % 5) * 24;
  const x = Math.round(wa.x + wa.width - winW - 28 - offset);
  const y = Math.round(wa.y + 28 + offset);

  const win = new BrowserWindow({
    x,
    y,
    width: winW,
    height: winH,
    minWidth: 160,
    minHeight: 110,
    maxWidth: 620,
    maxHeight: 540,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    alwaysOnTop: true,
    resizable: true,
    hasShadow: false,
    skipTaskbar: false,
    show: false,
    webPreferences: {
      preload: PRELOAD_PATH,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });
  win.setAlwaysOnTop(true, 'floating');
  pinnedWindows.add(win);

  const dataUrl = `data:image/png;base64,${pngBase64}`;
  win.loadFile(path.join(RENDERER_DIR, 'pinned.html'));
  win.webContents.once('did-finish-load', () => {
    if (win.isDestroyed()) return;
    win.webContents.send('pinned:init', {
      imageDataUrl: dataUrl,
      title: title || 'Pinned Capture',
      settings: decorateSettings(store.getPublicSettings())
    });
  });
  win.once('ready-to-show', () => {
    if (!win.isDestroyed()) win.show();
  });
  win.on('closed', () => {
    pinnedWindows.delete(win);
    rebuildTrayMenu();
  });
  rebuildTrayMenu();
  showToast('Capture pinned on screen', 'pin');
}

async function captureActiveDisplayPngDataUrl() {
  const cursor = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(cursor);
  const scaleFactor = display.scaleFactor || 1;
  const targetW = Math.max(1, Math.round(display.bounds.width * scaleFactor));
  const targetH = Math.max(1, Math.round(display.bounds.height * scaleFactor));

  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: { width: targetW, height: targetH }
  });

  let matched = sources.find((s) => String(s.display_id) === String(display.id));
  if (!matched && sources.length > 0) {
    matched = sources[0];
  }
  if (!matched || matched.thumbnail.isEmpty()) {
    throw new Error('Desktop capture returned empty frame.');
  }

  return {
    display,
    scaleFactor,
    screenshotDataUrl: matched.thumbnail.toDataURL()
  };
}

async function startOverlay(options = {}) {
  if (isCapturing) return;
  if (overlayWin && !overlayWin.isDestroyed()) {
    overlayWin.focus();
    return;
  }

  if (!UI_CHECK_DIR && authService && !authService.isSignedIn()) {
    showToast('Please sign in with Google to start searching', 'info');
    openManagedWindow('onboarding');
    return;
  }

  if (authService) {
    authService.recordResumeHeartbeat({ minIntervalMs: 15 * 60 * 1000 }).catch(() => {});
  }

  isCapturing = true;
  try {
    let capture;
    if (options.mockScreenshotDataUrl) {
      const display = screen.getPrimaryDisplay();
      capture = {
        display,
        scaleFactor: display.scaleFactor || 1,
        screenshotDataUrl: options.mockScreenshotDataUrl
      };
    } else {
      capture = await captureActiveDisplayPngDataUrl();
    }

    const { display, scaleFactor, screenshotDataUrl } = capture;
    const bounds = display.bounds;
    const workArea = display.workArea;
    const safeInsets = {
      top: Math.max(0, workArea.y - bounds.y),
      left: Math.max(0, workArea.x - bounds.x),
      right: Math.max(0, bounds.x + bounds.width - (workArea.x + workArea.width)),
      bottom: Math.max(0, bounds.y + bounds.height - (workArea.y + workArea.height))
    };

    getLensSession();

    const win = new BrowserWindow({
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      frame: false,
      transparent: true,
      backgroundColor: '#00000000',
      alwaysOnTop: true,
      skipTaskbar: true,
      enableLargerThanScreen: true,
      hasShadow: false,
      resizable: false,
      movable: false,
      fullscreenable: false,
      show: false,
      webPreferences: {
        preload: PRELOAD_PATH,
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        webviewTag: true
      }
    });

    win.setAlwaysOnTop(true, 'screen-saver');
    overlayWin = win;

    const settings = decorateSettings(store.getPublicSettings());
    const initPayload = {
      screenshotDataUrl,
      screenWidth: bounds.width,
      screenHeight: bounds.height,
      scaleFactor,
      safeInsets,
      settings,
      auth: authService.getPublicState(),
      mode: options.mode || settings.defaultMode || 'box',
      clipboardImageDataUrl: options.clipboardImageDataUrl || null,
      mockSelection: options.mockSelection || null,
      history: store.getHistory()
    };

    win.loadFile(path.join(RENDERER_DIR, 'overlay.html'));
    win.webContents.once('did-finish-load', () => {
      if (win.isDestroyed()) return;
      win.webContents.send('overlay:init', initPayload);
    });
    win.once('ready-to-show', () => {
      if (win.isDestroyed()) return;
      win.setBounds(bounds);
      win.show();
      win.focus();
    });
    win.on('closed', () => {
      if (overlayWin === win) overlayWin = null;
    });
  } catch (err) {
    showToast(
      process.platform === 'darwin'
        ? 'Allow Screen Recording in macOS System Settings to capture screen'
        : `Capture error: ${err.message}`,
      'error'
    );
  } finally {
    isCapturing = false;
  }
}

function registerGlobalHotkey() {
  globalShortcut.unregisterAll();
  registeredAccelerator = null;
  if (!store) return false;
  const settings = store.getPublicSettings();
  const accel = toElectronAccelerator(settings.hotkey);
  try {
    const ok = globalShortcut.register(accel, () => {
      startOverlay();
    });
    if (ok) {
      registeredAccelerator = accel;
    } else {
      showToast(`Hotkey ${formatHotkeyDisplay(settings.hotkey)} could not be registered`, 'error');
    }
    return ok;
  } catch {
    return false;
  }
}

function applyLaunchAtLogin(enabled) {
  if (UI_CHECK_DIR) return;
  if (process.platform === 'win32' || process.platform === 'darwin') {
    try {
      app.setLoginItemSettings({
        openAtLogin: Boolean(enabled),
        args: ['--background']
      });
    } catch {}
  }
}

function createTray() {
  const iconFile = path.join(BUILD_DIR, 'AppIcon.png');
  let icon = nativeImage.createFromPath(iconFile);
  if (!icon.isEmpty()) {
    const targetSize = process.platform === 'win32' ? 20 : 18;
    icon = icon.resize({ width: targetSize, height: targetSize, quality: 'best' });
  }
  tray = new Tray(icon);
  tray.on('click', () => {
    if (process.platform === 'win32') {
      startOverlay();
    } else {
      tray.popUpContextMenu();
    }
  });
  tray.on('right-click', () => {
    tray.popUpContextMenu();
  });
  rebuildTrayMenu();
}

function rebuildTrayMenu() {
  if (!tray || tray.isDestroyed() || !store) return;
  const settings = store.getPublicSettings();
  const auth = authService.getPublicState();
  const history = store.getHistory();

  tray.setToolTip(
    `LoopSearch (${settings.hotkeyDisplay})${auth.signedIn ? ` — ${auth.displayName}` : ''}`
  );

  const historySubmenu =
    history.length > 0
      ? [
          ...history.slice(0, 8).map((item, idx) => ({
            label: `${idx + 1}. ${(item.query || item.ocrText || item.mode || 'Capture').slice(0, 38)}`,
            click: () => {
              if (item.lensUrl) shell.openExternal(item.lensUrl);
              else startOverlay();
            }
          })),
          { type: 'separator' },
          {
            label: 'Clear Capture History',
            click: () => {
              store.clearHistory();
              rebuildTrayMenu();
              showToast('Capture history cleared', 'info');
            }
          }
        ]
      : [{ label: 'No Recent Captures', enabled: false }];

  const template = [];

  if (latestUpdateState && latestUpdateState.updateAvailable) {
    template.push(
      {
        label: `Update Available: v${latestUpdateState.latestVersion} — Download…`,
        click: () => shell.openExternal(latestUpdateState.releaseUrl)
      },
      { type: 'separator' }
    );
  }

  template.push(
    {
      label: `Circle to Search (${settings.hotkeyDisplay})`,
      click: () => startOverlay()
    },
    {
      label: 'OCR Text Selection Mode',
      click: () => startOverlay({ mode: 'text' })
    },
    {
      label: 'Search Clipboard Image',
      click: () => searchClipboardImage()
    },
    {
      label: 'Capture History',
      submenu: historySubmenu
    }
  );

  if (pinnedWindows.size > 0) {
    template.push({
      label: `Close All Pinned Notes (${pinnedWindows.size})`,
      click: () => {
        for (const pw of [...pinnedWindows]) {
          if (!pw.isDestroyed()) pw.close();
        }
      }
    });
  }

  template.push(
    { type: 'separator' },
    {
      label: 'LoopSearch Studio...',
      click: () => openManagedWindow('settings')
    },
    {
      label: 'How to Use',
      click: () => openManagedWindow('howToUse')
    },
    {
      label: 'Welcome Guide',
      click: () => openManagedWindow('onboarding')
    },
    {
      label:
        latestUpdateState && latestUpdateState.updateAvailable
          ? `Install Update (v${latestUpdateState.latestVersion})…`
          : 'Check for Updates...',
      click: () =>
        latestUpdateState && latestUpdateState.updateAvailable
          ? shell.openExternal(latestUpdateState.releaseUrl)
          : handleMenuUpdateCheck()
    },
    {
      label: 'Rate & Suggest Feature...',
      click: () => openManagedWindow('feedback')
    },
    {
      label: 'About LoopSearch',
      click: () => openManagedWindow('about')
    },
    { type: 'separator' },
    auth.signedIn
      ? {
          label: `Signed in: ${auth.email || auth.displayName}`,
          submenu: [
            {
              label: 'Sign Out',
              click: () => authService.signOut()
            }
          ]
        }
      : {
          label: 'Sign In with Google...',
          click: () => authService.startInteractiveSignIn().catch((e) => showToast(e.message, 'error'))
        },
    { type: 'separator' },
    {
      label: 'Quit LoopSearch',
      click: () => {
        isQuitting = true;
        app.quit();
      }
    }
  );

  tray.setContextMenu(Menu.buildFromTemplate(template));
}

async function searchClipboardImage() {
  const img = clipboard.readImage();
  if (img.isEmpty()) {
    showToast('No image found in clipboard', 'error');
    return;
  }
  await startOverlay({
    clipboardImageDataUrl: img.toDataURL(),
    mode: 'box'
  });
}

async function refreshUpdateState({ silent = false } = {}) {
  try {
    const res = await checkForUpdates(APP_VERSION);
    const prevAvailable = Boolean(latestUpdateState && latestUpdateState.updateAvailable);
    const prevVer = latestUpdateState && latestUpdateState.latestVersion;
    latestUpdateState = { ok: true, ...res };
    if (res.updateAvailable) {
      rebuildTrayMenu();
      broadcastAll('app:update-available', latestUpdateState);
      if (!prevAvailable || prevVer !== res.latestVersion) {
        showToast(`Update available: LoopSearch v${res.latestVersion}`, 'info', 4200);
      }
    } else if (prevAvailable) {
      rebuildTrayMenu();
      broadcastAll('app:update-available', latestUpdateState);
    }
    return latestUpdateState;
  } catch (err) {
    if (!silent) throw err;
    return null;
  }
}

async function handleMenuUpdateCheck() {
  try {
    const res = await refreshUpdateState({ silent: false });
    if (res.updateAvailable) {
      const choice = await dialog.showMessageBox({
        type: 'info',
        title: 'LoopSearch Update Available',
        message: `LoopSearch v${res.latestVersion} is available (you have v${res.currentVersion}).`,
        buttons: ['Download Update', 'Later'],
        defaultId: 0
      });
      if (choice.response === 0) shell.openExternal(res.releaseUrl);
    } else {
      showToast(`LoopSearch v${APP_VERSION} is up to date`, 'success');
    }
  } catch (err) {
    showToast(`Update check failed: ${err.message}`, 'error');
  }
}

function wireIpcHandlers() {
  ipcMain.handle('settings:get', () => decorateSettings(store.getPublicSettings()));
  ipcMain.handle('settings:presets', () => HOTKEY_PRESETS);
  ipcMain.handle('settings:update', (_e, patch) => {
    const prevHotkey = store.getPublicSettings().hotkey;
    const prevLaunch = store.getPublicSettings().launchAtLogin;
    const next = decorateSettings(store.update(patch));
    if (next.hotkey !== prevHotkey) {
      registerGlobalHotkey();
      rebuildTrayMenu();
    }
    if (next.launchAtLogin !== prevLaunch) {
      applyLaunchAtLogin(next.launchAtLogin);
    }
    broadcastAll('settings:changed', next);
    return next;
  });
  ipcMain.handle('settings:set-gemini-key', (_e, key) => {
    const next = decorateSettings(store.setGeminiApiKey(key));
    broadcastAll('settings:changed', next);
    return next;
  });

  ipcMain.handle('auth:get', () => authService.getPublicState());
  ipcMain.handle('auth:sign-in', async () => {
    try {
      const res = await authService.startInteractiveSignIn();
      showToast(`Signed in as ${res.displayName || res.email}`, 'success');
      if (!store.getPublicSettings().onboardingCompleted) {
        store.update({ onboardingCompleted: true });
      }
      openManagedWindow('howToUse');
      return { ok: true, auth: res };
    } catch (err) {
      showToast(err.message || 'Sign-in failed', 'error');
      return { ok: false, error: err.message };
    }
  });
  ipcMain.handle('auth:sign-out', async () => {
    const res = await authService.signOut();
    showToast('Signed out of LoopSearch', 'info');
    return res;
  });

  ipcMain.handle('history:get', () => store.getHistory());
  ipcMain.handle('history:add', (_e, item) => {
    const list = store.addHistoryItem(item);
    rebuildTrayMenu();
    return list;
  });
  ipcMain.handle('history:clear', () => {
    const list = store.clearHistory();
    rebuildTrayMenu();
    return list;
  });

  ipcMain.handle('window:open', (_e, name) => {
    openManagedWindow(name);
    return true;
  });
  ipcMain.handle('window:close', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender);
    if (win && !win.isDestroyed()) win.close();
  });
  ipcMain.handle('window:minimize', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender);
    if (win && !win.isDestroyed()) win.minimize();
  });
  ipcMain.handle('overlay:start', async (_e, opts) => {
    await startOverlay(opts);
  });
  ipcMain.handle('overlay:close', () => {
    if (overlayWin && !overlayWin.isDestroyed()) overlayWin.close();
  });

  ipcMain.handle('toast:show', (_e, { message, kind }) => {
    showToast(message, kind);
  });

  ipcMain.handle('lens:upload', async (_e, jpegBase64) => {
    const buf = Buffer.from(jpegBase64, 'base64');
    return uploadToGoogleLens(buf, getLensSession());
  });

  ipcMain.handle('vision:ocr', async (_e, pngBase64) => {
    const buf = Buffer.from(pngBase64, 'base64');
    return runWindowsOcr(buf);
  });

  ipcMain.handle('ai:gemini', async (_e, { imageBase64, prompt }) => {
    const apiKey = store.getGeminiApiKey();
    try {
      const answer = await callGeminiVision({ apiKey, imageBase64, prompt });
      return { ok: true, answer };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  });

  ipcMain.handle('lens:dark-script', (_e, enableDark) => {
    return buildLensDarkThemeInjectionScript(Boolean(enableDark));
  });

  ipcMain.handle('telemetry:search-success', () => {
    if (authService) {
      authService.recordResumeHeartbeat({ minIntervalMs: 15 * 60 * 1000 }).catch(() => {});
    }
    const res = store.incrementSearchCount();
    if (res.shouldPromptForFeedback) {
      store.update({ lastFeedbackPromptCount: res.settings.searchCount });
      setTimeout(() => openManagedWindow('feedback'), 900);
    }
    return {
      settings: decorateSettings(res.settings),
      shouldPromptForFeedback: res.shouldPromptForFeedback
    };
  });

  ipcMain.handle('pinned:create', (_e, payload) => {
    createPinnedWindow(payload);
    return true;
  });
  ipcMain.handle('pinned:clear-all', () => {
    for (const pw of [...pinnedWindows]) {
      if (!pw.isDestroyed()) pw.close();
    }
  });

  ipcMain.handle('clipboard:write-text', (_e, text) => {
    clipboard.writeText(String(text || ''));
    return true;
  });
  ipcMain.handle('clipboard:write-image', (_e, dataUrl) => {
    const img = nativeImage.createFromDataURL(dataUrl);
    if (!img.isEmpty()) clipboard.writeImage(img);
    return true;
  });

  ipcMain.handle('capture:save-png', async (e, pngBase64) => {
    const parentWin = BrowserWindow.fromWebContents(e.sender);
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const defaultPath = path.join(app.getPath('pictures'), `LoopSearch-${ts}.png`);
    const result = await dialog.showSaveDialog(parentWin || undefined, {
      title: 'Save Captured Region',
      defaultPath,
      filters: [{ name: 'PNG Image', extensions: ['png'] }]
    });
    if (result.canceled || !result.filePath) {
      return { saved: false };
    }
    fs.writeFileSync(result.filePath, Buffer.from(pngBase64, 'base64'));
    showToast('Saved capture PNG', 'success');
    return { saved: true, filePath: result.filePath };
  });

  ipcMain.handle('app:open-external', (_e, url) => {
    if (typeof url === 'string' && (url.startsWith('https://') || url.startsWith('http://'))) {
      shell.openExternal(url);
      return true;
    }
    return false;
  });

  ipcMain.handle('app:check-updates', async () => {
    try {
      return await refreshUpdateState({ silent: false });
    } catch (err) {
      return { ok: false, error: err.message };
    }
  });
  ipcMain.handle('app:get-update-state', () => latestUpdateState);

  ipcMain.handle('app:open-feedback', (_e, payload) => {
    const url = buildFeedbackIssueUrl({
      ...payload,
      appVersion: APP_VERSION,
      osVersion: formatOsVersion()
    });
    shell.openExternal(url);
    return true;
  });

  ipcMain.handle('app:info', () => ({
    appVersion: APP_VERSION,
    osVersion: formatOsVersion(),
    platform: process.platform,
    registeredAccelerator
  }));
}

function buildMockDesktopScreenshotSvgDataUrl(width = 1440, height = 900) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#0d1324"/>
        <stop offset="50%" stop-color="#131c36"/>
        <stop offset="100%" stop-color="#0a1020"/>
      </linearGradient>
      <radialGradient id="glow" cx="65%" cy="35%" r="55%">
        <stop offset="0%" stop-color="#2563eb" stop-opacity="0.32"/>
        <stop offset="100%" stop-color="#0a1020" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <rect width="100%" height="100%" fill="url(#bg)"/>
    <rect width="100%" height="100%" fill="url(#glow)"/>
    <rect x="80" y="90" width="760" height="580" rx="18" fill="#172038" stroke="#334155" stroke-width="2"/>
    <rect x="110" y="130" width="280" height="36" rx="10" fill="#2563eb" fill-opacity="0.25"/>
    <text x="128" y="155" fill="#93c5fd" font-family="sans-serif" font-size="18" font-weight="600">LoopSearch Visual Test Canvas</text>
    <rect x="110" y="200" width="440" height="220" rx="14" fill="#1e293b"/>
    <circle cx="230" cy="310" r="64" fill="#38bdf8" fill-opacity="0.28" stroke="#38bdf8" stroke-width="3"/>
    <text x="330" y="275" fill="#e2e8f0" font-family="sans-serif" font-size="22" font-weight="600">JetBrains IntelliJ IDEA 2026.2</text>
    <text x="330" y="315" fill="#94a3b8" font-family="sans-serif" font-size="16">128 + 256 = ?  •  https://github.com</text>
    <text x="330" y="355" fill="#7dd3fc" font-family="monospace" font-size="16">#38BDF8  •  Sample OCR Region</text>
  </svg>`;
  return 'data:image/svg+xml;base64,' + Buffer.from(svg, 'utf8').toString('base64');
}

async function runUiScreenshotVerification(outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  const waitLoaded = (win) =>
    new Promise((resolve) => {
      const done = () => {
        if (win.isVisible()) return resolve();
        win.once('show', resolve);
        setTimeout(resolve, 400);
      };
      if (win.webContents.isLoadingMainFrame()) {
        win.webContents.once('did-finish-load', done);
      } else {
        done();
      }
    });

  const captureWin = async (win, filename, delayMs = 650) => {
    await waitLoaded(win);
    await wait(delayMs);
    const img = await win.webContents.capturePage();
    fs.writeFileSync(path.join(outDir, filename), img.toPNG());
    if (!win.isDestroyed()) win.close();
  };

  await captureWin(openManagedWindow('onboarding'), '01-onboarding.png', 750);

  const studioWin = openManagedWindow('settings');
  await waitLoaded(studioWin);
  await wait(700);
  fs.writeFileSync(path.join(outDir, '02-settings.png'), (await studioWin.webContents.capturePage()).toPNG());
  await studioWin.webContents.executeJavaScript("document.querySelector('[data-tab=\"appearance\"]').click()");
  await wait(520);
  fs.writeFileSync(path.join(outDir, '02b-settings-glass.png'), (await studioWin.webContents.capturePage()).toPNG());
  await studioWin.webContents.executeJavaScript("document.querySelector('[data-tab=\"ai\"]').click()");
  await wait(520);
  fs.writeFileSync(path.join(outDir, '02c-settings-ai.png'), (await studioWin.webContents.capturePage()).toPNG());
  if (!studioWin.isDestroyed()) studioWin.close();

  await captureWin(openManagedWindow('howToUse'), '03-how-to-use.png', 650);
  await captureWin(openManagedWindow('about'), '04-about.png', 650);
  await captureWin(openManagedWindow('feedback'), '05-feedback.png', 650);

  showToast('Copied text to clipboard', 'success');
  await wait(550);
  if (toastWin && !toastWin.isDestroyed()) {
    const tImg = await toastWin.webContents.capturePage();
    fs.writeFileSync(path.join(outDir, '06-toast.png'), tImg.toPNG());
    toastWin.close();
  }

  const display = screen.getPrimaryDisplay();
  await startOverlay({
    mockScreenshotDataUrl: buildMockDesktopScreenshotSvgDataUrl(
      display.bounds.width,
      display.bounds.height
    ),
    mockSelection: {
      x: Math.round(display.bounds.width * 0.14),
      y: Math.round(display.bounds.height * 0.22),
      w: Math.round(display.bounds.width * 0.34),
      h: Math.round(display.bounds.height * 0.30)
    }
  });
  await wait(1200);
  if (overlayWin && !overlayWin.isDestroyed()) {
    const oImg = await overlayWin.webContents.capturePage();
    fs.writeFileSync(path.join(outDir, '07-overlay.png'), oImg.toPNG());
    overlayWin.close();
  }

  app.quit();
}

app.on('web-contents-created', (_e, contents) => {
  if (contents.getType() === 'webview') {
    contents.setWindowOpenHandler(({ url }) => {
      if (url && (url.startsWith('https://') || url.startsWith('http://'))) {
        shell.openExternal(url);
      }
      return { action: 'deny' };
    });
  }
});

app.on('window-all-closed', () => {
  // Keep resident in System Tray just like macOS menu bar app
  if (UI_CHECK_DIR || isQuitting) {
    app.quit();
  }
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.whenReady().then(async () => {
  const userDataDir = UI_CHECK_DIR ? path.join(UI_CHECK_DIR, '_userdata') : app.getPath('userData');
  store = new SettingsStore(userDataDir);
  const initialSettings = store.load();

  authService = new FirebaseAuthService({
    vault: store.vault,
    appVersion: APP_VERSION,
    openExternal: (url) => shell.openExternal(url),
    telemetryDisabled: Boolean(UI_CHECK_DIR || process.env.LOOPSEARCH_NO_TELEMETRY === '1')
  });

  authService.onChange((state) => {
    rebuildTrayMenu();
    broadcastAll('auth:changed', state);
  });

  wireIpcHandlers();
  createTray();
  registerGlobalHotkey();
  applyLaunchAtLogin(initialSettings.launchAtLogin);

  if (UI_CHECK_DIR) {
    await runUiScreenshotVerification(UI_CHECK_DIR);
    return;
  }

  // Silent session resume telemetry (strictly sends 'session_resume' per firestore.rules)
  authService.restoreAndRecordResume().catch(() => {});

  // Flush offline-queued analytics or wake-from-sleep sessions reliably
  powerMonitor.on('resume', () => {
    authService.recordResumeHeartbeat({ minIntervalMs: 5 * 60 * 1000 }).catch(() => {});
  });
  powerMonitor.on('unlock-screen', () => {
    authService.recordResumeHeartbeat({ minIntervalMs: 15 * 60 * 1000 }).catch(() => {});
  });
  const pendingFlushTimer = setInterval(() => {
    const pending = store.vault.get('pendingLoginEvents', []);
    if (Array.isArray(pending) && pending.length > 0) {
      authService.flushPendingEvents().catch(() => {});
    }
  }, 60 * 1000);
  if (typeof pendingFlushTimer.unref === 'function') pendingFlushTimer.unref();

  setTimeout(() => {
    refreshUpdateState({ silent: true }).catch(() => {});
  }, 3500);

  const isBackgroundLaunch = cliArgs.includes('--background');
  if (!isBackgroundLaunch) {
    if (!initialSettings.onboardingCompleted || !authService.isSignedIn()) {
      openManagedWindow('onboarding');
    } else {
      showToast(`LoopSearch ready — Press ${initialSettings.hotkeyDisplay}`, 'info', 2600);
    }
  }
});
