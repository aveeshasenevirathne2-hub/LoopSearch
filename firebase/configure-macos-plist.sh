#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_PLIST="$ROOT_DIR/Resources/FirebaseConfig.plist"

if [[ $# -lt 3 ]]; then
    cat <<EOF
Usage:
  $(basename "$0") <FIREBASE_WEB_API_KEY> <FIREBASE_PROJECT_ID> <GOOGLE_OAUTH_CLIENT_ID> [GOOGLE_OAUTH_CLIENT_SECRET] [DATABASE_ID]

Writes a gitignored Resources/FirebaseConfig.plist used by build_app.sh when bundling LoopSearch.app.
EOF
    exit 1
fi

API_KEY="$1"
PROJECT_ID="$2"
GOOGLE_CLIENT_ID="$3"
GOOGLE_CLIENT_SECRET="${4:-}"
DATABASE_ID="${5:-(default)}"

python3 - "$DEST_PLIST" "$API_KEY" "$PROJECT_ID" "$GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_SECRET" "$DATABASE_ID" <<'PY'
import plistlib
import sys

dest, api_key, project_id, client_id, client_secret, db_id = sys.argv[1:7]
payload = {
    "APIKey": api_key.strip(),
    "ProjectID": project_id.strip(),
    "DatabaseID": db_id.strip() or "(default)",
    "GoogleClientID": client_id.strip(),
    "GoogleClientSecret": client_secret.strip(),
    "ReversedClientScheme": "",
}
with open(dest, "wb") as f:
    plistlib.dump(payload, f)
print(f"Wrote {dest}")
PY
