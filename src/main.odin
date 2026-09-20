package main

import "core:os"
import "core:strings"
import "core:fmt"
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


main :: proc() {
    fmt.println("Hello basic parse example!")
    parse_config_file("examples/simple_tlm/tlm.txt")
}

// main :: proc() {
//     rl.InitWindow(1280, 720, "Telemetry Viewer")
//     defer rl.CloseWindow()
//     rl.SetTargetFPS(60)

//     for !rl.WindowShouldClose() {
//         rl.BeginDrawing()
//         defer rl.EndDrawing()

//         rl.ClearBackground(rl.Color{15, 15, 20, 255})

//         // Rounded transparent panel
//         rl.DrawRectangleRounded(
//             rl.Rectangle{40, 40, 300, 150},
//             0.15,   // roundness
//             8,      // segments
//             rl.Color{30, 30, 35, 160}, // fill, translucent
//         )
//         rl.DrawRectangleRoundedLinesEx(
//             rl.Rectangle{40, 40, 300, 150},
//             0.15, 8, 1.5,
//             rl.Color{255, 255, 255, 60}, // border
//         )

//         // Text and values drawn straight on top
//         rl.DrawText("VOLTAGE", 60, 60, 18, rl.WHITE)
//         rl.DrawText("28.4 V", 60, 90, 32, rl.GREEN)

//         rl.DrawFPS(10, 10)
//     }
// }