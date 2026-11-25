package main

import "./model"
import "core:strings"
import sdl "vendor:sdl2"

key :: proc(code: sdl.Keycode, window: ^sdl.Window = nil, mods: sdl.Keymod = {}) {
	if sponsor_menu {sponsor_menu_key(code); return}
	if settings_menu {settings_key(code); return}
	if autoplay_deadline != 0 {autoplay_key(code); return}
	if quality_menu {quality_menu_key(code); return}
	if card_menu {card_menu_key(code); return}
	if account_menu {
		add := len(auth_accounts) < MAX_ACCOUNTS
		last := len(auth_accounts) + int(add)
		#partial switch code {
		case sdl.Keycode.ESCAPE, sdl.Keycode.AC_BACK:
			account_menu = false
		case sdl.Keycode.UP:
			account_menu_selected = max(0, account_menu_selected - 1)
		case sdl.Keycode.DOWN:
			account_menu_selected = min(last, account_menu_selected + 1)
		case sdl.Keycode.RETURN, sdl.Keycode.KP_ENTER, sdl.Keycode.SPACE:
			if account_menu_selected < len(auth_accounts) {
				activate_account(account_menu_selected)
			} else if add && account_menu_selected == len(auth_accounts) {
				account_menu = false
				start_login(true)
			} else {
				sign_out()
			}
		}
		dirty = true
		return
	}
	if login_screen {
		#partial switch code {
		case sdl.Keycode.ESCAPE, sdl.Keycode.AC_BACK:
			leave_login(window)
		case sdl.Keycode.UP, sdl.Keycode.DOWN, sdl.Keycode.TAB:
			if login_failed() {login_retry_selected = !login_retry_selected}
		case sdl.Keycode.RETURN, sdl.Keycode.KP_ENTER, sdl.Keycode.SPACE:
			if login_retry_selected {retry_login()} else {leave_login(window)}
		}
		dirty = true
		return
	}
	if browsing && !search_editing {
		if (code == sdl.Keycode.ESCAPE || code == sdl.Keycode.AC_BACK) && browse_back() {return}
		if !rail_focus && channel_key(code) {return}
		if navigation_key(code, window) {return}
	}
	if browsing && search_key(code, window, mods) {return}
	if browsing {
		library_focus_pending = true
		#partial switch code {
		case sdl.Keycode.ESCAPE, sdl.Keycode.AC_BACK:
			if rail_active == .Playlists && strings.has_prefix(browse_id, "VL") {
				start_browse(NAV_ITEMS[.Playlists].browse_id)
			}
		case sdl.Keycode.RETURN, sdl.Keycode.SPACE, sdl.Keycode.KP_ENTER:
			open_selected()
		case sdl.Keycode.LEFT:
			selected = model.grid_move(selected, len(catalog.videos), -1, 0, grid_columns)
		case sdl.Keycode.RIGHT:
			pagination_failed = false
			selected = model.grid_move(selected, len(catalog.videos), 1, 0, grid_columns)
		case sdl.Keycode.UP:
			selected = model.grid_move(selected, len(catalog.videos), 0, -1, grid_columns)
		case sdl.Keycode.DOWN:
			pagination_failed = false
			selected = model.grid_move(selected, len(catalog.videos), 0, 1, grid_columns)
		}
	} else {
		show_player_controls()
		#partial switch code {
		case sdl.Keycode.ESCAPE, sdl.Keycode.AC_BACK:
			return_to_grid = true
		case sdl.Keycode.RETURN, sdl.Keycode.SPACE, sdl.Keycode.KP_ENTER:
			_ = player_pause(!paused)
		case sdl.Keycode.AUDIOPLAY:
			_ = player_pause(false)
		case sdl.Keycode.PAUSE:
			_ = player_pause(true)
		case sdl.Keycode.LEFT, sdl.Keycode.RIGHT:
			queue_seek(code == sdl.Keycode.RIGHT ? 10000 : -10000)
		}
	}
	dirty = true
}
