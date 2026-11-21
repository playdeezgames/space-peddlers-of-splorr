# Space Peddlers of SPLORR!!

An Odin/WebAssembly port of **Space Trader 1.2.2** for Palm OS by Pieter Spronck
(additional coding by Sam Anderson and Samuel Goldstein; some code from Matt Lee's
Dope Wars). Space Trader is free software under the GNU General Public License,
and so is this port: see `LICENSE` (GPL v2; the original sources say "version 2
or any later version").

This is not an official Space Trader release; Pieter Spronck asked that new
versions not be released under that name. The game logic is the original C,
translated mechanically; the Palm OS it ran on is emulated.

## How it is built

- `reference/` holds the original C sources (`Src/`), the Constructor headers
  (`MerchantRsc.h`, `MerchantGraphics.h`), the resource fork with all the text and
  form layouts (`rsrc/Merchant.rsrc`) and the original ReadMe. The original
  pictures (by Alexander Lawrence, not covered by the GPL) are **not** included or
  used; `tools/bitmap_sizes.txt` records only their sizes.
- `tools/gen_rsrc.py` reads the resource fork and writes `src/game/rsrc_gen.odin`
  (forms, alerts, strings, menus).
- `tools/transpile.py` runs `clang -ast-dump=json` over the C (with the Palm OS
  stubs in `tools/palm_stub/`) and writes `src/game/st_*.odin`. Mutable globals
  become fields of one `Globals` struct (`g.Name`).
- `src/game/palm_*.odin` emulate the Palm OS calls the game makes: forms and
  controls, alerts, help, dialogs, menus, databases and the screen (160 by 160
  Palm coordinates on a 320 by 320 double-density framebuffer).
- Blocking dialogs: the C code waits inside `FrmAlert` and `FrmDoDialog`. Here the
  game is replayed from a snapshot with the inputs so far (see `palm_run.odin`).
- `src/web/` is the wasm entry point; `web/index.html` is the page.

## Commands

```bash
python3 -I tools/gen_rsrc.py      # regenerate resources (rarely)
python3 -I tools/transpile.py     # regenerate the translated C (needs clang)
python3 -I tools/gen_font.py      # regenerate the font (needs Pillow)
tools/test.sh                     # native tests, including random-play soaks
tools/build.sh                    # build/web (add --size for shipping)
python3 -m http.server -d build/web 8000
```

## Play-testing

`playtest/` holds scripted players that play the real game for balance testing
(`odin build playtest -o:speed -out:build/playtest`). The findings are in `PLAYTEST.md`.

## Credits

- Space Trader: Pieter Spronck, with Sam Anderson and Samuel Goldstein. GPL.
- Font: m6x11 by Daniel Linssen (managore), free with attribution.
- Port: Ernest Pazera with an AI agent (Claude Code).

## GitHub Pages

`tools/pages.sh` builds the size-optimised web build into `docs/` (served from `main`, `/docs`) at <https://playdeezgames.github.io/space-peddlers-of-splorr/>. Commit `docs/` after running it; it never commits or pushes.
