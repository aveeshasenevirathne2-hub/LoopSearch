#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$SCRIPT_DIR/build_app.sh"
fi

APP_DIR="$SCRIPT_DIR/LoopSearch.app"
DMG_PATH="$SCRIPT_DIR/LoopSearch.dmg"
VOL_NAME="LoopSearch"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Error: $APP_DIR not found." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/loopsearch-dmg.XXXXXX)"
STAGE_DIR="$WORK_DIR/stage"
RW_DMG="$WORK_DIR/LoopSearch-rw.dmg"
MOUNT_DIR="$WORK_DIR/mnt"
BG_PNG="$WORK_DIR/dmg-bg.png"

cleanup() {
    if [[ -n "${MOUNT_DIR:-}" ]] && mount | grep -q "on $MOUNT_DIR "; then
        hdiutil detach -force "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/.background"

echo "Generating branded DMG installer artwork..."
swift "$SCRIPT_DIR/Resources/generate_dmg_bg.swift" "$BG_PNG"
cp "$BG_PNG" "$STAGE_DIR/.background/dmg-bg.png"

echo "Staging $VOL_NAME.dmg..."
COPYFILE_DISABLE=1 cp -a "$APP_DIR" "$STAGE_DIR/LoopSearch.app"
ln -s /Applications "$STAGE_DIR/Applications"

find "$STAGE_DIR" -name '.DS_Store' -delete
xattr -cr "$STAGE_DIR/LoopSearch.app"
codesign --verify --deep --strict "$STAGE_DIR/LoopSearch.app"

# Calculate generous size for RW image (~app size + 24MB padding)
SIZE_KB=$(du -sk "$STAGE_DIR" | awk '{print $1 + 24576}')
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE_DIR" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${SIZE_KB}k" \
    "$RW_DMG" >/dev/null

ATTACH_OUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUT" | awk '/\/Volumes\//{print substr($0, index($0, "/Volumes/"))}' | head -n 1)"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Error: Failed to locate mounted DMG volume under /Volumes." >&2
    exit 1
fi
DISK_NAME="$(basename "$MOUNT_DIR")"

chflags hidden "$MOUNT_DIR/.background" "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes" >/dev/null 2>&1 || true

# Apply Finder window layout (bounds, Retina background, large icons) using the mounted /Volumes disk
if osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        delay 1
        set win to container window
        set current view of win to icon view
        set toolbar visible of win to false
        set statusbar visible of win to false
        set the bounds of win to {200, 140, 860, 588}
        set viewOpts to the icon view options of win
        set arrangement of viewOpts to not arranged
        set icon size of viewOpts to 116
        set text size of viewOpts to 13
        set background picture of viewOpts to file ".background:dmg-bg.png"
        set position of item "LoopSearch.app" of win to {175, 222}
        set position of item "Applications" of win to {485, 222}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "Applied branded Finder installer layout ($DISK_NAME)."
else
    echo "Warning: Finder GUI layout skipped (headless/non-interactive session); DMG structure & symlink remain intact."
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null || hdiutil detach -force "$MOUNT_DIR" >/dev/null

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null

xattr -cr "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Built and verified $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
