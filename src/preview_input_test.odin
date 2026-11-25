#+build linux:default amd64, linux:default arm64
#+test
package main

import clay "../vendor/clay"
import "core:testing"
import sdl "vendor:sdl2"

@(test)
player_arrows_show_controls_and_speed_buttons_adjust_rate :: proc(t: ^testing.T) {
	saved_browsing, saved_card_menu, saved_account_menu, saved_login_screen :=
		browsing, card_menu, account_menu, login_screen
	saved_rate, saved_controls_until, saved_dirty, saved_card_press :=
		rate, controls_until, dirty, card_press
	defer {
		browsing, card_menu, account_menu, login_screen =
			saved_browsing, saved_card_menu, saved_account_menu, saved_login_screen
		rate, controls_until, dirty, card_press =
			saved_rate, saved_controls_until, saved_dirty, saved_card_press
	}
	browsing, card_menu, account_menu, login_screen = false, false, false, false
	rate, controls_until = 1, 0

	previous_context := clay.GetCurrentContext()
	memory := open_clay()
	defer {clay.SetCurrentContext(previous_context); delete(memory)}
	clay.SetLayoutDimensions({256, 128})
	clay.BeginLayout()
	control_button(SLOWER_BUTTON)
	control_button(FASTER_BUTTON)
	_ = clay.EndLayout(0)

	for code in ([2]sdl.Keycode{.UP, .DOWN}) {
		event: sdl.Event
		event.type = .KEYDOWN
		event.key.keysym.sym = code
		handle_event(nil, event)
		testing.expect_value(t, rate, 1.0)
	}
	testing.expect(t, controls_until > 0)

	expected_rates := [2]f64{0.75, 1.0}
	for button, i in control_buttons {
		element := clay.GetElementData(clay.ID(button.id))
		if !testing.expect(t, element.found) {return}
		box := element.boundingBox
		controls_pointer(nil, box.x + box.width / 2, box.y + box.height / 2, true, true)
		testing.expect_value(t, rate, expected_rates[i])
	}
}
