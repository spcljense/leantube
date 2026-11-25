#+test
package main

import "core:testing"
import sdl "vendor:sdl2"

@(test)
remote_back_uses_the_same_action_as_standard_back :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key({scancode = .AC_BACK}), sdl.Keycode.AC_BACK)
	// A held back key must not dismiss successive screens through repeats.
	saved_menu := account_menu
	defer {account_menu = saved_menu}
	account_menu = true
	event: sdl.Event
	event.type = .KEYDOWN
	event.key.keysym.scancode = .AC_BACK
	event.key.repeat = 1
	handle_event(nil, event)
	testing.expect(t, account_menu)
}

@(test)
remote_play_and_pause_keep_their_own_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key({scancode = .AUDIOPLAY}), sdl.Keycode.AUDIOPLAY)
	testing.expect_value(t, input_key({scancode = .PAUSE}), sdl.Keycode.PAUSE)
}

@(test)
remote_navigation_works_without_layout_key_symbols :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key({scancode = .UP}), sdl.Keycode.UP)
	testing.expect_value(t, input_key({scancode = .DOWN}), sdl.Keycode.DOWN)
	testing.expect_value(t, input_key({scancode = .LEFT}), sdl.Keycode.LEFT)
	testing.expect_value(t, input_key({scancode = .RIGHT}), sdl.Keycode.RIGHT)
	testing.expect_value(t, input_key({scancode = .RETURN}), sdl.Keycode.RETURN)
	testing.expect_value(t, input_key({scancode = .KP_ENTER}), sdl.Keycode.KP_ENTER)
}
