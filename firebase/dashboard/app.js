import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signOut,
  onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  getFirestore,
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
  doc,
  getDoc,
  getDocFromCache,
  collection,
  query,
  orderBy,
  limit,
  getDocs,
  onSnapshot
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";

const state = {
  app: null,
  auth: null,
  db: null,
  currentUser: null,
  isAdmin: false,
  liveEnabled: true,
  rangeDays: 14,
  eventTypeFilter: "all",
  searchQuery: "",
  sortBy: "lastLoginAt",
  users: [],
  loginEvents: [],
  unsubUsers: null,
  unsubEvents: null
};

const els = {
  authGate: document.getElementById("auth-gate"),
  authLoading: document.getElementById("auth-loading"),
  authSignin: document.getElementById("auth-signin"),
  authDenied: document.getElementById("auth-denied"),
  authError: document.getElementById("auth-error"),
  deniedEmail: document.getElementById("denied-email"),
  deniedUid: document.getElementById("denied-uid"),
  btnGoogleSignin: document.getElementById("btn-google-signin"),
  btnCopyUid: document.getElementById("btn-copy-uid"),
  btnRecheckAdmin: document.getElementById("btn-recheck-admin"),
  btnDeniedSignout: document.getElementById("btn-denied-signout"),

  dashboardShell: document.getElementById("dashboard-shell"),
  syncSubtitle: document.getElementById("sync-subtitle"),
  rangeSelector: document.getElementById("range-selector"),
  eventTypeFilter: document.getElementById("event-type-filter"),
  btnLiveToggle: document.getElementById("btn-live-toggle"),
  liveLabel: document.getElementById("live-label"),
  btnExportCsv: document.getElementById("btn-export-csv"),
  adminAvatar: document.getElementById("admin-avatar"),
  adminInitials: document.getElementById("admin-initials"),
  adminName: document.getElementById("admin-name"),
  btnSignout: document.getElementById("btn-signout"),

  kpiTotalUsers: document.getElementById("kpi-total-users"),
  kpiTotalUsersSub: document.getElementById("kpi-total-users-sub"),
  kpiTotalLogins: document.getElementById("kpi-total-logins"),
  kpiTotalLoginsSub: document.getElementById("kpi-total-logins-sub"),
  kpiDau: document.getElementById("kpi-dau"),
  kpiDauSub: document.getElementById("kpi-dau-sub"),
  kpiWau: document.getElementById("kpi-wau"),
  kpiWauSub: document.getElementById("kpi-wau-sub"),
  kpiMau: document.getElementById("kpi-mau"),
  kpiMauSub: document.getElementById("kpi-mau-sub"),
  kpiNew7d: document.getElementById("kpi-new-7d"),
  kpiNew7dSub: document.getElementById("kpi-new-7d-sub"),

  trendChart: document.getElementById("trend-chart"),
  chartTooltip: document.getElementById("chart-tooltip"),
  breakdownContent: document.getElementById("breakdown-content"),
  directoryCount: document.getElementById("directory-count"),
  userSearch: document.getElementById("user-search"),
  userSort: document.getElementById("user-sort"),
  usersTbody: document.getElementById("users-tbody"),
  activityFeed: document.getElementById("activity-feed"),

  userModal: document.getElementById("user-modal"),
  btnCloseModal: document.getElementById("btn-close-modal"),
  modalAvatar: document.getElementById("modal-avatar"),
  modalInitials: document.getElementById("modal-initials"),
  modalUserName: document.getElementById("modal-user-name"),
  modalUserEmail: document.getElementById("modal-user-email"),
  modalMeta: document.getElementById("modal-meta"),
  modalEvents: document.getElementById("modal-events")
};

const OFFLINE_CONFIG_KEY = "loopsearch_analytics_runtime_cfg_v1";
const OFFLINE_SNAPSHOT_PREFIX = "loopsearch_analytics_snapshot_v1_";

function snapshotKey(uid) {
  return `${OFFLINE_SNAPSHOT_PREFIX}${uid}`;
}

function serializeSnapshotItem(item) {
  const copy = { ...item };
  for (const key of Object.keys(copy)) {
    if (copy[key] instanceof Date) {
      copy[key] = copy[key].toISOString();
    }
  }
  return copy;
}

function hydrateSnapshotItem(item) {
  const copy = { ...item };
  for (const field of ["firstSeenAt", "lastSeenAt", "lastLoginAt", "createdAt"]) {
    if (copy[field]) {
      const parsed = new Date(copy[field]);
      copy[field] = Number.isNaN(parsed.getTime()) ? null : parsed;
    }
  }
  return copy;
}

function saveOfflineSnapshot(uid, users, loginEvents) {
  if (!uid) return;
  try {
    const payload = {
      savedAt: new Date().toISOString(),
      users: users.map(serializeSnapshotItem),
      loginEvents: loginEvents.map(serializeSnapshotItem)
    };
    localStorage.setItem(snapshotKey(uid), JSON.stringify(payload));
  } catch {
    // Ignore storage quota issues.
  }
}

