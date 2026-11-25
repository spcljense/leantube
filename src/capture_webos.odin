#+build linux:default arm32
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

UI_CAPTURE_PATH :: APP_TEMP_PREFIX + "-frame.png"
capture_ui_requested: i32

// Readback and file I/O belong to the main loop, not the signal handler.
capture_ui_signal :: proc "c" (_: posix.Signal) {
	sync.atomic_store(&capture_ui_requested, 1)
}

save_ui_frame :: proc(renderer: ^sdl.Renderer) {
	surface := create_surface(i32(view_width), i32(view_height))
	if surface == nil {
		fmt.eprintln("UI capture surface allocation failed:", sdl.GetError())
		return
	}
	defer sdl.FreeSurface(surface)
	if sdl.RenderReadPixels(renderer, nil, surface.format.format, surface.pixels, surface.pitch) != 0 {
		fmt.eprintln("UI capture readback failed:", sdl.GetError())
		return
	}
	// The snapshot contains the active feed. Create a private file and publish
	// its name only after a complete PNG has been written.
	temporary := strings.clone_to_cstring(UI_CAPTURE_PATH + ".XXXXXX")
	defer delete(temporary)
	fd := posix.mkstemp(temporary)
	if fd < 0 {
		fmt.eprintln("UI capture could not create a private temporary file")
		return
	}
	defer _ = os.remove(string(temporary))
	file := posix.fdopen(fd, "wb")
	if file == nil {
		_ = posix.close(fd)
		fmt.eprintln("UI capture could not open the temporary stream")
		return
	}
	stream := sdl.RWFromFP(file, false)
	saved := stream != nil && img.SavePNG_RW(surface, stream, true) == 0
	if !saved {fmt.eprintln("UI capture PNG encoding failed:", sdl.GetError())}
	closed := posix.fclose(file) == 0
	if !saved {return}
	if !closed || os.rename(string(temporary), UI_CAPTURE_PATH) != nil {
		fmt.eprintln("UI capture could not write", UI_CAPTURE_PATH)
		return
	}
	fmt.printf("UI capture %dx%d saved to %s\n", surface.w, surface.h, UI_CAPTURE_PATH)
}
