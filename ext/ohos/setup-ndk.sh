#!/bin/sh
# Downloads the OHOS NDK (ohos-sdk-public + LLVM-19) into a prefix dir.
# Idempotent: skips if the destination already has the critical files.
#
# Adapted from https://github.com/hqzing/ohos-node/blob/main/build.sh
#
# The OHOS NDK clang is an x86_64-linux binary. On an arm64 host this
# script still produces the right output (the files are placed at the
# expected paths); running the NDK binaries later requires binfmt_misc
# + qemu-user-static, registered separately in CI.
#
# Usage:
#   ./setup-ndk.sh [--prefix <dir>]
# Default prefix: $PWD/ext/ohos/ndk
set -e

PREFIX="$PWD/ext/ohos/ndk"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    *) echo "setup-ndk: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve to absolute path. Relative paths break `ln -s` below: symlink
# targets are interpreted relative to the SYMLINK's location, not the
# script's cwd. A relative $PREFIX would create a dangling symlink.
mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

SDK_DIR="$PREFIX/ohos-sdk/linux"
LLVM_DIR="$PREFIX/llvm-19/llvm"
SYSROOT_DIR="$PREFIX/llvm-19/sysroot"

# Critical-path checks. If all four exist, declare victory.
if [ -f "$SDK_DIR/toolchains/lib/binary-sign-tool" ] \
  && [ -f "$SDK_DIR/build/cmake/ohos.toolchain.cmake" ] \
  && [ -f "$LLVM_DIR/bin/aarch64-unknown-linux-ohos-clang" ] \
  && [ -d "$SYSROOT_DIR/usr/lib/aarch64-linux-ohos" ]; then
  echo "setup-ndk: NDK already present at $PREFIX"
  exit 0
fi

command -v curl >/dev/null || { echo "setup-ndk: curl required" >&2; exit 1; }
command -v jq   >/dev/null || { echo "setup-ndk: jq required" >&2; exit 1; }
command -v tar  >/dev/null || { echo "setup-ndk: tar required" >&2; exit 1; }
command -v unzip >/dev/null || { echo "setup-ndk: unzip required" >&2; exit 1; }

mkdir -p "$PREFIX"
TMP=$(mktemp -d "$PREFIX/.setup-ndk.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

query_component() {
  component=$1
  curl --retry 5 --retry-delay 5 --retry-all-errors -fsSL \
    'https://dcp.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'"${component}"'","type":1,"startTime":"2025080100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}

# Curl download helper with retries (the OHOS CDN sometimes resets connections).
dl() {
  curl --retry 5 --retry-delay 10 --retry-all-errors -fL "$1" -o "$2"
}

echo "setup-ndk: querying daily_build API for ohos-sdk-public..."
sdk_url=$(query_component "ohos-sdk-public" | jq -r '.data.list.dataList[0].obsPath')
[ -n "$sdk_url" ] || { echo "setup-ndk: failed to resolve sdk URL" >&2; exit 1; }
echo "setup-ndk: downloading $sdk_url"
dl "$sdk_url" "$TMP/ohos-sdk-public.tar.gz"
# The SDK tarball already contains ohos-sdk/{linux,windows,ohos}/ at the
# top level. Extract straight into $PREFIX so $PREFIX/ohos-sdk/linux/ ends
# up at the expected path (extracting into $PREFIX/ohos-sdk would create
# $PREFIX/ohos-sdk/ohos-sdk/linux/ -- which broke CI run 1).
tar -zxf "$TMP/ohos-sdk-public.tar.gz" -C "$PREFIX"
# Drop non-linux variants to keep the cache small.
rm -rf "$PREFIX/ohos-sdk/windows" "$PREFIX/ohos-sdk/ohos" 2>/dev/null || true
cd "$PREFIX/ohos-sdk/linux"
# The SDK ships multiple zips: toolchains-*.zip (binary-sign-tool etc.)
# and native-*.zip (ohos.toolchain.cmake, build-tools/cmake). Unzip them
# all so the NDK class can find both toolchains/lib/binary-sign-tool and
# native/build/cmake/ohos.toolchain.cmake.
for z in *.zip; do
  [ -e "$z" ] || continue
  unzip -q "$z"
  rm -f "$z"
done
cd -

echo "setup-ndk: querying daily_build API for LLVM-19..."
llvm_url=$(query_component "LLVM-19" | jq -r '.data.list.dataList[0].obsPath')
[ -n "$llvm_url" ] || { echo "setup-ndk: failed to resolve LLVM-19 URL" >&2; exit 1; }
echo "setup-ndk: downloading $llvm_url"
dl "$llvm_url" "$TMP/LLVM-19.tar.gz"
# LLVM-19 tarball extracts to ./llvm-linux-x86_64.tar.gz + ./ohos-sysroot.tar.gz
# at the top level. Extract straight into $PREFIX/llvm-19/ so the inner
# tarballs land where the next step expects them.
mkdir -p "$PREFIX/llvm-19"
tar -zxf "$TMP/LLVM-19.tar.gz" -C "$PREFIX/llvm-19"
cd "$PREFIX/llvm-19"
tar -zxf llvm-linux-x86_64.tar.gz
rm -rf llvm-linux-x86_64.tar.gz
# ohos-sysroot.tar.gz already contains sysroot/ at the top level (per
# ohos-node/build.sh). Extract directly into $PREFIX/llvm-19/ -- NOT into
# $PREFIX/llvm-19/sysroot/ (that would create a nested sysroot/sysroot/
# and break the SDK-sysroot symlink below).
tar -zxf ohos-sysroot.tar.gz
rm -rf ohos-sysroot.tar.gz
cd -

echo "setup-ndk: NDK ready at $PREFIX"
# The OHOS toolchain (ohos.toolchain.cmake) resolves CMAKE_SYSROOT relative
# to its own location: ohos-sdk/linux/native/sysroot/. That sysroot uses the
# MULTIARCH layout (usr/include/aarch64-linux-ohos/bits/...), but the
# toolchain expects the PER-ARCH layout (sysroot/usr/include/bits/...).
#
# The LLVM-19 tarball ships per-arch sysroots at llvm-19/sysroot/<arch>/.
# Symlink the SDK's multiarch sysroot to the per-arch aarch64 sysroot so
# the toolchain finds bits/alltypes.h and friends at the expected paths.
ARCH_SYSROOT="$PREFIX/llvm-19/sysroot/aarch64-linux-ohos"
if [ -d "$ARCH_SYSROOT/usr/include" ] && [ -d "$PREFIX/ohos-sdk/linux/native/sysroot" ]; then
  rm -rf "$PREFIX/ohos-sdk/linux/native/sysroot"
  ln -s "$ARCH_SYSROOT" "$PREFIX/ohos-sdk/linux/native/sysroot"
else
  echo "setup-ndk: WARNING - $ARCH_SYSROOT missing; SDK sysroot will be incomplete"
fi
echo "setup-ndk: locating critical files..."
find "$PREFIX" -maxdepth 9 \( -name 'ohos.toolchain.cmake' -o -name 'binary-sign-tool' -o -name 'aarch64-unknown-linux-ohos-clang' -o -name 'alltypes.h' \) -print | head -20
echo "setup-ndk: SDK sysroot is symlink to:"
readlink "$PREFIX/ohos-sdk/linux/native/sysroot" 2>&1 || echo "(not a symlink)"
echo "setup-ndk: SDK sysroot/usr/lib/ contents:"
ls "$PREFIX/ohos-sdk/linux/native/sysroot/usr/lib" 2>&1 | head -10
