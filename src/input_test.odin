#+test
package main

import "core:testing"
import sdl "vendor:sdl2"

@(test)
remote_back_uses_the_same_action_as_standard_back :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(412, sdl.Keycode.UNKNOWN), sdl.Keycode(sdl.Keycode.AC_BACK))
	testing.expect_value(t, input_key(412, sdl.Keycode(0x200003)), sdl.Keycode(sdl.Keycode.AC_BACK))
	// A held back key must not dismiss successive screens through repeats.
	saved_menu := account_menu
	defer {account_menu = saved_menu}
	account_menu = true
	event: sdl.Event
	event.type = .KEYDOWN
	event.key.repeat = 1
	handle_event(nil, event)
	testing.expect(t, account_menu)
}

@(test)
remote_play_and_pause_keep_their_own_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(207, sdl.Keycode.UNKNOWN), sdl.Keycode(MEDIA_PLAY_KEY))
	testing.expect_value(t, input_key(119, sdl.Keycode.UNKNOWN), sdl.Keycode(MEDIA_PAUSE_KEY))
}
