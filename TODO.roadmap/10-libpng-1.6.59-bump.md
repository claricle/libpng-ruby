# 10 - Libpng 1.6.59 bump when released

- **Priority**: Future
- **Status**: Planned (waiting on upstream)

## Context

The gem currently bundles libpng 1.6.58. Upstream `libpng16` branch is
at `1.6.59.git` (unreleased as of 2026-07-26). 1.6.59 will include:

- Memory safety fix: prevent double-free of `png_struct` members on
  allocation failure (`cae47455`).
- Windows/MinGW import-library symlink fix (`78ae423b`) -- doesn't
  affect us since we ship the .dll directly.
- CMake policy bump to 4.4 (`7ed557b4`).
- Various CI/license maintenance.

## Trigger

Tag `v1.6.59` on https://github.com/pnggroup/libpng.

## Approach

The release workflow already has a `bump-type=libpng` mode:

```sh
gh workflow run release.yml --repo claricle/libpng-ruby \
  --ref main \
  -f bump-type=libpng \
  -f libpng-version=1.6.59
```

This bumps `LIBPNG_VERSION = "1.6.59"` in `lib/libpng/version.rb`,
resets `LIBPNG_RUBY_ITERATION` to 0, and triggers a 1.6.59.0 release.

Manual steps before triggering:
1. Update `LIBPNG_URL` and `LIBPNG_SHA256` in `lib/libpng/recipe.rb`
   once the tarball is on sourceforge. Verify with:
   `curl -sL <URL> | shasum -a 256`
2. Smoke-test locally: `bundle exec rake compile` (downloads new
   source, builds, copies the .so/.dylib/.dll into `lib/libpng/`).
3. Run the full spec suite to catch any API regressions.

## Risks

- API surface: 1.6.59 is unlikely to add new public functions
  (the diff between 1.6.58 and 1.6.59.git shows only bug fixes and
  build improvements in `png.h`).
- Binary layout: `png_image` struct size and field offsets are
  unchanged.
- Version string: `LIBPNG_VER_STRING_C` in `lib/libpng.rb` would need
  to update to match the new binary, since `png_create_write_struct`
  checks `user_png_ver` against the compiled-in version.

## Won't do

Don't ship a `1.6.59.git`-suffixed version. The `.git` suffix in our
`{LIBPNG_VERSION}.{ITERATION}` scheme would be confusing for users.
Wait for the actual 1.6.59 release.
