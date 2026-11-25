package youtube

import "../model"

import "core:encoding/json"
import "core:slice"
import "core:strings"

Video_Limit :: struct {
	codec:              string,
	width, height, fps: int,
}

video_codec :: proc(mime: string) -> string {
	if !strings.has_prefix(mime, "video/") {return ""}
	for pair in ([][2]string{{"av01", "av1"}, {"vp09", "vp9"}, {"vp9", "vp9"}, {"avc1", "h264"}, {"hvc1", "hevc"}, {"hev1", "hevc"}}) {
		if strings.contains(mime, pair[0]) {return pair[1]}
	}
	return ""
}

supported_video :: proc(codec: string, width, height, fps: int, limits: []Video_Limit) -> bool {
	if codec == "" || width <= 0 || height <= 0 || fps <= 0 {return false}
	if limits == nil {return true} 	// Host tools do not have LG capabilities.
	for limit in limits {
		if limit.codec == codec {
			return width <= limit.width && height <= limit.height && fps <= limit.fps
		}
	}
	return false
}

// Return separate direct sources. Returned strings remain owned by the caller.
parse_player :: proc(
	data: string,
	limits: []Video_Limit = nil,
	requested_height: int = 0,
	preview: bool = false,
	maximum_height: int = 0,
) -> (
	stream: Stream,
	error: Error,
) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	status, _ := field(field(value, "playabilityStatus"), "status").(json.String)
	if status != "OK" {return {}, .Unavailable}
	adaptive, _ := field(field(value, "streamingData"), "adaptiveFormats").(json.Array)
	combined, _ := field(field(value, "streamingData"), "formats").(json.Array)
	audio := original_audio(adaptive)
	if audio.url == "" {
		// Some responses expose AAC only in a combined stream. Read its audio
		// without reducing the independently selected video quality.
		for format in combined {
			mime, _ := field(format, "mimeType").(json.String)
			url, _ := field(format, "url").(json.String)
			if strings.has_prefix(string(url), "https://") &&
			   strings.contains(string(mime), "mp4a.40.2") {
				audio.url = strings.clone(string(url)); break
			}
		}
	}
	if audio.url == "" {return {}, .No_Direct_Stream}
	best_area, best_fps, best_hdr, best_bitrate := f64(0), f64(0), false, f64(0)
	best_preview_gap := max(int)
	for formats in ([]json.Array{adaptive, combined}) {
		for format in formats {
			url, _ := field(format, "url").(json.String)
			mime, _ := field(format, "mimeType").(json.String)
			width, _ := numeric(field(format, "width"))
			height, _ := numeric(field(format, "height"))
			fps, _ := numeric(field(format, "fps"))
			bitrate, _ := numeric(field(format, "bitrate"))
			codec := video_codec(string(mime))
			drm, _ := field(format, "drmFamilies").(json.Array)
			if len(drm) > 0 ||
			   codec == "" ||
			   !strings.has_prefix(string(url), "https://") {continue}
			stream.has_4k |= model.is_4k(int(width), int(height))
			if !supported_video(codec, int(width), int(height), int(fps), limits) {continue}
			short_side := int(min(width, height))
			if preview && (short_side > 720 || max(width, height) > 1280) {continue}
			if !slice.contains(stream.heights[:], int(height)) {
				append(&stream.heights, int(height))
			}
			if requested_height > 0 && int(height) != requested_height {continue}
			// In portrait and cropped streams the shorter edge is the quality tier.
			if requested_height == 0 &&
			   maximum_height > 0 &&
			   (short_side > maximum_height ||
					   max(width, height) > f64(maximum_height) * 2) {continue}
			transfer, _ := field(
				field(format, "colorInfo"),
				"transferCharacteristics",
			).(json.String)
			transfer_name := strings.trim_prefix(
				string(transfer),
				"COLOR_TRANSFER_CHARACTERISTICS_",
			)
			hdr := transfer_name == "SMPTEST2084" || transfer_name == "ARIB_STD_B67"
			if preview && hdr {continue}
			area := width * height
			preview_gap := short_side <= 360 ? 360 - short_side : short_side
			better :=
				area > best_area ||
				(area == best_area &&
						(fps > best_fps ||
								(fps == best_fps &&
										((hdr && !best_hdr) ||
												(hdr == best_hdr && bitrate > best_bitrate)))))
			if preview {
				if preview_gap > best_preview_gap ||
				   (preview_gap == best_preview_gap && !better) {continue}
			} else if !better {continue}
			stream.url = string(url)
			stream.width, stream.height = int(width), int(height)
			best_area, best_fps, best_hdr, best_bitrate = area, fps, hdr, bitrate
			best_preview_gap = preview_gap
		}
	}
	if stream.url == "" {delete(audio.url); delete(stream.heights); return {}, .No_Direct_Stream}
	slice.sort_by(stream.heights[:], proc(a, b: int) -> bool {return a > b})
	stream.url = strings.clone(stream.url)
	stream.audio_url = audio.url
	channel_id, _ := field(field(value, "videoDetails"), "channelId").(json.String)
	stream.channel_id = strings.clone(string(channel_id))
	title, _ := field(field(value, "videoDetails"), "title").(json.String)
	stream.title = strings.clone(string(title))
	seconds, _ := numeric(field(field(value, "videoDetails"), "lengthSeconds"))
	if seconds > 0 {stream.duration_ms = seconds * 1000}
	return
}
