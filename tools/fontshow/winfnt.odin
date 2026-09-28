package fontshow

import rl "vendor:raylib"

// Loads a Windows bitmap font resource (.fnt, versions 2.0 and 3.0, e.g. Cozette). This is the
// binary .fnt format, not the BMFont text .fnt that rl.LoadFont expects - rl.LoadFont crashes the
// process on these. Glyph bitmaps are copied 1:1, so the font is pixel-exact when drawn at
// font.baseSize (its native pixel height) or a whole multiple of it, with a POINT filter.
// ok is false if the file can't be read or isn't a raster Windows .fnt.
load_font_winfnt :: proc(path: cstring) -> (font: rl.Font, ok: bool) {
    data_size: i32
    raw := rl.LoadFileData(path, &data_size)
    if raw == nil do return
    defer rl.UnloadFileData(raw)
    d := raw[:data_size]

    u16_at :: proc(d: []byte, i: int) -> int { return int(d[i]) | int(d[i+1]) << 8 }
    u32_at :: proc(d: []byte, i: int) -> int { return u16_at(d, i) | u16_at(d, i+2) << 16 }

    // header: dfVersion @0, dfType @66, dfPixHeight @88, dfFirstChar @95, dfLastChar @96
    if len(d) < 148 do return
    version := u16_at(d, 0)
    if version != 0x200 && version != 0x300 do return
    if u16_at(d, 66) & 1 != 0 do return // dfType bit 0 = vector font, no bitmaps
    height := u16_at(d, 88)
    first, last := int(d[95]), int(d[96])
    // char table right after the header: v2.0 entries are {u16 width, u16 offset}, v3.0 {u16 width, u32 offset}
    table, entry := 118, 4
    if version == 0x300 do table, entry = 148, 6

    Glyph :: struct { code, width, offset: int }
    glyph_at :: proc(d: []byte, version, table, entry, first, c: int) -> Glyph {
        e := table + (c - first)*entry
        offset := version == 0x200 ? u16_at(d, e+2) : u32_at(d, e+2)
        return {c, u16_at(d, e), offset}
    }
    // charset is Windows-1252: its printable ASCII and 0xA0..0xFF are the same Unicode code points
    wanted :: proc(c: int) -> bool { return (c >= 0x20 && c <= 0x7E) || c >= 0xA0 }

    // validate everything before allocating, so a bad file can't leave half a font behind
    if height == 0 || table + (last - first + 1)*entry > len(d) do return
    count := 0
    for c in first..=last {
        if !wanted(c) do continue
        g := glyph_at(d, version, table, entry, first, c)
        if g.width == 0 do continue
        if g.offset + (g.width + 7)/8*height > len(d) do return
        count += 1
    }
    if count == 0 do return

    // allocated with raylib's allocator so rl.UnloadFont frees it all like any other font
    font.baseSize = i32(height)
    font.glyphPadding = 1
    font.glyphCount = i32(count)
    font.glyphs = ([^]rl.GlyphInfo)(rl.MemAlloc(u32(count*size_of(rl.GlyphInfo))))
    n := 0
    for c in first..=last {
        if !wanted(c) do continue
        g := glyph_at(d, version, table, entry, first, c)
        if g.width == 0 do continue

        // raylib's font atlas builder takes 1-byte-per-pixel (grayscale alpha) glyph images;
        // MemAlloc zero-fills, so only the set pixels need writing
        px := ([^]u8)(rl.MemAlloc(u32(g.width*height)))
        // bitmaps are stored as 8-pixel-wide byte columns, each top to bottom; bit 7 = leftmost pixel
        for y in 0..<height {
            for x in 0..<g.width {
                if d[g.offset + x/8*height + y] & (u8(0x80) >> uint(x%8)) != 0 do px[y*g.width + x] = 255
            }
        }
        font.glyphs[n] = {
            value    = rune(c),
            advanceX = i32(g.width),
            image    = {data = px, width = i32(g.width), height = i32(height), mipmaps = 1, format = .UNCOMPRESSED_GRAYSCALE},
        }
        n += 1
    }

    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, font.glyphPadding, 0)
    font.texture = rl.LoadTextureFromImage(atlas)
    rl.UnloadImage(atlas)
    return font, true
}
