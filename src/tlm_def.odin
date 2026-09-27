package main

import "core:strconv"

// ---- Definition layer (built once, at config-load time) ----
// See docs/telemetry-database-plan.md §3 for the data model rationale and §5 milestone 0 for
// what this file implements: turning the grab_keyword stream into typed packet/item
// definitions instead of just printing them (parse_config_file's current behavior).

TlmItemType :: enum {
    None,
    INT, UINT, FLOAT, STRING, BLOCK, DERIVED,
}

// Discriminates an item's role without a v-table: a plain item, an id item (used to identify
// which packet definition a chunk of bytes matches - cosmos-config-format.md's ID_ITEM), or an
// array item. Tag lives in TlmItemDef.kind; this holds only the kind-specific extra data.
TlmItemKind :: enum {
    Plain,
    Id,
    Array,
}

TlmStateColor :: enum {
    None,
    Green,
    Yellow,
    Red,
}

// One STATE modifier line (cosmos-config-format.md's item modifier table): maps a raw value to
// a display name, optionally colored for limits-style display.
TlmState :: struct {
    name:  string,
    value: i64,
    color: TlmStateColor,
}

// A LIMITS modifier line. has_green distinguishes "no green band given" from "green band is
// 0..0" since 0 is a legitimate threshold value.
TlmLimits :: struct {
    set:         string,
    persistence: int,
    enabled:     bool,
    red_low:     f64,
    yellow_low:  f64,
    yellow_high: f64,
    red_high:    f64,
    has_green:   bool,
    green_low:   f64,
    green_high:  f64,
}

TlmItemDef :: struct {
    name:          string,
    bit_offset:    int,   // from start of packet; negative = from end (cosmos-config-format.md)
    bit_size:      int,
    type:          TlmItemType,
    little_endian: bool,
    desc:          string,

    kind:          TlmItemKind,
    id_value:      i64,   // valid when kind == .Id
    array_count:   int,   // valid when kind == .Array

    units_full:    string,
    units_abbrev:  string,
    format_string: string,
    states:        []TlmState,
    has_limits:    bool,
    limits:        TlmLimits,
}

TlmPacketDef :: struct {
    target:        string,
    name:          string,
    little_endian: bool,
    desc:          string,
    items:         []TlmItemDef, // allocated once when the definition is built, then immutable
    id_item_idxs:  []int,        // indices into items[] that are .Id - for packet identification
}

Build_Error :: enum {
    None,
    Item_Without_Packet,   // ITEM/APPEND_ITEM (or ID_ variant) seen before any TELEMETRY
    Modifier_Without_Item, // UNITS/FORMAT_STRING/LIMITS/STATE/DESCRIPTION seen before any item
    Unknown_Item_Type,     // data type isn't one of INT/UINT/FLOAT/STRING/BLOCK/DERIVED
    Invalid_Number,        // a param that should parse as int/float didn't
    Generic_Conversion_Not_Terminated, // GENERIC_*_CONVERSION_START with no matching _END
}

parse_item_type :: proc(s: string) -> (type: TlmItemType, err: Build_Error) {
    switch s {
        case "INT":     return .INT, .None
        case "UINT":    return .UINT, .None
        case "FLOAT":   return .FLOAT, .None
        case "STRING":  return .STRING, .None
        case "BLOCK":   return .BLOCK, .None
        case "DERIVED": return .DERIVED, .None
    }
    return .None, .Unknown_Item_Type
}

// COSMOS quotes free-form text params (descriptions, format strings, units) with double quotes;
// this strips them. Params that aren't quoted (e.g. bare state/unit names) pass through as-is.
unquote :: proc(s: string) -> string {
    if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
        return s[1:len(s)-1]
    }
    return s
}

parse_required_int :: proc(keyword: Keyword, text: string, param_idx: int) -> (value: int, err: Build_Error) {
    parsed, ok := strconv.parse_int(token_ref_text(keyword.params[param_idx], text))
    if !ok {
        return 0, .Invalid_Number
    }
    return parsed, .None
}

parse_required_f64 :: proc(keyword: Keyword, text: string, param_idx: int) -> (value: f64, err: Build_Error) {
    parsed, ok := strconv.parse_f64(token_ref_text(keyword.params[param_idx], text))
    if !ok {
        return 0, .Invalid_Number
    }
    return parsed, .None
}

