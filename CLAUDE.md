# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`libpng` is a Ruby gem that wraps the official libpng shared library via FFI. The native `libpng16.{so,dylib,dll}` is **pre-compiled per target platform and shipped inside the gem** — `gem install libpng` must not require a C compiler on the host.

11 platform gems are published per release (10 native + the source `ruby` gem). Native targets: `x86_64-linux`, `x86_64-linux-musl`, `aarch64-linux`, `aarch64-linux-musl`, `aarch64-linux-ohos`, `x64-mingw32`, `x64-mingw-ucrt`, `aarch64-mingw-ucrt`, `x86_64-darwin`, `arm64-darwin`.

## Architecture

The library is split into MECE per-concern files under `lib/libpng/`,
loaded via `autoload` from `lib/libpng.rb`. **Never use `require_relative`
(or `require` with a path) for internal library code** — add an
`autoload` entry to `lib/libpng.rb` instead.

| File | Responsibility |
|---|---|
| `lib/libpng.rb` | Module + FFI setup + constants + public dispatch (`encode`/`decode`/`encode_standard`) + autoloads |
| `lib/libpng/version.rb` | `LIBPNG_VERSION`, `LIBPNG_RUBY_ITERATION`, `VERSION` |
| `lib/libpng/error.rb` | `Libpng::Error` |
| `lib/libpng/decoded_image.rb` | `Libpng::DecodedImage` (Struct returned by `decode` / `decode_standard`) |
| `lib/libpng/chunk_walker.rb` | `Libpng::ChunkWalker` (walk/strip/extract metadata: `#each_chunk`, `#ihdr_fields`, `#text_chunks` for tEXt/zTXt/iTXt, `#color_chunks` for gAMA/cHRM/sRGB/iCCP, `#phys_chunk` for pHYs, `#strip_ancillary`) |
| `lib/libpng/bytes_per_pixel.rb` | `Libpng::BytesPerPixel` (pure-data lookup) |
| `lib/libpng/simplified_encoder.rb` | `Libpng::SimplifiedEncoder` (libpng simplified write API) |
| `lib/libpng/simplified_decoder.rb` | `Libpng::SimplifiedDecoder` (libpng simplified read API + metadata via ChunkWalker) |
| `lib/libpng/standard_encoder.rb` | `Libpng::StandardEncoder` (libpng standard write API; filter/compression/interlace/bit_depth/palette + metadata via MetadataWriter) |
| `lib/libpng/standard_decoder.rb` | `Libpng::StandardDecoder` (libpng standard read API; explicit transform control) |
| `lib/libpng/metadata_writer.rb` | `Libpng::MetadataWriter` (validates + writes text/gAMA/sRGB/cHRM/iCCP/pHYs onto a png_ptr/info_ptr pair) |
| `lib/libpng/text_writer.rb` | `Libpng::TextWriter` + `Libpng::TextEntry` (builds png_text struct array, calls `png_set_text`) |
| `lib/libpng/recipe.rb` | `Libpng::Recipe < MiniPortileCMake` (builds libpng from source for the source gem). Has `.for_target(platform)` factory -- OCP seam that returns `OHOS::Recipe` for `*-ohos`, base `Recipe` otherwise |
| `lib/libpng/ohos.rb` | `Libpng::OHOS` namespace + autoloads. Lazy-loaded only when `Recipe.for_target` is called with an OHOS target |
| `lib/libpng/ohos/ndk.rb` | `OHOS::NDK` -- pure-data class for NDK path discovery (toolchain/sysroot/clang/sign-tool). Idempotent `#download` via `setup-ndk.sh` |
| `lib/libpng/ohos/zlib_builder.rb` | `OHOS::ZlibBuilder < MiniPortileCMake` -- builds `libz.a` statically with the OHOS toolchain |
| `lib/libpng/ohos/code_signer.rb` | `OHOS::CodeSigner` -- wraps `binary-sign-tool sign -selfSign 1`. Pure-data `#sign_command` is testable without invoking the tool |
| `lib/libpng/ohos/recipe.rb` | `OHOS::Recipe < Libpng::Recipe` -- orchestrates NDK setup, zlib build, libpng cross-compile with `ohos.toolchain.cmake`, and post-install signing |
| `ext/extconf.rb` | Gem extension entry. Calls `Libpng::Recipe.for_target(ENV['target_platform']).new`, then emits a dummy Makefile |
| `ext/ohos/setup-ndk.sh` | Downloads OHOS SDK + LLVM-19 via OpenHarmony daily_build API (adapted from ohos-node/build.sh). Idempotent |
| `ext/ohos/smoke-test.c` | Minimal libpng round-trip test, cross-compiled with NDK clang and run inside dockerharmony |
| `ext/ohos/verify-prepare.sh` | Cross-compiles smoke-test, bundles signed `.so` + SONAME symlinks for dockerharmony |

### Public API

```ruby
Libpng.encode(width, height, pixels, pixel_format:, convert_to_8bit:, strip_colorspace:)
Libpng.encode_standard(width, height, pixels, pixel_format:, filter:, compression_level:, interlace:, bit_depth:, palette:, **metadata)
Libpng.decode(png, pixel_format:)
Libpng.decode_standard(png, pixel_format:, bit_depth:)
Libpng.decode(png, pixel_format:)
```

Each is a thin dispatcher that constructs a dedicated encoder/decoder instance and calls `#call`. The instance is discarded after the call (per-call state, Ractor-safe).

### FFI binding

