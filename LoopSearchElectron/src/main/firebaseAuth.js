'use strict';

const http = require('http');
const os = require('os');
const crypto = require('crypto');

const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyD67B6MnCvLwYB5xLQVH3IQdguetSe-Koc',
  projectId: 'loopsearch-analytics-78e3',
  databaseId: '(default)',
  authPageUrl: 'https://loopsearch-analytics-78e3.web.app/app-auth.html',
  authRequestUri: 'https://loopsearch-analytics-78e3.web.app'
};

const ALLOWED_EVENT_TYPES = new Set(['interactive_sign_in', 'session_resume']);
const MAX_PENDING_EVENTS = 25;

function formatOsVersion(platform = process.platform, release = os.release()) {
  let label;
  if (platform === 'win32') {
    const parts = String(release).split('.');
    const major = Number(parts[0] || 10);
    const build = Number(parts[2] || 0);
    const winName = major >= 10 && build >= 22000 ? 'Windows 11' : 'Windows 10';
    label = `${winName} (${release})`;
  } else if (platform === 'darwin') {
    label = `macOS (${release})`;
  } else {
    label = `${platform} (${release})`;
  }
  return label.slice(0, 60);
}

function getUtcDateKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function strVal(v) {
  return { stringValue: String(v ?? '') };
}

function buildFirestoreCommitWrites({
  session,
  eventType,
  eventId,
  dateKey,
  appVersion,
  osVersion,
  userExists
}) {
  if (!ALLOWED_EVENT_TYPES.has(eventType)) {
    throw new Error(`Invalid Firestore eventType: ${eventType}`);
  }
  if (!session || !session.uid) {
    throw new Error('Cannot build Firestore commit without session.uid');
  }

  const uid = String(session.uid);
  const email = String(session.email || '');
  const displayName = String(session.displayName || (email ? email.split('@')[0] : 'LoopSearch User'));
  const photoURL = String(session.photoURL || '');
  const safeDateKey = String(dateKey || getUtcDateKey()).slice(0, 10);
  const safeAppVer = String(appVersion || '1.0.3').slice(0, 40);
  const safeOsVer = String(osVersion || formatOsVersion()).slice(0, 60);
  const evtId = String(eventId || crypto.randomUUID());

  const userDocName = `projects/${FIREBASE_CONFIG.projectId}/databases/${FIREBASE_CONFIG.databaseId}/documents/users/${uid}`;
  const eventDocName = `projects/${FIREBASE_CONFIG.projectId}/databases/${FIREBASE_CONFIG.databaseId}/documents/loginEvents/${evtId}`;

  const userWrite = userExists
    ? {
        update: {
          name: userDocName,
          fields: {
            uid: strVal(uid),
            email: strVal(email),
            displayName: strVal(displayName),
            photoURL: strVal(photoURL),
            lastDateKey: strVal(safeDateKey),
            appVersion: strVal(safeAppVer),
            osVersion: strVal(safeOsVer),
            lastEventType: strVal(eventType)
          }
        },
        updateMask: {
          fieldPaths: [
            'uid',
            'email',
            'displayName',
            'photoURL',
            'lastDateKey',
            'appVersion',
            'osVersion',
            'lastEventType'
          ]
        },
        updateTransforms: [
          { fieldPath: 'loginCount', increment: { integerValue: '1' } },
          { fieldPath: 'lastSeenAt', setToServerValue: 'REQUEST_TIME' },
          { fieldPath: 'lastLoginAt', setToServerValue: 'REQUEST_TIME' }
        ],
        currentDocument: { exists: true }
      }
    : {
        update: {
          name: userDocName,
          fields: {
            uid: strVal(uid),
            email: strVal(email),
            displayName: strVal(displayName),
            photoURL: strVal(photoURL),
            lastDateKey: strVal(safeDateKey),
            loginCount: { integerValue: '1' },
            appVersion: strVal(safeAppVer),
            osVersion: strVal(safeOsVer),
            lastEventType: strVal(eventType)
          }
        },
        updateTransforms: [
          { fieldPath: 'firstSeenAt', setToServerValue: 'REQUEST_TIME' },
          { fieldPath: 'lastSeenAt', setToServerValue: 'REQUEST_TIME' },
          { fieldPath: 'lastLoginAt', setToServerValue: 'REQUEST_TIME' }
        ],
        currentDocument: { exists: false }
      };

  const eventWrite = {
    update: {
      name: eventDocName,
      fields: {
        uid: strVal(uid),
        email: strVal(email),
        displayName: strVal(displayName),
        photoURL: strVal(photoURL),
        dateKey: strVal(safeDateKey),
        appVersion: strVal(safeAppVer),
        osVersion: strVal(safeOsVer),
        eventType: strVal(eventType)
      }
    },
    updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }],
    currentDocument: { exists: false }
  };

  return { writes: [userWrite, eventWrite] };
}

