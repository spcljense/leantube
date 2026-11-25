package main

import clay "../vendor/clay"
import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

Icon :: enum {
	Play,
	Pause,
	Slower,
	Faster,
	Account,
	Search,
	Subscriptions,
	Watch_Later,
	Watch_Later_Saved,
	History,
	Check,
	Home,
	Playlists,
	Liked,
	Spinner,
	Hide,
	SponsorBlock,
	Settings,
}
icon_assets := [Icon]struct {
	file: string,
	sizes: [4]u16,
} {
	.Play              = {"play", {32, 0, 0, 0}},
	.Pause             = {"pause", {32, 0, 0, 0}},
	.Slower            = {"minus", {28, 0, 0, 0}},
	.Faster            = {"plus", {28, 0, 0, 0}},
	.Account           = {"user-round", {32, 64, 0, 0}},
	.Search            = {"search", {32, 0, 0, 0}},
	.Subscriptions     = {"gallery-vertical-end", {32, 0, 0, 0}},
	.Watch_Later       = {"clock", {32, 40, 0, 0}},
	.Watch_Later_Saved = {"clock-check", {32, 40, 0, 0}},
	.History           = {"rotate-ccw-clock", {32, 0, 0, 0}},
	.Check             = {"check", {32, 40, 0, 0}},
	.Home              = {"house", {32, 0, 0, 0}},
	.Playlists         = {"list-video", {32, 0, 0, 0}},
	.Liked             = {"thumbs-up", {32, 0, 0, 0}},
	.Spinner           = {"loader-circle", {24, 32, 40, 48}},
	.Hide              = {"eye-off", {32, 0, 0, 0}},
	.SponsorBlock      = {"skip-forward", {32, 0, 0, 0}},
	.Settings          = {"sliders", {32, 0, 0, 0}},
}
icons: [Icon][4]^sdl.Texture

icon_pixels :: proc(size: u16) -> c.int {
	return c.int(max(1, math.round(scaled(f32(size)))))
}

icon_texture :: proc(id: Icon, size: u16) -> ^sdl.Texture {
	for variant, index in icon_assets[id].sizes {
		if variant == size {return icons[id][index]}
	}
	return nil
}

// Opaque covers still need blending for the rounded edge coverage.
upload_surface :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) -> ^sdl.Texture {
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture != nil &&
	   (sdl.SetTextureBlendMode(texture, sdl.BlendMode.BLEND) != 0 ||
		   sdl.SetTextureScaleMode(texture, .Linear) != 0) {
		sdl.DestroyTexture(texture)
		return nil
	}
	return texture
}

load_texture :: proc(renderer: ^sdl.Renderer, path: cstring) -> ^sdl.Texture {
	surface := img.Load(path)
	defer sdl.FreeSurface(surface)
	return surface == nil ? nil : upload_surface(renderer, surface)
}

// Rasterize at twice the draw size, then prefilter into physical pixels.
// A single linear GPU sample would discard most samples when minifying a large icon.
load_icon :: proc(renderer: ^sdl.Renderer, file: string, size: u16) -> ^sdl.Texture {
	path := fmt.caprintf("%s/icons/%s.svg", app_directory, file)
	defer delete(path)
	stream := sdl.RWFromFile(path, "rb")
	if stream == nil {return nil}
	defer _ = sdl.RWclose(stream)
	pixels := icon_pixels(size)
	surface := img.LoadSizedSVG_RW(stream, pixels * 2, pixels * 2)
	if surface == nil {return nil}
	defer sdl.FreeSurface(surface)
	filtered := create_surface(pixels, pixels)
	if filtered == nil {return nil}
	defer sdl.FreeSurface(filtered)
	if sdl.SoftStretchLinear(surface, nil, filtered, nil) != 0 {return nil}
	return upload_surface(renderer, filtered)
}

open_icons :: proc(renderer: ^sdl.Renderer) -> bool {
	close_icons()
	for asset, id in icon_assets {
		for size, index in asset.sizes {
			if size == 0 {continue}
			icons[id][index] = load_icon(renderer, asset.file, size)
			if icons[id][index] == nil {close_icons(); return false}
		}
	}
	return true
}

close_icons :: proc() {
	for variants in icons {
		for texture in variants {if texture != nil {sdl.DestroyTexture(texture)}}
	}
	icons = {}
}

// Float in the center without changing the parent's content layout.
centered_spinner :: proc() {
	if clay.UI()(
	{
		floating = {
			attachTo = .Parent,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			pointerCaptureMode = .Passthrough,
		},
	},
	) {icon(.Spinner)}
}

// Icons are white. A tint borrows a static color, so it outlives the layout.
icon :: proc(id: Icon, size: u16 = 48, tint: ^clay.Color = nil) {
	if clay.UI()(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(f32(icon_pixels(size))),
				height = clay.SizingFixed(f32(icon_pixels(size))),
			},
		},
		image = {imageData = rawptr(icon_texture(id, size))},
		userData = tint,
	},
	) {}
}
