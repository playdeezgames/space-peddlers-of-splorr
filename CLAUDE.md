# CLAUDE.md

Space Peddlers of SPLORR!!: an Odin/wasm port of Pieter Spronck's Space Trader 1.2.2
(Palm OS, C). GPL. Vault note: `bok-of-splorr/splorr/Games/Space Peddlers of SPLORR!!.md`.

## Rules for sessions

- **Never use the original pictures** (Alexander Lawrence's copyright, not GPL). New
  art must match the sizes in `tools/bitmap_sizes.txt`.
- **Do not hand-edit generated files**: `src/game/st_*.odin` (tools/transpile.py),
  `src/game/rsrc_gen.odin` (tools/gen_rsrc.py), `src/game/font_gen.odin`
  (tools/gen_font.py). Fix the generator, or add the function to `OVERRIDES` in
  `transpile.py` and write it in `game_main.odin`.
- Faithful port: keep the original's rules, numbers and text. Don't "fix" its design.
- The repo is public and GPL; keep `LICENSE`, the credits in `README.md` and the
  page footer.
- Never `git push` unless the user says so.

## Layout

See README.md. Key idea: the C blocks inside FrmAlert/FrmDoDialog; `palm_run.odin`
replays a transaction from a snapshot of `world` with the logged inputs, so blocking
calls just read the next input. `g` is `&world.g` (all game globals).
