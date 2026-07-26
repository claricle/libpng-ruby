#!/bin/sh
# Compiles ext/ohos/smoke-test.c against the freshly-built libpng16.so
# using the NDK clang (aarch64-unknown-linux-ohos target), and bundles
# the result + the .so + its SONAME symlinks into ohos-verify/ for
# dockerharmony to consume.
#
# Unlike the PR #12 variant of this script (which used Alpine gcc on a
# native arm64 host), this version cross-compiles via the NDK clang.
# The clang binary itself is x86_64 ELF; it runs on the arm64 host via
# transparent binfmt_misc + qemu-user-static registration (set up in CI).
#
# Zlib is NOT bundled because libpng16.so has it baked in (built with
# -DZLIB_LIBRARY=<static libz.a> in OHOS::ZlibBuilder).
set -e

WORK="${WORK:-$(pwd)}"
NDK_ROOT="${NDK_ROOT:-$WORK/ext/ohos/ndk}"
SO_DIR="$WORK/lib/libpng"
SMOKE_SRC="$WORK/ext/ohos/smoke-test.c"
CLANG="$NDK_ROOT/llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang"

if [ ! -f "$CLANG" ]; then
  echo "verify-prepare: $CLANG not found; did setup-ndk.sh run?" >&2
  exit 1
fi

# libpng headers shipped with the source tree under ports/.
LIBPNG_VERSION=$(ruby -I"$WORK/lib" -rlibpng/version -e 'puts Libpng::LIBPNG_VERSION')
INCLUDES="-I$WORK/ports/ports/libpng-${LIBPNG_VERSION}/include"
if [ ! -d "$WORK/ports/ports/libpng-${LIBPNG_VERSION}/include" ]; then
  echo "verify-prepare: libpng headers not found at ports/, cannot continue" >&2
  exit 1
fi

OUT="$WORK/ohos-verify"
mkdir -p "$OUT"

# Cross-compile the smoke-test. rpath=$ORIGIN lets the binary find the
# .so in its own dir at runtime. -lz is intentionally omitted because
# libpng16.so has zlib statically linked.
"$CLANG" -O2 $INCLUDES \
  -L"$SO_DIR" \
  -Wl,-rpath=\$ORIGIN \
  -o "$OUT/smoke-test" \
  "$SMOKE_SRC" \
  -lpng16 -lm

# Copy all three .so forms so musl's SONAME lookup resolves regardless
# of how the dynamic linker asks for it. PR #12 only copied the
# unversioned dev symlink, which broke dockerharmony (binary's NEEDED
# entry is libpng16.so.16). cp -a preserves the symlink -> real-file
# relationship.
cp -a "$SO_DIR/libpng16.so" "$SO_DIR/libpng16.so.16" "$SO_DIR/libpng16.so.16.58.0" "$OUT/"

echo "verify-prepare: artifacts in $OUT"
ls -la "$OUT"
