# Lessons for building something better than COSMOS v4

The other docs describe COSMOS v4 as it is. This one is deliberately opinionated: specific,
sourced pain points in v4's design, what Ball/OpenC3's own v5 rewrite chose to change (and
didn't), and concrete implications for Solaris. Treat this as a running list to revisit as
`src/main.odin` grows past a tokenizer.

## 1. The bit-offset model has a documented, confusing special case

`cosmos-config-format.md` states the general rule cleanly: bit offset is measured from the MSB
of the packet, negative counts from the end. But for **`LITTLE_ENDIAN` items narrower than a
byte and not byte-aligned** (bitfields), COSMOS v4/OpenC3 requires the offset to be computed in
*big-endian bit space* regardless of the item's declared endianness — i.e. the same field's
`bit_offset` means something different depending on whether it happens to be byte-aligned or
not. OpenC3's own worked example (a 3-field C bitfield struct: 4+8+4 bits, `LITTLE_ENDIAN`)
requires defining it as `ITEM A 4 4 UINT`, `ITEM B 12 8 UINT`, `ITEM C 8 4 UINT` — offsets that
don't match reading the struct fields in order, because each is really "MSB position after an
implicit byte-swap." The docs also flag that `APPEND_ITEM` **does not work** for little-endian
bitfields at all, and recommend figuring out the right offset empirically via a raw-bytes
viewer rather than by calculation.

**Implication for Solaris**: this is a real, sharp-edged wart worth not inheriting. A cleaner
model: pick *one* bit-numbering convention that's identical regardless of item endianness (e.g.
always "offset from the start of the packet, in the item's own byte order"), and make the
parser compute physical byte/bit positions from `(byte_order, bit_offset, bit_size)` internally
rather than asking the config author to pre-swap. This is exactly the kind of thing worth a unit
test (Odin's `testing` package, per `CLAUDE.md`) once `src/main.odin` starts doing bit-packing —
a little-endian bitfield test case modeled on OpenC3's own example is a good first fixture.

Source: [Little Endian Bitfields (OpenC3 docs)](https://docs.openc3.com/docs/guides/little-endian-bitfields)

## 2. Everything is pull, nothing is push

Across the GUI tools (`cosmos-screens.md`'s `SCREEN width height POLLING_PERIOD`) and the API
(`cosmos-api.md`'s "subscribe" calls that still require polling a `get_*_event` drain method),
v4 has no server-initiated push. A screen redraws on a timer it owns, not because a value
changed. This means:
- Static/unchanging values still cost a round trip every poll period.
- Fast-changing values are only as fresh as the poll period, with no way to get "next change,
  whenever that is" cheaply.
- Every additional open screen/tool is N more independent polling loops hitting the same
  server.

**Implication for Solaris**: if Solaris ever grows a client/server split (a natural fit for
"server owns the hardware link, multiple viewers attach," per `cosmos-overview.md`'s functional
model), prefer a subscribe-and-get-pushed-to design for the transport — a change-notification
stream per subscribed item/packet, not a per-widget timer. This is cheap to get right early and
expensive to retrofit later; COSMOS v5 (below) still didn't fully solve this at the API layer,
it just moved the streaming onto Redis/Valkey streams internally.

## 3. Config-embedded scripting language makes the format non-declarative

Screen files aren't purely data — `BUTTON 'Start' 'cmd("INST COLLECT with TYPE NORMAL")'` and
canvas conditional widgets embed live Ruby strings inline. A truly declarative parser can
tokenize and structure a screen file, but can't fully *interpret* it without an embedded Ruby
(or Ruby-workalike) evaluator, since arbitrary code can appear as a widget argument.

**Implication for Solaris**: keep telemetry/command *definitions* (what `tlm.txt` already is)
strictly data — no code embedding — and if/when a "screen" concept is added, prefer expressing
the small set of things buttons/conditionals actually need (send a specific command with fixed
params, compare an item to a constant) as structured data too, reserving a real scripting hook
(if ever needed) for something explicitly and narrowly scoped, not string-eval'd Ruby dropped
into a widget's third argument.

## 4. Binary logs are append-only and not seekable

`cosmos-architecture.md` already notes logs must be parsed from the start because packets are
variable-length with no index. The API's replay engine (`cosmos-api.md`) fakes seekability
(`replay_move_index`) on top of that by doing the linear scan internally — meaning "jump to
timestamp X" in the tooling is still O(n) in log size under the hood, just hidden from the
caller.

**Implication for Solaris**: if Solaris ever writes its own log format, a small periodic index
(e.g. every N packets or every N seconds, record file offset + timestamp) costs almost nothing
to maintain at write time and turns "jump to timestamp" into an actual seek instead of a
disguised scan. This is a one-way-door decision worth making before any log format ships, since
old logs won't retroactively gain an index.

## 5. Ruby's dynamism bought flexibility (Gem-based custom interfaces/conversions written in
the host language, loaded and run in-process) at a real perf and robustness cost

- Custom interfaces are required to guard their own I/O because the server runs with
  `Thread.abort_on_exception = true` — an uncaught exception in *any* one interface's thread can
  kill the whole CmdTlmServer process, including every other target's live connection
  (`cosmos-architecture.md`). That's a single-process blast radius problem: one badly-behaved
  target's interface code can take down monitoring for every other target.
- COSMOS shipped C extensions for hot paths (`BallAerospace/COSMOS` issue #223 references
  "Ruby C Extensions" specifically for packet handling, needing GC-safety fixes) — i.e. pure
  Ruby wasn't fast enough for its own core packet-parsing loop and needed a native-code escape
  hatch, maintained as a second implementation of the same logic.

**Implication for Solaris**: writing the parser/packet-unpacking core in Odin (compiled, no GC
pauses, no need for a "fast path" escape hatch in a different language) sidesteps this class of
problem entirely — but the *process isolation* lesson still applies even in a compiled language:
if Solaris ever owns multiple live target connections in one process, one target's
interface/protocol code panicking or blocking shouldn't be able to take down every other
target's connection. Worth deciding per-target isolation (separate threads at minimum, separate
processes if going further) deliberately rather than by default.

## 6. v5's actual fix was containerization + a message bus, not a language rewrite

OpenC3 COSMOS v5/6 kept the Ruby core but rebuilt everything else: nine-plus containerized
services (`cmd-tlm-api`, `script-runner-api`, `operator`, a Vue.js/Vuetify web frontend replacing
the old Qt desktop GUIs), Redis/Valkey for both the current-value table and real-time streaming,
QuestDB for time-series history, S3-compatible object storage for raw logs, and treats each
target as an independently-versioned **plugin** rather than a folder colocated in one project
tree. Migrating from v4 to v5 required a dedicated migration tool and a full rewrite of any
custom GUI tool (v4's Qt-based tools have no v5 equivalent).

**Implication for Solaris**: this validates two structural choices distinct from "which
language": (a) decoupling *definitions* (what `tlm.txt` is) from *deployment* so a target's
config can be versioned/shared independently of any one project — already naturally true of
`examples/simple_tlm/` living outside `src/`; (b) picking a transport for live data (v5 chose a
stream-based bus) early, since it's the piece that's hardest to retrofit and most load-bearing
for the "many simultaneous viewers, one hardware link" goal. Full containerized-microservice
architecture is very likely overkill for Solaris's actual scale (a bench/lab telemetry viewer,
not a multi-tenant cloud product) — the lesson to take is "decouple the pieces that need
independent lifecycles," not "adopt nine Docker services."

## Sources

- [Little Endian Bitfields (OpenC3 docs)](https://docs.openc3.com/docs/guides/little-endian-bitfields)
- [OpenC3 COSMOS Architecture](https://docs.openc3.com/docs/getting-started/architecture)
- [Upgrading (v4 → v5, OpenC3 docs)](https://docs.openc3.com/docs/getting-started/upgrading)
- [C Extension Improvements, BallAerospace/COSMOS#223](https://github.com/BallAerospace/COSMOS/issues/223)
- `cosmos-architecture.md`, `cosmos-api.md`, `cosmos-screens.md` in this repo (for the v4 facts
  referenced above)
