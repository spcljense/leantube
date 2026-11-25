#+build linux:default amd64, linux:default arm64
package main

import "core:c"
import ttf "vendor:sdl2/ttf"

FALLBACK_FONT_PATHS :: [?]cstring {
	#config(EMOJI_FONT_PATH, "/usr/share/fonts/noto/NotoEmoji-Regular.ttf"),
	#config(TEXT_FALLBACK_FONT_PATH, ""),
	// Host Noto Sans already covers the TV-specific punctuation fallback.
	#config(TEXT_PUNCT_FONT_PATH, ""),
}

open_platform_fallback :: proc(path: cstring, size: c.int, _: Text_Style) -> ^ttf.Font {
	return ttf.OpenFont(path, size)
}
