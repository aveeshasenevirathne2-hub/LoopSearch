'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  MAX_HISTORY_ITEMS,
  normalizeHotkeyString,
  toElectronAccelerator,
  formatHotkeyDisplay,
  EncryptedVault,
  SettingsStore
} = require('../src/main/settings');

const {
  ALLOWED_EVENT_TYPES,
  formatOsVersion,
  getUtcDateKey,
  buildFirestoreCommitWrites
} = require('../src/main/firebaseAuth');

const {
  buildMultipartLensBody,
  extractLensResultUrlFromHtml,
  buildLensDarkThemeInjectionScript,
  compareSemver,
  buildFeedbackIssueUrl
} = require('../src/main/lensAndAi');

const {
  extractPrimaryURL,
  displayHostForUrl,
  evaluateMathExpression,
  extractDominantColor,
  analyzeRegionDetail,
  shouldApplyWebDarkCss,
  buildSearchUrl
} = require('../src/shared/visionHelpers');

test('Hotkey normalization and accelerator conversion', () => {
  assert.equal(normalizeHotkeyString('shift+ctrl+space'), 'Ctrl+Shift+Space');
  assert.equal(normalizeHotkeyString('alt + shift + s'), 'Alt+Shift+S');
  assert.equal(normalizeHotkeyString('invalid'), 'Ctrl+Shift+Space');
  assert.equal(toElectronAccelerator('Ctrl+Shift+Space', 'win32'), 'Control+Shift+Space');
  assert.equal(formatHotkeyDisplay('Ctrl+Shift+Space'), 'Ctrl + Shift + Space');
});

