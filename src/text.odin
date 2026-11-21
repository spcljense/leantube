package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

Text_Style :: enum u16 {
	Body,
	Small,
	Caption,
	Heading,
	Title,
	Player_Title,
}
BASE_TEXT_SIZES :: [Text_Style]u16 {
	.Body         = 32,
	.Small        = 26,
	.Caption      = 20,
	.Heading      = 36,
	.Title        = 56,
	.Player_Title = 48,
}
text_sizes := BASE_TEXT_SIZES
fonts: [Text_Style]^ttf.Font
// SDL centres the line box, not the glyphs, so digits sit below the middle of a
// chip. Keep the offset that puts their ink in the middle instead.
digit_ink_shift: [Text_Style]i32
// Preserve fallback order. Relative paths refer to bundled fonts.
fallback_fonts: [Text_Style][len(FALLBACK_FONT_PATHS)]^ttf.Font
Rendered_Text :: struct {
	texture: ^sdl.Texture,
	width: c.int,
	height: c.int,
	display: string,
	font: ^ttf.Font,
}
// Reuse visible text slots in draw order.
rendered_text: [dynamic]^Rendered_Text

frame_text :: proc(renderer: ^sdl.Renderer, index: int, font: ^ttf.Font, display: string) -> ^Rendered_Text {
	if index == len(rendered_text) {
		append(&rendered_text, new(Rendered_Text))
	}
	value := rendered_text[index]
	if value.texture != nil && value.font == font && value.display == display {return value}
	if value.texture != nil {sdl.DestroyTexture(value.texture)}
	delete(value.display)
	surface := ttf.RenderUTF8_Blended(font, cstring(raw_data(display)), sdl.Color{255, 255, 255, 255})
	if surface == nil {return nil}
	defer sdl.FreeSurface(surface)
	value.texture = sdl.CreateTextureFromSurface(renderer, surface)
	// The renderer is supplied by CreateTextureFromSurface through a temporary
	// SDL context only when a renderer is active, so text rendering sets it separately.
	value.width, value.height = surface.w, surface.h
	value.display = strings.clone(display)
	value.font = font
	return value
}

open_text :: proc(renderer: ^sdl.Renderer) -> bool {
	if ttf.Init() != 0 {return false}
	// Fallbacks are optional. Missing fonts must not prevent startup.
	sources: [len(FALLBACK_FONT_PATHS)]^ttf.Font
	for path, i in FALLBACK_FONT_PATHS {
		if string(path) == "" {continue}
		resolved := path
		owned: cstring
		defer delete(owned)
		if !strings.has_prefix(string(path), "/") {
			owned = fmt.caprintf("%s/%s", app_directory, path)
			resolved = owned
		}
		sources[i] = ttf.OpenFont(resolved, c.int(text_sizes[.Body]))
	}
	defer for source in sources {if source != nil {ttf.CloseFont(source)}}
	path := fmt.caprintf("%s/fonts/Geist.ttf", app_directory)
	defer delete(path)
	for size, style in text_sizes {
		fonts[style] = ttf.OpenFont(path, c.int(size))
		if fonts[style] == nil {return false}
	}
	return true
}

resize_text :: proc() -> bool {
	for base, style in BASE_TEXT_SIZES {
		size := u16(max(1, math.round(f32(base) * ui_scale)))
		for fallback in fallback_fonts[style] {
			if fallback != nil && ttf.SetFontSize(fallback, c.int(size)) != 0 {return false}
		}
		if ttf.SetFontSize(fonts[style], c.int(size)) != 0 {return false}
		text_sizes[style] = size
		digit_ink_shift[style] = digit_ink_shift_for(fonts[style])
	}
	return true
}

// Digits share one vertical extent and have no descenders, so their ink centre
// is this far below the line box centre.
digit_ink_shift_for :: proc(font: ^ttf.Font) -> i32 {
	if font == nil {return 0}
	top, bottom: c.int
	for digit in '0' ..= '9' {
		min_y, max_y: c.int
		if ttf.GlyphMetrics32(font, digit, nil, nil, &min_y, &max_y, nil) != 0 {return 0}
		if digit == '0' {top, bottom = max_y, min_y} else {
			top = max(top, max_y)
			bottom = min(bottom, min_y)
		}
	}
	height := ttf.FontHeight(font)
	ascent := ttf.FontAscent(font)
	return (2 * i32(ascent) - i32(height) - i32(top + bottom)) / 2
}

// Return a borrowed string when it fits; otherwise the caller owns the result.
fit_text :: proc(
	font: ^ttf.Font,
	text: string,
	width: c.int,
	continued: bool = false,
) -> (
	string,
	bool,
) {
	if text == "" || width <= 0 {return "", false}
	if !continued {
		measured: c.int
		if ttf.SizeUTF8(font, cstring(raw_data(text)), &measured, nil) != 0 {
			return "", false
		}
		if measured <= width {return text, false}
	}
	ELLIPSIS: string : "…"
	ellipsis_width: c.int
	if ttf.SizeUTF8(font, cstring(raw_data(ELLIPSIS)), &ellipsis_width, nil) != 0 {
		return "", false
	}
	if ellipsis_width > width {return "", false}
	length: c.int
	if width > ellipsis_width {
		if ttf.MeasureUTF8(
			font,
			cstring(raw_data(text)),
			width - ellipsis_width,
			nil,
			&length,
		) != 0 {
			return "", false
		}
	}
	prefix := strings.trim_right_space(text[:int(length)])
	return strings.concatenate({prefix, ELLIPSIS}), true
}

// Wrap text into at most max_lines at width, ellipsizing the last visible line.
// Return a borrowed string when everything fits; otherwise the caller owns it.
// SDL_ttf wraps the text, so the line count matches the drawn result exactly.
fit_wrapped :: proc(
	font: ^ttf.Font,
	text: string,
	width: c.int,
	max_lines: int,
) -> (
	string,
	bool,
	int,
) {
	if text == "" || width <= 0 || max_lines < 1 {return text, false, 1}
	line_height := ttf.FontHeight(font)
	if line_height <= 0 {return text, false, 1}
	bounds_width, bounds_height: c.int
	if ttf.SizeUTF8(font, cstring(raw_data(text)), &bounds_width, &bounds_height) != 0 {return text, false, 1}
	lines := clamp((bounds_width + width - 1) / width, 1, c.int(max_lines))
	if bounds_width <= width * c.int(max_lines) {return text, false, int(lines)}
	line_end := c.int(len(text))
	if width > 0 {
		_, count: c.int
		if ttf.MeasureUTF8(font, cstring(raw_data(text)), width, nil, &count) != 0 {return text, false, 1}
		line_end = count
	}
	if int(line_end) >= len(text) {return text, false, int(lines)}
	// Force the ellipsis: the visible line may fit, but text follows it.
	fitted, owned := fit_text(font, text[:int(line_end)], width, true)
	if !owned {return text, false, int(lines)}
	defer delete(fitted)
	return fitted, true, int(lines)
}

close_text :: proc() {
	for value in rendered_text {
		if value.texture != nil {sdl.DestroyTexture(value.texture)}
		delete(value.display)
		free(value)
	}
	delete(rendered_text); rendered_text = nil
	for font in fonts {ttf.CloseFont(font)}
	for fallbacks in fallback_fonts {for font in fallbacks {if font != nil {ttf.CloseFont(font)}}}
	fonts, fallback_fonts = {}, {}
	if ttf.WasInit() != 0 {ttf.Quit()}
}