class FirebaseAuthService {
  constructor({ vault, appVersion, openExternal, telemetryDisabled = false }) {
    this.vault = vault;
    this.appVersion = appVersion;
    this.openExternal = openExternal;
    this.telemetryDisabled = telemetryDisabled;
    this._activeServer = null;
    this._session = this.vault.get('firebaseSession', null);
    this._onChangeListeners = new Set();
    this._lastResumeRecordedAt = 0;
    this._resumeInFlight = null;
  }

  onChange(fn) {
    this._onChangeListeners.add(fn);
    return () => this._onChangeListeners.delete(fn);
  }

  _notify() {
    const pub = this.getPublicState();
    for (const fn of this._onChangeListeners) {
      try {
        fn(pub);
      } catch {}
    }
  }

  getPublicState() {
    if (!this._session || !this._session.uid) {
      return {
        signedIn: false,
        uid: null,
        email: null,
        displayName: null,
        photoURL: null
      };
    }
    return {
      signedIn: true,
      uid: this._session.uid,
      email: this._session.email || '',
      displayName: this._session.displayName || 'LoopSearch User',
      photoURL: this._session.photoURL || ''
    };
  }

  isSignedIn() {
    return Boolean(this._session && this._session.uid && this._session.refreshToken);
  }

  async restoreAndRecordResume() {
    return this.recordResumeHeartbeat({ minIntervalMs: 0, refreshProfile: true });
  }

  async recordResumeHeartbeat({ minIntervalMs = 15 * 60 * 1000, refreshProfile = false } = {}) {
    if (!this._session || !this._session.refreshToken) {
      return this.getPublicState();
    }
    if (this._resumeInFlight) {
      return this._resumeInFlight;
    }

    this._resumeInFlight = (async () => {
      try {
        try {
          await this.ensureFreshToken();
          if (refreshProfile) {
            await this.refreshUserProfile();
          }
        } catch {
          // Offline / cold-boot network error: keep local session alive and still queue/flush telemetry below
        }

        const elapsed = Date.now() - (this._lastResumeRecordedAt || 0);
        if (this._lastResumeRecordedAt === 0 || elapsed >= minIntervalMs) {
          this._lastResumeRecordedAt = Date.now();
          await this._recordEventWithFallback('session_resume');
        }
        await this.flushPendingEvents();
      } catch {
        // Offline queue preserves telemetry safely
      } finally {
        this._resumeInFlight = null;
      }
      this._notify();
      return this.getPublicState();
    })();

    return this._resumeInFlight;
  }

  async signOut() {
    this._session = null;
    this.vault.set('firebaseSession', null);
    this._notify();
    return this.getPublicState();
  }

  async startInteractiveSignIn(timeoutMs = 180000) {
    if (this._activeServer) {
      try {
        this._activeServer.close();
      } catch {}
      this._activeServer = null;
    }

    const expectedState = crypto.randomBytes(16).toString('hex');

    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = (err, res) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (this._activeServer) {
          try {
            this._activeServer.close();
          } catch {}
          this._activeServer = null;
        }
        if (err) reject(err);
        else resolve(res);
      };

