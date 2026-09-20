package main

import "core:os"
import "core:strings"
import "core:fmt"
import rl "vendor:raylib"


TokenState :: enum {
    NONE,
    IDENT,
    STR,
    INT,
    FLOAT,
    COMMENT,
}

Token :: struct {
    state:     TokenState,
    idx_start: int,
    idx_end:   int,
}

token_print :: proc(token: Token, text: string) {
    if token.state == TokenState.NONE {
        fmt.println("none")
        return
    }

    token_text := text[token.idx_start:token.idx_end]
    switch token.state {
        case TokenState.IDENT:
            fmt.printfln("ident(%s)", token_text)
        case TokenState.STR:
            fmt.printfln("string(%s)", token_text)
        case TokenState.INT:
            fmt.printfln("num(%s)", token_text)
        case TokenState.FLOAT:
            fmt.printfln("float(%s)", token_text)
        case TokenState.COMMENT:
            fmt.printfln("comment(%s)", token_text)
        case TokenState.NONE:
    }
}

line_print :: proc(keyword: Token, params: []Token, text: string) {
    fmt.printf("%s(", text[keyword.idx_start:keyword.idx_end])
    for param, i in params {
        if i > 0 {
            fmt.printf(", ")
        }
        fmt.printf("%s", text[param.idx_start:param.idx_end])
    }
    fmt.printfln(")")
}

is_ascii_letter :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b == '_')
}

parse_config_file :: proc(filepath: string) {
    data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		// could not read file
        fmt.println("failed to load file")
		return
	}
	defer delete(data, context.allocator)

    text := string(data)

    // token state
    token_state := TokenState.NONE
    token_idx := 0
    line_count := 0
    escaping := false

    keyword_line_count := 0
    keyword : Token
    params : [16]Token
    params_i := 0

    for i := 0; i < len(text); i += 1 {
        b := text[i] // Yields u8

        token := Token{TokenState.NONE, 0, 0}
        
        switch token_state {
            case TokenState.NONE:
                assert(!escaping)

                switch b {
                    case '"':
                        token_state = TokenState.STR
                    case '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                        token_state = TokenState.INT
                    case '.':
                        token_state = TokenState.FLOAT
                    case '\t', '\v', '\f', '\n', '\r', ' ':
                        token_state = TokenState.NONE
                    case '#':
                        token_state = TokenState.COMMENT
                    case:
                        // fmt.println("hello", b)
                        token_state = TokenState.IDENT
                }

                token_idx = i

            case TokenState.IDENT:
                assert(!escaping)
                assert(i >= 1)

                switch b {
                    case ' ', '\t', '\v', '\f', '\n', '\r':
                        token = Token{TokenState.IDENT, token_idx, i}
                        token_state = TokenState.NONE

                    case '"':
                        token = Token{TokenState.IDENT, token_idx, i}
                        token_state = TokenState.STR
                        token_idx = i
                    case '#':
                        token = Token{TokenState.IDENT, token_idx, i}
                        token_state = TokenState.COMMENT
                        token_idx = i
                    // allow . ands number
                }

            case TokenState.STR:
                assert(i >= 1)
                switch b {
                    case '\t', '\v', '\f':
                        fmt.println("ERROR: character not allowed inside of string")
                        return;
                    case '\n', '\r':
                        fmt.println("ERROR: string was not completed") // no multiline string
                        return
                    case '"':
                        assert(token_idx+1 <= i)
                        token = Token{TokenState.STR, token_idx, i+1}
                        token_state = TokenState.NONE
                }

            case TokenState.INT:
                assert(i >= 1)
                switch b {
                    case '\t', '\v', '\f', '\n', '\r', ' ':
                        token = Token{TokenState.INT, token_idx, i}
                        token_state = TokenState.NONE
                    case '.', 'e':
                        token_state = TokenState.FLOAT // convert to float
                    case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                        token_state = TokenState.INT // nominal
                    case '"':
                        token = Token{TokenState.INT, token_idx, i}
                        token_state = TokenState.STR
                        token_idx = i
                    case '#':
                        token = Token{TokenState.INT, token_idx, i}
                        token_state = TokenState.COMMENT
                        token_idx = i
                    case:
                        if is_ascii_letter(b) {
                            fmt.printfln("ERROR: character %c not allowed in float", b) // no multiline string
                            return
                        } else {
                            token = Token{TokenState.FLOAT, token_idx, i}
                            token_state = TokenState.IDENT
                            token_idx = i
                        }
                }

            case TokenState.FLOAT:
                assert(i >= 1)
                switch b {
                    case '\t', '\v', '\f', '\n', '\r', ' ':
                        token = Token{TokenState.FLOAT, token_idx, i}
                        token_state = TokenState.NONE
                    case '.', 'e', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
                        token_state = TokenState.FLOAT // nominal
                    case '"':
                        token = Token{TokenState.FLOAT, token_idx, i}
                        token_state = TokenState.STR
                        token_idx = i
                    case '#':
                        token = Token{TokenState.FLOAT, token_idx, i}
                        token_state = TokenState.COMMENT
                        token_idx = i
                    case:
                        if is_ascii_letter(b) {
                            fmt.printfln("ERROR: character %c not allowed in float", b) // no multiline string
                            return
                        } else {
                            token = Token{TokenState.FLOAT, token_idx, i}
                            token_state = TokenState.IDENT
                            token_idx = i
                        }
                }

            case TokenState.COMMENT:
                assert(i >= 1)
                switch b {
                    case '\n', '\r':
                        token = Token{TokenState.COMMENT, token_idx, i}
                        token_state = TokenState.NONE
                }
        }

        if token.state != TokenState.NONE && token.state != TokenState.COMMENT {
            if keyword.state == TokenState.NONE {
                keyword = token
                keyword_line_count = line_count
            }
            else if line_count == keyword_line_count {
                assert(params_i < len(params))
                params[params_i] = token
                params_i += 1
            } else {
                line_print(keyword, params[:params_i], text)
                keyword = token
                keyword_line_count = line_count
                params_i = 0
            }
        }

        if b == '\n' { line_count += 1 }
    }

    if keyword.state != TokenState.NONE {
        line_print(keyword, params[:params_i], text)
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