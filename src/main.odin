package main

import "core:os"
import "core:strings"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// ========== ASCII UTILS ============

is_ascii_letter :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b == '_')
}


// ========== TOKEN ============

TokenType :: enum {
    NONE,
    NEWLINE,
    IDENT,
    STR,
    INT,
    FLOAT,
    COMMENT,
}

TokenRef :: struct {
    type:      TokenType,
    idx_start: int,
    idx_end:   int,
}

token_ref_text :: proc(token: TokenRef, text: string) -> string {
    return text[token.idx_start:token.idx_end]
}

grab_token :: proc(text: string, idx: int) -> TokenRef {
    token := TokenRef{TokenType.NONE, 0, 0}
    found := false
    error := false

    for i := idx; i < len(text) && !found && !error; i += 1 {
        b := text[i] // Yields u8

        #partial switch token.type {

        case TokenType.NONE:
            switch b {
                case '\n':
                    token.type = TokenType.NEWLINE
                    token.idx_end = i+1
                    found = true
                case '"':
                    token.type = TokenType.STR
                case '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                    token.type = TokenType.INT
                case '.':
                    token.type = TokenType.FLOAT
                case '\t', '\v', '\f', '\r', ' ':
                    token.type = TokenType.NONE
                case '#':
                    token.type = TokenType.COMMENT
                case:
                    token.type = TokenType.IDENT
            }

            token.idx_start = i

        case TokenType.IDENT:
            switch b {
                case ' ', '\t', '\v', '\f', '\r', '\n', '"', '#':
                    token.idx_end = i
                    found = true
            }

        case TokenType.STR:
            switch b {
                case '\t', '\v', '\f':
                    fmt.println("ERROR: character not allowed inside of string")
                    error = true
                case '\n', '\r':
                    fmt.println("ERROR: string was not completed") // no multiline string
                    error = true
                case '"':
                    assert(token.idx_start+1 <= i)
                    token.idx_end = i+1
                    found = true
            }

        case TokenType.INT:
            switch b {
                case '\t', '\v', '\f', '\n', '\r', ' ', '"', '#':
                    token.idx_end = i
                    found = true
                case '.', 'e':
                    token.type = TokenType.FLOAT // convert to float
                case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                    // nominal
                case:
                    if is_ascii_letter(b) {
                        fmt.printfln("ERROR: character %c not allowed in float", b) // no multiline string
                        error = true
                    } else {
                        token.idx_end = i
                        found = true
                    }
            }

        case TokenType.FLOAT:
            switch b {
                case '\t', '\v', '\f', '\n', '\r', ' ', '"', '#':
                    token.idx_end = i
                    found = true
                case '.', 'e', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                    // nominal
                case:
                    if is_ascii_letter(b) {
                        fmt.printfln("ERROR: character %c not allowed in float", b) // no multiline string
                        error = true
                    } else {
                        token.idx_end = i
                        found = true
                    }
            }

        case TokenType.COMMENT:
            assert(i >= 1)
            switch b {
                case '\n', '\r':
                    token.idx_end = i
                    found = true
            }
        }
    }

    if error { os.exit(32) }

    // Ran out of input before a delimiter closed the token: treat EOF as an implicit terminator
    // instead of returning idx_end=0, which would make the caller rewind to the start of the
    // file forever. type==NONE here means we were between tokens (trailing whitespace/nothing
    // left) rather than mid-token.
    if !found {
        if token.type == TokenType.NONE {
            token.idx_start = len(text)
        }
        token.idx_end = len(text)
    }

    return token
}

print_token_ref :: proc(token: TokenRef, text: string) {
    switch token.type {
        case TokenType.NONE:
            fmt.println("none")
        case TokenType.NEWLINE:
            fmt.println("newline")
        case TokenType.IDENT:
            fmt.printfln("ident(%s)", text[token.idx_start:token.idx_end])
        case TokenType.STR:
            fmt.printfln("string(%s)", text[token.idx_start:token.idx_end])
        case TokenType.INT:
            fmt.printfln("int(%s)", text[token.idx_start:token.idx_end])
        case TokenType.FLOAT:
            fmt.printfln("float(%s)", text[token.idx_start:token.idx_end])
        case TokenType.COMMENT:
            fmt.printfln("comment(%s)", text[token.idx_start:token.idx_end])
    }
}

// ========== KEYWORD ============

MAX_KEYWORD_PARAMS :: 16

