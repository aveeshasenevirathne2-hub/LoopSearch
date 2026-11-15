#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building LoopSearch (release, macOS 14+ universal)..."
ARCH_FLAGS=()
if [[ "${SWIFT_UNIVERSAL:-1}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}" \
    -Xswiftc -debug-prefix-map -Xswiftc "$SCRIPT_DIR=/src"

BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/CircleToSearch"
APP_DIR="$SCRIPT_DIR/LoopSearch.app"

rm -rf "$SCRIPT_DIR/CircleToSearch.app" "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

COPYFILE_DISABLE=1 cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/CircleToSearch"
COPYFILE_DISABLE=1 cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
COPYFILE_DISABLE=1 cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -f "$SCRIPT_DIR/Resources/FirebaseConfig.plist" ]]; then
    COPYFILE_DISABLE=1 cp "$SCRIPT_DIR/Resources/FirebaseConfig.plist" "$APP_DIR/Contents/Resources/FirebaseConfig.plist"
fi
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Strip local and debug symbols so no local filesystem paths or personal metadata remain.
strip -S -x "$APP_DIR/Contents/MacOS/CircleToSearch"

# Clean Finder/macOS metadata before signing.
find "$APP_DIR" -name '.DS_Store' -delete
xattr -cr "$APP_DIR"

# Default to ad-hoc signing so personal Apple Development certificates/emails are never embedded.
# Override by setting CODESIGN_IDENTITY explicitly for notarized Developer ID builds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR (signed with: $CODESIGN_IDENTITY)"
