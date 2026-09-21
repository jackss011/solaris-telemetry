package main

import "core:strings"
import "core:testing"

@(test)
test_is_ascii_letter_lowercase :: proc(t: ^testing.T) {
	for c := u8('a'); c <= 'z'; c += 1 {
		testing.expectf(t, is_ascii_letter(c), "expected %c to be an ascii letter", c)
	}
}

@(test)
test_is_ascii_letter_uppercase :: proc(t: ^testing.T) {
	for c := u8('A'); c <= 'Z'; c += 1 {
		testing.expectf(t, is_ascii_letter(c), "expected %c to be an ascii letter", c)
	}
}

@(test)
test_is_ascii_letter_underscore :: proc(t: ^testing.T) {
	testing.expect(t, is_ascii_letter('_'), "expected '_' to be an ascii letter")
}

@(test)
test_is_ascii_letter_rejects_digits :: proc(t: ^testing.T) {
	for c := u8('0'); c <= '9'; c += 1 {
		testing.expectf(t, !is_ascii_letter(c), "expected %c to NOT be an ascii letter", c)
	}
}

@(test)
test_is_ascii_letter_rejects_punctuation_and_whitespace :: proc(t: ^testing.T) {
	non_letters := []u8{' ', '\t', '\n', '\r', '-', '.', '#', '"', ':', '('}
	for c in non_letters {
		testing.expectf(t, !is_ascii_letter(c), "expected %c to NOT be an ascii letter", c)
	}
}

@(test)
test_grab_token_ident :: proc(t: ^testing.T) {
	text := "HELLO next"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.IDENT)
	testing.expect_value(t, token_ref_text(token, text), "HELLO")
}

@(test)
test_grab_token_string :: proc(t: ^testing.T) {
	text := `"foo"`
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.STR)
	testing.expect_value(t, token_ref_text(token, text), `"foo"`)
}

@(test)
test_grab_token_string_with_printf_specifier :: proc(t: ^testing.T) {
	// FORMAT_STRING values are printf-style format specifiers, e.g. tlm.txt's
	// `FORMAT_STRING "%0.3f"` on the VOLTAGE item (cosmos-config-format.md's item modifier
	// table: `FORMAT_STRING <printf-format>`). The '%' and '.' inside the quotes must not be
	// mistaken for the start of a new token.
	text := `"%0.3f"`
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.STR)
	testing.expect_value(t, token_ref_text(token, text), `"%0.3f"`)
}

@(test)
test_grab_token_string_with_punctuation :: proc(t: ^testing.T) {
	// Quoted descriptions are free-form text (e.g. TELEMETRY's ["description"] param in
	// cosmos-config-format.md) and can contain parentheses, apostrophes, etc.
	text := `"Instrument's Health (nominal)"`
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.STR)
	testing.expect_value(t, token_ref_text(token, text), `"Instrument's Health (nominal)"`)
}

@(test)
test_grab_token_negative_float :: proc(t: ^testing.T) {
	// LIMITS thresholds (cosmos-config-format.md's LIMITS row: <red-low> <yellow-low> ...) are
	// plausibly floats, not just ints as in tlm.txt's example, and can be negative.
	text := "-10.5 "
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.FLOAT)
	testing.expect_value(t, token_ref_text(token, text), "-10.5")
}

@(test)
test_grab_token_int :: proc(t: ^testing.T) {
	text := "123 "
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.INT)
	testing.expect_value(t, token_ref_text(token, text), "123")
}

@(test)
test_grab_token_float :: proc(t: ^testing.T) {
	text := "1.5"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.FLOAT)
	testing.expect_value(t, token_ref_text(token, text), "1.5")
}

@(test)
test_grab_token_comment :: proc(t: ^testing.T) {
	text := "# a comment\n"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.COMMENT)
	testing.expect_value(t, token_ref_text(token, text), "# a comment")
}

@(test)
test_grab_token_newline :: proc(t: ^testing.T) {
	text := "\n"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.NEWLINE)
	testing.expect_value(t, token.idx_start, 0)
	testing.expect_value(t, token.idx_end, 1)
}

@(test)
test_grab_token_eof_returns_none :: proc(t: ^testing.T) {
	text := "   "
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.NONE)
	testing.expect_value(t, token.idx_start, len(text))
	testing.expect_value(t, token.idx_end, len(text))
}