Keyword :: struct {
    token:        TokenRef,
    params:       [MAX_KEYWORD_PARAMS]TokenRef,
    params_count: int,
    raw_idx_start: int,
    raw_idx_end: int
}

print_keyword :: proc(keyword: Keyword, text: string) {
    fmt.printf("%s(", text[keyword.token.idx_start:keyword.token.idx_end])
    for i in 0..<keyword.params_count {
        if i > 0 {
            fmt.printf(", ")
        }
        param := keyword.params[i]
        fmt.printf("%s", text[param.idx_start:param.idx_end])
    }
    fmt.printf(")")

    if keyword.raw_idx_end > keyword.raw_idx_start {
        raw := strings.trim_space(text[keyword.raw_idx_start:keyword.raw_idx_end])
        fmt.printf(" -- %s", raw)
    }

    fmt.println()
}

// Pulls one logical COSMOS line (keyword + its params) starting at idx, skipping over blank
// lines and comment-only lines along the way. All storage is inline/fixed-size (no allocations)
// - params beyond MAX_KEYWORD_PARAMS on one line will assert. Mirrors grab_token's shape: call
// it in a loop, feeding `next_idx` back in as `idx`, until the returned keyword.token.type is
// TokenType.NONE (end of file).
grab_keyword :: proc(text: string, idx: int) -> (keyword: Keyword, next_idx: int) {
    idx := idx

    for {
        token := grab_token(text, idx)
        idx = token.idx_end

        #partial switch token.type {
        case TokenType.NONE:
            return keyword, idx

        case TokenType.NEWLINE:
            if keyword.token.type != TokenType.NONE {
                return keyword, idx
            }
            // blank line before any keyword on it yet - keep scanning

        case TokenType.COMMENT:
            // comment-only line - keep scanning

        case:
            if keyword.token.type == TokenType.NONE {
                keyword.token = token
            } else {
                assert(keyword.params_count < len(keyword.params))
                keyword.params[keyword.params_count] = token
                keyword.params_count += 1
            }
        }
    }
}

// ============ RAW ============
// Scans forward line-by-line from idx looking for a line whose first word (leading spaces/tabs
// skipped) is exactly `needle`. Returns the index where that line begins - so text[idx:end_idx]
// is everything up to but not including it, verbatim - and whether `needle` was found before
// EOF. On failure, end_idx is len(text).
grab_until :: proc(text: string, idx: int, needle: string) -> (found: bool, end_idx: int) {
    i := idx
    for i < len(text) {
        line_start := i

        j := i
        for j < len(text) && (text[j] == ' ' || text[j] == '\t') {
            j += 1
        }
        word_start := j
        for j < len(text) && text[j] != '\n' && text[j] != '\r' && text[j] != ' ' && text[j] != '\t' {
            j += 1
        }

        word := text[word_start:j]
        if word == needle {
            return true, line_start
        }

        for i < len(text) && text[i] != '\n' {
            i += 1
        }
        if i >= len(text) {
            break
        }
        i += 1
    }

    return false, len(text)
}

// =========== PARSE ENTRY =============

parse_config_file :: proc(filepath: string) {
    data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		// could not read file
        fmt.println("failed to load file")
		return
	}
	defer delete(data, context.allocator)

    text := string(data)
    idx := 0

    for {
        keyword, next_idx := grab_keyword(text, idx)
        idx = next_idx

        if keyword.token.type == TokenType.NONE {
            break
        }

        // look for raw sections
        if keyword.token.type == TokenType.IDENT {
            raw_mode_until: string

            switch token_ref_text(keyword.token, text) {
                case "GENERIC_READ_CONVERSION_START":
                    raw_mode_until = "GENERIC_READ_CONVERSION_END"
                case "GENERIC_WRITE_CONVERSION_START":
                    raw_mode_until = "GENERIC_WRITE_CONVERSION_END"
            }

            if raw_mode_until != "" {
                found, end_idx := grab_until(text, idx, raw_mode_until)
                keyword.raw_idx_start = idx
                keyword.raw_idx_end = end_idx

                if(!found) {
                    fmt.printfln("[ERROR] %s not found!", raw_mode_until)
                    os.exit(32)
                }

                // consume the END line itself so it doesn't get emitted as its own keyword
                _, idx = grab_keyword(text, end_idx)
            }
        }

        // debug print
        print_keyword(keyword, text)
    }
}

TlmDef :: struct {
    target:        string,
    name:          string,
    little_endian: bool,
    desc:          string,
}

TlmItemType :: enum {
    None,
    INT, UINT, FLOAT, STRING, BLOCK, DERIVED,
}