function loadOfflineSnapshot(uid) {
  if (!uid) return null;
  try {
    const raw = localStorage.getItem(snapshotKey(uid));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return {
      savedAt: parsed.savedAt ? new Date(parsed.savedAt) : null,
      users: Array.isArray(parsed.users) ? parsed.users.map(hydrateSnapshotItem) : [],
      loginEvents: Array.isArray(parsed.loginEvents) ? parsed.loginEvents.map(hydrateSnapshotItem) : []
    };
  } catch {
    return null;
  }
}

function clearOfflineSnapshot(uid) {
  if (!uid) return;
  try {
    localStorage.removeItem(snapshotKey(uid));
  } catch {
    // Ignore storage access errors.
  }
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

async function loadRuntimeConfig() {
  try {
    const mod = await import("./firebase-config.js");
    if (mod.firebaseConfig?.apiKey && !String(mod.firebaseConfig.apiKey).startsWith("YOUR_")) {
      const cfg = {
        firebaseConfig: mod.firebaseConfig,
        databaseId: mod.firestoreDatabaseId || "(default)"
      };
      try {
        localStorage.setItem(OFFLINE_CONFIG_KEY, JSON.stringify(cfg));
      } catch {}
      return cfg;
    }
  } catch {
    // Fallback to Firebase Hosting auto-config below.
  }

  try {
    const resp = await fetch("/__/firebase/init.json");
    if (resp.ok) {
      const firebaseConfig = await resp.json();
      const cfg = { firebaseConfig, databaseId: "(default)" };
      try {
        localStorage.setItem(OFFLINE_CONFIG_KEY, JSON.stringify(cfg));
      } catch {}
      return cfg;
    }
  } catch {
    // Fallback to cached runtime config when offline.
  }

  try {
    const cached = localStorage.getItem(OFFLINE_CONFIG_KEY);
    if (cached) {
      return JSON.parse(cached);
    }
  } catch {}

  throw new Error("Missing firebase-config.js and /__/firebase/init.json.");
}

function createPersistentFirestore(app, databaseId) {
  const dbName = databaseId && databaseId !== "(default)" ? databaseId : undefined;
  try {
    return initializeFirestore(
      app,
      { localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }) },
      dbName
    );
  } catch {
    return dbName ? getFirestore(app, dbName) : getFirestore(app);
  }
}

async function bootstrap() {
  registerServiceWorker();
  bindUIEvents();
  try {
    const { firebaseConfig, databaseId } = await loadRuntimeConfig();
    state.app = initializeApp(firebaseConfig);
    state.auth = getAuth(state.app);
    state.db = createPersistentFirestore(state.app, databaseId);

    onAuthStateChanged(state.auth, handleAuthChange);
  } catch (err) {
    showAuthPanel("signin");
    showAuthError(err?.message || "Failed to initialize Firebase.");
  }
}

function bindUIEvents() {
  els.btnGoogleSignin.addEventListener("click", handleGoogleSignIn);
  els.btnSignout.addEventListener("click", handleSignOut);
  els.btnDeniedSignout.addEventListener("click", handleSignOut);

  els.btnRecheckAdmin.addEventListener("click", () => {
    if (state.currentUser) {
      verifyAdminAndLoad(state.currentUser);
    }
  });

  els.btnCopyUid.addEventListener("click", async () => {
    const uid = els.deniedUid.textContent || "";
    if (!uid || uid === "—") return;
    await navigator.clipboard.writeText(uid);
    els.btnCopyUid.textContent = "Copied!";
    setTimeout(() => {
      els.btnCopyUid.textContent = "Copy UID";
    }, 1400);
  });

  els.rangeSelector.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-days]");
    if (!btn) return;
    const days = Number(btn.dataset.days);
    if (!Number.isFinite(days)) return;
    state.rangeDays = days;
    els.rangeSelector.querySelectorAll(".pill").forEach((pill) => {
      pill.classList.toggle("active", Number(pill.dataset.days) === days);
    });
    renderDashboard();
  });

  els.eventTypeFilter.addEventListener("change", () => {
    state.eventTypeFilter = els.eventTypeFilter.value;
    renderDashboard();
  });

  els.btnLiveToggle.addEventListener("click", () => {
    state.liveEnabled = !state.liveEnabled;
    els.btnLiveToggle.classList.toggle("live-on", state.liveEnabled);
    els.liveLabel.textContent = state.liveEnabled ? "Live" : "Paused";
    if (state.isAdmin) {
      startDataSubscriptions();
    }
  });

  els.userSearch.addEventListener("input", () => {
    state.searchQuery = els.userSearch.value.trim().toLowerCase();
    renderUserDirectory();
  });

  els.userSort.addEventListener("change", () => {
    state.sortBy = els.userSort.value;
    renderUserDirectory();
  });

  els.btnExportCsv.addEventListener("click", exportUsersCsv);
  els.btnCloseModal.addEventListener("click", closeUserModal);
  els.userModal.addEventListener("click", (e) => {
    if (e.target === els.userModal) closeUserModal();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !els.userModal.classList.contains("hidden")) {
      closeUserModal();
    }
  });
}

