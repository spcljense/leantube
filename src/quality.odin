package main

import clay "../vendor/clay"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"

Quality_Option :: struct {
	height: int,
	label:  string,
}

player_quality_options: [dynamic]Quality_Option
player_quality_height: int
quality_change_pending: bool
quality_menu: bool
quality_cursor: int

clear_player_quality :: proc() {
	for option in player_quality_options {delete(option.label)}
	delete(player_quality_options)
	player_quality_options = nil
	player_quality_height = 0
	quality_change_pending, quality_menu = false, false
}

apply_stream_quality :: proc(result: ^Network_Result) {
	clear_player_quality()
	stream_width, stream_height = result.stream.width, result.stream.height
	if result.stream.has_4k {mark_video_4k(selected)}
	player_quality_height = result.quality_height
	if len(result.stream.heights) == 0 {return}
	auto_label :=
		auto_quality_max == 0 ? strings.clone("Auto (max)") : fmt.aprintf("Auto (%dp max)", auto_quality_max)
	append(&player_quality_options, Quality_Option{label = auto_label})
	for height in result.stream.heights {
		append(&player_quality_options, Quality_Option{height, fmt.aprintf("%dp", height)})
	}
}

open_quality_menu :: proc() {
	if !loaded || quality_change_pending || len(player_quality_options) < 2 {return}
	quality_menu = true
	quality_cursor = 0
	for option, index in player_quality_options {
		if option.height == player_quality_height {quality_cursor = index; break}
	}
	dirty = true
}

choose_quality :: proc(index: int) {
	quality_menu = false
	show_player_controls()
	height := player_quality_options[index].height
	if height == player_quality_height {return}
	if !submit_network(
		{
			kind = .Resolve,
			page = page,
			playback = playback,
			text = strings.clone(catalog.videos[selected].id),
			quality_height = height,
			quality_auto_max = auto_quality_max,
			quality_change = true,
		},
	) {
		show_notice("Could not change video quality")
		return
	}
	quality_change_pending = true
}

apply_quality_change :: proc(renderer: ^sdl.Renderer, result: ^Network_Result) {
	if !quality_change_pending || autoplay_deadline != 0 {return}
	quality_change_pending = false
	if result.error != .None {
		show_notice("Could not change video quality")
		return
	}
	position, was_paused, playback_rate := shown_position(), paused, rate
	segments := sponsor_segments
	sponsor_segments = nil
	stop_playback()
	sponsor_segments = segments
	playback += 1
	apply_stream_quality(result)
	load_video(result.stream, renderer, position, was_paused)
	rate = playback_rate
	show_player_controls()
	dirty = true
}

quality_menu_key :: proc(code: sdl.Keycode) {
	#partial switch code {
	case .ESCAPE, .AC_BACK:
		quality_menu = false
		show_player_controls()
	case .UP:
		quality_cursor = max(0, quality_cursor - 1)
	case .DOWN:
		quality_cursor = min(len(player_quality_options) - 1, quality_cursor + 1)
	case .RETURN, .KP_ENTER, .SPACE:
		choose_quality(quality_cursor)
	}
	dirty = true
}

quality_menu_pointer :: proc(activate: bool) {
	for _, index in player_quality_options {
		if clay.PointerOver(clay.ID("quality-option", u32(index))) {
			quality_cursor = index
			if activate {choose_quality(index)}
			return
		}
	}
	if activate && !clay.PointerOver(clay.ID("quality-menu")) {quality_menu = false}
}

quality_menu_layout :: proc() {
	modal_scrim()
	row_height := min(scaled(46), (view_height - scaled(140)) / f32(len(player_quality_options)))
	if clay.UI(clay.ID("quality-menu"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(min(scaled(400), view_width - scaled(64)))},
			padding = clay.PaddingAll(spacing(24)),
			layoutDirection = .TopToBottom,
			childGap = spacing(4),
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
		label("Video quality", .Heading)
		for option, index in player_quality_options {
			if clay.UI(clay.ID("quality-option", u32(index)))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(row_height)},
					padding = padding(12, 12, 0, 0),
					childAlignment = {y = .Center},
				},
				backgroundColor = quality_cursor == index ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {
				label(option.label, .Small)
				if option.height == player_quality_height {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
					label("Selected", .Small, COLOR_MUTED)
				}
			}
		}
	}
}
