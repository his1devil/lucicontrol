#!/bin/sh
# Renders the app icon (design round 14b) into Resources/Assets.xcassets/AppIcon.appiconset.
# Needs Google Chrome for the 1024 px master; sips makes the smaller sizes.
set -eu
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out=Resources/Assets.xcassets/AppIcon.appiconset
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/icon.html" <<'HTML'
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;background:transparent}
  .tile{position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;
    background:linear-gradient(180deg,#ffffff 0%,#eef1f5 100%);
    box-shadow:inset 0 0 0 3px rgba(0,0,0,.12),0 20px 68px rgba(0,0,0,.2);
    display:flex;align-items:center;justify-content:center}
  svg{display:block}
</style>
<div class="tile"><svg width="527" height="527" viewBox="0 0 24 24" fill="none" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
<rect x="2.2" y="5.2" width="19.6" height="13.6" rx="3.4" stroke="#1d1d1f"></rect>
<path d="M5.6 5.2H12v13.6H5.6a3.4 3.4 0 0 1-3.4-3.4V8.6a3.4 3.4 0 0 1 3.4-3.4z" fill="#1d1d1f" stroke="#1d1d1f"></path>
<circle cx="5.2" cy="8.4" r="1" fill="#fff" stroke="none"></circle><circle cx="7.8" cy="8.4" r="1" fill="#fff" stroke="none"></circle>
<path d="M14.6 10.6h4.6M14.6 13.4h2.8" stroke="#1d1d1f"></path></svg></div>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --screenshot="$tmp/icon_1024.png" "file://$tmp/icon.html" >/dev/null 2>&1
mkdir -p "$out"
cp "$tmp/icon_1024.png" "$out/icon_512x512@2x.png"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png"; do
  set -- $spec
  sips -s format png -z "$1" "$1" "$tmp/icon_1024.png" --out "$out/$2" >/dev/null
done
cat > "$out/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "icons in $out"