TlmItemArray :: struct {
    num: int,
}

TlmItemId :: struct {
    value_str: string,
}

TlmItemSuper :: union {TlmItemId, TlmItemArray}

TlmItemDef :: struct {
    name:          string,
    bit_offset:    int,
    bit_len:       int,
    type:          TlmItemType,
    little_endian: bool,
    desc:          string,
    super:         TlmItemSuper,
}


// main :: proc() {
//     fmt.println("Hello basic parse example!")
//     parse_config_file("examples/simple_tlm/tlm.txt")
// }




/* ::::::::::::::::::::::::::: RECT ::::::::::::::::::::::::::: */

// A rectangle in (float) screen pixels.
Rect :: struct {
    x : f32,
    y : f32,
    w : f32,
    h : f32,
}

rect_inset :: proc(r : Rect, inset: f32) -> Rect {
    half := inset / 2
    return Rect{r.x + half, r.y + half, r.w - inset, r.h - inset}
}

rect_to_rl :: proc(r: Rect) -> rl.Rectangle {
    return rl.Rectangle{r.x, r.y, r.w, r.h}
}

rect_end :: proc(r: Rect) -> (f32, f32) {
    return r.x + r.w, r.y + r.h
}

rect_contains :: proc(r: Rect, point: [2]f32) -> bool {
    return point.x >= r.x && point.x < r.x + r.w && point.y >= r.y && point.y < r.y + r.h
}

rect_centered :: proc(r: Rect, size: [2]f32) -> Rect {
    return Rect{r.x + r.w/2 - size.x/2, r.y + r.h/2 - size.y/2, size.x, size.y}
}

// Rects of the given size tucked into each corner of r (inside it).
rect_uplx :: proc(r: Rect, size: [2]f32) -> Rect {
    return Rect{r.x, r.y, size.x, size.y}
}

rect_uprx :: proc(r: Rect, size: [2]f32) -> Rect {
    return Rect{r.x + r.w - size.x, r.y, size.x, size.y}
}

rect_dwlx :: proc(r: Rect, size: [2]f32) -> Rect {
    return Rect{r.x, r.y + r.h - size.y, size.x, size.y}
}

rect_dwrx :: proc(r: Rect, size: [2]f32) -> Rect {
    return Rect{r.x + r.w - size.x, r.y + r.h - size.y, size.x, size.y}
}

// Splits r in two: `fixed` is `size` px thick along `edge` (e.g. .Up = a header strip across the
// top), `rest` is what's left after a `gap` between them. Both are clamped to r, so a size/gap
// bigger than r gives an empty `rest` rather than a negative one.
rect_split2 :: proc(r: Rect, edge: Edge, size: f32, gap: f32 = 0) -> (fixed, rest: Rect) {
    switch edge {
    case .Up:
        s := min(size, r.h)
        return Rect{r.x, r.y, r.w, s}, Rect{r.x, r.y + s + gap, r.w, max(r.h - s - gap, 0)}
    case .Dw:
        s := min(size, r.h)
        return Rect{r.x, r.y, r.w, max(r.h - s - gap, 0)}, Rect{r.x, r.y + r.h - s, r.w, s}
    case .Lx:
        s := min(size, r.w)
        return Rect{r.x, r.y, s, r.h}, Rect{r.x + s + gap, r.y, max(r.w - s - gap, 0), r.h}
    case .Rx:
        s := min(size, r.w)
        return Rect{r.x, r.y, max(r.w - s - gap, 0), r.h}, Rect{r.x + r.w - s, r.y, s, r.h}
    }
    return
}

// rl.DrawRectangleRounded's `roundness` is relative to the rect's shorter side, so the same
// value produces a different-looking corner radius on differently-sized/shaped rects. This
// converts a fixed pixel radius into the roundness fraction that reproduces it on rect `r`,
// so the corner radius stays constant (equal on every side) regardless of the rect's length.
rect_corner_roundness :: proc(r: Rect, radius: f32) -> f32 {
    shorter := min(r.w, r.h)
    if shorter <= 0 {
        return 0
    }
    return clamp(radius * 2 / shorter, 0, 1)
}

/* ::::::::::::::::::::::::::: DRAG ::::::::::::::::::::::::::: */

DragType :: enum {
    Move,
    Resize,
}

Edge :: enum {
    Up,
    Dw,
    Lx,
    Rx,
}

