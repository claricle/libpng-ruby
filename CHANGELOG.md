# Changelog

All notable changes to the `libpng` Ruby gem are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This gem follows a `{LIBPNG_VERSION}.{LIBPNG_RUBY_ITERATION}` version
scheme. `LIBPNG_VERSION` is the upstream libpng release; `ITERATION`
bumps for Ruby-side changes and resets to 0 when LIBPNG_VERSION bumps.

## [1.6.58.6] - 2026-07-26

### Changed
- **OHOS (`aarch64-linux-ohos`) is now cross-compiled with the proper
  OpenHarmony NDK**, replacing the previous approach of shipping the
  Alpine-built musl arm64 binary under the OHOS platform label.
  The previous approach assumed byte-equivalence based solely on the
  dynamic linker path matching (`/lib/ld-musl-aarch64.so.1`) -- an
  unverified claim that ignored real ABI risks (musl patches, symbol
  visibility, TLS layout, code signing).

  The new path uses the OpenHarmony daily_build API
  (`dcp.openharmony.cn/api/daily_build/build/list/component`) to fetch
  `ohos-sdk-public` + `LLVM-19`. The OHOS NDK's clang
  (`aarch64-unknown-linux-ohos-clang`) builds libpng against the OHOS
  sysroot; the resulting `.so` is signed with OHOS's
  `binary-sign-tool -selfSign 1` (mandatory for runtime loading).
  Verified via qemu-aarch64 smoke test (round-trip encode/decode
  through libpng's simplified API).

  Reference: https://github.com/hqzing/ohos-node (build pattern).

### Added
- `ext/ohos/setup-toolchain.sh` -- downloads + extracts OHOS SDK +
  LLVM-19 + sysroot via the OpenHarmony daily_build API.
- `ext/ohos/toolchain.cmake` -- CMake cross-compile config.
- `ext/ohos/smoke-test.c` + `smoke-test.sh` -- minimal C round-trip
  test, run via qemu-aarch64 with the OHOS sysroot as
  `QEMU_LD_PREFIX`.
- New CI job `build_ohos` in `.github/workflows/build.yml` and
  `release.yml`: runs on `ubuntu-latest`, sets up the OHOS NDK,
  cross-compiles, signs the `.so`, runs the qemu smoke test.

### Fixed
- `lib/libpng/recipe.rb` `setup_cross_compile` hook is now actually
  populated for OHOS (was previously an empty "seam" comment).

### Caveats
- The 1.6.58.4 and 1.6.58.5 `aarch64-linux-ohos` gems shipped with
  Alpine-built bytes. They are superseded by 1.6.58.6's NDK build.
  The Alpine-as-OHOS approach was an unverified assumption; whether
  those binaries actually ran on OHOS hardware is unknown. If you
  installed 1.6.58.4/.5 on OHOS and it worked, this version's
  binary will differ but should be more correct. If it didn't work,
  this version fixes it.
- OHOS NDK is a moving target (daily builds). The build IDs are
  logged in CI output for traceability but not pinned.

## [1.6.58.5] - 2026-07-26

### Added
- **Write-side metadata on `encode_standard`**. Six new keyword options:
  - `text:` -- `Hash<String,String>` of tEXt/iTXt entries. Non-ASCII
    values automatically use iTXt (UTF-8) instead of tEXt (Latin-1).
  - `gamma:` -- `Float` file gamma (e.g. `0.45455` for sRGB).
  - `srgb_intent:` -- `Integer 0..3` rendering intent.
  - `chromaticities:` -- `Hash` with the 8 cHRM primaries.
  - `icc_profile:` -- `Hash` with `:name` and `:data` for an ICC
    color profile (libpng compresses internally).
  - `phys:` -- `Hash` with `:pixels_per_unit_x/y` and `:unit`
    (`0` unknown, `1` meters).
- **`pHYs` chunk read support**. `Libpng::ChunkWalker#phys_chunk`
  returns a Hash with `:pixels_per_unit_x/y`, `:unit`, and (when
  `unit==1`) computed `:dpi_x/y`. `DecodedImage#phys` is populated
  by both decode paths.
- **`Libpng.decode_standard`** -- standard libpng read API
  (`png_create_read_struct` -> `png_read_info` -> transforms ->
  `png_read_image`). Counterpart to `encode_standard`; gives
  callers explicit control over which transforms apply
  (palette-to-RGB, gray-to-RGB, alpha add/strip, 16-to-8 demotion,
  interlace handling). Returns the same `DecodedImage` shape as
  `decode`, so metadata access is uniform across both decode paths.
- New classes/modules: `Libpng::StandardDecoder`,
  `Libpng::MetadataWriter`, `Libpng::TextWriter`, `Libpng::TextEntry`.
- 27 new specs across `spec/write_metadata_spec.rb` (round-trips for
  every metadata type + validation errors) and
  `spec/standard_decoder_spec.rb` (transform coverage + Ractor safety).

### Fixed
- Internal: refactored `StandardEncoder` to delegate metadata writing
  to `MetadataWriter`. Class length back under rubocop limits.
- Corrected `FILLER_BEFORE`/`FILLER_AFTER` constant values (the code
  had them swapped -- libpng uses `BEFORE=0, AFTER=1`).

## [1.6.58.4] - 2026-07-26

### Added
- `Libpng::ChunkWalker#text_chunks` -- parses `tEXt`, `zTXt`, and `iTXt`
  chunks into a flat Hash of keyword -> UTF-8 String. zTXt values are
  zlib-inflated; tEXt/zTXt values are transcoded from Latin-1 to UTF-8;
  iTXt values stay UTF-8 (with optional compression). Malformed chunks
  are silently skipped so a single broken entry doesn't poison the rest
  of the decode.
- `Libpng::ChunkWalker#color_chunks` -- parses `gAMA`, `cHRM`, `sRGB`,
  and `iCCP` chunks into a Hash with Symbol keys (`:gamma`,
  `:white_point_x/y`, `:red_x/y`, `:green_x/y`, `:blue_x/y`,
  `:srgb_intent`, `:icc_profile_name`, `:icc_profile`). iCCP profiles
  are zlib-decompressed into raw binary bytes for downstream ICC
  libraries.
- `Libpng::DecodedImage#text` and `#color` -- new keyword Struct fields,
  populated by `Libpng.decode` via the new ChunkWalker accessors. Both
  default to an empty Hash when the source PNG has no relevant chunks.
- New platform: `aarch64-linux-ohos` (OpenHarmony / Huawei HarmonyOS PC).
  OHOS is musl-based arm64 -- the resulting shared library is
  byte-compatible with `aarch64-linux-musl`; only the gem's platform
  label differs so RubyGems on OHOS selects the right variant. Built in
  the same Alpine container as the musl gem.
- Specs: 24 new specs across `spec/text_chunk_spec.rb` and
  `spec/color_metadata_spec.rb` covering all 7 chunk types, malformed
  input handling, Ractor moving, and end-to-end metadata exposure on
  `DecodedImage`.

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
