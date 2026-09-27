# CLAUDE.md

Guidance for Claude Code (and other coding agents) working in this repo.

## Project overview

Solaris is a **COSMOS-inspired telemetry viewer**, written in [Odin](https://odin-lang.org/)
using `vendor:raylib` for rendering. `src/main.odin` currently holds two pieces that don't talk
to each other yet:

1. A telemetry-definition **parser** that has grown past a bare tokenizer into a real two-layer
   design (see "Architecture" below) — it parses `examples/simple_tlm/tlm.txt` and debug-prints
   what it found. Parsed keywords aren't yet turned into semantic `Packet`/`Item` structures.
2. A working **raylib UI** — a grid of slots you click to spawn placeholder panels, with a
   Tab-toggled edit mode for moving and resizing them. This is what actually runs (`main`'s
   entry point is the UI, not the parser) but it has no knowledge of parsed telemetry yet; panels
   are generic placeholders, not real data.

See [`docs/solaris-architecture.md`](./docs/solaris-architecture.md) for the UI in full detail,
including exactly where the disconnect between the two halves is and what's still missing.

## Setup

The Odin compiler is not vendored in git (see `.gitignore`: `/bin/odin/*` is ignored except
its `README.md`). Before building, download it manually:

1. Get a release from https://github.com/odin-lang/Odin/releases
2. Place the extracted compiler at `bin/odin/` so `bin/odin/odin.exe` exists

## Build & run

```sh
./dev.sh
```

This just runs `./bin/odin/odin.exe run ./src -out:build/solaris.exe` (creating `build/` first
if needed — `odin` does not create missing output directories itself). `build/` is gitignored;
don't let build output land in the repo root (`*.exe`/`*.pdb` there are also gitignored as a
safety net, but the built binary belongs in `build/`, not loose at the repo root). There is no
CI config and no formatter config in this repo currently. There is a small test suite
(`src/main_test.odin`), run with:

```sh
mkdir -p build && ./bin/odin/odin.exe test ./src -out:build/solaris_test.exe
```

To produce a distributable build (release-optimized, no console window, zipped with its
`assets/` alongside it), use `./package.sh` — it writes to `dist/` (also gitignored) rather than
`build/`. See that script's comments for the exact `odin build` flags (`-o:speed`,
`-subsystem:windows`).

## Architecture

