# COSMOS command/telemetry definition format (deep reference)

This is the detailed keyword reference for the config language sampled in
[`examples/simple_tlm/tlm.txt`](../examples/simple_tlm/tlm.txt) and targeted by the parser in
[`src/main.odin`](../src/main.odin). See [`cosmos-overview.md`](./cosmos-overview.md) for why
this format exists and [`cosmos-architecture.md`](./cosmos-architecture.md) for where these
files live on disk (`config/targets/TARGET/cmd_tlm/*.txt`) and how they relate to the rest of
a COSMOS deployment. Everything below is COSMOS v4 (sources at the bottom).

Files are plain text, one keyword per line (leading whitespace is just for readability), and
are processed in filename order within a target's `cmd_tlm/` directory — so a file that
depends on definitions in another file is named to sort after it (a common pattern:
`tlm_override.txt`).

## Telemetry (packet definitions the target *sends*)

**`TELEMETRY <target> <packet-name> <endianness> ["description"]`**
Starts a new telemetry packet. Endianness is `BIG_ENDIAN` or `LITTLE_ENDIAN` and applies to
every item in the packet unless an item overrides it individually.

**`SELECT_TELEMETRY <target> <packet-name>`** — reopen an existing packet to add to/edit it
(this is how `tlm_override.txt`-style files work).

### Item keywords

Two families: explicit-offset (`ITEM`) and auto-offset (`APPEND_ITEM`), each with `ID_`
and `ARRAY_` variants. All of `tlm.txt` uses the `APPEND_*` family, which is the simpler
default — you never compute bit offsets by hand, COSMOS tracks the running position for you.

| Keyword | Parameters (in order) |
|---|---|
| `ITEM` | name, bit offset, bit size, data type, [description], [endianness] |
| `APPEND_ITEM` | name, bit size, data type, [description], [endianness] |
| `ID_ITEM` | name, bit offset, bit size, data type, **id value**, [description], [endianness] |
| `APPEND_ID_ITEM` | name, bit size, data type, **id value**, [description], [endianness] |
| `ARRAY_ITEM` | name, bit offset, item bit size, item data type, array bit size, [description], [endianness] |
| `APPEND_ARRAY_ITEM` | name, item bit size, item data type, array bit size, [description], [endianness] |
| `SELECT_ITEM` | item name — reopen an item to add modifiers below to it |
| `DELETE_ITEM` (4.4.1+) | item name — removes the definition; the byte space is *not* reclaimed unless something else fills it |

Notes:
- Bit offset is measured from the MSB; a negative offset means "from the end of the packet."
- **`ID_ITEM`/`APPEND_ID_ITEM`** are what let the server figure out *which* packet definition
  a chunk of incoming bytes matches — the id value is compared against the raw bytes at that
  position. `tlm.txt`'s `CCSDSAPID` (`APPEND_ID_ITEM ... 1 "CCSDS application process id"`,
  the `1` being the id value) is exactly this. A packet with no `ID_ITEM`s at all becomes a
  catch-all that matches anything not otherwise identified.
- Data types: `INT`, `UINT`, `FLOAT`, `STRING` (read stops at a null byte `0x00`), `BLOCK`
  (binary, reads through null bytes), `DERIVED` (see below).
- `DERIVED` items have bit size `0`/negative and no physical presence in the packet — their
  value comes entirely from a conversion (below). `tlm.txt`'s `DURATION` item
  (`ITEM DURATION 0 0 DERIVED ...` computing `COLLECTS * 0.5`) is this pattern.

### Item modifiers (apply to the most recently defined/selected item)

