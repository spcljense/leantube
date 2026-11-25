#+build linux:default amd64, linux:default arm64
package main

import "./model"
import yt "./youtube"
import "core:fmt"
import sdl "vendor:sdl2"

DEV_SMOKE :: #config(DEV_SMOKE, false)

start_text_input :: proc(window: ^sdl.Window) -> bool {
	if window == nil {return true}
	sdl.StartTextInput()
	return true
}
stop_text_input :: proc(window: ^sdl.Window) {if window != nil {sdl.StopTextInput()}}
update_text_input :: proc() {}

// The host has no LG media service. These are UI-only responses; no stream
// request is read and no audio or video playback is started.
player_pause :: proc(value: bool) -> bool {paused = value; return true}
player_rate_supported :: proc() -> bool {return true}
player_rate :: proc(_: f64) -> bool {return true}
player_seek :: proc(_: f64) -> bool {return true}
stop_feed_preview :: proc() {}
apply_feed_preview :: proc(_: ^Network_Result) {}

load_video :: proc(
	stream: yt.Stream,
	_: ^sdl.Renderer,
	position_ms: f64 = 0,
	start_paused: bool = false,
) {
	browsing, loaded = false, true
	duration_ms = catalog.videos[selected].duration_ms
	if stream.duration_ms > 0 {duration_ms = stream.duration_ms}
	timeline = {position_ms = position_ms, seek_target_ms = -1}
	paused = start_paused
	rate = 1
	dirty = true
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	browsing = false
	loaded = true
	paused = true
	duration_ms = catalog.videos[selected].duration_ms
	// The host has no stream. Show a typical label so the layout reserves it.
	stream_width, stream_height = 3840, 2160
	timeline = {
		position_ms    = model.video_resume_position(catalog.videos[selected]),
		seek_target_ms = -1,
	}
	rate = 1
	dirty = true
}

stop_playback :: proc() {
	browsing = true
	resolving = false
	clear_player_quality()
	autoplay_deadline = 0
	delete(sponsor_segments); sponsor_segments = nil
	return_to_grid = false
	seek_pending = {}
	library_focus_pending = true
	dirty = true
}

run_dev :: proc(renderer: ^sdl.Renderer) {
	fmt.println("local UI preview only; no TV commands or media playback")
	fmt.println(
		"arrows: select / seek / rate; enter: open / pause; escape: back; close the window to exit",
	)
	assert(render(renderer), string(sdl.GetError()))
	dirty = false
	started := sdl.GetTicks64()
	for running {
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(
			&event,
			loading_active() ? 16 : 100,
		) {wheel = handle_event(renderer, event)}
		if return_to_grid {stop_playback()}
		tick_autoplay(sdl.GetTicks64())
		poll_network(renderer)
		poll_card_press(sdl.GetTicks64())
		poll_login_tick()
		apply_pending_seek(sdl.GetTicks64())
		expire_player_controls()
		expire_toast(sdl.GetTicks64())
		if timeline.seek_target_ms >= 0 {
			timeline.position_ms = timeline.seek_target_ms
			model.seek_done(&timeline)
		}
		if dirty || loading_active() {
			assert(render(renderer, wheel), string(sdl.GetError()))
			dirty = false
		}
		if DEV_SMOKE {
			assert(sdl.GetTicks64() - started < 15000, "native search UI startup timed out")
			if !search_loading {
				assert(len(catalog.videos) > 0, "native search returned no videos")
				for texture in textures {
					if texture !=
					   nil {fmt.println("native search, cover upload, and Wayland UI passed"); return}
				}
			}
		}
	}
}

finish_video :: proc() {offer_next_video()}
