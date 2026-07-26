# 05 - lib/libpng/ohos/zlib_builder.rb

## Purpose

Build zlib as a static library (`libz.a`) using the OHOS NDK toolchain. The
resulting `.a` is linked into `libpng16.so` so the OHOS gem doesn't need
`libshared_libz.z.so` (OHOS's non-standard zlib SONAME) at runtime.

## Why static

- OHOS sysroot ships zlib as `libshared_libz.z.so` (per dockerharmony's
  `build-rootfs.sh` line 54 — patchelf renames `libz.so.1` to this).
- libpng's CMake `find_package(ZLIB)` expects `libz.so` — won't find OHOS's variant.
- Static linking avoids the whole problem: zlib is baked into `libpng16.so`.

## Class

```ruby
class ZlibBuilder < MiniPortileCMake
  ZLIB_VERSION = '1.3.1'
  ZLIB_URL = "https://zlib.net/fossils/zlib-#{ZLIB_VERSION}.tar.gz"
  ZLIB_SHA256 = '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4587b3e70eb117e57..."

  def initialize(ndk:)
    super('zlib', ZLIB_VERSION)
    @files << { url: ZLIB_URL, sha256: ZLIB_SHA256 }
    @ndk = ndk
  end

  def configure_defaults
    super + [
      "-DCMAKE_TOOLCHAIN_FILE=#{@ndk.toolchain_path}",
      "-DOHOS_ARCH=#{OHOS::OHOS_ARCH}",
      "-DOHOS_PLATFORM=OHOS",
      '-DBUILD_SHARED_LIBS=OFF',
      '-DCMAKE_INSTALL_LIBDIR=lib'
    ]
  end

  def libz_path
    Pathname.new(port_path).join('lib', 'libz.a')
  end

  def include_path
    Pathname.new(port_path).join('include')
  end
end
```

## Design notes

- Inherits from `MiniPortileCMake` — gets download/extract/compile/install for free.
- `@ndk` is the only state; toolchain paths come from there.
- `#libz_path` / `#include_path` are pure data — used by `OHOS::Recipe` to wire
  up `-DZLIB_LIBRARY=... -DZLIB_INCLUDE_DIR=...` for libpng's CMake.
- Version pinning (URL + sha256) follows the same pattern as `Libpng::Recipe`.

## Testability

Spec verifies:
- `configure_defaults` includes the OHOS toolchain file flag.
- `libz_path` ends in `lib/libz.a`.
- `ZLIB_URL` matches the pinned version.

No actual build in specs (would require NDK).