DragOperation :: struct {
    active: bool,
    panel_idx: int,
    mouse_start: [2]f32,
    tile_start: Tile,
    optype: DragType,
    edges: bit_set[Edge], // for Resize: which edges follow the mouse, e.g. {.Up, .Lx} = top-left corner
}

/* ::::::::::::::::::::::::::: SLOTS ::::::::::::::::::::::::::: */

// Layout vocabulary:
// - slot:   one cell of the layout grid (int coordinates)
// - tile:   a rectangle of whole slots (ints) - pure geometry, no theme
// - panel:  what's attached to a tile and drawn on screen - its Rect (float pixels) is derived
//           from its tile every frame; it's what will carry a UI theme and telemetry content
// - window: only ever the OS window

MAX_PANELS :: 128

// A rectangle of slots: top-left slot (x, y), size (w, h) in slots.
Tile :: struct {
    x: int,
    y: int,
    w: int,
    h: int,
}

Panel :: struct {
    tile: Tile,
    min_size: [2]int, // in slots
    max_size: [2]int, // in slots
}

Slots :: struct {
    w: int,
    h: int,
    panels: [dynamic; MAX_PANELS]Panel,
    drag_op: DragOperation,
    raised_panel: int, // panel drawn on top of every other one, -1 if none
}

PanelIter :: struct {
    slots: ^Slots,
    pos: int,
}

slots_panels :: proc(slots: ^Slots) -> PanelIter {
    return PanelIter{slots = slots}
}

// Yields panels in draw order: every non-raised panel in array order, then the raised one
// last so it ends up on top. Panels never move in the array, so the yielded index stays valid
// to hold elsewhere (e.g. drag_op.panel_idx). Usage:
//     it := slots_panels(&slots)
//     for p, i in slots_panels_next(&it) { ... }
slots_panels_next :: proc(it: ^PanelIter) -> (panel: Panel, idx: int, ok: bool) {
    n := len(it.slots.panels)
    raised := it.slots.raised_panel
    has_raised := raised >= 0 && raised < n

    for it.pos < n {
        idx = it.pos
        it.pos += 1
        if has_raised && idx == raised {
            continue
        }
        return it.slots.panels[idx], idx, true
    }

    if has_raised && it.pos == n {
        it.pos += 1
        return it.slots.panels[raised], raised, true
    }
    return {}, -1, false
}

// Adds a panel, if its tile is within the slot grid, and raises it. Panels are allowed to
// overlap. Returns -1 if out of bounds or the panel store is full.
slots_add_panel :: proc(slots: ^Slots, candidate: Panel) -> int {
    if !slots_contains_tile(slots^, candidate.tile) {
        return -1
    }
    if append(&slots.panels, candidate) == 0 {
        return -1
    }
    slots.raised_panel = len(slots.panels) - 1
    return slots.raised_panel
}

slots_contains_tile :: proc(slots: Slots, t: Tile) -> bool {
    return t.x >= 0 && t.y >= 0 && t.x + t.w <= slots.w && t.y + t.h <= slots.h
}

// Whether slot (x, y) is outside every panel's tile.
slots_is_free :: proc(slots: Slots, x: int, y: int) -> bool {
    for p in slots.panels {
        t := p.tile
        if x >= t.x && x < t.x + t.w && y >= t.y && y < t.y + t.h {
            return false
        }
    }
    return true
}

// Whether a new panel of size (w, h) slots could be placed with its top-left at slot (x, y):
// that slot must be free, and the whole tile must stay within the slot grid.
slots_can_place_panel :: proc(slots: Slots, x: int, y: int, w: int, h: int) -> bool {
    if !slots_is_free(slots, x, y) {
        return false
    }
    return slots_contains_tile(slots, Tile{x, y, w, h})
}

tile_to_rect :: proc(t: Tile, slot_px: f32, origin: [2]f32) -> Rect {
    return Rect{
        origin.x + f32(t.x) * slot_px,
        origin.y + f32(t.y) * slot_px,
        f32(t.w) * slot_px,
        f32(t.h) * slot_px,
    }
}

// Nudges the panel at panel_idx one slot up (dir < 0) or down (dir > 0), leaving its column and
// size unchanged. Refuses (leaving slots.panels untouched) if that would push it out of the slot
// grid; overlapping other panels is allowed. Returns whether the move happened.
slots_panel_move_v :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.y += math.sign(dir)

    if !slots_contains_tile(slots^, candidate.tile) {
        return false
    }

    slots.panels[panel_idx] = candidate
    return true
}

