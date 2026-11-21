#+build linux:default arm32
package main

import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

tv_cursor: ^sdl.Cursor

// Follow SDL-webOS: load the firmware arrow with hotspot (0, 0).
// This B9 uses the "small" pointer setting. SDL core provides the PNG loader.
open_tv_cursor :: proc() -> bool {
	surface := img.Load("/usr/share/im/cursorTypeAszSstN.png")
	if surface == nil {return false}
	defer sdl.FreeSurface(surface)
	// SDL2's linear-space premultiplication left 11 bottom-edge pixels with
	// RGB above alpha in the Wayland buffer. Bound the input once so the B9
	// blends them correctly. Keep opacity and the firmware file unchanged.
	for y in 0 ..< surface.h {
		for x in 0 ..< surface.w {
			r, g, b, a: u8
			if !read_surface_pixel(surface, x, y, &r, &g, &b, &a) {return false}
			if r > a || g > a || b > a {
				if !write_surface_pixel(surface, x, y, min(r, a), min(g, a), min(b, a), a) {
					return false
				}
			}
		}
	}
	tv_cursor = sdl.CreateColorCursor(surface, 0, 0)
	if tv_cursor == nil {return false}
	sdl.SetCursor(tv_cursor)
	return tv_cursor != nil
}

close_tv_cursor :: proc() {
	if tv_cursor != nil {sdl.FreeCursor(tv_cursor); tv_cursor = nil}
}