| Keyword | Meaning |
|---|---|
| `STATE <key> <value> [GREEN\|YELLOW\|RED]` | Map a raw numeric value to a display string, optionally colored. `tlm.txt`'s `COLLECT_TYPE`/`DEPLOYED` items use this for enum/boolean-style display. |
| `LIMITS <set> <persistence> <ENABLED\|DISABLED> <red-low> <yellow-low> <yellow-high> <red-high> [green-low] [green-high]` | Red/yellow/green thresholds. `persistence` = how many consecutive violating samples before the state actually changes (debouncing). `tlm.txt`'s `TEMP1` item (`LIMITS DEFAULT 3 ENABLED -10 -5 40 45 0 30`) needs 3 consecutive samples outside range before flagging, with green explicitly 0–30. |
| `LIMITS_RESPONSE <ruby-file> [args...]` | Custom code to run whenever this item's limits state changes. |
| `UNITS <full-name> <abbreviation>` | Display units, e.g. `UNITS "Volts" "V"`. |
| `FORMAT_STRING <printf-format>` | e.g. `"%0.3f"` on `tlm.txt`'s `VOLTAGE` item. |
| `DESCRIPTION <text>` | Override the item's description after the fact. |
| `META <name> [values...]` | Arbitrary metadata for custom tooling to key off of. |
| `OVERLAP` (4.4.1+) | Explicitly allow this item to overlap another's bits without a warning (intentional aliasing). |

### Conversions (item modifiers that transform the raw value before display)

- **`READ_CONVERSION <ruby-file> [args...]`** — arbitrary Ruby class conversion.
- **`POLY_READ_CONVERSION c0 [c1 c2 ...]`** — polynomial: `c0 + c1*x + c2*x^2 + ...`.
- **`SEG_POLY_READ_CONVERSION <lower-bound> c0 [c1 ...]`** — like the above but piecewise:
  multiple `SEG_POLY_READ_CONVERSION` lines with different lower bounds define different
  polynomials for different input ranges (lower bound is ignored for the lowest segment).
- **`GENERIC_READ_CONVERSION_START [converted-type] [converted-bit-size]` ... `GENERIC_READ_CONVERSION_END`**
  — inline Ruby between the two lines, last line's value is the conversion's result.
  `tlm.txt`'s `DURATION` derived item is this: `(packet.read('COLLECTS') * 0.5)` between the
  start/end markers. Unlike every other keyword, this one is a **mode switch**, not a
  single-line directive — worth spelling out precisely since it's the one place the line-level
  `(keyword, params)` model breaks down:
  - `GENERIC_READ_CONVERSION_START` itself just records the optional converted type
    (`INT`/`UINT`/`FLOAT`/`STRING`/`BLOCK`) and bit size as metadata (used by DART logging;
    warned about, not enforced) and flips `PacketConfig` into "building generic conversion"
    mode.
  - While in that mode, `PacketConfig#process_file` stops tokenizing lines into keyword/params
    at all. Instead of dispatching on `keyword`, it appends the **raw line text**
    (`ConfigParser#line`, the same attribute `ConfigParser` keeps around for error messages) to
    an accumulator string, verbatim, one line at a time — so arbitrary Ruby, including
    anything that would otherwise look like a keyword, passes through untouched.
  - `GENERIC_READ_CONVERSION_END` ends the mode and wraps the accumulated text in a
    `GenericConversion` object (`lib/cosmos/conversions/generic_conversion.rb`), assigned to
    the item's `read_conversion` (or `write_conversion` for the `WRITE` variant).
  - At **read time** (when telemetry is unpacked), `GenericConversion#call(value, packet,
    buffer)` does `eval(@code_to_eval)` — literally evaluating the captured source with
    `value`/`packet`/`buffer` bound as locals. Whatever the last expression evaluates to is the
    converted value. There's no sandboxing; this is intentionally the unrestricted escape hatch
    that `POLY_READ_CONVERSION`/`SEG_POLY_READ_CONVERSION` (fixed polynomial formula, no `eval`)
    are the safer, structured alternative to.

### Packet-level (not tied to one item)

| Keyword | Meaning |
|---|---|
| `LIMITS_GROUP <name>` / `LIMITS_GROUP_ITEM <target> <packet> <item>` | Group related limits so they can be enabled/disabled together as a unit. |
| `PROCESSOR <name> <ruby-file> [args...]` | Runs custom code every time this packet is received (not just on limits changes). |
| `ALLOW_SHORT` | Accept packets shorter than the definition; missing bytes are treated as zero. |
| `HIDDEN` | Hide this packet from GUI tools (Packet Viewer, Telemetry Grapher, Handbook Creator) — still reachable from scripts. |
| `META <name> [values...]` | Packet-level metadata, same idea as item-level. |

