package main

import sdl "vendor:sdl2"

input_key :: proc(keysym: sdl.Keysym) -> sdl.Keycode {
	// Keep navigation usable even if the compositor's layout leaves these
	// physical keys without an SDL key symbol.
	#partial switch keysym.scancode {
	case .AC_BACK:   return .AC_BACK
	case .AUDIOPLAY: return .AUDIOPLAY
	case .PAUSE:     return .PAUSE
	case .UP:       return .UP
	case .DOWN:     return .DOWN
	case .LEFT:     return .LEFT
	case .RIGHT:    return .RIGHT
	case .RETURN:   return .RETURN
	case .KP_ENTER: return .KP_ENTER
	}
	return keysym.sym
}
