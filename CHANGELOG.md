# Changelog

All notable changes to the `libpng` Ruby gem are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This gem follows a `{LIBPNG_VERSION}.{LIBPNG_RUBY_ITERATION}` version
scheme. `LIBPNG_VERSION` is the upstream libpng release; `ITERATION`
bumps for Ruby-side changes and resets to 0 when LIBPNG_VERSION bumps.

## [1.6.58.3] - 2026-07-26

### Added
- `Libpng.encode_standard` -- standard libpng write API
  (`png_create_write_struct` -> `png_set_IHDR` -> `png_set_rows` ->
  `png_write_png(PNG_TRANSFORM_IDENTITY)`). Mirrors libemf2svg's
  `rgb2png` byte layout and emits only IHDR/IDAT/IEND directly (no
  post-hoc chunk stripping).
- `interlace:` option on `encode_standard` -- `:none` (default) or
  `:adam7`.
- `bit_depth:` option on `encode_standard` -- 8 (default) or 16 for
  RGB/RGBA/GRAY.
- `pixel_format: :palette` with `palette:` option on `encode_standard` --
  emits PNG_COLOR_TYPE_PALETTE via `png_set_PLTE` (and `png_set_tRNS`
  when any palette entry has alpha).
- `Libpng::DecodedImage#bit_depth`, `#color_type`, `#interlace` -- IHDR
  metadata fields populated by walking the source PNG after decode.
- `Libpng::ChunkWalker` -- public class for walking PNG chunks:
  `#each_chunk`, `#strip_ancillary`, `#ihdr_fields`.
- `Libpng::BytesPerPixel` -- pure-data helper module mapping formats
  and color types to bytes-per-pixel (8- and 16-bit aware).
- Architecture refactor: split the monolithic `lib/libpng.rb` (466
  lines) into MECE per-concern files using Ruby `autoload`. New files:
  `lib/libpng/error.rb`, `decoded_image.rb`, `chunk_walker.rb`,
  `bytes_per_pixel.rb`, `simplified_encoder.rb`,
  `simplified_decoder.rb`, `standard_encoder.rb`. Public API
  unchanged.
- Specs: malformed-input suite, encode_standard Ractor suite,
  benchmark suite, options suite for interlace/bit_depth/palette,
  metadata suite for DecodedImage + ChunkWalker.

### Changed
- `mini_portile2` dependency bumped from `~> 2.6` to `~> 2.8`.
- Removed all `require_relative` from library code in favor of
  `autoload` (per project code-quality rules).
- `ext/extconf.rb` now triggers `Libpng::Recipe` autoload via
  `require 'libpng'` instead of reaching into `lib/libpng/recipe.rb`
  directly.

### Fixed
- Filter option documentation: clarified that `:default`, `:adaptive`,
  and `:all` produce byte-identical output but exercise different
  libpng code paths. `:none` forces no filtering.
- Removed redundant `.dup.freeze` on `LIBPNG_VER_STRING_C` (the source
  string is already a frozen literal).

## [1.6.58.2] - 2026-07-26

### Added
- `Libpng.encode_standard` initial release -- standard libpng write
  API with memory-stream output via `png_set_write_fn` FFI callback
  (no Tempfile), filter control, compression level control, and error
  handling via `png_set_error_fn` callback.
- Specs: 32 specs covering encode_standard round-trips, filter
  variants, compression levels, chunk-layout assertions, parity check
  against simplified `encode`.

## [1.6.58.1] - 2026-07-25

### Added
- Full platform coverage: `aarch64-linux-musl`, `aarch64-linux` (native
  on `ubuntu-24.04-arm`), `aarch64-mingw-ucrt` (native on
  `windows-11-arm`), `x86_64-linux-musl` (Alpine via `docker run`).
- `step-security/msvc-dev-cmd@v1` replaces deleted `ilammy/msvc-dev-tools`
  action.
- Release workflow tolerates already-published gems (skip-on-conflict).
- Specs: Ractor safety suite for `encode` and `decode` (Ruby 3.x and 4.0).

### Fixed
- `ext/extconf.rb` now emits a dummy Makefile so RubyGems is satisfied
  when installing the source (`ruby` platform) gem.
- Recipe globs `{bin,lib}/libpng16*.dll` on Windows (CMake's
  GNUInstallDirs puts the .dll in `bin/`, not `lib/`).
- Alpine build runs inside `docker run` (not the `container:` field)
  so it works on arm64 Ubuntu runners.
- `git config --global --add safe.directory /work` in Alpine container
  so `git ls-files` works for the gemspec.

## [1.6.58.0] - 2026-07-25

### Added
- Initial pre-compiled libpng gem. Bundles libpng 1.6.58 shared
  libraries for x86_64 Linux, x86_64 macOS, arm64 macOS, x64 Windows
  (MSVCRT and UCRT).
- `Libpng.encode` / `Libpng.decode` -- simplified API binding via FFI.
- `strip_colorspace:` option on `encode` to drop sRGB/gAMA chunks the
  simplified API emits by default.
- `convert_to_8bit:` option on `encode` for 16-bit input.
- MiniPortile-based recipe for building libpng from source when
  installing the platform-agnostic `ruby` gem.
