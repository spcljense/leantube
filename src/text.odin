package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

Text_Style :: enum u16 {
	Body,
	Small,
	Caption,
	Card_Metadata,
	Heading,
	Search_Input,
	Title,
	Video_Title,
	Player_Title,
}
BASE_TEXT_SIZES :: [Text_Style]u16 {
	.Body          = 32,
	.Small         = 26,
	.Caption       = 20,
	.Card_Metadata = 24,
	.Heading       = 36,
	.Search_Input  = 36,
	.Title         = 56,
	.Video_Title   = 32,
	.Player_Title  = 48,
}
// FreeType encodes the named instance in the high word of the face index.
ROBOTO_SEMIBOLD :: 6 << 16
TITLE_STYLES :: bit_set[Text_Style]{.Heading, .Title, .Video_Title, .Player_Title}
text_sizes := BASE_TEXT_SIZES
fonts: [Text_Style]^ttf.Font
// SDL centres the line box, not the glyphs, so digits sit below the middle of a
// chip. Keep the offset that puts their ink in the middle instead.
digit_ink_shift: [Text_Style]i32
fallback_fonts: [Text_Style][1 + len(BUNDLED_FALLBACKS) + len(FALLBACK_FONT_PATHS)]^ttf.Font
Rendered_Text :: struct {
	texture: ^sdl.Texture,
	width:   c.int,
	height:  c.int,
	display: string,
	font:    ^ttf.Font,
}
// Reuse visible text slots in draw order.
rendered_text: [dynamic]Rendered_Text

frame_text :: proc(
	renderer: ^sdl.Renderer,
	index: int,
	font: ^ttf.Font,
	display: string,
) -> ^Rendered_Text {
	if index == len(rendered_text) {append(&rendered_text, Rendered_Text{})}
	value := &rendered_text[index]
	if value.texture != nil && value.font == font && value.display == display {return value}
	surface := render_text_surface(font, display)
	if surface == nil {return nil}
	defer sdl.FreeSurface(surface)
	texture := upload_surface(renderer, surface)
	if texture == nil {return nil}
	release_rendered_text(index, index + 1)
	value^ = {texture, surface.w, surface.h, strings.clone(display), font}
	return value
}

release_rendered_text :: proc(first, end: int) {
	for &value in rendered_text[first:end] {
		if value.texture != nil {sdl.DestroyTexture(value.texture)}
		delete(value.display)
		value = {}
	}
}

open_text :: proc(renderer: ^sdl.Renderer) -> bool {
	if ttf.Init() != 0 {return false}
	roboto := fmt.caprintf("%s/fonts/Roboto.ttf", app_directory)
	noto := fmt.caprintf("%s/fonts/NotoSans-Regular.ttf", app_directory)
	noto_bold := fmt.caprintf("%s/fonts/NotoSans-Bold.ttf", app_directory)
	defer {delete(roboto); delete(noto); delete(noto_bold)}
	for size, style in text_sizes {
		if style in TITLE_STYLES {
			fonts[style] = ttf.OpenFont(noto_bold, c.int(size))
			fallback_fonts[style][0] = ttf.OpenFontIndex(roboto, c.int(size), ROBOTO_SEMIBOLD)
		} else {
			fonts[style] = ttf.OpenFont(roboto, c.int(size))
			fallback_fonts[style][0] = ttf.OpenFont(noto, c.int(size))
		}
		if fonts[style] == nil || fallback_fonts[style][0] == nil {return false}
		ttf.SetFontHinting(fonts[style], .LIGHT)
		ttf.SetFontHinting(fallback_fonts[style][0], .LIGHT)
	}
	return open_fallback_fonts()
}

resize_text :: proc() -> bool {
	release_rendered_text(0, len(rendered_text))
	clear(&rendered_text)
	for base, style in BASE_TEXT_SIZES {
		size := u16(max(1, math.round(f32(base) * ui_scale)))
		for &fallback in fallback_fonts[style] {
			if fallback != nil && ttf.SetFontSize(fallback, c.int(size)) != 0 {
				ttf.CloseFont(fallback)
				fallback = nil
			}
		}
		if ttf.SetFontSize(fonts[style], c.int(size)) != 0 {return false}
		text_sizes[style] = size
		digit_ink_shift[style] = digit_ink_shift_for(fonts[style])
	}
	return true
}

