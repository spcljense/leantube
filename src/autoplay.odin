package main

import clay "../vendor/clay"
import sdl "vendor:sdl2"

AUTOPLAY_DELAY_MS :: 5000
autoplay_deadline: u64
autoplay_index: int
autoplay_seconds: int
autoplay_cancel_focused: bool

offer_next_video :: proc() {
	for index in selected + 1 ..< len(catalog.videos) {
		video := catalog.videos[index]
		if video.id == "" || video.browse_id != "" {continue}
		autoplay_index = index
		autoplay_deadline = sdl.GetTicks64() + AUTOPLAY_DELAY_MS
		autoplay_seconds = AUTOPLAY_DELAY_MS / 1000
		autoplay_cancel_focused = false
		quality_menu = false
		dirty = true
		return
	}
	return_to_grid = true
}

play_next_video :: proc() {
	next := autoplay_index
	stop_playback()
	selected = next
	start_video()
}

tick_autoplay :: proc(now: u64) {
	if autoplay_deadline == 0 || return_to_grid {return}
	if now >= autoplay_deadline {play_next_video(); return}
	seconds := int((autoplay_deadline - now + 999) / 1000)
	if seconds != autoplay_seconds {autoplay_seconds = seconds; dirty = true}
}

autoplay_key :: proc(code: sdl.Keycode) {
	#partial switch code {
	case .ESCAPE, .AC_BACK:
		return_to_grid = true
	case .LEFT, .UP:
		autoplay_cancel_focused = true
	case .RIGHT, .DOWN:
		autoplay_cancel_focused = false
	case .RETURN, .KP_ENTER, .SPACE:
		if autoplay_cancel_focused {return_to_grid = true} else {play_next_video()}
	}
	dirty = true
}

autoplay_pointer :: proc(activate: bool) {
	if clay.PointerOver(clay.ID("autoplay-cancel")) {
		autoplay_cancel_focused = true
		if activate {return_to_grid = true}
	} else if clay.PointerOver(clay.ID("autoplay-play")) {
		autoplay_cancel_focused = false
		if activate {play_next_video()}
	}
}

autoplay_layout :: proc() {
	countdown := [?]string {
		"Up next",
		"Up next in 1 second",
		"Up next in 2 seconds",
		"Up next in 3 seconds",
		"Up next in 4 seconds",
		"Up next in 5 seconds",
	}
	modal_scrim()
	if clay.UI(clay.ID("autoplay"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(min(scaled(640), view_width - scaled(64)))},
			padding = clay.PaddingAll(spacing(24)),
			layoutDirection = .TopToBottom,
			childGap = spacing(16),
		},
		userData = &POPUP_SHADOW,
		backgroundColor = COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(24)),
		floating = {
			attachTo = .Root,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			zIndex = 11,
		},
	},
	) {
		label(countdown[autoplay_seconds], .Small, COLOR_MUTED)
		label(catalog.videos[autoplay_index].title, .Heading, wrap = .Words)
		if clay.UI()({layout = {childGap = spacing(12)}}) {
			autoplay_button("autoplay-cancel", "Cancel", autoplay_cancel_focused)
			autoplay_button("autoplay-play", "Play now", !autoplay_cancel_focused)
		}
	}
}

autoplay_button :: proc(id, text: string, focused: bool) {
	if clay.UI(clay.ID(id))(
	{
		layout = {padding = padding(18, 18, 12, 12)},
		backgroundColor = focused ? COLOR_TEXT : COLOR_HOVER,
		cornerRadius = clay.CornerRadiusAll(scaled(10)),
	},
	) {label(text, .Small, focused ? COLOR_BACKGROUND : COLOR_TEXT)}
}
