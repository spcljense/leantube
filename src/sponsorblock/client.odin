package sponsorblock

import "../http"
import "../model"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"

Category :: enum {
	Sponsor,
	Intro,
	Outro,
	Self_Promotion,
	Interaction,
	Preview,
	Filler,
	Music_Offtopic,
}
Categories :: bit_set[Category;u8]
DEFAULT_CATEGORIES :: Categories{.Sponsor}
CATEGORY_IDS := [Category]string {
	.Sponsor        = "sponsor",
	.Intro          = "intro",
	.Outro          = "outro",
	.Self_Promotion = "selfpromo",
	.Interaction    = "interaction",
	.Preview        = "preview",
	.Filler         = "filler",
	.Music_Offtopic = "music_offtopic",
}

Segment :: struct {
	start_ms, end_ms, video_duration_ms: f64,
	category:                            Category,
	skipped:                             bool,
}

// Use the existing OpenSSL library: core SHA-256 currently emits unsupported
// ARM SHA instructions when compiled for the B9 Cortex-A9 target.
foreign import crypto "system:crypto"
@(default_calling_convention = "c")
foreign crypto {
	SHA256 :: proc(data: rawptr, count: uint, digest: ^u8) -> ^u8 ---
}

// The documented four-character prefix avoids sending the exact video ID.
// No submissions, votes, or skip-count requests are sent.
endpoint :: proc(id: string) -> string {
	digest: [32]u8
	SHA256(raw_data(id), uint(len(id)), &digest[0])
	return fmt.aprintf("https://sponsor.ajay.app/api/skipSegments/%02x%02x", digest[0], digest[1])
}

parse :: proc(
	data, id: string,
	enabled: Categories = DEFAULT_CATEGORIES,
) -> (
	segments: [dynamic]Segment,
	valid: bool,
) {
	value, error := json.parse(data)
	if error != .None {return nil, false}
	defer json.destroy_value(value)
	videos, root_valid := value.(json.Array)
	if !root_valid {return nil, false}
	for video in videos {
		entry, entry_valid := video.(json.Object)
		if !entry_valid {continue}
		video_id, _ := entry["videoID"].(json.String)
		if string(video_id) != id {continue}
		items, _ := entry["segments"].(json.Array)
		for item in items {
			object, item_valid := item.(json.Object)
			if !item_valid {continue}
			category_id, _ := object["category"].(json.String)
			action, _ := object["actionType"].(json.String)
			if action != "skip" {continue}
			category, category_enabled := enabled_category(category_id, enabled)
			if !category_enabled {continue}
			times, _ := object["segment"].(json.Array)
			if len(times) != 2 {continue}
			start, a := model.number(times[0])
			end, b := model.number(times[1])
			length, _ := model.number(object["videoDuration"])
			if !a || !b || start < 0 || end <= start {continue}
			append(
				&segments,
				Segment {
					start_ms = start * 1000,
					end_ms = end * 1000,
					video_duration_ms = length * 1000,
					category = category,
				},
			)
		}
	}
	return segments, true
}

enabled_category :: proc(id: string, enabled: Categories) -> (Category, bool) {
	for candidate in Category {
		if candidate in enabled && CATEGORY_IDS[candidate] == id {return candidate, true}
	}
	return {}, false
}

request_url :: proc(id: string, enabled: Categories) -> string {
	base := endpoint(id)
	defer delete(base)
	query := strings.builder_make()
	strings.write_string(&query, base)
	separator := "?"
	for category in Category {
		if category not_in enabled {continue}
		strings.write_string(&query, separator)
		strings.write_string(&query, "category=")
		strings.write_string(&query, CATEGORY_IDS[category])
		separator = "&"
	}
	return strings.to_string(query)
}

fetch :: proc(
	client: ^http.Client,
	id: string,
	enabled: Categories = DEFAULT_CATEGORIES,
) -> (
	segments: [dynamic]Segment,
) {
	if enabled == {} {return nil}
	url := request_url(id, enabled)
	defer delete(url)
	response, error := http.request(client, url, timeout_ms = 2000)
	if error != nil {return nil}
	defer delete(response.body)
	if response.status != 200 {return nil} 	// 404 means that there are no segments.
	segments, _ = parse(string(response.body[:]), id, enabled)
	return
}

valid_span :: proc(segment: Segment, duration_ms: f64) -> bool {
	return(
		segment.start_ms >= 0 &&
		segment.end_ms > segment.start_ms &&
		segment.end_ms <= duration_ms &&
		(segment.video_duration_ms <= 0 ||
				math.abs(segment.video_duration_ms - duration_ms) <= 1000) \
	)
}

can_skip :: proc(segment: Segment, duration_ms: f64) -> bool {
	return !segment.skipped && valid_span(segment, duration_ms)
}

// Skip an overlapping group once per playback. This avoids repeating a seek
// on stale media notifications and lets a user intentionally rewind to it.
skip_target :: proc(segments: []Segment, position_ms, duration_ms: f64) -> f64 {
	target := position_ms
	for {
		before := target
		for segment in segments {
			if !can_skip(segment, duration_ms) {continue}
			if segment.start_ms <= target &&
			   segment.end_ms > position_ms {target = max(target, segment.end_ms)}
		}
		if target == before {break}
	}
	return target > position_ms ? target : -1
}
// Find the next eligible group, including a group containing the position.
next_skip :: proc(segments: []Segment, position_ms, duration_ms: f64) -> (from, to: f64) {
	from, to = -1, -1
	for segment in segments {
		if can_skip(segment, duration_ms) &&
		   segment.end_ms > position_ms &&
		   (from < 0 || segment.start_ms < from) {from = segment.start_ms}
	}
	if from >= 0 {to = skip_target(segments, max(from, position_ms), duration_ms)}
	return
}

mark_skipped :: proc(segments: []Segment, from_ms, to_ms: f64) {
	for &segment in segments {
		if segment.start_ms <= to_ms && segment.end_ms > from_ms {segment.skipped = true}
	}
}
