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
  curl -fsSL 'https://dcp.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'"${component}"'","type":1,"startTime":"2025080100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}

echo "setup-ndk: querying daily_build API for ohos-sdk-public..."
sdk_url=$(query_component "ohos-sdk-public" | jq -r '.data.list.dataList[0].obsPath')
[ -n "$sdk_url" ] || { echo "setup-ndk: failed to resolve sdk URL" >&2; exit 1; }
echo "setup-ndk: downloading $sdk_url"
curl -fL "$sdk_url" -o "$TMP/ohos-sdk-public.tar.gz"
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
curl -fL "$llvm_url" -o "$TMP/LLVM-19.tar.gz"
# LLVM-19 tarball extracts to ./llvm-linux-x86_64.tar.gz + ./ohos-sysroot.tar.gz
# at the top level. Extract straight into $PREFIX/llvm-19/ so the inner
# tarballs land where the next step expects them.
mkdir -p "$PREFIX/llvm-19"
tar -zxf "$TMP/LLVM-19.tar.gz" -C "$PREFIX/llvm-19"
cd "$PREFIX/llvm-19"
tar -zxf llvm-linux-x86_64.tar.gz
rm -rf llvm-linux-x86_64.tar.gz
mkdir -p sysroot
tar -zxf ohos-sysroot.tar.gz -C sysroot
rm -rf ohos-sysroot.tar.gz
cd -

echo "setup-ndk: NDK ready at $PREFIX"
echo "setup-ndk: locating critical files..."
find "$PREFIX" -maxdepth 8 \( -name 'ohos.toolchain.cmake' -o -name 'binary-sign-tool' -o -name 'aarch64-unknown-linux-ohos-clang' -o -name '*.cmake' \) -print | head -30
echo "setup-ndk: ohos-sdk/linux/ listing:"
ls "$PREFIX/ohos-sdk/linux" 2>&1 || true
echo "setup-ndk: any 'native' dir?"
find "$PREFIX/ohos-sdk" -type d -name native 2>&1 | head -5
