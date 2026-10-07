#!/bin/bash
# Build the drag-to-Applications installer before signing or notarizing its DMG.
# The input .app is copied intact, preserving its code signature and stapled ticket.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: build-dmg.sh <signed LuciControl.app> <new output.dmg>}"
OUTPUT="${2:?usage: build-dmg.sh <signed LuciControl.app> <new output.dmg>}"
PYTHON="${DMG_PYTHON:-python3}"
[[ "$APP" = /* && "$OUTPUT" = /* ]] || { echo 'Use absolute app and output paths.' >&2; exit 1; }
test -d "$APP" && test ! -e "$OUTPUT" || { echo 'Input missing or output already exists.' >&2; exit 1; }
"$PYTHON" -c 'import ds_store' || { echo 'Install scripts/dmg/requirements.txt in a venv and set DMG_PYTHON.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
WORK="$(mktemp -d /tmp/lucicontrol-dmg.XXXXXX)"
MOUNT="$WORK/mount"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then hdiutil detach "$MOUNT" -quiet || { echo "Detach manually: $MOUNT" >&2; return; }; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/staging/.background" "$(dirname "$OUTPUT")"
ditto "$APP" "$WORK/staging/LuciControl.app"
ln -s /Applications "$WORK/staging/Applications"
swift "$ROOT/scripts/dmg/artwork.swift" "$WORK/artwork"
tiffutil -cathidpicheck "$WORK/artwork/background.png" "$WORK/artwork/background@2x.png" -out "$WORK/staging/.background/background.tiff"
clang -fobjc-arc -Wno-deprecated-declarations -framework Foundation -framework CoreServices \
  "$ROOT/scripts/dmg/bookmark.m" -o "$WORK/bookmark"
hdiutil create -volname LuciControl -fs HFS+ -srcfolder "$WORK/staging" -format UDRW "$WORK/writable.dmg" -quiet
hdiutil attach -readwrite -nobrowse -mountpoint "$MOUNT" "$WORK/writable.dmg" -quiet
MOUNTED=1
"$WORK/bookmark" "$MOUNT/.background/background.tiff" "$WORK/alias" "$WORK/bookmark-data"
"$PYTHON" "$ROOT/scripts/dmg/layout.py" "$MOUNT" "$WORK/alias" "$WORK/bookmark-data"
# Finder opens the volume when the user mounts it through DiskImageMounter.
# bless --openfolder is unsupported on Apple Silicon.
hdiutil detach "$MOUNT" -quiet
MOUNTED=0
hdiutil convert "$WORK/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" -quiet
hdiutil verify "$OUTPUT"
echo "Installer ready for signing: $OUTPUT"