test('EncryptedVault and SettingsStore persist settings, masked key, and history cap', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ls-test-'));
  try {
    const store = new SettingsStore(tmpDir, 'test-machine-seed-123');
    const initial = store.load();
    assert.equal(initial.hotkey, 'Ctrl+Shift+Space');
    assert.equal(initial.hasGeminiApiKey, false);

    store.setGeminiApiKey('AIzaSyTestSecretKey123456');
    const updated = store.getPublicSettings();
    assert.equal(updated.hasGeminiApiKey, true);
    assert.equal(updated.maskedGeminiApiKey, 'AIza••••••3456');
    assert.equal(store.getGeminiApiKey(), 'AIzaSyTestSecretKey123456');

    // Vault on disk must not store plain secret
    const rawVault = fs.readFileSync(path.join(tmpDir, 'vault.enc.json'), 'utf8');
    assert.equal(rawVault.includes('AIzaSyTestSecretKey123456'), false);

    for (let i = 0; i < MAX_HISTORY_ITEMS + 5; i++) {
      store.addHistoryItem({ id: `id-${i}`, mode: 'box', query: `q-${i}` });
    }
    const hist = store.getHistory();
    assert.equal(hist.length, MAX_HISTORY_ITEMS);
    assert.equal(hist[0].id, `id-${MAX_HISTORY_ITEMS + 4}`);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('Firebase Firestore commit payload matches firestore.rules schema strictly', () => {
  assert.equal(formatOsVersion('win32', '10.0.22631'), 'Windows 11 (10.0.22631)');
  assert.equal(formatOsVersion('win32', '10.0.19045'), 'Windows 10 (10.0.19045)');
  assert.equal(getUtcDateKey(new Date('2026-11-15T10:00:00Z')), '2026-11-15');

  const session = {
    uid: 'uid_abc123',
    email: 'tester@example.com',
    displayName: 'Test User',
    photoURL: 'https://example.com/p.png'
  };

  assert.equal(ALLOWED_EVENT_TYPES.has('interactive_sign_in'), true);
  assert.equal(ALLOWED_EVENT_TYPES.has('session_resume'), true);
  assert.equal(ALLOWED_EVENT_TYPES.has('app_launch'), false);

  assert.throws(() =>
    buildFirestoreCommitWrites({
      session,
      eventType: 'app_launch',
      eventId: 'evt-1',
      dateKey: '2026-11-15',
      appVersion: '1.0.3',
      osVersion: 'Windows 11 (10.0.22631)',
      userExists: false
    })
  );

  const createCommit = buildFirestoreCommitWrites({
    session,
    eventType: 'interactive_sign_in',
    eventId: 'evt-1',
    dateKey: '2026-11-15',
    appVersion: '1.0.3',
    osVersion: 'Windows 11 (10.0.22631)',
    userExists: false
  });
  assert.equal(createCommit.writes.length, 2);
  assert.deepEqual(
    Object.keys(createCommit.writes[0].update.fields).concat(
      createCommit.writes[0].updateTransforms.map((t) => t.fieldPath)
    ).sort(),
    [
      'appVersion',
      'displayName',
      'email',
      'firstSeenAt',
      'lastDateKey',
      'lastEventType',
      'lastLoginAt',
      'lastSeenAt',
      'loginCount',
      'osVersion',
      'photoURL',
      'uid'
    ].sort()
  );
  assert.equal(createCommit.writes[0].currentDocument.exists, false);

  const resumeCommit = buildFirestoreCommitWrites({
    session,
    eventType: 'session_resume',
    eventId: 'evt-2',
    dateKey: '2026-11-15',
    appVersion: '1.0.3',
    osVersion: 'Windows 11 (10.0.22631)',
    userExists: true
  });
  assert.equal(resumeCommit.writes[0].currentDocument.exists, true);
  assert.equal(resumeCommit.writes[1].update.fields.eventType.stringValue, 'session_resume');
  assert.equal(resumeCommit.writes[1].updateTransforms[0].fieldPath, 'createdAt');
});

test('Vision helpers extract URLs, solve math cleanly, find color & low-info surfaces, and skip /sorry CSS', () => {
  assert.equal(extractPrimaryURL('Visit https://github.com/aveeshasenevirathne2-hub/LoopSearch.'), 'https://github.com/aveeshasenevirathne2-hub/LoopSearch');
  assert.equal(displayHostForUrl('https://www.google.com/search?q=hi'), 'google.com');

  assert.equal(evaluateMathExpression('128 + 256 = ?').formatted, '384');
  assert.equal(evaluateMathExpression('12 × (4 + 6)').formatted, '120');
  assert.equal(evaluateMathExpression('10 / 0'), null);
  assert.equal(evaluateMathExpression('2026-11-15'), null);

  // Solid uniform 8x8 color (#38BDF8) -> lowInfo=true & hex=#38BDF8
  const solid = new Uint8ClampedArray(8 * 8 * 4);
  for (let i = 0; i < 64; i++) {
    solid[i * 4] = 0x38;
    solid[i * 4 + 1] = 0xbd;
    solid[i * 4 + 2] = 0xf8;
    solid[i * 4 + 3] = 255;
  }
  assert.equal(extractDominantColor(solid, 8, 8).hex, '#38BDF8');
  assert.equal(analyzeRegionDetail(solid, 8, 8).isLowInfo, true);

  assert.equal(shouldApplyWebDarkCss('https://lens.google.com/search?p=123'), true);
  assert.equal(shouldApplyWebDarkCss('https://www.google.com/sorry/index?continue=https://...'), false);
  assert.equal(shouldApplyWebDarkCss('https://accounts.google.com/v3/signin'), false);
  assert.equal(buildSearchUrl('aiExplain', 'quantum'), 'https://www.google.com/search?udm=50&q=Explain%20this%20clearly%20and%20concisely%3A%20quantum');
});

test('Lens & GitHub helper functions', () => {
  const { boundary, body } = buildMultipartLensBody(Buffer.from([1, 2, 3]));
  assert.ok(body.toString('utf8').includes(boundary));
  assert.ok(body.toString('utf8').includes('name="encoded_image"; filename="search.jpg"'));

  const html = '<meta http-equiv="refresh" content="0;url=https://lens.google.com/search?ep=ccm&p=abc">';
  assert.equal(extractLensResultUrlFromHtml(html), 'https://lens.google.com/search?ep=ccm&p=abc');

  const script = buildLensDarkThemeInjectionScript(true);
  assert.ok(script.includes("u.includes('/sorry')"));
  assert.equal(compareSemver('1.0.4', '1.0.3'), 1);
  assert.equal(compareSemver('1.0.3', '1.0.3'), 0);

  const issueUrl = buildFeedbackIssueUrl({
    rating: 5,
    category: 'UI / Animation',
    notes: 'Super smooth!',
    appVersion: '1.0.3',
    osVersion: 'Windows 11'
  });
  assert.ok(issueUrl.startsWith('https://github.com/aveeshasenevirathne2-hub/LoopSearch/issues/new?'));
});
