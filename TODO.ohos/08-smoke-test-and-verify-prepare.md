# 08 - Smoke-test + verify-prepare.sh (cross-compile variant)

## ext/ohos/smoke-test.c

Carried over unchanged from PR #12 (`fix/ohos-dockerharmony`).

Tests libpng's simplified API round-trip: 2x2 RGBA encode → decode → byte
comparison via `png_image_*`. Exits 0 on success, non-zero on failure.

## ext/ohos/verify-prepare.sh

Rewritten. Was Alpine-gcc-native (ran on arm64 Alpine container); now
cross-compiles via the NDK's x86_64 clang (which itself runs under binfmt
on the arm64 host).

### Old vs new

| Aspect | Old (PR #12) | New (PR #13) |
|---|---|---|
| Compiler | `gcc` (Alpine arm64) | `$NDK/llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang` (x86_64 binary, runs via binfmt on arm64 host) |
| Host runner | `ubuntu-24.04-arm` (Alpine container) | `ubuntu-24.04-arm` (host) |
| Output binary | arm64 ELF | arm64 ELF (same target, different toolchain) |
| `.so` source | Alpine-built libpng16.so | NDK-built + signed libpng16.so |

### Contract

```
Usage: verify-prepare.sh
Expects env:
  NDK_ROOT (path to ext/ohos/ndk/)

Inputs:
  lib/libpng/libpng16.so         # freshly built + signed
  lib/libpng/libpng16.so.16      # symlink (created by CMake install)
  lib/libpng/libpng16.so.16.58.0 # actual file (created by CMake install)

Outputs in $PWD/ohos-verify/:
  smoke-test        # arm64 ELF binary
  libpng16.so       # copy of freshly built .so
  libpng16.so.16    # symlink (or copy — needed by musl's SONAME lookup)
  libpng16.so.16.58.0  # actual file
  (libz.so NOT needed — zlib is statically linked into libpng16.so)
```

### Zlib for smoke-test

Since libpng16.so is built with `-DZLIB_LIBRARY=/path/to/libz.a` (static
link), `ldd libpng16.so` will NOT show a libz dependency. The smoke-test
binary only needs `libpng16.so` + libc.

This is cleaner than PR #12 (which had to bundle `libz.so` separately).

### Fixes PR #12's symlink bug

PR #12 only copied `libpng16.so` (the dev symlink), but the smoke-test
binary's NEEDED entry was `libpng16.so.16` (the SONAME).

Fix: copy all three forms (`libpng16.so`, `libpng16.so.16`, `libpng16.so.16.58.0`),
preserving symlinks. The CMake install step already creates these in
`lib/libpng/` — we just `cp -a` the whole set.

### Cross-compile invocation

```sh
$NDK_ROOT/llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang \
  -O2 \
  -I$WORK/ports/ports/libpng-1.6.58/include \
  -L$WORK/lib/libpng \
  -Wl,-rpath=\$ORIGIN \
  -o "$OUT/smoke-test" \
  "$SMOKE_SRC" \
  -lpng16 -lm -lc
```

Note: `-lz` is NOT needed because libpng16.so has zlib baked in.

The NDK clang is x86_64 ELF. On the arm64 runner with binfmt registered,
this invocation "just works" — the kernel sees x86_64 ELF and transparently
routes through qemu-x86_64.