async function handleGoogleSignIn() {
  clearAuthError();
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: "select_account" });
  try {
    await signInWithPopup(state.auth, provider);
  } catch (err) {
    if (err?.code === "auth/popup-closed-by-user") return;
    if (err?.code === "auth/unauthorized-domain") {
      showAuthError("Domain not authorized in Firebase Auth settings. Add this hostname (without http:// or port) under Authentication > Settings > Authorized domains.");
      return;
    }
    showAuthError(err?.message || "Google sign-in failed.");
  }
}

async function handleSignOut() {
  const prevUid = state.currentUser?.uid;
  stopDataSubscriptions();
  clearOfflineSnapshot(prevUid);
  state.isAdmin = false;
  state.users = [];
  state.loginEvents = [];
  await signOut(state.auth);
}

async function handleAuthChange(user) {
  state.currentUser = user;
  if (!user) {
    stopDataSubscriptions();
    state.isAdmin = false;
    els.dashboardShell.classList.add("hidden");
    els.authGate.classList.remove("hidden");
    showAuthPanel("signin");
    return;
  }

  await verifyAdminAndLoad(user);
}

async function verifyAdminAndLoad(user) {
  showAuthPanel("loading");
  clearAuthError();
  try {
    const adminRef = doc(state.db, "admins", user.uid);
    let adminSnap;
    try {
      adminSnap = navigator.onLine ? await getDoc(adminRef) : await getDocFromCache(adminRef);
    } catch {
      adminSnap = await getDocFromCache(adminRef);
    }
    const allowed = adminSnap.exists() && adminSnap.data()?.active === true;
    state.isAdmin = allowed;

    if (!allowed) {
      stopDataSubscriptions();
      els.dashboardShell.classList.add("hidden");
      els.authGate.classList.remove("hidden");
      els.deniedEmail.textContent = user.email || "(no email claim)";
      els.deniedUid.textContent = user.uid;
      showAuthPanel("denied");
      return;
    }

    renderAdminChip(user);
    const cached = loadOfflineSnapshot(user.uid);
    if (cached) {
      state.users = cached.users;
      state.loginEvents = cached.loginEvents;
      renderDashboard();
      if (!navigator.onLine && cached.savedAt) {
        els.syncSubtitle.textContent = `Offline • Saved locally (${cached.savedAt.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })})`;
      }
    }
    els.authGate.classList.add("hidden");
    els.dashboardShell.classList.remove("hidden");
    startDataSubscriptions();
  } catch (err) {
    stopDataSubscriptions();
    showAuthPanel("signin");
    showAuthError(err?.message || "Could not verify admin privileges in Firestore.");
  }
}

function showAuthPanel(panelName) {
  els.authLoading.classList.toggle("hidden", panelName !== "loading");
  els.authSignin.classList.toggle("hidden", panelName !== "signin");
  els.authDenied.classList.toggle("hidden", panelName !== "denied");
}

function showAuthError(message) {
  els.authError.textContent = message;
  els.authError.classList.remove("hidden");
}

function clearAuthError() {
  els.authError.textContent = "";
  els.authError.classList.add("hidden");
}

function renderAdminChip(user) {
  els.adminName.textContent = user.displayName || user.email || "Admin";
  setAvatar(els.adminAvatar, els.adminInitials, user.photoURL, user.displayName || user.email || "A");
}

function stopDataSubscriptions() {
  if (state.unsubUsers) {
    state.unsubUsers();
    state.unsubUsers = null;
  }
  if (state.unsubEvents) {
    state.unsubEvents();
    state.unsubEvents = null;
  }
}

function startDataSubscriptions() {
  stopDataSubscriptions();
  const usersQuery = query(collection(state.db, "users"), orderBy("lastLoginAt", "desc"));
  const eventsQuery = query(collection(state.db, "loginEvents"), orderBy("createdAt", "desc"), limit(500));

  if (state.liveEnabled) {
    els.syncSubtitle.textContent = navigator.onLine
      ? "Live Firestore sync active"
      : "Offline • Showing saved local data";
    state.unsubUsers = onSnapshot(
      usersQuery,
      (snap) => {
        state.users = snap.docs.map((d) => normalizeUserDoc(d.id, d.data()));
        saveOfflineSnapshot(state.currentUser?.uid, state.users, state.loginEvents);
        updateSyncTimestamp(snap.metadata?.fromCache);
        renderDashboard();
      },
      (err) => {
        els.syncSubtitle.textContent = navigator.onLine
          ? `Users listener error: ${err.message}`
          : "Offline • Showing saved local data";
      }
    );

    state.unsubEvents = onSnapshot(
      eventsQuery,
      (snap) => {
        state.loginEvents = snap.docs.map((d) => normalizeEventDoc(d.id, d.data()));
        saveOfflineSnapshot(state.currentUser?.uid, state.users, state.loginEvents);
        updateSyncTimestamp(snap.metadata?.fromCache);
        renderDashboard();
      },
      (err) => {
        els.syncSubtitle.textContent = navigator.onLine
          ? `Events listener error: ${err.message}`
          : "Offline • Showing saved local data";
      }
    );
    return;
  }

  Promise.all([getDocs(usersQuery), getDocs(eventsQuery)])
    .then(([uSnap, eSnap]) => {
      state.users = uSnap.docs.map((d) => normalizeUserDoc(d.id, d.data()));
      state.loginEvents = eSnap.docs.map((d) => normalizeEventDoc(d.id, d.data()));
      saveOfflineSnapshot(state.currentUser?.uid, state.users, state.loginEvents);
      updateSyncTimestamp(uSnap.metadata?.fromCache || eSnap.metadata?.fromCache);
      renderDashboard();
    })
    .catch((err) => {
      els.syncSubtitle.textContent = navigator.onLine
        ? `Load error: ${err.message}`
        : "Offline • Showing saved local data";
    });
}

