package main

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
