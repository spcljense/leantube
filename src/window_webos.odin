#+build linux:default arm32
package main

import "base:runtime"
import "core:c"
import "core:fmt"
import sdl "vendor:sdl2"

init_tv_video :: proc() -> bool {
	_ = sdl.SetHint(sdl.HINT_VIDEODRIVER, "wayland")
	_ = sdl.SetHint(sdl.HINT_RENDER_DRIVER, "opengles2")
	_ = sdl.SetHint(sdl.HINT_VIDEO_EGL_ALLOW_TRANSPARENCY, "1")
	_ = sdl.SetHint("SDL_LEANTUBE_WEBOS", "1")
	return sdl.Init({.VIDEO}) == 0
}

create_window :: proc() -> ^sdl.Window {
	_ = sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.ES))
	_ = sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 2)
	_ = sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 0)
	_ = sdl.GL_SetAttribute(.RED_SIZE, 8)
	_ = sdl.GL_SetAttribute(.GREEN_SIZE, 8)
	_ = sdl.GL_SetAttribute(.BLUE_SIZE, 8)
	_ = sdl.GL_SetAttribute(.ALPHA_SIZE, 8)
	_ = sdl.GL_SetAttribute(.DEPTH_SIZE, 0)
	bounds: sdl.Rect
	if sdl.GetDisplayBounds(0, &bounds) != 0 {return nil}
	return sdl.CreateWindow(
		"LeanTube",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		bounds.w,
		bounds.h,
		{.OPENGL, .BORDERLESS, .SHOWN},
	)
}

// Use the drawable supplied by the compositor, including on TVs that
// expose a 1080p UI surface on a 4K panel.
window_ui_scale :: proc(_: ^sdl.Window, width, height: c.int) -> f32 {
	scale := min(f32(width) / 1920, f32(height) / 1080)
	return max(0.5, scale)
}

log_video_surface :: proc(window: ^sdl.Window) {
	width, height: c.int
	sdl.GetWindowSize(window, &width, &height)
	channels: [4]c.int
	for attr, i in ([4]sdl.GLattr{.RED_SIZE, .GREEN_SIZE, .BLUE_SIZE, .ALPHA_SIZE}) {
		_ = sdl.GL_GetAttribute(attr, &channels[i])
	}
	fmt.printf(
		"UI surface window=%dx%d drawable=%dx%d scale=%.2f RGBA=%d/%d/%d/%d\n",
		width, height, i32(view_width), i32(view_height), ui_scale,
		channels[0], channels[1], channels[2], channels[3],
	)
}

attach_sdl_window :: proc(window: ^sdl.Window) -> bool {
	wm: sdl.SysWMinfo
	sdl.VERSION(&wm.version)
	if !sdl.GetWindowWMInfo(window, &wm) || wm.subsystem != .WAYLAND {
		fmt.eprintln("Wayland window info failed:", sdl.GetError())
		return false
	}
	return attach_window(APP_ID, wm.info.wl.display, wm.info.wl.surface)
}

WL_MINIMIZED :: 1
WL_FULLSCREEN :: 3
window_display, window_surface: rawptr
window_registry, window_shell, window_role_shell: rawptr
window_shell_surface, window_role_surface: rawptr
window_closing: bool
window_visible := true

registry_listener := WL_Registry_Listener{registry_add, registry_remove}
role_listener := WL_Shell_Listener{role_ping, role_configure, role_popup_done}
shell_listener := WL_Webos_Listener {
	window_state_changed,
	window_position_changed,
	window_close_requested,
	window_exposed,
	window_state_changing,
}

registry_add :: proc "c" (data, registry: rawptr, name: u32, interface: cstring, version: u32) {
	context = runtime.default_context()
	switch string(interface) {
	case "wl_shell":
		window_role_shell = wl_registry_bind(registry, name, &wl_shell_interface, 1)
	case "wl_webos_shell":
		window_shell = wl_registry_bind(registry, name, &wl_webos_shell_interface, 1)
	case "text_model_factory":
		keyboard_factory = wl_registry_bind(registry, name, &text_model_factory_interface, 1)
	case "wl_seat":
		if keyboard_seat == nil {
			keyboard_seat = wl_registry_bind(registry, name, &wl_seat_interface, 1)
			wl_proxy_add_listener(keyboard_seat, &seat_listener, nil)
		}
	}
}
registry_remove :: proc "c" (data, registry: rawptr, name: u32) {}
role_ping :: proc "c" (data, surface: rawptr, serial: u32) {wl_shell_surface_pong(surface, serial)}
role_configure :: proc "c" (data, surface: rawptr, edges: u32, width, height: i32) {}
role_popup_done :: proc "c" (data, surface: rawptr) {}

window_state_changed :: proc "c" (data, surface: rawptr, state: u32) {
	context = runtime.default_context()
	window_visible = state != WL_MINIMIZED
	fmt.println("window state:", state)
}
window_position_changed :: proc "c" (data, surface: rawptr, x, y: i32) {}
window_close_requested :: proc "c" (data, surface: rawptr) {window_closing = true}
window_exposed :: proc "c" (data, surface, rectangles: rawptr) {}
window_state_changing :: proc "c" (data, surface: rawptr, state: u32) {}

attach_window :: proc(app_id: cstring, display, surface: rawptr) -> bool {
	window_display, window_surface = display, surface
	if display == nil || surface == nil {return false}
	window_registry = wl_display_get_registry(display)
	wl_proxy_add_listener(window_registry, &registry_listener, nil)
	if wl_display_roundtrip(display) < 0 ||
	   window_shell == nil ||
	   window_role_shell == nil {return false}

	// Match SDL-webOS: wl_shell supplies the role; the LG shell adds properties.
	window_role_surface = wl_shell_get_shell_surface(window_role_shell, surface)
	if window_role_surface == nil {return false}
	wl_proxy_add_listener(window_role_surface, &role_listener, nil)
	wl_shell_surface_set_class(window_role_surface, app_id)
	wl_shell_surface_set_toplevel(window_role_surface)
	window_shell_surface = wl_webos_shell_get_shell_surface(window_shell, surface)
	if window_shell_surface == nil {return false}
	wl_proxy_add_listener(window_shell_surface, &shell_listener, nil)
	wl_webos_shell_surface_set_property(window_shell_surface, "appId", app_id)
	wl_webos_shell_surface_set_property(
		window_shell_surface,
		"_WEBOS_ACCESS_POLICY_KEYS_BACK",
		"true",
	)
	// Leave KEYS_EXIT unclaimed: webOS handles long-back exit.
	wl_webos_shell_surface_set_state(window_shell_surface, WL_FULLSCREEN)
	return wl_display_roundtrip(display) >= 0
}

raise_window :: proc() {
	if window_shell_surface == nil {return}
	wl_webos_shell_surface_set_state(window_shell_surface, WL_FULLSCREEN)
	wl_display_flush(window_display)
}

close_window :: proc() {
	close_keyboard()
	proxies := [5]rawptr {
		window_shell_surface,
		window_role_surface,
		window_role_shell,
		window_shell,
		window_registry,
	}
	for proxy in proxies {
		if proxy != nil {wl_proxy_destroy(proxy)}
	}
	window_shell_surface, window_role_surface = nil, nil
	window_role_shell, window_shell, window_registry = nil, nil, nil
	window_display, window_surface = nil, nil
}
