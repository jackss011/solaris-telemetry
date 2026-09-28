// fontshow - interactive viewer for picking a UI font and size by eye.
//
// Lists every .ttf/.otf/.fnt under assets/fonts and draws sample text with the selected one the same
// way the app does (LoadFontEx at the chosen size, POINT filter, whole-pixel positions, app colors),
// plus a 3x zoom to inspect individual pixels. Sizes where the font rasterizes pixel-exactly (no
// antialiased pixels - see tools/fontcheck) are marked. .fnt files are Windows bitmap fonts, loaded
// by load_font_winfnt (winfnt.odin) - they're exact at their native size and its multiples.
//
// Controls: Up/Down or click = font, Left/Right or wheel = size, PgUp/PgDn = next/prev pixel-exact
// size, Enter = copy the LoadFontEx(...) line for the current font+size to the clipboard.
//
// Usage (from the repo root, so assets/fonts resolves):
//   ./bin/odin/odin.exe run tools/fontshow -out:build/fontshow.exe
package fontshow

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

FONT_DIR :: "assets/fonts"
SIZE_MIN :: 6
SIZE_MAX :: 64

WINDOW_W :: 1400
WINDOW_H :: 900
LIST_W   :: 280 // font list column on the left
LIST_Y   :: 16
ROW_H    :: 26
X0       :: LIST_W + 16 // left edge of the preview area
ZOOM     :: 3
ZOOM_Y   :: 520 // top of the zoomed view; the 1x samples are clipped above it

// same as the app (src/main.odin)
BG     :: rl.Color{15, 15, 20, 255}
HEADER :: rl.Color{60, 60, 60, 255}
TEXT   :: rl.Color{230, 230, 230, 255}
DIM    :: rl.Color{120, 120, 130, 255}
EXACT  :: rl.Color{110, 200, 120, 255}
BLURRY :: rl.Color{230, 150, 60, 255}

SAMPLES := [?]cstring{
    "[003,025]HOUSEKEEPING_ADCS_ATT_DET_MONITORING",
    "TEMP1   23.45 degC   RED_HIGH   0x1F3A",
    "The quick brown fox jumps over the lazy dog",
    "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG",
    "0123456789  +-*/=%  3.14159  -273.15",
    "il1I|!  O0oQ  rnm  ,.;:'\"`  ()[]{}<>",
}

// Share of glyph pixels that are partially transparent, per size, rasterized the way LoadFontEx does
// (printable ASCII): 0 = pixel-exact, -1 = nothing drawn (e.g. a bitmap-only font). For .fnt bitmap
// fonts it's filled in main instead: 0 at native size multiples, -2 elsewhere.
Ratios :: [SIZE_MAX + 1]f64

compute_ratios :: proc(path: cstring) -> (r: Ratios) {
    for &x in r do x = -1
    data_size: i32
    data := rl.LoadFileData(path, &data_size)
    if data == nil do return
    defer rl.UnloadFileData(data)

    for size in i32(SIZE_MIN)..=SIZE_MAX {
        glyph_count: i32
        glyphs := rl.LoadFontData(data, data_size, size, nil, 0, .DEFAULT, &glyph_count)
        if glyphs == nil do continue
        defer rl.UnloadFontData(glyphs, glyph_count)

        solid, grey := 0, 0
        for g in glyphs[:glyph_count] {
            if g.image.data == nil do continue
            // .DEFAULT glyph images are 1 byte (alpha) per pixel
            for a in ([^]u8)(g.image.data)[:g.image.width*g.image.height] {
                if a == 255 do solid += 1
                else if a != 0 do grey += 1
            }
        }
        if solid + grey > 0 do r[size] = f64(grey) / f64(solid + grey)
    }
    return
}

// Draws the samples at 1x from (x, y), one per line, like the app draws text.
draw_samples :: proc(font: rl.Font, size: i32, x, y: f32) {
    line_h := f32(size + max(size/3, 4))
    for s, i in SAMPLES {
        rl.DrawTextEx(font, s, {x, y + f32(i)*line_h}, f32(size), 0, TEXT)
    }
}