// Nudges the panel at panel_idx one slot left (dir < 0) or right (dir > 0), leaving its row and
// size unchanged. Refuses (leaving slots.panels untouched) if that would push it out of the slot
// grid; overlapping other panels is allowed. Returns whether the move happened.
slots_panel_move_h :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.x += math.sign(dir)

    if !slots_contains_tile(slots^, candidate.tile) {
        return false
    }

    slots.panels[panel_idx] = candidate
    return true
}

// Commits candidate to panel_idx if its tile stays within the slot grid and its size stays
// within the panel's own min_size/max_size. Returns whether it was committed.
slots_panel_try_resize :: proc(slots: ^Slots, panel_idx: int, candidate: Panel) -> bool {
    t := candidate.tile
    if t.w < candidate.min_size.x || t.w > candidate.max_size.x ||
       t.h < candidate.min_size.y || t.h > candidate.max_size.y {
        return false
    }
    if !slots_contains_tile(slots^, t) {
        return false
    }

    slots.panels[panel_idx] = candidate
    return true
}

// The expand procs move one edge of the panel at panel_idx by one slot: outward (grow) for
// dir > 0, inward (shrink) for dir < 0, keeping the opposite edge fixed. Refuses (leaving
// slots.panels untouched) if that would leave the slot grid or break the panel's size range;
// overlapping other panels is allowed. Returns whether the resize happened.

slots_panel_expand_up :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.y -= math.sign(dir)
    candidate.tile.h += math.sign(dir)
    return slots_panel_try_resize(slots, panel_idx, candidate)
}

slots_panel_expand_dw :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.h += math.sign(dir)
    return slots_panel_try_resize(slots, panel_idx, candidate)
}

slots_panel_expand_lx :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.x -= math.sign(dir)
    candidate.tile.w += math.sign(dir)
    return slots_panel_try_resize(slots, panel_idx, candidate)
}

slots_panel_expand_rx :: proc(slots: ^Slots, panel_idx: int, dir: int) -> bool {
    candidate := slots.panels[panel_idx]
    candidate.tile.w += math.sign(dir)
    return slots_panel_try_resize(slots, panel_idx, candidate)
}

// Advances the active drag (if any) toward the mouse. The target is always computed from where
// the drag started (tile_start/mouse_start), never from the current tile, so the panel can't
// drift; the mouse offset snaps to the nearest whole slot. Each edge then steps at most one slot
// per call toward its target - a refused step (grid edge, size range) just leaves it where it is.
slots_update_drag :: proc(slots: ^Slots, mouse: [2]f32, slot_px: f32) {
    op := slots.drag_op
    if !op.active {
        return
    }

    i := op.panel_idx
    cur := slots.panels[i].tile
    start := op.tile_start
    delta_drag := (mouse - op.mouse_start) / slot_px
    delta := [2]int{int(math.round(delta_drag.x)), int(math.round(delta_drag.y))}

    switch op.optype {
    case .Move:
        slots_panel_move_h(slots, i, start.x + delta.x - cur.x)
        slots_panel_move_v(slots, i, start.y + delta.y - cur.y)
    case .Resize:
        // signed distance (in slots) each edge still has to travel to reach its target -
        // positive means outward, matching the expand procs' dir
        if .Up in op.edges { slots_panel_expand_up(slots, i, cur.y - (start.y + delta.y)) }
        if .Dw in op.edges { slots_panel_expand_dw(slots, i, (start.y + start.h + delta.y) - (cur.y + cur.h)) }
        if .Lx in op.edges { slots_panel_expand_lx(slots, i, cur.x - (start.x + delta.x)) }
        if .Rx in op.edges { slots_panel_expand_rx(slots, i, (start.x + start.w + delta.x) - (cur.x + cur.w)) }
    }
}



/* ::::::::::::::::::::::::::: RENDER ::::::::::::::::::::::::::: */

BACKGROUND_COLOR := rl.Color{15, 15, 20, 255}
ui_font: rl.Font // loaded in main after InitWindow - raylib can't load fonts before a window exists
ui_font_14: rl.Font // Departure Mono - its 11px pixel grid is size 14 in raylib (ascent-to-descent height), the only pixel-exact size; 28/42 for 2x/3x
SLOT_PX :: 100
SLOTS_INIT_W :: 8
SLOTS_INIT_H :: 6
STATUS_BAR_H :: 32
PAD :: 8
CORNER_RADIUS :: 8
PANEL_SEGMENTS :: 36 // corner smoothness for rounded panels - higher = less jagged
NEW_PANEL_SLOTS_W :: 3
NEW_PANEL_SLOTS_H :: 4

