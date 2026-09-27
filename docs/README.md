# Solaris Docs

Deeper reference material that doesn't belong in the top-level `CLAUDE.md`/`README.md`.
`CLAUDE.md` points here for agents that need more context than the quick orientation it gives.

## Solaris itself

| Doc | Covers | Status |
|---|---|---|
| [Solaris architecture](./solaris-architecture.md) | How `src/main.odin` is actually organized today: the parser layer vs. the raylib tile/window-manager UI, why they're not wired together yet, the tiling/drag system in detail, and known gaps | Done |
| [Telemetry database implementation plan](./telemetry-database-plan.md) | Data model, module layout, and ordered milestones for turning parsed keywords into a queryable, notifying runtime telemetry store | Done |
| [TODO](./TODO.md) | Short-form scratch notes on planned work | — |
| Roadmap / open design questions | — | TODO |

## Reference material

| Doc | Covers |
|---|---|
| [Odin language overview](./odin-language-overview.md) | Core language features (declarations, control flow, structs/enums/unions, arrays vs. slices vs. dynamic arrays, allocators) with examples tied back to `src/main.odin` |
| [References](./references.md) | External links worth having open while working here — Odin, raylib, the UI font and its license, COSMOS/OpenC3 upstream, and the design philosophy (Handmade Hero) this codebase follows |

## COSMOS (what Solaris is inspired by)

Grouped under [`cosmos/`](./cosmos/) since these all document the *reference system*, not this
repo's own code:

| Doc | Covers |
|---|---|
| [How COSMOS works](./cosmos/overview.md) | Functional model + software architecture of the system Solaris is inspired by |
| [COSMOS architecture, interfaces & server config](./cosmos/architecture.md) | Deployment layout, `cmd_tlm_server.txt`, Interface/Protocol stacking, chaining, binary logs |
| [COSMOS command/telemetry definition format](./cosmos/config-format.md) | Full keyword reference for the `TELEMETRY`/`COMMAND` config language `tlm.txt` and `src/main.odin`'s parser target |
| [COSMOS screen/widget definition language](./cosmos/screens.md) | Telemetry Viewer's declarative dashboard format (layout containers, value widgets, styling) — reference point for the eventual raylib UI |
| [COSMOS v4 JSON API](./cosmos/api.md) | Transport, request format, method groups a client/server split would need to cover |
| [JSON-RPC 2.0](./cosmos/json-rpc.md) | The actual spec underneath COSMOS's "relaxed" dialect, where it deviates, and implications for Solaris's own transport |
| [Lessons for building something better than COSMOS v4](./cosmos/lessons.md) | Sourced pain points (bitfield model, pull-only updates, non-seekable logs, single-process blast radius) and what they imply for Solaris's design |
