#!/bin/bash
# Prepare a signed, notarized Universal release locally. Nothing is uploaded to
# the download server or GitHub. Sparkle private keys stay in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# Version and build default to project.yml, the one place they live.
setting() { awk -v key="$1:" '$1 == key { print $2; exit }' project.yml; }
VERSION="${RELEASE_VERSION:-$(setting MARKETING_VERSION)}"
BUILD="${RELEASE_BUILD:-$(setting CURRENT_PROJECT_VERSION)}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Antai Feng (M7ZSWL69E9)}"
TEAM="${DEVELOPER_TEAM:-M7ZSWL69E9}"
PROFILE="${NOTARY_PROFILE:-lucicontrol-notary}"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.his1devil.lucicontrol}"
BASE_URL="${DOWNLOAD_BASE_URL:-https://im.zhanghuanyang.com/lucirund/dist/}"
: "${SPARKLE_TOOLS:?Set SPARKLE_TOOLS to the bin directory of the official Sparkle 2.10.0 release}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid release version/build' >&2; exit 1; }
[[ "$BASE_URL" == https://*/ ]] || { echo 'Download URL must be HTTPS and end in /' >&2; exit 1; }
for tool in xcodegen xcodebuild codesign xcrun ditto hdiutil python3 swift clang tiffutil spctl; do command -v "$tool" >/dev/null; done
"${DMG_PYTHON:-python3}" -c 'import ds_store' || { echo 'Install scripts/dmg/requirements.txt in a venv and set DMG_PYTHON.' >&2; exit 1; }
for tool in generate_keys generate_appcast; do test -x "$SPARKLE_TOOLS/$tool"; done
if [[ "${ALLOW_DIRTY:-0}" != 1 ]]; then
  test -z "$(git status --porcelain)" || { echo 'Commit app changes before a public release (ALLOW_DIRTY=1 for a local candidate).' >&2; exit 1; }
  test -z "$(git -C "${LUCIRUND_SRC:-../lucirund}" status --porcelain)" || { echo 'Daemon source is dirty.' >&2; exit 1; }
fi
OUT="${RELEASE_OUT:-$ROOT/build/releases/$VERSION-$BUILD}"
# Never overwrite an earlier candidate, notarization record, or signed feed.
test ! -e "$OUT" || { echo "Release output already exists: $OUT" >&2; exit 1; }
mkdir -p "$OUT/updates" "$OUT/downloads"
xcodegen generate
PUBLIC_KEY="$("$SPARKLE_TOOLS/generate_keys" --account "$ACCOUNT" -p)"
BUNDLE_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
test "$PUBLIC_KEY" = "$BUNDLE_KEY" || { echo 'Sparkle key does not match the app public key.' >&2; exit 1; }
xcodebuild -project LuciControl.xcodeproj -scheme LuciControl -configuration Release \
  -derivedDataPath "$OUT/DerivedData" -archivePath "$OUT/LuciControl.xcarchive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive > "$OUT/archive.log" 2>&1
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>$IDENTITY</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/LuciControl.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" > "$OUT/export.log" 2>&1
APP="$OUT/export/LuciControl.app"
python3 scripts/verify-release.py "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ZIP="$OUT/updates/LuciControl-$VERSION-$BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --timeout 20m --output-format json > "$2"
  python3 - "$2" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
print('Notarization:', result.get('status'), result.get('id'))
if result.get('status') != 'Accepted': raise SystemExit('Notarization was not accepted; inspect the saved result.')
PY
}
notarize "$ZIP" "$OUT/notary-app.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# The update ZIP must include the app's stapled ticket.
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
DMG="$OUT/downloads/LuciControl-$VERSION-$BUILD-universal.dmg"
"$ROOT/scripts/build-dmg.sh" "$APP" "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG" "$OUT/notary-dmg.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --verbose=2 "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
if test -f "docs/releases/$VERSION.html"; then cp "docs/releases/$VERSION.html" "$OUT/updates/LuciControl-$VERSION-$BUILD.html"; fi
"$SPARKLE_TOOLS/generate_appcast" --account "$ACCOUNT" --download-url-prefix "$BASE_URL" \
  --maximum-deltas 0 --embed-release-notes "$OUT/updates"
(cd "$OUT" && shasum -a 256 updates/*.zip downloads/*.dmg > SHA256SUMS)
python3 - "$OUT" "$ROOT" "${LUCIRUND_SRC:-../lucirund}" <<'PY'
import json,subprocess,sys
from pathlib import Path
out,root,daemon=sys.argv[1:]
def git(path,*args): return subprocess.check_output(['git','-C',path,*args],text=True).strip()
metadata={'appCommit':git(root,'rev-parse','HEAD'),'appDirty':bool(git(root,'status','--porcelain')),'daemonCommit':git(daemon,'rev-parse','HEAD'),'daemonDirty':bool(git(daemon,'status','--porcelain'))}
Path(out,'source.json').write_text(json.dumps(metadata,indent=2)+'\n')
PY
echo "Prepared locally: $OUT"
echo 'Publish versioned archives first, verify their hashes, then replace appcast.xml atomically.'