// Draws a drag handle and starts a drag on it when clicked. Handles are drawn in slots_panels
// order (raised last), so if several overlap under the click the last one drawn (the frontmost)
// overwrites drag_op and wins. The caller raises drag_op.panel_idx after the loop, so the
// iteration order stays stable while it's running.
// edges is only meaningful for .Resize - pass {} for .Move.
draw_drag_handle :: proc(slots: ^Slots, optype: DragType, edges: bit_set[Edge], r: Rect, panel_idx: int) {
    mouse := rl.GetMousePosition()

    // should we enter moving?
    if rect_contains(r, mouse) && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        slots.drag_op.active = true
        slots.drag_op.optype = optype
        slots.drag_op.edges = edges
        slots.drag_op.panel_idx = panel_idx
        slots.drag_op.mouse_start = mouse
        slots.drag_op.tile_start = slots.panels[panel_idx].tile
    }

    op := slots.drag_op
    is_me_active := op.active && op.optype == optype && op.edges == edges && op.panel_idx == panel_idx

    rl.DrawRectangleRounded(
        rect_to_rl(r),
        rect_corner_roundness(r, CORNER_RADIUS),
        32,
        is_me_active ? rl.Color{140, 90, 80, 255} : rl.Color{100, 70, 70, 255},
    )
}

// Draws the slot grid with its top-left at r_origin, highlighting the hovered slot if a new panel
// could be placed there. Returns whether such a slot was clicked this frame, and which one.
draw_slots :: proc(slots: Slots, r_origin: Rect, edit_mode: bool) -> (clicked: bool, clicked_slot: [2]int) {
    mouse := rl.GetMousePosition()

    for iw in 0..<slots.w {
        for ih in 0..<slots.h {
            x, y := f32(iw*SLOT_PX)+r_origin.x, f32(ih*SLOT_PX)+r_origin.y
            r := Rect{x, y, f32(SLOT_PX), f32(SLOT_PX)}
            r1 := rect_inset(r, 8.0)

            can_add := edit_mode &&
                rect_contains(r, mouse) &&
                slots_can_place_panel(slots, iw, ih, NEW_PANEL_SLOTS_W, NEW_PANEL_SLOTS_H)

            rl.DrawRectangleRounded(
                rect_to_rl(r1),
                rect_corner_roundness(r1, CORNER_RADIUS),
                16,   // segments
                can_add ? rl.Color{45, 40, 40, 255} : rl.Color{30, 26, 26, 255}, // fill, translucent
            )

            if can_add {
                text_size := rl.MeasureTextEx(ui_font, "add", 20, 1)
                text_pos := rl.Vector2{
                    r.x + r.w/2 - text_size.x/2,
                    r.y + r.h/2 - text_size.y/2,
                }
                rl.DrawTextEx(ui_font, "add", text_pos, 20, 1, rl.Color{200, 210, 220, 255})

                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    clicked = true
                    clicked_slot = {iw, ih}
                }
            }
        }
    }
    return;
}

// Draws the status bar along the bottom of window: the "EDIT" badge on the left while in edit
// mode, and the "SOLARIS" logo on the right.
draw_status_bar :: proc(r_window: Rect, edit_mode: bool) {
    label_size := rl.MeasureTextEx(ui_font, "SOLARIS", STATUS_BAR_H, 2)
    label_color := rl.Color{207/3, 210/4, 220/4, 255}

    if edit_mode {
        rl.DrawTextEx(ui_font, "EDIT", rl.Vector2{PAD, r_window.h - PAD - STATUS_BAR_H + 3}, STATUS_BAR_H, 2, rl.Color{230, 180, 60, 255})
    }

    rl.DrawTextEx(ui_font, "SOLARIS",
        rl.Vector2{r_window.w - label_size.x - PAD*2, r_window.h - PAD - STATUS_BAR_H + 3},
        STATUS_BAR_H,
        2, label_color)
}