// Parses the [description] [endianness] pair shared by the ends of ITEM/APPEND_ITEM and their
// ID_ variants (cosmos-config-format.md's Item keywords table) - both optional, description
// before endianness when both are present. param_idx is where this pair would start.
apply_item_trailing_params :: proc(item: ^TlmItemDef, keyword: Keyword, text: string, param_idx: int) {
    param_idx := param_idx
    if keyword.params_count <= param_idx {
        return
    }

    candidate := token_ref_text(keyword.params[param_idx], text)
    if candidate == "BIG_ENDIAN" || candidate == "LITTLE_ENDIAN" {
        item.little_endian = candidate == "LITTLE_ENDIAN"
        return
    }

    item.desc = unquote(candidate)
    param_idx += 1
    if keyword.params_count > param_idx {
        item.little_endian = token_ref_text(keyword.params[param_idx], text) == "LITTLE_ENDIAN"
    }
}

// Accumulates one packet's items/id-indices as dynamic arrays while the keyword stream is being
// walked; finalize_packet converts them to the immutable slices TlmPacketDef holds. Kept
// separate from TlmPacketDef itself so the "still building" and "done, immutable" states can't
// be confused (see odin-best-practices skill on slices vs. dynamic arrays).
Packet_Builder :: struct {
    target:          string,
    name:            string,
    little_endian:   bool,
    desc:            string,
    items:           [dynamic]TlmItemDef,
    id_item_idxs:    [dynamic]int,
    cur_item_states: [dynamic]TlmState, // STATE lines accumulating for the most recent item
    next_bit_offset: int,               // running offset for the APPEND_* family only
}

// Attaches any STATE lines accumulated since the last item to that item, and resets the
// accumulator. Must run before a new item is appended (so the states land on the *previous*
// item) and before a packet is finalized (so the last item's states aren't dropped).
flush_item_states :: proc(b: ^Packet_Builder) {
    if len(b.cur_item_states) > 0 && len(b.items) > 0 {
        b.items[len(b.items) - 1].states = b.cur_item_states[:]
    }
    b.cur_item_states = nil
}

finalize_packet :: proc(b: ^Packet_Builder) -> TlmPacketDef {
    return TlmPacketDef{
        target        = b.target,
        name          = b.name,
        little_endian = b.little_endian,
        desc          = b.desc,
        items         = b.items[:],
        id_item_idxs  = b.id_item_idxs[:],
    }
}

