#!/bin/sh
# Verifies that an Alpine-built libpng16.so actually loads and
# round-trips in the dockerharmony container (real OHOS userland).
#
# Runs inside the Alpine container as a continuation of the regular
# aarch64-linux-ohos build. Steps:
#   1. Compile ext/ohos/smoke-test.c against the freshly-built .so
#      (using Alpine's gcc, since both produce aarch64-linux-musl
#      binaries that run in dockerharmony).
#   2. Bundle the .so + smoke binary + libz.so into a tarball that
#      dockerharmony can run.
#
# The dockerharmony run itself happens in the workflow YAML (host
# side), not here -- this script just produces the artifacts.
set -e

WORK="${WORK:-$(pwd)}"
SO_PATH="$WORK/lib/libpng/libpng16.so"
SMOKE_SRC="$WORK/ext/ohos/smoke-test.c"

if [ ! -f "$SO_PATH" ]; then
  echo "verify-prepare: $SO_PATH not found; did rake compile run?" >&2
  exit 1
fi

# libpng headers shipped with the source tree (mini_portile installed
# them under ports/...). Fallback to system libpng-dev headers if not.
LIBPNG_VERSION=$(ruby -I"$WORK/lib" -rlibpng/version -e 'puts Libpng::LIBPNG_VERSION')
INCLUDES="-I$WORK/ports/ports/libpng-${LIBPNG_VERSION}/include"
if [ ! -d "$WORK/ports/ports/libpng-${LIBPNG_VERSION}/include" ]; then
  INCLUDES=""  # rely on libpng-dev installed via apk
fi

# Output dir on the host (mounted volume).
OUT="/work/ohos-verify"
mkdir -p "$OUT"

# Compile the smoke test. -Wl,-rpath=$ORIGIN means the binary finds
# the .so in its own dir at runtime. We also link zlib statically
# where possible (dockerharmony may not have libz.so).
gcc -O2 $INCLUDES \
  -L"$WORK/lib/libpng" \
  -Wl,-rpath=\$ORIGIN \
  -o "$OUT/smoke-test" \
  "$SMOKE_SRC" \
  -lpng16 -lz -lm

# Copy the .so next to the smoke binary so rpath=$ORIGIN resolves.
cp "$SO_PATH" "$OUT/libpng16.so"

# Also copy libz.so in case dockerharmony doesn't ship it.
LIBZ_PATH=$(ldd "$SO_PATH" | grep 'libz\.so' | awk '{print $3}')
if [ -n "$LIBZ_PATH" ] && [ -f "$LIBZ_PATH" ]; then
  cp "$LIBZ_PATH" "$OUT/libz.so"
fi

echo "verify-prepare: artifacts in $OUT"
ls -la "$OUT"
