# COSMOS architecture, interfaces, and the server config file

This goes deeper than the "Software architecture" section of [`cosmos-overview.md`](./cosmos-overview.md)
on specifically: how a real COSMOS deployment is laid out on disk, how the Command and
Telemetry Server is told what to connect to, and how the Interface/Protocol layer actually
moves and delineates bytes. All of this is COSMOS v4 behavior (see sources at the bottom);
v5 restructured the deployment model (containers, a web frontend) but kept this same
interface/protocol/target vocabulary underneath.

## Directory layout

A COSMOS project root looks roughly like:

```
Gemfile, Rakefile, Launcher(.bat)
config/
  system/system.txt          # global config: ports, paths, declared targets
  data/                      # shared static data (images, crc.txt)
  tools/
    cmd_tlm_server/cmd_tlm_server.txt   # maps interfaces -> targets, for the CTS
    <other tool>/<other tool>.txt       # per-tool config
  targets/
    BOB/                     # target dirs are UPPERCASE by convention
      target.txt             # per-target settings (REQUIRE, IGNORE_ITEM, ...)
      cmd_tlm/                # *.txt command/telemetry definitions (see cosmos-config-format.md)
      lib/                    # target-specific Ruby (custom Interfaces, conversions, ...)
      procedures/             # test/ops scripts for this target
      screens/                # Telemetry Viewer screen definitions
      sequences/               # Command Sequence tool inputs
      tables/                 # binary tables for Table Manager
lib/                          # project-wide custom code (mirrors COSMOS's own source layout
                               # so you can override default behavior)
procedures/                   # default location for shared test/ops procedures
outputs/
  logs/                       # binary cmd/tlm logs + server message logs
  handbooks/                  # generated cmd/tlm documentation
  saved_config/               # snapshots of config, so old logs stay parseable after edits
  tmp/                        # safely-deletable cache
```

Two ways a target gets into the system, configured in `config/system/system.txt`:
- `AUTO_DECLARE_TARGETS` — auto-discovers every uppercase folder under `config/targets/`.
- `DECLARE_TARGET NAME [RENAMED_NAME] [target_filename.txt]` — explicit, one line per target;
  lets you instantiate the same target code twice under different names (e.g. `INST`/`INST2`)
  or point at a non-default target file.
- `DECLARE_GEM_TARGET` / `DECLARE_GEM_MULTI_TARGET` — same idea, but for targets shipped as a
  Ruby gem instead of a local folder.

## `system.txt` keywords worth knowing

| Keyword | Purpose |
|---|---|
| `PORT NAME PORT#` | Sets a named server port, e.g. `PORT CTS_API 7777`, `PORT CTS_PREIDENTIFIED 7779` |
| `LISTEN_HOST` / `CONNECT_HOST` | Bind an API to a specific interface/hostname |
| `ALLOW_ACCESS` | Whitelists client machines (or `ALL`) |
| `PATH NAME './dir'` | Where logs/procedures/tables/handbooks etc. live |
| `DEFAULT_PACKET_LOG_WRITER` / `_READER` | Which Ruby class writes/reads the binary log format |
| `STALENESS_SECONDS` | How long before a telemetry item is shown stale (purple) in screens |
| `META_INIT` | File of key/value pairs to seed the built-in `SYSTEM META` packet |
| `CLASSIFICATION text r g b` | Adds a colored classification banner to every tool |
| `HASHING_ALGORITHM` | Digest used to detect config changes (triggers cmd/tlm reload) |

`target.txt` (per-target) complements this with things like `REQUIRE` (load extra Ruby from
the target's `lib/`), `IGNORE_PARAMETER`/`IGNORE_ITEM` (hide fields from tools without
deleting them), and `CMD_UNIQUE_ID_MODE`/`TLM_UNIQUE_ID_MODE` (brute-force packet
identification when ID items alone are ambiguous).

## The Command and Telemetry Server (CTS)

The CTS is a single long-running process that:
- owns every live connection to a target (nothing else touches hardware directly),
- logs all commands/telemetry it sends/receives to binary log files by default,
- runs limits monitoring on every telemetry packet it receives,
- exposes an HTTP JSON-RPC-ish API (default port `7777`) that every GUI tool and script
  talks to instead of touching targets directly.

What it connects to is entirely described by `config/tools/cmd_tlm_server/cmd_tlm_server.txt`.
A minimal real example from the docs:

```
INTERFACE BOB_INT tcpip_client_interface.rb 192.168.1.5 8888 8888 5.0 nil LENGTH 0 32 4
  TARGET BOB
```

Reading this left to right:
- `INTERFACE BOB_INT tcpip_client_interface.rb` — declare an interface named `BOB_INT`,
  implemented by the built-in TCP/IP client interface class.
- `192.168.1.5 8888 8888 5.0 nil` — that class's own params: host, write port, read port,
  write timeout (seconds), read timeout (`nil` = block forever).
- `LENGTH 0 32 4` — a **protocol** stacked on the interface (see below): packets are
  length-delimited, with the length field at bit offset 0, 32 bits wide, and 4 added to the
  decoded value (a common trick for a length field that only counts *itself onward*).
- `TARGET BOB` — nested under the `INTERFACE` line, this maps target `BOB`'s command/telemetry
  traffic onto this interface. An interface can service more than one `TARGET` line.

