package main

import clay "../vendor/clay"
import sdl "vendor:sdl2"

handle_event :: proc(renderer: ^sdl.Renderer, event: sdl.Event) -> (wheel: f32) {
	#partial switch event.type {
	case .QUIT:
		running = false
	case .WINDOWEVENT:
		dirty = true
		if event.window.event == .FOCUS_LOST {card_press.active = false}
	case .KEYDOWN:
		code := input_key(event.key.keysym)
		ok := code == sdl.Keycode.RETURN || code == sdl.Keycode.KP_ENTER || code == sdl.Keycode.SPACE
		back := code == sdl.Keycode.AC_BACK || code == sdl.Keycode.ESCAPE
		if (ok || back) && event.key.repeat != 0 {return}
		clay.SetPointerState({-1, -1}, false)
		if ok && can_press_card() {
			if !card_press.active {begin_card_press(false, sdl.GetTicks64())}
		} else {
			card_press.active = false
			key(code, sdl.RenderGetWindow(renderer), event.key.keysym.mod)
		}
	case .KEYUP:
		code := input_key(event.key.keysym)
		if code == sdl.Keycode.RETURN || code == sdl.Keycode.KP_ENTER || code == sdl.Keycode.SPACE {
			finish_card_press(false, sdl.GetTicks64())
		}
	case .TEXTINPUT:
		if browsing {
			text := event.text.text
			append_search_text(string(cstring(&text[0])))
		}
	case .MOUSEWHEEL:
		card_press.active = false
		if browsing && !sponsor_menu && !settings_menu {
			controls_pointer(renderer, f32(event.wheel.mouseX), f32(event.wheel.mouseY), false, false)
			wheel = event.wheel.preciseY
			if wheel == 0 {wheel = f32(event.wheel.y)}
			if event.wheel.direction != 0 {wheel = -wheel}
			if wheel < 0 {pagination_failed = false}
		}
	case .MOUSEMOTION:
		controls_pointer(
			renderer,
			f32(event.motion.x),
			f32(event.motion.y),
			event.motion.state & sdl.BUTTON_LMASK != 0,
			false,
		)
	case .MOUSEBUTTONDOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			controls_pointer(renderer, f32(event.button.x), f32(event.button.y), true, true)
		}
	case .MOUSEBUTTONUP:
		if event.button.button == sdl.BUTTON_LEFT {
			controls_pointer(renderer, f32(event.button.x), f32(event.button.y), false, false)
			finish_card_press(true, sdl.GetTicks64())
		}
	}
	return
}