main :: proc() {
    rl.SetTraceLogLevel(.ERROR)
    rl.InitWindow(WINDOW_W, WINDOW_H, "fontshow")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    files := rl.LoadDirectoryFilesEx(FONT_DIR, ".ttf;.otf;.fnt", true)
    defer rl.UnloadDirectoryFiles(files)
    if files.count == 0 {
        fmt.eprintfln("no .ttf/.otf/.fnt fonts under %s - run from the repo root", FONT_DIR)
        return
    }
    paths := files.paths[:files.count]

    // the zoomed view is the samples drawn into this texture at 1x, then blown up with POINT
    zoom_w, zoom_h := i32(WINDOW_W - X0 - 16), i32(WINDOW_H - ZOOM_Y - 60)
    zoom_rt := rl.LoadRenderTexture(zoom_w/ZOOM, zoom_h/ZOOM)
    defer rl.UnloadRenderTexture(zoom_rt)
    rl.SetTextureFilter(zoom_rt.texture, .POINT)

    font_idx, size := 0, i32(16)
    loaded_idx, loaded_size := -1, i32(-1)
    font: rl.Font
    defer if loaded_idx != -1 do rl.UnloadFont(font)
    ratios: Ratios
    copied_timer: f32

    for !rl.WindowShouldClose() {
        defer free_all(context.temp_allocator)

        // INPUT
        n := len(paths)
        if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) do font_idx = (font_idx + 1) % n
        if rl.IsKeyPressed(.UP)   || rl.IsKeyPressedRepeat(.UP)   do font_idx = (font_idx + n - 1) % n
        if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) do size += 1
        if rl.IsKeyPressed(.LEFT)  || rl.IsKeyPressedRepeat(.LEFT)  do size -= 1
        size += i32(rl.GetMouseWheelMove())
        if rl.IsKeyPressed(.PAGE_UP) {
            for s in size + 1..=SIZE_MAX do if ratios[s] == 0 { size = s; break }
        }
        if rl.IsKeyPressed(.PAGE_DOWN) {
            for s := size - 1; s >= SIZE_MIN; s -= 1 do if ratios[s] == 0 { size = s; break }
        }
        size = clamp(size, SIZE_MIN, SIZE_MAX)

        mouse := rl.GetMousePosition()
        if rl.IsMouseButtonPressed(.LEFT) && mouse.x < LIST_W && mouse.y >= LIST_Y {
            i := int((mouse.y - LIST_Y) / ROW_H)
            if i < n do font_idx = i
        }

        path := paths[font_idx]
        is_fnt := strings.equal_fold(string(rl.GetFileExtension(path)), ".fnt")
        load_line := fmt.ctprintf(`rl.LoadFontEx("%s", %d, nil, 0)`, path, size)
        if is_fnt do load_line = fmt.ctprintf(`load_font_winfnt("%s") // draw at size %d`, path, size)
        if rl.IsKeyPressed(.ENTER) {
            rl.SetClipboardText(load_line)
            fmt.println(load_line)
            copied_timer = 1.5
        }
        copied_timer -= rl.GetFrameTime()

        // (RE)LOAD
        // a bitmap font has one native size and is scaled at draw time, so it only reloads on a font change
        if font_idx != loaded_idx || (!is_fnt && size != loaded_size) {
            new_font := font_idx != loaded_idx
            if loaded_idx != -1 do rl.UnloadFont(font) // no-op on the default font fallback below
            if is_fnt {
                ok: bool
                font, ok = load_font_winfnt(path)
                if new_font {
                    // exact at the native size and whole multiples, pixels stretched unevenly otherwise
                    for &r, s in ratios do r = !ok ? -1 : (s % int(font.baseSize) == 0 ? 0 : -2)
                    if ok do size = font.baseSize
                }
                if !ok do font = rl.GetFontDefault()
            } else {
                font = rl.LoadFontEx(path, size, nil, 0)
                if new_font do ratios = compute_ratios(path)
            }
            rl.SetTextureFilter(font.texture, .POINT)
            loaded_idx, loaded_size = font_idx, size
        }

        // zoom source, drawn before BeginDrawing
        rl.BeginTextureMode(zoom_rt)
        rl.ClearBackground(BG)
        draw_samples(font, size, 4, 4)
        rl.EndTextureMode()

        // DRAW
        rl.BeginDrawing()
        rl.ClearBackground(BG)

        // font list
        for p, i in paths {
            y := i32(LIST_Y + i*ROW_H)
            if i == font_idx do rl.DrawRectangle(8, y - 3, LIST_W - 16, ROW_H, HEADER)
            rl.DrawText(rl.GetFileName(p), 16, y, 20, i == font_idx ? TEXT : DIM)
        }

        // status
        ratio := ratios[size]
        rl.DrawText(fmt.ctprintf("%s   size %d", rl.GetFileName(paths[font_idx]), size), X0, 16, 20, TEXT)
        switch {
        case ratio == 0: rl.DrawText("PIXEL-EXACT", X0, 44, 20, EXACT)
        case ratio == -2: rl.DrawText(fmt.ctprintf("bitmap font off its grid - native size %d, pixels stretch unevenly", font.baseSize), X0, 44, 20, BLURRY)
        case ratio < 0:  rl.DrawText("nothing drawn - can't load or rasterize this font", X0, 44, 20, BLURRY)
        case:            rl.DrawText(fmt.ctprintf("blurry - %.0f%% of glyph pixels are grey", ratio*100), X0, 44, 20, BLURRY)
        }
        sb := strings.builder_make(context.temp_allocator)
        for s in SIZE_MIN..=SIZE_MAX do if ratios[s] == 0 do fmt.sbprintf(&sb, "%d  ", s)
        exact_sizes := strings.to_string(sb)
        rl.DrawText(fmt.ctprintf("pixel-exact sizes: %s", len(exact_sizes) > 0 ? exact_sizes : "none"), X0, 72, 20, DIM)
        rl.DrawText(load_line, X0, 100, 20, copied_timer > 0 ? EXACT : DIM)
        if copied_timer > 0 do rl.DrawText("copied", X0 + rl.MeasureText(load_line, 20) + 12, 100, 20, EXACT)

        // 1x: the panel-title look from the app, then the plain samples
        rl.BeginScissorMode(X0, 140, WINDOW_W - X0, ZOOM_Y - 150)
        title_size := rl.MeasureTextEx(font, SAMPLES[0], f32(size), 0)
        box := rl.Rectangle{X0, 146, title_size.x + 20, max(32, title_size.y + 12)}
        rl.DrawRectangleRounded(box, 0.3, 8, HEADER)
        rl.DrawTextEx(font, SAMPLES[0], {box.x + 10, math.floor(box.y + (box.height - title_size.y)/2)}, f32(size), 0, TEXT)
        // title width as MeasureTextEx reports it (%g, so a fractional width shows up), to size panels by
        rl.DrawText(fmt.ctprintf("%g x %g px", title_size.x, title_size.y),
            i32(box.x + box.width) + 12, i32(box.y + (box.height - 20)/2), 20, DIM)
        draw_samples(font, size, X0, box.y + box.height + 16)
        rl.EndScissorMode()

        // 3x zoom (render textures are stored upside down, hence the negative source height)
        rl.DrawText(fmt.ctprintf("%dx zoom", ZOOM), X0, ZOOM_Y - 26, 20, DIM)
        src := rl.Rectangle{0, 0, f32(zoom_rt.texture.width), -f32(zoom_rt.texture.height)}
        dst := rl.Rectangle{X0, ZOOM_Y, f32(zoom_rt.texture.width*ZOOM), f32(zoom_rt.texture.height*ZOOM)}
        rl.DrawTexturePro(zoom_rt.texture, src, dst, {}, 0, rl.WHITE)
        rl.DrawRectangleLinesEx(dst, 1, HEADER)

        rl.DrawText("Up/Down/click: font   Left/Right/wheel: size   PgUp/PgDn: pixel-exact size   Enter: copy line",
            X0, WINDOW_H - 32, 20, DIM)

        rl.EndDrawing()
    }
}
