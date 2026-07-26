#!/usr/bin/env bash
# Downloads and extracts the OpenHarmony NDK on a Linux x86_64 host.
# Outputs four environment variables for subsequent build steps:
#
#   OHOS_LLVM        -- the LLVM toolchain dir (contains bin/, lib/, ...)
#   OHOS_SYSROOT     -- the OHOS sysroot (musl + system headers)
#   OHOS_SIGN_TOOL   -- binary-sign-tool used to sign the final .so
#   OHOS_NDK_ROOT    -- parent directory of everything (for reference)
#
# Both SDK and LLVM come from OpenHarmony's daily_build API at
# dcp.openharmony.cn. There's no version pinning here -- the API
# returns the latest successful build, which changes over time. The
# build ID is logged so reproducing a specific build is possible if
# needed.
#
# Reference: https://github.com/hqzing/ohos-node/blob/main/build.sh
set -euo pipefail

OHOS_NDK_ROOT="${OHOS_NDK_ROOT:-/tmp/ohos-ndk}"
mkdir -p "$OHOS_NDK_ROOT"
cd "$OHOS_NDK_ROOT"

# apt deps: curl, jq, tar, unzip. The workflow installs these; this
# script assumes they're available.
query_component() {
  local component=$1
  curl -fsSL 'https://dcp.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'"${component}"'","type":1,"startTime":"2025080100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}

# 1. OHOS SDK (provides binary-sign-tool)
SDK_URL=$(query_component "ohos-sdk-public" | jq -r '.data.list.dataList[0].obsPath')
SDK_BUILD_ID=$(query_component "ohos-sdk-public" | jq -r '.data.list.dataList[0].buildId')
echo "OHOS SDK build: $SDK_BUILD_ID ($SDK_URL)"
curl -fsSL "$SDK_URL" -o ohos-sdk-public.tar.gz
tar -zxf ohos-sdk-public.tar.gz
# Inside ohos-sdk/linux/ there's toolchains-*.zip
unzip -q -o ohos-sdk/linux/toolchains-*.zip -d ohos-sdk/linux/

# 2. LLVM-19 (compilers + sysroot)
LLVM_URL=$(query_component "LLVM-19" | jq -r '.data.list.dataList[0].obsPath')
LLVM_BUILD_ID=$(query_component "LLVM-19" | jq -r '.data.list.dataList[0].buildId')
echo "LLVM-19 build: $LLVM_BUILD_ID ($LLVM_URL)"
curl -fsSL "$LLVM_URL" -o LLVM-19.tar.gz
mkdir -p llvm-19
tar -zxf LLVM-19.tar.gz -C llvm-19
(
  cd llvm-19
  tar -zxf llvm-linux-x86_64.tar.gz
  tar -zxf ohos-sysroot.tar.gz
)

# The ohos-sysroot.tar.gz extracts to a layout like:
#   llvm-19/sysroot/aarch64-linux-ohos/{Scrt1.o,libc.so,...}
#   llvm-19/sysroot/usr/include/...
# Find Scrt1.o and back-compute the sysroot + multiarch paths from its
# location. This handles both layouts (sysroot/aarch64-linux-ohos and
# sysroot/usr/lib/aarch64-linux-ohos) without hard-coding depth.
CRT_FILE=$(find "$OHOS_NDK_ROOT/llvm-19" -name 'Scrt1.o' -path '*aarch64-linux-ohos*' 2>/dev/null | head -1)
if [ -z "$CRT_FILE" ]; then
  echo "ERROR: could not find Scrt1.o under $OHOS_NDK_ROOT/llvm-19" >&2
  echo "Layout found:" >&2
  find "$OHOS_NDK_ROOT/llvm-19" -maxdepth 4 -type d >&2
  exit 1
fi
# LIB_DIR = directory containing Scrt1.o (= the multiarch lib dir).
LIB_DIR=$(cd "$(dirname "$CRT_FILE")" && pwd)
# SYSROOT = nearest ancestor named "sysroot", else parent of the
# multiarch dir. The OHOS layout uses sysroot/aarch64-linux-ohos;
# a more conventional layout would have sysroot/usr/lib/aarch64-linux-ohos.
SYSROOT=$(cd "$LIB_DIR" && pwd)
while [ "$(basename "$SYSROOT")" != "sysroot" ] && [ "$SYSROOT" != "/" ]; do
  SYSROOT=$(dirname "$SYSROOT")
done
if [ "$SYSROOT" = "/" ]; then
  # No 'sysroot' dir found; fall back to LIB_DIR's parent.
  SYSROOT=$(dirname "$LIB_DIR")
fi
echo "Detected OHOS sysroot: $SYSROOT"
echo "Detected OHOS lib dir: $LIB_DIR"
echo "Sample files in lib dir:"
ls -la "$LIB_DIR" | head -10 >&2

# 3. Export env vars (for GitHub Actions; harmless elsewhere)
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "OHOS_NDK_ROOT=$OHOS_NDK_ROOT" >> "$GITHUB_ENV"
  echo "OHOS_LLVM=$OHOS_NDK_ROOT/llvm-19/llvm" >> "$GITHUB_ENV"
  echo "OHOS_SYSROOT=$SYSROOT" >> "$GITHUB_ENV"
  echo "OHOS_LIB_DIR=$LIB_DIR" >> "$GITHUB_ENV"
  echo "OHOS_SIGN_TOOL=$OHOS_NDK_ROOT/ohos-sdk/linux/toolchains/lib/binary-sign-tool" >> "$GITHUB_ENV"
  # Build IDs for traceability
  echo "OHOS_SDK_BUILD_ID=$SDK_BUILD_ID" >> "$GITHUB_ENV"
  echo "OHOS_LLVMBUILD_ID=$LLVM_BUILD_ID" >> "$GITHUB_ENV"
fi

echo "OHOS NDK setup complete:"
echo "  OHOS_LLVM=$OHOS_NDK_ROOT/llvm-19/llvm"
echo "  OHOS_SYSROOT=$SYSROOT"
echo "  OHOS_LIB_DIR=$LIB_DIR"
echo "  OHOS_SIGN_TOOL=$OHOS_NDK_ROOT/ohos-sdk/linux/toolchains/lib/binary-sign-tool"
