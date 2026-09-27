# Solaris architecture (current state)

This documents how *this repo's own code* (`src/main.odin`) is organized today, and — importantly
— how its two halves currently relate to each other: they don't, yet. `CLAUDE.md`'s Architecture
section covers the same ground at orientation depth; this doc goes deeper on the part that isn't
covered anywhere else — the raylib UI — and is explicit about what's real vs. sketch.

## The two halves

`src/main.odin` currently contains two independent pieces of functionality that share a file but
not a call graph:

1. **The telemetry-definition parser** (token layer → keyword layer → raw-block capture →
   `parse_config_file`, plus the dormant `TlmDef`/`TlmItemDef` data-model types). This is the
   part `CLAUDE.md`'s Architecture section documents in detail, and the part
   [`cosmos/config-format.md`](./cosmos/config-format.md) is the semantic reference for.
2. **The slot/panel layout UI** (`Rect`, `Tile`/`Panel`/`Slots`, `DragOperation`, and `main`'s
   render loop). This is what actually runs when you launch the program, and it's what the rest
   of this doc covers.

**These are not wired together.** `main` no longer calls `parse_config_file` — the old
entry point that did (`fmt.println("Hello basic parse example!"); parse_config_file(...)`) is
still there, but commented out, sitting right above the `RECT` section. `main` today launches a
generic slot grid and lets you click a free slot to spawn a fixed-size placeholder panel (labeled
"Packet Viewer" only in a debug print, not from any parsed definition) — it has no knowledge of
`tlm.txt`, `TlmDef`, or `TlmItemDef` at all. Turning "click a slot" into "click a slot and pick a
real parsed telemetry packet to display" is the integration step that doesn't exist yet.

## Vocabulary

The UI uses these words consistently — in type names, proc prefixes and local variable names:

| Word | Meaning | Units |
|---|---|---|
| **slot** | One cell of the layout grid. `Slots` is the grid itself (plus the panels placed on it). | int |
| **tile** | A rectangle of whole slots — pure geometry, no theme or content. | int |
| **panel** | What's attached to a tile and drawn on screen. Its `Rect` is derived from its tile each frame; it's what carries (in future) a UI theme and telemetry content. | float px (drawn) |
| **rect** | Any rectangle in screen pixels (`Rect`). | float px |
| **window** | Only ever the OS window raylib opens — never a panel. | px |
| **status bar** | The strip along the bottom of the window ("EDIT" badge, "SOLARIS" logo). | px |

Naming follows from that: `*_rect` locals are pixels, `tile`/`Tile` values are slots, and index
variables are named after what they index (`panel_idx`, `raised_panel`).

## `Rect`: pixel-space rectangles

`Rect :: struct { x, y, w, h: f32 }` is the one pixel-space geometry primitive the UI uses. Its
helpers:

- `rect_inset(r, inset)` — shrinks a rect by `inset` in total (`inset/2` on each side), used to put
  visual padding between a slot's/panel's hit area and its drawn fill. A **negative** inset grows
  the rect instead, which the (currently commented-out) panel glow effect relies on.
- `rect_to_rl(r)` — converts to `rl.Rectangle` for raylib draw calls.
- `rect_contains(r, point)` — half-open bounds test (`x` in `[r.x, r.x+r.w)`, same for `y`), used
  for both slot hover and drag-handle hit-testing.
- `rect_centered(r, size)` — a rect of `size` centered inside `r`, used for each panel's move
  handle.
- `rect_uplx`/`rect_uprx`/`rect_dwlx`/`rect_dwrx(r, size)` — a rect of `size` tucked into each
  corner of `r`, used for the four resize handles.
- `rect_corner_roundness(r, radius)` — `rl.DrawRectangleRounded`'s `roundness` parameter is a
  *fraction of the rect's shorter side*, so the same `roundness` value produces a different-looking
  corner radius on differently-sized/shaped rects. This inverts that: given a desired **fixed
  pixel radius**, it returns the `roundness` fraction that reproduces it on rect `r` specifically.
  Every rounded-rect draw goes through this instead of a raw `roundness` literal, which is why
  every rounded corner in the app (slots, panels, drag handles) reads as the same visual radius
  regardless of the shape's aspect ratio.
- `rect_end(r)` — returns `(x+w, y+h)`. Currently unused.

## The slot model

Layout position/size is tracked in **slot units** (small integers), separately from the
pixel-space `Rect` used for drawing — `tile_to_rect` is the only place the two meet.

```odin
Tile :: struct { x, y, w, h: int }   // top-left slot + size, in slots

Panel :: struct {
    tile:     Tile,
    min_size: [2]int,   // smallest allowed tile size, in slots
    max_size: [2]int,   // largest allowed tile size, in slots
}

Slots :: struct {
    w, h:         int,                              // grid size, in slots
    panels:       [dynamic; MAX_PANELS]Panel,      // fixed-capacity, no heap allocation
    drag_op:      DragOperation,
    raised_panel: int,                              // index of the panel drawn on top, -1 if none
}
```

