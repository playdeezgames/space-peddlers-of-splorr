#!/usr/bin/env bash
# Native tests (random-play soaks included), then a wasm type check.
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN="${ODIN:-/home/yermom/ODIN/odin}"
"$ODIN" test src/game -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false -o:speed
"$ODIN" check src/web -target:js_wasm32
