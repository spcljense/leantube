#+build linux:default arm32
package main

import "core:c"
import ttf "vendor:sdl2/ttf"

// Installed TV fonts can fill in missing glyphs after the bundled faces.
// LG Display Regular covers broad scripts. LGIndia supplies U+2024 instead.
LG_SMART_UI_REGULAR :: cstring("/usr/share/fonts/LG_Smart_UI-Regular.ttf")
FALLBACK_FONT_PATHS :: [?]cstring {
	"/usr/share/fonts/NotoEmoji-Regular.ttf",
	LG_SMART_UI_REGULAR,
	"/usr/share/fonts/LG_Display-Regular.ttf",
	"/usr/share/fonts/LG_Display_IN.ttf",
}

open_platform_fallback :: proc(path: cstring, size: c.int, style: Text_Style) -> ^ttf.Font {
	if style in TITLE_STYLES && string(path) == string(LG_SMART_UI_REGULAR) {
		font := ttf.OpenFont("/usr/share/fonts/LG_Smart_UI-SemiBold.ttf", size)
		if font != nil {return font}
	}
	return ttf.OpenFont(path, size)
}
