package main

import clay "../vendor/clay"
import "core:c"
import "core:math"
import "core:strings"
import "core:text/edit"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

search_editing: bool
search_text: strings.Builder
search_editor: edit.State
search_scroll: f32
SEARCH_CARET_WIDTH :: f32(1)

close_search :: proc() {
	edit.destroy(&search_editor)
	search_editor = {}
	strings.builder_destroy(&search_text)
	search_editing = false
	search_scroll = 0
}

edit_search :: proc(window: ^sdl.Window) {
	if search_editing {return}
	strings.write_string(&search_text, catalog.query)
	edit.init(&search_editor, context.allocator, context.allocator)
	edit.setup_once(&search_editor, &search_text)
	search_editor.translate_by_grapheme = true
	search_editing = true
	if !start_text_input(window) {
		close_search()
		show_notice("Text input unavailable")
	}
	dirty = true
}
finish_search_input :: proc(window: ^sdl.Window) {
	close_search()
	rail_focus = false
	stop_text_input(window)
	dirty = true
}
append_search_text :: proc(text: string) {
	if !search_editing {return}
	lo, hi := edit.sorted_selection(&search_editor)
	if strings.builder_len(search_text) - (hi - lo) + len(text) > 512 {return}
	edit.update_time(&search_editor)
	edit.input_text(&search_editor, text)
	update_text_input()
	dirty = true
}
// LG text-model deletion uses byte offsets relative to the current caret.
erase_search_text :: proc(index: i32, length: u32) {
	if !search_editing {return}
	edit.update_time(&search_editor)
	if length == max(u32) {
		edit.clear_all(&search_editor)
	} else if edit.has_selection(&search_editor) {
		edit.selection_delete(&search_editor)
	} else {
		text := strings.to_string(search_text)
		cursor := search_editor.selection[0]
		start := cursor + int(index)
		if start < 0 || start > len(text) || length > u32(len(text) - start) {return}
		end := start + int(length)
		if start < len(text) && !utf8.rune_start(text[start]) {return}
		if end < len(text) && !utf8.rune_start(text[end]) {return}
		edit.remove(&search_editor, start, end)
		cursor -= clamp(cursor - start, 0, end - start)
		search_editor.selection = {cursor, cursor}
	}
	update_text_input()
	dirty = true
}

search_key :: proc(code: sdl.Keycode, window: ^sdl.Window, mods: sdl.Keymod = {}) -> bool {
	if !search_editing {
		if code == sdl.Keycode.TAB || code == sdl.Keycode.SLASH {
			edit_search(window)
			return true
		}
		return false
	}
	shift := mods & sdl.KMOD_SHIFT != {}
	command: edit.Command
	#partial switch code {
	case sdl.Keycode.ESCAPE, sdl.Keycode.AC_BACK, sdl.Keycode.DOWN:
		finish_search_input(window)
	case sdl.Keycode.RETURN, sdl.Keycode.KP_ENTER:
		if strings.trim_space(strings.to_string(search_text)) != "" {
			start_search(strings.to_string(search_text))
			finish_search_input(window)
		}
	case sdl.Keycode.BACKSPACE:
		command = .Backspace
	case sdl.Keycode.DELETE:
		command = .Delete
	case sdl.Keycode.LEFT:
		command = shift ? .Select_Left : .Left
	case sdl.Keycode.RIGHT:
		command = shift ? .Select_Right : .Right
	case sdl.Keycode.HOME:
		command = shift ? .Select_Start : .Start
	case sdl.Keycode.END:
		command = shift ? .Select_End : .End
	case sdl.Keycode.A:
		if mods & sdl.KMOD_CTRL != {} {command = .Select_All}
	}
	if command != .None {
		edit.update_time(&search_editor)
		edit.perform_command(&search_editor, command)
		update_text_input()
		dirty = true
	}
	return true
}

// SDL_ttf substring rectangles enclose ink, not insertion boundaries.
// Center stops in the gaps between shaped clusters, not on a letter's edge.
search_text_x :: proc(font: ^ttf.Font, value: string, at: int) -> (f32, bool) {
	if at <= 0 {return 0, true}
	if at >= len(value) {
		width: c.int
		if ttf.SizeUTF8(font, cstring(raw_data(value)), &width, nil) != 0 {return 0, false}
		return f32(width), true
	}
	width: c.int
	prefix := value[:at]
	if ttf.SizeUTF8(font, cstring(raw_data(prefix)), &width, nil) != 0 {return 0, false}
	return f32(width), true
}

search_pointer :: proc(x: f32, extend: bool = false) {
	value := strings.to_string(search_text)
	at := 0
	if value != "" {
		box := clay.GetElementData(clay.ID("search-text")).boundingBox
		point := x - math.round(box.x - search_scroll)
		first, ok := search_text_x(fonts[.Heading], value, 0)
		if !ok {return}
		nearest := math.abs(point - first)
		it := utf8.decode_grapheme_iterator_make(value)
		for part, grapheme in utf8.decode_grapheme_iterate(&it) {
			boundary := grapheme.byte_index + len(part)
			position, found := search_text_x(fonts[.Heading], value, boundary)
			if !found {return}
			if distance := math.abs(point - position); distance < nearest {
				at, nearest = boundary, distance
			}
		}
	}
	search_editor.selection[0] = at
	if !extend {search_editor.selection[1] = at}
	update_text_input()
	dirty = true
}

