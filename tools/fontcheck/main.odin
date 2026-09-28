// fontcheck - finds the font sizes at which raylib rasterizes a pixel font pixel-exactly.
//
// A pixel font's outlines are squares on a grid; only at the right LoadFontEx size (and its whole
// multiples) does each square land on exactly one pixel, so the glyphs have no antialiasing.
// raylib sizes fonts by ascent-to-descent height, not the font's advertised pixel size, so the
// right size is often not the one in the font's README (Departure Mono: "11px" -> size 14).
//
// For each font and each size in 6..64, this rasterizes printable ASCII the same way LoadFontEx
// does and counts partially transparent ("grey") glyph pixels. Zero grey = pixel-exact.
//
// Usage (from the repo root):
//   ./bin/odin/odin.exe run tools/fontcheck -out:build/fontcheck.exe -- <font.ttf|otf> [more fonts...]
package fontcheck

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

SIZE_MIN :: 6
SIZE_MAX :: 64

// Counts glyph pixels that are fully opaque (solid) and partially transparent (grey) when the
// font data is rasterized at size. ok is false if raylib couldn't rasterize it at all.
count_pixels :: proc(data: [^]byte, data_size: i32, size: i32) -> (solid, grey: int, ok: bool) {
    glyph_count: i32
    // nil codepoints = printable ASCII (32..126), what LoadFontEx loads by default
    glyphs := rl.LoadFontData(data, data_size, size, nil, 0, .DEFAULT, &glyph_count)
    if glyphs == nil do return 0, 0, false
    defer rl.UnloadFontData(glyphs, glyph_count)

    for g in glyphs[:glyph_count] {
        if g.image.data == nil do continue
        // .DEFAULT glyph images are 1 byte (alpha) per pixel
        px := ([^]u8)(g.image.data)[:g.image.width*g.image.height]
        for a in px {
            if a == 255 do solid += 1
            else if a != 0 do grey += 1
        }
    }
    return solid, grey, true
}

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("usage: fontcheck <font.ttf|otf> [more fonts...]")
        os.exit(1)
    }
    rl.SetTraceLogLevel(.ERROR) // its per-size glyph warnings drown the output; failures are reported below

    for path in os.args[1:] {
        fmt.printfln("%s", path)

        data_size: i32
        data := rl.LoadFileData(fmt.ctprint(path), &data_size)
        if data == nil {
            fmt.println("  can't read file")
            continue
        }
        defer rl.UnloadFileData(data)

        exact, drawn := 0, 0
        best_size, best_ratio := i32(0), 1.0
        for size in i32(SIZE_MIN)..=SIZE_MAX {
            solid, grey, ok := count_pixels(data, data_size, size)
            if !ok do break
            if solid + grey == 0 do continue
            drawn += 1
            if grey == 0 {
                fmt.printfln("  size %2d: pixel-exact", size)
                exact += 1
            }
            ratio := f64(grey) / f64(solid + grey)
            if ratio < best_ratio do best_size, best_ratio = size, ratio
        }
        // a bitmap-only file (e.g. .otb) either fails outright or "loads" with every glyph empty
        if drawn == 0 {
            fmt.println("  raylib can't rasterize this font (no outlines? e.g. a bitmap-only .otb)")
        } else if exact == 0 {
            fmt.printfln("  no pixel-exact size (not a pixel font?) - least grey: size %d, %.0f%% grey pixels", best_size, best_ratio*100)
        }
    }
}
