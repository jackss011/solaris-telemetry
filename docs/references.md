# References

External resources worth having open while working on Solaris — the language, the rendering
library, the font, and the systems this project is modeled on or borrows ideas from. See
[`README.md`](./README.md) for this repo's own documentation index.

## Odin

- [odin-lang.org](https://odin-lang.org/) — the language's home page and docs portal.
- [Odin overview](https://odin-lang.org/docs/overview/) — the official language tour; our own
  [`odin-language-overview.md`](./odin-language-overview.md) is a project-specific distillation of
  this, with examples pulled from `src/main.odin` instead of generic samples.
- [pkg.odin-lang.org](https://pkg.odin-lang.org/) — generated docs for the `base`, `core`, and
  `vendor` library collections (e.g. `core:math`, `core:testing`, `vendor:raylib`). The single
  best place to check a stdlib proc's exact signature before using it.
- [odin-lang/Odin on GitHub](https://github.com/odin-lang/Odin) — compiler + stdlib source
  (releases are what `bin/odin/` is populated from — see `CLAUDE.md`'s Setup section). When in
  doubt about exact runtime behavior of something (as opposed to just its signature), the vendored
  copy at `bin/odin/core/`/`bin/odin/vendor/` is the ground truth for *this* project's compiler
  version, and is worth grepping directly — several details in
  [`odin-language-overview.md`](./odin-language-overview.md) (e.g. the `[dynamic; N]T` fixed-capacity
  array feature) were confirmed this way rather than assumed.

## raylib

- [raylib.com](https://www.raylib.com/) — the library's home page, examples, and news.
- [raylib cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html) — a one-page function
  reference by module (`rcore`, `rshapes`, `rtextures`, `rtext`, ...); the fastest way to check
  what a raylib function does without opening source. Matches the vendored raylib 6.0 this project
  builds against (confirmed via this repo's own runtime log: `INFO: Initializing raylib 6.0`).
- [raysan5/raylib on GitHub](https://github.com/raysan5/raylib) — raylib's own source (the `C`
  implementation underneath `vendor:raylib`'s Odin bindings).
- The Odin bindings themselves: `bin/odin/vendor/raylib/raylib.odin` (local, not a URL) — the
  actual declared signatures/enums for whatever's imported as `rl` in `src/main.odin`. When a
  raylib call doesn't compile or behaves unexpectedly, this file is more authoritative than the
  C docs/cheatsheet above, since it's the exact Odin-side surface this project sees.
- [GLFW](https://www.glfw.org/) — the windowing/input backend raylib uses on desktop platforms
  (visible in this project's own startup log: `Platform backend: DESKTOP (GLFW)`).

## Font

- [Share Tech on Google Fonts](https://fonts.google.com/specimen/Share+Tech) — the font used for
  all UI text (`assets/fonts/ShareTech/ShareTech-Regular.ttf`), loaded via `rl.LoadFontEx` in `main`.
  Licensed under the SIL Open Font License 1.1 — see `assets/fonts/ShareTech/OFL.txt` (bundled alongside the
  font, as the license requires) for the full terms; the short version is it can be embedded,
  bundled, and used in a commercial product, but not resold by itself, and any *modified* version
  can't keep the "Share Tech" name without permission.

## COSMOS / OpenC3 (what Solaris is inspired by)

Full detail and sourcing lives under [`cosmos/`](./cosmos/) (see [`README.md`](./README.md) for
the index of those docs); the two upstream projects themselves:

- [BallAerospace/COSMOS](https://github.com/BallAerospace/COSMOS) — the original project (v4, the
  version this repo's docs focus on).
- [OpenC3](https://github.com/OpenC3) — where COSMOS's development continues after Ball Aerospace
  stopped maintaining it under that name.
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification) — the spec underneath
  COSMOS v4's own "relaxed JSON-RPC 2.0" API; see [`cosmos/json-rpc.md`](./cosmos/json-rpc.md) for
  exactly where COSMOS deviates from it.

## Design philosophy

The `casey-muratori-style` project skill (`.claude/skills/casey-muratori-style/`) is the
data-oriented, minimal-abstraction philosophy this codebase is meant to follow — flat control
flow, explicit allocation, abstracting only after real duplication shows up. Its namesake:

- [Handmade Hero](https://handmadehero.org/) — Casey Muratori's from-scratch game-programming
  series; the origin of this style of thinking about game/tool code.