      const server = http.createServer(async (req, res) => {
        try {
          const url = new URL(req.url || '/', 'http://127.0.0.1');
          const pathname = url.pathname.replace(/\/+$/, '') || '/';
          if (pathname === '/favicon.ico') {
            res.writeHead(204);
            res.end();
            return;
          }
          if (
            pathname === '/oauth2/callback' ||
            pathname === '/auth-callback' ||
            pathname === '/callback' ||
            pathname === '/'
          ) {
            const state = url.searchParams.get('state') || '';
            const errMsg = url.searchParams.get('error');
            const idToken = url.searchParams.get('id_token') || url.searchParams.get('idToken');
            const accessToken = url.searchParams.get('access_token') || url.searchParams.get('accessToken');
            const refreshToken = url.searchParams.get('refresh_token') || url.searchParams.get('refreshToken');
            const oauthCode = url.searchParams.get('code');

            if (state !== expectedState) {
              res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
              res.end(buildAuthResultHtml(false, 'Security state mismatch. Please try signing in again from LoopSearch.'));
              return;
            }
            if (errMsg) {
              res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
              res.end(buildAuthResultHtml(false, `Sign-in cancelled: ${errMsg}`));
              finish(new Error(errMsg));
              return;
            }
            if (!idToken && !accessToken && !oauthCode && !refreshToken) {
              res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
              res.end(buildAuthResultHtml(false, 'Missing Google credentials. Please return to LoopSearch and try again.'));
              return;
            }

            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(buildAuthResultHtml(true, 'You are signed in! You can close this browser tab and return to LoopSearch.'));

            let session = null;
            if (idToken || accessToken || oauthCode) {
              const postParts = [];
              if (idToken) postParts.push(`id_token=${encodeURIComponent(idToken)}`);
              if (accessToken) postParts.push(`access_token=${encodeURIComponent(accessToken)}`);
              if (oauthCode) postParts.push(`code=${encodeURIComponent(oauthCode)}`);
              postParts.push('providerId=google.com');
              session = await this._exchangeWithIdentityToolkit(postParts.join('&'));
            }
            if (!session && refreshToken) {
              session = await this._exchangeRefreshToken(refreshToken);
            }
            if (!session) {
              throw new Error('Could not complete Google sign-in token exchange.');
            }
            this._session = session;
            this.vault.set('firebaseSession', session);
            this._lastResumeRecordedAt = Date.now();
            await this._recordEventWithFallback('interactive_sign_in');
            await this.flushPendingEvents();
            this._notify();
            finish(null, this.getPublicState());
            return;
          }
          res.writeHead(404);
          res.end();
        } catch (err) {
          finish(err);
        }
      });

      this._activeServer = server;

      const timer = setTimeout(() => {
        finish(new Error('Google sign-in timed out. Please try again.'));
      }, timeoutMs);

