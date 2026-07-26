/* Minimal libpng round-trip test for cross-compiled OHOS binaries.
 * Built with the OHOS NDK clang and run via qemu-aarch64 -L $SYSROOT
 * to verify the .so loads and the simplified API works correctly.
 *
 * We can't run Ruby here (no Ruby port for OHOS), but we can verify
 * that libpng's API surface behaves -- which is what the gem's FFI
 * bindings exercise.
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

  /* Encode */
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

  /* Decode */
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

  /* Verify */
  if (memcmp(pixels, out_pixels, 16) != 0) {
    fprintf(stderr, "pixel mismatch:\n  in : ");
    for (i = 0; i < 16; i++) fprintf(stderr, "%02x ", pixels[i]);
    fprintf(stderr, "\n  out: ");
    for (i = 0; i < 16; i++) fprintf(stderr, "%02x ", out_pixels[i]);
    fprintf(stderr, "\n");
    return 1;
  }

  printf("OK\n");
  return 0;
}