// Draws a panel as a rounded shape filling its tile's screen rect r, inset so neighbouring
// panels don't touch.
draw_panel :: proc(r: Rect) {
    r1 := rect_inset(r, 8.0)
    roundness := rect_corner_roundness(r1, CORNER_RADIUS)

    rl.DrawRectangleRounded(
        rect_to_rl(r1),
        roundness,
        PANEL_SEGMENTS,
        rl.Color{40, 30, 30, 255},
    )

    // // soft outer glow: a couple of widening, fading outlines behind the crisp border
    // for glow_i in 1..=3 {
    //     glow_r := rect_inset(r1, -f32(glow_i) * 3)
    //     alpha := u8(70 - glow_i * 20)
    //     rl.DrawRectangleRoundedLinesEx(
    //         rect_to_rl(glow_r),
    //         rect_corner_roundness(glow_r, CORNER_RADIUS),
    //         PANEL_SEGMENTS, 2,
    //         rl.Color{110, 190, 255, alpha},
    //     )
    // }

    rl.DrawRectangleRoundedLinesEx(
        rect_to_rl(r1),
        roundness,
        PANEL_SEGMENTS, 1.5,
        rl.Color{140, 80, 80, 255},
    )
}

// Dims the slot area r with a translucent overlay while in edit mode, so the edit handles drawn
// after it stand out.
draw_edit_shadow :: proc(r: Rect) {
    rl.DrawRectangleRounded( // TODO: normal rectangle
        rect_to_rl(r),
        rect_corner_roundness(r, CORNER_RADIUS),
        16,
        rl.Color{0, 0, 0, 66},
    )
}

draw_textbox :: proc(txt: string, r: Rect, c: rl.Color) {
    ctxt := strings.clone_to_cstring(txt, context.temp_allocator)
    txt_size := rl.MeasureTextEx(ui_font_14, ctxt, 14, 0)
    x := math.round(r.x)
    y := math.round(r.y + (r.h - txt_size.y) / 2)

    display_len := len(txt)
    truncated := false

    if txt_size.x > r.w && display_len > 1 {
        letter_w := txt_size.x/f32(display_len)
        display_len = clamp(int(r.w / letter_w), 1, display_len) // >= 1 so [display_len-1] stays in bounds
        ([^]u8)(ctxt)[display_len-1] = 0 // cut the (temp) copy short, not txt - the last slot is the '+' below
        truncated = true
    }

    rl.DrawTextEx(ui_font_14, ctxt, rl.Vector2{x, y}, 14, 0, c)

    if truncated {
        // '+' marks the cut, drawn faded right after the kept text
        plus_x := x + rl.MeasureTextEx(ui_font_14, ctxt, 14, 0).x
        rl.DrawTextCodepoint(ui_font_14, '+', rl.Vector2{plus_x, y}, 14, rl.Fade(c, 0.4))
    }
}

// Draws a small "v" dropdown chevron centered in r, one pixel at a time so it stays as crisp as
// the pixel font next to it.
draw_chevron_down :: proc(r: Rect, c: rl.Color) {
    W :: 9 // odd, so the two arms meet in a single bottom pixel; the chevron is W/2+1 rows tall
    x0 := i32(math.round(r.x + (r.w - W)/2))
    y0 := i32(math.round(r.y + (r.h - (W/2 + 1))/2))
    for i in i32(0)..=W/2 {
        rl.DrawRectangle(x0 + i, y0 + i, 1, 1, c)
        rl.DrawRectangle(x0 + W-1 - i, y0 + i, 1, 1, c)
    }
}

