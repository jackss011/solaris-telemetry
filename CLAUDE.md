# CLAUDE.md

Guidance for Claude Code (and other coding agents) working in this repo.

## Project overview

Solaris is a **COSMOS-inspired telemetry viewer**, written in [Odin](https://odin-lang.org/)
using `vendor:raylib` for rendering. The project is very early-stage (2 commits at time of
writing) and not yet functional as a viewer — see "Current state" below.

## Setup

The Odin compiler is not vendored in git (see `.gitignore`: `/bin/odin/*` is ignored except
its `README.md`). Before building, download it manually:

1. Get a release from https://github.com/odin-lang/Odin/releases
2. Place the extracted compiler at `bin/odin/` so `bin/odin/odin.exe` exists

## Build & run

```sh
./dev.sh
```

This just runs `./bin/odin/odin.exe run ./src`. There is no CI config and no formatter config
in this repo currently. There is a small test suite (`src/main_test.odin`), run with:

```sh
./bin/odin/odin.exe test ./src
```

## Architecture

- `src/main.odin` — single-file program, currently split into two parts:
  - **Active code**: a hand-rolled tokenizer/parser (`parse_config_file`) for COSMOS-style
    telemetry definition files. It runs against `examples/simple_tlm/tlm.txt` and prints
    recognized tokens (`ident`, `string`, `num`, `float`, `comment`) via `fmt.printfln`.
  - **Commented-out code** at the bottom of the file: a raylib window loop that draws a
    telemetry-style panel (voltage readout, etc.). This is the intended eventual UI direction
    but is disabled — treat it as a sketch/reference, not live code.
- `src/main_test.odin` — `core:testing`-based tests, currently covering `is_ascii_letter`. Run
  with `./bin/odin/odin.exe test ./src` (see "Build & run"). Add to this as parser logic grows
  more testable surface (e.g. if `parse_config_file` is refactored to return a token list
  instead of only printing).
- `examples/simple_tlm/tlm.txt` — a sample telemetry definition in COSMOS command/telemetry
  definition language (`APPEND_ITEM`, `LIMITS`, `STATE`, `GENERIC_READ_CONVERSION_*`, etc.).
  This is the input format the parser in `main.odin` is being built to handle. Use this file
  as the reference for what the parser needs to eventually support in full.
- `bin/odin/` — local, gitignored home for the downloaded Odin compiler. Only `README.md`
  inside it is tracked.

## Documentation

Deeper reference material (beyond this quick-orientation file) lives in `docs/` —
see `docs/README.md` for the index. Notably `docs/cosmos-overview.md` explains how the real
COSMOS system this project is inspired by works, functionally and in software, which is
useful background before extending the telemetry-definition parser.

## Known issues / gotchas

- Odin's `fmt.println` does **not** do printf-style `%s`/`%c` substitution the way
  `fmt.printf`/`fmt.printfln` do. `parse_config_file` was fixed to use `fmt.printfln` for this
  reason — if you add more token-printing calls, use `fmt.printfln`, not `fmt.println`, when
  interpolating values.
- A test suite now exists (`src/main_test.odin`, using Odin's built-in `testing` package) but
  only covers the pure helper `is_ascii_letter` so far — `parse_config_file` itself isn't
  covered because it only prints tokens rather than returning a structured value. If you extend
  the parser, prefer having it return data (a token/packet list) so tests can assert on it
  instead of only checking printed output.

## Conventions

- Odin package `main`, procedures in `snake_case`, types in `PascalCase` (see `TokenState`
  enum in `main.odin`) — follow existing style rather than introducing a different convention.
- Keep the raylib UI code commented-out block in sync conceptually if you extend the parser
  output — the eventual goal is feeding parsed telemetry definitions into that rendering loop.