@(test)
test_grab_token_negative_int :: proc(t: ^testing.T) {
	text := "-42 "
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.INT)
	testing.expect_value(t, token_ref_text(token, text), "-42")
}

@(test)
test_grab_token_float_scientific :: proc(t: ^testing.T) {
	text := "1e5 "
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.FLOAT)
	testing.expect_value(t, token_ref_text(token, text), "1e5")
}

@(test)
test_grab_token_ident_at_eof_without_delimiter :: proc(t: ^testing.T) {
	text := "HELLO"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.IDENT)
	testing.expect_value(t, token_ref_text(token, text), "HELLO")
}

@(test)
test_grab_token_int_at_eof_without_delimiter :: proc(t: ^testing.T) {
	text := "123"
	token := grab_token(text, 0)
	testing.expect_value(t, token.type, TokenType.INT)
	testing.expect_value(t, token_ref_text(token, text), "123")
}

@(test)
test_grab_token_sequence_advances_idx :: proc(t: ^testing.T) {
	text := "FOO 1\n"
	tok1 := grab_token(text, 0)
	testing.expect_value(t, tok1.type, TokenType.IDENT)
	testing.expect_value(t, token_ref_text(tok1, text), "FOO")

	tok2 := grab_token(text, tok1.idx_end)
	testing.expect_value(t, tok2.type, TokenType.INT)
	testing.expect_value(t, token_ref_text(tok2, text), "1")

	tok3 := grab_token(text, tok2.idx_end)
	testing.expect_value(t, tok3.type, TokenType.NEWLINE)
}

@(test)
test_grab_until_found :: proc(t: ^testing.T) {
	text := "foo\nbar\nEND\nbaz"
	found, end_idx := grab_until(text, 0, "END")
	testing.expect(t, found, "expected to find END")
	testing.expect_value(t, end_idx, 8)
}

@(test)
test_grab_until_not_found :: proc(t: ^testing.T) {
	text := "foo\nbar\n"
	found, end_idx := grab_until(text, 0, "END")
	testing.expect(t, !found, "expected END to not be found")
	testing.expect_value(t, end_idx, len(text))
}

@(test)
test_grab_until_requires_exact_word_not_substring :: proc(t: ^testing.T) {
	text := "foo\nEND_EXTRA\nEND\nbaz"
	found, end_idx := grab_until(text, 0, "END")
	testing.expect(t, found, "expected to find exact END, not END_EXTRA")
	testing.expect_value(t, end_idx, 14)
}

@(test)
test_grab_until_matches_first_line :: proc(t: ^testing.T) {
	text := "END\nfoo\n"
	found, end_idx := grab_until(text, 0, "END")
	testing.expect(t, found, "expected to find END on the first line")
	testing.expect_value(t, end_idx, 0)
}

@(test)
test_grab_until_generic_conversion_block_spans_multiple_lines_with_code :: proc(t: ^testing.T) {
	// cosmos-config-format.md's GENERIC_READ_CONVERSION_START/END section: the body between
	// the two markers is arbitrary Ruby, captured verbatim line-by-line and never tokenized,
	// so code that itself looks tokenizable (parens, quotes, operators) must not confuse the
	// END-line scan. Modeled on tlm.txt's DURATION item body
	// (`(packet.read('COLLECTS') * 0.5)`), extended with an extra line using string quotes,
	// a ternary-like operator, and an inline '#' comment to stress the scan further.
	text := `  (packet.read('COLLECTS') * 0.5)
  status = (value != nil) ? "ok" : "error" # inline note
GENERIC_READ_CONVERSION_END
`
	expected_idx := strings.index(text, "GENERIC_READ_CONVERSION_END")
	found, end_idx := grab_until(text, 0, "GENERIC_READ_CONVERSION_END")
	testing.expect(t, found, "expected to find GENERIC_READ_CONVERSION_END")
	testing.expect_value(t, end_idx, expected_idx)
}

@(test)
test_grab_keyword_with_params :: proc(t: ^testing.T) {
	text := "FOO 1 2\n"
	keyword, next_idx := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "FOO")
	testing.expect_value(t, keyword.params_count, 2)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "1")
	testing.expect_value(t, token_ref_text(keyword.params[1], text), "2")
	testing.expect_value(t, next_idx, len(text))
}

