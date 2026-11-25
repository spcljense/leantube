package main

import clay "../vendor/clay"
import sb "./sponsorblock"

COLOR_BACKGROUND :: clay.Color{0, 0, 0, 255}
COLOR_SURFACE :: clay.Color{28, 28, 28, 255}
COLOR_HOVER :: clay.Color{48, 48, 48, 255}
COLOR_PANEL :: clay.Color{16, 16, 16, 192}
COLOR_BADGE :: clay.Color{0, 0, 0, 220}
COLOR_TRACK :: clay.Color{64, 64, 64, 255}
COLOR_BUFFERED :: clay.Color{144, 144, 144, 255}
SPONSOR_COLORS := [sb.Category]clay.Color {
	.Sponsor        = {102, 148, 111, 255},
	.Intro          = {105, 145, 169, 255},
	.Outro          = {139, 123, 169, 255},
	.Self_Promotion = {163, 137, 94, 255},
	.Interaction    = {159, 114, 128, 255},
	.Preview        = {101, 149, 147, 255},
	.Filler         = {147, 145, 104, 255},
	.Music_Offtopic = {163, 119, 101, 255},
}
COLOR_TEXT :: clay.Color{240, 240, 240, 255}
COLOR_MUTED :: clay.Color{176, 176, 176, 255}
// Rectangle userData can borrow this color for the shared popup shadow.
POPUP_SHADOW := clay.Color{0, 0, 0, 96}
// Use the warm accent only on focus outlines and progress.
COLOR_ACCENT :: clay.Color{250, 88, 36, 255}

// Darken the page behind a centered popup. Popups use zIndex 11.
modal_scrim :: proc() {
	if clay.UI()(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(view_width),
				height = clay.SizingFixed(view_height),
			},
		},
		backgroundColor = {0, 0, 0, 160},
		floating = {attachTo = .Root, zIndex = 10},
	},
	) {}
}
