---
name: casey-muratori-style
description: Data-oriented, minimal-abstraction coding philosophy in the style of Casey Muratori / Handmade Hero — flat control flow, abstract only after real duplication appears, plain data over encapsulated objects, explicit allocation, debuggability as a first-class concern. Use this whenever designing a new data structure, module boundary, or API surface in this repo — not just when the user names Casey Muratori — especially before introducing an interface/abstraction layer, a new file/package split, or a generic/reusable version of something that currently has only one caller.
---

# Casey Muratori-style coding philosophy

This is a design philosophy, not a syntax guide (pair with `odin-best-practices` for Odin
specifics). The throughline: code should be easy to read top-to-bottom, easy to step through in
a debugger, and shaped by what the data actually looks like — not by anticipated future
flexibility that hasn't been needed yet.

## Abstract after duplication shows up, not before

The single most important rule. Don't write a generic `Interface`/`Protocol` abstraction (see
`cosmos-architecture.md`'s Ruby-class-per-interface model as an example of the *kind* of thing
to avoid pre-building) until there are at least two concrete, real call sites that need it and
the shared shape between them is obvious. A speculative abstraction built for "the second thing
that will probably show up later" almost always guesses the wrong shape, and now there's an
abstraction layer to unwind *and* the real second use case to accommodate. Concretely in this
project: the telemetry-database plan's event notification (milestone 5) is deliberately a plain
ring buffer, not a subscribe/callback registry — because there is exactly one known consumer
right now. Build the callback registry when a second, actually-different consumer exists, not
before.

## Prefer flat, linear control flow over many tiny indirected functions

A function that does five sequential things in five lines, each line's purpose clear from
reading it, is often *more* readable than the same logic split into five one-line helper
functions each called once — especially when tracing execution in a debugger, where every extra
function is another frame to step into and another name to remember. This doesn't mean "never
factor out a helper" — factor out a helper when it's called from more than one place, or when a
single piece of logic is genuinely a distinct, nameable *concept* worth a name of its own (like
`grab_token` being its own thing rather than inlined into `grab_keyword`). It means don't factor
out a helper purely because a function "feels long" — line count alone isn't a reason to split
something whose control flow reads clearly straight through.

## Plain data over encapsulated objects

A struct's fields should be visible and directly settable by code that legitimately owns that
struct — not hidden behind getter/setter procedures that exist only to look encapsulated. In
`§3`'s data model (see `docs/telemetry-database-plan.md`), `TlmPacketDef`/`TlmItemDef` are plain
structs whose fields any procedure in the package can read and write directly; there's no
`tlm_item_get_name(item)` wrapping a trivial field read. Encapsulation earns its keep when it's
actually enforcing an invariant (e.g. "this field must only change through a procedure that also
updates that other field") — not as a default reflex.

## Prefer a tag + plain fields over a union/interface, until the payload actually needs it

`TlmItemKind` (an enum) plus a few extra fields sitting unused for the wrong variant is simpler
to read, debug, and pattern-match on than a real tagged `union`, as long as the wasted memory
per unused field is trivial (an `int` and an `i64` sitting next to each other costs nothing
real). Reach for an actual `union` or a v-table-style interface only once the per-variant payload
is large or heterogeneous enough that flattening it would be a genuine waste — don't reach for
it by default because it "feels more correct" for a tagged-variant situation.

## Explicit, visible allocation — no hidden cost

Every allocation should be visible at its call site (see `odin-best-practices` on
`context.allocator`) and, on any path that runs per-packet/per-frame, avoided entirely if
possible in favor of reusing a fixed buffer. "Don't pessimize" is the operative rule: it's fine
to not micro-optimize prematurely, but don't structure code so that an obviously avoidable
allocation happens on every single packet ingested — that's not premature optimization, it's
just needless cost with no offsetting benefit. Milestone 3 of the telemetry-database plan
(timestamped ingestion) is written to make exactly this distinction: identify + notify allocate
nothing; only the owned copy of the raw packet bytes allocates, because that one genuinely has
to outlive the call.

## Debuggability is a first-class design constraint

Prefer designs where, mid-execution in a debugger, you can look at a struct's fields and
immediately understand the current state — no reconstructing state from a chain of closures, no
guessing which of several possible dynamic-dispatch targets actually ran. This is part of why
`odin-best-practices` prefers exhaustive `switch` over dynamic dispatch, and why this skill
prefers flat control flow: both make "what is this code doing right now" answerable by reading,
not by running a debugger session and hoping.

## Comments explain *why*, not *what*

A comment restating what the next line obviously does is noise. A comment is worth writing when
it captures something the code can't: why a bound is what it is, why a seemingly-simpler
alternative doesn't work, a constraint from the spec that isn't visible locally. The existing
`grab_token`/`grab_keyword` comments in `src/main.odin` are the reference — e.g. the comment on
`grab_token`'s EOF handling explaining *why* `idx_start` gets special-cased for `TokenType.NONE`
at EOF, not what the two-line `if` does.
