package main

import clay "../vendor/clay"
import ttf "vendor:sdl2/ttf"

UHD_BADGE_WIDTH :: 44
UHD_BADGE_GAP :: 8

mark_video_4k :: proc(index: int) {
	if index < 0 || index >= len(catalog.videos) || catalog.videos[index].has_4k {return}
	catalog.videos[index].has_4k = true
	labels_release()
	dirty = true
}

uhd_badge :: proc(id: clay.ElementId, title_style: Text_Style, focused := false) {
	if clay.UI()(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(scaled(UHD_BADGE_WIDTH)),
				height = clay.SizingFixed(f32(ttf.FontHeight(fonts[title_style]))),
			},
			childAlignment = {x = .Center, y = .Center},
		},
	},
	) {
		if clay.UI(id)(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(28))},
				childAlignment = {x = .Center, y = .Center},
			},
			backgroundColor = focused ? COLOR_HOVER : COLOR_SURFACE,
			cornerRadius = clay.CornerRadiusAll(scaled(4)),
		},
		) {label("4K", .Caption)}
	}
}
