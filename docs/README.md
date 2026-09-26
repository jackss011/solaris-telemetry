# Solaris Docs

Deeper reference material that doesn't belong in the top-level `CLAUDE.md`/`README.md`.
`CLAUDE.md` points here for agents that need more context than the quick orientation it gives.

## Sections

| Section | Status |
|---|---|
| [How COSMOS works](./cosmos-overview.md) — functional model + software architecture of the system Solaris is inspired by | Done |
| [COSMOS architecture, interfaces & server config](./cosmos-architecture.md) — deployment layout, `cmd_tlm_server.txt`, Interface/Protocol stacking, chaining, binary logs | Done |
| [COSMOS command/telemetry definition format](./cosmos-config-format.md) — full keyword reference for the `TELEMETRY`/`COMMAND` config language `tlm.txt` and `src/main.odin`'s parser target | Done |
| [COSMOS screen/widget definition language](./cosmos-screens.md) — Telemetry Viewer's declarative dashboard format (layout containers, value widgets, styling) — reference point for the eventual raylib UI | Done |
| [COSMOS v4 JSON API](./cosmos-api.md) — transport, request format, method groups a client/server split would need to cover | Done |
| [JSON-RPC 2.0](./json-rpc.md) — the actual spec underneath COSMOS's "relaxed" dialect, where it deviates, and implications for Solaris's own transport | Done |
| [Lessons for building something better than COSMOS v4](./cosmos-lessons.md) — sourced pain points (bitfield model, pull-only updates, non-seekable logs, single-process blast radius) and what they imply for Solaris's design | Done |
| [Telemetry database implementation plan](./telemetry-database-plan.md) — data model, module layout, and ordered milestones for turning parsed keywords into a queryable, notifying runtime telemetry store | Done |
| Solaris architecture (how our own code is organized, and how/where it currently diverges from the reference above — see `CLAUDE.md`'s Architecture section for the current token/keyword-layer parser design; no `Packet`/`Item` semantic layer yet) | TODO |
| Roadmap / open design questions | TODO |
