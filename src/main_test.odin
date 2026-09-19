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
