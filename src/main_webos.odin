#+build linux:default arm32
package main

import clay "../vendor/clay"
import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:sys/posix"
import sdl "vendor:sdl2"

APP_ID :: #config(APP_ID, "org.hyperpuncher.leantube")
APP_VERSION :: #config(APP_VERSION, "dev")
APP_TEMP_PREFIX :: "/tmp/leantube"
registered: bool
interrupted: i32
stop_signal :: proc "c" (_: posix.Signal) {sync.atomic_store(&interrupted, 1)}

register_application :: proc() -> bool {
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	token: c.ulong
	return LSCall(
		bus,
		"luna://com.webos.applicationManager/registerNativeApp",
		"{\"id\":\"" + APP_ID + "\",\"subscribe\":true}",
		reply,
		nil,
		&token,
		&error,
	)
}

reply :: proc "c" (_: rawptr, message: rawptr, _: rawptr) -> bool {
	context = runtime.default_context()
	value, error := json.parse(string(LSMessageGetPayload(message)))
	if error != .None {return true}
	defer json.destroy_value(value)
	root, ok := value.(json.Object)
	if !ok {return true}
	if success, found := root["returnValue"].(json.Boolean); found {
		if !bool(success) {return true}
		registered = true
	}
	switch lifecycle_event(root) {
	case "close":
		running = false
	case "relaunch":
		raise_window()
		queue_control(launch_parameters(root))
	}
	return true
}

main :: proc() {
	benchmark_reader_entry()
	setup_logging()
	_ = os.remove(CONTROL_STATE)
	if len(os.args) > 1 {
		if value, err := json.parse(os.args[1]); err == .None {
			if root, ok := value.(json.Object); ok {queue_control(launch_parameters(root))}
			json.destroy_value(value)
		}
	}
	action := posix.sigaction_t {
		sa_handler = stop_signal,
	}
	if posix.sigaction(.SIGTERM, &action, nil) != .OK ||
	   posix.sigaction(.SIGINT, &action, nil) != .OK {return}
	capture_action := posix.sigaction_t{sa_handler = capture_ui_signal}
	if posix.sigaction(.SIGUSR1, &capture_action, nil) != .OK {
		fmt.eprintln("UI capture signal unavailable")
	}
	if !start_bus(APP_ID) {os.exit(1)}
	window: ^sdl.Window
	renderer: ^sdl.Renderer
	clay_memory: []u8
	defer {
		if search_editing {finish_search_input(window)}
		stop_playback()
		write_control_state(true)
		close_login_screen()
		stop_network()
		close_search()
		clear_browse_history()
		delete(browse_id); delete(browse_params); delete(browse_filter)
		clear_catalog()
		close_fade()
		close_icons()
		close_tv_cursor()
		close_text()
		if renderer != nil {sdl.DestroyRenderer(renderer)}
		close_window()
		close_bus()
		if window != nil {sdl.DestroyWindow(window)}
		sdl.Quit()
		delete(clay_memory)
		fmt.println("native cleanup completed")
	}
	path, path_error := os.get_executable_path(context.allocator)
	if path_error != nil {return}
	defer delete(path)
	app_directory = filepath.dir(path)
	// Use the firmware's EGL adapter, never a copied driver-specific binary.
	legacy_egl := "/usr/lib/libwayland-egl.so.0"
	egl_alias := fmt.aprintf("%s/lib/libwayland-egl.so.1", app_directory)
	defer delete(egl_alias)
	if os.exists(legacy_egl) && !os.exists(egl_alias) {
		if error := os.symlink(legacy_egl, egl_alias); error != nil {
			fmt.eprintln("EGL adapter alias failed:", error)
			return
		}
	}
	if !register_application() {return}
	start := sdl.GetTicks64()
	for !registered && sdl.GetTicks64() - start < 3000 {poll_services(); sdl.Delay(10)}
	if !registered {fmt.eprintln("registration failed"); return}
	if !init_tv_video() {fmt.eprintln("SDL init failed:", sdl.GetError()); return}
	window = create_window()
	if window == nil {fmt.eprintln("window failed:", sdl.GetError()); return}
	renderer = sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	if renderer == nil {fmt.eprintln("renderer failed:", sdl.GetError()); return}
	if !attach_sdl_window(window) {fmt.eprintln("LG window role is unavailable"); return}
	if !tv_clay_abi(
		u32(size_of(clay.RenderCommand)),
		u32(size_of(clay.ElementDeclaration)),
		u32(size_of(clay.ErrorData)),
	) {fmt.eprintln("Clay ABI mismatch"); return}
	clay_memory = open_clay()
	if sdl.SetRenderDrawBlendMode(renderer, sdl.BlendMode.BLEND) != 0 {return}
	if !open_tv_cursor() {fmt.eprintln("cursor failed:", sdl.GetError())}
	if !open_text(renderer) {fmt.eprintln("UI assets failed:", sdl.GetError()); return}
	init_player()
	if start_network() {
		if pending_control.action == .Open {apply_control(window)} else {
			activate_navigation(signed_in ? .Subscriptions : .Home)
		}
	} else {
		show_notice("Network unavailable")
	}
	if !render(renderer) {fmt.eprintln("frame failed:", sdl.GetError()); return}
	log_video_surface(window)
	fmt.println("video grid presented")
	previous_frame := sdl.GetTicks64()
	for running && !window_closing && sync.atomic_load(&interrupted) == 0 {
		poll_services()
		if return_to_grid {stop_playback()}
		apply_control(window)
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, loading_active() ? 0 : 20) {
			// SDL documents draining the queue after the blocking wait.
			for {
				wheel += handle_event(renderer, event)
				if !sdl.PollEvent(&event) {break}
			}
		}
		poll_network(renderer)
		poll_player()
		poll_card_press(sdl.GetTicks64())
		poll_login_tick()
		apply_pending_seek(sdl.GetTicks64())
		auto_skip_sponsor()
		write_control_state()
		expire_player_controls()
		now := sdl.GetTicks64()
		expire_toast(now)
		frame_dt := f32(min(now - previous_frame, 50)) / 1000
		previous_frame = now
		if !window_visible {running = false}
		before_present: proc(^sdl.Renderer)
		if sync.atomic_exchange(&capture_ui_requested, 0) != 0 && browsing && !login_screen {
			before_present = save_ui_frame
		}
		if dirty || loading_active() || before_present != nil {
			if !render(renderer, wheel, frame_dt, before_present) {break}
			dirty = false
		}
	}
	fmt.println("player stopping")
}
