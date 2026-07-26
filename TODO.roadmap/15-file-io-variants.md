# 15 - File I/O variants

- **Priority**: Skip
- **Status**: Won't do

## Context

libpng exposes file-based I/O via `png_init_io(FILE*)`, plus the
simplified API has `png_image_begin_read_from_file` /
`png_image_write_to_file`. We currently only use the memory-based
variants (`_from_memory`, `_to_memory`, `png_set_write_fn` with
in-memory callback).

## Why we won't do this

1. **`FILE*` lifetime is awkward across FFI**: A Ruby `File` object
   wraps a `FILE*`. Passing it to libpng via FFI requires either:
   - Reaching into Ruby's internal struct layout (fragile, version-
     dependent)
   - Opening a separate `FILE*` via `fopen(3)` and managing its
     lifetime manually (error-prone)

2. **Memory-stream output is the right default**: It avoids disk I/O
   entirely, lets callers decide where to persist (or not), and works
   identically across all 10 platforms.

3. **Ruby already has good file I/O**:
   ```ruby
   png = Libpng.encode(width, height, pixels, pixel_format: "RGBA")
   File.binwrite("out.png", png)
   ```
   is idiomatic Ruby. Adding `Libpng.encode_to_file` would be a
   duplicate API for marginal benefit.

4. **Simplified API file variants are POSIX-only**:
   `png_image_begin_read_from_file` takes a `const char *filename`,
   which doesn't handle Windows wide-char paths cleanly. The memory
   variants sidestep this entirely.

## When this position might change

- A user with truly huge images (multi-GB) where holding the encoded
  PNG in memory before writing to disk is wasteful.
- A performance benchmark showing `File.binwrite` is a real bottleneck
  (unlikely -- disk I/O is fast and `File.binwrite` uses `write(2)`
  directly).

## Alternative under consideration

If streaming-to-file becomes important, the right design is:
```ruby
Libpng.encode_standard(width, height, pixels, output: io_object)
```
where `io_object` is anything responding to `#<<` (String, File,
StringIO, etc.). The internal FFI write callback would call
`io_object << data.read_bytes(len)`. This is more flexible than a
file-only variant and requires no new libpng functions.
