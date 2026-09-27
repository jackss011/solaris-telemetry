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




/* ::::::::::::::::::::::::::: BOX ::::::::::::::::::::::::::: */

Box :: struct {
    x : f32,
    y : f32,
    w : f32,
    h : f32,
}

box_inset :: proc(b : Box, inset: f32) -> Box {
    half := inset / 2
    return Box{b.x + half, b.y + half, b.w - inset, b.h - inset}
}

box_to_rl :: proc(b: Box) -> rl.Rectangle {
    return rl.Rectangle{b.x, b.y, b.w, b.h}
}

box_end :: proc(b: Box) -> (f32, f32) {
    return b.x + b.w, b.y + b.h
}

box_contains :: proc(b: Box, point: [2]f32) -> bool {
    return point.x >= b.x && point.x < b.x + b.w && point.y >= b.y && point.y < b.y + b.h
}

box_centered :: proc(b: Box, size: [2]f32) -> Box {
    return Box{b.x + b.w/2 - size.x/2, b.y + b.h/2 - size.y/2, size.x, size.y}
}

// rl.DrawRectangleRounded's `roundness` is relative to the box's shorter side, so the same
// value produces a different-looking corner radius on differently-sized/shaped boxes. This
// converts a fixed pixel radius into the roundness fraction that reproduces it on box `b`,
// so the corner radius stays constant (equal on every side) regardless of the box's length.
box_corner_roundness :: proc(b: Box, radius: f32) -> f32 {
    shorter := min(b.w, b.h)
    if shorter <= 0 {
        return 0
    }
    return clamp(radius * 2 / shorter, 0, 1)
}

/* ::::::::::::::::::::::::::: TILING ::::::::::::::::::::::::::: */

MAX_TILES :: 128
MAX_WINDOWS :: 128

TiledBox :: struct {
    n_x: int,
    n_y: int,
    n_w: int,
    n_h: int,
}

TiledWindow :: struct {
    box : TiledBox,
    range_nw: [2]int,
    range_nh: [2]int,
}

Tiles :: struct {
    n_w: int,
    n_h: int,
    windows: [dynamic; MAX_WINDOWS]TiledWindow,
}

// Places a window of size (w, h) at (x, y) in the tile grid, if that spot is within grid
// bounds. Windows are allowed to overlap - the one placed/raised last renders on top, since
// draw order follows array order. Returns -1 if out of bounds or the window store is full.
tiles_new_window :: proc(tiles: ^Tiles, candidate: TiledWindow) -> int {
    if !tiles_is_in_bounds(tiles^, candidate) {
        return -1
    }
    if append(&tiles.windows, candidate) == 0 {
        return -1
    }
    return len(tiles.windows) - 1
}

tiles_is_in_bounds :: proc(tiles: Tiles, window: TiledWindow) -> bool {
    b := window.box
    return b.n_x >= 0 && b.n_y >= 0 && b.n_x + b.n_w <= tiles.n_w && b.n_y + b.n_h <= tiles.n_h
}

// Whether grid cell (x, y) falls inside any existing window's footprint.
tiles_cell_is_free :: proc(tiles: Tiles, x: int, y: int) -> bool {
    for w in tiles.windows {
        b := w.box
        if x >= b.n_x && x < b.n_x + b.n_w && y >= b.n_y && y < b.n_y + b.n_h {
            return false
        }
    }
    return true
}

// Whether a new window of size (w, h) could be placed with its top-left at grid cell (x, y):
// that cell must be unoccupied, and the whole footprint must stay within the grid.
tiles_can_place_new_window :: proc(tiles: Tiles, x: int, y: int, w: int, h: int) -> bool {
    if !tiles_cell_is_free(tiles, x, y) {
        return false
    }
    return tiles_is_in_bounds(tiles, TiledWindow{box = TiledBox{x, y, w, h}})
}

// Moves the window at win_idx to the end of tiles.windows, so it renders on top of every other
// window (draw order follows array order). Updates win_idx callers may be tracking (e.g.
// drag_op.win_idx) since every window at a higher index shifts down by one.
tiles_raise_to_front :: proc(tiles: ^Tiles, win_idx: int) {
    if win_idx == len(tiles.windows) - 1 {
        return
    }
    w := tiles.windows[win_idx]
    ordered_remove(&tiles.windows, win_idx)
    append(&tiles.windows, w)
}

tiles_window_to_box :: proc(window: TiledWindow, tile_px: f32, origin: [2]f32) -> Box {
    b := window.box
    return Box{
        origin.x + f32(b.n_x) * tile_px,
        origin.y + f32(b.n_y) * tile_px,
        f32(b.n_w) * tile_px,
        f32(b.n_h) * tile_px,
    }
}

