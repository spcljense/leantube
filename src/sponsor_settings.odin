package main

import clay "../vendor/clay"
import sb "./sponsorblock"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl2"

sponsor_categories: sb.Categories = sb.DEFAULT_CATEGORIES
sponsor_menu: bool
sponsor_menu_selected: sb.Category

SPONSOR_CATEGORY_LABELS := [sb.Category]string {
	.Sponsor        = "Sponsors",
	.Intro          = "Intros",
	.Outro          = "Outros",
	.Self_Promotion = "Self-promotion",
	.Interaction    = "Like and subscribe reminders",
	.Preview        = "Previews and recaps",
	.Filler         = "Filler",
	.Music_Offtopic = "Non-music sections",
}

load_sponsor_settings :: proc() {
	sponsor_categories = sb.DEFAULT_CATEGORIES
	path := fmt.aprintf("%s/.sponsorblock", app_directory)
	defer delete(path)
	data, error := os.read_entire_file_from_path(path, context.allocator)
	if error != nil {return}
	defer delete(data)
	value := strings.trim_space(string(data))
	count: int
	mask, ok := strconv.parse_uint(value, 10, &count)
	if ok && count == len(value) && mask <= uint(max(u8)) {
		sponsor_categories = transmute(sb.Categories)u8(mask)
	}
}

save_sponsor_settings :: proc(categories: sb.Categories) -> bool {
	data := fmt.aprintf("%d\n", transmute(u8)categories)
	defer delete(data)
	return save_app_preference(".sponsorblock", data)
}

save_app_preference :: proc(filename, data: string) -> bool {
	path := fmt.aprintf("%s/%s", app_directory, filename)
	defer delete(path)
	file, open_error := os.create_temp_file(app_directory, ".settings-*")
	if open_error != nil {return false}
	temporary := strings.clone(os.name(file))
	defer delete(temporary)
	defer os.remove(temporary)
	written, write_error := os.write(file, transmute([]byte)data)
	close_error := os.close(file)
	if write_error != nil || written != len(data) || close_error != nil {return false}
	return os.rename(temporary, path) == nil
}

toggle_sponsor_category :: proc(category: sb.Category) {
	updated := sponsor_categories ~ sb.Categories{category}
	if save_sponsor_settings(updated) {
		sponsor_categories = updated
	} else {
		show_notice("Could not save SponsorBlock settings")
	}
}

sponsor_menu_key :: proc(code: sdl.Keycode) {
	#partial switch code {
	case .ESCAPE, .AC_BACK:
		sponsor_menu = false
	case .UP:
		sponsor_menu_selected = sb.Category(max(0, int(sponsor_menu_selected) - 1))
	case .DOWN:
		sponsor_menu_selected = sb.Category(
			min(int(sb.Category.Music_Offtopic), int(sponsor_menu_selected) + 1),
		)
	case .RETURN, .KP_ENTER, .SPACE:
		toggle_sponsor_category(sponsor_menu_selected)
	}
	dirty = true
}

sponsor_menu_pointer :: proc(activate: bool) {
	for category in sb.Category {
		if clay.PointerOver(clay.ID("sponsor-category", u32(category))) {
			sponsor_menu_selected = category
			if activate {toggle_sponsor_category(category)}
			return
		}
	}
	if activate && !clay.PointerOver(clay.ID("sponsor-menu")) {sponsor_menu = false}
}

sponsor_menu_layout :: proc() {
	modal_scrim()
	if clay.UI(clay.ID("sponsor-menu"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(min(scaled(640), view_width - scaled(64)))},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(spacing(24)),
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
		label("SponsorBlock", .Heading)
		label("Automatically skip", .Small, COLOR_MUTED)
		for category in sb.Category {
			focused := sponsor_menu_selected == category
			enabled := category in sponsor_categories
			if clay.UI(clay.ID("sponsor-category", u32(category)))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(50))},
					childAlignment = {y = .Center},
					childGap = spacing(12),
					padding = padding(12, 12, 0, 0),
				},
				backgroundColor = focused ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {
				swatch := scaled(12)
				if clay.UI()(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(swatch),
							height = clay.SizingFixed(swatch),
						},
					},
					backgroundColor = SPONSOR_COLORS[category],
					cornerRadius = clay.CornerRadiusAll(swatch / 2),
				},
				) {}
				label(SPONSOR_CATEGORY_LABELS[category], .Small)
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
				label(enabled ? "On" : "Off", .Small, enabled ? COLOR_TEXT : COLOR_MUTED)
			}
		}
	}
}
