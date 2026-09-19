# COSMOS v4 JSON API

How every GUI tool and script actually talks to the Command and Telemetry Server (see
`cosmos-overview.md`'s "every GUI tool is a thin client" point). Relevant to Solaris if/when it
grows beyond a static definition viewer into something that connects to a live server — either
COSMOS's own, or a future Solaris server of its own. v4 only; sources at the bottom.

## Transport and envelope

- Plain **HTTP**, POST to the CmdTlmServer's API port (default `7777`).
- Body is **a relaxed JSON-RPC 2.0** request: `{"jsonrpc": "2.0", "method": "...", "params": [...], "id": N}`.
  Relaxations vs. strict JSON-RPC 2.0:
  - Requests with a `null` id aren't supported (every call expects a real response).
  - Non-standard JSON number literals (`NaN`, `Infinity`, `-Infinity`) are allowed, since
    telemetry legitimately produces these (e.g. a float conversion dividing by zero).
  - Parameters are **positional only** — no named-parameter calling convention.
  - No batched requests (each call is its own HTTP round trip).
- No authentication is documented for v4 — the API's security model is "whoever can reach the
  port can call anything," which is consistent with `ALLOW_ACCESS` in `system.txt` being the
  only access control (`cosmos-architecture.md`). Worth treating as a deliberate risk-accepted
  choice for a lab-bench tool, not something to replicate silently in a design meant for
  anything more exposed.
- The full method list lives in COSMOS's own source (`@api_whitelist` in
  `lib/cosmos/tools/cmd_tlm_server/api.rb`) — that's the actual authority; the summary below is
  a representative cross-section, grouped by concern, not necessarily exhaustive or
  signature-exact.

## Method groups

**Commanding** — `cmd`, `cmd_no_range_check`, `cmd_no_hazardous_check`, `cmd_no_checks`, and raw
variants (`cmd_raw*`) that skip write-conversions; each takes either one `"TARGET CMD with PARAM value"`
string or separate target/command/params arguments. `send_raw` bypasses definitions entirely and
writes bytes straight to an interface. `get_cmd_buffer`/`get_cmd_time` inspect what was last
sent.

**Telemetry reads** — `tlm`/`tlm_raw`/`tlm_formatted`/`tlm_with_units` mirror the four value
stages from `cosmos-screens.md`'s widget binding (`RAW`/`CONVERTED`/`FORMATTED`/`WITH_UNITS`).
`get_tlm_packet`/`get_tlm_values` fetch several items (with limits state) in one call —
important for a client polling a whole screen's worth of items without N round trips.

**Telemetry writes / simulation** — `set_tlm`/`set_tlm_raw` (inject a value locally),
`inject_tlm` (fabricate a whole packet as if it arrived from the target), `override_tlm`/
`override_tlm_raw`/`normalize_tlm` (pin an item to a constant, then release it) — this is the
API-level equivalent of the `Override` protocol from `cosmos-architecture.md`, exposed for
scripted use instead of interface-time config.

**Limits** — enable/disable per item or per `LIMITS_GROUP`, `get_out_of_limits`/
`get_overall_limits_state` for current violations, multiple named **limits sets**
(`get_limits_set`/`set_limits_set`) so e.g. a "thermal vacuum test" profile and a "flight"
profile can define different thresholds for the same items without editing config.

**Interface/router control** — `connect_interface`/`disconnect_interface`/`interface_state`,
same shape for routers; `map_target_to_interface` for runtime rerouting.

**Logging control** — start/stop cmd and/or tlm logging independently, raw (unframed) logging
per interface/router, query current log filenames.

**Introspection** — `get_target_list`, `get_all_tlm_info`/`get_all_cmd_info`,
`get_tlm_item_list`, `get_cmd_param_list`, `get_tlm_details` — this is what lets a generic
client (like Command Sender or Packet Viewer) build its UI purely from server-reported
definitions instead of having them compiled in, i.e. the API surface makes the declarative
config in `cosmos-config-format.md` introspectable at runtime, not just load-time.

**Event subscriptions** — `subscribe_limits_events`/`subscribe_packet_data`/
`subscribe_server_messages` plus matching `get_*_event`/`get_packet_data`/`get_server_message`
polling calls. This is COSMOS's closest thing to a push model, and it's actually still
pull-shaped: a client subscribes, then has to keep calling a `get_*` method to drain its queue.
There's no server-initiated push (no websocket/SSE in v4) — see `cosmos-lessons.md`.

**Replay** — `replay_select_file`, `replay_play`/`replay_reverse_play`/`replay_stop`,
frame-stepping, and direct seeking (`replay_move_index`) — notably, direct seek is possible here
at the API level even though the underlying binary log format is not random-access
(`cosmos-architecture.md`'s "have to parse a log from the start" point); the replay engine must
be doing the linear scan internally and presenting a seek-like interface on top.

## Practical implications for a client (or a Solaris-side server)

- Every UI in COSMOS v4 is fundamentally **poll + occasional subscribe-and-drain**, never
  server push. A viewer redraws because it asked, on its own timer (`SCREEN`'s polling-period
  parameter), not because the server told it something changed.
- Batched, multi-item reads (`get_tlm_values`) exist specifically to keep a screen's worth of
  widgets to one round trip — a client built against this API should reach for those over N
  calls to `tlm()`.
- Because everything is positional-args JSON-RPC over plain HTTP, the API itself is
  language-agnostic — an Odin (or any other language) client doesn't need Ruby, just an HTTP
  client and a JSON encoder/decoder, which is a very low bar for a future "Solaris talks to a
  live server" milestone.

## Sources

- [JSON API (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/json-api)
- [`api.rb` source, cosmos4 branch](https://github.com/BallAerospace/COSMOS/blob/cosmos4/lib/cosmos/tools/cmd_tlm_server/api.rb)
