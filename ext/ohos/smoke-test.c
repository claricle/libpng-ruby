/* Minimal libpng round-trip test, run inside the dockerharmony
 * container (real OHOS userland) to verify that an NDK-built, signed
 * libpng16.so actually loads and works on OHOS.
 *
 * The binary itself is cross-compiled with the OHOS NDK clang
 * (aarch64-unknown-linux-ohos target). Both the binary and the .so
 * run via the OHOS dynamic linker (/lib/ld-musl-aarch64.so.1).
 *
 * This is the empirical check that "NDK-built OHOS bytes work in
 * real OHOS userland" -- not just an assumption based on matching
 * dynamic-linker paths.
 */
#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  png_image img = {0};
  img.version = PNG_IMAGE_VERSION;
  img.width = 2;
  img.height = 2;
  img.format = PNG_FORMAT_RGBA;

  unsigned char pixels[16];
  int i;
  for (i = 0; i < 16; i++) {
    pixels[i] = (unsigned char)i;
  }

  png_alloc_size_t size = 0;
  if (!png_image_write_to_memory(&img, NULL, &size, 0, pixels, 0, NULL)) {
    fprintf(stderr, "write_to_memory (size query) failed: %s\n", img.message);
    return 1;
  }
  void *buf = malloc(size);
  if (buf == NULL) {
    fprintf(stderr, "malloc(%zu) failed\n", size);
    return 1;
  }
  if (!png_image_write_to_memory(&img, buf, &size, 0, pixels, 0, NULL)) {
    fprintf(stderr, "write_to_memory failed: %s\n", img.message);
    free(buf);
    return 1;
  }
  png_image_free(&img);

  png_image read_img = {0};
  read_img.version = PNG_IMAGE_VERSION;
  if (!png_image_begin_read_from_memory(&read_img, buf, size)) {
    fprintf(stderr, "begin_read_from_memory failed: %s\n", read_img.message);
    free(buf);
    return 1;
  }
  read_img.format = PNG_FORMAT_RGBA;

  unsigned char out_pixels[16] = {0};
  if (!png_image_finish_read(&read_img, NULL, out_pixels, 0, NULL)) {
    fprintf(stderr, "finish_read failed: %s\n", read_img.message);
    free(buf);
    return 1;
  }
  png_image_free(&read_img);
  free(buf);

  if (memcmp(pixels, out_pixels, 16) != 0) {
    fprintf(stderr, "pixel mismatch\n");
    return 1;
  }

  printf("OK\n");
  return 0;
}
