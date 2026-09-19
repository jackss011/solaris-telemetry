# JSON-RPC 2.0

A reference for the transport-layer protocol underneath [`cosmos-api.md`](./cosmos-api.md) —
COSMOS v4's own API is explicitly "a relaxed JSON-RPC 2.0" (its words). This doc covers the
*actual* spec, then calls out exactly where COSMOS deviates from it, since that gap matters for
anyone designing Solaris's own client/server transport (per `cosmos-lessons.md`'s point that
the API being plain HTTP + JSON is a low bar for any language, not just Ruby, to implement).

## What it is

JSON-RPC 2.0 is a small, transport-agnostic RPC spec: it defines the shape of request/response
JSON objects and nothing else — no transport (works equally over HTTP, TCP, WebSocket, stdio,
etc.), no authentication, no service discovery. It is stateless and, on its own, request/response
only (see "Notifications" and "no server push" below).

## Request object

```json
{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}
```

| Field | Required | Meaning |
|---|---|---|
| `jsonrpc` | yes | Must be the exact string `"2.0"` |
| `method` | yes | Name of the method to invoke. Names starting with `rpc.` are reserved for spec-internal extensions and must not be used for application methods |
| `params` | no | Structured argument data — either an **Array** (positional args, in declared order) or an **Object** (named args, by exact member name) |
| `id` | no | Client-chosen correlation token: String, Number, or `null`. Its presence is what distinguishes a request from a notification |

A request whose `id` is `null` is technically legal per the spec's grammar, but the spec advises
against it because it collides with the `id: null` a server sends back when it couldn't parse
the id at all (see Response object below) — best practice is to just omit `id` entirely for
notifications instead of setting it to `null`.

## Notifications

A **notification** is a request object with no `id` member at all. It's a fire-and-forget call:
the server must not send any response to it, success or error — including parse/validation
errors, since without an `id` there's nothing to correlate a response to. This is the spec's
only built-in way to say "I don't care about the result."

## Response object

Exactly one of `result` / `error` is present — never both, never neither:

```json
{"jsonrpc": "2.0", "result": 19, "id": 1}
{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": 1}
```

| Field | Meaning |
|---|---|
| `result` | The method's return value on success. Can be anything JSON-representable, including `null` — so `result: null` on success looks identical on the wire to `result` being absent; a receiver must key off the presence of `error` instead of null-checking `result` |
| `error` | An error object (below) on failure |
| `id` | Echoes the request's `id`. If the server couldn't even determine the id (e.g. the JSON didn't parse), this is `null` |

### Error object

| Field | Required | Meaning |
|---|---|---|
| `code` | yes | Integer error code (table below) |
| `message` | yes | Short, one-line human-readable description |
| `data` | no | Arbitrary extra structured detail (stack trace, offending field, etc.) |

### Reserved error codes

| Code | Name | Meaning |
|---|---|---|
| `-32700` | Parse error | Server received invalid JSON |
| `-32600` | Invalid Request | The JSON was valid but not a well-formed Request object |
| `-32601` | Method not found | No such method |
| `-32602` | Invalid params | Method exists but the supplied params don't match |
| `-32603` | Internal error | Unhandled server-side error |
| `-32000`..`-32099` | Server error | Reserved range for implementation-defined server errors |

Anything outside the reserved ranges above is free for the application to define its own
meanings.

## Batching

A client may send an **Array** of Request objects as a single call instead of one object. The
server processes each independently (order not guaranteed) and replies with an Array of the
corresponding Response objects — notifications inside the batch produce no entry in the response
array. If *every* request in a batch is a notification, the server sends no HTTP body back at
all, not even an empty array.

## Where COSMOS v4's API deviates ("relaxed JSON-RPC 2.0")

Cross-referencing [`cosmos-api.md`](./cosmos-api.md#transport-and-envelope):

| Spec behavior | COSMOS v4's actual behavior |
|---|---|
| `id: null` is a legal (if discouraged) request/notification marker | Not supported — every COSMOS call expects a real response, so there's no true fire-and-forget notification |
| JSON numbers only (`NaN`/`Infinity`/`-Infinity` are invalid JSON) | Allowed as literals, since a telemetry conversion (e.g. divide-by-zero in a `POLY_READ_CONVERSION`) can legitimately produce one |
| `params` may be an Array *or* an Object (named args) | **Positional only** — always an Array, never named parameters |
| Batching is a core, mandatory-to-support feature | **Not supported** — every call is its own HTTP round trip, which is why `get_tlm_values`/`get_tlm_packet`-style multi-item methods exist as an app-level workaround (see `cosmos-api.md`) |
| Transport-agnostic | COSMOS fixes it to plain HTTP POST to one port (default `7777`) |
| No auth defined by the spec (left to the transport) | COSMOS v4 defines none either — `ALLOW_ACCESS` IP whitelisting in `system.txt` is the only gate (`cosmos-architecture.md`) |

## Implications for Solaris

- The spec itself is a genuinely good, minimal fit for "one server, many thin clients" (the
  functional model in `cosmos-overview.md`) regardless of what language either side is written
  in — adopting *unmodified* JSON-RPC 2.0 (rather than COSMOS's relaxed dialect) would get
  Solaris real batching for free, which directly addresses `cosmos-lessons.md`'s point #2 about
  COSMOS's API making N round trips where one would do.
- Batching is not the same thing as push — a JSON-RPC batch is still client-initiated. If
  Solaris wants server-initiated updates (the bigger lesson from `cosmos-lessons.md` point #2),
  JSON-RPC would need to ride on a transport that supports server push (WebSocket, SSE) with
  notifications (no `id`) as the message shape for "value changed" events, rather than trying to
  make plain request/response HTTP do that job.
- Dropping the `NaN`/`Infinity` relaxation is worth reconsidering carefully rather than
  reflexively "being spec-strict": telemetry conversions producing non-finite floats is a real
  case, not a COSMOS quirk, so Solaris's own encoding needs *some* answer for it (e.g. encode as
  a string sentinel, or a wrapper object) if it sticks to strict JSON.
- Being positional-only vs. supporting named params is a real usability tradeoff, not just spec
  purity: named params make a hand-constructed request self-documenting; positional-only is more
  compact and matches how `"TARGET CMD with PARAM value"`-style COSMOS calls already read.
  Nothing stops Solaris from supporting both, since the spec allows either shape.

## Sources

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [`cosmos-api.md`](./cosmos-api.md) — COSMOS v4's own relaxed dialect and full method list