measure_font :: proc(font: ^ttf.Font, text: string, width, height: ^c.int) -> bool {
	terminated := strings.clone_to_cstring(text)
	defer delete(terminated)
	return ttf.SizeUTF8(font, terminated, width, height) == 0
}

// Keep Odin slices on grapheme boundaries, including across fallback faces.
text_fit_offset :: proc(font: ^ttf.Font, text: string, width: c.int) -> int {
	runs := fallback_text_runs(font, text)
	defer delete(runs)
	remaining := width
	for run in runs {
		part := text[run.first:run.end]
		advance: c.int
		if !measure_font(run.font, part, &advance, nil) {return run.first}
		if advance > remaining {return run.first + font_fit_offset(run.font, part, remaining)}
		remaining -= advance
	}
	return len(runs) > 0 ? len(text) : font_fit_offset(font, text, width)
}

font_fit_offset :: proc(font: ^ttf.Font, text: string, width: c.int) -> int {
	if text == "" || width <= 0 {return 0}
	// HarfBuzz may produce one glyph from several scalars or several glyphs
	// from one cluster. Measure real prefixes when those counts can differ.
	if len(text) != utf8.rune_count_in_string(text) {
		boundaries := make([dynamic]int)
		defer delete(boundaries)
		iterator := utf8.decode_grapheme_iterator_make(text)
		for _, grapheme in utf8.decode_grapheme_iterate(&iterator) {
			append(&boundaries, grapheme.byte_index)
		}
		append(&boundaries, len(text))
		first, last := 0, len(boundaries)
		for first + 1 < last {
			mid := (first + last) / 2
			measured: c.int
			if !measure_font(font, text[:boundaries[mid]], &measured, nil) {return 0}
			if measured <= width {first = mid} else {last = mid}
		}
		return boundaries[first]
	}
	terminated := strings.clone_to_cstring(text)
	defer delete(terminated)
	count: c.int
	if ttf.MeasureUTF8(font, terminated, width, nil, &count) != 0 {return 0}
	return min(len(text), int(max(0, count)))
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
		if !measure_utf8(font, text, &measured, nil) {
			return "", false
		}
		if measured <= width {return text, false}
	}
	ELLIPSIS: string : "…"
	ellipsis_width: c.int
	if !measure_utf8(font, ELLIPSIS, &ellipsis_width, nil) {
		return "", false
	}
	if ellipsis_width > width {return "", false}
	length := text_fit_offset(font, text, width - ellipsis_width)
	prefix := strings.trim_right_space(text[:length])
	return strings.concatenate({prefix, ELLIPSIS}), true
}

// Wrap text into at most max_lines at width, ellipsizing the last visible line.
// Return the original for a single line. Wrapped results carry explicit breaks.
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
	remaining := text
	wrapped := strings.builder_make()
	defer strings.builder_destroy(&wrapped)
	for line in 1 ..= max_lines {
		paragraph := remaining
		if newline := strings.index_byte(remaining, '\n');
		   newline >= 0 {paragraph = remaining[:newline]}
		end := text_fit_offset(font, paragraph, width)
		if end == len(remaining) {
			if line == 1 {return text, false, 1}
			strings.write_string(&wrapped, remaining)
			return strings.clone(strings.to_string(wrapped)), true, line
		}
		if line == max_lines || (end == 0 && paragraph != "") {
			fitted, owned := fit_text(font, paragraph, width, true)
			defer if owned {delete(fitted)}
			strings.write_string(&wrapped, fitted)
			return strings.clone(strings.to_string(wrapped)), true, line
		}
		if end < len(paragraph) && paragraph[end] != ' ' {
			if space := strings.last_index_byte(paragraph[:end], ' '); space > 0 {end = space}
		}
		strings.write_string(&wrapped, strings.trim_right_space(paragraph[:end]))
		strings.write_byte(&wrapped, '\n')
		remaining = strings.trim_left_space(remaining[end:])
	}
	return text, false, 1
}

close_text :: proc() {
	release_rendered_text(0, len(rendered_text))
	delete(rendered_text); rendered_text = nil
	for font in fonts {ttf.CloseFont(font)}
	for fallbacks in fallback_fonts {for font in fallbacks {if font != nil {ttf.CloseFont(font)}}}
	fonts, fallback_fonts = {}, {}
	if ttf.WasInit() != 0 {ttf.Quit()}
}