function updateSyncTimestamp(fromCache = false) {
  if (!navigator.onLine) {
    els.syncSubtitle.textContent = "Offline • Showing saved local data";
    return;
  }
  const mode = fromCache ? "Saved cache" : (state.liveEnabled ? "Live sync" : "Snapshot");
  const nowStr = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  els.syncSubtitle.textContent = `${mode} • Updated ${nowStr}`;
}

window.addEventListener("offline", () => {
  if (state.isAdmin) {
    els.syncSubtitle.textContent = "Offline • Showing saved local data";
  }
});

window.addEventListener("online", () => {
  if (state.isAdmin) {
    startDataSubscriptions();
  }
});

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeUserDoc(id, data) {
  return {
    uid: data.uid || id,
    email: data.email || "",
    displayName: data.displayName || "",
    photoURL: data.photoURL || "",
    firstSeenAt: toDate(data.firstSeenAt),
    lastSeenAt: toDate(data.lastSeenAt),
    lastLoginAt: toDate(data.lastLoginAt),
    lastDateKey: data.lastDateKey || "",
    loginCount: Number(data.loginCount) || 0,
    appVersion: data.appVersion || "Unknown",
    osVersion: data.osVersion || "macOS",
    lastEventType: data.lastEventType || "interactive_sign_in"
  };
}

function normalizeEventDoc(id, data) {
  const createdAt = toDate(data.createdAt);
  return {
    id,
    uid: data.uid || "",
    email: data.email || "",
    displayName: data.displayName || "",
    photoURL: data.photoURL || "",
    createdAt,
    dateKey: data.dateKey || (createdAt ? utcDateKey(createdAt) : ""),
    appVersion: data.appVersion || "Unknown",
    osVersion: data.osVersion || "macOS",
    eventType: data.eventType || "interactive_sign_in"
  };
}

function utcDateKey(date) {
  return date.toISOString().slice(0, 10);
}

function getFilteredEvents() {
  if (state.eventTypeFilter === "all") return state.loginEvents;
  return state.loginEvents.filter((ev) => ev.eventType === state.eventTypeFilter);
}

function renderDashboard() {
  renderKpis();
  renderTrendChart();
  renderBreakdowns();
  renderUserDirectory();
  renderActivityFeed();
}

function renderKpis() {
  const now = new Date();
  const todayKey = utcDateKey(now);
  const msDay = 86_400_000;
  const cutoff7d = now.getTime() - 7 * msDay;
  const cutoff30d = now.getTime() - 30 * msDay;
  const filteredEvents = getFilteredEvents();

  const totalUsers = state.users.length;
  const totalUserLogins = state.users.reduce((acc, u) => acc + u.loginCount, 0);
  const newToday = state.users.filter((u) => u.firstSeenAt && utcDateKey(u.firstSeenAt) === todayKey).length;
  const new7d = state.users.filter((u) => u.firstSeenAt && u.firstSeenAt.getTime() >= cutoff7d).length;

  const dauUids = new Set();
  const wauUids = new Set();
  const mauUids = new Set();

  for (const ev of filteredEvents) {
    if (!ev.uid) continue;
    const t = ev.createdAt?.getTime();
    if (ev.dateKey === todayKey) dauUids.add(ev.uid);
    if (t && t >= cutoff7d) wauUids.add(ev.uid);
    if (t && t >= cutoff30d) mauUids.add(ev.uid);
  }

  // Fallback to users.lastLoginAt for active users in case events exceed 500 recent limit
  if (state.eventTypeFilter === "all") {
    for (const u of state.users) {
      const t = u.lastLoginAt?.getTime();
      if (!t) continue;
      if (u.lastDateKey === todayKey) dauUids.add(u.uid);
      if (t >= cutoff7d) wauUids.add(u.uid);
      if (t >= cutoff30d) mauUids.add(u.uid);
    }
  }

  const avgLogins = totalUsers > 0 ? (totalUserLogins / totalUsers).toFixed(1) : "0.0";
  const dauPct = totalUsers > 0 ? Math.round((dauUids.size / totalUsers) * 100) : 0;

  els.kpiTotalUsers.textContent = formatNumber(totalUsers);
  els.kpiTotalUsersSub.textContent = `+${newToday} joined today`;

  if (state.eventTypeFilter === "all") {
    els.kpiTotalLogins.textContent = formatNumber(totalUserLogins);
    els.kpiTotalLoginsSub.textContent = `${avgLogins} avg per user`;
  } else {
    els.kpiTotalLogins.textContent = formatNumber(filteredEvents.length);
    els.kpiTotalLoginsSub.textContent = `From latest 500 events`;
  }

  els.kpiDau.textContent = formatNumber(dauUids.size);
  els.kpiDauSub.textContent = `${dauPct}% of registered users`;

  els.kpiWau.textContent = formatNumber(wauUids.size);
  els.kpiWauSub.textContent = `${totalUsers > 0 ? Math.round((wauUids.size / totalUsers) * 100) : 0}% 7d reach`;

  els.kpiMau.textContent = formatNumber(mauUids.size);
  els.kpiMauSub.textContent = `${totalUsers > 0 ? Math.round((mauUids.size / totalUsers) * 100) : 0}% 30d reach`;

  els.kpiNew7d.textContent = formatNumber(new7d);
  els.kpiNew7dSub.textContent = "Joined in past 7 days";
}