`Libpng` extends `FFI::Library` and attaches:
- 4 simplified-API functions (`png_image_*`)
- 10 standard-API functions (`png_create_write_struct`, `png_set_IHDR`, `png_set_PLTE`, `png_set_tRNS`, `png_set_filter`, `png_set_compression_level`, `png_set_write_fn`, `png_write_png`, `png_set_rows`, `png_destroy_write_struct`, `png_create_info_struct`)

FFI calls inside encoder classes use the qualified form: `Libpng.png_set_IHDR(...)`. The function table is set up once at module load and is shareable across Ractors.

### Ractor safety

Every encoder/decoder allocates its own `png_image` (simplified API) or `png_struct` (standard API) per call. No shared mutable state on the Ruby side. The Ractor specs in `spec/ractor_spec.rb` and `spec/ractor_standard_spec.rb` verify this across Ruby 3.3, 3.4, and 4.0.

Ruby 4.0 removed `Ractor#take`; use the helper `ractor_result(r)` which prefers `#value` (4.0+) and falls back to `#take` (3.x).

## Common commands

```sh
bundle install
bundle exec rake compile         # build libpng via MiniPortile (needs cmake + zlib)
bundle exec rake spec            # all specs (~132 examples)
bundle exec rspec spec/libpng_spec.rb:17   # single spec by line
bundle exec rake rubocop
bundle exec rake                 # default: spec + rubocop

bundle exec rake gem:native:arm64-darwin    # build a pre-compiled gem
bundle exec rake gem:native:any             # source gem (compiles on install)
```

Platform gem tasks: `x64-mingw32`, `x64-mingw-ucrt`, `aarch64-mingw-ucrt`, `x86_64-linux`, `x86_64-linux-musl`, `aarch64-linux`, `aarch64-linux-musl`, `aarch64-linux-ohos`, `x86_64-darwin`, `arm64-darwin`.

### OHOS (`aarch64-linux-ohos`) build notes

OHOS uses a dedicated `build_ohos` CI job (see `.github/workflows/build.yml`)
that runs on `ubuntu-24.04-arm`. The NDK's clang and `binary-sign-tool` are
x86_64 ELF and run via `binfmt_misc` + `qemu-user-static`. The job:

1. Downloads OHOS SDK + LLVM-19 via `ext/ohos/setup-ndk.sh` (~1.5 GB, cached
   across runs by `actions/cache@v4`).
2. Runs `rake gem:native:aarch64-linux-ohos`, which delegates to
   `Libpng::OHOS::Recipe` (sets up NDK, builds static zlib, cross-compiles
   libpng with `ohos.toolchain.cmake`, signs the `.so`).
3. Cross-compiles `ext/ohos/smoke-test.c` with NDK clang via
   `verify-prepare.sh`, then runs it inside the `dockerharmony` container
   (real OHOS userland) — build fails if smoke-test doesn't output `OK`.

Local dev: `target_platform=aarch64-linux-ohos bundle exec rake compile`
will only succeed on an arm64 host with `qemu-user-static` registered,
because the NDK clang is x86_64 ELF. CI handles this automatically.

## Release process

Releases are tag-triggered via `.github/workflows/release.yml`. Trigger with:

```sh
gh workflow run release.yml --repo claricle/libpng-ruby --ref main -f bump-type=iteration
# or: -f bump-type=libpng -f libpng-version=1.6.59
# or: -f bump-type=current  # release current VERSION as-is
```

The workflow bumps `lib/libpng/version.rb`, pushes a `v*` tag, builds all 11 platform gems (10 native + the source `ruby` gem), and publishes to RubyGems via OIDC Trusted Publishing.

**Never** push tags or merge to main directly — always go through PRs.

## Code quality rules (project-wide)

- **Never** `require_relative` for internal library code — use `autoload`.
- **Never** `send` to call private methods. Redesign the API boundary instead.
- **Never** `instance_variable_set`/`get` across objects.
- **Never** `respond_to?` for type checks — use `is_a?` or design the type hierarchy so the check isn't needed.
- **DRY / MECE / OCP**: each concern lives in exactly one file. New pixel format = add to `FORMAT_BY_NAME` + `COLOR_TYPE_BY_FORMAT` + `BytesPerPixel` (and `FORMAT_TO_COLOR_TYPE` if standard-API).

## Specs

- `spec/libpng_spec.rb` — `encode`/`decode` simplified API
- `spec/libpng_standard_spec.rb` — `encode_standard` core
- `spec/standard_encoder_options_spec.rb` — `interlace:`/`bit_depth:`/`palette:` options
- `spec/write_metadata_spec.rb` — text/gAMA/sRGB/cHRM/pHYs write round-trips + validation
- `spec/decoded_image_metadata_spec.rb` — IHDR metadata + `ChunkWalker`
- `spec/text_chunk_spec.rb` — tEXt/zTXt/iTXt parsing (read side)
- `spec/color_metadata_spec.rb` — gAMA/cHRM/sRGB/iCCP parsing (read side)
- `spec/standard_decoder_spec.rb` — `decode_standard` transforms + Ractor safety
- `spec/malformed_input_spec.rb` — corrupt PNG input handling
- `spec/ractor_spec.rb` — Ractor safety for simplified API
- `spec/ractor_standard_spec.rb` — Ractor safety for standard write API
- `spec/benchmark_spec.rb` — encode/decode timing comparison

## See also

- `CHANGELOG.md` — release history
- `REPORT-complex-api-needs.md` — historical report that drove `encode_standard`
