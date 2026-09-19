# COSMOS v4 JSON API

How every GUI tool and script actually talks to the Command and Telemetry Server (see
`cosmos-overview.md`'s "every GUI tool is a thin client" point). Relevant to Solaris if/when it
grows beyond a static definition viewer into something that connects to a live server — either
COSMOS's own, or a future Solaris server of its own. v4 only; sources at the bottom.

## Transport and envelope

- Plain **HTTP**, POST to the CmdTlmServer's API port (default `7777`).
- Body is **a relaxed JSON-RPC 2.0** request: `{"jsonrpc": "2.0", "method": "...", "params": [...], "id": N}`.
  See [`json-rpc.md`](./json-rpc.md) for the actual spec this is relaxing. Relaxations vs.
  strict JSON-RPC 2.0:
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
  `lib/cosmos/tools/cmd_tlm_server/api.rb`) — that's the actual authority. The table below was
  pulled directly from that file (`cosmos4` branch) and is a near-complete enumeration, not a
  curated sample; treat any method missing here as an oversight rather than intentionally
  omitted.

## Method groups

**Commanding** — `cmd(*args)`, `cmd_no_range_check(*args)`, `cmd_no_hazardous_check(*args)`,
`cmd_no_checks(*args)`, and raw variants (`cmd_raw(*args)`, `cmd_raw_no_range_check(*args)`,
`cmd_raw_no_hazardous_check(*args)`, `cmd_raw_no_checks(*args)`) that skip write-conversions;
each takes either one `"TARGET CMD with PARAM value"` string or separate target/command/params
arguments. `send_raw(interface_name, data)` bypasses definitions entirely and writes bytes
straight to an interface.

**Command information** — `get_cmd_buffer(target, cmd)`, `get_cmd_list(target)`,
`get_cmd_param_list(target, cmd)`, `get_cmd_hazardous(target, cmd, params = {})`,
`get_cmd_value(target, cmd, param, value_type = :CONVERTED)`,
`get_cmd_time(target = nil, cmd = nil)`, `get_cmd_cnt(target, cmd)`.

**Telemetry reads** — `tlm(*args)`/`tlm_raw(*args)`/`tlm_formatted(*args)`/
`tlm_with_units(*args)` mirror the four value stages from `cosmos-screens.md`'s widget binding
(`RAW`/`CONVERTED`/`FORMATTED`/`WITH_UNITS`); `tlm_variable(*args)` is the same read but with the
value-type passed as a parameter instead of baked into the method name.
`get_tlm_packet(target, packet, value_type = :CONVERTED)`/`get_tlm_values(item_array,
value_types = :CONVERTED)` fetch several items (with limits state) in one call — important for a
client polling a whole screen's worth of items without N round trips.

**Telemetry writes / simulation** — `set_tlm(*args)`/`set_tlm_raw(*args)` (inject a value
locally), `inject_tlm(target, packet, item_hash = nil, value_type = :CONVERTED, send_routers =
true, send_packet_log_writers = true, create_new_logs = false)` (fabricate a whole packet as if
it arrived from the target), `override_tlm(*args)`/`override_tlm_raw(*args)`/
`normalize_tlm(*args)` (pin an item to a constant, then release it) — this is the API-level
equivalent of the `Override` protocol from `cosmos-architecture.md`, exposed for scripted use
instead of interface-time config.

**Telemetry information** — `get_tlm_buffer(target, packet)`, `get_tlm_list(target)`,
`get_tlm_item_list(target, packet)`, `get_tlm_details(item_array)`, `get_tlm_cnt(target,
packet)`.

**Limits** — `limits_enabled?(*args)`, `enable_limits(*args)`/`disable_limits(*args)` per item,
`get_limits_groups`/`enable_limits_group(name)`/`disable_limits_group(name)` per group,
`get_out_of_limits`/`get_overall_limits_state(ignored_items = nil)`/`get_stale(with_limits_only =
false, target = nil)` for current violations/staleness, `get_limits(target, packet, item,
limits_set = nil)`/`set_limits(target, packet, item, red_low, yellow_low, yellow_high, red_high,
green_low = nil, green_high = nil, limits_set = :CUSTOM, persistence = nil, enabled = true)` for
per-item thresholds, and multiple named **limits sets** (`get_limits_sets`/`get_limits_set`/
`set_limits_set(set)`) so e.g. a "thermal vacuum test" profile and a "flight" profile can define
different thresholds for the same items without editing config.

