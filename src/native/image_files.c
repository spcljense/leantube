#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>

int leantube_image_file_info(const char *path, int64_t *size, int64_t *modified) {
	struct stat info;
	if (lstat(path, &info) != 0 || !S_ISREG(info.st_mode)) {
		return 0;
	}
	if (size) {
		*size = info.st_size;
	}
	if (modified) {
		*modified = (int64_t)info.st_mtim.tv_sec * 1000000000 + info.st_mtim.tv_nsec;
	}
	return 1;
}

int leantube_image_dir_next(DIR *directory, const char **name) {
	errno = 0;
	struct dirent *entry = readdir(directory);
	if (!entry) {
		return errno == 0 ? 0 : -1;
	}
	*name = entry->d_name;
	return 1;
}