@(test)
test_grab_keyword_skips_blank_and_comment_lines :: proc(t: ^testing.T) {
	text := "\n# just a comment\nFOO 1\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "FOO")
	testing.expect_value(t, keyword.params_count, 1)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "1")
}

@(test)
test_grab_keyword_at_eof_returns_none :: proc(t: ^testing.T) {
	text := ""
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.token.type, TokenType.NONE)
}

@(test)
test_grab_keyword_zero_params :: proc(t: ^testing.T) {
	text := "FOO\n"
	keyword, next_idx := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "FOO")
	testing.expect_value(t, keyword.params_count, 0)
	testing.expect_value(t, next_idx, len(text))
}

@(test)
test_grab_keyword_item_negative_bit_offset :: proc(t: ^testing.T) {
	// cosmos-config-format.md item notes: "Bit offset is measured from the MSB; a negative
	// offset means 'from the end of the packet.'" ITEM's param order is
	// name, bit offset, bit size, data type, [description].
	text := `ITEM FOO -32 32 UINT "Signal from end of packet"
`
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "ITEM")
	testing.expect_value(t, keyword.params_count, 5)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "FOO")
	testing.expect_value(t, token_ref_text(keyword.params[1], text), "-32")
	testing.expect_value(t, keyword.params[1].type, TokenType.INT)
}

@(test)
test_grab_keyword_limits_with_green_thresholds :: proc(t: ^testing.T) {
	// cosmos-config-format.md: LIMITS <set> <persistence> <ENABLED|DISABLED> <red-low>
	// <yellow-low> <yellow-high> <red-high> [green-low] [green-high] — the trailing green
	// bounds are optional. tlm.txt's TEMP1 item supplies them:
	// `LIMITS DEFAULT 3 ENABLED -10 -5 40 45 0 30`.
	text := "LIMITS DEFAULT 3 ENABLED -10 -5 40 45 0 30\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 9)
	testing.expect_value(t, token_ref_text(keyword.params[7], text), "0")
	testing.expect_value(t, token_ref_text(keyword.params[8], text), "30")
}

@(test)
test_grab_keyword_limits_without_green_thresholds :: proc(t: ^testing.T) {
	// Same LIMITS keyword, but omitting the optional [green-low] [green-high] pair, per
	// cosmos-config-format.md marking those two params optional.
	text := "LIMITS DEFAULT 1 ENABLED -10 -5 40 45\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 7)
	testing.expect_value(t, token_ref_text(keyword.params[6], text), "45")
}

@(test)
test_grab_keyword_limits_with_float_thresholds :: proc(t: ^testing.T) {
	// tlm.txt's LIMITS example uses integer thresholds, but cosmos-config-format.md doesn't
	// restrict them to ints; a real target's thresholds are plausibly floats.
	text := "LIMITS DEFAULT 3 ENABLED -10.5 -5.25 40.5 45.75\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 7)
	testing.expect_value(t, keyword.params[3].type, TokenType.FLOAT)
	testing.expect_value(t, token_ref_text(keyword.params[3], text), "-10.5")
	testing.expect_value(t, token_ref_text(keyword.params[6], text), "45.75")
}

@(test)
test_grab_keyword_state_with_color :: proc(t: ^testing.T) {
	// cosmos-config-format.md: `STATE <key> <value> [GREEN|YELLOW|RED]` — the color is an
	// optional trailing param.
	text := "STATE SPECIAL 1 YELLOW\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 3)
	testing.expect_value(t, token_ref_text(keyword.params[2], text), "YELLOW")
}

@(test)
test_grab_keyword_state_without_color :: proc(t: ^testing.T) {
	// Same STATE keyword without the optional color, matching tlm.txt's plain STATE lines
	// (`STATE NORMAL 0`), for contrast with the colored form above.
	text := "STATE NORMAL 0\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 2)
}

@(test)
test_grab_keyword_select_telemetry_reopen :: proc(t: ^testing.T) {
	// cosmos-config-format.md: `SELECT_TELEMETRY <target> <packet-name>` reopens an existing
	// packet (the mechanism tlm_override.txt-style files rely on).
	text := "SELECT_TELEMETRY YEP01 HEALTH_STATUS\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "SELECT_TELEMETRY")
	testing.expect_value(t, keyword.params_count, 2)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "YEP01")
	testing.expect_value(t, token_ref_text(keyword.params[1], text), "HEALTH_STATUS")
}