Other keywords in this file:
- `ROUTER` — declared just like `INTERFACE` (same underlying parameters), but a Router's job
  is to re-broadcast an existing Interface's telemetry to whatever connects to the Router, and
  forward that connection's commands back through the original Interface. Used for things like
  the `PREIDENTIFIED_ROUTER` (default port `7779`) that chained/child CmdTlmServers connect to.
- `LOG` — override the default packet-log writer/reader class for this specific interface.
- `LOG_RAW` — log the *exact* bytes sent/received, with no COSMOS framing — useful for
  low-level debugging, but not readable by COSMOS's own log tools.
- `OPTION` — interface-specific extra settings, consumed by Serial and TCP/IP Server
  interfaces (e.g., socket options).
- `PROTOCOL READ|WRITE|READ_WRITE ProtocolClassName [args...]` — attach a *helper* protocol
  (see below) in addition to the interface's primary delineation protocol.

## Interfaces: how bytes actually move

Every interface implementation must provide `connect`, `connected?`, `disconnect`,
`read_interface` (blocking), and `write_interface` (non-blocking) — this is the seam where
you'd write a custom interface for hardware COSMOS doesn't ship support for. Provided ones:

| Interface | Key parameters |
|---|---|
| **TCP/IP client** | host, write port, read port, write timeout, read timeout (`nil` = block) |
| **TCP/IP server** | same minus host — it listens instead of dialing out |
| **UDP** | host, write dest port, read port, optional write source port, optional multicast interface address, optional TTL |
| **Serial** | write port / read port (device names, `nil` to disable one direction), baud rate, parity, stop bits, timeouts |
| **CmdTlmServer interface** | none — an internal loopback interface into the CTS's own API, used by chaining |
| **LINC interface** | Ball-specific: host, port, handshake/response/timeouts, length field location, GUID/length field names |

Custom interfaces are Ruby files named/cased to match their class (`labview_interface.rb` →
`LabviewInterface`), and must guard their I/O with `begin/rescue` — the server runs with
`Thread.abort_on_exception = true`, so one uncaught exception in a custom interface can take
the whole process down.

## Protocols: how packets are delineated within the byte stream

An interface only knows how to move bytes; a **Protocol** decides where one packet ends and
the next begins, and can transform data on the way in/out. In COSMOS v4 protocols became
stackable on an interface (earlier versions baked exactly one delineation scheme into the
interface class itself) — this is what lets you layer, say, a CRC-checking protocol on top of
a length-delimited one instead of writing that combination as a one-off interface.

**Primary delineation protocols** (declared right after `INTERFACE`, as in the `LENGTH ...`
example above):
- `BURST` — just read whatever's available each call; no real delineation.
- `LENGTH` — a length field at a known bit offset/size tells you how much more to read.
- `TERMINATED` — packets end at a byte sequence (e.g. `0x0D0A`).
- `FIXED` — every packet is a known fixed size, with a known ID location.
- `TEMPLATE` — for text/line based command-response protocols (e.g. SCPI instruments).
- `PREIDENTIFIED` — COSMOS's own internal framing (packet name + data), used between
  CmdTlmServers and their tools/chained servers, not for talking to real hardware.

**Helper protocols** (added via the `PROTOCOL` keyword, can stack multiple):
- `CRC` — appends/verifies a checksum on outgoing/incoming packets.
- `Override` — forces specific telemetry items to fixed values on read (useful for
  simulating/patching values without touching the target).
- `Ignore` — silently drops specified packets.

## Chaining servers

Multiple CmdTlmServers can be linked so a remote workstation doesn't need direct hardware
access, or so a machine with the actual serial/USB connection can still be monitored remotely:

- **Client → master**: a child CTS opens a normal `tcpip_client_interface` connection to the
  master's `PREIDENTIFIED_ROUTER` (port `7779` by default) and lists the `TARGET`s it wants:
  ```
  INTERFACE CHAININT tcpip_client_interface.rb localhost 7779 7779 10 5 PREIDENTIFIED
    TARGET INST
    TARGET INST2
  ```
- **Master → client**: inverted — the master dials into a child that owns the real
  connection, using the same `PREIDENTIFIED` protocol.

Both sides must agree on target definitions, and firewalls need port `7779` (or whatever it's
remapped to when running multiple servers on one host) open.

## Binary log format (brief)

Command/telemetry logs are binary files under `outputs/logs/`, named
`YYYY_MM_DD_HH_MM_SS_..._cmd.bin` / `..._tlm.bin`, each packet prefixed with a COSMOS header
(timing + target/packet name) after a 128-byte file header. Because packets are variable
length, a reader has to parse a log from the start — you can't seek into the middle of one
without having walked every packet before it. `outputs/logs/..._server_messages.txt` holds
timestamped INFO/WARN/ERROR server messages alongside the binary logs.

## Sources

- [COSMOS Architecture (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/)
- [Interface Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/interfaces)
- [System Configuration (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/system)
- [Directory structure (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/structure)
- [Getting Started (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/gettingstarted)
- [Chaining CmdTlmServers (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/chaining)
- [Logging (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/logging)
- [Command and Telemetry Server CLI options (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/cmd-tlm-server)
