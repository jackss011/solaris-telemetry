# Telemetry database — implementation plan

This is a concrete plan for the "telemetry database" sketched in `docs/TODO.md` on the unmerged
`tlm-parsing` branch (not yet on `main` at time of writing). That branch's `docs/TODO.md` reads:

> Based on [Cosmos Telemetry v4](https://ballaerospace.github.io/cosmos-website/docs/v4/telemetry)
> telemetry packet arrives as `[]u8`
> - timestamp it
> - map it to a `tlm_id` (opaque)
> - notify `tlm_id` on event_bus
> - from `tlm_id`, into:
>   - name, other base def
>   - enumerate `tlm_items`

Its `src/main.odin` also sketched the shape of the data (`TlmDef`, `TlmItemType`,
`TlmItemArray`, `TlmItemId`, `TlmItemSuper`, `TlmItemDef`) — but using C-style
`struct Name { ... }`/`enum Name { ... }`/`union Name { ... }` syntax, which **is not valid
Odin** (Odin's declaration syntax is `Name :: struct { ... }`, see "Data model" below) — so that
branch doesn't currently compile. This plan keeps the sketch's intent and field vocabulary but
fixes the syntax and fills in the parts the TODO left implicit.

Style guides for the implementation are pulled out into two standalone skills so they apply to
this work (and any future Odin work in this repo) automatically rather than living only in this
doc: `.claude/skills/odin-best-practices/` and `.claude/skills/casey-muratori-style/`. Read
those for the *why* behind the choices below; this doc focuses on the *what*.

## 1. Scope

Two genuinely different things are both called "the parser" informally, and this plan treats
them as two layers:

1. **Definition layer** (static, load-time): turn the existing `grab_keyword` token stream
   (`src/main.odin`, see `CLAUDE.md`'s Architecture section) into typed `TlmPacketDef`/
   `TlmItemDef` values — i.e. actually interpret `TELEMETRY`/`APPEND_ITEM`/`LIMITS`/`STATE`/etc.
   instead of just printing them. **This does not exist yet** and is a hard prerequisite for
   everything below — there is no `tlm_id` to map a packet to until packet definitions exist as
   data. `docs/cosmos-config-format.md`'s keyword tables are the reference for what each keyword
   means.
2. **Telemetry database** (dynamic, runtime): given a raw `[]u8` packet and a timestamp, resolve
   it against the definitions from (1), assign/look up its `tlm_id`, store it, and notify
   whoever's interested. This is what `docs/TODO.md` is actually describing.

This plan is mostly about (2), but (1) has to happen first, so it's included as milestone 0.

## 2. Design principles (summary — see the two skills for the full reasoning)

- **No hidden control flow.** No exceptions (Odin doesn't have them anyway), no virtual
  dispatch for item types — a `TlmItemType` enum + explicit `switch` does the job COSMOS uses
  Ruby duck-typing for.
- **Flat data over deep abstraction.** A packet registry is an array of `TlmPacketDef`, not a
  tree of interface-implementing objects. Don't introduce a generic "Interface"/"Protocol"
  abstraction layer (`cosmos-architecture.md`'s Ruby-class-per-interface model) until there are
  two concrete things that need it.
- **Explicit ownership, no hidden allocation.** Ingesting a packet should not allocate on the
  hot path by default — reuse buffers, prefer fixed-capacity arrays sized like
  `MAX_KEYWORD_PARAMS` already is in the existing parser, and make any allocator use explicit
  (`context.allocator` passed or defaulted, never silently global).
- **Return data, don't print it.** Exactly the lesson `CLAUDE.md` already draws from
  `grab_token`/`grab_keyword` vs. `parse_config_file`: every new procedure here returns a value
  a test can assert on.
- **One bit-numbering convention, not COSMOS's.** `docs/cosmos-lessons.md` point #1 flags
  COSMOS's little-endian-bitfield special case as a wart worth not inheriting. Item extraction
  in this plan computes physical bit position from `(byte_order, bit_offset, bit_size)`
  internally — the config author (and this code) never pre-swaps.
- **Push, not poll, for notification** — `docs/cosmos-lessons.md` point #2. But start with the
  simplest possible mechanism (see milestone 5), not a generic pub/sub framework.

## 3. Data model

Fixing the `tlm-parsing` sketch's syntax and filling gaps. All types live in package `main`
(see "Module layout" — no sub-packages yet):

```odin
// ---- Definition layer (built once, at config-load time) ----

TlmItemType :: enum {
    None,
    INT, UINT, FLOAT, STRING, BLOCK, DERIVED,
}

// Discriminates an item's role without a v-table: a plain item, an id item (used to identify
// which packet definition a chunk of bytes matches — cosmos-config-format.md's ID_ITEM), or an
// array item. Tag lives in TlmItemDef.kind; this holds only the kind-specific extra data.
TlmItemKind :: enum {
    Plain,
    Id,
    Array,
}

TlmItemDef :: struct {
    name:          string,
    bit_offset:    int,   // from start of packet; negative = from end (cosmos-config-format.md)
    bit_size:      int,
    type:          TlmItemType,
    little_endian: bool,
    desc:          string,

    kind:          TlmItemKind,
    id_value:      i64,   // valid when kind == .Id
    array_count:   int,   // valid when kind == .Array
}

TlmPacketDef :: struct {
    target:        string,
    name:          string,
    little_endian: bool,
    desc:          string,
    items:         []TlmItemDef, // allocated once when the definition is built, then immutable
    id_item_idxs:  []int,        // indices into items[] that are .Id — for packet identification
}

// Opaque handle, per docs/TODO.md ("map it to a tlm_id (opaque)"). `distinct` so it can't be
// silently mixed up with a plain int or an array index for something else.
TlmId :: distinct int
TLM_ID_INVALID :: TlmId(-1)

// ---- Runtime layer ----

TlmPacket :: struct {
    id:        TlmId,
    timestamp: time.Time,
    raw:       []u8, // owned copy of the packet bytes
}
```

`TlmItemSuper` (a `union{TlmItemId, TlmItemArray}` in the original sketch) is deliberately
replaced by a tag (`TlmItemKind`) plus inline fields rather than a union: a plain enum-tagged
struct is simpler to switch on, easier to inspect in a debugger, and avoids Odin union access
patterns (`.(T)` type assertions) for what's really a 3-way flag. Only reach for a real
`union` when the payload per kind is large/heterogeneous enough that flattening wastes real
memory — that's not the case here (an `i64` and an `int` cost nothing extra sitting side by
side).

## 4. Module layout

The project is one file today (`src/main.odin`, ~360 lines). Don't jump to a multi-package
layout (Odin idiom leans toward few, flat packages; see `odin-best-practices` skill) — but do
split *files* within package `main` once this grows, since three concerns are genuinely
separable:

- `src/main.odin` — entry point only.
- `src/parser.odin` — move the existing `grab_token`/`grab_keyword`/`grab_until`/`TokenRef`/
  `Keyword` code here unchanged (pure rename/move, no behavior change — do this as its own
  first commit so it's a trivial diff to review).
- `src/tlm_def.odin` — the definition layer: `TlmPacketDef`/`TlmItemDef`/`TlmItemType`/
  `TlmItemKind` from §3, plus the keyword-stream → definitions builder (milestone 0).
- `src/tlm_db.odin` — the runtime layer: `TlmId`, `TlmPacket`, the registry, ingestion, and
  notification (milestones 1–5).

`src/main_test.odin` stays as-is for the parser; add `src/tlm_def_test.odin` and
`src/tlm_db_test.odin` alongside their respective files, matching the existing one-test-file-
per-source-file pattern.

## 5. Milestones

Ordered; each should land as its own commit with its own tests, mirroring how the existing
`grab_token`/`grab_keyword`/`grab_until` layers were each built and tested independently.

**0. Definition builder.** `build_packet_defs(text: string) -> (defs: []TlmPacketDef, ok: bool)`
   (or an `Error` enum return instead of bare `ok` — see the Odin skill on error signaling)
   drives `grab_keyword` in a loop and interprets `TELEMETRY` (open a packet), `APPEND_ITEM`/
   `APPEND_ID_ITEM`/`ITEM`/`ID_ITEM` (append/insert an item, tracking running bit offset for the
   `APPEND_*` family per `cosmos-config-format.md`), and item modifiers (`UNITS`,
   `FORMAT_STRING`, `LIMITS`, `STATE`, `DESCRIPTION`) attaching to *the most recently defined
   item* — exactly the semantics `cosmos-config-format.md`'s "Item modifiers" section documents.
   `LIMITS`/`STATE`/`UNITS`/`FORMAT_STRING` data isn't in the §3 struct yet; add fields (or a
   side-table keyed by item index) as this milestone actually needs them — don't pre-build
   fields nothing reads yet. Test against `examples/simple_tlm/tlm.txt` directly: assert the
   resulting `TlmPacketDef` has the right item count, names, offsets, and id values.

**1. Registry.** `TlmRegistry :: struct { defs: []TlmPacketDef }` plus
   `registry_find_by_name(r: ^TlmRegistry, target, name: string) -> (TlmId, bool)`. `TlmId` is
   just the index into `defs` — no separate id-allocation scheme needed, since the registry is
   built once and is immutable after load.

**2. Packet identification.** `registry_identify(r: ^TlmRegistry, raw: []u8) -> (TlmId, bool)` —
   walk each `TlmPacketDef`'s `id_item_idxs`, extract the raw bytes at each id item's bit
   position, and compare against `id_value`. First full match wins; a packet matching zero
   definitions returns `ok = false` (COSMOS's "catch-all" packet concept is explicitly deferred —
   flag it as a follow-up, don't build it speculatively).

**3. Timestamped ingestion.** `tlm_db_ingest(db: ^TlmDatabase, raw: []u8, timestamp: time.Time) -> (TlmId, bool)`
   — identify (milestone 2), copy `raw` into a `TlmPacket`, store it (milestone 4), notify
   (milestone 5). Timestamp is a caller-supplied parameter, not `time.now()` read internally —
   keeps the function pure/testable (no hidden clock dependency), matching how `grab_token`
   takes `text`/`idx` instead of reading global state.

**4. Latest-value storage.** `latest: []TlmPacket` on `TlmDatabase`, indexed directly by
   `int(TlmId)` — a flat array parallel to the registry's `defs`, not a `map[TlmId]TlmPacket`.
   Since `TlmId` is a dense array index by construction (milestone 1), a map only adds hashing
   overhead and pointer-chasing for no benefit. History-over-time (not just latest value) is
   explicitly out of scope for this plan — a follow-up once "latest value" is working end to
   end.

**5. Notification.** Start with the simplest thing that satisfies "notify tlm_id on event_bus":
   a fixed-capacity ring buffer of `TlmId` (+ generation counter) on `TlmDatabase`, written by
   `tlm_db_ingest`, drained by callers polling `tlm_db_poll_events`. This is *push from the
   producer's perspective* (ingest writes immediately, doesn't wait for a poll to decide
   anything) even though consumers still drain it — a deliberate middle ground, not full
   callback-based push, because there's exactly one consumer shape needed right now (a future
   UI redraw loop) and no evidence yet that more are coming. Revisit only when a second, actually
   different consumer shows up — don't build a generic subscribe/callback registry speculatively
   (see the Muratori-style skill on abstraction timing).

**6. Item value extraction.** `tlm_item_read(item: TlmItemDef, raw: []u8) -> (value: TlmValue, ok: bool)`
   where `TlmValue` is a small tagged union over the `TlmItemType` variants. This is where the
   bit-offset/endianness computation from §2's "one bit-numbering convention" principle actually
   gets implemented — write this milestone's tests directly from
   `docs/cosmos-lessons.md`'s point #1 (a little-endian bitfield case modeled on OpenC3's own
   worked example) since that's the sharpest edge case in the whole format.

Each milestone's procedures take their inputs as parameters and return values — no procedure in
this list reads or writes a package-level global. `TlmDatabase` (holding the registry + latest
values + event ring buffer) is threaded through explicitly by the caller.

## 6. Explicitly out of scope for this plan

- Multi-threaded ingestion / locking. Milestone 3's `tlm_db_ingest` is single-threaded; revisit
  only once there's a real second thread (e.g. a network interface reader) that needs it.
- Historical/logged storage (`cosmos-architecture.md`'s binary log format) — latest-value only.
- The `Override`/`normalize_tlm` style value-pinning from `cosmos-api.md` — no API surface at all
  yet, this plan is the in-process data model underneath one.
- Command (outgoing) packets — telemetry (incoming) only, matching this repo's name.

## 7. Open questions

- Ring buffer capacity for milestone 5, and what happens on overflow (drop oldest vs. block) —
  needs a concrete consumer (the eventual raylib UI loop) to answer with real numbers rather
  than guessing.
- Where `LIMITS`/`STATE`/`UNITS`/`FORMAT_STRING` data lives on `TlmItemDef` — inline fields
  (simple, some waste for items that don't use them) vs. a side-table keyed by item index
  (denser, one more indirection). Milestone 0 should decide this from what it actually needs to
  store, not in advance.
- Whether `build_packet_defs` (milestone 0) should live on top of the existing `grab_keyword`
  stream as-is, or whether the keyword layer needs new capability first (e.g. `SELECT_TELEMETRY`/
  `SELECT_ITEM` reopening a prior definition — already tokenizes fine per the spec-derived tests,
  but nothing consumes that semantic yet).