function buildDailySeries(days) {
  const buckets = [];
  const map = new Map();
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);

  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today.getTime() - i * 86_400_000);
    const key = utcDateKey(d);
    const entry = {
      key,
      label: d.toLocaleDateString(undefined, { month: "short", day: "numeric", timeZone: "UTC" }),
      events: 0,
      uniqueUids: new Set(),
      signups: 0
    };
    buckets.push(entry);
    map.set(key, entry);
  }

  for (const ev of getFilteredEvents()) {
    const b = map.get(ev.dateKey);
    if (!b) continue;
    b.events += 1;
    if (ev.uid) b.uniqueUids.add(ev.uid);
  }

  for (const u of state.users) {
    if (!u.firstSeenAt) continue;
    const b = map.get(utcDateKey(u.firstSeenAt));
    if (b) b.signups += 1;
  }

  return buckets.map((b) => ({
    key: b.key,
    label: b.label,
    events: b.events,
    dau: b.uniqueUids.size,
    signups: b.signups
  }));
}

function renderTrendChart() {
  const svg = els.trendChart;
  svg.replaceChildren();

  const data = buildDailySeries(state.rangeDays);
  const w = 820;
  const h = 260;
  const pad = { top: 18, right: 18, bottom: 32, left: 38 };
  const plotW = w - pad.left - pad.right;
  const plotH = h - pad.top - pad.bottom;

  const maxVal = Math.max(
    4,
    ...data.map((d) => Math.max(d.events, d.dau, d.signups))
  );

  const ns = "http://www.w3.org/2000/svg";
  const el = (tag, attrs = {}) => {
    const node = document.createElementNS(ns, tag);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
    return node;
  };

  // Gradient definitions
  const defs = el("defs");
  const barGrad = el("linearGradient", { id: "barGrad", x1: "0", y1: "0", x2: "0", y2: "1" });
  barGrad.appendChild(el("stop", { offset: "0%", "stop-color": "#38bdf8", "stop-opacity": "0.52" }));
  barGrad.appendChild(el("stop", { offset: "100%", "stop-color": "#2563eb", "stop-opacity": "0.08" }));
  defs.appendChild(barGrad);
  svg.appendChild(defs);

  // Horizontal grid lines
  const gridSteps = 4;
  for (let i = 0; i <= gridSteps; i++) {
    const ratio = i / gridSteps;
    const y = pad.top + plotH - ratio * plotH;
    svg.appendChild(el("line", {
      x1: pad.left,
      y1: y,
      x2: w - pad.right,
      y2: y,
      stroke: "rgba(148, 163, 184, 0.14)",
      "stroke-width": 1
    }));
    const tick = el("text", {
      x: pad.left - 8,
      y: y + 4,
      "text-anchor": "end",
      fill: "#7c91b5",
      "font-size": 10.5
    });
    tick.textContent = String(Math.round(ratio * maxVal));
    svg.appendChild(tick);
  }

  const slotW = plotW / data.length;
  const barW = Math.max(4, Math.min(26, slotW * 0.56));
  const dauPoints = [];
  const signupPoints = [];
  const labelStride = data.length > 35 ? 10 : data.length > 18 ? 4 : 2;

  data.forEach((d, idx) => {
    const cx = pad.left + slotW * idx + slotW / 2;
    const barH = (d.events / maxVal) * plotH;
    const barY = pad.top + plotH - barH;

    svg.appendChild(el("rect", {
      x: cx - barW / 2,
      y: barY,
      width: barW,
      height: Math.max(1, barH),
      rx: Math.min(4, barW / 2),
      fill: "url(#barGrad)",
      stroke: "rgba(56, 189, 248, 0.35)",
      "stroke-width": 0.75
    }));

    const dauY = pad.top + plotH - (d.dau / maxVal) * plotH;
    const sigY = pad.top + plotH - (d.signups / maxVal) * plotH;
    dauPoints.push(`${cx.toFixed(1)},${dauY.toFixed(1)}`);
    signupPoints.push(`${cx.toFixed(1)},${sigY.toFixed(1)}`);

    if (idx % labelStride === 0 || idx === data.length - 1) {
      const lbl = el("text", {
        x: cx,
        y: h - 10,
        "text-anchor": "middle",
        fill: "#7c91b5",
        "font-size": 10.5
      });
      lbl.textContent = d.label;
      svg.appendChild(lbl);
    }
  });

  if (dauPoints.length > 1) {
    svg.appendChild(el("polyline", {
      points: dauPoints.join(" "),
      fill: "none",
      stroke: "#38bdf8",
      "stroke-width": 2.4,
      "stroke-linecap": "round",
      "stroke-linejoin": "round"
    }));
    svg.appendChild(el("polyline", {
      points: signupPoints.join(" "),
      fill: "none",
      stroke: "#34d399",
      "stroke-width": 2,
      "stroke-dasharray": "4 3",
      "stroke-linecap": "round",
      "stroke-linejoin": "round"
    }));
  }

  // Hover hit zones
  data.forEach((d, idx) => {
    const cx = pad.left + slotW * idx + slotW / 2;
    const hit = el("rect", {
      x: pad.left + slotW * idx,
      y: pad.top,
      width: slotW,
      height: plotH,
      fill: "transparent"
    });
    hit.addEventListener("mouseenter", () => {
      const pctX = (cx / w) * 100;
      els.chartTooltip.innerHTML = "";
      const title = document.createElement("strong");
      title.textContent = `${d.label} (${d.key})`;
      const line1 = document.createElement("div");
      line1.textContent = `Events: ${d.events}`;
      const line2 = document.createElement("div");
      line2.textContent = `Unique Users: ${d.dau}`;
      const line3 = document.createElement("div");
      line3.textContent = `New Users: ${d.signups}`;
      els.chartTooltip.append(title, line1, line2, line3);
      els.chartTooltip.style.left = `${Math.min(82, Math.max(8, pctX))}%`;
      els.chartTooltip.style.top = "10px";
      els.chartTooltip.classList.remove("hidden");
    });
    hit.addEventListener("mouseleave", () => {
      els.chartTooltip.classList.add("hidden");
    });
    svg.appendChild(hit);
  });
}