// Milestone 0 of docs/telemetry-database-plan.md: drives grab_keyword over `text` and
// interprets TELEMETRY/APPEND_ITEM/APPEND_ID_ITEM/ITEM/ID_ITEM plus the UNITS/FORMAT_STRING/
// LIMITS/STATE/DESCRIPTION item modifiers, instead of just printing them the way
// parse_config_file does. Anything else it doesn't yet recognize (SELECT_TELEMETRY,
// SELECT_ITEM, ARRAY_ITEM, ...) is silently skipped - see the plan's §7 open questions.
build_packet_defs :: proc(text: string) -> (defs: []TlmPacketDef, err: Build_Error) {
    packets: [dynamic]TlmPacketDef
    b: Packet_Builder
    has_packet := false

    idx := 0
    for {
        keyword, next_idx := grab_keyword(text, idx)
        idx = next_idx

        if keyword.token.type == TokenType.NONE {
            break
        }

        name := token_ref_text(keyword.token, text)

        if end_marker := generic_conversion_end_marker(name); end_marker != "" {
            found, end_idx := grab_until(text, idx, end_marker)
            if !found {
                return nil, .Generic_Conversion_Not_Terminated
            }
            _, idx = grab_keyword(text, end_idx) // consume the END line itself
            continue
        }

        switch name {
        case "TELEMETRY":
            if has_packet {
                flush_item_states(&b)
                append(&packets, finalize_packet(&b))
            }
            b = Packet_Builder{}
            b.target = token_ref_text(keyword.params[0], text)
            b.name = token_ref_text(keyword.params[1], text)
            b.little_endian = token_ref_text(keyword.params[2], text) == "LITTLE_ENDIAN"
            if keyword.params_count > 3 {
                b.desc = unquote(token_ref_text(keyword.params[3], text))
            }
            has_packet = true

        case "APPEND_ITEM", "APPEND_ID_ITEM":
            if !has_packet {
                return nil, .Item_Without_Packet
            }
            is_id := name == "APPEND_ID_ITEM"
            flush_item_states(&b)

            bit_size := parse_required_int(keyword, text, 1) or_return
            type := parse_item_type(token_ref_text(keyword.params[2], text)) or_return

            item := TlmItemDef{
                name          = token_ref_text(keyword.params[0], text),
                bit_offset    = b.next_bit_offset,
                bit_size      = bit_size,
                type          = type,
                little_endian = b.little_endian,
            }

            param_idx := 3
            if is_id {
                id_value := parse_required_int(keyword, text, param_idx) or_return
                item.kind = .Id
                item.id_value = i64(id_value)
                param_idx += 1
            }
            apply_item_trailing_params(&item, keyword, text, param_idx)

            b.next_bit_offset += bit_size
            if is_id {
                append(&b.id_item_idxs, len(b.items))
            }
            append(&b.items, item)

        case "ITEM", "ID_ITEM":
            if !has_packet {
                return nil, .Item_Without_Packet
            }
            is_id := name == "ID_ITEM"
            flush_item_states(&b)

            bit_offset := parse_required_int(keyword, text, 1) or_return
            bit_size := parse_required_int(keyword, text, 2) or_return
            type := parse_item_type(token_ref_text(keyword.params[3], text)) or_return

            item := TlmItemDef{
                name          = token_ref_text(keyword.params[0], text),
                bit_offset    = bit_offset,
                bit_size      = bit_size,
                type          = type,
                little_endian = b.little_endian,
            }

            param_idx := 4
            if is_id {
                id_value := parse_required_int(keyword, text, param_idx) or_return
                item.kind = .Id
                item.id_value = i64(id_value)
                param_idx += 1
            }
            apply_item_trailing_params(&item, keyword, text, param_idx)

            if is_id {
                append(&b.id_item_idxs, len(b.items))
            }
            append(&b.items, item)

        case "DESCRIPTION":
            if len(b.items) == 0 {
                return nil, .Modifier_Without_Item
            }
            b.items[len(b.items) - 1].desc = unquote(token_ref_text(keyword.params[0], text))

        case "UNITS":
            if len(b.items) == 0 {
                return nil, .Modifier_Without_Item
            }
            item := &b.items[len(b.items) - 1]
            item.units_full = unquote(token_ref_text(keyword.params[0], text))
            if keyword.params_count > 1 {
                item.units_abbrev = unquote(token_ref_text(keyword.params[1], text))
            }

        case "FORMAT_STRING":
            if len(b.items) == 0 {
                return nil, .Modifier_Without_Item
            }
            b.items[len(b.items) - 1].format_string = unquote(token_ref_text(keyword.params[0], text))

        case "STATE":
            if len(b.items) == 0 {
                return nil, .Modifier_Without_Item
            }
            value := parse_required_int(keyword, text, 1) or_return
            state := TlmState{
                name  = token_ref_text(keyword.params[0], text),
                value = i64(value),
            }
            if keyword.params_count > 2 {
                switch token_ref_text(keyword.params[2], text) {
                    case "GREEN":  state.color = .Green
                    case "YELLOW": state.color = .Yellow
                    case "RED":    state.color = .Red
                }
            }
            append(&b.cur_item_states, state)

        case "LIMITS":
            if len(b.items) == 0 {
                return nil, .Modifier_Without_Item
            }
            persistence := parse_required_int(keyword, text, 1) or_return
            red_low := parse_required_f64(keyword, text, 3) or_return
            yellow_low := parse_required_f64(keyword, text, 4) or_return
            yellow_high := parse_required_f64(keyword, text, 5) or_return
            red_high := parse_required_f64(keyword, text, 6) or_return

            item := &b.items[len(b.items) - 1]
            item.has_limits = true
            item.limits.set = token_ref_text(keyword.params[0], text)
            item.limits.persistence = persistence
            item.limits.enabled = token_ref_text(keyword.params[2], text) == "ENABLED"
            item.limits.red_low = red_low
            item.limits.yellow_low = yellow_low
            item.limits.yellow_high = yellow_high
            item.limits.red_high = red_high

            if keyword.params_count > 8 {
                green_low := parse_required_f64(keyword, text, 7) or_return
                green_high := parse_required_f64(keyword, text, 8) or_return
                item.limits.has_green = true
                item.limits.green_low = green_low
                item.limits.green_high = green_high
            }
        }
    }

    if has_packet {
        flush_item_states(&b)
        append(&packets, finalize_packet(&b))
    }

    return packets[:], .None
}
