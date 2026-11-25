package youtube

import "../http"
import "../model"
import "core:encoding/json"
import "core:strings"

browse :: proc(
	client: ^http.Client,
	id: string,
	continuation: string = "",
	params: string = "",
	filter: string = "",
	visitor_data: string = "",
) -> (
	model.Catalog,
	Error,
	string,
) {
	if strings.has_prefix(id, "UC") {
		return channel_browse(client, id, params, continuation, filter, visitor_data)
	}
	request := struct {
		ctx:          struct {
			client: Client_Context,
		} `json:"context"`,
		browseId:     string `json:",omitempty"`,
		continuation: string `json:",omitempty"`,
	} {
		ctx = {
			client = {
				clientName = "TVHTML5",
				clientVersion = TV_VERSION,
				hl = "en",
				gl = "US",
				userAgent = TV_AGENT,
				visitorData = visitor_data,
			},
		},
		browseId = continuation == "" ? id : "",
		continuation = continuation,
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response, ""}
	defer delete(body)
	response, error := api_post(client, "browse", body, .TV)
	if error != .None {return {}, error, ""}
	defer delete(response.body)
	return parse_browse(string(response.body[:]), videos_only = id == "FEwhat_to_watch")
}

parse_browse :: proc(
	data: string,
	videos_only: bool = false,
) -> (
	catalog: model.Catalog,
	error: Error,
	visitor: string,
) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response, ""}
	defer json.destroy_value(value)
	contents := feed_contents(value)
	if contents == nil {return {}, .Invalid_Response, ""}
	if text, ok := field(field(value, "responseContext"), "visitorData").(json.String); ok {
		visitor = strings.clone(string(text))
	}
	collect_tiles(contents, &catalog, videos_only)
	catalog.continuation = browse_continuation(contents)
	return
}

collect_tiles :: proc(value: json.Value, catalog: ^model.Catalog, videos_only: bool = false) {
	#partial switch item in value {
	case json.Array:
		for child in item {collect_tiles(child, catalog, videos_only)}
	case json.Object:
		// Ads and navigation tabs are not feed cards. Only the selected tab's
		// content is a feed; its sibling tabs can contain unrelated channel data.
		if item["adSlotRenderer"] != nil || item["inFeedAdLayoutRenderer"] != nil {return}
		if tab := item["tabRenderer"]; tab != nil {
			selected, _ := field(tab, "selected").(json.Boolean)
			if bool(selected) {collect_tiles(field(tab, "content"), catalog, videos_only)}
			return
		}
		if tile := item["tileRenderer"]; tile != nil {
			card := parse_tile(tile, videos_only)
			if card.id == "" && card.browse_id == "" {return}
			for existing in catalog.videos {
				if existing.id == card.id && existing.browse_id == card.browse_id {
					model.video_destroy(&card)
					return
				}
			}
			append(&catalog.videos, card)
			return
		}
		if videos_only {
			if lockup := item["lockupViewModel"]; lockup != nil {
				kind, _ := field(lockup, "contentType").(json.String)
				if kind == "LOCKUP_CONTENT_TYPE_VIDEO" {collect_lockups(value, catalog)}
				return
			}
			if item["videoRenderer"] != nil {collect_videos(value, catalog); return}
		}
		for _, child in item {collect_tiles(child, catalog, videos_only)}
	}
}

