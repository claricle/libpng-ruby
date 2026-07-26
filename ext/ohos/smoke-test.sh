#!/usr/bin/env bash
# Compiles ext/ohos/smoke-test.c against the freshly-built libpng16.so
# using the OHOS NDK clang, then runs it under qemu-aarch64 with the
# OHOS sysroot as QEMU_LD_PREFIX so the dynamic linker resolves
# against OHOS's musl libc rather than the host's.
#
# Inputs (env vars, set by setup-toolchain.sh):
#   OHOS_LLVM      -- OHOS NDK LLVM dir (clang lives in bin/)
#   OHOS_SYSROOT   -- OHOS sysroot (musl + headers)
#
# The .so under test is at lib/libpng/libpng16.so (relative to repo
# root) after `rake compile` finishes.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
SO_PATH="$REPO_ROOT/lib/libpng/libpng16.so"

if [ ! -f "$SO_PATH" ]; then
  echo "smoke-test: $SO_PATH not found; did rake compile run?" >&2
  exit 1
fi

# Use the libpng headers that ship with the source tree (under
# ports/.../include after MiniPortile cooks), or fall back to the
# host's libpng-dev if not available.
INCLUDES=(-I"$REPO_ROOT/lib/libpng")
if [ -d "$REPO_ROOT/ports/ports/libpng-$(ruby -I"$REPO_ROOT/lib" -rlibpng/version -e 'puts Libpng::LIBPNG_VERSION')/include" ]; then
  INCLUDES+=(-I"$REPO_ROOT/ports/ports/libpng-$(ruby -I"$REPO_ROOT/lib" -rlibpng/version -e 'puts Libpng::LIBPNG_VERSION')/include")
elif pkg-config --exists libpng; then
  INCLUDES+=($(pkg-config --cflags libpng))
fi

CC="${OHOS_LLVM}/bin/aarch64-unknown-linux-ohos-clang"
SYSROOT="${OHOS_SYSROOT}"

# Compile + link. rpath=$ORIGIN so the binary finds the .so next to
# it at runtime. We also pass --sysroot for the libc headers.
"$CC" \
  --sysroot="$SYSROOT" \
  "${INCLUDES[@]}" \
  -L"$REPO_ROOT/lib/libpng" \
  -Wl,-rpath=\$ORIGIN \
  -o /tmp/ohos-smoke-test \
  "$REPO_ROOT/ext/ohos/smoke-test.c" \
  -lpng16 -lz

# Copy the .so next to the binary so rpath=$ORIGIN finds it.
cp "$SO_PATH" /tmp/libpng16.so

# Run via qemu. QEMU_LD_PREFIX tells qemu where to find the dynamic
# linker (/lib/ld-musl-aarch64.so.1 inside the OHOS sysroot).
echo "Running smoke test under qemu-aarch64..."
QEMU_LD_PREFIX="$SYSROOT" qemu-aarch64 /tmp/ohos-smoke-test
