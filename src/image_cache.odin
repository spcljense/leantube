#+build !wasi
package main

import "./http"
import yt "./youtube"
import "core:c"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

// Used only by the network worker. Keep the original encoded image bytes.
IMAGE_CACHE_MIB :: #config(IMAGE_CACHE_MIB, 64)
#assert(IMAGE_CACHE_MIB >= 0 && IMAGE_CACHE_MIB <= 256)
IMAGE_CACHE_BYTES :: IMAGE_CACHE_MIB * 1024 * 1024
Image_Cache :: struct {
	directory:     string,
	maximum_bytes: i64,
}

image_cache_path :: proc(cache: Image_Cache, source: string) -> string {
	if cache.directory == "" {return ""}
	return fmt.aprintf("%s/%016x.image", cache.directory, hash.fnv64a(transmute([]u8)source))
}

// Reserve space before writing. Hits do not change the download order.
trim_image_cache :: proc(cache: Image_Cache, incoming_bytes: i64 = 0) -> bool {
	if cache.directory == "" ||
	   incoming_bytes < 0 ||
	   cache.maximum_bytes < 0 ||
	   incoming_bytes > cache.maximum_bytes {return false}
	// SDL uses libc filesystem APIs; Odin's directory scan requires statx.
	files_info, read_error := os.read_all_directory_by_path(cache.directory, context.allocator)
	if read_error != nil {return false}
	defer os.file_info_slice_delete(files_info, context.allocator)
	Entry :: struct {
		path:     cstring,
		size:     i64,
		modified: i64,
	}
	files: [dynamic]Entry
	defer {for file in files {delete(file.path)}; delete(files)}
	total := incoming_bytes
	for info in files_info {
		if info.type != .Regular || !strings.has_suffix(info.name, ".image") {continue}
		path := strings.clone_to_cstring(info.fullpath)
		append(&files, Entry{path, i64(info.size), time.time_to_unix(info.modification_time)})
		total += i64(info.size)
	}
	if total <= cache.maximum_bytes {return true}
	slice.sort_by(files[:], proc(a, b: Entry) -> bool {return a.modified < b.modified})
	for file in files {
		if total <= cache.maximum_bytes {return true}
		if os.remove(string(file.path)) == nil {total -= file.size}
	}
	return total <= cache.maximum_bytes
}

// A scheduling hint only; reads still decode and reject corrupt cache files.
cached_image_exists :: proc(cache: Image_Cache, source: string) -> bool {
	path := image_cache_path(cache, source)
	defer delete(path)
	if path == "" {return false}
	info, error := os.stat(path, context.allocator)
	return error == nil && info.type == .Regular
}

// Return owned pixels without resolving or downloading the image source.
read_cached_image :: proc(cache: Image_Cache, source: string, target: i32) -> ^sdl.Surface {
	path := image_cache_path(cache, source)
	defer delete(path)
	if path == "" {return nil}
	bytes, error := os.read_entire_file(path, context.allocator)
	defer delete(bytes)
	surface: ^sdl.Surface
	if error == nil {surface = decode_image(bytes, target)}
	if surface == nil {_ = os.remove(path)}
	return surface
}

load_cached_image :: proc(
	cache: Image_Cache,
	client: ^http.Client,
	source: string,
	target: i32 = 0,
	fetch: type_of(yt.fetch_thumbnail) = yt.fetch_thumbnail,
	cache_source: string = "",
) -> ^sdl.Surface {
	if source == "" {return nil}
	// Channel IDs remain available after restart, before their avatar URL is known.
	key := cache_source != "" ? cache_source : source
	if surface := read_cached_image(cache, key, target); surface != nil {return surface}

	bytes: [dynamic]u8
	if strings.has_prefix(source, "https://") {
		response, error := fetch(client, source)
		if error == nil &&
		   response.status == 200 {bytes = response.body} else {delete(response.body)}
	} else {
		bytes = yt.thumbnail(client, source, network_stopping, fetch)
	}
	defer delete(bytes)
	surface := decode_image(bytes[:], target)
	if surface != nil && trim_image_cache(cache, i64(len(bytes))) {
		// Cache files are disposable: a partial file is fetched again on the next read.
		path := image_cache_path(cache, key)
		defer delete(path)
		if path != "" && os.write_entire_file(path, bytes[:]) != nil {_ = os.remove(path)}
	}
	return surface
}

// Decode and prefilter on the worker. The result owns its pixels, not bytes.
decode_image :: proc(bytes: []u8, target: i32 = 0) -> ^sdl.Surface {
	if len(bytes) == 0 {return nil}
	_ = img.Init({.PNG, .JPG, .WEBP})
	io := sdl.RWFromConstMem(raw_data(bytes), c.int(len(bytes)))
	if io == nil {return nil}
	surface := img.Load_RW(io, true)
	for target > 0 && surface != nil && max(surface.w, surface.h) > target {
		ratio := max(f32(0.5), f32(target) / f32(max(surface.w, surface.h)))
		width := max(1, i32(math.round(f32(surface.w) * ratio)))
		height := max(1, i32(math.round(f32(surface.h) * ratio)))
		next := sdl.CreateRGBSurfaceWithFormat(0, width, height, 32, u32(sdl.PixelFormatEnum.RGBA32))
		if next != nil {
			if sdl.SoftStretchLinear(surface, nil, next, nil) != 0 {
				sdl.FreeSurface(next)
				next = nil
			}
		}
		sdl.FreeSurface(surface)
		surface = next
	}
	return surface
}