- `src/main.odin` — single-file program, split into three parts:
  - **Token layer** (`grab_token`) — allocation-free lexer: given `(text, idx)`, returns one
    `TokenRef{type, idx_start, idx_end}` (an index range into `text`, not a copy) and advances
    past it. Token types: `NONE`, `NEWLINE`, `IDENT`, `STR`, `INT`, `FLOAT`, `COMMENT`. Callers
    loop, feeding the previous call's end index back in, until a `NONE` token signals EOF.
  - **Keyword/line layer** (`grab_keyword`) — groups tokens into one logical COSMOS line: a
    `Keyword{token, params[16]TokenRef, params_count, raw_idx_start, raw_idx_end}`, mirroring
    COSMOS's one-keyword-plus-arguments-per-line config model. It calls `grab_token` in a loop,
    skips blank and comment-only lines, and treats the first ident on a line as the keyword and
    everything after as positional params (fixed-size array, no allocation — more than
    `MAX_KEYWORD_PARAMS` (16) params on one line asserts).
  - **Raw-block capture** (`grab_until`) — for `GENERIC_READ_CONVERSION_START`/
    `GENERIC_WRITE_CONVERSION_START`, `parse_config_file` switches out of the keyword/token
    parser entirely and uses `grab_until` to find the matching `_END` line by scanning raw text
    line-by-line for a line whose first word matches — the inline Ruby body in between is
    captured as one raw span (`keyword.raw_idx_start`/`raw_idx_end`) and never tokenized. This
    is deliberate: those bodies are arbitrary Ruby expressions, not COSMOS keyword syntax (see
    `docs/cosmos/lessons.md` point #3 on config-embedded scripting).
  - **Entry point** (`parse_config_file`) — reads a file, loops `grab_keyword`, special-cases
    the two `GENERIC_*_CONVERSION_START` keywords into raw-capture mode, and debug-prints every
    keyword + its params (+ raw body, if any) via `print_keyword`. This is still print-only:
    keywords aren't yet interpreted semantically — `TELEMETRY`, `ITEM`, `STATE`, `LIMITS`, etc.
    all flow through as generic `Keyword{ident, params}` values with no COSMOS-aware structure
    built on top. Turning that into real `Packet`/`Item` data (per
    `docs/cosmos/config-format.md`'s keyword tables) is the next layer up.
  - **The raylib UI** (`Rect`, `Tile`/`Panel`/`Slots`, `DragOperation`, and `main`'s render
    loop) — a slot-grid + draggable/resizable panel prototype that is genuinely live (it's
    `main`'s entry point) but **not connected to the parser above**: clicking a free slot spawns
    a fixed-size placeholder panel, not a real parsed telemetry packet. Vocabulary, used
    consistently in names: a **slot** is one grid cell, a **tile** is a rectangle of slots
    (ints, pure geometry), a **panel** is attached to a tile and is what's drawn (float `Rect`,
    and later its theme/content), **window** only ever means the OS window, and the bottom strip
    is the **status bar**. See [`docs/solaris-architecture.md`](./docs/solaris-architecture.md)
    for the full design (slot model, z-ordering, drag/edit-mode mechanics, render loop, known
    gaps).
- `src/main_test.odin` — `core:testing`-based tests, now covering all three parser layers
  (`is_ascii_letter`, `grab_token` across every token type including EOF, `grab_until` for both
  found/not-found, `grab_keyword` including blank/comment-line skipping and EOF), plus the UI's
  `slots_panel_expand_*` resize procs and `slots_update_drag`. Run via the
  test command in "Build & run" above. This coverage was only possible because
  `grab_token`/`grab_keyword` return structured values instead of printing — keep that pattern
  as the parser grows (see "Known issues" below).
- `examples/simple_tlm/tlm.txt` — a sample telemetry definition in COSMOS command/telemetry
  definition language (`APPEND_ITEM`, `LIMITS`, `STATE`, `GENERIC_READ_CONVERSION_*`, etc.).
  This is the input format the parser in `main.odin` is being built to handle. Use this file
  as the reference for what the parser needs to eventually support in full.
- `bin/odin/` — local, gitignored home for the downloaded Odin compiler. Only `README.md`
  inside it is tracked.

## Documentation

Deeper reference material (beyond this quick-orientation file) lives in `docs/` —
see `docs/README.md` for the index. Notably: `docs/solaris-architecture.md` covers this repo's
own code (the parser above, and the raylib UI in far more depth than this file does);
`docs/cosmos/overview.md` explains how the real COSMOS system this project is inspired by works,
functionally and in software, useful background before extending the telemetry-definition parser;
and `docs/references.md` collects external links (Odin, raylib, the UI font/license, COSMOS/OpenC3
upstream) worth having open while working here.

## Known issues / gotchas

- Odin's `fmt.println` does **not** do printf-style `%s`/`%c` substitution the way
  `fmt.printf`/`fmt.printfln` do. Use `fmt.printfln`/`fmt.printf` when interpolating values.
- `parse_config_file` still only *prints* what it parses (via `print_keyword`) rather than
  returning structured `Packet`/`Item` data — so while the token and keyword layers underneath
  it are well-tested (see "Architecture"), the top-level semantic interpretation of COSMOS
  keywords (`TELEMETRY` starts a packet, `LIMITS` attaches to the preceding item, etc.) has no
  test coverage yet and doesn't exist as data other than print output. If you build that layer,
  keep following the `grab_token`/`grab_keyword` pattern of returning values instead of printing,
  so it stays testable.
- `MAX_KEYWORD_PARAMS` (16) is a fixed-size cap on `Keyword.params` — a config line with more
  positional params than that will `assert` (crash), not error gracefully. Worth keeping in mind
  if `examples/simple_tlm/tlm.txt` grows lines with long param lists (e.g. multi-segment
  `SEG_POLY_READ_CONVERSION` chains).
- The raylib UI is **mostly untested** (only the `slots_panel_expand_*` resize procs and
  `slots_update_drag` have tests — the iterator, placement, handle hit-testing and all render
  code don't), and its
  debug prints (`fmt.println`/`fmt.printfln`) go nowhere in the
  packaged `-subsystem:windows` release build (see `package.sh`) since it has no console attached.
  See `docs/solaris-architecture.md`'s "Known gaps" for this and other UI-side loose ends.

## Conventions

- Odin package `main`, procedures in `snake_case`, types in `PascalCase` (see `TokenType`
  enum in `main.odin`) — follow existing style rather than introducing a different convention.
- The raylib UI (`main`) and the parser (`parse_config_file`) are currently independent — the
  eventual goal is feeding real parsed telemetry definitions into the slot/panel UI in
  place of today's generic placeholder panels. Keep that direction in mind when extending either
  side (e.g. a `Packet`/`Item` semantic layer should shape itself around what the UI will need to
  display, not just around `tlm.txt`'s keyword syntax).