function renderBreakdowns() {
  els.breakdownContent.replaceChildren();
  if (state.users.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted small";
    empty.textContent = "No signed-in users recorded yet.";
    els.breakdownContent.appendChild(empty);
    return;
  }

  const osCounts = countBy(state.users, (u) => u.osVersion || "macOS");
  const verCounts = countBy(state.users, (u) => `v${u.appVersion || "Unknown"}`);
  const flowCounts = countBy(state.loginEvents, (e) =>
    e.eventType === "interactive_sign_in" ? "Interactive Google Sign-In" : "App Launch Session Resume"
  );

  els.breakdownContent.appendChild(makeBreakdownSection("macOS Versions (Users)", osCounts, state.users.length));
  els.breakdownContent.appendChild(makeBreakdownSection("LoopSearch Builds (Users)", verCounts, state.users.length));
  if (state.loginEvents.length > 0) {
    els.breakdownContent.appendChild(makeBreakdownSection("Auth Event Mix (Recent 500)", flowCounts, state.loginEvents.length));
  }
}

function countBy(items, keyFn) {
  const map = new Map();
  for (const item of items) {
    const key = keyFn(item);
    map.set(key, (map.get(key) || 0) + 1);
  }
  return Array.from(map.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);
}

function makeBreakdownSection(title, entries, total) {
  const wrap = document.createElement("div");
  const heading = document.createElement("h4");
  heading.className = "breakdown-group-title";
  heading.textContent = title;
  wrap.appendChild(heading);

  entries.forEach(([label, count]) => {
    const pct = total > 0 ? Math.round((count / total) * 100) : 0;
    const row = document.createElement("div");
    row.className = "bar-row";

    const top = document.createElement("div");
    top.className = "bar-label-line";
    const nameSpan = document.createElement("span");
    nameSpan.textContent = label;
    const valSpan = document.createElement("span");
    valSpan.className = "muted";
    valSpan.textContent = `${count} (${pct}%)`;
    top.append(nameSpan, valSpan);

    const track = document.createElement("div");
    track.className = "bar-track";
    const fill = document.createElement("div");
    fill.className = "bar-fill";
    fill.style.width = `${Math.max(4, pct)}%`;
    track.appendChild(fill);

    row.append(top, track);
    wrap.appendChild(row);
  });
  return wrap;
}

