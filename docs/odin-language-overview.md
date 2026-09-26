# Odin language overview

A working reference for Odin's core language features, written for this codebase rather than
as a full language spec. Based on the [official Odin overview](https://odin-lang.org/docs/overview/)
and [odin-lang/Odin](https://github.com/odin-lang/Odin) on GitHub (see those for the exhaustive,
authoritative version — this doc pulls out what's relevant to `src/main.odin` and links back to
it as live examples). See also `odin-best-practices` (skill) for conventions specific to how this
repo should be written, and `casey-muratori-style` (skill) for the data-oriented design philosophy
behind it.

## Packages and declarations

Every file starts with `package name`; all `.odin` files in a directory belong to the same
package (this repo is a single `package main` — see `src/main.odin:1`). There's no per-file
export syntax — visibility is per-package (exported by default, `foo :: proc() {}`) vs.
file-private (`@(private="file")`).

Declarations use `:=` (mutable, type inferred), `: T =` (mutable, explicit type), or `::`
(constant — a compile-time value, not just `const`). This trips people up coming from C: a
type declaration and a procedure declaration look identical:

```odin
GRID_PX :: 64                          // untyped integer constant
TokenType :: enum { NONE, IDENT }      // constant binding to a type
grab_token :: proc(text: string, idx: int) -> TokenRef { ... }  // constant binding to a procedure
```

All three are "bind this name to this compile-time value" — Odin doesn't distinguish types,
procedures, and constants syntactically the way `struct`/`fn`/`const` keywords do in other
languages. This is *why* `struct Foo { ... }` and `enum Bar { ... }` (C order) are invalid Odin —
the name always comes first, `::`, then the kind:

```odin
Box :: struct { x, y, w, h: f32 }      // see src/main.odin's Box type
TlmItemType :: enum { None, INT, UINT, FLOAT, STRING, BLOCK, DERIVED }
TlmItemSuper :: union { TlmItemId, TlmItemArray }
```

Untyped constants (like `GRID_PX` above) convert implicitly wherever they're used — `f32`,
`i32`, `int`, whatever the context needs — which is why passing `GRID_PX*GRID_INIT_W` straight
into `rl.InitWindow`'s `i32` parameters works without a cast, but a *typed* `:=` variable of
the wrong width (e.g. an `int` where raylib wants `i32`) needs an explicit `i32(...)` cast.

## Control flow

`if`, `for`, and `switch` don't use parens around the condition, but always use braces —
there's no bare single-statement form. `for` is the *only* loop keyword (no `while`/`do`), with
four shapes:

```odin
for {}                                 // infinite loop
for cond {}                            // while-loop
for i := 0; i < n; i += 1 {}           // C-style three-part
for x in slice {}                      // range-based (also works over: strings, maps, ints via 0..<n)
```

The idiomatic Odin form for counting loops is range-based (see `src/main.odin`'s grid-drawing
loop: `for iw in 0..<grid_w`), not the C-style three-part form — that's why the earlier
C-style-with-`int`-prefix draft in this file (`for int iw := 0; ...; ih++`) was wrong twice
over: Odin's for-init doesn't take a type before the variable, and there's no `++`/`--`
operator at all, only `+= 1`.

`switch` doesn't fall through by default (each case implicitly breaks) and can switch on types
or ranges, not just values. `#partial switch` (used throughout `grab_token`/`grab_keyword` in
this file) tells the compiler "I know this doesn't cover every enum case, that's intentional" —
without it, switching on an enum requires exhaustive cases or a compile error.

`defer` runs its statement when the enclosing scope exits, LIFO — used throughout this file for
paired setup/teardown (`rl.InitWindow` / `defer rl.CloseWindow()`, `rl.LoadFontEx` /
`defer rl.UnloadFont(font)`).

## Procedures

Procedures can return multiple values, which is Odin's primary substitute for both tuples and
exceptions:

```odin
box_end :: proc(b: Box) -> (f32, f32) {
    return b.x + b.w, b.y + b.h
}
window_w, window_h := box_end(grid)    // must destructure into separate variables —
                                        // Odin does not splat a multi-return call into
                                        // a composite literal like Box{0, 0, box_end(grid)}
```

Named return values (`-> (keyword: Keyword, next_idx: int)`, as in `grab_keyword`) let you
`return` bare at the end and have it return whatever those named variables currently hold —
useful when a procedure has one loop building up a result across many exit points.

There's no exceptions or `try`/`catch`. The idiomatic error-signaling pattern is either a second
return value (`value, ok := ...` or `value, err := ...`), or — for genuinely unrecoverable
programmer errors, as opposed to expected failure — `assert()` / `panic()`, which is what this
file uses for `MAX_KEYWORD_PARAMS` overflow and malformed string/float tokens (see
`odin-best-practices` for when each is appropriate).

## Structs, enums, unions

- **Struct**: plain data, no methods, no inheritance. Fields have no defaults — a zero-valued
  struct just has each field at its type's zero value.
- **Enum**: `enum { A, B, C }`, backed by an integer (`c.int` in many vendor bindings, `int` by
  default in plain Odin code) — see `TokenType`/`TlmItemType` in this file.
- **Union**: `union { A, B }` is a *tagged* union (unlike C) — it tracks which variant is active
  at runtime and a type-switch (`switch v in u { case A: ...; case B: ... }`) narrows it safely.
  This is what backs `TlmItemSuper :: union { TlmItemId, TlmItemArray }` — a telemetry item's
  bit position is described by *either* a fixed offset+id *or* an array descriptor, never both,
  and the union enforces that at the type level instead of a struct with unused fields.

## Arrays, slices, dynamic arrays

Three closely related but distinct types:

- **`[N]T`** — a fixed-size array, size baked into the type, lives inline (stack or wherever its
  owner lives), no allocation. This is what `Keyword.params: [MAX_KEYWORD_PARAMS]TokenRef` uses
  — a hard cap chosen deliberately to keep the token/keyword layer allocation-free (see
  `CLAUDE.md`'s "Known issues" on why exceeding `MAX_KEYWORD_PARAMS` asserts rather than growing).
- **`[]T`** — a slice: a `{data pointer, len}` *view* into an array/dynamic array/string's
  backing storage. Doesn't own memory, can't grow. `text[idx_start:idx_end]` (used everywhere in
  this file's token layer) produces a `string`, which is itself slice-shaped under the hood.
- **`[dynamic]T`** — a growable, heap-backed array: `{data pointer, len, cap, allocator}`.
  `append(&arr, x)` grows it geometrically (amortized O(1)); you own it and must `delete(arr)`
  (or free/reset the allocator backing it) since Odin has no garbage collector.

### Bounded/inline growable arrays — `[dynamic; N]T`

For a *bounded* growable array — capacity fixed and known at compile time, inline storage,
`[dynamic]T` ergonomics, but no heap allocation — Odin's current answer is
**`[dynamic; N]T`**: a fixed-capacity dynamic array. It behaves exactly like `[dynamic]T`
(`append`, `pop`, `unordered_remove`, `clear`, `len`, `cap`, ranging with `for`) but the backing
storage is inline (`[N]T`-shaped) rather than allocator-backed, and `append` past `N` simply
returns `0` elements-appended instead of growing or crashing:

```odin
items: [dynamic; 4]int
append(&items, 1, 2, 3, 4)   // ok, len=4 cap=4
n := append(&items, 5)       // n == 0 — silently refused, no growth, no allocation
```

This is exactly a "growable stack array": use it as a drop-in replacement anywhere you'd reach
for a hand-rolled `[N]T` + count field (like `Keyword.params`/`params_count` in this file) but
want `append`/`pop`-style ergonomics instead of manually indexing and bumping a counter.

Verified directly against this repo's vendored compiler (`bin/odin/odin.exe version` →
`dev-2026-09-nightly`) rather than assumed, since it's newer than most cached Odin knowledge.

There's also the older `core:container/small_array.Small_Array(N, T)` in the standard library,
providing the same fixed-inline-capacity idea via explicit `small_array.push_back`/`pop_back`/
etc. calls — **its own doc comment now says to prefer `[dynamic; N]T` instead** (see
`bin/odin/core/container/small_array/doc.odin`), so treat `Small_Array` as legacy/only relevant
when reading older Odin code.

## Maps

`map[K]V` is a built-in hash map — `m[key] = value`, `v, ok := m[key]`, `delete_key(&m, key)`,
`for k, v in m`. Not used yet in this codebase, but the natural fit once the parser needs to look
up items/packets by name rather than scanning a list.

## Allocators and `context`

Odin threads an implicit `context` through every procedure call, carrying `context.allocator`
(used by `make`, `new`, `append`, string concatenation, etc.) and `context.temp_allocator` (a
per-frame/per-scope arena, typically reset once per game loop iteration with
`free_all(context.temp_allocator)`). Passing an allocator explicitly (`make([dynamic]T, 0, cap,
my_allocator)`) is how you opt out of the default without a hidden global — consistent with this
project's general preference (per `casey-muratori-style`) for explicit, visible allocation over
hidden control flow.

## `using`

`using` on a struct field or import brings its fields/exports into the current scope directly —
e.g. `using b: Box` inside a procedure would let you write `x` instead of `b.x`. It's convenient
but can obscure where a name comes from; this codebase doesn't currently use it, and per
`odin-best-practices` it's worth being sparing with for that reason.

## Testing

`core:testing` (used in `src/main_test.odin`) provides `@(test)`-annotated procedures taking a
`^testing.T`, with `testing.expect`/`testing.expect_value` for assertions — run via
`odin test ./src` (see root `CLAUDE.md`, "Build & run"). This is why the token/keyword layer's
"return structured values instead of printing" discipline matters: it's what made that test
suite possible at all.