render_search_text :: proc(
	renderer: ^sdl.Renderer,
	rect: sdl.FRect,
	index: int,
	clip: sdl.Rect,
) -> bool {
	// The fixed icon stays outside the scrolling text's clip.
	box := clay.GetElementData(clay.ID("search-icon")).boundingBox
	destination := sdl.FRect{box.x, box.y, box.width, box.height}
	texture := icons[.Search]
	if sdl.SetTextureColorMod(
		texture,
		u8(COLOR_MUTED[0]),
		u8(COLOR_MUTED[1]),
		u8(COLOR_MUTED[2]),
	) != 0 {return false}
	defer _ = sdl.SetTextureColorMod(texture, 255, 255, 255)
	if sdl.RenderCopyF(renderer, texture, nil, &destination) != 0 {return false}
	value := strings.to_string(search_text)
	text := frame_text(renderer, index, fonts[.Heading], value == "" ? "Search YouTube" : value)
	if text == nil {return false}
	caret, caret_ok := search_text_x(fonts[.Heading], value, search_editor.selection[0])
	anchor, anchor_ok := search_text_x(fonts[.Heading], value, search_editor.selection[1])
	width, height := text.width, text.height
	if !caret_ok || !anchor_ok {return false}
	if value == "" {caret, anchor = 0, 0}
	search_scroll = clamp(search_scroll, 0, max(0, f32(width) + SEARCH_CARET_WIDTH - rect.w))
	if caret < search_scroll {search_scroll = caret}
	if caret + SEARCH_CARET_WIDTH >
	   search_scroll + rect.w {search_scroll = caret + SEARCH_CARET_WIDTH - rect.w}
	visible: sdl.Rect
	clip_rect := pixel_bounds(rect)
	clip_copy := clip
	if !bool(sdl.IntersectRect(&clip_copy, &clip_rect, &visible)) {return true}
	if sdl.RenderSetClipRect(renderer, &visible) != 0 {return false}
	saved_clip := clip
	defer _ = sdl.RenderSetClipRect(renderer, &saved_clip)
	x, y := math.round(rect.x - search_scroll), rect.y + (rect.h - f32(height)) / 2
	if edit.has_selection(&search_editor) {
		selection := sdl.FRect{x + min(caret, anchor), rect.y, math.abs(caret - anchor), rect.h}
		if !set_color(renderer, COLOR_TRACK) ||
		   sdl.RenderFillRectF(renderer, &selection) != 0 {return false}
	}
	color := value == "" ? COLOR_MUTED : COLOR_TEXT
	if text.texture == nil {return false}
	_ = sdl.SetTextureColorMod(text.texture, u8(color[0]), u8(color[1]), u8(color[2]))
	_ = sdl.SetTextureAlphaMod(text.texture, u8(color[3]))
	text_destination := sdl.FRect{x, math.round(y), f32(text.width), f32(text.height)}
	if sdl.RenderCopyF(renderer, text.texture, nil, &text_destination) != 0 {return false}
	caret_rect := sdl.FRect {
		max(rect.x, math.round(x + caret - SEARCH_CARET_WIDTH / 2)),
		rect.y + (rect.h - f32(text_sizes[.Heading])) / 2,
		SEARCH_CARET_WIDTH,
		f32(text_sizes[.Heading]),
	}
	return set_color(renderer, COLOR_TEXT) && sdl.RenderFillRectF(renderer, &caret_rect) == 0
}

search_layout :: proc() {
	modal_scrim()
	if clay.UI(clay.ID("search"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(min(scaled(960), view_width - scaled(64)))},
			padding = clay.PaddingAll(spacing(4)),
		},
		userData = &POPUP_SHADOW,
		backgroundColor = COLOR_TEXT,
		cornerRadius = clay.CornerRadiusAll(scaled(8)),
		floating = {
			attachTo = .Root,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			zIndex = 11,
		},
	},
	) {
		if clay.UI(clay.ID("search-input"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				padding = padding(8, 8, 4, 4),
				childGap = spacing(12),
				childAlignment = {y = .Center},
			},
			backgroundColor = COLOR_SURFACE,
			cornerRadius = clay.CornerRadiusAll(scaled(4)),
		},
		) {
			if clay.UI(clay.ID("search-icon"))(
			{
				layout = {
					sizing = {
						width = clay.SizingFixed(scaled(32)),
						height = clay.SizingFixed(scaled(32)),
					},
				},
			},
			) {}
			if clay.UI(clay.ID("search-text"))(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFixed(f32(ttf.FontHeight(fonts[.Heading]))),
					},
				},
				custom = {customData = &search_editor},
			},
			) {}
		}
	}
}