// Nudges the window at win_idx one tile up (dir < 0) or down (dir > 0), leaving its column and
// size unchanged. Refuses (leaving tiles.windows untouched) if that would push it out of grid
// bounds; overlapping other windows is allowed. Returns whether the move happened.
tiles_window_move_v :: proc(tiles: ^Tiles, win_idx: int, dir: int) -> bool {
    candidate := tiles.windows[win_idx]
    candidate.box.n_y += math.sign(dir)

    if !tiles_is_in_bounds(tiles^, candidate) {
        return false
    }

    tiles.windows[win_idx] = candidate
    return true
}

// Nudges the window at win_idx one tile left (dir < 0) or right (dir > 0), leaving its row and
// size unchanged. Refuses (leaving tiles.windows untouched) if that would push it out of grid
// bounds; overlapping other windows is allowed. Returns whether the move happened.
tiles_window_move_h :: proc(tiles: ^Tiles, win_idx: int, dir: int) -> bool {
    candidate := tiles.windows[win_idx]
    candidate.box.n_x += math.sign(dir)

    if !tiles_is_in_bounds(tiles^, candidate) {
        return false
    }

    tiles.windows[win_idx] = candidate
    return true
}

/* ::::::::::::::::::::::::::: DRAG ::::::::::::::::::::::::::: */

DragType :: enum {
    Move,
    Resize,
}

DragOperation :: struct {
    active: bool,
    win_idx: int,
    mouse_start: [2]f32,
    box_start: TiledBox,
    optype: DragType,
}


/* ::::::::::::::::::::::::::: RENDER ::::::::::::::::::::::::::: */

BACKGROUND_COLOR := rl.Color{15, 15, 20, 255}
GRID_PX :: 100
GRID_INIT_W :: 8
GRID_INIT_H :: 6
HEADER_H :: 32
PAD :: 8
CORNER_RADIUS :: 10
PANEL_SEGMENTS :: 36 // corner smoothness for rounded panels - higher = less jagged
NEW_WINDOW_TILES_W :: 3
NEW_WINDOW_TILES_H :: 4