function getFilteredSortedUsers() {
  const q = state.searchQuery;
  const filtered = state.users.filter((u) => {
    if (!q) return true;
    return [u.displayName, u.email, u.uid, u.osVersion, u.appVersion]
      .some((v) => String(v || "").toLowerCase().includes(q));
  });

  filtered.sort((a, b) => {
    if (state.sortBy === "loginCount") return b.loginCount - a.loginCount;
    if (state.sortBy === "firstSeenAt") return (b.firstSeenAt?.getTime() || 0) - (a.firstSeenAt?.getTime() || 0);
    if (state.sortBy === "name") return (a.displayName || a.email).localeCompare(b.displayName || b.email);
    return (b.lastLoginAt?.getTime() || 0) - (a.lastLoginAt?.getTime() || 0);
  });

  return filtered;
}

function renderUserDirectory() {
  const users = getFilteredSortedUsers();
  els.directoryCount.textContent = String(users.length);
  els.usersTbody.replaceChildren();

  if (users.length === 0) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 6;
    td.className = "empty-cell";
    td.textContent = state.users.length === 0
      ? "No users have signed into LoopSearch yet."
      : "No users match your search filter.";
    tr.appendChild(td);
    els.usersTbody.appendChild(tr);
    return;
  }

  users.forEach((u) => {
    const tr = document.createElement("tr");
    tr.addEventListener("click", () => openUserModal(u));

    // User cell
    const tdUser = document.createElement("td");
    const cellWrap = document.createElement("div");
    cellWrap.className = "user-cell";
    const img = document.createElement("img");
    img.className = "avatar-sm hidden";
    img.alt = "";
    const fallback = document.createElement("div");
    fallback.className = "avatar-fallback sm";
    setAvatar(img, fallback, u.photoURL, u.displayName || u.email || "U");

    const info = document.createElement("div");
    const nameEl = document.createElement("div");
    nameEl.className = "user-name";
    nameEl.textContent = u.displayName || "Google User";
    const emailEl = document.createElement("div");
    emailEl.className = "user-email";
    emailEl.textContent = u.email || u.uid;
    info.append(nameEl, emailEl);

    cellWrap.append(img, fallback, info);
    tdUser.appendChild(cellWrap);

    // Logins
    const tdLogins = document.createElement("td");
    const strong = document.createElement("strong");
    strong.textContent = formatNumber(u.loginCount);
    tdLogins.appendChild(strong);

    // First Seen
    const tdFirst = document.createElement("td");
    tdFirst.textContent = formatDateShort(u.firstSeenAt);
    tdFirst.title = u.firstSeenAt ? u.firstSeenAt.toLocaleString() : "";

    // Last Login
    const tdLast = document.createElement("td");
    tdLast.textContent = formatRelative(u.lastLoginAt);
    tdLast.title = u.lastLoginAt ? u.lastLoginAt.toLocaleString() : "";

    // App / macOS
    const tdEnv = document.createElement("td");
    tdEnv.textContent = `v${u.appVersion} • ${u.osVersion}`;

    // Status
    const tdStatus = document.createElement("td");
    const badge = document.createElement("span");
    const isInteractive = u.lastEventType === "interactive_sign_in";
    badge.className = `badge ${isInteractive ? "badge-interactive" : "badge-resume"}`;
    badge.textContent = isInteractive ? "Sign-In" : "Launch";
    tdStatus.appendChild(badge);

    tr.append(tdUser, tdLogins, tdFirst, tdLast, tdEnv, tdStatus);
    els.usersTbody.appendChild(tr);
  });
}

function renderActivityFeed() {
  const events = getFilteredEvents().slice(0, 50);
  els.activityFeed.replaceChildren();

  if (events.length === 0) {
    const p = document.createElement("p");
    p.className = "muted small";
    p.textContent = "No login events recorded for this filter yet.";
    els.activityFeed.appendChild(p);
    return;
  }

  events.forEach((ev) => {
    const item = document.createElement("div");
    item.className = "activity-item";

    const left = document.createElement("div");
    left.className = "user-cell";
    const img = document.createElement("img");
    img.className = "avatar-sm hidden";
    img.alt = "";
    const fallback = document.createElement("div");
    fallback.className = "avatar-fallback sm";
    setAvatar(img, fallback, ev.photoURL, ev.displayName || ev.email || "U");

    const info = document.createElement("div");
    const title = document.createElement("div");
    title.className = "user-name";
    title.textContent = ev.displayName || ev.email || ev.uid;
    const sub = document.createElement("div");
    sub.className = "user-email";
    sub.textContent = `${ev.email || ev.uid} • ${ev.osVersion}`;
    info.append(title, sub);
    left.append(img, fallback, info);

    const right = document.createElement("div");
    right.className = "activity-meta";
    const badge = document.createElement("span");
    const isInteractive = ev.eventType === "interactive_sign_in";
    badge.className = `badge ${isInteractive ? "badge-interactive" : "badge-resume"}`;
    badge.textContent = isInteractive ? "Google Sign-In" : "App Launch";

    const when = document.createElement("span");
    when.className = "muted small";
    when.textContent = formatRelative(ev.createdAt);
    when.title = ev.createdAt ? ev.createdAt.toLocaleString() : "";

    right.append(badge, when);
    item.append(left, right);
    els.activityFeed.appendChild(item);
  });
}