**Interface/router control** — `get_interface_names`/`get_interface_targets(name)`/
`connect_interface(name, *params)`/`disconnect_interface(name)`/`interface_state(name)`/
`get_interface_info(name)`/`get_all_interface_info`, and the identically-shaped router set
(`get_router_names`, `connect_router`/`disconnect_router`/`router_state`, `get_router_info`/
`get_all_router_info`); `map_target_to_interface(target, interface)` for runtime rerouting.

**Logging control** — `start_logging`/`stop_logging(writer = 'ALL')` and the cmd/tlm-specific
`start_cmd_log`/`start_tlm_log`/`stop_cmd_log`/`stop_tlm_log` (all take `(writer = 'ALL', label =
nil)` on start), `get_cmd_log_filename`/`get_tlm_log_filename(writer = 'DEFAULT')`; raw
(unframed) logging per interface/router via `start_raw_logging_interface`/
`stop_raw_logging_interface`/`start_raw_logging_router`/`stop_raw_logging_router(name = 'ALL')`;
`get_server_message_log_filename`/`start_new_server_message_log` for the separate server-message
log. `get_packet_loggers`/`get_packet_logger_info(name = 'DEFAULT')`/`get_all_packet_logger_info`
introspect what logger instances exist.

**Introspection** — `get_target_list`, `get_target_info(target)`/`get_all_target_info`,
`get_target_ignored_parameters(target)`/`get_target_ignored_items(target)` (surfaces
`target.txt`'s `IGNORE_PARAMETER`/`IGNORE_ITEM`, see `cosmos-architecture.md`),
`get_all_tlm_info`/`get_all_cmd_info`, `get_tlm_item_list`/`get_cmd_param_list`,
`get_tlm_details` — this is what lets a generic client (like Command Sender or Packet Viewer)
build its UI purely from server-reported definitions instead of having them compiled in, i.e.
the API surface makes the declarative config in `cosmos-config-format.md` introspectable at
runtime, not just load-time.

**Event subscriptions** — `subscribe_limits_events(queue_size = ...)`/
`subscribe_packet_data(packets, queue_size = ...)`/`subscribe_server_messages(queue_size = ...)`
each return an id, paired with `unsubscribe_*(id)` and polling drains
(`get_limits_event(id, non_block = false)`/`get_packet_data(id, non_block = false)`/
`get_server_message(id, non_block = false)`). This is COSMOS's closest thing to a push model, and
it's actually still pull-shaped: a client subscribes, then has to keep calling a `get_*` method
to drain its queue (`non_block` just controls whether an empty queue blocks or returns
immediately). There's no server-initiated push (no websocket/SSE in v4) — see
`cosmos-lessons.md`.

**Replay** — `replay_select_file(filename, reader = "DEFAULT")`, `replay_status`,
`replay_set_playback_delay(delay)`, `replay_play`/`replay_reverse_play`/`replay_stop`,
`replay_step_forward`/`replay_step_back` for frame-stepping, and direct seeking
(`replay_move_start`/`replay_move_end`/`replay_move_index(index)`) — notably, direct seek is
possible here at the API level even though the underlying binary log format is not
random-access (`cosmos-architecture.md`'s "have to parse a log from the start" point); the
replay engine must be doing the linear scan internally and presenting a seek-like interface on
top.

**Server & background tasks** — `get_server_status`, `cmd_tlm_reload` (re-read all definition
files without restarting the process), `cmd_tlm_clear_counters`, `get_background_tasks`/
`start_background_task(name)`/`stop_background_task(name)` (arbitrary named Ruby tasks the server
runs alongside its interfaces).

**Screen & saved-config introspection** — `get_screen_list(config_filename = nil, force_refresh =
false)`/`get_screen_definition(screen_full_name, ...)` let a client fetch `cosmos-screens.md`
screen files from the server instead of reading them off disk itself;
`get_saved_config(configuration_name = nil)` reads from `outputs/saved_config/`
(`cosmos-architecture.md`); `get_output_logs_filenames(filter = '*tlm.bin')` lists log files by
glob.

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
  — the "Method groups" section above was enumerated directly from this file's `@api_whitelist`.
