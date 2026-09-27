package main

import "core:os"
import "core:testing"

// examples/simple_tlm/tlm.txt is the reference target vocabulary (see CLAUDE.md's Architecture
// section) - loaded once per test rather than hardcoding a trimmed copy, so these tests catch
// drift if the example file changes.
load_tlm_txt :: proc(t: ^testing.T) -> string {
    data, err := os.read_entire_file("examples/simple_tlm/tlm.txt", context.allocator)
    testing.expect(t, err == nil, "failed to read examples/simple_tlm/tlm.txt")
    return string(data)
}

@(test)
test_build_packet_defs_tlm_txt_packet_header :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    testing.expect_value(t, len(defs), 1)

    p := defs[0]
    testing.expect_value(t, p.target, "YEP01")
    testing.expect_value(t, p.name, "HEALTH_STATUS")
    testing.expect_value(t, p.little_endian, false)
    testing.expect_value(t, p.desc, "Instrument Health and Status")
}

@(test)
test_build_packet_defs_tlm_txt_item_count :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    // CCSDSVER, CCSDSTYPE, CCSDSAPID, CCSDSSEQCNT, CCSDSLENGTH, VOLTAGE, TEMP1, COLLECT_TYPE,
    // DEPLOYED, COLLECTS, DURATION, LABEL
    testing.expect_value(t, len(defs[0].items), 12)
}

@(test)
test_build_packet_defs_tlm_txt_id_items :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    p := defs[0]

    testing.expect_value(t, len(p.id_item_idxs), 3)
    testing.expect_value(t, p.id_item_idxs[0], 0) // CCSDSVER
    testing.expect_value(t, p.id_item_idxs[1], 1) // CCSDSTYPE
    testing.expect_value(t, p.id_item_idxs[2], 2) // CCSDSAPID

    apid := p.items[2]
    testing.expect_value(t, apid.name, "CCSDSAPID")
    testing.expect_value(t, apid.kind, TlmItemKind.Id)
    testing.expect_value(t, apid.id_value, i64(1))
    testing.expect_value(t, apid.bit_offset, 4) // after CCSDSVER(3) + CCSDSTYPE(1)
    testing.expect_value(t, apid.bit_size, 11)
}

@(test)
test_build_packet_defs_tlm_txt_append_offsets_accumulate :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    items := defs[0].items

    testing.expect_value(t, items[0].name, "CCSDSVER")
    testing.expect_value(t, items[0].bit_offset, 0)
    testing.expect_value(t, items[3].name, "CCSDSSEQCNT")
    testing.expect_value(t, items[3].bit_offset, 15) // 3+1+11
    testing.expect_value(t, items[5].name, "VOLTAGE")
    testing.expect_value(t, items[5].bit_offset, 45) // 3+1+11+14+16
    testing.expect_value(t, items[5].bit_size, 32)
    testing.expect_value(t, items[5].type, TlmItemType.FLOAT)
}

@(test)
test_build_packet_defs_tlm_txt_derived_item_keeps_explicit_offset :: proc(t: ^testing.T) {
    // ITEM (not APPEND_ITEM) uses an explicit offset and must not perturb the APPEND_* running
    // offset - LABEL right after it should still land where COLLECTS's append would put it.
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    items := defs[0].items

    duration := items[10]
    testing.expect_value(t, duration.name, "DURATION")
    testing.expect_value(t, duration.bit_offset, 0)
    testing.expect_value(t, duration.bit_size, 0)
    testing.expect_value(t, duration.type, TlmItemType.DERIVED)
    testing.expect_value(t, duration.desc, "Collection duration")

    label := items[11]
    testing.expect_value(t, label.name, "LABEL")
    testing.expect_value(t, label.bit_offset, 125) // COLLECTS ends at 109+16, unaffected by DURATION
    testing.expect_value(t, label.bit_size, 256)
    testing.expect_value(t, label.type, TlmItemType.STRING)
}

@(test)
test_build_packet_defs_tlm_txt_units_and_format_string :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    voltage := defs[0].items[5]

    testing.expect_value(t, voltage.format_string, "%0.3f")
    testing.expect_value(t, voltage.units_full, "Volts")
    testing.expect_value(t, voltage.units_abbrev, "V")
}

