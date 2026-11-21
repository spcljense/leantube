package main

import "core:c"
import sdl "vendor:sdl2"

create_surface :: proc(width, height: c.int) -> ^sdl.Surface {
	return sdl.CreateRGBSurfaceWithFormat(0, width, height, 32, u32(sdl.PixelFormatEnum.RGBA32))
}

read_surface_pixel :: proc(
	surface: ^sdl.Surface,
	x, y: c.int,
	r, g, b, a: ^u8,
) -> bool {
	if surface == nil || x < 0 || y < 0 || x >= surface.w || y >= surface.h {return false}
	if sdl.LockSurface(surface) != 0 {return false}
	defer sdl.UnlockSurface(surface)
	pixel := (^u32)(rawptr(uintptr(surface.pixels) + uintptr(y * surface.pitch + x * 4)))^
	if r != nil || g != nil || b != nil || a != nil {
		sdl.GetRGBA(pixel, surface.format, r, g, b, a)
	}
	return true
}

write_surface_pixel :: proc(
	surface: ^sdl.Surface,
	x, y: c.int,
	r, g, b, a: u8,
) -> bool {
	if surface == nil || x < 0 || y < 0 || x >= surface.w || y >= surface.h {return false}
	if sdl.LockSurface(surface) != 0 {return false}
	defer sdl.UnlockSurface(surface)
	pixel := sdl.MapRGBA(surface.format, r, g, b, a)
	(^u32)(rawptr(uintptr(surface.pixels) + uintptr(y * surface.pitch + x * 4)))^ = pixel
	return true
}
