---
name: odin-best-practices
description: Idiomatic Odin language conventions — naming, error signaling without exceptions, explicit allocators, slices vs. dynamic arrays, testing with core:testing, and package/file layout. Use this whenever writing, reviewing, or planning Odin (.odin) code in this repo, or any time a change to src/*.odin is being designed — not just when the user says "Odin" explicitly. Also consult it when deciding how to structure a new Odin procedure's signature, how to represent an error, or whether something needs its own package/file.
---

# Odin best practices

Odin is not object-oriented and has no exceptions — code that tries to import patterns from
those paradigms (classes with inheritance, throw/catch, RAII destructors) fights the language.
Write Odin the way its standard library (`core:`) is written, and match this repo's existing
style in `src/main.odin`/`src/main_test.odin` rather than introducing a different convention.

## Naming

- Packages: short, lowercase, no underscores if avoidable.
- Types: `PascalCase` (`TokenType`, `TlmPacketDef`).
- Procedures and variables: `snake_case` (`grab_token`, `parse_config_file`).
- Constants: `SCREAMING_CASE` (`MAX_KEYWORD_PARAMS`).
- Enum members: `PascalCase` for a `TokenType`-style closed set describing *what something is*
  (this repo already mixes conventions here — `TokenType.NONE` is screaming-case while newer
  code should prefer `PascalCase` like `.Plain`/`.Id`/`.Array`; don't "fix" existing enums in an
  unrelated change, but use `PascalCase` for anything new).

## Error signaling — no exceptions, ever

Odin has no `throw`/`catch`. Every fallible procedure returns its error explicitly as an extra
return value:

```odin
// Boolean ok, when there's exactly one failure mode worth naming:
grab_until :: proc(text: string, idx: int, needle: string) -> (found: bool, end_idx: int)

// An Error enum, when the caller needs to distinguish *why* it failed:
Parse_Error :: enum { None, Unterminated_String, Invalid_Number_Char }
parse_item :: proc(...) -> (item: TlmItemDef, err: Parse_Error)
```

Prefer this over `os.exit()` inside anything that isn't the top-level CLI entry point.
`grab_token`'s current use of `os.exit(32)` on a malformed string/number (see `CLAUDE.md`'s
"Known issues") is a known wart, not a pattern to copy into new code — it makes the function
untestable for its own error paths (a test can't observe "the process exited," only crash
alongside it). New parsing/validation code should return an error value instead, even if
`main()`'s top-level loop chooses to call `os.exit` after inspecting it.

Use Odin's `or_return`/`or_else` to propagate errors tersely once a procedure returns
`(T, bool)` or `(T, Error)`:

```odin
item := parse_item(text, idx) or_return
```

## Allocators are explicit, not ambient

Every allocation goes through `context.allocator` (or a caller-supplied allocator parameter) —
never assume a global heap the way `malloc`/`new` implies in C. When a procedure allocates and
hands ownership to the caller, say so in how it's used (mirror the existing
`data, err := os.read_entire_file(...)` + `defer delete(data, context.allocator)` pattern in
`parse_config_file`). When a procedure only *reads* from data the caller owns, take a `string`/
slice parameter and allocate nothing — most of the token/keyword layer (`grab_token`,
`grab_keyword`) already does this correctly by returning index ranges (`TokenRef`) into the
caller's `text` rather than copying substrings; keep extending that pattern rather than having
new code return owned strings where an index range would do.

## Slices, fixed arrays, and dynamic arrays — pick deliberately

- A **fixed-size array** (`[16]TokenRef`, as `Keyword.params` already does) when there's a real,
  known upper bound and you want zero allocation — this is the right default for anything
  per-line/per-call-frame sized like COSMOS keyword params.
- A **slice** (`[]T`) for "some data I don't own or am only viewing" — function parameters
  should almost always be slices, not `[dynamic]T` or `^[dynamic]T`, so callers aren't forced
  into a specific growable-storage choice.
- A **dynamic array** (`[dynamic]T`) only when the count is genuinely unbounded and known only
  at runtime (e.g. "however many packet definitions this config file happens to define") — and
  even then, prefer building it once and converting to `[]T` for anything downstream that only
  reads it, so read-only consumers can't accidentally `append` to storage they don't own.

## Testing

Use `core:testing` (`@(test)` procedures, `testing.expect`/`expect_value`/`expectf`), run via
`./bin/odin/odin.exe test ./src`. This repo's existing tests are the reference pattern: one test
per behavior, named `test_<function>_<scenario>`, asserting on *returned values* — which is only
possible because the functions under test return data instead of printing
(`fmt.println`/`fmt.printfln`) it. This is the single biggest thing to get right when writing new
procedures: if a procedure's only observable effect is a print statement, it cannot be
unit-tested, only smoke-tested by running the whole program. Design for the former.

## Package/file layout

Odin idiom favors few, flat packages over deep hierarchies — this is closer to Go's philosophy
than Java's. Don't split into multiple packages just because a concern feels "separate"; a
single package with multiple files (`src/main.odin`, `src/parser.odin`, `src/tlm_db.odin`, ...)
is the right level of separation for a project this size. Reach for a second package only when
something is genuinely reusable outside this program, not as an organizational device.

## Miscellaneous conventions worth following

- `defer` for cleanup right next to the acquisition (`data, err := os.read_entire_file(...)` /
  `defer delete(data, context.allocator)`), not gathered at the end of a function — this keeps
  the acquire/release pair visually adjacent and impossible to forget when editing nearby code.
- Prefer `#partial switch` only when a switch is genuinely meant to handle a subset of an enum
  and ignore the rest intentionally (as `grab_token`'s inner state switch does) — an *exhaustive*
  switch (no `#partial`) is a compile-time check that a new enum variant can't silently fall
  through unhandled, so default to exhaustive and only opt out deliberately.
- Avoid `using` on structs in new code unless it measurably reduces noise at a call site — it
  hides which struct a field actually came from when reading unfamiliar code, which fights
  debuggability (see the `casey-muratori-style` skill).
- `distinct` a type (like `TlmId :: distinct int`) whenever a plain `int`/`string` is being used
  as an opaque handle rather than a number/text to do arithmetic or string-ops on — it turns
  "accidentally passed a raw array index where a `TlmId` was expected" into a compile error
  instead of a runtime bug.
