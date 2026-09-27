package main

import "core:os"
import "core:fmt"

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
            raw_mode_until := generic_conversion_end_marker(token_ref_text(keyword.token, text))

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
    run_viewer()
}

// Console debug driver predating the UI (src/ui.odin) - still useful for inspecting how a
// config file tokenizes/parses without the raylib window. Run by temporarily swapping the
// call in main() above.
// debug_print_config :: proc() {
//     fmt.println("Hello basic parse example!")
//     parse_config_file("examples/simple_tlm/tlm.txt")
// }