parse_tile :: proc(tile: json.Value, videos_only: bool) -> (card: model.Video) {
	command := field(tile, "onSelectCommand")
	id, _ := field(field(command, "watchEndpoint"), "videoId").(json.String)
	browse_id, _ := field(field(command, "browseEndpoint"), "browseId").(json.String)
	playlist := strings.has_prefix(string(browse_id), "VL")
	if playlist && videos_only {return}
	if !playlist && !video_id_valid(string(id)) {return}
	header := field(field(tile, "header"), "tileHeaderRenderer")
	stamp: string
	overlays, _ := field(header, "thumbnailOverlays").(json.Array)
	for overlay in overlays {
		if status := field(overlay, "thumbnailOverlayTimeStatusRenderer"); status != nil {
			stamp = text(field(status, "text"))
			break
		}
	}
	ms := playlist ? 0 : duration(stamp)
	if !playlist && ms <= 0 {delete(stamp); return}
	metadata := field(field(tile, "metadata"), "tileMetadataRenderer")
	title := text(field(metadata, "title"))
	if title == "" {delete(stamp); return}
	card = {
		id              = strings.clone(string(id)),
		watched_percent = playlist ? 0 : watched_percent(field(header, "thumbnailOverlays")),
		watch_later     = watch_later_state(field(header, "thumbnailOverlays")),
		browse_id       = playlist ? strings.clone(string(browse_id)) : "",
		title           = title,
		duration_label  = stamp,
		duration_ms     = ms,
		has_4k          = !playlist && (has_4k_badge(metadata) ||
				has_4k_badge(field(header, "thumbnailOverlays")) ||
				has_4k_badge(field(tile, "badges"))),
	}
	if !playlist {read_resume_position(&card, command)}
	labels: [dynamic]string
	defer {
		for label in labels {delete(label)}
		delete(labels)
	}
	lines, _ := field(metadata, "lines").(json.Array)
	for line in lines {
		items, _ := field(field(line, "lineRenderer"), "items").(json.Array)
		for item in items {
			label := text(field(field(item, "lineItemRenderer"), "text"))
			if label != "" {append(&labels, label)}
		}
	}
	fill_card_labels(&card, labels[:])
	card.actions = parse_card_actions(field(tile, "onLongPressCommand"))
	card.avatar_url = card_avatar(metadata)
	thumbnails, _ := field(field(header, "thumbnail"), "thumbnails").(json.Array)
	for thumbnail in thumbnails {
		if url, ok := field(thumbnail, "url").(json.String);
		   ok && strings.has_prefix(string(url), "https://") {
			card.thumbnail_url = string(url)
		}
	}
	card.thumbnail_url = strings.clone(card.thumbnail_url)
	return
}

browse_continuation :: proc(value: json.Value) -> string {
	token, _ := next_browse_cursor(value)
	return strings.clone(token)
}

// The feed cursor is usually outside the shelves. At the same level, a list's
// trailing continuation wins over an earlier one.
next_browse_cursor :: proc(value: json.Value, depth := 0) -> (token: string, level: int) {
	level = max(int)
	#partial switch item in value {
	case json.Array:
		for child in item {
			candidate, candidate_level := next_browse_cursor(child, depth + 1)
			if candidate != "" &&
			   candidate_level <= level {token, level = candidate, candidate_level}
		}
	case json.Object:
		if item["adSlotRenderer"] != nil ||
		   item["inFeedAdLayoutRenderer"] != nil ||
		   item["tileRenderer"] != nil ||
		   item["videoRenderer"] != nil ||
		   item["lockupViewModel"] != nil ||
		   item["chipViewModel"] != nil ||
		   item["listItemViewModel"] != nil ||
		   item["menuRenderer"] != nil {return}
		if node := item["continuationItemRenderer"]; node != nil {
			command := find_node(field(node, "continuationEndpoint"), "continuationCommand")
			if command == nil {command = find_node(field(node, "button"), "continuationCommand")}
			if value, ok := field(command, "token").(json.String); ok && value != "" {
				return string(value), depth
			}
			return
		}
		if tab := item["tabRenderer"]; tab != nil {
			selected, _ := field(tab, "selected").(json.Boolean)
			if bool(selected) {return next_browse_cursor(field(tab, "content"), depth + 1)}
			return
		}
		continuations, _ := item["continuations"].(json.Array)
		for entry in continuations {
			if value, ok := field(
				   field(entry, "nextContinuationData"),
				   "continuation",
			   ).(json.String); ok && value != "" {
				return string(value), depth
			}
		}
		for _, child in item {
			candidate, candidate_level := next_browse_cursor(child, depth + 1)
			if candidate != "" &&
			   candidate_level < level {token, level = candidate, candidate_level}
		}
	}
	return
}