@(test)
test_grab_keyword_select_item_reopen :: proc(t: ^testing.T) {
	// cosmos-config-format.md: `SELECT_ITEM <item name>` reopens an item to add modifiers.
	text := "SELECT_ITEM VOLTAGE\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "SELECT_ITEM")
	testing.expect_value(t, keyword.params_count, 1)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "VOLTAGE")
}

@(test)
test_grab_keyword_append_item_with_endianness :: proc(t: ^testing.T) {
	// cosmos-config-format.md's APPEND_ITEM row: name, bit size, data type, [description],
	// [endianness] — endianness (BIG_ENDIAN/LITTLE_ENDIAN) is an optional trailing param that
	// overrides the packet-level endianness for this one item.
	text := `APPEND_ITEM VOLTAGE 32 FLOAT "Measured bus voltage" LITTLE_ENDIAN
`
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, keyword.params_count, 5)
	testing.expect_value(t, token_ref_text(keyword.params[4], text), "LITTLE_ENDIAN")
	testing.expect_value(t, keyword.params[4].type, TokenType.IDENT)
}

@(test)
test_grab_keyword_trailing_comment_after_params :: proc(t: ^testing.T) {
	// COSMOS config files use '#' for comments (grab_token's COMMENT token, and every
	// commented header line in tlm.txt); a comment trailing after a keyword's params on the
	// same line should not be swallowed up as an extra positional param.
	text := "FOO 1 2 # trailing comment\n"
	keyword, next_idx := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "FOO")
	testing.expect_value(t, keyword.params_count, 2)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "1")
	testing.expect_value(t, token_ref_text(keyword.params[1], text), "2")
	testing.expect_value(t, next_idx, len(text))
}

@(test)
test_grab_keyword_consecutive_comment_lines_before_keyword :: proc(t: ^testing.T) {
	// tlm.txt uses standalone '#' comment lines as section headers (e.g. "# Packet
	// identification"); two such comment lines in a row, with no blank line between them,
	// should both be skipped to reach the next real keyword.
	text := `# first comment
# second comment
FOO 1
`
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "FOO")
	testing.expect_value(t, keyword.params_count, 1)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "1")
}

@(test)
test_grab_keyword_multiple_spaces_and_tabs_between_params :: proc(t: ^testing.T) {
	// cosmos-config-format.md: "Files are plain text, one keyword per line (leading whitespace
	// is just for readability)" — COSMOS config lines are free-form whitespace-separated, and
	// tlm.txt itself indents/aligns params with runs of spaces (e.g. the APPEND_ID_ITEM block).
	text := "APPEND_ITEM   VOLTAGE\t\t32\tFLOAT   \"Measured bus voltage\"\n"
	keyword, _ := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword.token, text), "APPEND_ITEM")
	testing.expect_value(t, keyword.params_count, 4)
	testing.expect_value(t, token_ref_text(keyword.params[0], text), "VOLTAGE")
	testing.expect_value(t, token_ref_text(keyword.params[1], text), "32")
	testing.expect_value(t, token_ref_text(keyword.params[2], text), "FLOAT")
	testing.expect_value(t, token_ref_text(keyword.params[3], text), `"Measured bus voltage"`)
}

@(test)
test_grab_keyword_multiple_lines_advance_correctly :: proc(t: ^testing.T) {
	text := "FOO 1\nBAR 2 3\n"

	keyword1, idx1 := grab_keyword(text, 0)
	testing.expect_value(t, token_ref_text(keyword1.token, text), "FOO")
	testing.expect_value(t, keyword1.params_count, 1)
	testing.expect_value(t, token_ref_text(keyword1.params[0], text), "1")

	keyword2, idx2 := grab_keyword(text, idx1)
	testing.expect_value(t, token_ref_text(keyword2.token, text), "BAR")
	testing.expect_value(t, keyword2.params_count, 2)
	testing.expect_value(t, token_ref_text(keyword2.params[0], text), "2")
	testing.expect_value(t, token_ref_text(keyword2.params[1], text), "3")
	testing.expect_value(t, idx2, len(text))
}