      server.on('error', (err) => finish(err));
      server.listen(0, '127.0.0.1', () => {
        const addr = server.address();
        const port = addr && typeof addr === 'object' ? addr.port : null;
        if (!port) {
          finish(new Error('Failed to start local auth callback listener.'));
          return;
        }
        const authUrl = `${FIREBASE_CONFIG.authPageUrl}?port=${port}&state=${expectedState}`;
        Promise.resolve(this.openExternal(authUrl)).catch((err) => finish(err));
      });
    });
  }

  async _exchangeWithIdentityToolkit(postBody) {
    const resp = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${FIREBASE_CONFIG.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          postBody,
          requestUri: FIREBASE_CONFIG.authRequestUri,
          returnIdpCredential: true,
          returnSecureToken: true
        })
      }
    );
    const data = await resp.json();
    if (!resp.ok || !data.localId || !data.idToken) {
      throw new Error(data?.error?.message || `Sign-in exchange failed (${resp.status})`);
    }
    const expiresInSec = Number(data.expiresIn || 3600);
    return {
      uid: data.localId,
      email: data.email || '',
      displayName: data.displayName || data.fullName || '',
      photoURL: data.photoUrl || '',
      idToken: data.idToken,
      refreshToken: data.refreshToken,
      expiresAt: Date.now() + Math.max(60, expiresInSec - 120) * 1000
    };
  }

  async _exchangeRefreshToken(refreshToken) {
    const resp = await fetch(
      `https://securetoken.googleapis.com/v1/token?key=${FIREBASE_CONFIG.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: refreshToken
        }).toString()
      }
    );
    const data = await resp.json();
    if (!resp.ok || !data.id_token || !data.user_id) {
      throw new Error(data?.error?.message || `Refresh token exchange failed (${resp.status})`);
    }
    const expiresInSec = Number(data.expires_in || 3600);
    const session = {
      uid: data.user_id,
      email: '',
      displayName: '',
      photoURL: '',
      idToken: data.id_token,
      refreshToken: data.refresh_token || refreshToken,
      expiresAt: Date.now() + Math.max(60, expiresInSec - 120) * 1000
    };
    this._session = session;
    await this.refreshUserProfile().catch(() => {});
    return this._session;
  }

  async ensureFreshToken() {
    if (!this._session || !this._session.refreshToken) {
      throw new Error('No active session');
    }
    if (this._session.idToken && Date.now() < (this._session.expiresAt || 0)) {
      return this._session.idToken;
    }
    const resp = await fetch(
      `https://securetoken.googleapis.com/v1/token?key=${FIREBASE_CONFIG.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: this._session.refreshToken
        }).toString()
      }
    );
    const data = await resp.json();
    if (!resp.ok || !data.id_token) {
      throw new Error(data?.error?.message || `Token refresh failed (${resp.status})`);
    }
    const expiresInSec = Number(data.expires_in || 3600);
    this._session = {
      ...this._session,
      idToken: data.id_token,
      refreshToken: data.refresh_token || this._session.refreshToken,
      expiresAt: Date.now() + Math.max(60, expiresInSec - 120) * 1000
    };
    this.vault.set('firebaseSession', this._session);
    return this._session.idToken;
  }

  async refreshUserProfile() {
    if (!this._session) return;
    const idToken = await this.ensureFreshToken();
    const resp = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_CONFIG.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken })
      }
    );
    if (!resp.ok) return;
    const data = await resp.json();
    const u = data?.users?.[0];
    if (!u) return;
    this._session = {
      ...this._session,
      email: u.email || this._session.email,
      displayName: u.displayName || this._session.displayName,
      photoURL: u.photoUrl || this._session.photoURL
    };
    this.vault.set('firebaseSession', this._session);
  }

  async _recordEventWithFallback(eventType) {
    if (this.telemetryDisabled || !this._session) return;
    const eventMeta = {
      eventType,
      eventId: crypto.randomUUID(),
      dateKey: getUtcDateKey(),
      appVersion: this.appVersion,
      osVersion: formatOsVersion()
    };
    try {
      await this._commitEvent(eventMeta);
    } catch {
      const pending = this.vault.get('pendingLoginEvents', []);
      const next = [...pending, eventMeta].slice(-MAX_PENDING_EVENTS);
      this.vault.set('pendingLoginEvents', next);
    }
  }

  async flushPendingEvents() {
    if (this.telemetryDisabled || !this._session) return;
    const pending = this.vault.get('pendingLoginEvents', []);
    if (!Array.isArray(pending) || pending.length === 0) return;
    const remaining = [];
    for (const evt of pending) {
      if (!ALLOWED_EVENT_TYPES.has(evt.eventType)) continue;
      try {
        await this._commitEvent(evt);
      } catch {
        remaining.push(evt);
      }
    }
    this.vault.set('pendingLoginEvents', remaining);
  }

  async _commitEvent(eventMeta, allowTokenRetry = true) {
    const endpoint = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/${FIREBASE_CONFIG.databaseId}/documents:commit`;
    const isMissingDoc = (status, text) =>
      status === 404 ||
      text.includes('NOT_FOUND') ||
      text.includes('FAILED_PRECONDITION') ||
      text.includes('no entity to update') ||
      text.includes('stored version');

    const doCommit = (userExists, token) =>
      fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify(
          buildFirestoreCommitWrites({
            session: this._session,
            ...eventMeta,
            userExists
          })
        )
      });

    let token = await this.ensureFreshToken();
    let resp = await doCommit(true, token);
    if (resp.status === 401 && allowTokenRetry) {
      this._session = { ...this._session, expiresAt: 0 };
      token = await this.ensureFreshToken();
      resp = await doCommit(true, token);
    }
    if (resp.ok) return;

    const errText = await resp.text();
    if (!isMissingDoc(resp.status, errText)) {
      throw new Error(`Firestore update commit failed (${resp.status}): ${errText}`);
    }

    resp = await doCommit(false, token);
    if (!resp.ok) {
      throw new Error(`Firestore create commit failed (${resp.status}): ${await resp.text()}`);
    }
  }
}

function buildAuthResultHtml(success, message) {
  const accent = success ? '#38bdf8' : '#f87171';
  const title = success ? 'LoopSearch Connected' : 'Sign-In Incomplete';
  const icon = success ? '✓' : '!';
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${title}</title>
  <style>
    body {
      margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: radial-gradient(circle at 50% 85%, rgba(37,99,235,0.28), #070912 65%);
      color: #f8fafc;
    }
    .card {
      width: 390px; padding: 32px 28px; border-radius: 22px; text-align: center;
      background: rgba(15, 20, 36, 0.88);
      border: 1px solid rgba(255,255,255,0.14);
      box-shadow: 0 24px 60px rgba(0,0,0,0.55);
    }
    .badge {
      width: 48px; height: 48px; margin: 0 auto 16px; border-radius: 14px;
      display: flex; align-items: center; justify-content: center;
      background: rgba(56,189,248,0.14); border: 1px solid ${accent};
      color: ${accent}; font-size: 22px; font-weight: 700;
    }
    h1 { margin: 0 0 8px; font-size: 19px; font-weight: 650; }
    p { margin: 0; font-size: 13.5px; line-height: 1.5; color: rgba(226,232,240,0.78); }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">${icon}</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>`;
}

module.exports = {
  FIREBASE_CONFIG,
  ALLOWED_EVENT_TYPES,
  formatOsVersion,
  getUtcDateKey,
  buildFirestoreCommitWrites,
  FirebaseAuthService
};