`panels` uses Odin's `[dynamic; N]T` fixed-capacity dynamic array (see the "Bounded/inline
growable arrays" section of [`odin-language-overview.md`](./odin-language-overview.md)) —
`append`/indexing work normally, but it never allocates and refuses to grow past `MAX_PANELS`
(128).

**Panels are allowed to overlap by design.** There is no general occupancy check between existing
panels — `slots_contains_tile` only checks grid bounds. The only place occupancy is checked at all
is *placing a brand-new panel from a free slot* (`slots_can_place_panel`/`slots_is_free`), so you
can't accidentally spawn a panel directly on top of an existing one — but once placed, panels can
be dragged and resized freely on top of each other.

**Z-order is one index, not array order.** Panels never move within `slots.panels`, so any index
held elsewhere (like `drag_op.panel_idx`) stays valid. `raised_panel` names the one panel drawn on
top; raising a panel just sets that index. `slots_panels`/`slots_panels_next` is an Odin-style
iterator yielding panels in draw order — every other panel in array order, then the raised one
last:

```odin
it := slots_panels(&slots)
for p, i in slots_panels_next(&it) { ... }
```

Only one panel is "raised" at a time: raising A then B puts A back at its array position rather
than second from the top. Newly added panels are raised automatically.

Slot-grid procedures, all in the `SLOTS` section of `main.odin`:

| Proc | Purpose |
|---|---|
| `slots_add_panel(slots, candidate)` | Appends `candidate` if its tile is in bounds, and raises it; returns its index or `-1` |
| `slots_contains_tile(slots, tile)` | Pure grid-bounds check (no overlap check) |
| `slots_is_free(slots, x, y)` | Whether slot `(x,y)` is outside every panel's tile |
| `slots_can_place_panel(slots, x, y, w, h)` | Combines the two above, for the "click a free slot to add" flow |
| `slots_panels` / `slots_panels_next` | Draw-order iterator (raised panel last) |
| `tile_to_rect(tile, slot_px, origin)` | Slot coords → pixel-space `Rect` |
| `slots_panel_move_h`/`_v(slots, panel_idx, dir)` | Moves the panel's tile one slot along one axis by `sign(dir)`, refusing (leaving state untouched) if that goes out of bounds |
| `slots_panel_expand_up`/`_dw`/`_lx`/`_rx(slots, panel_idx, dir)` | Moves one edge one slot — outward (grow) for `dir > 0`, inward (shrink) for `dir < 0` — keeping the opposite edge fixed |
| `slots_panel_try_resize(slots, panel_idx, candidate)` | Shared check behind the expand procs: commits only if the tile stays in bounds and within `min_size`/`max_size` |

Note the sign convention differs between the two families: `move_*` take a *screen* direction
(`dir < 0` = up/left), while `expand_*` take *outward vs. inward* for that edge — so
`slots_panel_expand_up(…, 1)` moves the top edge up the screen.

## Drag / edit mode

