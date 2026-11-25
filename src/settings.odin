package main

import clay "../vendor/clay"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl2"

feed_previews := true
feed_preview_audio := true
feed_preview_visible: bool
settings_menu: bool
settings_cursor: int
settings_quality_menu: bool
auto_quality_max: int

QUALITY_LIMITS := [?]Quality_Option {
	{0, "No limit"},
	{2160, "2160p (4K)"},
	{1440, "1440p"},
	{1080, "1080p"},
	{720, "720p"},
	{480, "480p"},
	{360, "360p"},
	{240, "240p"},
	{144, "144p"},
}
SETTINGS_OPTIONS := [?]string{"Feed previews", "Preview audio", "Auto maximum resolution"}
MAXIMUM_RESOLUTION_ROW :: len(SETTINGS_OPTIONS) - 1

load_preview_settings :: proc() {
	feed_previews, feed_preview_audio = true, true
	path := fmt.aprintf("%s/.feed-previews", app_directory)
	defer delete(path)
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {return}
	defer delete(data)
	value := strings.trim_space(string(data))
	if len(value) == 2 &&
	   (value[0] == '0' || value[0] == '1') &&
	   (value[1] == '0' || value[1] == '1') {
		feed_previews, feed_preview_audio = value[0] == '1', value[1] == '1'
	}
}

toggle_preview_setting :: proc(index: int) {
	previews, audio := feed_previews, feed_preview_audio
	if index == 0 {previews = !previews} else {audio = !audio}
	data := [2]u8{previews ? '1' : '0', audio ? '1' : '0'}
	if save_app_preference(".feed-previews", string(data[:])) {
		feed_previews, feed_preview_audio = previews, audio
	} else {show_notice("Could not save preview settings")}
	dirty = true
}

load_auto_quality_max :: proc() {
	auto_quality_max = 0
	path := fmt.aprintf("%s/.max-resolution", app_directory)
	defer delete(path)
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {return}
	defer delete(data)
	value, ok := strconv.parse_int(strings.trim_space(string(data)), 10)
	if !ok {return}
	for option in QUALITY_LIMITS {
		if option.height == value {auto_quality_max = value; return}
	}
}

quality_limit_index :: proc() -> int {
	for option, index in QUALITY_LIMITS {
		if option.height == auto_quality_max {return index}
	}
	return 0
}

settings_option_count :: proc() -> int {
	return settings_quality_menu ? len(QUALITY_LIMITS) : len(SETTINGS_OPTIONS)
}

settings_back :: proc() {
	if settings_quality_menu {
		settings_quality_menu = false
		settings_cursor = MAXIMUM_RESOLUTION_ROW
	} else {
		settings_menu = false
	}
}

choose_setting :: proc(index: int) {
	if settings_quality_menu {
		height := QUALITY_LIMITS[index].height
		data := fmt.aprintf("%d\n", height)
		defer delete(data)
		if save_app_preference(".max-resolution", data) {
			auto_quality_max = height
			settings_back()
		} else {show_notice("Could not save maximum resolution")}
	} else if index == MAXIMUM_RESOLUTION_ROW {
		settings_quality_menu = true
		settings_cursor = quality_limit_index()
	} else {
		toggle_preview_setting(index)
	}
}

settings_key :: proc(code: sdl.Keycode) {
	#partial switch code {
	case .ESCAPE, .AC_BACK:
		settings_back()
	case .UP:
		settings_cursor = max(0, settings_cursor - 1)
	case .DOWN:
		settings_cursor = min(settings_option_count() - 1, settings_cursor + 1)
	case .RETURN, .KP_ENTER, .SPACE:
		choose_setting(settings_cursor)
	}
	dirty = true
}

settings_pointer :: proc(activate: bool) {
	for index in 0 ..< settings_option_count() {
		if clay.PointerOver(clay.ID("settings-option", u32(index))) {
			settings_cursor = index
			if activate {choose_setting(index)}
			return
		}
	}
	if activate && !clay.PointerOver(clay.ID("settings-menu")) {settings_back()}
}

settings_layout :: proc() {
	modal_scrim()
	if clay.UI(clay.ID("settings-menu"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(min(scaled(560), view_width - scaled(64)))},
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
		label(settings_quality_menu ? "Auto maximum resolution" : "Settings", .Heading)
		limit := quality_limit_index()
		for index in 0 ..< settings_option_count() {
			name, value: string
			if settings_quality_menu {
				name = QUALITY_LIMITS[index].label
				if index == limit {value = "Selected"}
			} else {
				name = SETTINGS_OPTIONS[index]
				if index == MAXIMUM_RESOLUTION_ROW {
					value = QUALITY_LIMITS[limit].label
				} else {
					enabled := index == 0 ? feed_previews : feed_preview_audio
					value = enabled ? "On" : "Off"
				}
			}
			if clay.UI(clay.ID("settings-option", u32(index)))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(46))},
					padding = padding(12, 12, 0, 0),
					childAlignment = {y = .Center},
				},
				backgroundColor = settings_cursor == index ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {
				label(name, .Small)
				if value != "" {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
					label(value, .Small, COLOR_MUTED)
				}
			}
		}
	}
}
