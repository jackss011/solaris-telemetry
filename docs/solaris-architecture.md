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
2. **The tile/window-manager UI** (`Box`, `TiledBox`/`TiledWindow`/`Tiles`, `DragOperation`, and
   `main`'s render loop). This is what actually runs when you launch the program, and it's what
   the rest of this doc covers.

**These are not wired together.** `main` no longer calls `parse_config_file` — the old
entry point that did (`fmt.println("Hello basic parse example!"); parse_config_file(...)`) is
still there, but commented out, sitting right above the tiling constants. `main` today launches a
generic tile grid and lets you click a cell to spawn a fixed-size placeholder panel (labeled
"Packet Viewer" only in a debug print, not from any parsed definition) — it has no knowledge of
`tlm.txt`, `TlmDef`, or `TlmItemDef` at all. Turning "click a cell" into "click a cell and pick a
real parsed telemetry packet to display" is the integration step that doesn't exist yet.

## `Box`: pixel-space rectangles

`Box :: struct { x, y, w, h: f32 }` is the one geometry primitive the UI uses, always in pixel
space. Its helpers:

- `box_inset(b, inset)` — shrinks a box by `inset` on all sides (used to put visual padding
  between a tile's/window's hit-box and its drawn fill). A **negative** inset grows the box
  instead, which the window glow effect (below) relies on.
- `box_to_rl(b)` — converts to `rl.Rectangle` for raylib draw calls.
- `box_contains(b, point)` — half-open bounds test (`x` in `[b.x, b.x+b.w)`, same for `y`), used
  for both grid-cell hover and drag-handle hit-testing.
- `box_centered(b, size)` — a box of `size` centered inside `b`, used to place the small
  draggable handle above each window panel.
- `box_corner_roundness(b, radius)` — `rl.DrawRectangleRounded`'s `roundness` parameter is a
  *fraction of the box's shorter side*, so the same `roundness` value produces a different-looking
  corner radius on differently-sized/shaped boxes. This inverts that: given a desired **fixed
  pixel radius**, it returns the `roundness` fraction that reproduces it on box `b` specifically.
  Every rounded-rect draw in `main` goes through this instead of a raw `roundness` literal, which
  is why every rounded corner in the app (grid cells, window panels, drag handles) reads as the
  same visual radius regardless of the shape's aspect ratio.
- `box_end(b)` — returns `(x+w, y+h)`. Currently unused (dead code) — an earlier version of the
  window-sizing math used it; `main` now computes `window_w`/`window_h` directly.

## The tile-grid model

Grid position/size is tracked in **tile units** (small integers), separately from the pixel-space
`Box` used for drawing — `tiles_window_to_box` is the only place the two meet.

```odin
TiledBox :: struct { n_x, n_y, n_w, n_h: int }   // grid-cell coordinates + size

TiledWindow :: struct {
    box:      TiledBox,
    range_nw: [2]int,   // reserved: (min, max) allowed width in tiles — not read anywhere yet
    range_nh: [2]int,   // reserved: (min, max) allowed height in tiles — not read anywhere yet
}

Tiles :: struct {
    n_w, n_h: int
    windows:  [dynamic; MAX_WINDOWS]TiledWindow   // fixed-capacity, no heap allocation
}
```

`windows` uses Odin's `[dynamic; N]T` fixed-capacity dynamic array (see the "Bounded/inline
growable arrays" section of [`odin-language-overview.md`](./odin-language-overview.md)) —
`append`/`ordered_remove`/indexing all work normally, but it never allocates and silently refuses
to grow past `MAX_WINDOWS` (128).

**Windows are allowed to overlap by design.** There is no general occupancy check between
existing windows — `tiles_is_in_bounds` only checks grid bounds, nothing else. The only place
occupancy is checked at all is *placing a brand-new window from an empty grid cell*
(`tiles_can_place_new_window`/`tiles_cell_is_free`), so you can't accidentally spawn a new window
directly on top of an existing one — but once placed, windows can be dragged freely on top of
each other.

**Z-order is just array order.** There's no separate z-index field: both render loops in `main`
draw `tiles.windows` front-to-back in array order, so "on top" literally means "later in the
array." `tiles_raise_to_front(tiles, win_idx)` implements "bring to front" by removing that
window and re-appending it — nothing fancier. Newly created windows are already appended last, so
they're on top by construction with no extra step needed.

Tile-grid procedures, all in `Tiles`' section of `main.odin`:

| Proc | Purpose |
|---|---|
| `tiles_new_window(tiles, candidate)` | Appends `candidate` if in bounds; returns its index or `-1` |
| `tiles_is_in_bounds(tiles, window)` | Pure grid-bounds check (no overlap check) |
| `tiles_cell_is_free(tiles, x, y)` | Whether grid cell `(x,y)` falls inside any existing window |
| `tiles_can_place_new_window(tiles, x, y, w, h)` | Combines the two above, for the "click empty cell to add" flow |
| `tiles_raise_to_front(tiles, win_idx)` | Moves a window to the end of the array (z-order) |
| `tiles_window_to_box(window, tile_px, origin)` | Tile-grid coords → pixel-space `Box` |
| `tiles_window_move_h`/`_v(tiles, win_idx, dir)` | Nudges one axis by `sign(dir)` tiles, refusing (leaving state untouched) if that goes out of bounds |

## Drag / edit mode

`edit_mode` is a `bool` toggled by `Tab` (`rl.IsKeyPressed(.TAB)`). When on: the grid dims under a
translucent overlay, and every placed window gets a small pill-shaped drag handle centered above
it (`box_centered` + a fixed y-offset).

```odin
DragOperation :: struct {
    active:      bool,
    win_idx:     int,
    mouse_start: [2]f32,     // mouse position when the drag began
    box_start:   TiledBox,   // the window's tile position when the drag began
    optype:      DragType,   // Move (implemented) or Resize (defined, not implemented)
}
```

Two things about this that are easy to get wrong (both were bugs at some point during
development, which is why they're called out here):

- **`box_start` exists to prevent drift.** Each frame recomputes the *total* tile-space delta
  since the drag started (`(mouse - mouse_start) / GRID_PX`, converted to a step) and applies it
  against the window's position *when the drag began* (`box_start`), not against whatever
  `tiles.windows[i]` currently holds. Since the window's live position is mutated in place every
  frame, computing the delta against the *current* (already-moved) position instead of the
  original would double-apply movement and make the window run away from the cursor.
- **Raising to front happens after the per-window loop, not during it.** `tiles_raise_to_front`
  removes an element and re-appends it, which shifts every later index down by one. Doing that
  mid-iteration (inside `for w, i in tiles.windows`) would corrupt the rest of that frame's pass —
  wrong window drawn at the wrong index for whatever's left of the loop. Instead, the loop just
  records `raise_idx` when a handle is clicked, and the actual reorder happens once, after the
  loop finishes.
- `DragType.Resize` is defined but nothing sets or handles it yet — only `Move` is implemented.

## Render loop (`main`)

Per-frame, in order:
1. `Tab` toggles `edit_mode`; `drag_op` is reset to its zero value whenever the left mouse button
   isn't held (`!rl.IsMouseButtonDown`), so a drag can't survive past its own mouse-up.
2. Background clear, "SOLARIS" wordmark (bottom-right of the header strip) and, if `edit_mode`,
   an "EDIT" label (bottom-left, same strip).
3. **Grid pass**: every empty-cell candidate is drawn as a rounded square; a cell only highlights
   and shows "add" if `tiles_can_place_new_window` says a new window would actually fit there
   (occupied cells and cells too close to the grid edge just don't respond to hover/click at all).
   A click on such a cell creates a `NEW_WINDOW_TILES_W × NEW_WINDOW_TILES_H` window there.
4. **Window pass**: every placed window is drawn as a filled rounded panel, three widening/fading
   outline rings behind it (a cheap outer-glow effect via repeated `box_inset` with a negative
   amount), and one crisp bright border on top — all sharing one `roundness`/`PANEL_SEGMENTS` so
   the glow rings trace the same corners as the fill instead of drifting into a different shape as
   they expand outward.
5. **Edit-mode pass** (only if `edit_mode`): the screen-shade overlay, then each window's drag
   handle (hit-tested, colored differently while being dragged), with the move/raise-to-front
   logic described above.

`rl.SetConfigFlags({.MSAA_4X_HINT})` is set before `rl.InitWindow` — required for any of the
rounded-rect/circle edges to look smooth rather than aliased; raylib's shape drawing has no
anti-aliasing of its own, and segment count alone (`PANEL_SEGMENTS`) only affects how *circular*
a curve is, not how smooth its rasterized edge is.

### Constants (all in the `RENDER` section)

| Constant | Meaning |
|---|---|
| `GRID_PX` | Pixel size of one grid cell |
| `GRID_INIT_W`/`GRID_INIT_H` | Initial grid dimensions, in tiles |
| `HEADER_H`, `PAD` | Header-strip height and outer margin, in pixels |
| `CORNER_RADIUS` | The fixed pixel corner radius fed to `box_corner_roundness` everywhere |
| `PANEL_SEGMENTS` | Arc segments per rounded corner for window panels (grid cells still use a literal `16`) |
| `NEW_WINDOW_TILES_W`/`_H` | Size (in tiles) of a window created by clicking an empty cell |
| `MAX_TILES` | Declared but currently unused |
| `MAX_WINDOWS` | Capacity of `Tiles.windows` |

## Known gaps

- **Parser and UI are disconnected** (see "The two halves" above) — this is the big one.
- `TiledWindow.range_nw`/`range_nh` are set (to `{n_w, n_w}`/`{n_h, n_h}`, i.e. no slack) when a
  window is created, but nothing reads them — they're scaffolding for a future resize-range
  constraint.
- `DragType.Resize` is unimplemented.
- `box_end` and `MAX_TILES` are unused.
- **No test coverage.** `src/main_test.odin` only exercises the parser's token/keyword layers
  (see `CLAUDE.md`'s "Known issues"); none of `Box`, `Tiles`, `TiledWindow`, or the drag logic has
  any tests. That's a bigger gap here than it is for the parser, since this code has already had
  several real bugs (index/position drift, mid-iteration array mutation, unsigned underflow from
  an earlier `u32`-based version of `TiledBox`) caught only by manual play-testing.
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
