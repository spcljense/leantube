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
import "core:sync"
import "core:sys/posix"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

when ODIN_ARCH == .arm32 {
	foreign import image_files "system:c"
} else {
	foreign import image_files "../build/host-qr/image_files.a"
}

foreign image_files {
	leantube_image_file_info :: proc "c" (path: cstring, size, modified: ^i64) -> c.int ---
	leantube_image_dir_next :: proc "c" (directory: posix.DIR, name: ^cstring) -> c.int ---
}

image_disk_mutex: sync.Mutex

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
	// Use libc directory metadata so older webOS kernels need no statx support.
	path := strings.clone_to_cstring(cache.directory)
	defer delete(path)
	directory := posix.opendir(path)
	if directory == nil {return false}
	defer _ = posix.closedir(directory)
	Entry :: struct {
		path:     cstring,
		size:     i64,
		modified: i64,
	}
	files: [dynamic]Entry
	defer {for file in files {delete(file.path)}; delete(files)}
	total := incoming_bytes
	for {
		name: cstring
		status := leantube_image_dir_next(directory, &name)
		if status < 0 {return false}
		if status == 0 {break}
		if !strings.has_suffix(string(name), ".image") {continue}
		entry := Entry{path = fmt.caprintf("%s/%s", cache.directory, name)}
		if leantube_image_file_info(entry.path, &entry.size, &entry.modified) == 0 {
			delete(entry.path)
			continue
		}
		append(&files, entry)
		total += entry.size
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
	terminated := strings.clone_to_cstring(path)
	defer delete(terminated)
	return leantube_image_file_info(terminated, nil, nil) != 0
}

// Return owned pixels without resolving or downloading the image source.
read_cached_image :: proc(cache: Image_Cache, source: string, target: i32) -> ^sdl.Surface {
	path := image_cache_path(cache, source)
	defer delete(path)
	if path == "" {return nil}
	terminated := strings.clone_to_cstring(path)
	defer delete(terminated)
	surface: ^sdl.Surface
	{
		sync.guard(&image_disk_mutex)
		surface = img.Load(terminated)
		if surface == nil {_ = os.remove(path)}
	}
	return scale_image(surface, target)
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
	if surface != nil {
		sync.guard(&image_disk_mutex)
		if !trim_image_cache(cache, i64(len(bytes))) {return surface}
		// Cache files are disposable: a partial file is fetched again on the next read.
		path := image_cache_path(cache, key)
		defer delete(path)
		if path != "" && os.write_entire_file(path, bytes[:]) != nil {_ = os.remove(path)}
	}
	return surface
}

// Decode and prefilter on the worker. The result owns its pixels, not bytes.
decode_image :: proc(bytes: []u8, target: i32 = 0) -> ^sdl.Surface {
	if len(bytes) == 0 || len(bytes) > int(max(c.int)) {return nil}
	io := sdl.RWFromConstMem(raw_data(bytes), c.int(len(bytes)))
	if io == nil {return nil}
	return scale_image(img.Load_RW(io, true), target)
}

scale_image :: proc(decoded: ^sdl.Surface, target: i32) -> ^sdl.Surface {
	surface := decoded
	if target > 0 && surface != nil && max(surface.w, surface.h) > target &&
	   surface.format.format != u32(sdl.PixelFormatEnum.RGBA32) {
		converted := sdl.ConvertSurfaceFormat(surface, u32(sdl.PixelFormatEnum.RGBA32), 0)
		sdl.FreeSurface(surface)
		surface = converted
	}
	for target > 0 && surface != nil && max(surface.w, surface.h) > target {
		ratio := max(f32(0.5), f32(target) / f32(max(surface.w, surface.h)))
		width := max(1, i32(math.round(f32(surface.w) * ratio)))
		height := max(1, i32(math.round(f32(surface.h) * ratio)))
		next := create_surface(width, height)
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
