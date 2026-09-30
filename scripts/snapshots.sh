#!/bin/sh
# Renders every page of the demo panel, light and dark, into the given directory.
#   scripts/snapshots.sh <out dir> [app path]
set -eu
out="${1:?out dir}"
app="${2:-DerivedData/Build/Products/Debug/LuciControl.app}"
mkdir -p "$out"
for theme in light dark; do
  for page in home empty claude add pair "pair --pair-state code" "pair --pair-state claimed" "pair --pair-state done" devices settings settings-latest settings-downloading codex-missing; do
    name=$(echo "$page" | sed 's/ --pair-state /-/')
    # shellcheck disable=SC2086
    "$app/Contents/MacOS/LuciControl" --demo --window --appearance "$theme" --page $page --snapshot "$out/$theme-$name.png" 2>/dev/null &
    sleep 2.2
  done
done
wait
ls "$out"
