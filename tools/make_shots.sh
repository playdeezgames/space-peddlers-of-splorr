#!/usr/bin/env bash
# Renders the itch.io screenshots and the cover from the native smoke test's frame dumps
# (build/shots/*.ppm): assets/screenshots/01-05 at 2x (640 by 640) and assets/cover.png.
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false \
	-define:ODIN_TEST_NAMES=game.smoke_new_game >/dev/null
python3 - <<'PY'
from PIL import Image
pairs = [("00-start", "01-title"), ("03-system-info", "02-system-info"), ("04-buy-cargo", "03-buy-cargo"),
         ("05-warp", "04-short-range-chart"), ("06-galaxy", "05-galactic-chart")]
for src, dst in pairs:
    im = Image.open(f"build/shots/{src}.ppm").convert("RGB")
    im.resize((640, 640), Image.NEAREST).save(f"assets/screenshots/{dst}.png", optimize=True)
    print("assets/screenshots/" + dst + ".png")
PY
python3 tools/make_cover.py
