#!/usr/bin/env bash
# Build the web version into build/web. --size builds for shipping (-o:size).
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN="${ODIN:-/home/yermom/ODIN/odin}"
OPT="-o:speed"
[[ "${1:-}" == "--size" ]] && OPT="-o:size"
mkdir -p build/web
"$ODIN" build src/web -target:js_wasm32 -out:build/web/game.wasm $OPT
cp "$("$ODIN" root)/core/sys/wasm/js/odin.js" build/web/
cp web/index.html build/web/
ls -la build/web