@(test)
test_build_packet_defs_tlm_txt_limits_with_green :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    temp1 := defs[0].items[6]

    testing.expect_value(t, temp1.name, "TEMP1")
    testing.expect_value(t, temp1.has_limits, true)
    testing.expect_value(t, temp1.limits.set, "DEFAULT")
    testing.expect_value(t, temp1.limits.persistence, 3)
    testing.expect_value(t, temp1.limits.enabled, true)
    testing.expect_value(t, temp1.limits.red_low, -10.0)
    testing.expect_value(t, temp1.limits.yellow_low, -5.0)
    testing.expect_value(t, temp1.limits.yellow_high, 40.0)
    testing.expect_value(t, temp1.limits.red_high, 45.0)
    testing.expect_value(t, temp1.limits.has_green, true)
    testing.expect_value(t, temp1.limits.green_low, 0.0)
    testing.expect_value(t, temp1.limits.green_high, 30.0)
}

@(test)
test_build_packet_defs_tlm_txt_states :: proc(t: ^testing.T) {
    text := load_tlm_txt(t)
    defs, _ := build_packet_defs(text)
    collect_type := defs[0].items[7]

    testing.expect_value(t, collect_type.name, "COLLECT_TYPE")
    testing.expect_value(t, len(collect_type.states), 2)
    testing.expect_value(t, collect_type.states[0].name, "NORMAL")
    testing.expect_value(t, collect_type.states[0].value, i64(0))
    testing.expect_value(t, collect_type.states[1].name, "SPECIAL")
    testing.expect_value(t, collect_type.states[1].value, i64(1))

    deployed := defs[0].items[8]
    testing.expect_value(t, len(deployed.states), 2)
    testing.expect_value(t, deployed.states[0].name, "FALSE")
    testing.expect_value(t, deployed.states[1].name, "TRUE")
}

@(test)
test_build_packet_defs_state_with_color :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nAPPEND_ITEM X 8 UINT\nSTATE BAD 1 RED\n"
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    testing.expect_value(t, defs[0].items[0].states[0].color, TlmStateColor.Red)
}

@(test)
test_build_packet_defs_multiple_packets :: proc(t: ^testing.T) {
    text := `TELEMETRY TGT ONE BIG_ENDIAN
  APPEND_ITEM A 8 UINT
  APPEND_ITEM B 8 UINT
TELEMETRY TGT TWO LITTLE_ENDIAN
  APPEND_ITEM C 16 UINT
`
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    testing.expect_value(t, len(defs), 2)
    testing.expect_value(t, defs[0].name, "ONE")
    testing.expect_value(t, len(defs[0].items), 2)
    testing.expect_value(t, defs[1].name, "TWO")
    testing.expect_value(t, defs[1].little_endian, true)
    testing.expect_value(t, len(defs[1].items), 1)
}

@(test)
test_build_packet_defs_item_without_packet_errors :: proc(t: ^testing.T) {
    text := "APPEND_ITEM A 8 UINT\n"
    _, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.Item_Without_Packet)
}

@(test)
test_build_packet_defs_modifier_without_item_errors :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nUNITS \"Volts\" \"V\"\n"
    _, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.Modifier_Without_Item)
}

@(test)
test_build_packet_defs_unknown_item_type_errors :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nAPPEND_ITEM A 8 BOGUS\n"
    _, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.Unknown_Item_Type)
}

@(test)
test_build_packet_defs_unterminated_generic_conversion_errors :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nITEM D 0 0 DERIVED\nGENERIC_READ_CONVERSION_START\n  (1)\n"
    _, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.Generic_Conversion_Not_Terminated)
}

@(test)
test_build_packet_defs_append_item_with_endianness_override :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nAPPEND_ITEM A 32 FLOAT \"desc\" LITTLE_ENDIAN\n"
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    item := defs[0].items[0]
    testing.expect_value(t, item.desc, "desc")
    testing.expect_value(t, item.little_endian, true)
}

@(test)
test_build_packet_defs_id_item_explicit_offset :: proc(t: ^testing.T) {
    text := "TELEMETRY TGT PKT BIG_ENDIAN\nID_ITEM A -32 32 UINT 7 \"desc\"\n"
    defs, err := build_packet_defs(text)
    testing.expect_value(t, err, Build_Error.None)
    item := defs[0].items[0]
    testing.expect_value(t, item.bit_offset, -32)
    testing.expect_value(t, item.kind, TlmItemKind.Id)
    testing.expect_value(t, item.id_value, i64(7))
    testing.expect_value(t, item.desc, "desc")
    testing.expect_value(t, len(defs[0].id_item_idxs), 1)
}
