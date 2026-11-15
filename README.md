# LoopSearch

Native macOS visual screen search utility built with Swift and AppKit. Circle, box, or tap anything on your screen to run Google Lens visual search, instant on-device Vision OCR, subject lifting, or Ask AI follow-ups.

> **Disclaimer:** LoopSearch is an independent macOS application and is not affiliated with, endorsed by, or sponsored by Google LLC.

## Features

- **4 Selection Modes:** Box (`1`), Freehand Loop (`2`), Tap (`3`), and Text OCR (`4`).
- **Global Shortcut:** Trigger from any app (`⌘⇧Space` default, `⌥Space`, `⌘⇧S`, or custom shortcut).
- **Search Providers:** Google Lens, Google, Perplexity, Bing, and Ask AI.
- **On-Device Vision OCR:** Instant text extraction with one-click copy and 4-entry session history.
- **LoopSearch Studio & Welcome Guide:** Configure theme (`System` / `Dark` / `Light`), glow intensity, Horizon Blue vs. Spectrum palette, reduce-motion mode, and check for updates via GitHub Releases.

## Privacy & Security

- **Private Encrypted Local Storage:** Any optional Gemini API key (`ai-key.bin`) and your Google/Firebase session tokens (`auth-session.bin`) are stored AES-GCM encrypted in `~/Library/Application Support/LoopSearch/` (`0o700`/`0o600` permissions, zero macOS Keychain password prompts) and are never bundled in the repository.
- **Required Google Sign-In & Offline Resilience:** LoopSearch requires a one-time Google Sign-In via OAuth 2.0 PKCE in your browser (name & email only), continues working offline afterward, and queues telemetry locally until internet returns.
- **Private Config Exclusion:** Personal Firebase config files (`Resources/FirebaseConfig.plist`, `firebase/.firebaserc`, `firebase/dashboard/firebase-config.js`) are `.gitignore`d so contributors configure their own Firebase project safely.
- **On-Demand Captures:** Screen captures are only processed when you trigger a selection and are sent only to the search provider you choose.
- **Clean Distribution Builds:** `./build_app.sh` strips debug/local symbols and signs ad-hoc (`-`) by default so no local build paths or developer certificates are embedded.

## Firebase Auth & Analytics Dashboard Setup

The `firebase/` directory contains Firestore Security Rules (`firestore.rules`), composite indexes (`firestore.indexes.json`), Hosting config (`firebase.json`), and the dark Liquid Glass **LoopSearch Analytics** web dashboard (`firebase/dashboard/`).

1. **Provision Firebase:**
   - Enable **Google** sign-in under Firebase Console → Authentication → Sign-in method.
   - In Google Cloud Console → APIs & Services → Credentials, create a **Desktop app** OAuth 2.0 Client ID and add that Client ID to Firebase Authentication → Google → **Authorized client IDs**.
2. **Configure macOS App (Gitignored):**
   ```bash
   ./firebase/configure-macos-plist.sh "<WEB_API_KEY>" "<PROJECT_ID>" "<GOOGLE_DESKTOP_CLIENT_ID>" "<GOOGLE_DESKTOP_CLIENT_SECRET>"
   ```
   (Or copy `Resources/FirebaseConfig.plist.example` to `Resources/FirebaseConfig.plist` before running `./build_dmg.sh`.)
3. **Configure & Deploy Rules + Dashboard:**
   - Copy `firebase/.firebaserc.example` → `firebase/.firebaserc` and `firebase/dashboard/firebase-config.example.js` → `firebase/dashboard/firebase-config.js`.
   - Deploy from `firebase/`:
     ```bash
     npx -y firebase-tools@latest deploy --only firestore,hosting
     ```
4. **Authorize Dashboard Admins (2-Admin Allowlist):**
   - Dashboard access is strictly locked via `admins/{uid}` (`active: true`) in `firestore.rules`. No admin emails or UIDs live in source control.
   - Open your hosted dashboard, sign in with each admin Google account to reveal its Firebase `UID`, and add `admins/<UID>` (`{ active: true }`) in Cloud Firestore.

## Installation (DMG)

1. Download `LoopSearch.dmg` from [Releases](https://github.com/aveeshasenevirathne2-hub/LoopSearch/releases).
2. Open the disk image and drag **LoopSearch.app** into **Applications**.
3. On first launch, if macOS Gatekeeper warns about an unidentified developer (since open-source ad-hoc builds are not notarized), right-click **LoopSearch.app** → **Open** (or allow it in **System Settings → Privacy & Security**).
4. Grant **Screen Recording** permission in **System Settings → Privacy & Security → Screen Recording** when prompted.

## Building from Source

Requires macOS 14+ and Swift 5.10+:

```bash
chmod +x build_app.sh build_dmg.sh
./build_dmg.sh
```

- `./build_app.sh` builds `LoopSearch.app` (override signing with `CODESIGN_IDENTITY="..." ./build_app.sh` if distributing with your own Developer ID).
- `./build_dmg.sh` builds `LoopSearch.app` and packages a verified `LoopSearch.dmg`.

## Creator & Feedback

- Made by **Aveesha Senevirathne**
- X: [@AveeshaSen](https://x.com/AveeshaSen)
- GitHub: [aveeshasenevirathne2-hub/LoopSearch](https://github.com/aveeshasenevirathne2-hub/LoopSearch)
- Rate & Suggest Features: Open **Rate & Suggest Feature…** from the menu bar or submit an idea on [GitHub Issues](https://github.com/aveeshasenevirathne2-hub/LoopSearch/issues)
