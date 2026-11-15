import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  GoogleAuthProvider,
  getAuth,
  inMemoryPersistence,
  setPersistence,
  signInWithPopup,
  signOut
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";

const readyPanel = document.getElementById("bridge-ready");
const invalidPanel = document.getElementById("bridge-invalid");
const continueBtn = document.getElementById("btn-continue-google");
const cancelBtn = document.getElementById("btn-cancel-auth");
const statusEl = document.getElementById("bridge-status");
const errorEl = document.getElementById("bridge-error");

const params = new URLSearchParams(window.location.search);
const port = Number(params.get("port"));
const stateToken = (params.get("state") || "").trim();

function isValidBridgeRequest() {
  return Number.isInteger(port)
    && port >= 1024
    && port <= 65535
    && /^[A-Za-z0-9_-]{12,128}$/.test(stateToken);
}

async function loadFirebaseConfig() {
  try {
    const mod = await import("./firebase-config.js");
    if (mod.firebaseConfig?.apiKey && !String(mod.firebaseConfig.apiKey).startsWith("YOUR_")) {
      return mod.firebaseConfig;
    }
  } catch {
    // Fallback to Firebase Hosting auto-config below.
  }

  const resp = await fetch("/__/firebase/init.json");
  if (!resp.ok) {
    throw new Error("Could not load Firebase project configuration.");
  }
  return await resp.json();
}

function showError(msg) {
  errorEl.textContent = msg;
  errorEl.classList.remove("hidden");
  statusEl.classList.add("hidden");
}

function clearMessages() {
  errorEl.textContent = "";
  errorEl.classList.add("hidden");
  statusEl.textContent = "";
  statusEl.classList.add("hidden");
}

function showStatus(msg) {
  errorEl.classList.add("hidden");
  statusEl.textContent = msg;
  statusEl.classList.remove("hidden");
}

function redirectToMacApp(queryPairs) {
  const cb = new URL(`http://127.0.0.1:${port}/oauth2/callback`);
  cb.searchParams.set("state", stateToken);
  for (const [k, v] of Object.entries(queryPairs)) {
    if (v) cb.searchParams.set(k, v);
  }
  window.location.replace(cb.toString());
}

async function main() {
  if (!isValidBridgeRequest()) {
    readyPanel.classList.add("hidden");
    invalidPanel.classList.remove("hidden");
    return;
  }

  let auth;
  try {
    const config = await loadFirebaseConfig();
    const app = initializeApp(config, "loopsearch-mac-bridge");
    auth = getAuth(app);
    // Keep desktop sign-in strictly in memory so admin dashboard sessions remain untouched.
    await setPersistence(auth, inMemoryPersistence);
  } catch (err) {
    showError(err?.message || "Failed to initialize Google Sign-In.");
    continueBtn.disabled = true;
    return;
  }

  cancelBtn.addEventListener("click", () => {
    redirectToMacApp({ error: "access_denied" });
  });

  continueBtn.addEventListener("click", async () => {
    clearMessages();
    continueBtn.disabled = true;
    showStatus("Waiting for Google sign-in confirmation…");

    try {
      const provider = new GoogleAuthProvider();
      provider.setCustomParameters({ prompt: "select_account" });
      const result = await signInWithPopup(auth, provider);
      const cred = GoogleAuthProvider.credentialFromResult(result);
      const idToken = cred?.idToken || "";
      const accessToken = cred?.accessToken || "";
      const refreshToken = result.user?.refreshToken || "";

      await signOut(auth).catch(() => {});

      if (idToken) {
        redirectToMacApp({ id_token: idToken });
      } else if (accessToken) {
        redirectToMacApp({ access_token: accessToken });
      } else if (refreshToken) {
        redirectToMacApp({ refresh_token: refreshToken });
      } else {
        throw new Error("Google sign-in did not return a verification credential.");
      }
    } catch (err) {
      continueBtn.disabled = false;
      if (err?.code === "auth/popup-closed-by-user" || err?.code === "auth/cancelled-popup-request") {
        showError("Sign-in popup closed. Click Continue with Google to try again.");
      } else if (err?.code === "auth/popup-blocked") {
        showError("Your browser blocked the sign-in popup. Allow popups for this site and try again.");
      } else {
        showError(err?.message || "Google Sign-In failed.");
      }
    }
  });
}

main();
