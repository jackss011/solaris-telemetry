# How COSMOS works

Solaris is "a COSMOS inspired telemetry viewer" (see root `README.md`). This section
summarizes how the real Ball Aerospace COSMOS system works — functionally and in software —
as background for design decisions in this repo. It's based on the [COSMOS v4
docs](https://ballaerospace.github.io/cosmos-website/docs/v4/) and the
[BallAerospace/COSMOS](https://github.com/BallAerospace/COSMOS) repo (sources at the bottom).

Note on versions: Ball Aerospace shipped COSMOS through v5, then suspended further
development of it under that name; the project's lineage continues as
[OpenC3](https://github.com/OpenC3) COSMOS. This doc focuses on **v4**, since its config-file
telemetry definition language is the direct model for `examples/simple_tlm/tlm.txt` and the
parser in `src/main.odin`. v5 restructured a lot of this (containerized services, web UI)
but kept the same conceptual model described below.

This page stays at overview depth. For the full detail behind the two summaries below, see
[`cosmos-architecture.md`](./cosmos-architecture.md) (deployment layout, `cmd_tlm_server.txt`,
interfaces/protocols, chaining, binary logs) and
[`cosmos-config-format.md`](./cosmos-config-format.md) (every `TELEMETRY`/`COMMAND` config
keyword).

## Functional model

COSMOS exists to send commands to, and receive telemetry from, one or more embedded systems
("targets") — anything from a test board on a bench to a spacecraft. It's built around a
**client-server architecture**:

- **Command and Telemetry Server (CmdTlmServer)** is the hub. It's the single point that
  owns realtime connections to every target, and the only thing that actually writes to /
  reads from hardware. Every other tool is a client of it.
- **Targets** are the things being controlled/monitored.
- **Interfaces** are the transport between the server and a target: TCP/IP, UDP/IP, serial,
  or a custom interface you write. An interface is *how bytes move*.
- **Protocols** sit on top of an interface and know how to delineate packets within a stream
  (e.g. length-delimited, terminator-delimited, CRC-checked). In v4, protocols became
  composable/stackable on an interface rather than being baked into the interface class —
  this is what lets you layer something like a CRC-checking protocol on top of a
  length-delimited one.
- A collection of **GUI tools** act purely as clients, talking to the server over its API
  rather than to hardware directly:
  - **Command and Telemetry Server** app — shows interface/target status, connect/disconnect,
    raw byte counts, shortcuts to inspect raw and formatted packets.
  - **Command Sender** — manually build and send a command, with parameter descriptions.
  - **Packet Viewer** — realtime key/value view of every defined telemetry item's latest value.
  - **Telemetry Viewer** — custom-built screens/widgets showing chosen telemetry items.
  - **Telemetry Grapher** — realtime and historical line graphs of telemetry points.
  - **Limits Monitor** — tracks and logs telemetry points that go out of acceptable range.
  - **Script Runner** — runs Ruby test procedures with line-by-line highlighting, pausing,
    and automatic stop on a failed telemetry check or exception.
  - **Extractor** — offline export of logged command/telemetry to CSV for analysis.

So functionally: definitions describe *what* the bytes mean, interfaces+protocols describe
*how* the bytes arrive, the server is the *only* thing touching the target, and every GUI
tool is a thin, replaceable client on top of that server's data.

## Definitions: how "what the bytes mean" is expressed

This is the part most directly relevant to Solaris, since it's what `tlm.txt` mimics.

- Configuration lives in per-target directories (`config/targets/TARGET_NAME/...`, uppercase
  by convention), each containing a `cmd_tlm/` subfolder of `.txt` definition files, plus a
  `target.txt`. A `system.txt` at the top level configures shared things like ports and
  target list, so individual target files don't repeat themselves.
- Files in `cmd_tlm/` are plain-text, keyword-driven, and processed in filename order — so a
  file that depends on another (e.g. an override file) is named to sort after it.
- Core keywords:
  - `TELEMETRY` / `COMMAND` start a new packet definition (target, mnemonic, endianness,
    description).
  - `ITEM` defines a field at an explicit bit offset/size; `APPEND_ITEM` defines fields
    sequentially without manual offset bookkeeping — this is the one `src/main.odin`'s parser
    and `tlm.txt` currently use.
  - `ID_ITEM` / `APPEND_ID_ITEM` mark fields used to identify *which* packet definition a
    given set of bytes matches (e.g. `tlm.txt`'s `CCSDSAPID`).
  - `STATE` maps raw numeric values to human-readable strings (optionally with a color, for
    red/yellow/green-style displays) — e.g. `tlm.txt`'s `COLLECT_TYPE`/`DEPLOYED` fields.
  - `LIMITS` defines red/yellow/green numeric thresholds per item, which is what feeds the
    Limits Monitor tool and colored displays.
  - Items can carry `UNITS`, `FORMAT_STRING`, `DESCRIPTION`, `META` metadata purely for
    display.
  - `DERIVED` items have zero bit size — they aren't physically in the packet at all, but are
    computed from other items (via `GENERIC_READ_CONVERSION_START/END` Ruby snippets, or
    `POLY_READ_CONVERSION` for polynomial conversions). `tlm.txt`'s `DURATION` item is exactly
    this pattern.
- At startup, the server reads all of this and builds in-memory packet definitions; incoming
  bytes are then matched to a definition (via ID items) and sliced up per the bit
  offsets/sizes/conversions, rather than being interpreted by bespoke per-target code.

This declarative, one-config-file-per-packet-type approach is the reason Solaris's parser
exists: `examples/simple_tlm/tlm.txt` is a hand-written example of exactly this format, and
`parse_config_file` in `src/main.odin` is the beginning of a tokenizer for it.

## Software architecture

- COSMOS (through v4/v5) is implemented in **Ruby**.
- The Command and Telemetry Server exposes an **API** — in v4, an HTTP server (default port
  `7777`) implementing a relaxed JSON-RPC 2.0 spec, historically layered over DRb
  (Distributed Ruby) for the underlying object access. GUI tools and scripts talk to the
  server exclusively through this API rather than linking against target-specific code.
- The server logs all commands and telemetry it sends/receives by default (for replay and
  offline analysis — this is what Extractor and log-playback tooling consume), and separately
  runs limits monitoring on every telemetry packet it receives.
- Each interface typically runs on its own thread inside the server process, since it owns a
  long-lived connection to a target and needs to read/write independently of everything else
  the server is doing.
- The GUI tools are effectively thin clients: none of them own target connections directly;
  they all query/subscribe through the server's API. This is what makes it possible to run
  many simultaneous viewers/graphers against one live system without contention over the
  actual hardware link.

## Sources

- [COSMOS Architecture (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/)
- [Interface Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/interfaces)
- [Telemetry Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/telemetry)
- [Directory structure (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/structure)
- [JSON API (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/json-api)
- [Command and Telemetry Server (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/cmd-tlm-server)
- [BallAerospace/COSMOS README](https://github.com/BallAerospace/COSMOS/blob/master/README.md)
- [Protocol Rate news post (v4 protocol stacking change)](https://ballaerospace.github.io/cosmos-website/news/2020/03/17/protocol-rate/)