function openUserModal(user) {
  els.modalUserName.textContent = user.displayName || "Google User";
  els.modalUserEmail.textContent = `${user.email || "—"} • UID: ${user.uid}`;
  setAvatar(els.modalAvatar, els.modalInitials, user.photoURL, user.displayName || user.email || "U");

  els.modalMeta.replaceChildren();
  const metaPairs = [
    ["Total Logins", formatNumber(user.loginCount)],
    ["Last Login", user.lastLoginAt ? user.lastLoginAt.toLocaleString() : "—"],
    ["First Joined", user.firstSeenAt ? user.firstSeenAt.toLocaleString() : "—"],
    ["Environment", `LoopSearch v${user.appVersion} (${user.osVersion})`]
  ];
  metaPairs.forEach(([label, value]) => {
    const box = document.createElement("div");
    const span = document.createElement("span");
    span.textContent = label;
    const val = document.createElement("strong");
    val.textContent = value;
    box.append(span, val);
    els.modalMeta.appendChild(box);
  });

  const userEvents = state.loginEvents.filter((e) => e.uid === user.uid).slice(0, 20);
  els.modalEvents.replaceChildren();
  if (userEvents.length === 0) {
    const p = document.createElement("p");
    p.className = "muted small";
    p.textContent = "No events found in the latest 500 event window.";
    els.modalEvents.appendChild(p);
  } else {
    userEvents.forEach((ev) => {
      const row = document.createElement("div");
      row.className = "activity-item";
      const left = document.createElement("div");
      left.textContent = ev.createdAt ? ev.createdAt.toLocaleString() : ev.dateKey;
      const right = document.createElement("span");
      const isInteractive = ev.eventType === "interactive_sign_in";
      right.className = `badge ${isInteractive ? "badge-interactive" : "badge-resume"}`;
      right.textContent = isInteractive ? "Google Sign-In" : "App Launch";
      row.append(left, right);
      els.modalEvents.appendChild(row);
    });
  }

  els.userModal.classList.remove("hidden");
}

function closeUserModal() {
  els.userModal.classList.add("hidden");
}

function exportUsersCsv() {
  const rows = getFilteredSortedUsers();
  const headers = ["uid", "displayName", "email", "loginCount", "firstSeenAt", "lastLoginAt", "appVersion", "osVersion", "lastEventType"];
  const lines = [
    headers.join(","),
    ...rows.map((u) => [
      u.uid,
      u.displayName,
      u.email,
      u.loginCount,
      u.firstSeenAt ? u.firstSeenAt.toISOString() : "",
      u.lastLoginAt ? u.lastLoginAt.toISOString() : "",
      u.appVersion,
      u.osVersion,
      u.lastEventType
    ].map(csvCell).join(","))
  ];

  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `loopsearch-users-${utcDateKey(new Date())}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function csvCell(raw) {
  const str = String(raw ?? "");
  // Prevent CSV formula injection in spreadsheet tools.
  const safe = /^[=+\-@\t\r]/.test(str) ? `'${str}` : str;
  return `"${safe.replace(/"/g, '""')}"`;
}

function setAvatar(imgEl, fallbackEl, photoURL, label) {
  const safeUrl = typeof photoURL === "string" && /^https?:\/\//i.test(photoURL) ? photoURL : "";
  const initials = getInitials(label);
  fallbackEl.textContent = initials;

  if (!safeUrl) {
    imgEl.classList.add("hidden");
    fallbackEl.classList.remove("hidden");
    return;
  }

  imgEl.referrerPolicy = "no-referrer";
  imgEl.src = safeUrl;
  imgEl.onload = () => {
    imgEl.classList.remove("hidden");
    fallbackEl.classList.add("hidden");
  };
  imgEl.onerror = () => {
    imgEl.classList.add("hidden");
    fallbackEl.classList.remove("hidden");
  };
}

function getInitials(label) {
  const parts = String(label || "U").trim().split(/\s+/).slice(0, 2);
  const letters = parts.map((p) => p[0] || "").join("").toUpperCase();
  return letters || "U";
}

function formatNumber(n) {
  return new Intl.NumberFormat().format(Number(n) || 0);
}

function formatDateShort(date) {
  if (!date) return "—";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function formatRelative(date) {
  if (!date) return "—";
  const diffSec = Math.round((Date.now() - date.getTime()) / 1000);
  if (diffSec < 60) return "Just now";
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
  if (diffSec < 7 * 86400) return `${Math.floor(diffSec / 86400)}d ago`;
  return formatDateShort(date);
}

bootstrap();