main :: proc() {
    tile := Box{PAD, PAD, GRID_PX*GRID_INIT_W, GRID_PX*GRID_INIT_H}
    window_w, window_h := tile.w + PAD*2, tile.h + HEADER_H + PAD*2
    window := Box{0, 0, window_w, window_h}

    rl.SetConfigFlags({.MSAA_4X_HINT}) // smooths rounded-rect/circle edges - must be set before InitWindow
    rl.InitWindow(i32(window.w), i32(window.h), "Solaris")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    icon := rl.LoadImage("assets/solaris.png")
    rl.ImageFormat(&icon, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8) // GLFW requires RGBA8 for a window icon
    rl.SetWindowIcon(icon)
    rl.UnloadImage(icon)

    font := rl.LoadFontEx("assets/fonts/ShareTech-Regular.ttf", 32, nil, 0);
    defer rl.UnloadFont(font)
    rl.SetTextureFilter(font.texture, rl.TextureFilter.BILINEAR);

    tiles := Tiles{n_w = GRID_INIT_W, n_h = GRID_INIT_H}
    edit_mode := false
    drag_op : DragOperation

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()

        if rl.IsKeyPressed(rl.KeyboardKey.TAB) {
            edit_mode = !edit_mode
        }

        // backgorund
        rl.ClearBackground(BACKGROUND_COLOR)

        // logo
        label_size := rl.MeasureTextEx(font, "SOLARIS", HEADER_H, 2)
        label_color := rl.Color{207/3, 210/4, 220/4, 255}

        if edit_mode {
            rl.DrawTextEx(font, "EDIT", rl.Vector2{PAD, window_h - PAD - HEADER_H + 3}, HEADER_H, 2, rl.Color{230, 180, 60, 255})
        }

        rl.DrawTextEx(font, "SOLARIS",
            rl.Vector2{window_w - label_size.x - PAD*2, window_h - PAD - HEADER_H + 3}, 
            HEADER_H, 
            2, label_color)

        mouse := rl.GetMousePosition()

        if !rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
            drag_op = DragOperation{}
        }

        clicked := false
        clicked_iw, clicked_ih : int = 0, 0

        // grid
        for iw in 0..<tiles.n_w {
            for ih in 0..<tiles.n_h {
                x, y := f32(iw*GRID_PX)+tile.x, f32(ih*GRID_PX)+tile.y
                b := Box{x, y, f32(GRID_PX), f32(GRID_PX)}
                b1 := box_inset(b, 8.0)
                hovered := box_contains(b, mouse) &&
                    tiles_can_place_new_window(tiles, iw, ih, NEW_WINDOW_TILES_W, NEW_WINDOW_TILES_H)

                if hovered && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    clicked = true
                    clicked_iw = iw
                    clicked_ih = ih
                }

                rl.DrawRectangleRounded(
                    box_to_rl(b1),
                    box_corner_roundness(b1, CORNER_RADIUS),
                    16,   // segments
                    hovered ? rl.Color{45, 40, 40, 255} : rl.Color{30, 26, 26, 255}, // fill, translucent
                )

                if hovered {
                    text_size := rl.MeasureTextEx(font, "add", 20, 1)
                    text_pos := rl.Vector2{
                        b.x + b.w/2 - text_size.x/2,
                        b.y + b.h/2 - text_size.y/2,
                    }
                    rl.DrawTextEx(font, "add", text_pos, 20, 1, rl.Color{200, 210, 220, 255})
                }
            }
        }

        if clicked {
            new_box := TiledBox{clicked_iw, clicked_ih, NEW_WINDOW_TILES_W, NEW_WINDOW_TILES_H}
            new_win := TiledWindow{
                box      = new_box,
                range_nw = {new_box.n_w, new_box.n_w},
                range_nh = {new_box.n_h, new_box.n_h},
            }
            if tiles_new_window(&tiles, new_win) != -1 {
                fmt.printfln("Adding Packet Viewer at (%d, %d)", clicked_iw, clicked_ih)
            }
        }

        // render every placed window as a tiled, glowing panel on top of the grid
        for w in tiles.windows {
            wb := tiles_window_to_box(w, f32(GRID_PX), [2]f32{tile.x, tile.y})
            wb1 := box_inset(wb, 8.0)
            roundness := box_corner_roundness(wb1, CORNER_RADIUS)

            rl.DrawRectangleRounded(
                box_to_rl(wb1),
                roundness,
                PANEL_SEGMENTS,
                rl.Color{40, 90, 140, 255},
            )

            // soft outer glow: a couple of widening, fading outlines behind the crisp border
            for glow_i in 1..=3 {
                glow_b := box_inset(wb1, -f32(glow_i) * 3)
                alpha := u8(70 - glow_i * 20)
                rl.DrawRectangleRoundedLinesEx(
                    box_to_rl(glow_b),
                    box_corner_roundness(glow_b, CORNER_RADIUS),
                    PANEL_SEGMENTS, 2,
                    rl.Color{110, 190, 255, alpha},
                )
            }

            rl.DrawRectangleRoundedLinesEx(
                box_to_rl(wb1),
                roundness,
                PANEL_SEGMENTS, 2,
                rl.Color{160, 215, 255, 255},
            )
        }

        if edit_mode {
            // shadow rest of the screen
            rl.DrawRectangleRounded( // TODO: normal rectangle
                box_to_rl(tile),
                box_corner_roundness(tile, CORNER_RADIUS),
                16,
                rl.Color{0, 0, 0, 33},
            )

            // draw drag widgets
            raise_idx := -1
            for w, i in tiles.windows {
                is_moving := drag_op.active && drag_op.optype == DragType.Move && drag_op.win_idx == i

                if is_moving {
                    delta_drag := (mouse - drag_op.mouse_start) / [2]f32{GRID_PX, GRID_PX}
                    delta_tiles := [2]int{int(delta_drag.x), int(delta_drag.y)}
                    delta_tiles -= [2]int{w.box.n_x - drag_op.box_start.n_x, w.box.n_y - drag_op.box_start.n_y}

                    tiles_window_move_h(&tiles, i, delta_tiles.x)
                    tiles_window_move_v(&tiles, i, delta_tiles.y)
                }

                wb := tiles_window_to_box(tiles.windows[i], f32(GRID_PX), [2]f32{tile.x, tile.y})
                b := box_centered(wb, {GRID_PX/3*4, 15})
                b.y -= b.h/3

                // should we enter moving?
                if !drag_op.active &&
                    box_contains(b, mouse) &&
                    rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    drag_op.active = true
                    drag_op.optype = DragType.Move
                    drag_op.win_idx = i
                    drag_op.mouse_start = mouse
                    drag_op.box_start = w.box
                    raise_idx = i
                    fmt.println("dragging!");
                }

                rl.DrawRectangleRounded(
                    box_to_rl(b),
                    box_corner_roundness(b, CORNER_RADIUS),
                    32,
                    is_moving ? rl.Color{120, 90, 140, 255} : rl.Color{200, 90, 140, 255},
                )
            }

            if raise_idx >= 0 {
                tiles_raise_to_front(&tiles, raise_idx)
                drag_op.win_idx = len(tiles.windows) - 1
            }
        }

        // rl.DrawFPS(13, i32(window_h) - 28)
    }
}