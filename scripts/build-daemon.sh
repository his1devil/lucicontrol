#!/bin/sh
# Builds lucirund from ../lucirund as a universal binary into build/lucirund, which the
# Xcode project copies into LuciControl.app/Contents/MacOS/. Needs Go.
set -eu
cd "$(dirname "$0")/.."
src="${LUCIRUND_SRC:-../lucirund}"
out="$PWD/build"
mkdir -p "$out"
if ! command -v go >/dev/null 2>&1; then
  export PATH="$PATH:/opt/homebrew/bin:/usr/local/go/bin"
fi
daemon_version="${LUCIRUND_VERSION:-0.2.0}"
version=$(cd "$src" && git describe --always --dirty 2>/dev/null || echo dev)
(cd "$src" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-X lucirund/internal/daemon.Version=$daemon_version+$version" -o "$out/lucirund-arm64" ./cmd/lucirund)
(cd "$src" && CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-X lucirund/internal/daemon.Version=$daemon_version+$version" -o "$out/lucirund-amd64" ./cmd/lucirund)
lipo -create "$out/lucirund-arm64" "$out/lucirund-amd64" -output "$out/lucirund"
rm -f "$out/lucirund-arm64" "$out/lucirund-amd64"
echo "build/lucirund: $(lipo -archs "$out/lucirund") ($version)"
