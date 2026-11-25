package main

import "core:c"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

Fallback_Face :: struct {
	path, script: cstring,
	direction:    ttf.Direction,
}

BUNDLED_FALLBACKS :: [?]Fallback_Face {
	{"NotoSansArabic-Regular.ttf", "Arab", .RTL},
	{"NotoSansHebrew-Regular.ttf", "Hebr", .RTL},
	{"NotoSansDevanagari-Regular.ttf", "Deva", .LTR},
	{"NotoSansBengali-Regular.ttf", "Beng", .LTR},
	{"NotoSansThai-Regular.ttf", "Thai", .LTR},
	{path = "NotoSansCJK-Regular.ttf"},
	{path = "NotoEmoji.ttf"},
	{path = "NotoSansMath.ttf"},
	{path = "NotoSansSymbols-Regular.ttf"},
	{path = "NotoSansSymbols2-Regular.ttf"},
}

open_fallback_fonts :: proc() -> bool {
	for face, index in BUNDLED_FALLBACKS {
		path := fmt.caprintf("%s/fonts/%s", app_directory, face.path)
		defer delete(path)
		for size, style in text_sizes {
			font := ttf.OpenFont(path, c.int(size))
			if font == nil {return false}
			fallback_fonts[style][index + 1] = font
			ttf.SetFontHinting(font, .LIGHT)
			if face.script != nil {
				_ = ttf.SetFontScriptName(font, face.script)
				_ = ttf.SetFontDirection(font, face.direction)
			}
		}
	}
	for path, index in FALLBACK_FONT_PATHS {
		if string(path) == "" {continue}
		for size, style in text_sizes {
			font := open_platform_fallback(path, c.int(size), style)
			if font != nil {ttf.SetFontHinting(font, .LIGHT)}
			fallback_fonts[style][index + 1 + len(BUNDLED_FALLBACKS)] = font
		}
	}
	return true
}

Text_Run :: struct {
	font:       ^ttf.Font,
	first, end: int,
}

font_supports_text :: proc(font: ^ttf.Font, text: string) -> bool {
	for codepoint in text {
		// Shaping consumes these controls. They do not need a visible glyph
		// or a different font from the letters and marks beside them.
		switch codepoint {
		case 0xAD,
		     0x34F,
		     0x61C,
		     0xFEFF,
		     0x200B ..=
		     0x200F,
		     0x202A ..=
		     0x202E,
		     0x2060,
		     0x2066 ..=
		     0x2069,
		     0xFE00 ..=
		     0xFE0F,
		     0xE0000 ..=
		     0xE007F,
		     0xE0100 ..=
		     0xE01EF:
			continue
		}
		if ttf.GlyphIsProvided32(font, codepoint) == 0 {return false}
	}
	return true
}

// SDL2_ttf has no fallback chain. Shape consecutive graphemes in the same
// font together so fallback does not separate combining marks or ligatures.
fallback_text_runs :: proc(font: ^ttf.Font, text: string) -> (runs: [dynamic]Text_Run) {
	if font == nil {return}
	style: Text_Style
	for primary, index in fonts {
		if primary == font {style = index; break}
	}
	if fonts[style] != font || font_supports_text(font, text) {return}
	// Shape a complete right-to-left title together when it belongs to one
	// script. Spaces must not split it into independently reversed words.
	for face, index in BUNDLED_FALLBACKS {
		if face.direction != .RTL {continue}
		fallback := fallback_fonts[style][index + 1]
		if fallback != nil && font_supports_text(fallback, text) {
			append(&runs, Text_Run{fallback, 0, len(text)})
			return
		}
	}
	first := 0
	current := font
	iterator := utf8.decode_grapheme_iterator_make(text)
	for part, grapheme in utf8.decode_grapheme_iterate(&iterator) {
		chosen := font
		if !font_supports_text(font, part) {
			for fallback in fallback_fonts[style] {
				if fallback != nil && font_supports_text(fallback, part) {chosen = fallback; break}
			}
		}
		if chosen == current {continue}
		if grapheme.byte_index >
		   first {append(&runs, Text_Run{current, first, grapheme.byte_index})}
		first, current = grapheme.byte_index, chosen
	}
	if first > 0 || current != font {append(&runs, Text_Run{current, first, len(text)})}
	return
}

text_run_bounds :: proc(
	font: ^ttf.Font,
	text: string,
	runs: []Text_Run,
) -> (
	width, height, ascent: c.int,
	ok: bool,
) {
	ascent = ttf.FontAscent(font)
	descent := ttf.FontHeight(font) - ascent
	for run in runs {
		run_width, run_height: c.int
		if !measure_font(run.font, text[run.first:run.end], &run_width, &run_height) {return}
		run_ascent := ttf.FontAscent(run.font)
		width += run_width
		ascent = max(ascent, run_ascent)
		descent = max(descent, run_height - run_ascent)
	}
	return width, ascent + descent, ascent, true
}

measure_utf8 :: proc(font: ^ttf.Font, text: string, width, height: ^c.int) -> bool {
	runs := fallback_text_runs(font, text)
	defer delete(runs)
	if len(runs) == 0 {return measure_font(font, text, width, height)}
	w, h, _, ok := text_run_bounds(font, text, runs[:])
	if width != nil {width^ = w}
	if height != nil {height^ = h}
	return ok
}

render_font_surface :: proc(font: ^ttf.Font, text: string) -> ^sdl.Surface {
	terminated := strings.clone_to_cstring(text)
	defer delete(terminated)
	return ttf.RenderUTF8_Blended(font, terminated, {255, 255, 255, 255})
}

render_text_surface :: proc(font: ^ttf.Font, text: string) -> ^sdl.Surface {
	runs := fallback_text_runs(font, text)
	defer delete(runs)
	if len(runs) == 0 {return render_font_surface(font, text)}
	width, height, ascent, ok := text_run_bounds(font, text, runs[:])
	if !ok {return nil}
	surface := create_surface(width, height)
	if surface == nil {return nil}
	x: c.int
	for run in runs {
		image := render_font_surface(run.font, text[run.first:run.end])
		if image == nil {sdl.FreeSurface(surface); return nil}
		defer sdl.FreeSurface(image)
		destination := sdl.Rect{x, ascent - ttf.FontAscent(run.font), image.w, image.h}
		if sdl.SetSurfaceBlendMode(image, .NONE) != 0 ||
		   sdl.BlitSurface(image, nil, surface, &destination) !=
			   0 {sdl.FreeSurface(surface); return nil}
		x += image.w
	}
	return surface
}