main :: proc() {
    r_slots := Rect{PAD, PAD, SLOT_PX*SLOTS_INIT_W, SLOT_PX*SLOTS_INIT_H}
    window_w, window_h := r_slots.w + PAD*2, r_slots.h + STATUS_BAR_H + PAD*2
    r_window := Rect{0, 0, window_w, window_h}

    rl.SetConfigFlags({.MSAA_4X_HINT}) // smooths rounded-rect/circle edges - must be set before InitWindow
    rl.InitWindow(i32(r_window.w), i32(r_window.h), "Solaris")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    icon := rl.LoadImage("assets/solaris.png")
    rl.ImageFormat(&icon, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8) // GLFW requires RGBA8 for a window icon
    rl.SetWindowIcon(icon)
    rl.UnloadImage(icon)

    ui_font = rl.LoadFontEx("assets/fonts/ShareTech/ShareTech-Regular.ttf", 32, nil, 0);
    defer rl.UnloadFont(ui_font)
    rl.SetTextureFilter(ui_font.texture, rl.TextureFilter.BILINEAR);

    ui_font_14 = rl.LoadFontEx("assets/fonts/DepartureMono/DepartureMono-Regular.otf", 14, nil, 0);
    defer rl.UnloadFont(ui_font_14)
    // drawn only at its native size on whole pixels, so POINT keeps glyphs 1:1 instead of resampling them
    rl.SetTextureFilter(ui_font_14.texture, rl.TextureFilter.POINT);

    slots := Slots{w = SLOTS_INIT_W, h = SLOTS_INIT_H, raised_panel = -1}
    edit_mode := false

    for !rl.WindowShouldClose() {
        // beign
        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(BACKGROUND_COLOR)

        // input handling
        if rl.IsKeyPressed(rl.KeyboardKey.TAB) {
            edit_mode = !edit_mode
        }
        mouse := rl.GetMousePosition()

        if !rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
            slots.drag_op = DragOperation{}
        }

        // STATUS BAR
        draw_status_bar(r_window, edit_mode)

        // SLOT PLACEHOLDERS
        clicked, clicked_slot := draw_slots(slots, r_slots, edit_mode)
        if clicked {
            new_panel := Panel{
                tile     = Tile{clicked_slot.x, clicked_slot.y, NEW_PANEL_SLOTS_W, NEW_PANEL_SLOTS_H},
                min_size = {2, 2},
                max_size = {slots.w, slots.h},
            }
            if slots_add_panel(&slots, new_panel) != -1 {
                fmt.printfln("Adding Packet Viewer at (%d, %d)", clicked_slot.x, clicked_slot.y)
            }
        }

        // PANELS
        panels_it := slots_panels(&slots)
        for p in slots_panels_next(&panels_it) {
            r_panel := tile_to_rect(p.tile, f32(SLOT_PX), [2]f32{r_slots.x, r_slots.y})
            draw_panel(r_panel)

            H :: 28
            r_header := rect_inset(r_panel, 16)
            r_header.h = H

            c1 := rl.Color{230, 230, 230, 255}
            c2 := rl.Color{33, 33, 33, 255}
            c3 := rl.Color{77, 77, 33, 255}

            rl.DrawRectangleRounded(
                rect_to_rl(r_header),
                rect_corner_roundness(r_header, CORNER_RADIUS),
                PANEL_SEGMENTS,
                c2,
            )

            rl.DrawRectangleRoundedLinesEx(
                rect_to_rl(r_header),
                rect_corner_roundness(r_header, CORNER_RADIUS),
                PANEL_SEGMENTS, 1,
                c3,
            )

            title :: "[003,025]HOUSEKEEPING_ADCS_ATT_DET_MONITORING"
            r_name, r_icon := rect_split2(rect_inset(r_header, 8), .Rx, r_header.h, 0)
            draw_textbox(title, r_name, c1)
            draw_chevron_down(r_icon, c1)

            r_b := rect_inset(r_panel, 16)
            r_b.y += (H+8)
            r_b.h -= (H+8)

            rl.DrawRectangleRoundedLinesEx(
                rect_to_rl(r_b),
                rect_corner_roundness(r_b, CORNER_RADIUS),
                PANEL_SEGMENTS, 1,
                c2,
            )
        }

        // EDIT MODE
        if edit_mode {
            slots_update_drag(&slots, mouse, SLOT_PX)

            draw_edit_shadow(r_slots)

            // draw drag widgets, in the same order as the panels
            handles_it := slots_panels(&slots)
            for p, i in slots_panels_next(&handles_it) {
                r_panel := tile_to_rect(p.tile, f32(SLOT_PX), [2]f32{r_slots.x, r_slots.y})

                // central move handle
                r_move_handle := rect_centered(r_panel, {r_panel.w*0.6, 32})
                draw_drag_handle(&slots, .Move, {}, r_move_handle, i)

                // corner handles sit just inside the visible (inset) panel
                r_corners := rect_inset(r_panel, 16)
                resize_size := [2]f32{32, 32}
                draw_drag_handle(&slots, .Resize, {.Up, .Lx}, rect_uplx(r_corners, resize_size), i)
                draw_drag_handle(&slots, .Resize, {.Up, .Rx}, rect_uprx(r_corners, resize_size), i)
                draw_drag_handle(&slots, .Resize, {.Dw, .Lx}, rect_dwlx(r_corners, resize_size), i)
                draw_drag_handle(&slots, .Resize, {.Dw, .Rx}, rect_dwrx(r_corners, resize_size), i)
            }

            // raising just sets an index - done after the loop so the iteration order above
            // doesn't shift mid-loop
            if slots.drag_op.active {
                slots.raised_panel = slots.drag_op.panel_idx
            }
        }

        // RENDER: debug
        // rl.DrawFPS(13, i32(window_h) - 28)
    }
}