`edit_mode` is a `bool` toggled by `Tab` (`rl.IsKeyPressed(.TAB)`). When on: the slot area dims
under a translucent overlay, and every panel gets a pill-shaped move handle centered on it
(`rect_centered`, 60% of the panel's width) plus a square resize handle in each corner.

```odin
DragOperation :: struct {
    active:      bool,
    panel_idx:   int,
    mouse_start: [2]f32,     // mouse position when the drag began
    tile_start:  Tile,       // the panel's tile when the drag began
    optype:      DragType,   // Move, or one of the four Resize* corners
}
```

`draw_drag_handle(slots, optype, rect, panel_idx)` both draws a handle and, if it's clicked this
frame, starts a drag on it. Things about this that are easy to get wrong (several were bugs at some
point during development, which is why they're called out here):

- **`tile_start` exists to prevent drift.** Each frame recomputes the *total* slot-space delta since
  the drag started (`(mouse - mouse_start) / SLOT_PX`, truncated to whole slots) and computes each
  edge's *target* from `tile_start`, not from the tile's current (already-moved) position. Each
  edge then steps one slot per frame toward its target. Computing the delta against the current
  position instead would double-apply movement and make the panel run away from the cursor.
- **The frontmost handle wins a click.** Handles are drawn in iterator order (raised panel last),
  and a click overwrites `drag_op` without checking whether it's already active — so when handles
  overlap under the cursor, the last one drawn (the frontmost) is the one that ends up in
  `drag_op`. This is safe because `drag_op` is zeroed every frame the mouse button is up, so it's
  always inactive on the frame a press happens.
- **Raising happens after the handle loop, not during it.** Setting `raised_panel` changes the
  iterator's order; doing it mid-loop would skip or repeat a panel for that frame. The loop only
  fills in `drag_op`; `raised_panel = drag_op.panel_idx` runs once, after the loop finishes.
- **Drags are applied before drawing**, so each frame the panel and its handles are drawn at the
  same, already-updated position.

## Render loop (`main`)

Per-frame, in order:
1. Background clear. `Tab` toggles `edit_mode`; `drag_op` is reset to its zero value whenever the
   left mouse button isn't held (`!rl.IsMouseButtonDown`), so a drag can't survive past its own
   mouse-up.
2. **Status bar** (`draw_status_bar`): "SOLARIS" wordmark at the bottom-right and, if
   `edit_mode`, an "EDIT" label at the bottom-left.
3. **Slot pass** (`draw_slots`): every slot is drawn as a rounded square; a slot only highlights
   (and, in edit mode, shows "add") if `slots_can_place_panel` says a new panel would fit there
   (occupied slots and slots too close to the grid edge don't respond to hover/click at all).
   `draw_slots` returns the clicked slot, and `main` adds a `NEW_PANEL_SLOTS_W × NEW_PANEL_SLOTS_H`
   panel there (size range: 2 slots up to the full grid).
4. **Drag update** (only if `edit_mode` and a drag is active): moves or resizes the dragged
   panel's tile as described above.
5. **Panel pass**: every panel, in iterator order, is drawn by `draw_panel` as a filled rounded
   shape with a crisp border, sharing one `roundness`/`PANEL_SEGMENTS`. A three-ring outer-glow
   effect (repeated `rect_inset` with a negative amount) is present but commented out.
6. **Edit-mode pass** (only if `edit_mode`): `draw_edit_shadow` over the slot area, then each
   panel's move and resize handles, then the raise.

`rl.SetConfigFlags({.MSAA_4X_HINT})` is set before `rl.InitWindow` — required for any of the
rounded-rect/circle edges to look smooth rather than aliased; raylib's shape drawing has no
anti-aliasing of its own, and segment count alone (`PANEL_SEGMENTS`) only affects how *circular*
a curve is, not how smooth its rasterized edge is.

### Constants (all in the `RENDER` section, except `MAX_PANELS`)

| Constant | Meaning |
|---|---|
| `SLOT_PX` | Pixel size of one slot |
| `SLOTS_INIT_W`/`SLOTS_INIT_H` | Initial grid dimensions, in slots |
| `STATUS_BAR_H`, `PAD` | Status-bar height and outer margin, in pixels |
| `CORNER_RADIUS` | The fixed pixel corner radius fed to `rect_corner_roundness` everywhere |
| `PANEL_SEGMENTS` | Arc segments per rounded corner for panels (slots still use a literal `16`) |
| `NEW_PANEL_SLOTS_W`/`_H` | Size (in slots) of a panel created by clicking a free slot |
| `MAX_PANELS` | Capacity of `Slots.panels` (in the `SLOTS` section) |

`ui_font` is a global (not a constant): it can only be loaded after `rl.InitWindow`, so `main`
assigns it at startup and every `draw_*` proc reads it directly.

## Known gaps

- **Parser and UI are disconnected** (see "The two halves" above) — this is the big one.
- **Panels have no theme or content yet** — `Panel` is just a tile plus a size range. The theme
  and the telemetry it displays are meant to live on `Panel`, never on `Tile`.
- `rect_end` is unused.
- **Test coverage is thin on the UI side.** `src/main_test.odin` covers the parser layers and the
  `slots_panel_expand_*` resize procs (grow/shrink per edge, grid bounds, size range); the rest of
  `Slots` (iterator order, move, placement) and all drag/render logic in `main` are untested. That
  matters here because this code has already had several real bugs (index/position drift,
  mid-iteration array mutation, unsigned underflow from an earlier `u32`-based tile type) caught
  only by manual play-testing.
- **Debug output is `fmt.println`/`fmt.printfln` to stdout**, which only reaches anywhere useful
  in a normal console-attached run (`./dev.sh`). The packaged release build
  (see [`package.sh`](../package.sh), which passes `-subsystem:windows`) has no console at all, so
  those prints currently go nowhere in a distributed build. Surfacing logs in the UI itself would
  need a custom `context.logger` (see `core:log`'s `Logger`/`Logger_Proc`) feeding an in-app panel,
  rather than relying on OS-level stdout capture.

## See also

- `CLAUDE.md`'s Architecture section — the parser layer, at orientation depth.
- [`cosmos/config-format.md`](./cosmos/config-format.md) — the keyword semantics the parser
  targets, and what a future `Packet`/`Item` data model (and eventually a real telemetry panel
  instead of a placeholder) would need to represent.
- [`odin-language-overview.md`](./odin-language-overview.md) — language features referenced above
  (`[dynamic; N]T`, multi-return, etc.), with examples pulled from this file.
- [`references.md`](./references.md) — external docs (Odin, raylib, the font in use) worth having
  open while working on this file.
