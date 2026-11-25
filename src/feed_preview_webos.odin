#+build linux:default arm32
package main

import clay "../vendor/clay"
import reader "./playback"
import "core:fmt"
import "core:strings"
import "core:sync"
import sdl "vendor:sdl2"

PREVIEW_DWELL_MS :: 1000
PREVIEW_STARTUP_MS :: 8000
PREVIEW_SECONDS :: 12

preview_focus := -1
preview_page, preview_generation: u32
preview_due, preview_opened_at, preview_play_at, preview_started_at: u64
preview_bounds: sdl.Rect
preview_reader: ^reader.Session
preview_api: ^Starfish
preview_status: ^Decoder_Status
preview_bound, preview_eos: bool

feed_preview_target :: proc() -> (index: int, bounds: sdl.Rect) {
	if !feed_previews ||
	   !browsing ||
	   return_to_grid ||
	   !window_visible ||
	   search_loading ||
	   login_screen ||
	   search_editing ||
	   account_menu ||
	   sponsor_menu ||
	   settings_menu ||
	   card_menu ||
	   card_menu_waiting ||
	   card_press.active ||
	   rail_focus ||
	   channel_focus ||
	   selected < 0 ||
	   selected >= len(catalog.videos) {return -1, {}}
	video := catalog.videos[selected]
	if video.id == "" || video.browse_id != "" {return -1, {}}
	cover := clay.GetElementData(clay.ID("cover", u32(selected)))
	scroll := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	box := cover.boundingBox
	if !cover.found ||
	   box.height <= 0 ||
	   box.y < scroll.y ||
	   box.y + box.height > scroll.y + scroll.height + 0.1 {return -1, {}}
	return selected, pixel_bounds({box.x, box.y, box.width, box.height})
}

close_preview_media :: proc() {
	if preview_reader != nil {reader.stop(preview_reader)}
	if preview_api != nil {_ = decoder_close(preview_api, preview_status)}
	reader.close(preview_reader)
	preview_reader, preview_api, preview_status = nil, nil, nil
	preview_bound, preview_eos = false, false
	preview_started_at, preview_play_at = 0, 0
	if feed_preview_visible {
		feed_preview_visible = false
		dirty = true
	}
}

stop_feed_preview :: proc() {
	close_preview_media()
	preview_focus = -1
	preview_due = 0
	preview_generation += 1
}

apply_feed_preview :: proc(result: ^Network_Result) {
	if result.playback != preview_generation {return}
	index, bounds := feed_preview_target()
	if index < 0 || index != preview_focus || bounds != preview_bounds {return}
	if result.error != .None {
		fmt.eprintf("preview resolve failed: %v\n", result.error)
		return
	}
	if result.stream.has_4k {mark_video_4k(index)}
	preview_reader = reader.open(
		result.stream.url,
		result.stream.audio_url,
		{mode = "curl-auto", decoder_preroll = true, end = PREVIEW_SECONDS},
	)
	preview_opened_at = sdl.GetTicks64()
	if preview_reader == nil {fmt.eprintln("preview reader initialization failed")}
}

poll_feed_preview :: proc(now: u64) {
	index, bounds := feed_preview_target()
	if index != preview_focus || preview_page != page || bounds != preview_bounds {
		stop_feed_preview()
		preview_focus, preview_page, preview_bounds = index, page, bounds
		if index >= 0 {preview_due = now + PREVIEW_DWELL_MS}
	}
	if preview_due != 0 && now >= preview_due {
		preview_due = 0
		_ = submit_network(
			{
				kind = .Preview,
				page = page,
				playback = preview_generation,
				text = strings.clone(catalog.videos[index].id),
			},
		)
	}
	if preview_reader == nil {return}
	failure := sync.atomic_load(&preview_reader.state.failure)
	if failure != 0 {
		fmt.eprintf("preview reader failed: %d\n", failure)
		close_preview_media()
		return
	}
	if preview_started_at == 0 && now - preview_opened_at >= PREVIEW_STARTUP_MS {
		fmt.eprintf(
			"preview startup timed out: decoder=%v bound=%v\n",
			preview_api != nil,
			preview_bound,
		)
		close_preview_media()
		return
	}
	if preview_started_at != 0 && now - preview_started_at >= PREVIEW_SECONDS * 1000 {
		close_preview_media()
		return
	}
	v, a := &preview_reader.tracks[0], &preview_reader.tracks[1]
	if preview_api == nil {
		sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
		ready := reader.startup_buffered(v, v.end) && reader.startup_buffered(a, a.end)
		sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
		if !ready {return}
		preview_api, preview_status = decoder_open(v, a, 0, preview_bounds)
		if preview_api == nil {
			fmt.eprintln("preview decoder initialization failed")
			close_preview_media()
			return
		}
	}
	status := preview_status
	decoder_error := sync.atomic_load(&status.error)
	if decoder_error != 0 || sync.atomic_load(&status.ended) != 0 {
		if decoder_error != 0 {fmt.eprintf("preview decoder failed: %d\n", decoder_error)}
		close_preview_media()
		return
	}
	frame := sync.atomic_load(&status.frame_ns)
	clock := max(0, f64(frame) / 1e9)
	// Match fullscreen pre-roll. Some pipelines only complete loading after input arrives.
	if !decoder_feed(preview_api, a, clock + 1) || !decoder_feed(preview_api, v, clock + 1) {
		fmt.eprintln("preview decoder feed failed")
		close_preview_media()
		return
	}
	if sync.atomic_load(&status.loaded) == 0 {return}
	if !preview_bound {
		if !display_started() {
			fmt.eprintln("preview display binding failed")
			close_preview_media()
			return
		}
		if !feed_preview_audio && !sf_mute(preview_api) {
			fmt.eprintln("preview decoder mute failed")
			close_preview_media()
			return
		}
		preview_bound = true
	}
	sync.atomic_store(&preview_reader.state.position, clock)
	drained := true
	for &track in preview_reader.tracks {
		sync.mutex_lock(&track.mutex)
		drained = drained && reader.span_drained(&track)
		sync.cond_signal(&track.changed)
		sync.mutex_unlock(&track.mutex)
	}
	if drained && !preview_eos {
		if !sf_eos(preview_api) {
			fmt.eprintln("preview decoder end-of-stream failed")
			close_preview_media()
			return
		}
		preview_eos = true
	}
	if sync.atomic_load(&status.playing) == 0 && now - preview_play_at >= 250 {
		_ = sf_play(preview_api)
		preview_play_at = now
	}
	if frame >= 0 && !feed_preview_visible {
		preview_started_at = now
		feed_preview_visible = true
		fmt.eprintln("preview first frame")
		dirty = true
	}
}
