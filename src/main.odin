package main

import "core:os"
import "core:fmt"
import rl "vendor:raylib"

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