## Commands (packets the target *receives*) — for comparison

Structurally near-identical to telemetry, with parallel keyword names:

| Telemetry | Command equivalent |
|---|---|
| `TELEMETRY` / `SELECT_TELEMETRY` | `COMMAND` / `SELECT_COMMAND` |
| `ITEM` / `APPEND_ITEM` | `PARAMETER` / `APPEND_PARAMETER` |
| `ID_ITEM` / `APPEND_ID_ITEM` | `ID_PARAMETER` / `APPEND_ID_PARAMETER` |
| `ARRAY_ITEM` / `APPEND_ARRAY_ITEM` | `ARRAY_PARAMETER` / `APPEND_ARRAY_PARAMETER` |
| `READ_CONVERSION` family | `WRITE_CONVERSION`, `POLY_WRITE_CONVERSION`, `SEG_POLY_WRITE_CONVERSION`, `GENERIC_WRITE_CONVERSION_START/END` — same shapes, applied when a value is *written into* the outgoing packet instead of read out of an incoming one |

The key difference: `PARAMETER`/`APPEND_PARAMETER` additionally take **Minimum Value,
Maximum Value, Default Value** (for INT/UINT/FLOAT/DERIVED) or just **Default Value** (for
STRING/BLOCK) — since a command parameter is something a user or script fills in, COSMOS
needs to know its valid range and what to default to. `STATE` values on a command parameter
can also carry a `HAZARDOUS ["description"]` flag that pops a confirmation dialog when that
specific state is selected.

Command-only keywords: `HAZARDOUS ["description"]` (whole command needs confirmation),
`DISABLED` (command can't be sent at all, from tools or scripts), `DISABLE_MESSAGES` (don't
print the normal `cmd(...)` log line, but still log the command), `REQUIRED` (parameter has
no usable default — scripts must supply it explicitly), `MINIMUM_VALUE`/`MAXIMUM_VALUE`/
`DEFAULT_VALUE` (override those without redefining the whole parameter), and
`OVERFLOW <ERROR|ERROR_ALLOW_HEX|TRUNCATE|SATURATE>` (what to do when a value doesn't fit the
declared bit size).

## Mapping onto `tlm.txt` / our parser

`examples/simple_tlm/tlm.txt` uses: `TELEMETRY`, `APPEND_ID_ITEM`, `APPEND_ITEM`,
`FORMAT_STRING`, `UNITS`, `LIMITS`, `STATE`, `ITEM` (for the derived item),
`GENERIC_READ_CONVERSION_START/END`. That's a representative slice of the full keyword set
above, but far from all of it — no `ARRAY_ITEM`, no `POLY_READ_CONVERSION`, no packet-level
keywords, no command side at all. Whoever extends `parse_config_file` in `src/main.odin`
should treat this file as the full target vocabulary, and this doc as the reference for what
each keyword's argument list should tokenize into.

Right now the parser is purely a **tokenizer** (it classifies bytes into `ident`/`string`/
`num`/`float`/`comment` runs) — it doesn't yet know that the first `ident` on a line is a
keyword that determines how many/what type of arguments follow. That's the next layer up:
turning the token stream into actual `Packet`/`Item` structures per the tables above.

## Sources

- [Telemetry Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/telemetry)
- [Command Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/command)
- [`config_parser.rb` source, cosmos4 branch](https://github.com/BallAerospace/COSMOS/blob/cosmos4/lib/cosmos/config/config_parser.rb)
  — the generic line tokenizer (`(keyword, parameters[])` per logical line) underlying all
  COSMOS config files.
- [`packet_config.rb` source, cosmos4 branch](https://github.com/BallAerospace/COSMOS/blob/cosmos4/lib/cosmos/packets/packet_config.rb)
  — drives the per-target file walk and keyword dispatch; the generic-conversion
  start/end state machine described above lives in `process_file`/`process_current_item`.
- [`generic_conversion.rb` source, cosmos4 branch](https://github.com/BallAerospace/COSMOS/blob/cosmos4/lib/cosmos/conversions/generic_conversion.rb)
